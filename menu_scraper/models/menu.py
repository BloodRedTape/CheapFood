from __future__ import annotations

from decimal import Decimal
from enum import StrEnum

from pydantic import BaseModel, Field


class MenuSourceType(StrEnum):
    HTML_TEXT = "html_text"
    IMAGE = "image"
    PDF = "pdf"


class MediaFile(BaseModel):
    original_url: str
    local_path: str
    media_type: MenuSourceType
    ocr_text: str | None = None


class MenuItem(BaseModel):
    name: str
    description: str | None = None
    price: Decimal | None = None
    currency: str = "USD"


class MenuResult(BaseModel):
    url: str
    restaurant_name: str | None = None
    items: list[MenuItem] = Field(default_factory=list)
    source_type: MenuSourceType = MenuSourceType.HTML_TEXT
    media_files: list[MediaFile] = Field(default_factory=list)
    raw_text: str | None = None
