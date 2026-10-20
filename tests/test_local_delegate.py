#!/usr/bin/env python3
"""scripts/local_delegate.py のテスト。

本物の Ollama は使わない。スレッドで偽の Ollama（/api/version, /api/tags, /api/ps, /api/chat）を立て、
/api/chat の応答を順番に差し替えて、検証（L0/L2）・再試行・skip・台帳・集計・bench を確認する。
"""

import contextlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# scripts/__pycache__ を作らない（init.sh の cp -R scripts で配布先に混ざるため）
sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "local_delegate.py"
spec = importlib.util.spec_from_file_location("local_delegate", SCRIPT)
ld = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ld)

LABELS = {"labels": [{"name": "犬", "description": "犬の話"}, {"name": "猫", "description": "猫の話"}],
          "allow_null": True, "null_description": "どちらでもない"}
SCHEMA = {"type": "object", "required": ["name", "date"], "additionalProperties": False,
          "properties": {"name": {"type": "string"}, "date": {"type": ["string", "null"]},
                         "amount": {"type": "integer", "x-verbatim": True},
                         "summary": {"type": "string", "x-verbatim": False}}}


class FakeOllama:
    def __init__(self, models=("qwen3:4b",), loaded=()):
        self.models = list(models)
        self.loaded = list(loaded)
        self.replies = []
        self.requests = []
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def _send(self, obj, code=200):
                body = json.dumps(obj).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                if self.path == "/api/version":
                    self._send({"version": "0.0.0-fake"})
                elif self.path == "/api/tags":
                    self._send({"models": [{"name": m, "digest": "digest-" + m} for m in fake.models]})
                elif self.path == "/api/ps":
                    self._send({"models": [{"name": m} for m in fake.loaded]})
                else:
                    self._send({"error": "not found"}, 404)

            def do_POST(self):
                payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                fake.requests.append(payload)
                content = fake.replies.pop(0) if fake.replies else ""
                done = "length" if content.startswith("TRUNCATED") else "stop"
                self._send({"message": {"role": "assistant", "content": content, "thinking": "考えた"},
                            "done_reason": done,
                            "prompt_eval_count": 100, "eval_count": 20, "load_duration": 5_000_000})

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.fake = FakeOllama(loaded=("qwen3:4b",))
        self.env = {"LOCAL_DELEGATE_HOME": str(self.dir / "home"), "LOCAL_DELEGATE_ENDPOINT": self.fake.url,
                    "LOCAL_DELEGATE_BLACKOUT": "", "LOCAL_DELEGATE_MIN_AVAILABLE_GB": "0",
                    "LOCAL_DELEGATE_AGENT": "test"}
        self._old = {k: os.environ.get(k) for k in self.env}
        os.environ.update(self.env)
        (self.dir / "labels.json").write_text(json.dumps(LABELS, ensure_ascii=False), encoding="utf-8")
        (self.dir / "schema.json").write_text(json.dumps(SCHEMA), encoding="utf-8")

    def tearDown(self):
        self.fake.close()
        for k, v in self._old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def run_main(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = ld.main(argv)
        return code, out.getvalue(), err.getvalue()

    def ledger(self):
        p = self.dir / "home" / "ledger.jsonl"
        return [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines()] if p.exists() else []

    def write_items(self, items):
        p = self.dir / "items.jsonl"
        p.write_text("\n".join(json.dumps(i, ensure_ascii=False) for i in items), encoding="utf-8")
        return str(p)


class TestParse(unittest.TestCase):
    def test_plain(self):
        self.assertEqual(ld.parse_json_output('[{"id": "1"}]'), [{"id": "1"}])

    def test_think_and_fence_and_prefix(self):
        text = '<think>考え中 {"x": 1}</think>\n結果です:\n```json\n{"a": "b"}\n```'
        self.assertEqual(ld.parse_json_output(text), {"a": "b"})

    def test_think_without_open_tag(self):
        text = 'Okay, {"label": "猫"} かな。\n</think>\n\n[{"id": "1", "label": "犬"}]'
        self.assertEqual(ld.parse_json_output(text), [{"id": "1", "label": "犬"}])

    def test_leading_text(self):
        self.assertEqual(ld.parse_json_output('答え: {"a": [1, 2]} 以上'), {"a": [1, 2]})

    def test_no_json(self):
        with self.assertRaises(ValueError):
            ld.parse_json_output("JSON なし")


class TestBlackout(unittest.TestCase):
    def test_windows(self):
        import datetime as dt
        w = ld.parse_blackout("10:55-11:10,23:50-00:10")
        self.assertTrue(ld.in_blackout(dt.time(11, 0), w))
        self.assertFalse(ld.in_blackout(dt.time(11, 10), w))
        self.assertTrue(ld.in_blackout(dt.time(0, 5), w))
        self.assertTrue(ld.in_blackout(dt.time(23, 55), w))
        self.assertFalse(ld.in_blackout(dt.time(12, 0), w))
        self.assertEqual(ld.parse_blackout(""), [])
        with self.assertRaises(ld.UsageError):
            ld.parse_blackout("11時")


class TestVerifyClassify(unittest.TestCase):
    spec = {"labels": LABELS["labels"], "allow_null": False, "null_description": ""}
    items = [{"id": "a", "text": "x"}, {"id": "b", "text": "y"}]

    def test_pass(self):
        l0, l2, out = ld.verify_classify([{"id": "a", "label": "犬"}, {"id": "b", "label": "猫"}],
                                         self.spec, self.items)
        self.assertEqual((l0, l2), ([], []))
        self.assertEqual([r["label"] for r in out], ["犬", "猫"])

    def test_l0_shape(self):
        l0, _, _ = ld.verify_classify({"result": "犬"}, self.spec, self.items)
        self.assertTrue(l0)
        l0, _, _ = ld.verify_classify([{"id": "a"}], self.spec, self.items)
        self.assertTrue(l0)

    def test_l2_count_ids_labels(self):
        _, l2, _ = ld.verify_classify([{"id": "a", "label": "犬"}], self.spec, self.items)
        self.assertTrue(any("件数" in e for e in l2))
        _, l2, _ = ld.verify_classify([{"id": "a", "label": "犬"}, {"id": "a", "label": "猫"}],
                                      self.spec, self.items)
        self.assertTrue(any("重複" in e for e in l2))
        _, l2, _ = ld.verify_classify([{"id": "a", "label": "鳥"}, {"id": "b", "label": None}],
                                      self.spec, self.items)
        self.assertTrue(any("ラベル集合にない" in e for e in l2))
        self.assertTrue(any("null は許可" in e for e in l2))

    def test_int_id_and_single_object(self):
        l0, l2, out = ld.verify_classify({"id": 1, "label": "犬"}, self.spec, [{"id": "1", "text": "x"}])
        self.assertEqual((l0, l2, out[0]["id"]), ([], [], "1"))


class TestClassifyPrompt(unittest.TestCase):
    def test_null_is_unquoted_when_allowed(self):
        spec = {"labels": LABELS["labels"], "allow_null": True, "null_description": "どちらでもない"}
        user = ld.classify_messages(spec, [{"id": "1", "text": "x"}], "")[1]["content"]
        self.assertIn('"label": "<ラベル名>" または null,', user)
        self.assertIn('文字列の "null" は不可', user)
        self.assertNotIn('"<ラベル名、または null>"', user)

    def test_no_null_when_not_allowed(self):
        spec = {"labels": LABELS["labels"], "allow_null": False, "null_description": ""}
        user = ld.classify_messages(spec, [{"id": "1", "text": "x"}], "")[1]["content"]
        self.assertIn('"label": "<ラベル名>",', user)
        self.assertNotIn("null", user)

    def test_prompt_version(self):
        self.assertEqual(ld.PROMPT_VERSIONS["classify.fixed"], "classify.fixed/v2")


class TestVerifyExtract(unittest.TestCase):
    src = "山田太郎が2026年10月6日に3000円を支払った。"

    def test_pass(self):
        l0, l2, _ = ld.verify_extract({"name": "山田太郎", "date": "2026年10月6日", "amount": 3000,
                                       "summary": "支払いの記録"}, SCHEMA, self.src)
        self.assertEqual((l0, l2), ([], []))

    def test_l0(self):
        l0, _, _ = ld.verify_extract({"name": "山田太郎"}, SCHEMA, self.src)
        self.assertTrue(any("必須キー date" in e for e in l0))
        l0, _, _ = ld.verify_extract({"name": 1, "date": None}, SCHEMA, self.src)
        self.assertTrue(any("$.name" in e for e in l0))
        l0, _, _ = ld.verify_extract({"name": "山田太郎", "date": None, "extra": 1}, SCHEMA, self.src)
        self.assertTrue(any("未定義のキー extra" in e for e in l0))
        l0, _, _ = ld.verify_extract({"name": "山田太郎", "date": None, "amount": True}, SCHEMA, self.src)
        self.assertTrue(l0)

    def test_l2_verbatim(self):
        _, l2, _ = ld.verify_extract({"name": "山田 太郎", "date": None}, SCHEMA, self.src)
        self.assertTrue(any("原文にない文字列" in e for e in l2))
        _, l2, _ = ld.verify_extract({"name": "山田太郎", "date": None, "amount": 5000}, SCHEMA, self.src)
        self.assertTrue(any("原文にない数値 5000" in e for e in l2))


class TestRun(Base):
    def test_classify_passed_and_ledger(self):
        self.fake.replies = ['[{"id": "1", "label": "犬", "reason": "犬"}, {"id": "2", "label": null}]']
        inp = self.write_items([{"id": 1, "text": "犬が走る"}, {"id": 2, "text": "雨"}])
        code, out, _ = self.run_main(["run", "--type", "classify.fixed", "--labels",
                                      str(self.dir / "labels.json"), "--input", inp])
        self.assertEqual(code, 0, out)
        res = json.loads(out)
        self.assertEqual(res["outcome"], "passed")
        self.assertEqual([r["label"] for r in res["output"]], ["犬", None])
        req = self.fake.requests[0]
        self.assertEqual(req["model"], "qwen3:4b")
        self.assertIs(req["think"], True)
        self.assertNotIn("format", req)
        self.assertEqual(req["options"], {"temperature": 0, "num_ctx": 8192, "num_predict": 4096})
        rows = self.ledger()
        self.assertEqual(len(rows), 1)
        r = rows[0]
        for key in ("ts", "agent", "project", "task_type", "model_id", "model_digest", "prompt_version",
                    "input_hash", "input_tokens", "output_tokens", "load_ms", "latency_ms", "verify_L0",
                    "verify_L1", "verify_L2", "retries", "outcome", "fail_layer", "skip_reason",
                    "main_review", "main_redo"):
            self.assertIn(key, r)
        self.assertEqual((r["agent"], r["model_digest"], r["verify_L0"], r["verify_L1"], r["verify_L2"]),
                         ("test", "digest-qwen3:4b", "pass", "n/a", "pass"))
        self.assertEqual((r["input_tokens"], r["output_tokens"], r["load_ms"]), (100, 20, 5))
        self.assertEqual((r["thinking_chars"], r["truncated"]), (3, False))
        self.assertNotIn("犬が走る", json.dumps(r, ensure_ascii=False))  # 台帳に本文を残さない

    def test_retry_then_pass(self):
        self.fake.replies = ['[{"id": "1", "label": "鳥"}]', '[{"id": "1", "label": "猫"}]']
        code, out, _ = self.run_main(["run", "--type", "classify.fixed", "--labels",
                                      str(self.dir / "labels.json"), "--text", "猫が鳴く"])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["output"][0]["label"], "猫")
        self.assertEqual(self.ledger()[0]["retries"], 1)
        attempts = self.ledger()[0]["attempt_errors"]
        self.assertEqual(len(attempts), 2)
        self.assertTrue(any("ラベル集合にない" in e for e in attempts[0]))
        self.assertEqual(attempts[1], [])
        retry_msgs = self.fake.requests[1]["messages"]
        self.assertIn("検証に失敗", retry_msgs[-1]["content"])
        self.assertEqual(self.ledger()[0]["input_tokens"], 200)

    def test_think_option_and_truncated(self):
        self.fake.replies = ["TRUNCATED Okay, let me", '[{"id": "1", "label": "犬"}]']
        code, _, _ = self.run_main(["run", "--type", "classify.fixed", "--labels",
                                    str(self.dir / "labels.json"), "--text", "x", "--think", "omit"])
        self.assertEqual(code, 0)
        self.assertNotIn("think", self.fake.requests[0])
        r = self.ledger()[0]
        self.assertEqual((r["truncated"], r["retries"], r["think"]), (True, 1, None))

    def test_failed_after_retry(self):
        self.fake.replies = ["説明だけ", "まだ説明だけ"]
        code, out, _ = self.run_main(["run", "--type", "classify.fixed", "--labels",
                                      str(self.dir / "labels.json"), "--text", "x"])
        self.assertEqual(code, 1)
        r = self.ledger()[0]
        self.assertEqual((r["outcome"], r["fail_layer"], r["retries"], r["verify_L0"]), ("failed", "L0", 1, "fail"))
        self.assertEqual(len(self.fake.requests), 2)

    def test_extract_l2_failed(self):
        self.fake.replies = ['{"name": "山田さん", "date": null}', '{"name": "山田さん", "date": null}']
        src = self.dir / "src.txt"
        src.write_text("山田太郎が来た。", encoding="utf-8")
        code, out, _ = self.run_main(["run", "--type", "extract.struct", "--schema", str(self.dir / "schema.json"),
                                      "--input", str(src)])
        self.assertEqual(code, 1)
        r = self.ledger()[0]
        self.assertEqual((r["fail_layer"], r["verify_L0"], r["verify_L2"]), ("L2", "pass", "fail"))

    def test_extract_passed(self):
        self.fake.replies = ['```json\n{"name": "山田太郎", "date": null, "amount": 3000}\n```']
        code, out, _ = self.run_main(["run", "--type", "extract.struct", "--schema", str(self.dir / "schema.json"),
                                      "--text", "山田太郎が3000円払った"])
        self.assertEqual(code, 0, out)
        self.assertEqual(json.loads(out)["output"]["amount"], 3000)


