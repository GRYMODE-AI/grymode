# syntax=docker/dockerfile:1.7
# Cloud Run image for the Grymode API.

FROM ghcr.io/astral-sh/uv:0.9-python3.12-bookworm-slim AS build
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /srv
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev --no-install-project
COPY app ./app

FROM python:3.12-slim-bookworm AS runtime
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PATH="/srv/.venv/bin:$PATH" PORT=8080
RUN groupadd --system --gid 10001 grymode && useradd --system --uid 10001 --gid grymode --no-create-home grymode
WORKDIR /srv
COPY --from=build --chown=grymode:grymode /srv /srv
USER grymode
EXPOSE 8080
# Cloud Run sets PORT. Proxy headers are trusted only from Google's front end.
CMD ["sh", "-c", "exec uvicorn app.main:create_app --factory --host 0.0.0.0 --port ${PORT} --proxy-headers --forwarded-allow-ips='*' --no-server-header"]
