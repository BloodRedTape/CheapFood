"""Parser for choiceQR-based restaurant websites (choiceqr.com platform)."""
from __future__ import annotations

import json
import logging
import re
from decimal import Decimal
from pathlib import Path

from menu_scraper.models.menu import DaySchedule, MenuItem, MenuCategory, MenuItemVariation, RestaurantInfo

logger: logging.Logger = logging.getLogger(__name__)

_NEXT_DATA_RE = re.compile(
    r'<script[^>]+id=["\']__NEXT_DATA__["\'][^>]*>(.*?)</script>',
    re.DOTALL,
)


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


def _parse_work_time(work_time_all: list[dict]) -> list[DaySchedule]:
    """Convert workTimeAll array to list of DaySchedule (active days only)."""
    result: list[DaySchedule] = []
    for day in sorted(work_time_all, key=lambda d: d.get("dayOfWeek", 0)):
        if not day.get("active", False):
            continue
        result.append(DaySchedule(
            day=day["dayOfWeek"],
            open=_format_time(day["from"]) if day.get("from") else None,
            close=_format_time(day["till"]) if day.get("till") else None,
        ))
    return result


class ChoiceQrParser:
    def parse(self, pages: list[tuple[str, str]], log_dir: Path) -> tuple[list[MenuCategory], RestaurantInfo]:
        """Parse menu and restaurant info from crawled HTML pages.

        Args:
            pages: list of (html_content, filename) tuples from CrawlResult.pending_texts
            log_dir: directory for debug output
        """
        best_info: RestaurantInfo = RestaurantInfo()
        for html, filename in pages:
            data = _extract_next_data(html)
            if data is not None:
                logger.info("choiceQR: found __NEXT_DATA__ in %s", filename)
                categories, info = self._parse_data(data)
                best_info = best_info.merge(info)
                if categories:
                    self._dump_debug(data, log_dir)
                    return categories, best_info
                logger.warning("choiceQR: __NEXT_DATA__ found but no menu items in %s", filename)

        logger.warning("choiceQR: no usable __NEXT_DATA__ found in any page")
        return [], best_info

    def _parse_data(self, data: dict) -> tuple[list[MenuCategory], RestaurantInfo]:
        app: dict = data.get("props", {}).get("app", {})
        place: dict = app.get("place", {})
        currency: str = place.get("currency", "")

        # Restaurant info
        contact: dict = place.get("contactInfo", {})
        raw_phone: str | None = contact.get("phone") or None
        phones: list[str] = [raw_phone] if raw_phone else []
        if contact.get("additionalPhones"):
            phones.extend(contact["additionalPhones"])
        address: str | None = (contact.get("address") or {}).get("prediction") or None
        info = RestaurantInfo(
            name=place.get("name") or None,
            phones=phones,
            address=address,
            working_hours=_parse_work_time(place.get("workTimeAll", [])),
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
