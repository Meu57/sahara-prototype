# /sahara-final/Dockerfile
FROM python:3.11-slim

ENV PORT=8080
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

WORKDIR /app
EXPOSE 8080

# Install dependencies
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy only the backend package into the container (keeps context smaller)
COPY backend/ /app/backend

# Use --chdir so the module path backend.app resolves reliably.
# Use sh -c so ${PORT} expands (Cloud Run provides PORT at runtime).
# Start with 1 worker and 2 threads to keep memory low while debugging.
CMD ["sh", "-c", "gunicorn --chdir /app --bind 0.0.0.0:${PORT:-8080} backend.app:app --workers 1 --threads 2 --timeout 120"]
