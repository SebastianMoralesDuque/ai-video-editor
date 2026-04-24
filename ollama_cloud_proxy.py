"""
Ollama Cloud Proxy — converts OpenAI-compatible /v1/chat/completions requests
to Ollama Cloud native /api/chat format and converts responses back.

Env vars:
  OLLAMA_API_KEY  — required, Ollama Cloud API key
  OLLAMA_CLOUD_URL — optional, defaults to https://ollama.com
  PROXY_HOST — optional, defaults to 127.0.0.1
  PROXY_PORT — optional, defaults to 11434 (drop-in replacement for local Ollama)
"""

from __future__ import annotations

import json
import os
import time
import logging
from typing import Any

import httpx
import uvicorn
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse, StreamingResponse

logger = logging.getLogger("ollama-cloud-proxy")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(levelname)s %(message)s")

OLLAMA_API_KEY = os.environ.get("OLLAMA_API_KEY", "")
OLLAMA_CLOUD_URL = (os.environ.get("OLLAMA_CLOUD_URL") or "https://ollama.com").rstrip("/")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "minimax-m2.7:cloud")
PROXY_HOST = os.environ.get("PROXY_HOST", "127.0.0.1")
PROXY_PORT = int(os.environ.get("PROXY_PORT", "11434"))

if not OLLAMA_API_KEY:
    logger.warning("OLLAMA_API_KEY is not set — requests will fail!")

app = FastAPI(title="Ollama Cloud Proxy", version="1.0.0")


def _ollama_headers() -> dict[str, str]:
    return {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {OLLAMA_API_KEY}",
    }


def _openai_to_ollama(body: dict[str, Any]) -> dict[str, Any]:
    """Convert OpenAI-compatible request body to Ollama /api/chat format."""
    messages = body.get("messages") or []

    ollama_messages = []
    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")

        # Handle multimodal content (list of blocks with images)
        if isinstance(content, list):
            images = []
            text_parts = []
            for block in content:
                if isinstance(block, dict):
                    if block.get("type") == "text":
                        text_parts.append(block.get("text", ""))
                    elif block.get("type") == "image_url":
                        url = block.get("image_url", {}).get("url", "")
                        if url.startswith("data:"):
                            # data:image/jpeg;base64,XXXX -> extract base64 payload
                            b64 = url.split(",", 1)[1] if "," in url else ""
                            if b64:
                                images.append(b64)
                        elif url:
                            text_parts.append(f"[image: {url}]")
            ollama_messages.append({
                "role": role,
                "content": "\n".join(text_parts) if text_parts else "",
                **({"images": images} if images else {}),
            })
        else:
            ollama_messages.append({"role": role, "content": str(content)})

    ollama_body: dict[str, Any] = {
        "model": body.get("model", OLLAMA_MODEL),
        "messages": ollama_messages,
        "stream": bool(body.get("stream", False)),
    }

    # Map optional parameters
    if "temperature" in body:
        ollama_body["options"] = {**ollama_body.get("options", {}), "temperature": body["temperature"]}
    if "top_p" in body:
        ollama_body["options"] = {**ollama_body.get("options", {}), "top_p": body["top_p"]}
    if "max_tokens" in body or "max_completion_tokens" in body:
        mt = body.get("max_completion_tokens") or body.get("max_tokens")
        if mt is not None:
            ollama_body["options"] = {**ollama_body.get("options", {}), "num_predict": mt}

    return ollama_body


def _ollama_to_openai_response(data: dict[str, Any], model: str) -> dict[str, Any]:
    """Convert Ollama /api/chat response to OpenAI-compatible format."""
    message = data.get("message") or {}
    content = message.get("content", "")

    return {
        "id": f"chatcmpl-{data.get('created_at', int(time.time()))}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": data.get("model") or model,
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": message.get("role", "assistant"),
                    "content": content,
                },
                "finish_reason": "stop" if data.get("done") else None,
            }
        ],
        "usage": {
            "prompt_tokens": data.get("prompt_eval_count", 0) or 0,
            "completion_tokens": data.get("eval_count", 0) or 0,
            "total_tokens": (data.get("prompt_eval_count", 0) or 0) + (data.get("eval_count", 0) or 0),
        },
    }


@app.post("/v1/chat/completions")
@app.post("/v1/chat/completions/")
async def chat_completions(request: Request):
    body = await request.json()
    stream = bool(body.get("stream", False))
    model = body.get("model", OLLAMA_MODEL)

    ollama_body = _openai_to_ollama(body)

    try:
        if stream:
            return StreamingResponse(
                _stream_ollama(ollama_body, model),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                    "X-Accel-Buffering": "no",
                },
            )
        else:
            timeout_val = float(body.get("timeout", 600.0))
            async with httpx.AsyncClient(timeout=httpx.Timeout(timeout_val)) as client:
                resp = await client.post(
                    f"{OLLAMA_CLOUD_URL}/api/chat",
                    headers=_ollama_headers(),
                    json=ollama_body,
                )
                resp.raise_for_status()
                data = resp.json()

            return JSONResponse(_ollama_to_openai_response(data, model))

    except httpx.HTTPStatusError as e:
        logger.error(f"Ollama Cloud error: {e.response.status_code} {e.response.text[:500]}")
        raise HTTPException(status_code=e.response.status_code, detail=f"Ollama Cloud error: {e.response.text[:500]}")
    except Exception as e:
        logger.error(f"Proxy error: {e}")
        raise HTTPException(status_code=502, detail=str(e))


async def _stream_ollama(ollama_body: dict[str, Any], model: str):
    """Stream Ollama Cloud response, converting each chunk to OpenAI SSE format."""
    async with httpx.AsyncClient(timeout=httpx.Timeout(600.0)) as client:
        async with client.stream(
            "POST",
            f"{OLLAMA_CLOUD_URL}/api/chat",
            headers=_ollama_headers(),
            json=ollama_body,
        ) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                line = line.strip()
                if not line:
                    continue
                try:
                    chunk = json.loads(line)
                except json.JSONDecodeError:
                    continue

                content = chunk.get("message", {}).get("content", "")
                done = chunk.get("done", False)

                openai_chunk = {
                    "id": f"chatcmpl-{int(time.time())}",
                    "object": "chat.completion.chunk",
                    "created": int(time.time()),
                    "model": chunk.get("model") or model,
                    "choices": [
                        {
                            "index": 0,
                            "delta": {"content": content} if content else {},
                            "finish_reason": "stop" if done else None,
                        }
                    ],
                }
                yield f"data: {json.dumps(openai_chunk)}\n\n"

                if done:
                    break

            yield "data: [DONE]\n\n"


# --- Health / compatibility endpoints ---

@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [
            {"id": "minimax-m2.7:cloud", "object": "model", "owned_by": "ollama-cloud"},
            {"id": "gemma4:31b-cloud", "object": "model", "owned_by": "ollama-cloud"},
        ],
    }


@app.get("/")
@app.get("/v1")
async def root():
    return {"status": "ok", "proxy": "ollama-cloud", "cloud_url": OLLAMA_CLOUD_URL}


if __name__ == "__main__":
    logger.info(f"Starting Ollama Cloud Proxy on {PROXY_HOST}:{PROXY_PORT} → {OLLAMA_CLOUD_URL}")
    uvicorn.run(app, host=PROXY_HOST, port=PROXY_PORT)
