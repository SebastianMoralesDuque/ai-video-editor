#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PYTHONPATH="$ROOT_DIR/src"

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-7860}"

# Resolve Ollama host IP: use env var, or auto-detect Docker gateway
if [ -z "$OLLAMA_HOST" ]; then
  # Try host.docker.internal first (works on Docker Desktop / Mac / Windows)
  if getent hosts host.docker.internal > /dev/null 2>&1; then
    OLLAMA_HOST="host.docker.internal"
  else
    # Linux Docker: use the default gateway from ip route
    OLLAMA_HOST=$(ip route show default 2>/dev/null | awk '/default/ {print $3}' | head -1)
    # Fallback to common Docker bridge gateway
    if [ -z "$OLLAMA_HOST" ]; then
      OLLAMA_HOST="172.17.0.1"
    fi
  fi
fi

# Auto-build base URLs if not explicitly set
if [ -z "$LLM_BASE_URL" ]; then
  LLM_BASE_URL="http://${OLLAMA_HOST}:11434/v1"
fi
if [ -z "$VLM_BASE_URL" ]; then
  VLM_BASE_URL="http://${OLLAMA_HOST}:11434/v1"
fi

export LLM_BASE_URL VLM_BASE_URL

echo "=== Ollama Configuration ==="
echo "OLLAMA_HOST: ${OLLAMA_HOST}"
echo "LLM_BASE_URL: ${LLM_BASE_URL}"
echo "VLM_BASE_URL: ${VLM_BASE_URL}"
echo "==========================="

# Inject Ollama config from environment variables into config.toml
if [ -n "$LLM_MODEL" ] || [ -n "$VLM_MODEL" ]; then
  python3 -c "
import tomllib, re, os

path = '$ROOT_DIR/config.toml'
with open(path, 'r') as f:
    content = f.read()

def replace_val(section, key, value):
    global content
    pattern = rf'^({key}\s*=\s*)\"[^\"]*\"'
    repl = rf'\1\"{value}\"'
    content = re.sub(pattern, repl, content, count=1, flags=re.MULTILINE)

replace_val('llm', 'model', os.getenv('LLM_MODEL', ''))
replace_val('llm', 'base_url', os.getenv('LLM_BASE_URL', ''))
replace_val('llm', 'api_key', os.getenv('LLM_API_KEY', ''))
replace_val('llm', 'timeout', os.getenv('LLM_TIMEOUT', '300.0'))
replace_val('vlm', 'model', os.getenv('VLM_MODEL', ''))
replace_val('vlm', 'base_url', os.getenv('VLM_BASE_URL', ''))
replace_val('vlm', 'api_key', os.getenv('VLM_API_KEY', ''))
replace_val('vlm', 'timeout', os.getenv('VLM_TIMEOUT', '600.0'))

with open(path, 'w') as f:
    f.write(content)
print('Config injected from environment variables')
"
fi

python -m open_storyline.mcp.server &
MCP_PID=$!

uvicorn agent_fastapi:app \
  --host "$HOST" \
  --port "$PORT" &
WEB_PID=$!

trap 'kill $MCP_PID $WEB_PID' INT TERM

wait
