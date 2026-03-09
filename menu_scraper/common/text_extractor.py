"""Extract menu items from plain text using OpenAI."""
from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from openai import AsyncOpenAI, RateLimitError, APIError
from pydantic import BaseModel, Field, ValidationError

from menu_scraper.models.menu import MenuCategory
from menu_scraper.common.prompts import MENU_ITEM_FIELDS, MENU_ITEM_RULES

logger: logging.Logger = logging.getLogger(__name__)

SYSTEM_PROMPT: str = f"""You are a menu parser. You receive text from a restaurant menu.
Extract ALL menu items grouped by category. For each category return:
- name: category name as written (e.g. "Starters", "Main Course"), or null if no category is apparent
- items: list of dishes in that category

{MENU_ITEM_FIELDS}

Rules:
- Group items by the section headers/titles found in the text
- If all items belong to no clear category, return a single category with name null
{MENU_ITEM_RULES}"""


class MenuCategoryList(BaseModel):
    categories: list[MenuCategory] = Field(default_factory=list)


class TextMenuExtractor:
    """Extracts menu items from plain text using OpenAI structured outputs."""

    MAX_RETRIES: int = 3
    RETRY_FALLBACK_DELAY: float = 60.0

    def __init__(
        self,
        api_key: str,
        model: str = "gpt-4.1-mini",
        rpm: int = 500,
    ) -> None:
        self._client: AsyncOpenAI = AsyncOpenAI(api_key=api_key)
        self._model: str = model
        self._rate_lock: asyncio.Lock = asyncio.Lock()
        self._interval: float = 60.0 / rpm
        self._last_call: float = 0.0

    async def extract(
        self,
        text: str,
        log_dir: Path | None = None,
        filename: str | None = None,
    ) -> list[MenuCategory]:
        """Send text to OpenAI and parse structured response."""
        log_path: Path | None = None
        if log_dir is not None and filename is not None:
            stem = Path(filename).stem
            log_path = log_dir / f"{stem}.llm.txt"

        response = None
        for attempt in range(self.MAX_RETRIES):
            try:
                async with self._rate_lock:
                    now: float = asyncio.get_event_loop().time()
                    wait: float = self._interval - (now - self._last_call)
                    if wait > 0:
                        logger.info("Rate limit: waiting %.1fs", wait)
                        await asyncio.sleep(wait)
                    self._last_call = asyncio.get_event_loop().time()
                response = await self._client.beta.chat.completions.parse(
                    model=self._model,
                    messages=[
                        {"role": "system", "content": SYSTEM_PROMPT},
                        {"role": "user", "content": text},
                    ],
                    response_format=MenuCategoryList,
                    max_completion_tokens=16384,
                )

                result: MenuCategoryList = response.choices[0].message.parsed or MenuCategoryList()
                total = sum(len(c.items) for c in result.categories)
                logger.info("OpenAI extracted %d items in %d categories", total, len(result.categories))

                if log_path is not None:
                    _save_log(log_path, text, result.model_dump_json())

                return result.categories

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
                        _save_log(log_path, text, f"ERROR: {exc}")
                    return []

            except ValidationError as exc:
                finish_reason = response.choices[0].finish_reason if response is not None else "no_response"
                raw = response.choices[0].message.content if response is not None else ""
                logger.error(
                    "OpenAI response parsing failed (file=%s, finish_reason=%s, attempt %d/%d, raw_len=%d): %s",
                    filename, finish_reason, attempt + 1, self.MAX_RETRIES, len(raw or ""), exc,
                )
                if log_path is not None:
                    _save_log(log_path, text, f"PARSE ERROR ({finish_reason}):\n{exc}\n\nRAW:\n{raw}")
                return []

            except APIError as exc:
                if exc.code == "context_length_exceeded":
                    logger.error(
                        "OpenAI context length exceeded (file=%s, input_chars=%d): %s",
                        filename, len(text), exc,
                    )
                else:
                    logger.exception("OpenAI API error (file=%s): %s", filename, exc)
                if log_path is not None:
                    _save_log(log_path, text, f"ERROR: {exc}")
                return []

            except Exception:
                logger.exception("OpenAI extraction failed")
                if log_path is not None:
                    _save_log(log_path, text, "ERROR: see application logs")
                return []

        return []


def _save_log(log_path: Path, request_text: str, response_text: str) -> None:
    """Save LLM request/response pair to a text file."""
    content: str = f"REQUEST:\n{request_text}\n\nRESPONSE:\n{response_text}\n"
    log_path.write_text(content, encoding="utf-8")
