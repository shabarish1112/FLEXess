FROM python:3.14-slim-bookworm
WORKDIR /app
COPY requirements-runtime.lock .
RUN pip install --no-cache-dir -r requirements-runtime.lock
COPY app app
COPY migrations migrations
COPY alembic.ini .
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=5s CMD ["python", "-c", "from urllib.request import urlopen; urlopen('http://127.0.0.1:8000/health/ready', timeout=3).close()"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--no-access-log", "--no-proxy-headers", "--timeout-graceful-shutdown", "20"]
