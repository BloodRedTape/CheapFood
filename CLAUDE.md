# CheapFood Project

## Architecture
- Microservice architecture, each service self-contained with own pyproject.toml and tests
- First service: `menu_scraper/` — Scrapy + FastAPI, scrapes restaurant menus to JSON
- No `services/` wrapper — services live directly in root

## Technical Details
- Python 3.14, Windows 11
- Twisted requires SelectorEventLoop — solved via loop factory in `__main__.py`
- Playwright support planned but currently disabled
- OCR stub exists, will use Gemini Vision API later
- Simplified data model: flat MenuItem list, no categories/tags

## Python
- Always use strict type annotations
- Pydantic v2 for models, pydantic-settings for config

## File Structure
- `menu_scraper/` — scraper microservice (pyproject.toml, tests/, code)
- `notes/` — technical reference docs
- Root: `.gitignore`, `CLAUDE.md`

## Conventions
- Communicate in Russian
- Log messages in English
- Tests are local to each service
- Use `.env` for configuration (pydantic-settings with CHEAPFOOD_ prefix)