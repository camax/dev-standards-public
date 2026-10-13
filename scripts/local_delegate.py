#!/usr/bin/env python3
"""local_delegate.py — 単純タスクをローカルLLM（Ollama）へ委譲し、検証して台帳に記録する（Phase 1）。

対象種別は classify.fixed（固定ラベル分類）と extract.struct（自由文 → JSON）の2つだけ。
委譲に使うモデルは qwen3:4b 固定。bench だけは --model で計測対象を変えられる（台帳には書かない）。

Ollama の設定・環境変数・Modelfile には触れない。渡すのはリクエスト単位のオプション
（num_ctx / num_predict / temperature / think）だけ。標準ライブラリのみで動く。

使い方:
  local_delegate.py run --type classify.fixed --labels labels.json (--input items.jsonl | --text TEXT)
  local_delegate.py run --type extract.struct --schema schema.json (--input text.txt | --text TEXT)
  local_delegate.py review <id> --result adopted|rejected|not_sampled [--redo] [--note TEXT]
  local_delegate.py stats [--json]
  local_delegate.py bench --golden golden.json [--model M] [--think false|true|omit] [--limit N]
  local_delegate.py policy show [--json]
  local_delegate.py policy set <task_type> --state trial|allowed|stopped --reason TEXT [--model M] [--evidence E]

委譲ポリシー（~/.local-delegate/delegation_policy.yaml）:
  run は、その種別・モデルのポリシーが stopped なら Ollama に接続せず skip する（skip_reason=policy_stopped）。
  決定が無い種別は trial として委譲する。bench は計測のためポリシーに関係なく実行する。
  bench は SLA 判定（n≥20 かつ Wilson 下限≥0.9 で allowed、下限<0.6 で stopped）を表示する。反映は policy set で行う。

検証:
  L0（構造）: JSON としてパースでき、classify は [{id, label}] の形、extract はスキーマ（部分集合）に合う
  L1（範囲）: コード編集を伴わないので Phase 1 では対象外（台帳には "n/a" と記録）
  L2（意味）: classify は件数・id の一致とラベル集合、extract は文字列値が原文の部分文字列か
  失敗したら検証エラーを添えて1回だけ再試行する。それでも失敗なら outcome=failed を返す。

終了コード: 0=passed, 1=failed, 2=使い方の誤り, 3=skipped（委譲せず。呼び出し側が自分で実行する）

環境変数:
  LOCAL_DELEGATE_HOME            台帳・ポリシーなどの置き場（既定 ~/.local-delegate）
  LOCAL_DELEGATE_ENDPOINT        Ollama の URL（既定は OLLAMA_HOST、無ければ http://127.0.0.1:11434）
  LOCAL_DELEGATE_BLACKOUT        推論しない時間帯（既定 "10:55-11:10"。日次RAGと重ねない。空文字で無効）
  LOCAL_DELEGATE_MIN_AVAILABLE_GB  モデル未ロード時に必要な空きメモリ（既定 4）
  LOCAL_DELEGATE_AGENT           台帳の agent 欄（既定 unknown）
"""

import argparse
import datetime
import fcntl
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

MODEL = "qwen3:4b"
TASK_TYPES = ("classify.fixed", "extract.struct")
# classify.fixed/v2: v1 は出力例で null を引用符の内側に書いていたため、文字列 "null" を返すモデルがあった（2026-10-06）
PROMPT_VERSIONS = {"classify.fixed": "classify.fixed/v2", "extract.struct": "extract.struct/v1"}
# qwen3:4b は Qwen3 4B Thinking 2507。think:false を無視し、開始タグなしの思考を本文に書き出して
# num_predict で打ち切られる（2026-10-06 実測）。そのため既定は think:true とし、思考の分も含めて枠を取る。
DEFAULT_THINK = "true"
DEFAULT_NUM_CTX = 8192
DEFAULT_NUM_PREDICT = 4096
DEFAULT_TIMEOUT_S = 120
MAX_INPUT_CHARS = 3000
DEFAULT_BLACKOUT = "10:55-11:10"
DEFAULT_MIN_AVAILABLE_GB = 4.0

EXIT_PASSED, EXIT_FAILED, EXIT_USAGE, EXIT_SKIPPED = 0, 1, 2, 3

# 委譲ポリシー（設計案 2.4）。種別×モデルごとに trial / allowed / stopped を持ち、run は stopped なら委譲しない。
# 判定基準は成功率の Wilson 下限（95%）。全件成功でも n/(n+1.96²) なので、n<35 では 0.9 に届かない。
POLICY_STATES = ("trial", "allowed", "stopped")
SLA_ALLOWED_WILSON = 0.9
SLA_STOPPED_WILSON = 0.6
SLA_MIN_N = 20
POLICY_HEADER = ("# delegation_policy.yaml — local_delegate.py の委譲ポリシー。\n"
                 "# 中身は JSON（YAML 1.2 のサブセット）。手で編集せず `local_delegate.py policy set` で更新する。\n")


class UsageError(Exception):
    pass


# ---------------------------------------------------------------- 環境

def home_dir():
    return Path(os.environ.get("LOCAL_DELEGATE_HOME") or Path.home() / ".local-delegate")