class TestSkip(Base):
    def assert_skipped(self, reason, argv=None):
        argv = argv or ["run", "--type", "classify.fixed", "--labels", str(self.dir / "labels.json"), "--text", "x"]
        code, out, _ = self.run_main(argv)
        self.assertEqual(code, 3, out)
        self.assertEqual(json.loads(out)["skip_reason"], reason)
        self.assertEqual(self.ledger()[-1]["outcome"], "skipped")
        self.assertEqual(self.fake.requests, [])

    def test_blackout(self):
        os.environ["LOCAL_DELEGATE_BLACKOUT"] = "00:00-23:59,23:59-00:00"
        self.assert_skipped("blackout_window")

    def test_unavailable(self):
        os.environ["LOCAL_DELEGATE_ENDPOINT"] = "http://127.0.0.1:9"
        self.assert_skipped("ollama_unavailable")

    def test_model_missing(self):
        self.fake.models = ["other:1b"]
        self.assert_skipped("model_not_installed")

    def test_too_large(self):
        self.assert_skipped("input_too_large", ["run", "--type", "classify.fixed", "--labels",
                                                str(self.dir / "labels.json"), "--text", "あ" * 3001])

    def test_low_memory_only_when_not_loaded(self):
        self.fake.loaded = []
        os.environ["LOCAL_DELEGATE_MIN_AVAILABLE_GB"] = "100000"
        original = ld.available_memory_gb
        ld.available_memory_gb = lambda: 1.0
        try:
            self.assert_skipped("low_memory")
            self.fake.loaded = ["qwen3:4b"]
            self.fake.replies = ['[{"id": "1", "label": "犬"}]']
            code, _, _ = self.run_main(["run", "--type", "classify.fixed", "--labels",
                                        str(self.dir / "labels.json"), "--text", "x"])
            self.assertEqual(code, 0)
        finally:
            ld.available_memory_gb = original


