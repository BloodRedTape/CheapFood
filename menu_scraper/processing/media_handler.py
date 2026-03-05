from __future__ import annotations

import hashlib
import os
from pathlib import Path

import httpx


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
