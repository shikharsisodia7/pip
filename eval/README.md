# Listening evaluation

Compare the app's word flags with expert word accuracy labels from
[speechocean762](https://huggingface.co/datasets/mispeech/speechocean762).
This is non-native pronunciation data from Mandarin-speaking English learners,
not native child read-aloud. Recall is expected to be low because speech models
normalize mispronunciations. A missed flag alone does not prove that mechanism.
Batch Scribe performance also does not validate the app's realtime Scribe model.

## Run

Run commands from the repository root with Node dependencies already installed,
`uv`, and Python 3.11 or later. The isolated Python project has no dependencies.
The runner reads `ELEVENLABS_API_KEY` from the process environment or from
`.env.local` at the repository root, in that order. It never copies or prints keys.
`NEXT_PUBLIC_MOCK=1` keeps app helpers in mock mode; this evaluation explicitly
uses the live batch transcription endpoint unless `--offline` is supplied.

Before 12:30 PM Pacific, only the same five-utterance smoke sample may use Scribe,
with concurrency one. Reruns reuse its transcripts:

```sh
UV_CACHE_DIR="$PWD/eval/.cache/uv" NEXT_PUBLIC_MOCK=1 uv run --project eval python eval/run.py \
  --limit 5 --concurrency 1 --output .cache/smoke-results.json
```

At or after 12:30 PM Pacific, run all 200 with concurrency four:

```sh
UV_CACHE_DIR="$PWD/eval/.cache/uv" NEXT_PUBLIC_MOCK=1 uv run --project eval python eval/run.py
```

Add `--wait-for-window` to wait for the shared API window. Without that flag,
an early full run exits without making requests. Live requests retry network
errors, HTTP 408/429, and server errors with bounded exponential backoff.
If any utterance fails, the run stops without writing a partial result;
successful transcripts remain cached for the next run.

After the app alignment upgrade lands, rescore without a key or network requests:

```sh
UV_CACHE_DIR="$PWD/eval/.cache/uv" NEXT_PUBLIC_MOCK=1 uv run --project eval python eval/run.py --offline
```

The runner prints a precision-led slide line, recall, agreement, and the measured
share of **distinct sampled speakers** under 13. A completed full run writes
`eval/results.json`. Smoke results stay in the ignored cache and cannot overwrite
the full result. No numeric result is a fixture or an estimate.

## What is measured

- Load all 2,500 rows of the Hugging Face `test` split using the documented
  [dataset viewer rows API](https://huggingface.co/docs/dataset-viewer/rows).
  This avoids installing the `datasets` library or audio decoders. Validate that
  every page is complete, untruncated, and from the same dataset revision.
- Select 200 utterances by ascending speaker age. Ties use SHA-256 of the fixed
  seed `762` and dataset row index. The five smoke rows are the full sample's
  prefix. This deliberately favors the youngest speakers, without using scores
  or transcripts to select the sample. It is not a representative population
  sample, and multiple utterances from one speaker are not independent.
- Send each selected recording to ElevenLabs batch `scribe_v2`, using English,
  word timestamps, `no_verbatim=false`, and no reference-text prompts or keyterms.
  Retain filler words, filter spacing and audio-event tokens, and keep the actual
  returned timestamps. Parameters follow the
  [current batch API reference](https://elevenlabs.io/docs/api-reference/speech-to-text/convert).
- Call the app's imported `alignWords` through `npx tsx eval/align-cli.ts`.
  There is no Python alignment implementation. The CLI checks that each human
  word label maps exactly to the app's normalized expected word at the same index.
  Any mismatch stops scoring instead of silently dropping or shifting labels.
- A positive human label is **word accuracy <= 5**, on the dataset's 0 to 10
  scale. A model flag is **substitution or omission**. Correct and self-corrected
  words are negative; insertions have no reference label and are not scored.
- Compute micro-averages across all labeled reference words: precision is
  `TP / (TP + FP)`, recall is `TP / (TP + FN)`, and percent agreement is
  `100 * (TP + TN) / n_words`. Undefined precision or recall is JSON `null`,
  never an invented zero or perfect score. Agreement can be high when most
  words are negative, so the confusion matrix and class counts are included.
- `child_share` is a fraction of distinct sampled speakers aged strictly under
  13. `child_utterance_share` separately measures their share of utterances.
  Precision and recall are fractions; agreement is in percent.

Results include the date, model parameters, dataset revision, sample fingerprint,
and hashes of the local alignment sources. If the bootstrap placeholder is still
present, the summary explicitly marks the measurement preliminary. Merge the
alignment upgrade and rescore before quoting a final app result. Cached transcripts
are keyed by dataset revision, row index, and transcription parameters, independent
of alignment code, so an alignment-only rescore makes no paid requests.

The slide line's "experts agreed" means the dataset's aggregated expert word score
met the chosen threshold. It does not measure agreement among individual raters,
reading improvement, clinical validity, or performance for native child readers.

## Checks and private artifacts

```sh
UV_CACHE_DIR="$PWD/eval/.cache/uv" NEXT_PUBLIC_MOCK=1 uv run --project eval \
  python -m unittest discover -s eval -p 'test_*.py'
NEXT_PUBLIC_MOCK=1 npm run check
```

Tests use synthetic data to verify the metric denominator and threshold, child
share, real TypeScript bridge, cache reuse, retry behavior, and concurrency gate.
They do not contact Scribe. The bridge accepts a JSON object or array on stdin,
and emits the app's alignment result or result array as JSON on stdout:

```sh
printf '%s\n' '{"expectedText":"The cat sat.","transcript":{"text":"The cat","words":[{"text":"The","start":0,"end":0.2},{"text":"cat","start":0.3,"end":0.5}]}}' \
  | npx tsx eval/align-cli.ts
```

`eval/data/`, `eval/.cache/`, and `eval/.venv/` are gitignored. Audio, dataset rows,
speaker identifiers, and transcripts stay there. Only scripts, project metadata,
this README, and aggregate results belong in a commit. Do not force-add caches.

Dataset: *speechocean762: An Open-Source Non-native English Speech Corpus for
Pronunciation Assessment*, Interspeech 2021,
[paper](https://arxiv.org/abs/2104.01378). The Hugging Face dataset lists Apache 2.0.
No dataset recordings or utterance text are redistributed by this evaluation.
