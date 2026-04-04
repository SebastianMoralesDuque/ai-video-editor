# FireRed-OpenStoryline + Ollama - Setup Context

## Machine Info
- **OS**: Ubuntu 22.04 (jammy) ARM64
- **Python**: 3.11.15 (installed via deadsnakes PPA, system default was 3.10.12)
- **Ollama**: Running on `http://localhost:11434` with OpenAI-compatible API at `/v1`
- **ffmpeg**: Installed
- **Architecture**: ARM64 (aarch64) - important for CUDA packages

## Ollama Models Used
| Role | Model | Purpose |
|------|-------|---------|
| LLM | `minimax-m2.7:cloud` | Text generation, scripting, planning |
| VLM | `gemma4:31b-cloud` | Video/image understanding (supports base64 images) |

**Important**: gemma4:31b-cloud does NOT support image URLs, only base64-encoded images. The project's `sampling_handler.py` already converts all images to base64 data URLs, so this works out of the box.

## Project Location
- **Repo**: `/home/ubuntu/FireRed-OpenStoryline`
- **Venv**: `/home/ubuntu/FireRed-OpenStoryline/.venv`
- **Config**: `/home/ubuntu/FireRed-OpenStoryline/config.toml`

## What Was Done

### 1. Python 3.11 Installation
```bash
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update
sudo apt install -y python3.11 python3.11-venv python3.11-dev
```
Also needed: `sudo apt install -y unzip` (for extracting resources)

### 2. Venv & Dependencies
```bash
cd /home/ubuntu/FireRed-OpenStoryline
python3.11 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt
```

**Dependency fix**: `langgraph` had a version conflict. Upgraded from 1.0.10 to 1.1.6:
```bash
.venv/bin/pip install --upgrade langgraph
```
Warning about `langchain 1.2.4 requires langgraph<1.1.0` can be ignored - it works.

**ARM64 warning**: `nvidia-cusparselt-cu13` is not supported on ARM64. Not needed since we use Ollama cloud models, not local GPU inference.

### 3. Download Resources
The `download.sh` script had issues running as a single bash command. Manual steps:
```bash
cd /home/ubuntu/FireRed-OpenStoryline
mkdir -p .storyline resource

# Download and extract models
wget "https://image-url-2-feature-1251524319.cos.ap-shanghai.myqcloud.com/openstoryline/models.zip" -O .storyline/models.zip
unzip -o .storyline/models.zip -d .storyline/models/
rm .storyline/models.zip

# Download and extract resources
wget "https://image-url-2-feature-1251524319.cos.ap-shanghai.myqcloud.com/openstoryline/resource.zip" -O .storyline/resource.zip
unzip -o .storyline/resource.zip -d resource
rm .storyline/resource.zip

# Download web static assets
for f in brand_black.png brand_white.png logo.png dice.png github.png node_map.png user_guide.png; do
    wget "https://image-url-2-feature-1251524319.cos.ap-shanghai.myqcloud.com/zailin/datasets/open_storyline/$f" -O "web/static/$f"
done
```

**Downloaded resources include**:
- TransNetV2 model weights (`.storyline/models/transnetv2-pytorch-weights.pth`)
- Sentence transformer (`.storyline/models/all-MiniLM-L6-v2/`)
- BGMs (`resource/bgms/`)
- Fonts (`resource/fonts/`)
- Web static assets (`web/static/*.png`)

### 4. Config.toml for Ollama
```toml
[llm]
model = "minimax-m2.7:cloud"
base_url = "http://localhost:11434/v1"
api_key = "ollama"
timeout = 300.0
temperature = 0.1
max_retries = 2

[vlm]
model = "gemma4:31b-cloud"
base_url = "http://localhost:11434/v1"
api_key = "ollama"
timeout = 600.0
temperature = 0.1
max_retries = 2
```

**Critical**: The original `config.toml` had a duplicate `[vlm]` section. After setting the Ollama config, the duplicate section was removed. Always check for duplicate sections after editing.

### 5. Starting Services (IMPORTANT - stdin issue)

Services close immediately if stdin is closed. Must use `nohup` with `</dev/null`:

**MCP Server (port 8001)**:
```bash
cd /home/ubuntu/FireRed-OpenStoryline
PYTHONPATH=/home/ubuntu/FireRed-OpenStoryline/src nohup .venv/bin/python -m open_storyline.mcp.server </dev/null > /tmp/mcp_server.log 2>&1 &
disown
```

