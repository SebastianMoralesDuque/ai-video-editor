# FireRed-OpenStoryline - Guia de Instalacion

## Requisitos Previos
- Python 3.11+
- FFmpeg instalado
- Git

## Instalacion

### 1. Clonar el repositorio
```bash
git clone <url-del-repositorio>
cd ai-video-editor
```

### 2. Instalar Miniconda (si no esta instalado)
```bash
cd /tmp
curl -O https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda3
source ~/miniconda3/etc/profile.d/conda.sh
conda init bash
```

### 3. Crear entorno conda
```bash
# Aceptar Terminos de Servicio de conda (requerido)
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# Crear entorno con Python 3.11
conda create -n storyline python=3.11 -y
```

### 4. Ejecutar script de instalacion
```bash
conda activate storyline
bash build_env.sh
```

Este script:
- Verifica conda y Python
- Instala FFmpeg si no existe
- Descarga modelos del proyecto
- Instala dependencias de requirements.txt

## Ejecucion

### 1. Obtener API Key de Ollama Cloud
1. Ir a https://ollama.com/api
2. Crear una cuenta si no tienes
3. Copiar tu API key

### 2. Ejecutar el proyecto
```bash
conda activate storyline
cd ai-video-editor
OLLAMA_API_KEY=tu_api_key_aqui ./run.sh
```

El proyecto iniciara:
- Proxy Ollama en puerto 11434
- Web UI en http://localhost:7860
- MCP Server en puerto 8001

### 3. Abrir en el navegador
```
http://localhost:7860
```

## Problemas Conocidos y Soluciones

### Error: "NameError: name 'skills' is not defined"
**Causa:** En el commit `a70c57a` se elimino accidentalmente la carga de skills en `src/open_storyline/agent.py`.

**Solucion:** Verificar que en `agent.py` la linea `skills = await load_skills(...)` exista despues de `tools = await client.get_tools()`:

```python
tools = await client.get_tools()
logger.info(f"[AGENT] Got {len(tools)} tools: {[t.name for t in tools]}")
skills = await load_skills(cfg.skills.skill_dir)  # Load skills
node_manager = NodeManager(tools)
```

### Error: "ImportError: cannot import name 'ExecutionInfo' from 'langgraph.runtime'"
**Causa:** Conflicto de versiones entre langgraph y langgraph-checkpoint.

**Solucion:** Reinstalar las versiones compatibles:
```bash
pip uninstall -y langgraph langgraph-checkpoint langgraph-sdk langgraph-prebuilt
pip install langgraph langgraph-checkpoint langgraph-sdk langgraph-prebuilt
```

### Error: "[Errno 98] address already in use" en puerto 11434
**Causa:** El proxy de Ollama ya esta corriendo en el puerto 11434.

**Solucion:** Matar el proceso que ocupa el puerto:
```bash
fuser -k 11434/tcp
# o
lsof -ti:11434 | xargs kill -9
```

## Estructura del Proyecto
```
ai-video-editor/
├── build_env.sh       # Script de instalacion de dependencias
├── run.sh             # Script para ejecutar el proyecto
├── download.sh        # Script para descargar modelos
├── requirements.txt    # Dependencias Python
├── config.toml        # Configuracion del proyecto
├── src/open_storyline/   # Codigo fuente
└── .storyline/        # Modelos y skills descargados
```

## Comandos Utiles

### Verificar entorno conda
```bash
conda activate storyline
python --version
```

### Verificar dependencias
```bash
conda activate storyline
pip list | grep -E "torch|langgraph|fastapi|langchain"
```

### Ver logs del proyecto
```bash
tail -f /tmp/openstoryline.log
```

### Reiniciar desde cero
```bash
# Matar todos los procesos
pkill -f "run.sh\|ollama\|uvicorn\|open_storyline"

# Limpiar puertos
fuser -k 11434/tcp 8001/tcp 7860/tcp 2>/dev/null

# Recrear entorno (opcional)
conda env remove -n storyline
conda create -n storyline python=3.11 -y
conda activate storyline
pip install -r requirements.txt
```