class TestUsage(Base):
    def test_errors(self):
        code, _, err = self.run_main(["run", "--type", "classify.fixed", "--text", "x"])
        self.assertEqual(code, 2)
        self.assertIn("--labels", err)
        code, _, err = self.run_main(["run", "--type", "classify.fixed", "--labels", str(self.dir / "labels.json")])
        self.assertEqual(code, 2)
        bad = self.dir / "bad.json"
        bad.write_text('{"labels": [{"name": "a"}, {"name": "a"}]}', encoding="utf-8")
        code, _, err = self.run_main(["run", "--type", "classify.fixed", "--labels", str(bad), "--text", "x"])
        self.assertEqual(code, 2)
        self.assertIn("重複", err)
        code, _, err = self.run_main(["review", "nope", "--result", "adopted"])
        self.assertEqual(code, 2)
        self.assertEqual(self.ledger(), [])

    def test_run_has_no_model_option(self):
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stderr(io.StringIO()):
                ld.main(["run", "--type", "classify.fixed", "--model", "qwen3:32b", "--text", "x"])


class TestReviewStats(Base):
    def test_review_and_stats(self):
        self.fake.replies = ['[{"id": "1", "label": "犬"}]', "x", "x", '[{"id": "1", "label": "猫"}]']
        labels = str(self.dir / "labels.json")
        self.run_main(["run", "--type", "classify.fixed", "--labels", labels, "--text", "a"])
        self.run_main(["run", "--type", "classify.fixed", "--labels", labels, "--text", "b"])
        self.run_main(["run", "--type", "classify.fixed", "--labels", labels, "--text", "c"])
        os.environ["LOCAL_DELEGATE_BLACKOUT"] = "00:00-23:59,23:59-00:00"
        self.run_main(["run", "--type", "classify.fixed", "--labels", labels, "--text", "d"])
        first = self.ledger()[0]["id"]
        second = self.ledger()[1]["id"]
        self.assertEqual(self.run_main(["review", first, "--result", "adopted"])[0], 0)
        self.assertEqual(self.run_main(["review", second, "--result", "rejected", "--redo"])[0], 0)
        code, out, _ = self.run_main(["stats", "--json"])
        self.assertEqual(code, 0)
        g = json.loads(out)[0]
        self.assertEqual((g["n"], g["passed"], g["failed"], g["skipped"]), (4, 2, 1, 1))
        self.assertEqual((g["adopted"], g["rejected"], g["redo"]), (1, 1, 1))
        self.assertEqual(g["pass_rate"], 0.667)
        self.assertAlmostEqual(g["wilson_lower"], round(ld.wilson_lower(2, 3), 3))
        code, out, _ = self.run_main(["stats"])
        self.assertIn("classify.fixed", out)

    def test_wilson(self):
        self.assertEqual(ld.wilson_lower(0, 0), 0.0)
        self.assertAlmostEqual(ld.wilson_lower(20, 20), 0.8389, places=3)


