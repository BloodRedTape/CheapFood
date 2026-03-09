"""Scraper quality test — runs scraper against a list of URLs and reports metrics."""
from __future__ import annotations

import asyncio
import logging
import sys
import time
from dataclasses import dataclass, field

from menu_scraper.models.menu import MenuCategory
from menu_scraper.scraper.scraper import scrape_menu

logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")

# ---------------------------------------------------------------------------
# URLs to test
# ---------------------------------------------------------------------------
TEST_URLS: list[str] = [
            "https://pivniburza.cz",
            "https://east-village6.webnode.cz/",
            "https://www.zadnycukrbliky.cz/",
            "http://www.restauracedukat.cz/",
            "http://www.fabrik.cz/",
            "http://www.bill.cz/",
            "http://www.ochutnavkovapivnice.cz/",
            "https://stopkova.kolkovna.cz/",
            "https://www.utomana.cz/",
            "http://www.fraumayer.at/",
            "http://www.vogelkaffee.at/",
            "https://www.xn--ferhat-dner-yfb.at/",
            "https://faencyfries.cz/",
            "https://brno.doebikokota.cz",
            "https://brno.ftfck.cz",
            "https://smashburgersbrno.cz/",
            "https://udrevaka.cz/",
            "https://www.pizzaalcapone.cz/",
            "http://www.silenymysak.cz/",
            "http://www.pivniceucolka.cz/",
            "https://chilligardenvn.com/",
            "http://www.zadnycukrbliky.cz/",
            "https://www.cukrbliky.cz/",
            "http://betlem-restaurant.cz/",
            "http://www.naskopek.cz/",
            "https://knvrestaurant.cz",
            "http://www.noknokrestaurant.cz/"
]

# ---------------------------------------------------------------------------
# Thresholds for the global quality score
# ---------------------------------------------------------------------------
MIN_ITEMS = 3          # site is considered "broken" if fewer items found
MIN_PRICE_PCT = 0.5    # at least 50% of items should have a price


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------
@dataclass
class SiteResult:
    url: str
    total_items: int = 0
    items_with_price: int = 0
    elapsed_s: float = 0.0
    error: str | None = None

    @property
    def price_pct(self) -> float:
        return self.items_with_price / self.total_items if self.total_items else 0.0

    @property
    def ok(self) -> bool:
        return (
            self.error is None
            and self.total_items >= MIN_ITEMS
            and self.price_pct >= MIN_PRICE_PCT
        )


@dataclass
class QualityReport:
    results: list[SiteResult] = field(default_factory=list)

    @property
    def score(self) -> float:
        """Fraction of sites that passed all thresholds."""
        if not self.results:
            return 0.0
        return sum(1 for r in self.results if r.ok) / len(self.results)

    @property
    def total_items(self) -> int:
        return sum(r.total_items for r in self.results)

    @property
    def overall_price_pct(self) -> float:
        with_price = sum(r.items_with_price for r in self.results)
        return with_price / self.total_items if self.total_items else 0.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _count(categories: list[MenuCategory]) -> tuple[int, int]:
    """Return (total_items, items_with_price)."""
    total = 0
    with_price = 0
    for cat in categories:
        for item in cat.items:
            total += 1
            if any(v.price is not None for v in item.variations):
                with_price += 1
    return total, with_price


async def _run_one(url: str) -> SiteResult:
    result = SiteResult(url=url)
    t0 = time.monotonic()
    try:
        categories, _ = await scrape_menu(url)
        result.total_items, result.items_with_price = _count(categories)
    except Exception as exc:
        result.error = str(exc)
    result.elapsed_s = time.monotonic() - t0
    return result


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
def _bar(value: float, width: int = 20) -> str:
    filled = round(value * width)
    return "[" + "#" * filled + "." * (width - filled) + "]"


def _print_report(report: QualityReport) -> None:
    COL = 45
    print()
    print("=" * 72)
    print(f"  SCRAPER QUALITY REPORT  —  {len(report.results)} URLs")
    print("=" * 72)
    print(f"  {'URL':<{COL}}  {'items':>5}  {'price%':>6}  {'time':>6}  status")
    print("-" * 72)

    for r in report.results:
        url_display = r.url[:COL]
        if r.error:
            status = f"ERROR: {r.error[:30]}"
            print(f"  {url_display:<{COL}}  {'—':>5}  {'—':>6}  {r.elapsed_s:>5.1f}s  {status}")
        else:
            status = "OK" if r.ok else "FAIL"
            flags = []
            if r.total_items < MIN_ITEMS:
                flags.append(f"<{MIN_ITEMS} items")
            if r.price_pct < MIN_PRICE_PCT:
                flags.append(f"price%<{MIN_PRICE_PCT*100:.0f}%")
            if flags:
                status = f"FAIL ({', '.join(flags)})"
            print(
                f"  {url_display:<{COL}}  {r.total_items:>5}  {r.price_pct:>5.0%}  "
                f"{r.elapsed_s:>5.1f}s  {status}"
            )

    print("=" * 72)
    passed = sum(1 for r in report.results if r.ok)
    print(f"  Passed:        {passed}/{len(report.results)}")
    print(f"  Total items:   {report.total_items}")
    print(f"  Avg price%:    {report.overall_price_pct:.0%}")
    print(f"  Quality score: {report.score:.0%}  {_bar(report.score)}")
    print("=" * 72)
    print()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
async def main() -> None:
    urls = TEST_URLS
    if len(sys.argv) > 1:
        urls = sys.argv[1:]

    print(f"Running scraper on {len(urls)} URL(s)...")
    results = await asyncio.gather(*[_run_one(url) for url in urls])

    report = QualityReport(results=list(results))
    _print_report(report)

    sys.exit(0 if report.score == 1.0 else 1)


if __name__ == "__main__":
    asyncio.run(main())
