"""Detects the type of website from raw HTML."""
from __future__ import annotations

from enum import Enum


class SiteType(Enum):
    CHOICEQR = "choiceqr"
    GENERIC = "generic"


_CHOICEQR_SIGNALS: list[str] = [
    "cdn-clients.choiceqr.com",
    "cdn-media.choiceqr.com",
    "choiceqr",
]

_CHOICEQR_MIN_SIGNALS: int = 3


def detect_site_type(html: str) -> SiteType:
    """Detect site type from HTML content of the main page."""
    if "__NEXT_DATA__" in html:
        signal_count = sum(1 for s in _CHOICEQR_SIGNALS if s in html)
        if signal_count >= _CHOICEQR_MIN_SIGNALS:
            return SiteType.CHOICEQR
    return SiteType.GENERIC