class TestBench(Base):
    def test_bench_scoring_and_no_ledger(self):
        golden = {"task_type": "classify.fixed", "labels": LABELS["labels"], "allow_null": True,
                  "items": [
                      {"id": "g1", "text": "犬", "expected": "犬", "must_match": True},
                      {"id": "g2", "text": "猫", "expected": "猫", "acceptable": ["犬"], "must_match": True},
                      {"id": "g3", "text": "雨", "expected": None},
                      {"id": "g4", "text": "猫", "expected": "猫", "must_match": True},
                      {"id": "g5", "text": "?", "expected": "犬"}]}
        gp = self.dir / "golden.json"
        gp.write_text(json.dumps(golden, ensure_ascii=False), encoding="utf-8")
        self.fake.models.append("qwen3-classify:latest")
        self.fake.loaded.append("qwen3-classify:latest")
        self.fake.replies = ['[{"id": "g1", "label": "犬"}]', '[{"id": "g2", "label": "犬"}]',
                             '[{"id": "g3", "label": "猫"}]', '[{"id": "g4", "label": null}]', "x", "x"]
        code, out, _ = self.run_main(["bench", "--golden", str(gp), "--model", "qwen3-classify:latest"])
        self.assertEqual(code, 0, out)
        self.assertIn("分類: 2/5 PASS (40.0%)", out)
        self.assertIn("取りこぼし(miss)         : 1", out)
        self.assertIn("誤検出(false_positive)   : 1", out)
        self.assertIn("検証失敗(invalid)        : 1", out)
        self.assertIn("must_match違反           : 1", out)
        self.assertIn("Wilson下限(95%)          : 0.118", out)
        self.assertIn("SLA判定                  : trial", out)
        self.assertEqual(self.fake.requests[0]["model"], "qwen3-classify:latest")
        self.assertEqual(self.ledger(), [])
        files = list((self.dir / "home" / "bench").glob("*.jsonl"))
        self.assertEqual(len(files), 1)
        rows = [json.loads(x) for x in files[0].read_text(encoding="utf-8").splitlines()]
        self.assertEqual([r["kind"] for r in rows], ["correct", "correct", "false_positive", "miss", "invalid"])
        self.assertEqual(rows[4]["attempt_errors"], [["JSON としてパースできない: JSON が見つからない"]] * 2)
        self.assertEqual({r["prompt_version"] for r in rows}, {"classify.fixed/v2"})
        self.assertNotIn('"text"', files[0].read_text(encoding="utf-8"))


