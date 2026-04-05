# 基础镜像
FROM python:3.11-slim

# 设置工作目录
WORKDIR /app

# 先复制不常变的文件，利用 Docker 缓存
COPY requirements.txt .

# 安装系统依赖和 Python 依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg wget unzip git git-lfs curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir --upgrade langgraph

# 复制项目文件
COPY src/ ./src/
COPY agent_fastapi.py .
COPY cli.py .
COPY config.toml .
COPY web/ ./web/
COPY prompts/ ./prompts/
COPY run.sh .

# 创建必要目录
RUN mkdir -p .storyline resource outputs/media

# 下载模型和资源
RUN wget -q "https://image-url-2-feature-1251524319.cos.ap-shanghai.myqcloud.com/openstoryline/models.zip" -O .storyline/models.zip \
    && unzip -q -o .storyline/models.zip -d .storyline/models/ \
    && rm .storyline/models.zip

RUN wget -q "https://image-url-2-feature-1251524319.cos.ap-shanghai.myqcloud.com/openstoryline/resource.zip" -O .storyline/resource.zip \
    && unzip -q -o .storyline/resource.zip -d resource \
    && rm .storyline/resource.zip

# 下载 web 静态资源
RUN for f in brand_black.png brand_white.png logo.png dice.png github.png node_map.png user_guide.png; do \
      wget -q "https://image-url-2-feature-1251524319.cos.ap-shanghai.myqcloud.com/zailin/datasets/open_storyline/$f" -O "web/static/$f"; \
    done || true

# 设置环境变量
ENV PYTHONPATH=/app/src
ENV HOST=0.0.0.0
ENV PORT=7860

# Ollama configuration (same pattern as NeonRunner)
ENV OLLAMA_HOST=host.docker.internal
ENV LLM_MODEL=minimax-m2.7:cloud
ENV LLM_BASE_URL=http://host.docker.internal:11434/v1
ENV LLM_API_KEY=ollama
ENV LLM_TIMEOUT=300.0
ENV VLM_MODEL=gemma4:31b-cloud
ENV VLM_BASE_URL=http://host.docker.internal:11434/v1
ENV VLM_API_KEY=ollama
ENV VLM_TIMEOUT=600.0

# 暴露端口
EXPOSE 7860

# 启动
CMD ["bash", "run.sh"]
