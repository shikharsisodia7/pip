"""Synthetic checks for measurement validity, cache reuse, and the app bridge."""

from datetime import datetime
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request

import run


class MeasurementTests(unittest.TestCase):
    def test_threshold_and_confusion_matrix(self):
        rows = [{"words": [{"accuracy": n} for n in [5, 6, 0, 10, 5, 9]]}]
        alignment = [{"words": [{"status": status} for status in [
            "substitution", "substitution", "omission", "correct", "selfCorrected", "correct",
        ]]}]
        result = run.score(rows, alignment)
        self.assertEqual(result["confusion_matrix"], {"tp": 2, "fp": 1, "fn": 1, "tn": 2})
        self.assertAlmostEqual(result["precision"], 2 / 3)
        self.assertAlmostEqual(result["recall"], 2 / 3)
        self.assertAlmostEqual(result["percent_agreement"], 100 * 4 / 6)
        self.assertEqual(result["n_words"], 6)

    def test_undefined_precision_and_recall_are_not_zero_or_perfect(self):
        result = run.score([{"words": [{"accuracy": 10}]}], [{"words": [{"status": "correct"}]}])
        self.assertIsNone(result["precision"])
        self.assertIsNone(result["recall"])
        self.assertEqual(result["percent_agreement"], 100)

    def test_missing_label_is_never_silently_dropped(self):
        with self.assertRaises(ValueError):
            run.score([{"words": [{"accuracy": 5}, {"accuracy": 6}]}],
                      [{"words": [{"status": "correct"}]}])

    def test_child_share_counts_distinct_speakers_and_excludes_age_13(self):
        rows = [{"speaker": "synthetic-child", "age": 7}] * 3 + [
            {"speaker": "synthetic-teen", "age": 13}]
        result = run.child_stats(rows)
        self.assertEqual(result["child_share"], 0.5)
        self.assertEqual(result["child_utterance_share"], 0.75)
        self.assertEqual(result["n_speakers"], 2)

    def test_sampling_is_reproducible_youngest_first_and_smoke_is_a_prefix(self):
        rows = [{"index": i, "age": 6 + i % 3, "speaker": f"synthetic-{i}"} for i in range(20)]
        full = run.select_sample(rows, 10)
        self.assertEqual(full, run.select_sample(list(reversed(rows)), 10))
        self.assertEqual(full[:5], run.select_sample(rows, 5))
        self.assertEqual([row["age"] for row in full], sorted(row["age"] for row in full))

    def test_app_bridge_uses_real_alignment_and_rejects_shifted_labels(self):
        row = {"text": "The cat sat.", "words": [{"text": word} for word in ["THE", "CAT", "SAT"]]}
        transcript = {"text": "The cat", "words": [
            {"text": "The", "start": 0, "end": 0.2}, {"text": "cat", "start": 0.3, "end": 0.5},
        ]}
        result = run.align([row], [transcript])[0]
        self.assertEqual([word["status"] for word in result["words"]], ["correct", "correct", "omission"])
        row["words"] = [{"text": word} for word in ["CAT", "THE", "SAT"]]
        with self.assertRaises(ValueError):
            run.align([row], [transcript])