**Web Server (port 8005)**:
```bash
cd /home/ubuntu/FireRed-OpenStoryline
PYTHONPATH=/home/ubuntu/FireRed-OpenStoryline/src nohup .venv/bin/uvicorn agent_fastapi:app --host 127.0.0.1 --port 8005 </dev/null > /tmp/web_server.log 2>&1 &
disown
```

**Alternative**: Use wrapper scripts (already created):
```bash
nohup /tmp/start_mcp.sh </dev/null > /tmp/mcp_server.log 2>&1 &
nohup /tmp/start_web.sh </dev/null > /tmp/web_server.log 2>&1 &
```

**Verification**:
```bash
# Check processes
ps aux | grep -E "(mcp.server|uvicorn)" | grep -v grep

# Check ports
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8001/mcp  # Should return 406
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8005/    # Should return 200

# Create session
curl -s -X POST "http://127.0.0.1:8005/api/sessions"
```

### 6. Port Conflicts
If ports are in use:
```bash
lsof -ti:8001 | xargs kill -9 2>/dev/null
lsof -ti:8005 | xargs kill -9 2>/dev/null
```

Or change ports in `config.toml`:
```bash
.venv/bin/python scripts/update_config.py --config ./config.toml --set local_mcp_server.port=8002
```
And start uvicorn with `--port 8006` or another available port.

## Current State
- Both services running on ports 8001 and 8005
- Session ID from test: `4b8dcf46acb6420f94d247ce40434f78`
- All resources downloaded and in place
- Config verified and loading correctly

## Known Issues & Workarounds

### Issue 1: Services exit immediately
**Cause**: When running with `&` in background, stdin closes and uvicorn shuts down.
**Fix**: Use `nohup ... </dev/null > logfile 2>&1 &` pattern.

### Issue 2: Duplicate [vlm] section in config.toml
**Cause**: The original config had two `[vlm]` sections.
**Fix**: After editing, ensure only one `[vlm]` section exists.

### Issue 3: langgraph version conflict
**Cause**: `langgraph 1.0.10` missing `ExecutionInfo` import.
**Fix**: `pip install --upgrade langgraph` (installs 1.1.6, ignore compatibility warning).

### Issue 4: nvidia-cusparselt-cu13 not supported on ARM64
**Impact**: None - this package is for NVIDIA GPU sparse tensor operations. Not needed for Ollama cloud inference.
**Action**: Ignore the `pip check` warning.

### Issue 5: download.sh may fail silently
**Cause**: Network issues or the script running as a single long bash command gets truncated.
**Fix**: Run download steps manually as shown in section 3.

## File Locations Reference
```
/home/ubuntu/FireRed-OpenStoryline/
├── .venv/                          # Python virtual environment
├── .storyline/
│   ├── models/
│   │   ├── transnetv2-pytorch-weights.pth
│   │   └── all-MiniLM-L6-v2/       # Sentence transformer
│   └── skills/
├── resource/
│   ├── bgms/                       # Background music files
│   └── fonts/                      # Chinese/English fonts
├── web/static/                     # Web UI assets
├── config.toml                     # Main configuration (Ollama configured)
├── agent_fastapi.py               # FastAPI web server entry point
├── requirements.txt
├── scripts/
│   └── update_config.py           # Config update utility
└── src/open_storyline/
    ├── agent.py                    # Main agent logic
    ├── config.py                   # Config loader
    ├── mcp/
    │   ├── server.py              # MCP server entry point
    │   └── sampling_handler.py    # VLM image handling (base64 conversion)
    └── ...
```

## How to Use for Editing Videos

### 1. Ensure services are running
```bash
ps aux | grep -E "(mcp.server|uvicorn)" | grep -v grep
# If not running, restart using commands from section 5
```

### 2. Create a session
```bash
curl -s -X POST "http://127.0.0.1:8005/api/sessions"
# Returns: {"session_id": "...", ...}
```

### 3. Upload media
```bash
# Option A: Via API
curl -s -X POST "http://127.0.0.1:8005/api/sessions/{session_id}/media" \
  -F "files=@/absolute/path/to/video.mp4"

# Option B: Direct copy (for large files)
cp /path/to/video.mp4 /home/ubuntu/FireRed-OpenStoryline/outputs/{session_id}/media/
```

### 4. Send editing request via bridge script
```bash
cd /home/ubuntu/FireRed-OpenStoryline
.venv/bin/python .claude/skills/openstoryline-use/scripts/bridge_openstoryline.py \
  --session-id <session_id> \
  --base-url http://127.0.0.1:8005 \
  --prompt "Your editing instructions here" \
  --lang "zh"
```

### 5. Check output
```bash
find .storyline/.server_cache/<session_id> -name "output_*.mp4" 2>/dev/null
```
