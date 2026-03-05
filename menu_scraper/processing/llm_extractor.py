"""Extract menu items from cleaned HTML text using Gemini."""
from __future__ import annotations

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

    def __init__(self, api_key: str, model: str = "gemini-2.5-flash") -> None:
        self._client: genai.Client = genai.Client(api_key=api_key)
        self._model: str = model

    async def extract(self, clean_text: str, log_path: Path | None = None) -> list[MenuItem]:
        """Send cleaned page text to Gemini and parse structured response.

        If log_path is provided, saves request/response to a .llm.txt file.
        """
        logger.info("GeminiMenuExtractor Extract")
        if not clean_text.strip():
            logger.info("No text provided")
            return []

        truncated: str = clean_text[:30_000]
        prompt: str = f"{SYSTEM_PROMPT}\n\n---\n\n{truncated}"

        try:
            response = self._client.models.generate_content(
                model=self._model,
                contents=prompt,
                config={
                    "response_mime_type": "application/json",
                    "response_json_schema": MenuItemList.model_json_schema(),
                },
            )
            response_text: str = response.text or ""

            logger.info("Gemini response %s", response_text)
            result: MenuItemList = MenuItemList.model_validate_json(response_text)
            logger.info("Gemini extracted %d items", len(result.items))

            if log_path is not None:
                _save_log(log_path, truncated, response_text)

            return result.items
        except Exception:
            logger.exception("Gemini extraction failed")
            if log_path is not None:
                _save_log(log_path, truncated, "ERROR: see application logs")
            return []


def _save_log(log_path: Path, request_text: str, response_text: str) -> None:
    """Save LLM request/response pair to a text file."""
    content: str = f"REQUEST:\n{request_text}\n\nRESPONSE:\n{response_text}\n"
    log_path.write_text(content, encoding="utf-8")
