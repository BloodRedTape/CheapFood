"""Extract menu items from cleaned HTML text using Gemini."""
from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from google import genai
from pydantic import BaseModel, Field

from menu_scraper.models.menu import MenuItem

logger: logging.Logger = logging.getLogger(__name__)

SYSTEM_PROMPT: str = """You are a menu parser. You receive cleaned text from a restaurant website page.
Extract ALL menu items you can find. For each item return:
- name: dish name exactly as written
- description: dish description if present, null otherwise
- price: numeric price if present, null otherwise
- currency: ISO currency code (USD, EUR, ILS, GBP, etc.), default USD

Rules:
- Extract every item that looks like a menu dish with a price
- Keep original dish names, do not translate
- If price has comma as decimal separator, convert to dot (e.g. 12,50 -> 12.50)
- If no items found, return empty list
- Do NOT invent items that are not in the text"""


class MenuItemList(BaseModel):
    items: list[MenuItem] = Field(default_factory=list)


class GeminiMenuExtractor:
    """Extracts menu items by sending cleaned text to Gemini."""

    def __init__(self, api_key: str, model: str = "gemini-2.5-flash", rpm: int = 5) -> None:
        self._client: genai.Client = genai.Client(api_key=api_key)
        self._model: str = model
        self._semaphore: asyncio.Semaphore = asyncio.Semaphore(1)
        self._interval: float = 60.0 / rpm
        self._last_call: float = 0.0

    async def extract(self, clean_text: str, log_path: Path | None = None) -> list[MenuItem]:
        """Send cleaned page text to Gemini and parse structured response.

        If log_path is provided, saves request/response to a .llm.txt file.
        """
        logger.info("GeminiMenuExtractor Extract")
        if not clean_text.strip():
            logger.info("No text provided")
            return []

        # Убрали обрезку текста
        prompt: str = f"{SYSTEM_PROMPT}\n\n---\n\n{clean_text}"

        try:
            async with self._semaphore:
                now: float = asyncio.get_event_loop().time()
                wait: float = self._interval - (now - self._last_call)
                if wait > 0:
                    logger.info("Rate limit: waiting %.1fs", wait)
                    await asyncio.sleep(wait)
                response = await self._client.aio.models.generate_content(
                    model=self._model,
                    contents=prompt,
                    config={
                        "response_mime_type": "application/json",
                        "response_schema": MenuItemList,
                    },
                )
                self._last_call = asyncio.get_event_loop().time()
            response_text: str = response.text or ""

            logger.info("Gemini response %s", response_text)
            result: MenuItemList = MenuItemList.model_validate_json(response_text)
            logger.info("Gemini extracted %d items", len(result.items))

            if log_path is not None:
                _save_log(log_path, clean_text, response_text)

            return result.items
        except Exception:
            logger.exception("Gemini extraction failed")
            if log_path is not None:
                _save_log(log_path, clean_text, "ERROR: see application logs")
            return []

def _save_log(log_path: Path, request_text: str, response_text: str) -> None:
    """Save LLM request/response pair to a text file."""
    content: str = f"REQUEST:\n{request_text}\n\nRESPONSE:\n{response_text}\n"
    log_path.write_text(content, encoding="utf-8")
