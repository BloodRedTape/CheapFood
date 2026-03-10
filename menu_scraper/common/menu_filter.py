"""Two-pass LLM filter: align category names to items, then remove non-food categories."""
from __future__ import annotations

import asyncio
import logging
import random
from collections.abc import Callable, Coroutine
from typing import Literal

from openai import AsyncOpenAI
from pydantic import BaseModel, Field

from menu_scraper.models.menu import MenuCategory, MenuItem
from menu_scraper.utils.debug import DebugLogContext

logger: logging.Logger = logging.getLogger(__name__)

ProgressCallback = Callable[[str], Coroutine[None, None, None]]

_BATCH_SIZE = 4


# --- Pass 1: name alignment ---

class _NameAlignmentDecision(BaseModel):
    index: int
    action: Literal["ok", "rename"]
    new_name: str | None = None  # only for "rename" — do NOT set for "ok"


class _NameAlignmentBatch(BaseModel):
    decisions: list[_NameAlignmentDecision] = Field(default_factory=list)


_NAME_ALIGNMENT_SYSTEM_PROMPT: str = """You are a restaurant menu data quality checker.
You will receive a batch of menu categories, each with a sample of their items.
For each category, decide if the category name accurately reflects its items:

- ok: the name clearly describes the items — regardless of what language it is in \
(e.g. "Polévky" for soups, "Напитки" for drinks, "Burgery" for burgers — all ok)
- rename: the name does not match the items at all, OR the name is too generic to be useful, \
OR the category has no name at all (shown as "(unnamed)")

Too-generic names that must be renamed: "Menu", "Food", "Dishes", "Items", "Products", "Category", \
"Section", "Other", "Misc", "General", or translations of these in any language. \
A good name is specific: "Drinks", "Meat & Fish", "Pasta", "Hot Appetizers".

CRITICAL: Do NOT rename just because the name is in a foreign language — a foreign-language name that \
fits its items is perfectly ok. Do NOT delete categories here. Do NOT judge \
whether items are food — only whether the name fits. When in doubt, prefer ok.

For "ok": leave new_name empty — the original name will be kept as-is.
For "rename": provide new_name in the same language as the existing items' names.

Return the index and decision for each category."""


# --- Pass 2: food relevance filter ---

class _FoodRelevanceDecision(BaseModel):
    index: int
    action: Literal["keep", "delete"]


class _FoodRelevanceBatch(BaseModel):
    decisions: list[_FoodRelevanceDecision] = Field(default_factory=list)


_FOOD_RELEVANCE_SYSTEM_PROMPT: str = """You are a restaurant menu data quality checker.
You will receive a batch of menu categories, each with a sample of their items.
Decide if each category belongs on a restaurant menu (food, drinks, or meal-related items).

- keep: it's a real food/drink/meal category
- delete: it's not food-related (navigation, UI elements, ads, social media, legal text, \
contact info, or other non-food content)

Be conservative: only delete when clearly not menu content. When in doubt, keep.

Return the index and decision for each category."""


