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


def detect_site_type(html: str) -> SiteType:
    """Detect site type from HTML content of the main page."""
    for signal in _CHOICEQR_SIGNALS:
        if signal in html:
            return SiteType.CHOICEQR
    return SiteType.GENERIC
