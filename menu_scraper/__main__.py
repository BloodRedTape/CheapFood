"""Entry point: python -m menu_scraper"""
from __future__ import annotations

import uvicorn

from menu_scraper.config import get_settings


def main() -> None:
    config = get_settings()
    uvicorn.run(
        "menu_scraper.app:app",
        host=config.host,
        port=config.port,
    )


if __name__ == "__main__":
    main()
