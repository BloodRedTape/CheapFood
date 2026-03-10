"""Post-processing pass to improve extracted menu data."""
from __future__ import annotations

import logging
import re

from openai import AsyncOpenAI
from pydantic import BaseModel, Field

from menu_scraper.models.menu import MenuCategory
from menu_scraper.common.menu_filter import MenuFilter, ProgressCallback
from menu_scraper.utils.debug import DebugLogContext

logger: logging.Logger = logging.getLogger(__name__)


class _CategoryEmoji(BaseModel):
    name: str
    clean_name: str
    emoji: str


class _CategoryEmojiList(BaseModel):
    categories: list[_CategoryEmoji] = Field(default_factory=list)


_EMOJI_SYSTEM_PROMPT: str = """You are a restaurant menu assistant.
For each menu category name:
1. Clean the name: strip ALL leading and trailing non-letter/non-digit characters — \
including dots, commas, dashes, colons, semicolons, bullet points, middle dots (·), \
pipes (|), asterisks (*), slashes, decorative underscores, spaces, and any other punctuation or symbols \
used as decorations or dividers (e.g. "___Main___", "-- Starters --", "· Dezerty ·", "• Soups •"). \
Preserve hyphens that are part of the name (e.g. "Catch-of-the-day"). Capitalize the first letter.
2. Choose a single relevant food/drink emoji that best represents the category.

Return the original name (as given), the cleaned name, and the emoji.
Examples:
- "· Dezerty ·" -> clean: "Dezerty", emoji: "🍰"
- "· bezmasá jídla ·" -> clean: "Bezmasá jídla", emoji: "🥗"
- "__Starters__" -> clean: "Starters", emoji: "🥗"
- "Pizza," -> clean: "Pizza", emoji: "🍕"
- "-- Drinks --" -> clean: "Drinks", emoji: "🍹"
- "Desserts." -> clean: "Desserts", emoji: "🍰"
- "Main Course" -> clean: "Main Course", emoji: "🍽️"."""


class MenuEnhancer:
    def __init__(self, api_key: str, model: str = "gpt-4.1-mini") -> None:
        self._client: AsyncOpenAI = AsyncOpenAI(api_key=api_key)
        self._model: str = model

    async def enhance(
        self,
        categories: list[MenuCategory],
        on_progress: ProgressCallback | None = None,
        ctx: DebugLogContext | None = None,
    ) -> list[MenuCategory]:
        """Run all enhancement passes over the menu categories."""
        categories = await MenuFilter(self._client, self._model).filter(
            categories, on_progress, ctx
        )
        if on_progress:
            await on_progress("Adding category emojis...")
        categories = await self._add_category_emojis(categories)
        return categories

    @staticmethod
    def _clean_category_name(name: str) -> str:
        """Strip decorative leading/trailing non-word characters."""
        cleaned = re.sub(r"^[\W_]+|[\W_]+$", "", name, flags=re.UNICODE)
        return cleaned[:1].upper() + cleaned[1:] if cleaned else name

    async def _add_category_emojis(self, categories: list[MenuCategory]) -> list[MenuCategory]:
        """Prepend a fitting emoji to each category name."""
        for cat in categories:
            if cat.name:
                cat.name = self._clean_category_name(cat.name)

        named = [c for c in categories if c.name]
        if not named:
            return categories

        names = [c.name for c in named]  # type: ignore[misc]
        prompt = "Category names:\n" + "\n".join(f"- {n}" for n in names)
        logger.info("Enhancing %d category names: %s", len(names), names)

        try:
            response = await self._client.beta.chat.completions.parse(
                model=self._model,
                messages=[
                    {"role": "system", "content": _EMOJI_SYSTEM_PROMPT},
                    {"role": "user", "content": prompt},
                ],
                response_format=_CategoryEmojiList,
            )
            parsed = response.choices[0].message.parsed
            logger.info("Enhancer raw response: %s", parsed)
            if not parsed:
                logger.warning("Enhancer returned no parsed result")
                return categories

            result_map: dict[str, _CategoryEmoji] = {e.name: e for e in parsed.categories}
            logger.info("Enhancer result_map keys: %s", list(result_map.keys()))
            for cat in named:
                entry = result_map.get(cat.name or "")  # type: ignore[arg-type]
                if entry:
                    cat.name = f"{entry.emoji} {entry.clean_name}"

        except Exception:
            logger.exception("Failed to add category emojis")

        return categories
