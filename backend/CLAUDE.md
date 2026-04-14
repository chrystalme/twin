# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Uses `uv` (see `.python-version`, `uv.lock`). Python >= 3.12.

- Install deps: `uv sync` (or `pip install -r requirements.txt` in the `.venv`)
- Run dev server: `uv run uvicorn server:app --reload --port 8000` (or `python server.py`)
- Required env: `OPENROUTER_API_KEY` in `.env`; optional `CORS_ORIGINS` (comma-separated, defaults to `http://localhost:3000`)

No test suite or linter is configured.

## Architecture

FastAPI backend serving a "digital twin" chatbot that impersonates the site owner. Lives under `twin/` alongside `frontend/` and a sibling `memory/` directory used for persistence.

- **`server.py`** — FastAPI app. Endpoints: `GET /`, `GET /health`, `POST /chat`, `GET /sessions`. Talks to OpenRouter via the `openai` SDK (`base_url=https://openrouter.ai/api/v1`, model `gpt-4o-mini`). Conversation history is persisted as JSON files in `../memory/{session_id}.json` (sibling to `backend/`, not inside it). Each `/chat` call loads history, prepends the system prompt, appends the new user turn, calls the model, and saves.
- **`context.py`** — Builds the system prompt via `prompt()` using persona data imported from `resources.py`. Note: `server.py` imports `prompt` but currently uses `PERSONALITY` (loaded from `me.txt`) instead — the `context.prompt()` pipeline is wired but unused.
- **`resources.py`** — Loads persona inputs from `./data/`: `linkedin.pdf` (via `pypdf`), `summary.txt`, `facts.json`, `style.txt`. The text-file loads sit inside the PDF `except FileNotFoundError` branch, so they only run when the PDF is missing — likely a bug to be aware of when editing.
- **`data/`** — Persona source material (not code). Editing these changes the twin's identity.
- **`me.txt`** — Simpler personality blob currently used as the actual system prompt in `server.py`.

### Known rough edges (do not "fix" without asking)
- `server.py` uses `Path` without importing it (`from pathlib import Path` is missing).
- In `/chat`, the user turn is appended to history with `role="assistant"` instead of `"user"` (line ~113).
- `context.prompt` is imported but never called.
- `resources.py` only loads txt/json files when the PDF is missing.
