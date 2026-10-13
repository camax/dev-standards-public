#!/usr/bin/env bash
# scripts/local_delegate.py のテスト（本体は tests/test_local_delegate.py。偽の Ollama を使い、本物には接続しない）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -x "$SCRIPT_DIR/../scripts/local_delegate.py" ] || { echo "Error: scripts/local_delegate.py が無いか実行権限がない" >&2; exit 1; }

python3 "$SCRIPT_DIR/test_local_delegate.py"
