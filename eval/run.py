"""Evaluate the app's word flags. All downloaded data stays inside eval/."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import random
import shlex
import subprocess
import sys
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import uuid
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
DATA = HERE / "data"
CACHE = HERE / ".cache"
DATASET = "mispeech/speechocean762"
SPLIT = "test"
DATASET_SIZE = 2500
SEED = 762
PACIFIC = ZoneInfo("America/Los_Angeles")
PARAMS = {
    "model_id": "scribe_v2",
    "language_code": "en",
    "timestamps_granularity": "word",
    "no_verbatim": "false",
    "tag_audio_events": "false",
    "diarize": "false",
    "temperature": "0",
    "seed": str(SEED),
}


def digest(value) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")
    temporary.replace(path)


def read_json(path: Path):
    return json.loads(path.read_text())


def request_bytes(request: Request, service: str) -> tuple[bytes, dict]:
    """Do not print URLs, response bodies, or credentials in error messages."""
    for attempt in range(5):
        delay = min(2 ** attempt + random.random(), 30)
        try:
            with urlopen(request, timeout=90) as response:
                return response.read(), dict(response.headers)
        except HTTPError as error:
            retryable = error.code in (408, 429) or 500 <= error.code <= 599
            if not retryable or attempt == 4:
                raise RuntimeError(f"{service}: HTTP {error.code}; request failed.") from None
            retry_after = error.headers.get("Retry-After", "")
            if retry_after.isdigit():
                delay = max(delay, min(float(retry_after), 60))
        except (URLError, TimeoutError, ConnectionError):
            if attempt == 4:
                raise RuntimeError(f"{service}: network request failed after retries.") from None
        print(f"{service}: retry {attempt + 1}/4 in {delay:.1f}s", flush=True)
        time.sleep(delay)
    raise RuntimeError(f"{service}: retry limit reached.")


def fetch_rows(offset: int, length: int = 100) -> tuple[list[dict], str]:
    url = "https://datasets-server.huggingface.co/rows?" + urlencode({
        "dataset": DATASET, "config": "default", "split": SPLIT,
        "offset": offset, "length": length,
    })
    raw, headers = request_bytes(Request(url), "Hugging Face")
    payload = json.loads(raw)
    if payload.get("num_rows_total") != DATASET_SIZE or payload.get("partial"):
        raise ValueError("Expected a complete 2,500-row test split.")
    rows = payload["rows"]
    if len(rows) != length or any(row.get("truncated_cells") for row in rows):
        raise ValueError("Hugging Face returned incomplete row data.")
    if [row["row_idx"] for row in rows] != list(range(offset, offset + length)):
        raise ValueError("Hugging Face row indexes are not contiguous.")
    revision = next((v for k, v in headers.items() if k.lower() == "x-revision"), "")
    if not revision:
        raise ValueError("Hugging Face did not identify the dataset revision.")
    return [{"index": row["row_idx"], **row["row"]} for row in rows], revision


def load_dataset(offline: bool) -> tuple[list[dict], str]:
    path = DATA / "test.json"
    if path.exists():
        saved = read_json(path)
        rows, revision = saved["rows"], saved["revision"]
    else:
        if offline:
            raise ValueError("No local dataset metadata. Run the live smoke test first.")
        rows, revision = [], None
        for offset in range(0, DATASET_SIZE, 100):
            page_path = DATA / "pages" / f"{offset}.json"
            if page_path.exists():
                saved_page = read_json(page_path)
                page, page_revision = saved_page["rows"], saved_page["revision"]
            else:
                page, page_revision = fetch_rows(offset)
                write_json(page_path, {"rows": page, "revision": page_revision})
            if revision is not None and page_revision != revision:
                raise ValueError("Dataset changed while downloading; rerun before scoring.")
            revision = page_revision
            rows.extend(page)
            print(f"Dataset metadata: {len(rows)}/{DATASET_SIZE}", flush=True)
        write_json(path, {"revision": revision, "rows": rows})
    if len(rows) != DATASET_SIZE or len({row["index"] for row in rows}) != DATASET_SIZE:
        raise ValueError("Local metadata must contain all 2,500 distinct test rows.")
    return rows, revision


def select_sample(rows: list[dict], count: int) -> list[dict]:
    ages = {}
    for row in rows:
        age = row["age"]
        if not isinstance(age, (int, float)) or not math.isfinite(age) or age <= 0:
            raise ValueError("Speaker age is missing or invalid.")
        if row["speaker"] in ages and ages[row["speaker"]] != age:
            raise ValueError("The same speaker has inconsistent ages.")
        ages[row["speaker"]] = age
    return sorted(rows, key=lambda row: (row["age"], digest([SEED, row["index"]])))[:count]


def child_stats(rows: list[dict]) -> dict:
    speakers = {row["speaker"]: row["age"] for row in rows}
    children = sum(age < 13 for age in speakers.values())
    return {
        "n_speakers": len(speakers),
        "n_child_speakers": children,
        "child_share": children / len(speakers),
        "child_utterance_share": sum(row["age"] < 13 for row in rows) / len(rows),
        "age_min": min(speakers.values()),
        "age_max": max(speakers.values()),
    }


def api_key() -> str:
    value = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if value:
        return value
    path = ROOT / ".env.local"
    if path.exists():
        for line in path.read_text().splitlines():
            parts = shlex.split(line, comments=True)
            if parts and parts[0] == "export":
                parts = parts[1:]
            if parts and parts[0].startswith("ELEVENLABS_API_KEY="):
                value = parts[0].partition("=")[2]
                if value:
                    return value
    raise ValueError("ELEVENLABS_API_KEY is missing from the environment or .env.local.")


def cache_path(row: dict, revision: str) -> Path:
    return CACHE / "transcripts" / (digest({
        "dataset": DATASET, "split": SPLIT, "revision": revision,
        "row": row["index"], "params": PARAMS, "format_version": 1,
    }) + ".json")


def audio_bytes(row: dict, revision: str) -> bytes:
    path = DATA / "audio" / revision / f"{row['index']}.wav"
    if path.exists():
        return path.read_bytes()
    # Viewer audio URLs expire, so obtain a fresh URL for each uncached recording.
    fresh, fresh_revision = fetch_rows(row["index"], 1)
    if fresh_revision != revision:
        raise ValueError("Dataset revision changed; refusing to mix labels and recordings.")
    source = fresh[0]["audio"][0]["src"]
    raw, _ = request_bytes(Request(source), "Hugging Face audio")
    if not raw.startswith(b"RIFF") or raw[8:12] != b"WAVE":
        raise ValueError("Expected WAV audio from the dataset viewer.")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)
    return raw


def multipart(audio: bytes) -> tuple[bytes, str]:
    boundary = "pip_eval_" + uuid.uuid4().hex
    parts = []
    for name, value in PARAMS.items():
        parts.append((f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"'
                      f'\r\n\r\n{value}\r\n').encode())
    parts.extend([
        (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; '
         'filename="utterance.wav"\r\nContent-Type: audio/wav\r\n\r\n').encode(),
        audio, f"\r\n--{boundary}--\r\n".encode(),
    ])
    return b"".join(parts), boundary


def normalize_transcript(response: dict) -> dict:
    if not isinstance(response.get("text"), str) or not isinstance(response.get("words"), list):
        raise ValueError("Scribe response is missing text or word timestamps.")
    words = []
    for word in response["words"]:
        if word.get("type") != "word":
            continue
        start, end = word.get("start"), word.get("end")
        if (not isinstance(word.get("text"), str) or
            not isinstance(start, (int, float)) or not isinstance(end, (int, float)) or
            not math.isfinite(start) or not math.isfinite(end) or start < 0 or end < start):
            raise ValueError("Scribe returned an invalid word timestamp.")
        words.append({"text": word["text"], "start": start, "end": end})
    if response["text"].strip() and not words:
        raise ValueError("Scribe returned text without timestamped words.")
    return {"text": response["text"], "words": words}


def transcribe(row: dict, revision: str, key: str | None) -> tuple[dict, bool]:
    path = cache_path(row, revision)
    if path.exists():
        return normalize_transcript(read_json(path)["response"]), True
    if key is None:
        raise ValueError("Missing cached transcript; offline mode never calls Scribe.")
    body, boundary = multipart(audio_bytes(row, revision))
    request = Request("https://api.elevenlabs.io/v1/speech-to-text", data=body, headers={
        "xi-api-key": key, "Content-Type": f"multipart/form-data; boundary={boundary}",
    })
    raw, _ = request_bytes(request, "ElevenLabs Scribe")
    response = json.loads(raw)
    transcript = normalize_transcript(response)
    write_json(path, {"response": response, "recorded_at": datetime.now(timezone.utc).isoformat()})
    return transcript, False


def alignment_provenance() -> dict:
    paths = sorted((ROOT / "lib/reading").glob("*.ts")) + [ROOT / "lib/text.ts", ROOT / "lib/types.ts"]
    files = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
             for path in paths if not path.name.endswith(".test.ts")}
    return {
        "source_sha256": digest(files), "files": files,
        "bootstrap_placeholder": "Placeholder alignment" in (ROOT / "lib/reading/align.ts").read_text(),
    }


def align(rows: list[dict], transcripts: list[dict]) -> list[dict]:
    inputs = [{"expectedText": row["text"], "transcript": transcript,
               "referenceWords": [word["text"] for word in row["words"]]}
              for row, transcript in zip(rows, transcripts, strict=True)]
    completed = subprocess.run(
        ["npx", "--no-install", "tsx", "eval/align-cli.ts"], cwd=ROOT,
        input=json.dumps(inputs), text=True, capture_output=True, timeout=60,
        env={**os.environ, "NEXT_PUBLIC_MOCK": "1"},
    )
    if completed.returncode:
        raise ValueError("App alignment CLI failed; check label token mapping and the installed tsx runner.")
    results = json.loads(completed.stdout)
    if not isinstance(results, list) or len(results) != len(rows):
        raise ValueError("Alignment CLI returned the wrong number of utterances.")
    return results


def score(rows: list[dict], alignments: list[dict]) -> dict:
    counts = {"tp": 0, "fp": 0, "fn": 0, "tn": 0}
    for row, alignment in zip(rows, alignments, strict=True):
        for label, word in zip(row["words"], alignment["words"], strict=True):
            accuracy = label["accuracy"]
            if not isinstance(accuracy, (int, float)) or not 0 <= accuracy <= 10:
                raise ValueError("Human accuracy labels must be on the 0 to 10 scale.")
            if word["status"] not in ("correct", "selfCorrected", "substitution", "omission"):
                raise ValueError("Unknown alignment status.")
            human = accuracy <= 5
            flagged = word["status"] in ("substitution", "omission")
            counts["tp" if flagged and human else "fp" if flagged else "fn" if human else "tn"] += 1
    tp, fp, fn, tn = (counts[key] for key in ("tp", "fp", "fn", "tn"))
    total = sum(counts.values())
    if not total:
        raise ValueError("No labeled words to score.")
    return {
        "precision": tp / (tp + fp) if tp + fp else None,
        "recall": tp / (tp + fn) if tp + fn else None,
        "percent_agreement": 100 * (tp + tn) / total,
        "n_words": total, "n_utterances": len(rows),
        "n_flagged_words": tp + fp, "n_human_positive_words": tp + fn,
        "confusion_matrix": counts,
    }


def slide_line(result: dict) -> str:
    precision = result["precision"]
    lead = (f"When Pip flags a word, experts agreed {100 * precision:.1f}% of the time"
            if precision is not None else "Precision is undefined because Pip flagged no words")
    return (f"{lead} ({result['n_words']:,} words, {result['n_flagged_words']:,} flagged, "
            f"speechocean762, non-native English learners, "
            f"{100 * result['child_share']:.1f}% of speakers under 13).")


def wait_for_window(count: int, concurrency: int, wait: bool) -> None:
    while True:
        now = datetime.now(PACIFIC)
        release = now.replace(hour=12, minute=30, second=0, microsecond=0)
        if now >= release or (count <= 5 and concurrency == 1):
            return
        if not wait:
            raise ValueError("Before 12:30 PM Pacific, use at most 5 utterances and concurrency 1.")
        remaining = (release - now).total_seconds()
        print(f"Shared Scribe window opens at 12:30 PM Pacific; waiting {remaining / 60:.1f} minutes.", flush=True)
        time.sleep(min(remaining, 60))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, default=200, choices=range(1, 201), metavar="1..200")
    parser.add_argument("--concurrency", type=int, choices=range(1, 5), default=4)
    parser.add_argument("--offline", action="store_true", help="Only use cached data and transcripts.")
    parser.add_argument("--wait-for-window", action="store_true", help="Wait until 12:30 PM Pacific for full runs.")
    parser.add_argument("--output", default="results.json", help="Path relative to eval/.")
    args = parser.parse_args()
    output = (HERE / args.output).resolve()
    if not output.is_relative_to(HERE) or output.suffix != ".json":
        parser.error("Output must be a JSON file inside eval/.")
    if args.limit != 200 and output == HERE / "results.json":
        parser.error("Smoke runs must use --output .cache/smoke-results.json; results.json is reserved for 200.")
    if not args.offline:
        wait_for_window(args.limit, args.concurrency, args.wait_for_window)
    rows, revision = load_dataset(args.offline)
    sample = select_sample(rows, args.limit)
    demographics = child_stats(sample)
    print(f"Sample: {len(sample)} utterances, {demographics['n_speakers']} speakers; "
          f"{100 * demographics['child_share']:.1f}% of speakers under 13; "
          f"{100 * demographics['child_utterance_share']:.1f}% of utterances from children.", flush=True)
    # Verify label indexes before paying for any transcription.
    align(sample, [{"text": "", "words": []} for _ in sample])
    missing = sum(not cache_path(row, revision).exists() for row in sample)
    if args.offline and missing:
        raise ValueError(f"Offline mode: {missing} transcripts are missing. No results written.")
    key = api_key() if missing else None
    transcripts = [None] * len(sample)
    cache_hits = 0
    stopped = threading.Event()

    def work(index: int):
        if stopped.is_set():
            return None
        try:
            return transcribe(sample[index], revision, key)
        except Exception:
            stopped.set()
            raise

    with ThreadPoolExecutor(max_workers=args.concurrency) as executor:
        futures = {executor.submit(work, i): i for i in range(len(sample))}
        for done, future in enumerate(as_completed(futures), 1):
            result = future.result()
            if result is None:
                continue
            transcript, cached = result
            transcripts[futures[future]] = transcript
            cache_hits += cached
            print(f"Transcripts: {done}/{len(sample)} ({cache_hits} cache hits)", flush=True)
    if any(transcript is None for transcript in transcripts):
        raise ValueError("Incomplete transcription run. Cached successes are safe to reuse.")
    provenance = alignment_provenance()
    metrics = score(sample, align(sample, transcripts))
    if provenance != alignment_provenance():
        raise ValueError("Alignment source changed during scoring; rerun from cached transcripts.")
    caveat = ("This is non-native pronunciation data from Mandarin-speaking English learners, "
              "not native child read-aloud. Recall is expected to be low because speech models "
              "normalize mispronunciations; this run does not establish the cause of missed flags. "
              "The youngest-first sample is not representative of all children. "
              "Batch Scribe results do not validate the app's realtime Scribe model.")
    if provenance["bootstrap_placeholder"]:
        caveat += " Preliminary bootstrap alignment only; rescore after the app alignment upgrade."
    result = {
        **metrics, **demographics, "date": datetime.now(timezone.utc).isoformat(),
        "dataset": DATASET, "dataset_revision": revision, "split": SPLIT,
        "sampling": {"method": "age ascending, SHA-256(seed, row index) tie-break", "seed": SEED,
                     "sample_sha256": digest([row["index"] for row in sample]), "available_utterances": len(rows)},
        "scribe": PARAMS, "alignment": provenance,
        "human_label": "word accuracy <= 5 (0 to 10 scale)",
        "flagged_statuses": ["substitution", "omission"],
        "metric_units": {"precision": "fraction", "recall": "fraction", "percent_agreement": "percent",
                         "child_share": "fraction of distinct sampled speakers under 13",
                         "child_utterance_share": "fraction of sampled utterances from speakers under 13"},
        "limitations": caveat,
    }
    result["summary"] = slide_line(result) + " " + caveat
    write_json(output, result)
    print(slide_line(result), flush=True)
    recall = f"{100 * metrics['recall']:.1f}%" if metrics["recall"] is not None else "undefined"
    print(f"Recall: {recall}; agreement: {metrics['percent_agreement']:.1f}%.")
    print(caveat)
    print(f"Wrote eval/{output.relative_to(HERE)}. Scribe cache hits: {cache_hits}/{len(sample)}.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError, KeyError, subprocess.SubprocessError) as error:
        print(f"Eval stopped: {error}", file=sys.stderr)
        raise SystemExit(1)
