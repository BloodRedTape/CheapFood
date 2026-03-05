from __future__ import annotations

import re
from decimal import Decimal, InvalidOperation
from typing import ClassVar

from menu_scraper.models.menu import MenuItem

# Price patterns: currency symbol before or after the number
PRICE_PATTERNS: list[re.Pattern[str]] = [
    # $12.50, €10, £8.99
    re.compile(r"([\$€£])\s*(\d+(?:[.,]\d{1,2})?)"),
    # 45₪, 12.50$
    re.compile(r"(\d+(?:[.,]\d{1,2})?)\s*([\$€£₪])"),
    # 45 NIS, 50 ILS, 12 EUR, 10 USD, 45 ש"ח
    re.compile(r'(\d+(?:[.,]\d{1,2})?)\s*(NIS|ILS|EUR|USD|ש"ח)', re.IGNORECASE),
]

CURRENCY_MAP: dict[str, str] = {
    "$": "USD",
    "€": "EUR",
    "£": "GBP",
    "₪": "ILS",
    "NIS": "ILS",
    "ILS": "ILS",
    "EUR": "EUR",
    "USD": "USD",
    'ש"ח': "ILS",
}

# Pattern to split text into individual menu entries
# Looks for lines that contain a name followed by a price
ENTRY_PATTERN: re.Pattern[str] = re.compile(
    r"""
    ^                          # Start of line
    \s*                        # Optional whitespace
    (.+?)                      # Item name (non-greedy)
    \s*[-–—.·:]*\s*            # Separator (dash, dots, colon, etc.)
    (                          # Price group
        [\$€£]?\s*\d+(?:[.,]\d{1,2})?\s*[\$€£₪]?
        | \d+(?:[.,]\d{1,2})?\s*(?:NIS|ILS|EUR|USD|ש"ח)
    )
    \s*$                       # End of line
    """,
    re.VERBOSE | re.MULTILINE | re.IGNORECASE,
)


class HtmlMenuExtractor:
    """Extracts structured menu items from raw text content."""

    def extract(self, text: str, html: str = "") -> list[MenuItem]:
        """Extract menu items from text, optionally using HTML for structure."""
        items: list[MenuItem] = []

        # Try line-by-line extraction with price patterns
        for match in ENTRY_PATTERN.finditer(text):
            name_raw: str = match.group(1).strip()
            price_raw: str = match.group(2).strip()

            if not name_raw or len(name_raw) < 2:
                continue

            price, currency = self._parse_price(price_raw)
            name, description = self._split_name_description(name_raw)

            items.append(
                MenuItem(
                    name=name,
                    description=description,
                    price=price,
                    currency=currency,
                )
            )

        # Deduplicate by name
        seen: set[str] = set()
        unique_items: list[MenuItem] = []
        for item in items:
            key: str = item.name.lower().strip()
            if key not in seen:
                seen.add(key)
                unique_items.append(item)

        return unique_items

    def _parse_price(self, price_str: str) -> tuple[Decimal | None, str]:
        """Parse a price string into a Decimal value and currency code."""
        for pattern in PRICE_PATTERNS:
            match: re.Match[str] | None = pattern.search(price_str)
            if not match:
                continue

            groups: tuple[str, ...] = match.groups()
            # Determine which group is the number and which is the currency
            number_str: str = ""
            currency_str: str = ""

            for group in groups:
                if re.match(r"\d", group):
                    number_str = group
                else:
                    currency_str = group

            if number_str:
                # Normalize comma to dot
                number_str = number_str.replace(",", ".")
                try:
                    price: Decimal = Decimal(number_str)
                except InvalidOperation:
                    continue

                currency: str = CURRENCY_MAP.get(currency_str.upper(), "USD")
                if currency_str in CURRENCY_MAP:
                    currency = CURRENCY_MAP[currency_str]

                return price, currency

        return None, "USD"

    def _split_name_description(self, text: str) -> tuple[str, str | None]:
        """Split a menu item text into name and optional description.

        Looks for common separators: dash, parentheses, newline, pipe.
        """
        # Check for text in parentheses as description
        paren_match: re.Match[str] | None = re.match(
            r"^(.+?)\s*\((.+)\)\s*$", text
        )
        if paren_match:
            return paren_match.group(1).strip(), paren_match.group(2).strip()

        # Check for dash/pipe separator
        sep_match: re.Match[str] | None = re.match(
            r"^(.+?)\s*[-–—|]\s+(.+)$", text
        )
        if sep_match:
            name_part: str = sep_match.group(1).strip()
            desc_part: str = sep_match.group(2).strip()
            # Only treat as description if the second part is long enough
            if len(desc_part) > 5:
                return name_part, desc_part

        return text.strip(), None
