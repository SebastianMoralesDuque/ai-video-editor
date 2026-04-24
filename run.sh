#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PYTHONPATH="$ROOT_DIR/src"

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-7860}"

# ---- Start Ollama Cloud Proxy ----
# The proxy runs on port 11434 inside the container, providing an
# OpenAI-compatible /v1/chat/completions endpoint that forwards to
# Ollama Cloud (https://ollama.com/api/chat).
PROXY_HOST="${PROXY_HOST:-127.0.0.1}"
PROXY_PORT="${PROXY_PORT:-11434}"

if [ -z "$OLLAMA_API_KEY" ]; then
  echo "ERROR: OLLAMA_API_KEY is not set. Get one from https://ollama.com/api"
  exit 1
fi

# Ensure OLLAMA_MODEL is set (used by ollama_cloud_proxy.py)
export OLLAMA_MODEL="${OLLAMA_MODEL:-${LLM_MODEL:-minimax-m2.7:cloud}}"

echo "=== Starting Ollama Cloud Proxy ==="
echo "  OLLAMA_CLOUD_URL: ${OLLAMA_CLOUD_URL:-https://ollama.com}"
echo "  PROXY_HOST: ${PROXY_HOST}"
echo "  PROXY_PORT: ${PROXY_PORT}"
echo "==================================="

PROXY_HOST="$PROXY_HOST" PROXY_PORT="$PROXY_PORT" \
  python3 "$ROOT_DIR/ollama_cloud_proxy.py" &
PROXY_PID=$!

# Wait for proxy to be ready
echo "Waiting for Ollama Cloud proxy to start..."
for i in $(seq 1 30); do
  if curl -s -o /dev/null http://127.0.0.1:${PROXY_PORT}/ 2>/dev/null; then
    echo "Ollama Cloud proxy is ready!"
    break
  fi
  sleep 1
done

# Auto-build base URLs pointing to the local proxy
if [ -z "$LLM_BASE_URL" ]; then
  LLM_BASE_URL="http://127.0.0.1:${PROXY_PORT}/v1"
fi
if [ -z "$VLM_BASE_URL" ]; then
  VLM_BASE_URL="http://127.0.0.1:${PROXY_PORT}/v1"
fi

export LLM_BASE_URL VLM_BASE_URL

echo "=== Ollama Cloud Configuration ==="
echo "LLM_BASE_URL: ${LLM_BASE_URL}"
echo "VLM_BASE_URL: ${VLM_BASE_URL}"
echo "LLM_MODEL: ${LLM_MODEL:-minimax-m2.7:cloud}"
echo "VLM_MODEL: ${VLM_MODEL:-gemma4:31b-cloud}"
echo "==================================="

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
replace_val('llm', 'api_key', os.getenv('LLM_API_KEY', 'ollama'))
replace_val('llm', 'timeout', os.getenv('LLM_TIMEOUT', '300.0'))
replace_val('vlm', 'model', os.getenv('VLM_MODEL', ''))
replace_val('vlm', 'base_url', os.getenv('VLM_BASE_URL', ''))
replace_val('vlm', 'api_key', os.getenv('VLM_API_KEY', 'ollama'))
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

trap 'kill $PROXY_PID $MCP_PID $WEB_PID' INT TERM

wait
