from decimal import Decimal
from enum import StrEnum

from pydantic import BaseModel, Field, field_validator

_CURRENCY_SYMBOL_MAP: dict[str, str] = {
    "$": "USD",
    "€": "EUR",
    "£": "GBP",
    "¥": "JPY",
    "₽": "RUB",
    "₴": "UAH",
    "₺": "TRY",
    "₹": "INR",
    "₩": "KRW",
    "₪": "ILS",
    "Kč": "CZK",
    "zł": "PLN",
    "kr": "SEK",
    "Fr": "CHF",
    "kn": "HRK",
    "lei": "RON",
    "лв": "BGN",
    "Ft": "HUF",
    "Nkr": "NOK",
    "Dkr": "DKK",
}


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
    unit: str | None = None
    unit_size: Decimal | None = None

    @field_validator("currency", mode="before")
    @classmethod
    def normalize_currency(cls, v: str) -> str:
        return _CURRENCY_SYMBOL_MAP.get(v, v).upper()


class MenuCategory(BaseModel):
    name: str | None = None
    items: list[MenuItem] = Field(default_factory=list)


class MenuResult(BaseModel):
    url: str
    restaurant_name: str | None = None
    categories: list[MenuCategory] = Field(default_factory=list)
    source_type: MenuSourceType = MenuSourceType.HTML_TEXT
    media_files: list[MediaFile] = Field(default_factory=list)
