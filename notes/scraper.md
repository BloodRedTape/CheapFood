# Menu Scraper — техническая сводка

## Что это
Микросервис на Python, принимает URL ресторана → возвращает JSON с меню (блюда, цены, описания).

## Стек
- **Scrapy** — скрейпинг HTML
- **FastAPI + uvicorn** — HTTP API
- **Pydantic v2** — модели данных и валидация
- **Twisted asyncio reactor** — мост между Scrapy и FastAPI

## Запуск
```bash
cd menu_scraper
pip install -e ".[dev]"
python -m menu_scraper        # http://0.0.0.0:8000
```

## API
- `POST /scrape` — `{"url": "https://..."}`  → `ScrapeResponse`
- `GET /health` — `{"status": "ok"}`
- `GET /docs` — Swagger UI

## Структура menu_scraper/
```
__main__.py          — точка входа, настройка SelectorEventLoop для Windows
app.py               — FastAPI (lifespan, /scrape, /health)
config.py            — AppSettings через pydantic-settings (.env)
runner.py            — ScrapyRunner: CrawlerRunner + asyncio reactor
items.py             — Scrapy dataclass items (RawMenuTextItem, MenuMediaItem)
scrapy_settings.py   — настройки Scrapy (dict)
models/
  menu.py            — MenuItem, MenuResult, MediaFile, MenuSourceType
  requests.py        — ScrapeRequest, ScrapeResponse
spiders/
  menu_spider.py     — MenuSpider: парсит HTML text, PDF links, images
pipelines/
  media.py           — планирует скачивание PDF/картинок
  extract.py         — HTML text → MenuItem через HtmlMenuExtractor
  collect.py         — собирает MediaFile в результат
processing/
  html_extractor.py  — regex-эвристика: name + price из текста
  media_handler.py   — async download файлов (httpx)
  ocr_stub.py        — заглушка для Gemini OCR (TODO)
tests/               — pytest, локальные к сервису
```

## Модель данных (упрощённая, без категорий)
```
MenuItem: name, description?, price?, currency
MenuResult: url, restaurant_name?, items[], source_type, media_files[], raw_text?
```

## Ключевые решения
- **Без категорий/тегов** — плоский список items, категории добавим позже
- **Playwright отключён по умолчанию** — download handlers убраны, будет opt-in позже
- **ROBOTSTXT_OBEY=False** — чтобы не зависать на недоступных robots.txt
- **Windows:** uvicorn запускается с SelectorEventLoop через loop factory в __main__.py
- **Reactor** устанавливается лениво в runner.py при первом crawl()
- **OCR** — заглушка, будет Gemini Vision API

## Известные проблемы
- Python 3.14: `WindowsSelectorEventLoopPolicy` deprecated, используем loop factory
- Scrapy deprecation warnings: start_requests → start(), spider arg в pipelines
- Второй вызов /scrape может упасть т.к. CrawlerRunner не пересоздаётся
