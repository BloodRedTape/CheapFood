"""Debug file context — writes to disk only when not in production mode."""
from __future__ import annotations

import logging
import shutil
from pathlib import Path

logger: logging.Logger = logging.getLogger(__name__)

_is_prod: bool | None = None


def _get_is_prod() -> bool:
    global _is_prod
    if _is_prod is None:
        from menu_scraper.config import get_settings
        _is_prod = get_settings().is_prod
    return _is_prod


class DebugLogContext:
    """Manages a debug output directory for one scrape run.

    All writes are silently skipped when IS_PROD=true.
    Directories are created lazily on first write.
    """

    def __init__(self, base_dir: Path) -> None:
        self._base_dir = base_dir
        self._dir_created = False

    def _ensure_dir(self) -> bool:
        """Create base_dir if needed. Returns False in production."""
        if _get_is_prod():
            return False
        if not self._dir_created:
            self._base_dir.mkdir(parents=True, exist_ok=True)
            self._dir_created = True
        return True

    def write_file(self, filename: str, content: str, encoding: str = "utf-8") -> None:
        """Write text content to base_dir/filename. No-op in production."""
        if not self._ensure_dir():
            return
        try:
            (self._base_dir / filename).write_text(content, encoding=encoding)
        except OSError as e:
            logger.warning("Failed to write debug file %s: %s", self._base_dir / filename, e)

    def write_bytes_file(self, filename: str, content: bytes) -> Path | None:
        """Write binary content to base_dir/filename. No-op in production, returns path on success."""
        if not self._ensure_dir():
            return None
        path = self._base_dir / filename
        try:
            path.write_bytes(content)
        except OSError as e:
            logger.warning("Failed to write debug file %s: %s", path, e)
            return None
        return path

    def subcontext(self, subdir: str) -> DebugLogContext:
        """Return a new DebugLogContext rooted at base_dir/subdir."""
        return DebugLogContext(self._base_dir / subdir)

    def clear(self) -> None:
        """Delete the entire base_dir tree. No-op in production."""
        if _get_is_prod():
            return
        if self._base_dir.exists():
            shutil.rmtree(self._base_dir)
        self._dir_created = False
