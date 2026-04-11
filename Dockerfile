# FireRed-OpenStoryline - Installation following instructions.md
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=/bin/bash

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg wget unzip git git-lfs curl \
    && rm -rf /var/lib/apt/lists/*

RUN cd /tmp && \
    curl -O https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh && \
    bash Miniconda3-latest-Linux-x86_64.sh -b -p /opt/conda && \
    rm Miniconda3-latest-Linux-x86_64.sh

ENV PATH=/opt/conda/bin:$PATH

RUN conda init bash && \
    conda config --set auto_activate_base false

COPY requirements.txt .
COPY download.sh .

RUN bash download.sh

RUN conda create -n storyline python=3.11 -y && \
    conda run -n storyline pip install -r requirements.txt && \
    conda run -n storyline pip install --upgrade langgraph

COPY src/ ./src/
COPY agent_fastapi.py .
COPY ollama_cloud_proxy.py .
COPY cli.py .
COPY config.toml .
COPY web/ ./web/
COPY prompts/ ./prompts/
COPY run.sh .

RUN mkdir -p .storyline .storyline/skills resource outputs/media

ENV PATH="/opt/conda/envs/storyline/bin:$PATH"
ENV CONDA_DEFAULT_ENV=storyline
ENV PYTHONPATH=/app/src
ENV HOST=0.0.0.0
ENV PORT=7860
ENV OLLAMA_API_KEY=""
ENV OLLAMA_CLOUD_URL=https://ollama.com
ENV LLM_MODEL=minimax-m2.7:cloud
ENV LLM_BASE_URL=http://127.0.0.1:11434/v1
ENV LLM_API_KEY=ollama
ENV LLM_TIMEOUT=300.0
ENV VLM_MODEL=gemma4:31b-cloud
ENV VLM_BASE_URL=http://127.0.0.1:11434/v1
ENV VLM_API_KEY=ollama
ENV VLM_TIMEOUT=600.0

EXPOSE 7860

CMD ["/opt/conda/envs/storyline/bin/bash", "run.sh"]