class TestPolicy(Base):
    def labels_run(self, *extra):
        return self.run_main(["run", "--type", "classify.fixed", "--labels", str(self.dir / "labels.json"),
                              "--text", "x", *extra])

    def policy_file(self):
        return self.dir / "home" / "delegation_policy.yaml"

    def test_set_show_and_history(self):
        code, out, _ = self.run_main(["policy", "set", "classify.fixed", "--state", "stopped", "--reason", "精度不足",
                                      "--evidence", "bench-a.jsonl", "--evidence", "bench-b.jsonl"])
        self.assertEqual(code, 0, out)
        self.assertEqual(json.loads(out)["state"], "stopped")
        text = self.policy_file().read_text(encoding="utf-8")
        self.assertTrue(text.startswith("# delegation_policy.yaml"))
        data = json.loads("".join(l for l in text.splitlines(keepends=True) if not l.startswith("#")))
        e = data["policies"]["classify.fixed"]["*"]
        self.assertEqual((e["state"], e["reason"], e["evidence"], e["decided_by"]),
                         ("stopped", "精度不足", ["bench-a.jsonl", "bench-b.jsonl"], "test"))
        self.run_main(["policy", "set", "classify.fixed", "--state", "trial", "--reason", "再計測"])
        hist = ld.load_policy()["history"]
        self.assertEqual([(h["from"], h["to"]) for h in hist], [(None, "stopped"), ("stopped", "trial")])
        code, out, _ = self.run_main(["policy", "show"])
        self.assertEqual(code, 0)
        self.assertIn("state=trial", out)
        self.assertIn("reason: 再計測", out)

    def test_show_without_file(self):
        code, out, _ = self.run_main(["policy", "show"])
        self.assertEqual(code, 0)
        self.assertIn("決定なし", out)
        self.assertFalse(self.policy_file().exists())

    def test_run_skipped_when_stopped(self):
        self.run_main(["policy", "set", "classify.fixed", "--state", "stopped", "--reason", "精度不足"])
        code, out, _ = self.labels_run()
        self.assertEqual(code, 3, out)
        self.assertEqual(json.loads(out)["skip_reason"], "policy_stopped")
        self.assertEqual(self.fake.requests, [])
        self.assertEqual(self.ledger()[-1]["skip_reason"], "policy_stopped")
        # 別の種別には影響しない
        self.fake.replies = ['{"name": "山田太郎", "date": null}']
        code, out, _ = self.run_main(["run", "--type", "extract.struct", "--schema", str(self.dir / "schema.json"),
                                      "--text", "山田太郎が来た"])
        self.assertEqual(code, 0, out)

    def test_model_specific_overrides_wildcard(self):
        self.run_main(["policy", "set", "classify.fixed", "--state", "stopped", "--reason", "x", "--model", "other:1b"])
        self.fake.replies = ['[{"id": "1", "label": "犬"}]']
        self.assertEqual(self.labels_run()[0], 0)
        self.run_main(["policy", "set", "classify.fixed", "--state", "stopped", "--reason", "x"])
        self.run_main(["policy", "set", "classify.fixed", "--state", "allowed", "--reason", "y", "--model", "qwen3:4b"])
        self.fake.replies = ['[{"id": "1", "label": "犬"}]']
        self.assertEqual(self.labels_run()[0], 0)

    def test_unreadable_policy(self):
        self.policy_file().parent.mkdir(parents=True, exist_ok=True)
        self.policy_file().write_text("policies: [壊れている", encoding="utf-8")
        code, out, _ = self.labels_run()
        self.assertEqual(code, 3)
        self.assertEqual(json.loads(out)["skip_reason"], "policy_unreadable")
        self.assertEqual(self.fake.requests, [])
        code, _, err = self.run_main(["policy", "show"])
        self.assertEqual(code, 2)
        self.assertIn("ポリシーを読めない", err)

    def test_set_errors(self):
        code, _, err = self.run_main(["policy", "set", "classify.fixed", "--state", "stopped", "--reason", "  "])
        self.assertEqual(code, 2)
        self.assertIn("--reason", err)
        code, _, err = self.run_main(["policy", "set", "code.trivial", "--state", "stopped", "--reason", "x"])
        self.assertEqual(code, 2)
        self.assertFalse(self.policy_file().exists())
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stderr(io.StringIO()):
                ld.main(["policy", "set", "classify.fixed", "--state", "maybe", "--reason", "x"])

    def test_sla_state(self):
        self.assertEqual(ld.sla_state(19, 19), "trial")      # n<20
        self.assertEqual(ld.sla_state(34, 34), "trial")      # 全件成功でも下限 0.8985
        self.assertEqual(ld.sla_state(35, 35), "allowed")    # 下限 0.901
        self.assertEqual(ld.sla_state(39, 40), "trial")      # 下限 0.871
        self.assertEqual(ld.sla_state(18, 20), "trial")      # 下限 0.699
        self.assertEqual(ld.sla_state(16, 20), "stopped")    # 下限 0.584