def ledger_path():
    return home_dir() / "ledger.jsonl"


def policy_path():
    return home_dir() / "delegation_policy.yaml"


def endpoint():
    ep = os.environ.get("LOCAL_DELEGATE_ENDPOINT") or os.environ.get("OLLAMA_HOST") or "127.0.0.1:11434"
    if not ep.startswith(("http://", "https://")):
        ep = "http://" + ep
    return ep.rstrip("/")


def now():
    return datetime.datetime.now().astimezone()


def parse_blackout(spec):
    """"HH:MM-HH:MM[,HH:MM-HH:MM]" を [(start, end), ...] にする。空文字は空リスト。"""
    windows = []
    for part in (spec or "").split(","):
        part = part.strip()
        if not part:
            continue
        m = re.fullmatch(r"(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})", part)
        if not m:
            raise UsageError(f"LOCAL_DELEGATE_BLACKOUT の形式が不正: {part}")
        h1, m1, h2, m2 = map(int, m.groups())
        windows.append((datetime.time(h1, m1), datetime.time(h2, m2)))
    return windows


def in_blackout(t, windows):
    for start, end in windows:
        if start <= end:
            if start <= t < end:
                return True
        elif t >= start or t < end:  # 日付をまたぐ窓
            return True
    return False


def blackout_windows():
    return parse_blackout(os.environ.get("LOCAL_DELEGATE_BLACKOUT", DEFAULT_BLACKOUT))


