"""Parser for choiceQR-based restaurant websites (choiceqr.com platform)."""
from __future__ import annotations

import json
import logging
import re
from decimal import Decimal
from pathlib import Path

from menu_scraper.models.menu import MenuItem, MenuCategory, MenuItemVariation, RestaurantInfo

logger: logging.Logger = logging.getLogger(__name__)

_NEXT_DATA_RE = re.compile(
    r'<script[^>]+id=["\']__NEXT_DATA__["\'][^>]*>(.*?)</script>',
    re.DOTALL,
)

_DAY_NAMES: list[str] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]


def _extract_next_data(html: str) -> dict | None:
    match = _NEXT_DATA_RE.search(html)
    if not match:
        return None
    try:
        return json.loads(match.group(1))
    except json.JSONDecodeError:
        logger.warning("Failed to parse __NEXT_DATA__ JSON")
        return None


def _parse_price(raw: int) -> Decimal:
    """choiceQR stores price in centimes (5000 = 50.00)."""
    return Decimal(raw) / Decimal(100)


def _format_time(t: str) -> str:
    """'11:00:00.000' → '11:00'"""
    return t[:5]


def _format_work_time(work_time_all: list[dict]) -> str | None:
    """Convert workTimeAll array to human-readable string like 'Mon–Fri 11:00–22:00, Sat 11:00–23:00, Sun 12:00–21:00'."""
    active = [d for d in work_time_all if d.get("active", False)]
    if not active:
        return None

    # Group consecutive days with same hours
    day_groups: list[tuple[list[int], str]] = []
    for day in sorted(active, key=lambda d: d["dayOfWeek"]):
        day_idx: int = day["dayOfWeek"]
        from_t: str = _format_time(day.get("from", ""))
        till_t: str = _format_time(day.get("till", ""))
        hours: str = f"{from_t}–{till_t}"
        if day_groups and day_groups[-1][1] == hours and day_groups[-1][0][-1] == day_idx - 1:
            day_groups[-1][0].append(day_idx)
        else:
            day_groups.append(([day_idx], hours))

    parts: list[str] = []
    for days, hours in day_groups:
        if len(days) == 1:
            parts.append(f"{_DAY_NAMES[days[0]]} {hours}")
        else:
            parts.append(f"{_DAY_NAMES[days[0]]}–{_DAY_NAMES[days[-1]]} {hours}")

    return ", ".join(parts) if parts else None


class ChoiceQrParser:
    def parse(self, pages: list[tuple[str, str]], log_dir: Path) -> tuple[list[MenuCategory], RestaurantInfo]:
        """Parse menu and restaurant info from crawled HTML pages.

        Args:
            pages: list of (html_content, filename) tuples from CrawlResult.pending_texts
            log_dir: directory for debug output
        """
        for html, filename in pages:
            data = _extract_next_data(html)
            if data is not None:
                logger.info("choiceQR: found __NEXT_DATA__ in %s", filename)
                categories, info = self._parse_data(data)
                if categories:
                    self._dump_debug(data, log_dir)
                    return categories, info
                logger.warning("choiceQR: __NEXT_DATA__ found but no menu items in %s", filename)

        logger.warning("choiceQR: no usable __NEXT_DATA__ found in any page")
        return [], RestaurantInfo()

    def _parse_data(self, data: dict) -> tuple[list[MenuCategory], RestaurantInfo]:
        app: dict = data.get("props", {}).get("app", {})
        place: dict = app.get("place", {})
        currency: str = place.get("currency", "")

        # Restaurant info
        info = RestaurantInfo(
            name=place.get("name") or None,
            working_hours=_format_work_time(place.get("workTimeAll", [])),
            site_language=app.get("language", {}).get("current") or None,
        )

        # Build category id → name map
        raw_categories: list[dict] = app.get("categories", [])
        cat_map: dict[str, str] = {
            c["_id"]: c["name"]
            for c in raw_categories
            if "_id" in c and "name" in c
        }

        # Collect items from app.menu (full menu list)
        raw_menu: list[dict] = app.get("menu", [])
        items_by_category: dict[str, list[MenuItem]] = {}

        for raw_item in raw_menu:
            if not raw_item.get("available", True):
                continue
            name: str = raw_item.get("name", "").strip()
            if not name:
                continue

            raw_price: int | None = raw_item.get("price")
            weight: int | str | None = raw_item.get("weight") or None
            weight_type: str | None = raw_item.get("weightType") or None

            unit: str | None = None
            unit_size: Decimal | None = None
            if weight is not None and weight_type:
                unit = weight_type
                try:
                    unit_size = Decimal(str(weight))
                except Exception:
                    pass

            variation = MenuItemVariation(
                price=_parse_price(raw_price) if raw_price is not None else None,
                currency=currency or None,
                unit=unit,
                unit_size=unit_size,
            )

            item = MenuItem(
                name=name,
                description=raw_item.get("description", "").strip() or None,
                variations=[variation],
            )

            cat_id: str = raw_item.get("category", "")
            cat_name: str = cat_map.get(cat_id, "")
            if cat_name not in items_by_category:
                items_by_category[cat_name] = []
            items_by_category[cat_name].append(item)

        categories = [
            MenuCategory(name=name or None, items=items)
            for name, items in items_by_category.items()
            if items
        ]
        return categories, info

    def _dump_debug(self, data: dict, log_dir: Path) -> None:
        debug_path = log_dir / "choiceqr_parsed.json"
        try:
            debug_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        except OSError as e:
            logger.warning("choiceQR: failed to write debug file: %s", e)
