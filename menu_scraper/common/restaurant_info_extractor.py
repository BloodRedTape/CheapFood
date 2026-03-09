"""Extract restaurant meta-info (name, working hours, site language) from page text."""
from __future__ import annotations

import logging
from pathlib import Path

from openai import AsyncOpenAI, APIError, RateLimitError
from pydantic import BaseModel

from menu_scraper.models.menu import RestaurantInfo
from menu_scraper.common.html_extractor import clean_html

logger: logging.Logger = logging.getLogger(__name__)

_SYSTEM_PROMPT_BASE: str = """You are extracting basic information about a restaurant from its website page.

Return a JSON object with these fields:
- name: the restaurant's name, or null if not found on this page
- working_hours: opening hours as a human-readable string (e.g. "Mon–Fri 11:00–22:00, Sat–Sun 12:00–23:00"), or null if not found
- site_language: the primary language of the page text as a BCP-47 code (e.g. "en", "ru", "he", "cs", "de"), or null if unclear

Rules:
- Only extract what is explicitly present on the page — do not invent or infer
- For name, the site URL is provided as a hint — the restaurant name is often similar to the domain (e.g. "pivniburza.cz" → likely "Pivní Burza"), use it to recognise the name when it appears in the page text, but do not use the domain itself as the name
- For site_language, detect from the actual page text language, not from the domain or URL
- For working_hours, preserve the original format from the page as closely as possible
- If you cannot find a field, return null for it"""


def _make_system_prompt(site_url: str) -> str:
    return f"{_SYSTEM_PROMPT_BASE}\n\nSite URL: {site_url}"


class _LLMResponse(BaseModel):
    name: str | None = None
    working_hours: str | None = None
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
        log_dir: Path | None = None,
    ) -> RestaurantInfo:
        """Iterate pages (html, filename) until RestaurantInfo is complete or pages exhausted."""
        info = RestaurantInfo()
        for html, filename in pages:
            text = clean_html(html)
            if not text.strip():
                continue
            page_info = await self._extract_from_text(text, site_url=site_url, filename=filename, log_dir=log_dir)
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
        log_dir: Path | None = None,
    ) -> RestaurantInfo:
        log_path: Path | None = None
        if log_dir is not None and filename is not None:
            stem = Path(filename).stem
            (log_dir / f"{stem}.txt").write_text(text, encoding="utf-8")
            log_path = log_dir / f"{stem}.llm.txt"

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
                    working_hours=parsed.working_hours,
                    site_language=parsed.site_language,
                )
                if log_path is not None:
                    _save_log(log_path, text, result.model_dump_json())
                return result

            except RateLimitError as exc:
                logger.warning(
                    "OpenAI rate limit (attempt %d/%d): %s",
                    attempt + 1, self.MAX_RETRIES, exc,
                )
                if attempt < self.MAX_RETRIES - 1:
                    import asyncio
                    await asyncio.sleep(self.RETRY_FALLBACK_DELAY)
                else:
                    logger.error("RestaurantInfo extraction failed after %d retries", self.MAX_RETRIES)
                    if log_path is not None:
                        _save_log(log_path, text, f"ERROR: {exc}")
                    return RestaurantInfo()

            except (APIError, Exception) as exc:
                logger.exception("RestaurantInfo extraction error: %s", exc)
                if log_path is not None:
                    _save_log(log_path, text, f"ERROR: {exc}")
                return RestaurantInfo()

        return RestaurantInfo()


def _save_log(log_path: Path, request_text: str, response_text: str) -> None:
    content: str = f"REQUEST:\n{request_text}\n\nRESPONSE:\n{response_text}\n"
    log_path.write_text(content, encoding="utf-8")
