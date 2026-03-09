"""Extract menu items from images using OpenAI vision."""
from __future__ import annotations

import asyncio
import base64
import logging
from pathlib import Path

from openai import AsyncOpenAI, RateLimitError
from pydantic import BaseModel, Field, ValidationError

from menu_scraper.models.menu import MenuCategory
from menu_scraper.common.prompts import MENU_ITEM_FIELDS, MENU_ITEM_RULES

logger: logging.Logger = logging.getLogger(__name__)

SYSTEM_PROMPT: str = f"""You are a menu parser. You receive images of pages from a restaurant menu.
Extract ALL menu items grouped by category. For each category return:
- name: category name as written (e.g. "Starters", "Main Course"), or null if no category is apparent
- items: list of dishes in that category

{MENU_ITEM_FIELDS}

Rules:
- Group items by the section headers/titles found in the image
- If all items belong to no clear category, return a single category with name null
{MENU_ITEM_RULES}"""


class MenuCategoryList(BaseModel):
    categories: list[MenuCategory] = Field(default_factory=list)


class ImageMenuExtractor:
    MAX_RETRIES: int = 3
    RETRY_FALLBACK_DELAY: float = 60.0

    def __init__(self, api_key: str, model: str = "gpt-4o", rpm: int = 10) -> None:
        self._client: AsyncOpenAI = AsyncOpenAI(api_key=api_key)
        self._model: str = model
        self._semaphore: asyncio.Semaphore = asyncio.Semaphore(1)
        self._interval: float = 60.0 / rpm
        self._last_call: float = 0.0

    async def extract(
        self,
        images_b64: list[str],
        source_url: str,
        log_path: Path | None = None,
    ) -> list[MenuCategory]:
        """Extract menu categories from a list of base64-encoded PNG images."""
        tasks = [
            self._process_single_image(img_b64, i, source_url)
            for i, img_b64 in enumerate(images_b64, start=1)
        ]
        pages_results = await asyncio.gather(*tasks)

        all_categories: list[MenuCategory] = []
        for page_categories in pages_results:
            if page_categories:
                all_categories.extend(page_categories)
        return all_categories

    async def _process_single_image(
        self, img_b64: str, index: int, source_url: str
    ) -> list[MenuCategory]:
        content = [
            {"type": "text", "text": SYSTEM_PROMPT},
            {
                "type": "image_url",
                "image_url": {"url": f"data:image/png;base64,{img_b64}", "detail": "high"},
            },
        ]

        for attempt in range(self.MAX_RETRIES):
            try:
                async with self._semaphore:
                    now: float = asyncio.get_event_loop().time()
                    wait: float = self._interval - (now - self._last_call)
                    if wait > 0:
                        await asyncio.sleep(wait)
                    self._last_call = asyncio.get_event_loop().time()

                response = await self._client.beta.chat.completions.parse(
                    model=self._model,
                    messages=[{"role": "user", "content": content}],
                    response_format=MenuCategoryList,
                    max_tokens=4096,
                )
                parsed_result = response.choices[0].message.parsed
                return parsed_result.categories if parsed_result else []

            except RateLimitError:
                if attempt < self.MAX_RETRIES - 1:
                    await asyncio.sleep(self.RETRY_FALLBACK_DELAY)
                else:
                    logger.error("Rate limit failed for image %d from %s", index, source_url)
                    return []

            except ValidationError as exc:
                if attempt < self.MAX_RETRIES - 1:
                    await asyncio.sleep(2)
                else:
                    logger.error("Validation failed for image %d: %s", index, exc)
                    return []

            except Exception:
                if attempt < self.MAX_RETRIES - 1:
                    await asyncio.sleep(2)
                else:
                    logger.exception("Extraction failed for image %d from %s", index, source_url)
                    return []

        return []
