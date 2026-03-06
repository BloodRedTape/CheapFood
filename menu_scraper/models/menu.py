import re
from decimal import Decimal
from enum import StrEnum

from pydantic import BaseModel, Field, field_validator, model_validator

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


class MenuItemVariation(BaseModel):
    price: Decimal | None = None
    currency: str | None = None
    unit: str | None = None
    unit_size: Decimal | None = None

    @field_validator("currency", mode="before")
    @classmethod
    def normalize_currency(cls, v: str | None) -> str | None:
        if v is None:
            return None
        return _CURRENCY_SYMBOL_MAP.get(v, v).upper()


def _capitalize_first(s: str | None) -> str | None:
    if not s:
        return s
    return s[0].upper() + s[1:]


_SIZE_PREFIX_RE = re.compile(
    r"^\s*(\d+(?:[.,]\d+)?)\s*(l|ml|cl|dl|g|kg|ks|pcs|pc|portion)\s+",
    re.IGNORECASE,
)
_SIZE_SUFFIX_RE = re.compile(
    r"\s+(\d+(?:[.,]\d+)?)\s*(l|ml|cl|dl|g|kg|ks|pcs|pc|portion)\s*$",
    re.IGNORECASE,
)


class MenuItem(BaseModel):
    name: str
    description: str | None = None
    variations: list[MenuItemVariation] = Field(default_factory=list)

    @model_validator(mode="after")
    def clean_name(self) -> "MenuItem":
        name = _capitalize_first(self.name) or self.name
        has_size = any(v.unit is not None or v.unit_size is not None for v in self.variations)
        if has_size:
            name = _SIZE_PREFIX_RE.sub("", name).strip()
            name = _SIZE_SUFFIX_RE.sub("", name).strip()
            name = _capitalize_first(name) or name
        self.name = name
        self.description = _capitalize_first(self.description)
        return self


class MenuCategory(BaseModel):
    name: str | None = None
    items: list[MenuItem] = Field(default_factory=list)

    @field_validator("name", mode="before")
    @classmethod
    def capitalize_name(cls, v: str | None) -> str | None:
        return _capitalize_first(v)


class MenuResult(BaseModel):
    url: str
    restaurant_name: str | None = None
    categories: list[MenuCategory] = Field(default_factory=list)
    source_type: MenuSourceType = MenuSourceType.HTML_TEXT
    media_files: list[MediaFile] = Field(default_factory=list)
