# NeuroSense API. Python 3.12 because the host's Python 3.14 has no PyTorch build.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 KERAS_BACKEND=torch

WORKDIR /srv

# CPU-only PyTorch (much smaller than the default CUDA build).
RUN pip install --index-url https://download.pytorch.org/whl/cpu torch==2.5.1 torchvision==0.20.1

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

RUN useradd --create-home appuser && chown -R appuser /srv
USER appuser

EXPOSE 8000
# One process: the analysis worker thread lives inside it (see app/services/analysis_worker.py).
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 1 --no-access-log"]
