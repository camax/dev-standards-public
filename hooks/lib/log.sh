#!/usr/bin/env bash
log_record() {
    local hook="$1"
    local check="$2"
    local result="$3"
    local detail="$4"

    local ts
    ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    local repo
    repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
    local agent="${HARNESS_AGENT:-unknown}"
    
    local host="${HARNESS_HOST:-$(hostname -s)}"
    
    local detail_esc
    detail_esc=$(echo "$detail" | sed 's/"/\\"/g' | tr '\n' ' ')

    local log_dir="$HOME/.harness-log"
    mkdir -p "$log_dir" 2>/dev/null || true
    local log_file="$log_dir/$(date +'%Y-%m').jsonl"
    
    local json="{\"ts\":\"$ts\",\"repo\":\"$repo\",\"hook\":\"$hook\",\"check\":\"$check\",\"result\":\"$result\",\"agent\":\"$agent\",\"detail\":\"$detail_esc\",\"host\":\"$host\"}"
    echo "$json" >> "$log_file" 2>/dev/null || true
}
