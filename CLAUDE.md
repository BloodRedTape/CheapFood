# CheapFood Project

## Architecture
- Microservice architecture, each service self-contained with own pyproject.toml and tests
- `menu_scraper/` — FastAPI service, scrapes restaurant menus, returns `list[MenuItem]` from `POST /scrape`
- `backend_dart/` — Dart/shelf HTTP server on port 8080, proxies `/scrape` to `menu_scraper:8000`, adds CORS headers
- `common_dart/` — shared Dart models (`MenuItem`, `ScrapeRequest`), no code generation, manual JSON parsing
- `frontend/` — Flutter app, calls `backend_dart`, shows scraped menu items in a list
- No `services/` wrapper — services live directly in root

## Technical Details
- Python 3.14, Windows 11
- Twisted requires SelectorEventLoop — solved via loop factory in `__main__.py`
- Playwright support planned but currently disabled
- OCR stub exists, will use Gemini Vision API later
- Simplified data model: flat `list[MenuItem]`, no categories/tags/wrapper objects
- `Decimal` price fields serialize to JSON strings — Dart parses both `num` and `String`

## Python
- Always use strict type annotations
- Pydantic v2 for models, pydantic-settings for config

## Dart
- No code generation (no json_serializable/build_runner) — manual `fromJson`/`toJson`
- `backend_dart` uses shelf + shelf_router + http packages

## File Structure
- `menu_scraper/` — scraper microservice (pyproject.toml, tests/, code)
- `backend_dart/` — Dart proxy server (bin/backend_dart.dart)
- `common_dart/` — shared Dart models (lib/src/models/)
- `frontend/` — Flutter app (lib/main.dart)
- `notes/` — technical reference docs
- Root: `.gitignore`, `CLAUDE.md`

## Conventions
- Communicate in Russian
- Log messages in English
- Tests are local to each service
- Use `.env` for configuration (pydantic-settings with CHEAPFOOD_ prefix)

## Common Dart
- common models between flutter frontend and dart backend should be in common_dart

## Frontend UI
- Frontend should be in a mobile app style
- UI text by default should be English