def available_memory_gb():
    """macOS の vm_stat から free + inactive + speculative を GB で返す。取れなければ None。"""
    try:
        out = subprocess.run(["vm_stat"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r"page size of (\d+) bytes", out)
    if not m:
        return None
    page = int(m.group(1))
    pages = 0
    for key in ("Pages free", "Pages inactive", "Pages speculative"):
        km = re.search(re.escape(key) + r":\s+(\d+)", out)
        if km:
            pages += int(km.group(1))
    return pages * page / 1024 ** 3


# ---------------------------------------------------------------- Ollama

def http_json(method, path, payload=None, timeout=10):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(endpoint() + path, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return json.loads(res.read().decode("utf-8"))


def model_digest(model):
    for m in http_json("GET", "/api/tags", timeout=5).get("models", []):
        if m.get("name") == model or m.get("model") == model:
            return m.get("digest")
    return None


def model_loaded(model):
    try:
        return any(m.get("name") == model or m.get("model") == model
                   for m in http_json("GET", "/api/ps", timeout=5).get("models", []))
    except (OSError, ValueError):
        return False


def chat(model, messages, think, num_ctx, num_predict, timeout):
    payload = {
        "model": model,
        "messages": messages,
        "stream": False,
        "options": {"temperature": 0, "num_ctx": num_ctx, "num_predict": num_predict},
    }
    if think is not None:
        payload["think"] = think
    # format:"json" は付けない（Qwen3 Thinking で GBNF 衝突により HTTP 500 になった実績がある）
    return http_json("POST", "/api/chat", payload, timeout=timeout)


# ---------------------------------------------------------------- 出力のパース

def parse_json_output(text):
    """モデル出力から最初の JSON 値を取り出す。<think> とコードフェンスは除く。失敗時は ValueError。"""
    text = re.sub(r"<think>.*?</think>", "", text or "", flags=re.DOTALL)
    if "</think>" in text:  # 開始タグなしで思考が本文に出た場合は、最後の閉じタグより後だけを見る
        text = text.rsplit("</think>", 1)[1]
    text = text.strip()
    fence = re.search(r"```(?:json)?\s*(.*?)```", text, flags=re.DOTALL)
    if fence:
        text = fence.group(1).strip()
    try:
        return json.loads(text)
    except ValueError:
        pass
    decoder = json.JSONDecoder()
    for i, ch in enumerate(text):
        if ch in "[{":
            try:
                return decoder.raw_decode(text, i)[0]
            except ValueError:
                continue
    raise ValueError("JSON が見つからない")


# ---------------------------------------------------------------- classify.fixed

def load_labels(path):
    try:
        spec = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise UsageError(f"ラベル定義を読めない: {path}: {e}")
    labels = spec.get("labels") if isinstance(spec, dict) else None
    if not labels or not isinstance(labels, list):
        raise UsageError("ラベル定義には labels（{name, description} の配列）が必要")
    names = [lb.get("name") if isinstance(lb, dict) else None for lb in labels]
    if not all(isinstance(n, str) and n for n in names) or len(set(names)) != len(names):
        raise UsageError("labels の name は重複のない文字列にする")
    return {
        "labels": [{"name": lb["name"], "description": lb.get("description", "")} for lb in labels],
        "allow_null": bool(spec.get("allow_null", False)),
        "null_description": spec.get("null_description", "どのラベルにも当てはまらない"),
    }


def classify_messages(spec, items, instructions):
    lines = [f"- {lb['name']}: {lb['description']}" for lb in spec["labels"]]
    if spec["allow_null"]:
        lines.append(f"- null: {spec['null_description']}")
    label_value = '"<ラベル名>"' + (" または null" if spec["allow_null"] else "")
    label_rule = "label は上のラベル名のどれか1つを文字列で書く。"
    if spec["allow_null"]:
        label_rule += 'どれにも当てはまらない場合は、引用符を付けない JSON の null にする（文字列の "null" は不可）。'
    user = (
        (instructions + "\n\n" if instructions else "")
        + "ラベル一覧:\n" + "\n".join(lines) + "\n\n"
        + "出力形式（入力と同じ件数・同じ id・同じ順番にする）:\n"
        + f'[{{"id": "<入力の id>", "label": {label_value}, "reason": "<30字以内の理由>"}}]\n'
        + label_rule + "\n\n"
        + "入力:\n" + json.dumps(items, ensure_ascii=False)
    )
    system = ("あなたは固定ラベル分類器です。各項目を、指定されたラベルのうち最も当てはまる1つに分類します。"
              "出力は JSON 配列だけにし、説明文やコードブロックは書きません。")
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


def verify_classify(parsed, spec, items):
    """(L0 エラー, L2 エラー, 正規化した出力) を返す。"""
    if isinstance(parsed, dict) and "id" in parsed:
        parsed = [parsed]
    if not isinstance(parsed, list):
        return ["JSON 配列ではない"], [], None
    l0, out = [], []
    for i, row in enumerate(parsed):
        if not isinstance(row, dict) or "id" not in row or "label" not in row:
            l0.append(f"[{i}] に id と label がない")
            continue
        label = row["label"]
        if label is not None and not isinstance(label, str):
            l0.append(f"[{i}] label が文字列でも null でもない")
            continue
        out.append({"id": str(row["id"]), "label": label, "reason": row.get("reason")})
    if l0:
        return l0, [], None
    l2 = []
    if len(out) != len(items):
        l2.append(f"件数が一致しない: 入力 {len(items)} 件、出力 {len(out)} 件")
    in_ids = [it["id"] for it in items]
    out_ids = [r["id"] for r in out]
    if len(set(out_ids)) != len(out_ids):
        l2.append("出力の id が重複している")
    if set(out_ids) != set(in_ids):
        l2.append(f"id が一致しない: 不足 {sorted(set(in_ids) - set(out_ids))}、余分 {sorted(set(out_ids) - set(in_ids))}")
    names = {lb["name"] for lb in spec["labels"]}
    for r in out:
        if r["label"] is None:
            if not spec["allow_null"]:
                l2.append(f"id={r['id']}: null は許可されていない")
        elif r["label"] not in names:
            l2.append(f"id={r['id']}: ラベル集合にない値 {r['label']!r}")
    return [], l2, out


# ---------------------------------------------------------------- extract.struct

def load_schema(path):
    try:
        schema = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise UsageError(f"スキーマを読めない: {path}: {e}")
    if not isinstance(schema, dict) or schema.get("type") != "object":
        raise UsageError("スキーマの最上位は type: object にする")
    return schema


_TYPE_CHECKS = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "boolean": lambda v: isinstance(v, bool),
    "null": lambda v: v is None,
}


def schema_errors(value, schema, path="$"):
    """JSON Schema の部分集合（type, enum, required, properties, additionalProperties:false, items）で検証する。"""
    t = schema.get("type")
    if t is not None:
        types = t if isinstance(t, list) else [t]
        if not any(_TYPE_CHECKS.get(x, lambda v: False)(value) for x in types):
            return [f"{path}: 型が {types} ではない"]
    errors = []
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: enum {schema['enum']} にない値")
    if isinstance(value, dict):
        props = schema.get("properties", {})
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}: 必須キー {key} がない")
        for key, sub in value.items():
            if key in props:
                errors += schema_errors(sub, props[key], f"{path}.{key}")
            elif schema.get("additionalProperties") is False:
                errors.append(f"{path}: 未定義のキー {key}")
    if isinstance(value, list) and isinstance(schema.get("items"), dict):
        for i, sub in enumerate(value):
            errors += schema_errors(sub, schema["items"], f"{path}[{i}]")
    return errors


def verbatim_errors(value, schema, source, path="$"):
    """文字列値（x-verbatim:false 以外）と x-verbatim:true の数値が原文の部分文字列かを調べる。"""
    errors = []
    if isinstance(value, str):
        if schema.get("x-verbatim", True) and value not in source:
            errors.append(f"{path}: 原文にない文字列 {value!r}")
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        if schema.get("x-verbatim") is True:
            rep = str(int(value)) if float(value).is_integer() else str(value)
            if rep not in source:
                errors.append(f"{path}: 原文にない数値 {rep}")
    elif isinstance(value, dict):
        props = schema.get("properties", {})
        for key, sub in value.items():
            errors += verbatim_errors(sub, props.get(key, {}), source, f"{path}.{key}")
    elif isinstance(value, list):
        items = schema.get("items") if isinstance(schema.get("items"), dict) else {}
        for i, sub in enumerate(value):
            errors += verbatim_errors(sub, items, source, f"{path}[{i}]")
    return errors


def extract_messages(schema, text, instructions):
    system = ("あなたは情報抽出器です。入力テキストから、JSON Schema に従う JSON オブジェクトを1つだけ出力します。"
              "文字列の値は入力テキストからそのまま抜き出し、言い換え・要約・補完をしません。"
              "該当がない項目はスキーマが許す場合 null にします。説明文やコードブロックは書きません。")
    user = ((instructions + "\n\n" if instructions else "")
            + "JSON Schema:\n" + json.dumps(schema, ensure_ascii=False) + "\n\n"
            + "入力テキスト:\n<<<\n" + text + "\n>>>")
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


