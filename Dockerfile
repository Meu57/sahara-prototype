FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PORT=8080 \
    PYTHONPATH=/app

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/ ./backend

RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE ${PORT}

CMD ["sh", "-c", "gunicorn --bind 0.0.0.0:${PORT:-8080} backend.app:app --workers 1 --threads 4 --timeout 120"]