class MenuFilter:
    def __init__(self, client: AsyncOpenAI, model: str) -> None:
        self._client = client
        self._model = model

    async def filter(
        self,
        categories: list[MenuCategory],
        on_progress: ProgressCallback | None = None,
        ctx: DebugLogContext | None = None,
    ) -> list[MenuCategory]:
        """Pass 1: align names to items. Pass 2: remove non-food categories."""
        if not categories:
            return categories

        async def _progress(msg: str) -> None:
            if on_progress:
                await on_progress(msg)

        # Pass 1: align names (all categories — unnamed ones must be renamed from items)
        await _progress(f"Checking category names ({len(categories)} categories)...")
        categories = await self._pass1_align_names(categories, ctx)

        # Pass 2: filter non-food (all categories, unnamed included)
        await _progress(f"Filtering non-food categories ({len(categories)} categories)...")
        categories = await self._pass2_filter_food(categories, ctx)
        return categories

    # --- Pass 1 ---

    async def _pass1_align_names(
        self,
        categories: list[MenuCategory],
        ctx: DebugLogContext | None,
    ) -> list[MenuCategory]:
        batches = _make_batches(categories, _BATCH_SIZE)
        logger.info("Pass 1 (name alignment): %d categories in %d batches", len(categories), len(batches))

        tasks = [
            self._align_names_batch(batch, i, ctx)
            for i, batch in enumerate(batches)
        ]
        batch_results: list[dict[int, _NameAlignmentDecision]] = await asyncio.gather(*tasks)

        decisions_by_id: dict[int, _NameAlignmentDecision] = {}
        for batch, result in zip(batches, batch_results):
            for local_idx, dec in result.items():
                if 0 <= local_idx < len(batch):
                    decisions_by_id[id(batch[local_idx])] = dec

        for cat in categories:
            dec = decisions_by_id.get(id(cat))
            if dec and dec.action == "rename" and dec.new_name and dec.new_name.strip():
                logger.info("Pass 1 rename: %r -> %r", cat.name, dec.new_name)
                cat.name = dec.new_name

        return categories

    async def _align_names_batch(
        self,
        batch: list[MenuCategory],
        batch_index: int,
        ctx: DebugLogContext | None,
    ) -> dict[int, _NameAlignmentDecision]:
        prompt = _format_batch_with_items(batch, sample_size=10)
        log_filename = f"filter_pass1_batch{batch_index}.llm.txt"
        try:
            response = await self._client.beta.chat.completions.parse(
                model=self._model,
                messages=[
                    {"role": "system", "content": _NAME_ALIGNMENT_SYSTEM_PROMPT},
                    {"role": "user", "content": prompt},
                ],
                response_format=_NameAlignmentBatch,
            )
            parsed = response.choices[0].message.parsed
            if not parsed:
                logger.warning("Pass 1 batch returned no parsed result")
                if ctx:
                    _save_log(ctx, log_filename, prompt, "NO PARSED RESULT")
                return {}
            if ctx:
                _save_log(ctx, log_filename, prompt, parsed.model_dump_json())
            return {d.index: d for d in parsed.decisions}
        except Exception:
            logger.exception("Pass 1 batch failed")
            if ctx:
                _save_log(ctx, log_filename, prompt, "ERROR: see application logs")
            return {}

    # --- Pass 2 ---

    async def _pass2_filter_food(
        self,
        categories: list[MenuCategory],
        ctx: DebugLogContext | None,
    ) -> list[MenuCategory]:
        batches = _make_batches(categories, _BATCH_SIZE)
        logger.info("Pass 2 (food filter): %d categories in %d batches", len(categories), len(batches))

        tasks = [
            self._filter_food_batch(batch, i, ctx)
            for i, batch in enumerate(batches)
        ]
        batch_results: list[dict[int, _FoodRelevanceDecision]] = await asyncio.gather(*tasks)

        # Collect object ids to delete
        delete_ids: set[int] = set()
        for batch, result in zip(batches, batch_results):
            for local_idx, dec in result.items():
                if 0 <= local_idx < len(batch) and dec.action == "delete":
                    cat = batch[local_idx]
                    logger.info("Pass 2 delete: %r", cat.name)
                    delete_ids.add(id(cat))

        return [c for c in categories if id(c) not in delete_ids]

    async def _filter_food_batch(
        self,
        batch: list[MenuCategory],
        batch_index: int,
        ctx: DebugLogContext | None,
    ) -> dict[int, _FoodRelevanceDecision]:
        prompt = _format_batch_with_items(batch, sample_size=3)
        log_filename = f"filter_pass2_batch{batch_index}.llm.txt"
        try:
            response = await self._client.beta.chat.completions.parse(
                model=self._model,
                messages=[
                    {"role": "system", "content": _FOOD_RELEVANCE_SYSTEM_PROMPT},
                    {"role": "user", "content": prompt},
                ],
                response_format=_FoodRelevanceBatch,
            )
            parsed = response.choices[0].message.parsed
            if not parsed:
                logger.warning("Pass 2 batch returned no parsed result")
                if ctx:
                    _save_log(ctx, log_filename, prompt, "NO PARSED RESULT")
                return {}
            if ctx:
                _save_log(ctx, log_filename, prompt, parsed.model_dump_json())
            return {d.index: d for d in parsed.decisions}
        except Exception:
            logger.exception("Pass 2 batch failed")
            if ctx:
                _save_log(ctx, log_filename, prompt, "ERROR: see application logs")
            return {}


# --- Helpers ---

def _make_batches(items: list[MenuCategory], size: int) -> list[list[MenuCategory]]:
    return [items[i:i + size] for i in range(0, len(items), size)]


def _format_batch_with_items(batch: list[MenuCategory], sample_size: int) -> str:
    lines: list[str] = []
    for i, cat in enumerate(batch):
        label = cat.name or "(unnamed)"
        lines.append(f"[{i}] Category: {label}")
        sample = _sample_items(cat.items, sample_size)
        for item in sample:
            lines.append(f"  - {item.name}")
    return "\n".join(lines)


def _sample_items(items: list[MenuItem], n: int) -> list[MenuItem]:
    if len(items) <= n:
        return items
    return random.sample(items, n)


def _save_log(ctx: DebugLogContext, filename: str, request_text: str, response_text: str) -> None:
    content: str = f"REQUEST:\n{request_text}\n\nRESPONSE:\n{response_text}\n"
    ctx.write_file(filename, content)
