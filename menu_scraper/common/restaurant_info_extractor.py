"""Extract restaurant meta-info (name, working hours, site language) from page text."""
from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from openai import AsyncOpenAI, APIError, RateLimitError
from pydantic import BaseModel, Field

from menu_scraper.models.menu import DaySchedule, RestaurantInfo
from menu_scraper.common.html_extractor import clean_html, extract_favicon_url
from menu_scraper.utils.debug import DebugLogContext

logger: logging.Logger = logging.getLogger(__name__)

_SYSTEM_PROMPT_BASE: str = """You are extracting basic information about a restaurant from its website page.

Return a JSON object with these fields:
- name: the restaurant's name, or null if not found on this page
- phones: list of phone numbers found on the page (strings, e.g. ["+420 123 456 789"]), or [] if none
- address: the restaurant's physical address as a single string, or null if not found
- working_hours: list of objects for each day the restaurant is open, each with:
  - day: integer 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
  - open: opening time as "HH:MM" string, or null if unknown
  - close: closing time as "HH:MM" string, or null if unknown
  Only include days that are explicitly listed as open. [] if no hours found.
- site_language: the primary language of the page text as a BCP-47 code (e.g. "en", "ru", "he", "cs", "de"), or null if unclear

Rules:
- Only extract what is explicitly present on the page — do not invent or infer
- For name, the site URL is provided as a hint — the restaurant name is often similar to the domain (e.g. "pivniburza.cz" → likely "Pivní Burza"), use it to recognise the name when it appears in the page text, but do not use the domain itself as the name
- For site_language, detect from the actual page text language, not from the domain or URL
- If you cannot find a field, return null (or [] for list fields)"""


def _make_system_prompt(site_url: str) -> str:
    return f"{_SYSTEM_PROMPT_BASE}\n\nSite URL: {site_url}"


class _LLMDaySchedule(BaseModel):
    day: int
    open: str | None = None
    close: str | None = None


class _LLMResponse(BaseModel):
    name: str | None = None
    phones: list[str] = Field(default_factory=list)
    address: str | None = None
    working_hours: list[_LLMDaySchedule] = Field(default_factory=list)
    site_language: str | None = None


class RestaurantInfoExtractor:
    """Extracts restaurant meta-info from HTML pages sequentially, stops when complete."""

    MAX_RETRIES: int = 3
    RETRY_FALLBACK_DELAY: float = 60.0

    def __init__(self, api_key: str, model: str = "gpt-4.1-mini") -> None:
        self._client: AsyncOpenAI = AsyncOpenAI(api_key=api_key)
        self._model: str = model

    async def extract_from_pages(
        self,
        pages: list[tuple[str, str]],
        site_url: str,
        ctx: DebugLogContext | None = None,
    ) -> RestaurantInfo:
        """Iterate pages (html, filename) until RestaurantInfo is complete or pages exhausted."""
        info = RestaurantInfo()
        # Extract favicon from the first page (index page)
        if pages:
            first_html = pages[0][0]
            icon_url = extract_favicon_url(first_html, site_url)
            if icon_url:
                info = RestaurantInfo(icon_url=icon_url)
                logger.info("Favicon found: %s", icon_url)
        for html, filename in pages:
            text = clean_html(html)
            if not text.strip():
                continue
            page_info = await self._extract_from_text(text, site_url=site_url, filename=filename, ctx=ctx)
            info = info.merge(page_info)
            logger.info(
                "RestaurantInfo after %s: name=%r, hours=%r, lang=%r",
                filename, info.name, info.working_hours, info.site_language,
            )
            if info.is_complete():
                break
        return info

    async def _extract_from_text(
        self,
        text: str,
        site_url: str,
        filename: str | None = None,
        ctx: DebugLogContext | None = None,
    ) -> RestaurantInfo:
        log_filename: str | None = None
        if ctx is not None and filename is not None:
            stem = Path(filename).stem
            ctx.write_file(f"{stem}.txt", text)
            log_filename = f"{stem}.llm.txt"

        for attempt in range(self.MAX_RETRIES):
            try:
                response = await self._client.beta.chat.completions.parse(
                    model=self._model,
                    messages=[
                        {"role": "system", "content": _make_system_prompt(site_url)},
                        {"role": "user", "content": text},
                    ],
                    response_format=_LLMResponse,
                )
                parsed: _LLMResponse = response.choices[0].message.parsed or _LLMResponse()
                result = RestaurantInfo(
                    name=parsed.name,
                    phones=parsed.phones,
                    address=parsed.address,
                    working_hours=[
                        DaySchedule(day=d.day, open=d.open, close=d.close)
                        for d in parsed.working_hours
                    ],
                    site_language=parsed.site_language,
                )
                if ctx and log_filename:
                    _save_log(ctx, log_filename, text, result.model_dump_json())
                return result

            except RateLimitError as exc:
                logger.warning(
                    "OpenAI rate limit (attempt %d/%d): %s",
                    attempt + 1, self.MAX_RETRIES, exc,
                )
                if attempt < self.MAX_RETRIES - 1:
                    await asyncio.sleep(self.RETRY_FALLBACK_DELAY)
                else:
                    logger.error("RestaurantInfo extraction failed after %d retries", self.MAX_RETRIES)
                    if ctx and log_filename:
                        _save_log(ctx, log_filename, text, f"ERROR: {exc}")
                    return RestaurantInfo()

            except (APIError, Exception) as exc:
                logger.exception("RestaurantInfo extraction error: %s", exc)
                if ctx and log_filename:
                    _save_log(ctx, log_filename, text, f"ERROR: {exc}")
                return RestaurantInfo()

        return RestaurantInfo()


def _save_log(ctx: DebugLogContext, filename: str, request_text: str, response_text: str) -> None:
    content: str = f"REQUEST:\n{request_text}\n\nRESPONSE:\n{response_text}\n"
    ctx.write_file(filename, content)