class TestBenchExtract(Base):
    def golden(self, items):
        g = {"task_type": "extract.struct", "schemas": {"person": SCHEMA},
             "instructions": {"person": "人名と日付を抜き出す"}, "items": items}
        p = self.dir / "golden_extract.json"
        p.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
        return str(p)

    def test_scoring_and_policy_ignored(self):
        self.run_main(["policy", "set", "extract.struct", "--state", "stopped", "--reason", "x"])
        inline = {"type": "object", "required": ["city"], "properties": {"city": {"type": "string"}}}
        gp = self.golden([
            {"id": "e1", "schema": "person", "text": "山田太郎が2026年10月6日に来た",
             "expected": {"name": "山田太郎", "date": "2026年10月6日"}},
            {"id": "e2", "schema": "person", "text": "山田太郎と鈴木花子が来た",
             "expected": {"name": "山田太郎", "date": None}},
            {"id": "e3", "schema": "person", "text": "誰も来ない", "expected": {"name": "誰", "date": None}},
            {"id": "e4", "schema": inline, "text": "東京へ行く", "expected": {"city": "東京"}},
        ])
        self.fake.replies = ['{"name": "山田太郎", "date": "2026年10月6日"}',
                             '{"name": "鈴木花子", "date": null}',
                             '{"name": "佐藤"}', '{"name": "佐藤"}',
                             '{"city": "東京"}']
        code, out, _ = self.run_main(["bench", "--golden", gp, "--model", "qwen3:4b"])
        self.assertEqual(code, 0, out)
        self.assertIn("task_type=extract.struct", out)
        self.assertIn("抽出: 2/4 PASS (50.0%)", out)
        self.assertIn("完全一致(exact)          : 2", out)
        self.assertIn("値の違い(mismatch)       : 1", out)
        self.assertIn("検証失敗(invalid)        : 1", out)
        self.assertIn("フィールド正解率         : 4/7", out)
        self.assertIn("値が違ったフィールド     : {'name': 1}", out)
        self.assertIn("Wilson下限(95%)          : 0.150", out)
        self.assertIn("SLA判定                  : trial", out)
        self.assertEqual(len(self.fake.requests), 5)  # stopped でも bench は推論する
        self.assertIn("人名と日付を抜き出す", self.fake.requests[0]["messages"][1]["content"])
        self.assertEqual(self.ledger(), [])
        rows = [json.loads(x) for x in next((self.dir / "home" / "bench").glob("*extract.struct*.jsonl"))
                .read_text(encoding="utf-8").splitlines()]
        self.assertEqual([r["kind"] for r in rows], ["exact", "mismatch", "invalid", "exact"])
        self.assertEqual(rows[1]["diff_fields"], ["name"])
        self.assertEqual((rows[0]["schema"], rows[3]["schema"]), ("person", None))

    def test_golden_validation(self):
        gp = self.golden([{"id": "e1", "schema": "nope", "text": "x", "expected": {"name": "x"}}])
        code, _, err = self.run_main(["bench", "--golden", gp])
        self.assertEqual(code, 2)
        self.assertIn("スキーマが見つからない", err)
        gp = self.golden([{"id": "e1", "schema": "person", "text": "x"}])
        code, _, err = self.run_main(["bench", "--golden", gp])
        self.assertEqual(code, 2)
        self.assertIn("expected", err)
        self.assertEqual(self.fake.requests, [])


class TestCli(Base):
    def test_script_runs_as_command(self):
        res = subprocess.run([sys.executable, str(SCRIPT), "stats"], capture_output=True, text=True,
                             env={**os.environ})
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("ledger:", res.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