def verify_extract(parsed, schema, text):
    l0 = schema_errors(parsed, schema)
    if l0:
        return l0, [], None
    return [], verbatim_errors(parsed, schema, text), parsed


# ---------------------------------------------------------------- 委譲の本体

def input_hash(task_type, spec, payload):
    blob = json.dumps({"task_type": task_type, "spec": spec, "input": payload},
                      ensure_ascii=False, sort_keys=True)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def load_policy():
    """委譲ポリシーを読む。ファイルが無ければ空のポリシー。壊れていれば ValueError。"""
    path = policy_path()
    if not path.exists():
        return {"version": 1, "policies": {}, "history": []}
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    data = json.loads("".join(line for line in lines if not line.startswith("#")))
    if not isinstance(data, dict) or not isinstance(data.get("policies"), dict):
        raise ValueError("policies がない")
    data.setdefault("history", [])
    return data


def save_policy(data):
    path = policy_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(POLICY_HEADER + json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def policy_entry(policy, task_type, model):
    """モデル個別の決定を優先し、無ければ全モデル（"*"）の決定を返す。どちらも無ければ None（trial 扱い）。"""
    entries = policy["policies"].get(task_type, {})
    return entries.get(model) or entries.get("*")


def sla_state(passed, n):
    """ゴールデンセットや台帳の成功数から、SLA 基準に照らした状態を返す。"""
    if n < SLA_MIN_N:
        return "trial"
    lb = wilson_lower(passed, n)
    if lb >= SLA_ALLOWED_WILSON:
        return "allowed"
    if lb < SLA_STOPPED_WILSON:
        return "stopped"
    return "trial"


def preflight(model, input_chars, check_time=True, task_type=None):
    """委譲してよいかを調べる。だめなら skip 理由の文字列、良ければ None。task_type があればポリシーも見る。"""
    if check_time and in_blackout(now().time(), blackout_windows()):
        return "blackout_window"
    if task_type is not None:
        try:
            entry = policy_entry(load_policy(), task_type, model)
        except (OSError, ValueError):
            return "policy_unreadable"
        if entry and entry.get("state") == "stopped":
            return "policy_stopped"
    if input_chars > MAX_INPUT_CHARS:
        return "input_too_large"
    try:
        http_json("GET", "/api/version", timeout=3)
    except (OSError, ValueError):
        return "ollama_unavailable"
    try:
        if model_digest(model) is None:
            return "model_not_installed"
    except (OSError, ValueError):
        return "ollama_unavailable"
    if not model_loaded(model):
        need = float(os.environ.get("LOCAL_DELEGATE_MIN_AVAILABLE_GB", DEFAULT_MIN_AVAILABLE_GB))
        avail = available_memory_gb()
        if avail is not None and avail < need:
            return "low_memory"
    return None


def delegate(task_type, spec, payload, *, model=MODEL, instructions="", think=True,
             num_ctx=DEFAULT_NUM_CTX, num_predict=DEFAULT_NUM_PREDICT, timeout=DEFAULT_TIMEOUT_S,
             check_time=True, check_policy=True):
    """1回の委譲を実行し、台帳に書く内容（record）と出力を返す。台帳への書き込みは呼び出し側。

    payload: classify.fixed は [{id, text}]、extract.struct は原文の文字列。
    check_policy=False は bench 用（ポリシーを決めるための計測なので、stopped でも推論する）。
    """
    if task_type == "classify.fixed":
        input_chars = sum(len(it["text"]) for it in payload)
        messages = classify_messages(spec, payload, instructions)
        verify = lambda parsed: verify_classify(parsed, spec, payload)  # noqa: E731
        n_items = len(payload)
    else:
        input_chars = len(payload)
        messages = extract_messages(spec, payload, instructions)
        verify = lambda parsed: verify_extract(parsed, spec, payload)  # noqa: E731
        n_items = 1

    record = {
        "event": "delegation",
        "id": uuid.uuid4().hex,
        "ts": now().isoformat(timespec="seconds"),
        "agent": os.environ.get("LOCAL_DELEGATE_AGENT", "unknown"),
        "project": Path.cwd().name,
        "task_type": task_type,
        "model_id": model,
        "model_digest": None,
        "prompt_version": PROMPT_VERSIONS[task_type],
        "input_hash": input_hash(task_type, spec, payload),
        "input_items": n_items,
        "input_chars": input_chars,
        "think": think,
        "num_ctx": num_ctx,
        "input_tokens": 0,
        "output_tokens": 0,
        "load_ms": 0,
        "latency_ms": 0,
        "thinking_chars": 0,
        "truncated": False,
        "verify_L0": None,
        "verify_L1": "n/a",
        "verify_L2": None,
        "verify_errors": [],
        "attempt_errors": [],
        "retries": 0,
        "outcome": None,
        "fail_layer": None,
        "skip_reason": None,
        "main_review": None,
        "main_redo": None,
    }

    reason = preflight(model, input_chars, check_time=check_time,
                       task_type=task_type if check_policy else None)
    if reason:
        record.update(outcome="skipped", skip_reason=reason)
        return record, None
    try:
        record["model_digest"] = model_digest(model)
    except (OSError, ValueError):
        pass

    started = time.monotonic()
    output = None
    for attempt in range(2):
        record["retries"] = attempt
        try:
            res = chat(model, messages, think, num_ctx, num_predict, timeout)
        except (OSError, ValueError) as e:
            record.update(outcome="failed", fail_layer="infer", verify_errors=[f"推論エラー: {e}"])
            record["attempt_errors"].append(record["verify_errors"])
            break
        record["input_tokens"] += res.get("prompt_eval_count") or 0
        record["output_tokens"] += res.get("eval_count") or 0
        record["load_ms"] += round((res.get("load_duration") or 0) / 1e6)
        content = (res.get("message") or {}).get("content", "")
        record["thinking_chars"] += len((res.get("message") or {}).get("thinking") or "")
        if res.get("done_reason") == "length":
            record["truncated"] = True
        try:
            parsed = parse_json_output(content)
        except ValueError as e:
            l0, l2, out = [f"JSON としてパースできない: {e}"], [], None
        else:
            l0, l2, out = verify(parsed)
        record["verify_L0"] = "fail" if l0 else "pass"
        record["verify_L2"] = None if l0 else ("fail" if l2 else "pass")
        record["verify_errors"] = l0 + l2
        record["attempt_errors"].append(l0 + l2)
        if not l0 and not l2:
            record.update(outcome="passed", fail_layer=None)
            output = out
            break
        record.update(outcome="failed", fail_layer="L0" if l0 else "L2")
        messages = messages + [
            {"role": "assistant", "content": content},
            {"role": "user", "content": "前回の出力は検証に失敗しました:\n- " + "\n- ".join(l0 + l2)
             + "\n修正した JSON だけを出力してください。"},
        ]
    record["latency_ms"] = round((time.monotonic() - started) * 1000)
    return record, output


# ---------------------------------------------------------------- 台帳

def append_ledger(record):
    path = ledger_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.write(json.dumps(record, ensure_ascii=False) + "\n")
        fcntl.flock(f, fcntl.LOCK_UN)


def read_ledger():
    path = ledger_path()
    if not path.exists():
        return []
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def wilson_lower(passed, n, z=1.96):
    if n == 0:
        return 0.0
    p = passed / n
    denom = 1 + z * z / n
    centre = p + z * z / (2 * n)
    margin = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return (centre - margin) / denom


def compute_stats(rows):
    reviews = {}
    for r in rows:
        if r.get("event") == "review":
            reviews[r["ref"]] = r
    groups = {}
    for r in rows:
        if r.get("event") != "delegation":
            continue
        g = groups.setdefault((r["task_type"], r["model_id"]), {
            "task_type": r["task_type"], "model_id": r["model_id"], "n": 0, "passed": 0, "failed": 0,
            "skipped": 0, "latencies": [], "adopted": 0, "rejected": 0, "redo": 0})
        g["n"] += 1
        g[r["outcome"]] += 1
        if r["outcome"] != "skipped":
            g["latencies"].append(r["latency_ms"])
        rv = reviews.get(r["id"])
        if rv:
            if rv["main_review"] in ("adopted", "rejected"):
                g[rv["main_review"]] += 1
            if rv.get("main_redo"):
                g["redo"] += 1
    result = []
    for g in groups.values():
        attempted = g["passed"] + g["failed"]
        lat = g.pop("latencies")
        g["pass_rate"] = round(g["passed"] / attempted, 3) if attempted else None
        g["wilson_lower"] = round(wilson_lower(g["passed"], attempted), 3) if attempted else None
        g["avg_latency_ms"] = round(sum(lat) / len(lat)) if lat else None
        result.append(g)
    return sorted(result, key=lambda g: (g["task_type"], g["model_id"]))


# ---------------------------------------------------------------- コマンド

def read_payload(args):
    if args.type == "classify.fixed":
        if args.text is not None:
            return [{"id": "1", "text": args.text}]
        items = []
        try:
            lines = Path(args.input).read_text(encoding="utf-8").splitlines()
        except OSError as e:
            raise UsageError(f"入力を読めない: {e}")
        for n, line in enumerate(lines, 1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except ValueError:
                raise UsageError(f"{args.input}:{n} が JSON ではない")
            if not isinstance(row, dict) or not isinstance(row.get("text"), str):
                raise UsageError(f"{args.input}:{n} に text がない")
            items.append({"id": str(row.get("id", n)), "text": row["text"]})
        if not items:
            raise UsageError("入力が空")
        if len({it["id"] for it in items}) != len(items):
            raise UsageError("入力の id が重複している")
        return items
    if args.text is not None:
        return args.text
    try:
        return Path(args.input).read_text(encoding="utf-8")
    except OSError as e:
        raise UsageError(f"入力を読めない: {e}")


def think_value(s):
    return {"false": False, "true": True, "omit": None}[s]


def cmd_run(args):
    if args.type == "classify.fixed":
        if not args.labels:
            raise UsageError("classify.fixed には --labels が必要")
        spec = load_labels(args.labels)
    else:
        if not args.schema:
            raise UsageError("extract.struct には --schema が必要")
        spec = load_schema(args.schema)
    if (args.input is None) == (args.text is None):
        raise UsageError("--input と --text のどちらか一方を指定する")
    payload = read_payload(args)
    record, output = delegate(args.type, spec, payload, instructions=args.instructions or "",
                              think=think_value(args.think), num_ctx=args.num_ctx,
                              num_predict=args.num_predict, timeout=args.timeout)
    append_ledger(record)
    print(json.dumps({"id": record["id"], "outcome": record["outcome"], "skip_reason": record["skip_reason"],
                      "fail_layer": record["fail_layer"], "verify_errors": record["verify_errors"],
                      "retries": record["retries"], "latency_ms": record["latency_ms"], "output": output},
                     ensure_ascii=False, indent=2))
    return {"passed": EXIT_PASSED, "failed": EXIT_FAILED, "skipped": EXIT_SKIPPED}[record["outcome"]]


def cmd_review(args):
    ids = {r["id"] for r in read_ledger() if r.get("event") == "delegation"}
    if args.id not in ids:
        raise UsageError(f"台帳に id {args.id} がない")
    record = {"event": "review", "ts": now().isoformat(timespec="seconds"), "ref": args.id,
              "main_review": args.result, "main_redo": args.redo, "note": args.note}
    append_ledger(record)
    print(json.dumps(record, ensure_ascii=False))
    return 0


def cmd_stats(args):
    stats = compute_stats(read_ledger())
    if args.json:
        print(json.dumps(stats, ensure_ascii=False, indent=2))
        return 0
    print(f"ledger: {ledger_path()}")
    print("task_type        model_id     n  passed failed skipped pass_rate wilson_lb avg_ms adopted rejected redo")
    for g in stats:
        print(f"{g['task_type']:<16} {g['model_id']:<10} {g['n']:>3} {g['passed']:>7} {g['failed']:>6} "
              f"{g['skipped']:>7} {str(g['pass_rate']):>9} {str(g['wilson_lower']):>9} "
              f"{str(g['avg_latency_ms']):>6} {g['adopted']:>7} {g['rejected']:>8} {g['redo']:>4}")
    return 0


def score_item(item, actual, valid):
    expected = item.get("expected")
    acceptable = set(item.get("acceptable") or [])
    if not valid:
        return "invalid", False
    if expected is None:
        return ("correct_reject", True) if actual is None else ("false_positive", False)
    if actual is None:
        return "miss", False
    if actual == expected or actual in acceptable:
        return "correct", True
    return "wrong_type", False


def extract_diff(expected, actual, schema):
    """expected と actual で値が違うキーを返す（スキーマの properties と expected のキーの和集合で比べる）。"""
    keys = list(schema.get("properties", {}))
    keys += [k for k in expected if k not in keys]
    return [k for k in keys if expected.get(k) != (actual or {}).get(k)]


def bench_classify(spec, golden, item, args, think):
    record, output = delegate("classify.fixed", spec, [{"id": item["id"], "text": item["text"]}],
                              model=args.model, instructions=golden.get("instructions", ""),
                              think=think, num_ctx=args.num_ctx, num_predict=args.num_predict,
                              timeout=args.timeout, check_time=False, check_policy=False)
    if record["outcome"] == "skipped":
        return None, record
    valid = record["outcome"] == "passed"
    actual = output[0]["label"] if valid else None
    kind, ok = score_item(item, actual, valid)
    row = {"id": item["id"], "expected": item.get("expected"), "acceptable": item.get("acceptable") or [],
           "must_match": bool(item.get("must_match")), "actual": actual, "kind": kind, "passed": ok,
           "reason": output[0].get("reason") if valid else None}
    return row, record


def bench_extract(golden, item, args, think):
    schema = item["_schema"]
    name = item.get("schema") if isinstance(item.get("schema"), str) else None
    instructions = item.get("instructions") or (golden.get("instructions", {}).get(name, "") if name else "")
    record, output = delegate("extract.struct", schema, item["text"], model=args.model,
                              instructions=instructions, think=think, num_ctx=args.num_ctx,
                              num_predict=args.num_predict, timeout=args.timeout,
                              check_time=False, check_policy=False)
    if record["outcome"] == "skipped":
        return None, record
    valid = record["outcome"] == "passed"
    diff = extract_diff(item["expected"], output, schema) if valid else None
    kind = "invalid" if not valid else ("exact" if not diff else "mismatch")
    row = {"id": item["id"], "schema": name,
           "expected": item["expected"], "actual": output, "diff_fields": diff, "kind": kind,
           "passed": kind == "exact"}
    return row, record


def load_golden(path):
    try:
        golden = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise UsageError(f"ゴールデンセットを読めない: {e}")
    if golden.get("task_type") not in TASK_TYPES:
        raise UsageError(f"ゴールデンセットの task_type は {TASK_TYPES} のどれか")
    if golden["task_type"] == "extract.struct":
        schemas = golden.get("schemas", {})
        for item in golden["items"]:
            sch = schemas.get(item.get("schema")) if isinstance(item.get("schema"), str) else item.get("schema")
            if not isinstance(sch, dict) or sch.get("type") != "object":
                raise UsageError(f"{item.get('id')}: スキーマが見つからないか type: object ではない")
            if not isinstance(item.get("expected"), dict):
                raise UsageError(f"{item.get('id')}: expected（正解の JSON オブジェクト）がない")
            item["_schema"] = sch
    return golden


def cmd_bench(args):
    golden = load_golden(args.golden)
    task_type = golden["task_type"]
    items = golden["items"][: args.limit] if args.limit else golden["items"]
    think = think_value(args.think)
    if task_type == "classify.fixed":
        spec = {"labels": golden["labels"], "allow_null": bool(golden.get("allow_null", False)),
                "null_description": golden.get("null_description", "どのラベルにも当てはまらない")}
        run_item = lambda item: bench_classify(spec, golden, item, args, think)  # noqa: E731
    else:
        run_item = lambda item: bench_extract(golden, item, args, think)  # noqa: E731
    stamp = now().strftime("%Y%m%d-%H%M%S")
    out_path = (home_dir() / "bench"
                / f"{stamp}_{task_type}_{args.model.replace(':', '-')}_think-{args.think}.jsonl")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"bench: golden={args.golden} task_type={task_type} model={args.model} think={args.think} "
          f"num_ctx={args.num_ctx} items={len(items)} out={out_path}", flush=True)
    results = []
    with open(out_path, "w", encoding="utf-8") as f:
        for i, item in enumerate(items, 1):
            if in_blackout(now().time(), blackout_windows()):
                print("中断: 推論しない時間帯（LOCAL_DELEGATE_BLACKOUT）に入った", flush=True)
                break
            row, record = run_item(item)
            if row is None:
                print(f"中断: skipped ({record['skip_reason']})", flush=True)
                break
            row.update({"outcome": record["outcome"], "retries": record["retries"],
                        "latency_ms": record["latency_ms"], "input_tokens": record["input_tokens"],
                        "output_tokens": record["output_tokens"], "verify_errors": record["verify_errors"],
                        "attempt_errors": record["attempt_errors"], "prompt_version": record["prompt_version"]})
            results.append(row)
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
            f.flush()
            if task_type == "classify.fixed":
                detail = f"expected={row['expected']} actual={row['actual']}"
            else:
                detail = f"diff={row['diff_fields']}" if row["kind"] == "mismatch" else ""
            print(f"[{i:>2}/{len(items)}] {row['kind']:<14} {row['id']} {detail} "
                  f"retries={row['retries']} {row['latency_ms']}ms", flush=True)
    n = len(results)
    if not n:
        return EXIT_SKIPPED
    count = lambda k: sum(1 for r in results if r["kind"] == k)  # noqa: E731
    passed = sum(1 for r in results if r["passed"])
    if task_type == "classify.fixed":
        print(f"\n分類: {passed}/{n} PASS ({100 * passed / n:.1f}%)")
        print(f"  正解(correct)            : {count('correct')}")
        print(f"  正しく除外(correct_reject): {count('correct_reject')}")
        print(f"  取りこぼし(miss)         : {count('miss')}")
        print(f"  誤検出(false_positive)   : {count('false_positive')}")
        print(f"  型違い(wrong_type)       : {count('wrong_type')}")
        print(f"  検証失敗(invalid)        : {count('invalid')}")
        print(f"  must_match違反           : {sum(1 for r in results if r['must_match'] and not r['passed'])}")
    else:
        print(f"\n抽出: {passed}/{n} PASS ({100 * passed / n:.1f}%)  ※全フィールドが正解と一致した件数")
        print(f"  完全一致(exact)          : {count('exact')}")
        print(f"  値の違い(mismatch)       : {count('mismatch')}")
        print(f"  検証失敗(invalid)        : {count('invalid')}")
        fields_total = sum(len(item_schema_keys(r)) for r in results)
        fields_bad = sum(len(r["diff_fields"]) if r["diff_fields"] is not None else len(item_schema_keys(r))
                         for r in results)
        print(f"  フィールド正解率         : {fields_total - fields_bad}/{fields_total}"
              f" ({100 * (fields_total - fields_bad) / fields_total:.1f}%)  ※検証失敗は全フィールド不正解として数える")
        by_field = {}
        for r in results:
            for k in r["diff_fields"] or []:
                by_field[k] = by_field.get(k, 0) + 1
        print(f"  値が違ったフィールド     : {dict(sorted(by_field.items(), key=lambda kv: -kv[1]))}")
    lb = wilson_lower(passed, n)
    print(f"  Wilson下限(95%)          : {lb:.3f}")
    print(f"  SLA判定                  : {sla_state(passed, n)}  （n≥{SLA_MIN_N} かつ 下限≥{SLA_ALLOWED_WILSON} で allowed、"
          f"下限<{SLA_STOPPED_WILSON} で stopped、それ以外は trial）")
    print(f"  再試行あり               : {sum(1 for r in results if r['retries'])}")
    lat = [r["latency_ms"] for r in results]
    print(f"  レイテンシ ms            : 平均 {round(sum(lat) / n)} / 最小 {min(lat)} / 最大 {max(lat)}")
    print(f"  トークン                 : 入力 {sum(r['input_tokens'] for r in results)} / "
          f"出力 {sum(r['output_tokens'] for r in results)}")
    return EXIT_PASSED


def item_schema_keys(row):
    """フィールド正解率の分母。正解 JSON のキー数で数える。"""
    return list(row["expected"])


def cmd_policy(args):
    try:
        data = load_policy()
    except (OSError, ValueError) as e:
        raise UsageError(f"ポリシーを読めない: {policy_path()}: {e}")
    if args.action == "show":
        if args.json:
            print(json.dumps(data, ensure_ascii=False, indent=2))
            return 0
        print(f"policy: {policy_path()}")
        if not data["policies"]:
            print("（決定なし。すべての種別・モデルを trial として扱う）")
        for task_type, entries in sorted(data["policies"].items()):
            for model, e in sorted(entries.items()):
                print(f"{task_type:<16} model={model:<18} state={e['state']:<8} decided_at={e['decided_at']} "
                      f"by={e.get('decided_by')}\n  reason: {e['reason']}")
                for ev in e.get("evidence") or []:
                    print(f"  evidence: {ev}")
        return 0
    if args.task_type not in TASK_TYPES:
        raise UsageError(f"task_type は {TASK_TYPES} のどれか")
    if not (args.reason or "").strip():
        raise UsageError("--reason（理由）が必要")
    ts = now().isoformat(timespec="seconds")
    entries = data["policies"].setdefault(args.task_type, {})
    prev = entries.get(args.model)
    entry = {"state": args.state, "reason": args.reason, "evidence": args.evidence or [], "decided_at": ts,
             "decided_by": args.decided_by or os.environ.get("LOCAL_DELEGATE_AGENT", "unknown")}
    entries[args.model] = entry
    data["history"].append({"ts": ts, "task_type": args.task_type, "model": args.model,
                            "from": prev["state"] if prev else None, "to": args.state, "reason": args.reason,
                            "evidence": entry["evidence"], "decided_by": entry["decided_by"]})
    data["updated"] = ts
    save_policy(data)
    print(json.dumps({"policy": str(policy_path()), "task_type": args.task_type, "model": args.model, **entry},
                     ensure_ascii=False, indent=2))
    return 0


def build_parser():
    p = argparse.ArgumentParser(prog="local_delegate.py", description="ローカルLLMへの委譲（Phase 1）")
    sub = p.add_subparsers(dest="cmd", required=True)

    def add_infer_opts(sp, num_ctx_default):
        sp.add_argument("--think", choices=["false", "true", "omit"], default=DEFAULT_THINK)
        sp.add_argument("--num-ctx", type=int, default=num_ctx_default)
        sp.add_argument("--num-predict", type=int, default=DEFAULT_NUM_PREDICT)
        sp.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_S)

    r = sub.add_parser("run", help="1件の委譲を実行して台帳に記録する")
    r.add_argument("--type", required=True, choices=TASK_TYPES)
    r.add_argument("--labels", help="classify.fixed のラベル定義 JSON")
    r.add_argument("--schema", help="extract.struct の JSON Schema")
    r.add_argument("--input", help="classify: {id,text} の JSONL / extract: テキストファイル")
    r.add_argument("--text", help="入力を直接渡す（classify は1件）")
    r.add_argument("--instructions", help="プロンプト冒頭に付ける追加指示")
    add_infer_opts(r, DEFAULT_NUM_CTX)

    v = sub.add_parser("review", help="メイン側のレビュー結果を台帳に追記する")
    v.add_argument("id")
    v.add_argument("--result", required=True, choices=["adopted", "rejected", "not_sampled"])
    v.add_argument("--redo", action="store_true", help="メイン側でやり直した")
    v.add_argument("--note")

    s = sub.add_parser("stats", help="台帳を種別×モデルで集計する")
    s.add_argument("--json", action="store_true")

    pp = sub.add_parser("policy", help="委譲ポリシー（trial / allowed / stopped）を表示・設定する")
    psub = pp.add_subparsers(dest="action", required=True)
    ps = psub.add_parser("show")
    ps.add_argument("--json", action="store_true")
    pset = psub.add_parser("set")
    pset.add_argument("task_type")
    pset.add_argument("--state", required=True, choices=POLICY_STATES)
    pset.add_argument("--reason", required=True)
    pset.add_argument("--model", default="*", help="このモデルだけに適用する（既定 * は全モデル）")
    pset.add_argument("--evidence", action="append", help="根拠（bench の結果ファイルなど）。複数指定可")
    pset.add_argument("--decided-by", help="決定者（既定は LOCAL_DELEGATE_AGENT）")

    b = sub.add_parser("bench", help="ゴールデンセットで計測する（台帳には書かない。ポリシーが stopped でも実行する）")
    b.add_argument("--golden", required=True)
    b.add_argument("--model", default=MODEL)
    b.add_argument("--limit", type=int)
    add_infer_opts(b, DEFAULT_NUM_CTX)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        return {"run": cmd_run, "review": cmd_review, "stats": cmd_stats, "bench": cmd_bench,
                "policy": cmd_policy}[args.cmd](args)
    except UsageError as e:
        print(f"Error: {e}", file=sys.stderr)
        return EXIT_USAGE


if __name__ == "__main__":
    sys.exit(main())
