"""Extract menu items from cleaned HTML text using Gemini."""
from __future__ import annotations

import asyncio
import logging
import re
from pathlib import Path
from typing import Any

from google import genai
from google.genai.errors import APIError
from google.genai.types import Blob, Part
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


class GeminiMenuExtractor:
    """Extracts menu items by sending cleaned text to Gemini."""

    MAX_RETRIES: int = 3
    RETRY_FALLBACK_DELAY: float = 60.0

    def __init__(
        self,
        api_key: str,
        model: str = "gemini-3.1-flash-lite-preview",
        pdf_model: str = "gemini-2.5-flash-lite",
        rpm: int = 10,
    ) -> None:
        self._client: genai.Client = genai.Client(api_key=api_key)
        self._model: str = model
        self._pdf_model: str = pdf_model
        self._semaphore: asyncio.Semaphore = asyncio.Semaphore(1)
        self._interval: float = 70.0 / rpm
        self._last_call: float = 0.0

    async def _call_gemini(
        self,
        contents: Any,
        source_label: str,
        log_path: Path | None = None,
        model: str | None = None,
    ) -> list[MenuItem]:
        """Call Gemini with retry logic. Returns extracted menu items."""
        use_model: str = model or self._model
        for attempt in range(self.MAX_RETRIES):
            try:
                async with self._semaphore:
                    now: float = asyncio.get_event_loop().time()
                    wait: float = self._interval - (now - self._last_call)
                    if wait > 0:
                        logger.info("Rate limit: waiting %.1fs", wait)
                        await asyncio.sleep(wait)
                    response = await self._client.aio.models.generate_content(
                        model=use_model,
                        contents=contents,
                        config={
                            "response_mime_type": "application/json",
                            "response_schema": MenuItemList,
                        },
                    )
                    self._last_call = asyncio.get_event_loop().time()
                response_text: str = response.text or ""

                logger.info("Gemini response for %s: %s", source_label, response_text)
                result: MenuItemList = MenuItemList.model_validate_json(response_text)
                logger.info("Gemini extracted %d items from %s", len(result.items), source_label)

                if log_path is not None:
                    _save_log(log_path, source_label, response_text)

                return result.items
            except APIError as exc:
                if _is_daily_quota(exc):
                    logger.error("Daily quota exhausted for %s, skipping retries", source_label)
                    if log_path is not None:
                        _save_log(log_path, source_label, f"ERROR: daily quota exhausted — {exc}")
                    return []
                delay: float = _parse_retry_delay(exc) or self.RETRY_FALLBACK_DELAY
                logger.warning(
                    "Gemini API error (attempt %d/%d) for %s: %s. Retrying in %.0fs",
                    attempt + 1, self.MAX_RETRIES, source_label, exc, delay,
                )
                if attempt < self.MAX_RETRIES - 1:
                    await asyncio.sleep(delay)
                else:
                    logger.error("Gemini extraction failed after %d retries for %s",
                                 self.MAX_RETRIES, source_label)
                    if log_path is not None:
                        _save_log(log_path, source_label, f"ERROR: {exc}")
                    return []
            except Exception:
                logger.exception("Gemini extraction failed for %s", source_label)
                if log_path is not None:
                    _save_log(log_path, source_label, "ERROR: see application logs")
                return []
        return []

    async def extract(self, clean_text: str, log_path: Path | None = None) -> list[MenuItem]:
        """Send cleaned page text to Gemini and parse structured response."""
        if not clean_text.strip():
            logger.info("No text provided")
            return []

        prompt: str = f"{SYSTEM_PROMPT}\n\n---\n\n{clean_text}"
        return await self._call_gemini(prompt, source_label="html_text", log_path=log_path)

    async def extract_from_pdf(
        self, pdf_data: bytes, source_url: str, log_path: Path | None = None,
    ) -> list[MenuItem]:
        """Send PDF binary data to Gemini for menu extraction."""
        logger.info("Extracting menu from PDF: %s (%d bytes)", source_url, len(pdf_data))
        parts: list[Part] = [
            Part(inline_data=Blob(data=pdf_data, mime_type="application/pdf")),
            Part(text=SYSTEM_PROMPT),
        ]
        return await self._call_gemini(
            parts, source_label=f"pdf:{source_url}", log_path=log_path,
            model=self._pdf_model,
        )

def _is_daily_quota(exc: APIError) -> bool:
    """Check if the error is a daily quota limit (not worth retrying)."""
    try:
        error_details = exc.details.get("error", {}).get("details", [])  # type: ignore[union-attr]
        for detail in error_details:
            if str(detail.get("@type", "")).endswith("QuotaFailure"):
                for violation in detail.get("violations", []):
                    if "PerDay" in str(violation.get("quotaId", "")):
                        return True
    except Exception:
        pass
    return False


def _parse_retry_delay(exc: APIError) -> float | None:
    """Extract retryDelay seconds from Gemini API error details."""
    try:
        error_details = exc.details.get("error", {}).get("details", [])  # type: ignore[union-attr]
        for detail in error_details:
            if str(detail.get("@type", "")).endswith("RetryInfo"):
                raw = str(detail.get("retryDelay", ""))
                match = re.match(r"(\d+)", raw)
                if match:
                    return float(match.group(1)) + 5.0
    except Exception:
        pass
    return None


def _save_log(log_path: Path, request_text: str, response_text: str) -> None:
    """Save LLM request/response pair to a text file."""
    content: str = f"REQUEST:\n{request_text}\n\nRESPONSE:\n{response_text}\n"
    log_path.write_text(content, encoding="utf-8")
