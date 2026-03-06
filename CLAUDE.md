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
- Data model: `MenuResult` → `list[MenuCategory]` → `list[MenuItem]` → `list[MenuItemVariation]`
- Price, currency, unit, unit_size live on `MenuItemVariation`, not on `MenuItem`
- Most items have one variation; multiple variations when item is offered in different sizes/prices
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
- Shared models between flutter frontend and dart backend live in `common_dart`
- Models: `MenuItem`, `MenuItemVariation`, `MenuCategory`, `ScrapeRequest`, `ScrapeResponse`, `ExchangeRates`
- `MenuItem` has `name`, `description`, `variations: List<MenuItemVariation>`
- `MenuItemVariation` has `price`, `currency`, `unit`, `unitSize`

## Frontend UI
- Frontend should be in a mobile app style
- UI text by default should be English

## SSE Streaming
- `menu_scraper` exposes `POST /scrape/stream` — SSE with `progress`, `result`, `error` events
- `backend_dart` proxies it at `POST /scrape/stream` using `dart:io HttpClient` (not `package:http`)
- shelf buffers streaming responses by default — must set `context: {'shelf.io.buffer_output': false}` on the `Response.ok`
- Also set `server.autoCompress = false` on the shelf_io server (gzip buffers too)
- Flutter Web: `package:http` uses XHR which buffers SSE — use `FetchClient(mode: RequestMode.cors)` from `fetch_client` package instead
- Do NOT add `Transfer-Encoding: chunked` manually — causes double-encoding error in `http_parser`

NEVER READ .env FILES!!!