# FireRed-OpenStoryline - Simple Dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg wget unzip git git-lfs curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir --upgrade langgraph

COPY src/ ./src/
COPY agent_fastapi.py .
COPY ollama_cloud_proxy.py .
COPY cli.py .
COPY config.toml .
COPY web/ ./web/
COPY prompts/ ./prompts/
COPY run.sh .

# Skills from git
COPY .storyline/skills/ .storyline/skills/

RUN mkdir -p .storyline .storyline/models resource outputs/media

RUN wget -q "https://image-url-2-feature-1251524319.cos.ap-shanghai.myqcloud.com/openstoryline/models.zip" -O .storyline/models.zip \
    && unzip -q -o .storyline/models.zip -d .storyline/models/ \
    && rm .storyline/models.zip

RUN wget -q "https://image-url-2-feature-1251524319.cos.ap-shanghai.myqcloud.com/openstoryline/resource.zip" -O .storyline/resource.zip \
    && unzip -q -o .storyline/resource.zip -d resource \
    && rm .storyline/resource.zip

ENV PYTHONPATH=/app/src
ENV HOST=0.0.0.0
ENV PORT=7860

EXPOSE 7860

CMD ["bash", "run.sh"]