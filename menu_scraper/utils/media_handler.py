from __future__ import annotations

import hashlib
import os
import re
from pathlib import Path
from urllib.parse import urlparse
import logging

import httpx

logger: logging.Logger = logging.getLogger(__name__)


async def download_file(url: str, dest_dir: str) -> str:
    """Download a file from URL to destination directory. Returns local path."""
    os.makedirs(dest_dir, exist_ok=True)

    url_hash: str = hashlib.md5(url.encode()).hexdigest()[:12]
    # Guess extension from URL
    ext: str = _guess_extension(url)
    filename: str = f"{url_hash}{ext}"
    local_path: str = str(Path(dest_dir) / filename)

    if os.path.exists(local_path):
        return local_path

    async with httpx.AsyncClient(follow_redirects=True, timeout=30.0) as client:
        response: httpx.Response = await client.get(url)
        response.raise_for_status()
        with open(local_path, "wb") as f:
            f.write(response.content)

    return local_path


def _guess_extension(url: str) -> str:
    """Guess file extension from URL."""
    lower: str = url.lower().split("?")[0]
    if lower.endswith(".pdf"):
        return ".pdf"
    if lower.endswith(".png"):
        return ".png"
    if lower.endswith(".webp"):
        return ".webp"
    if lower.endswith((".jpg", ".jpeg")):
        return ".jpg"
    return ".bin"

async def download_pdf(
    client: httpx.AsyncClient,
    url: str,
    pdf_dir: Path,
) -> tuple[bytes, Path] | None:
    """Download a PDF file and save to disk. Returns (pdf_bytes, local_path) or None."""
    try:
        response: httpx.Response = await client.get(url)
        response.raise_for_status()
    except httpx.HTTPError as exc:
        logger.warning("Failed to download PDF %s: %s", url, exc)
        return None

    pdf_data: bytes = response.content
    if len(pdf_data) < 100:
        logger.warning("PDF too small, likely not a real PDF: %s (%d bytes)", url, len(pdf_data))
        return None

    url_hash: str = hashlib.md5(url.encode()).hexdigest()[:10]
    parsed = urlparse(url)
    stem: str = parsed.path.strip("/").replace("/", "_").removesuffix(".pdf") or "doc"
    safe_stem: str = re.sub(r"[^a-zA-Z0-9_]", "", stem)[:60]
    filename: str = f"{safe_stem}_{url_hash}.pdf"
    local_path: Path = pdf_dir / filename
    local_path.write_bytes(pdf_data)
    logger.info("Saved PDF: %s -> %s (%d bytes)", url, filename, len(pdf_data))

    return pdf_data, local_path


def looks_like_pdf(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.path.lower().endswith(".pdf"):
        return True
    return ".pdf" in parsed.query.lower()
