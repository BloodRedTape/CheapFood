"""Extract menu items from PDF files using OpenAI vision."""
from __future__ import annotations

import asyncio
import base64
import logging
from pathlib import Path

import fitz  # pymupdf
from openai import AsyncOpenAI, RateLimitError
from pydantic import BaseModel, Field

from menu_scraper.models.menu import MenuCategory
from menu_scraper.processing.prompts import MENU_ITEM_FIELDS, MENU_ITEM_RULES

logger: logging.Logger = logging.getLogger(__name__)

SYSTEM_PROMPT: str = f"""You are a menu parser. You receive images of pages from a restaurant menu PDF.
Extract ALL menu items grouped by category. For each category return:
- name: category name as written (e.g. "Starters", "Main Course"), or null if no category is apparent
- items: list of dishes in that category

{MENU_ITEM_FIELDS}

Rules:
- Group items by the section headers/titles found in the PDF
- If all items belong to no clear category, return a single category with name null
{MENU_ITEM_RULES}"""

_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "categories": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "name": {"type": ["string", "null"]},
                    "items": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "name": {"type": "string"},
                                "description": {"type": ["string", "null"]},
                                "variations": {
                                    "type": "array",
                                    "items": {
                                        "type": "object",
                                        "properties": {
                                            "price": {"type": ["number", "null"]},
                                            "currency": {"type": "string"},
                                            "unit": {"type": ["string", "null"]},
                                            "unit_size": {"type": ["number", "null"]},
                                        },
                                        "required": ["price", "currency", "unit", "unit_size"],
                                        "additionalProperties": False,
                                    },
                                },
                            },
                            "required": ["name", "description", "variations"],
                            "additionalProperties": False,
                        },
                    },
                },
                "required": ["name", "items"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["categories"],
    "additionalProperties": False,
}


class MenuCategoryList(BaseModel):
    categories: list[MenuCategory] = Field(default_factory=list)

def _pdf_to_images(pdf_data: bytes, dpi: int = 300) -> list[str]:
    """Изменено: dpi увеличено до 300 для лучшего распознавания мелкого текста."""
    doc: fitz.Document = fitz.open(stream=pdf_data, filetype="pdf")
    matrix: fitz.Matrix = fitz.Matrix(dpi / 72, dpi / 72)
    images: list[str] = []
    for page in doc:
        pix: fitz.Pixmap = page.get_pixmap(matrix=matrix)
        png_bytes: bytes = pix.tobytes("png")
        images.append(base64.b64encode(png_bytes).decode())
    doc.close()
    return images

class PdfMenuExtractor:
    MAX_RETRIES: int = 3
    RETRY_FALLBACK_DELAY: float = 60.0

    def __init__(self, api_key: str, model: str = "gpt-4o", rpm: int = 10) -> None:
        self._client: AsyncOpenAI = AsyncOpenAI(api_key=api_key)
        self._model: str = model
        self._semaphore: asyncio.Semaphore = asyncio.Semaphore(1)
        self._interval: float = 60.0 / rpm # Чуть строже, 60 секунд
        self._last_call: float = 0.0

    async def extract(
        self, pdf_data: bytes, source_url: str, log_path: Path | None = None,
    ) -> list[MenuCategory]:
        
        images: list[str] = await asyncio.to_thread(_pdf_to_images, pdf_data, 300)
        
        # Создаем задачи для параллельной обработки каждой страницы
        tasks = [
            self._process_single_page(img_b64, i, source_url)
            for i, img_b64 in enumerate(images, start=1)
        ]
        
        # Ждем выполнения всех страниц
        pages_results = await asyncio.gather(*tasks)
        
        # Объединяем категории со всех страниц
        all_categories: list[MenuCategory] = []
        for page_categories in pages_results:
            if page_categories:
                all_categories.extend(page_categories)
                
        return all_categories

    async def _process_single_page(self, img_b64: str, page_num: int, source_url: str) -> list[MenuCategory]:
        content = [
            {"type": "text", "text": SYSTEM_PROMPT},
            {
                "type": "image_url",
                "image_url": {"url": f"data:image/png;base64,{img_b64}", "detail": "high"}
            }
        ]

        for attempt in range(self.MAX_RETRIES):
            try:
                async with self._semaphore:
                    now: float = asyncio.get_event_loop().time()
                    wait: float = self._interval - (now - self._last_call)
                    if wait > 0:
                        await asyncio.sleep(wait)
                    
                    # ОБНОВЛЯЕМ ДО СЕТЕВОГО ВЫЗОВА, чтобы следующие таски считали wait правильно
                    self._last_call = asyncio.get_event_loop().time()

                # Используем встроенный парсер SDK для Pydantic
                response = await self._client.beta.chat.completions.parse(
                    model=self._model,
                    messages=[{"role": "user", "content": content}],
                    response_format=MenuCategoryList,
                    max_tokens=4096, # Защита от обрезания длинных списков
                )
                
                parsed_result = response.choices[0].message.parsed
                return parsed_result.categories if parsed_result else []

            except RateLimitError as exc:
                if attempt < self.MAX_RETRIES - 1:
                    await asyncio.sleep(self.RETRY_FALLBACK_DELAY)
                else:
                    logger.error("Rate limit failed for page %d", page_num)
                    return []
                    
            except ValidationError as exc:
                # Теперь ошибки Pydantic ловятся, и цикл может сделать ретрай
                if attempt < self.MAX_RETRIES - 1:
                    await asyncio.sleep(2)
                else:
                    logger.error("Validation failed for page %d: %s", page_num, exc)
                    return []
                    
            except Exception as exc:
                if attempt < self.MAX_RETRIES - 1:
                    await asyncio.sleep(2)
                else:
                    logger.exception("Extraction failed for page %d", page_num)
                    return []
                    
        return []
    
def _save_images(log_path: Path, images: list[str]) -> None:
    """Save base64-encoded PNG images next to the log file as page_1.png, page_2.png, ..."""
    stem: str = log_path.stem  # e.g. "doc_abc123.llm"
    for i, img_b64 in enumerate(images, start=1):
        out_path: Path = log_path.parent / f"{stem}_page_{i}.png"
        out_path.write_bytes(base64.b64decode(img_b64))


def _save_log(log_path: Path, request_text: str, response_text: str) -> None:
    """Save LLM request/response pair to a text file."""
    content: str = f"REQUEST:\n{request_text}\n\nRESPONSE:\n{response_text}\n"
    log_path.write_text(content, encoding="utf-8")