class PipelineTests(unittest.TestCase):
    def test_incomplete_dataset_page_is_rejected(self):
        import json
        payload = {"num_rows_total": 2500, "partial": False,
                   "rows": [{"row_idx": 0, "row": {}, "truncated_cells": ["words"]}]}
        with patch.object(run, "request_bytes", return_value=(json.dumps(payload).encode(), {"x-revision": "synthetic"})):
            with self.assertRaisesRegex(ValueError, "incomplete row data"):
                run.fetch_rows(0, 1)

    def test_completed_metadata_pages_survive_a_later_download_failure(self):
        run.CACHE.mkdir(exist_ok=True)
        rows = [{"index": i} for i in range(100)]
        with tempfile.TemporaryDirectory(dir=run.CACHE) as directory, patch.object(run, "DATA", Path(directory)):
            with patch.object(run, "fetch_rows", side_effect=[(rows, "synthetic"), RuntimeError("temporary outage")]):
                with self.assertRaises(RuntimeError):
                    run.load_dataset(False)
            self.assertEqual(run.read_json(Path(directory) / "pages/0.json")["rows"], rows)
            with patch.object(run, "fetch_rows", side_effect=RuntimeError("temporary outage")) as fetch:
                with self.assertRaises(RuntimeError):
                    run.load_dataset(False)
                fetch.assert_called_once_with(100)

    def test_spacing_and_audio_events_are_removed_but_fillers_remain(self):
        response = {"text": "Um, cat.", "words": [
            {"type": "word", "text": "Um,", "start": 0, "end": 0.2},
            {"type": "spacing", "text": " ", "start": 0.2, "end": 0.3},
            {"type": "word", "text": "cat.", "start": 0.3, "end": 0.5},
            {"type": "audio_event", "text": "(noise)", "start": 0.5, "end": 0.6},
        ]}
        self.assertEqual([word["text"] for word in run.normalize_transcript(response)["words"]], ["Um,", "cat."])

    def test_missing_timestamps_fail_instead_of_inventing_timing(self):
        with self.assertRaises(ValueError):
            run.normalize_transcript({"text": "cat", "words": [{"type": "word", "text": "cat"}]})

    def test_cached_transcript_needs_neither_key_nor_network(self):
        run.CACHE.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=run.CACHE) as directory, patch.object(run, "CACHE", Path(directory)):
            row = {"index": 12}
            response = {"text": "cat", "words": [{"type": "word", "text": "cat", "start": 0, "end": 1}]}
            run.write_json(run.cache_path(row, "synthetic-revision"), {"response": response})
            with patch.object(run, "request_bytes", side_effect=AssertionError("Network used")):
                transcript, cached = run.transcribe(row, "synthetic-revision", None)
                self.assertTrue(cached)
                self.assertEqual(transcript["text"], "cat")
            with self.assertRaises(ValueError):
                run.transcribe(row, "different-revision", None)

    def test_rate_limit_retries_and_fatal_errors_do_not_leak_response_body(self):
        rate_limit = HTTPError("https://example.invalid", 429, "rate limit", {}, io.BytesIO(b"private response"))
        unauthorized = HTTPError("https://example.invalid", 401, "unauthorized", {}, io.BytesIO(b"private response"))
        with patch.object(run, "urlopen", side_effect=[rate_limit, unauthorized]) as request, \
             patch.object(run.time, "sleep") as sleep, patch("sys.stdout", new_callable=io.StringIO):
            with self.assertRaisesRegex(RuntimeError, "Scribe: HTTP 401; request failed") as raised:
                run.request_bytes(Request("https://example.invalid"), "Scribe")
            self.assertNotIn("private response", str(raised.exception))
            self.assertEqual(request.call_count, 2)
            sleep.assert_called_once()

    def test_request_has_word_timestamps_verbatim_and_no_reference_hints(self):
        body, boundary = run.multipart(b"synthetic-audio")
        self.assertIn(b'name="timestamps_granularity"\r\n\r\nword', body)
        self.assertIn(b'name="no_verbatim"\r\n\r\nfalse', body)
        self.assertNotIn(b"keyterms", body)
        self.assertNotIn(b"transcript_edit", body)
        self.assertTrue(body.endswith(f"--{boundary}--\r\n".encode()))

    def test_shared_window_enforces_limit_and_concurrency(self):
        with patch.object(run, "datetime") as clock:
            clock.now.return_value = datetime(2026, 11, 13, 12, 29, tzinfo=run.PACIFIC)
            run.wait_for_window(5, 1, False)
            for count, concurrency in [(6, 1), (5, 2), (200, 4)]:
                with self.assertRaises(ValueError):
                    run.wait_for_window(count, concurrency, False)
            clock.now.return_value = datetime(2026, 11, 13, 12, 30, tzinfo=run.PACIFIC)
            run.wait_for_window(200, 4, False)

    def test_smoke_cannot_overwrite_full_results(self):
        process = subprocess.run(["python", "eval/run.py", "--limit", "5", "--offline"],
                                 cwd=run.ROOT, capture_output=True, text=True)
        self.assertNotEqual(process.returncode, 0)
        self.assertIn("reserved for 200", process.stderr)


if __name__ == "__main__":
    unittest.main()
