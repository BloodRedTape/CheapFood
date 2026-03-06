"""Extract menu items from cleaned HTML text using OpenAI."""
from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from openai import AsyncOpenAI, RateLimitError, APIError
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
- Extract every item that looks like a menu dish, even if it has no price
- Keep original dish names, do not translate
- If price has comma as decimal separator, convert to dot (e.g. 12,50 -> 12.50)
- If price is missing or not listed, set price to null
- If no items found, return empty list
- Do NOT invent items that are not in the text"""


class MenuItemList(BaseModel):
    items: list[MenuItem] = Field(default_factory=list)


class HtmlMenuExtractor:
    """Extracts menu items from cleaned HTML text using OpenAI structured outputs."""

    MAX_RETRIES: int = 3
    RETRY_FALLBACK_DELAY: float = 60.0

    def __init__(
        self,
        api_key: str,
        model: str = "gpt-4o-mini",
        rpm: int = 500,
    ) -> None:
        self._client: AsyncOpenAI = AsyncOpenAI(api_key=api_key)
        self._model: str = model
        self._semaphore: asyncio.Semaphore = asyncio.Semaphore(1)
        self._interval: float = 60.0 / rpm
        self._last_call: float = 0.0

    async def extract(self, clean_text: str, log_path: Path | None = None) -> list[MenuItem]:
        """Send cleaned page text to OpenAI and parse structured response."""
        if not clean_text.strip():
            logger.info("No text provided")
            return []

        for attempt in range(self.MAX_RETRIES):
            try:
                async with self._semaphore:
                    now: float = asyncio.get_event_loop().time()
                    wait: float = self._interval - (now - self._last_call)
                    if wait > 0:
                        logger.info("Rate limit: waiting %.1fs", wait)
                        await asyncio.sleep(wait)
                    response = await self._client.beta.chat.completions.parse(
                        model=self._model,
                        messages=[
                            {"role": "system", "content": SYSTEM_PROMPT},
                            {"role": "user", "content": clean_text},
                        ],
                        response_format=MenuItemList,
                    )
                    self._last_call = asyncio.get_event_loop().time()

                result: MenuItemList = response.choices[0].message.parsed or MenuItemList()
                logger.info("OpenAI extracted %d items from html_text", len(result.items))

                if log_path is not None:
                    _save_log(log_path, clean_text, result.model_dump_json())

                return result.items

            except RateLimitError as exc:
                logger.warning(
                    "OpenAI rate limit (attempt %d/%d): %s. Retrying in %.0fs",
                    attempt + 1, self.MAX_RETRIES, exc, self.RETRY_FALLBACK_DELAY,
                )
                if attempt < self.MAX_RETRIES - 1:
                    await asyncio.sleep(self.RETRY_FALLBACK_DELAY)
                else:
                    logger.error("OpenAI extraction failed after %d retries", self.MAX_RETRIES)
                    if log_path is not None:
                        _save_log(log_path, clean_text, f"ERROR: {exc}")
                    return []

            except APIError as exc:
                logger.exception("OpenAI API error for html_text: %s", exc)
                if log_path is not None:
                    _save_log(log_path, clean_text, f"ERROR: {exc}")
                return []

            except Exception:
                logger.exception("OpenAI extraction failed for html_text")
                if log_path is not None:
                    _save_log(log_path, clean_text, "ERROR: see application logs")
                return []

        return []


def _save_log(log_path: Path, request_text: str, response_text: str) -> None:
    """Save LLM request/response pair to a text file."""
    content: str = f"REQUEST:\n{request_text}\n\nRESPONSE:\n{response_text}\n"
    log_path.write_text(content, encoding="utf-8")
