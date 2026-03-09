from __future__ import annotations

import asyncio
import json
import logging

from fastapi import FastAPI, Request
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

from menu_scraper.models.menu import MenuCategory, RestaurantInfo
from menu_scraper.models.requests import ScrapeRequest
from menu_scraper.scraper import scrape_menu

logging.basicConfig(level=logging.INFO)

app: FastAPI = FastAPI(
    title="CheapFood Menu Scraper",
    description="Microservice that scrapes restaurant menus and returns structured JSON",
    version="0.1.0",
)

class ScrapeResult(BaseModel):
    categories: list[MenuCategory]
    restaurant_info: RestaurantInfo


@app.post("/scrape", response_model=ScrapeResult)
async def scrape_endpoint(request: ScrapeRequest) -> ScrapeResult:
    """Scrape a restaurant menu from the given URL."""
    categories, restaurant_info = await scrape_menu(
        url=str(request.url),
        timeout=request.timeout,
        download_media=request.download_media,
    )
    return ScrapeResult(categories=categories, restaurant_info=restaurant_info)


@app.post("/scrape/stream")
async def scrape_stream_endpoint(request: ScrapeRequest, http_request: Request) -> StreamingResponse:
    """Scrape with SSE progress stream. Events: progress (text) and result (JSON)."""
    queue: asyncio.Queue[str | None] = asyncio.Queue()

    async def on_progress(msg: str) -> None:
        await queue.put(msg)

    async def run_scrape() -> None:
        try:
            categories, restaurant_info = await scrape_menu(
                url=str(request.url),
                timeout=request.timeout,
                download_media=request.download_media,
                on_progress=on_progress,
            )
            payload = json.dumps({
                "categories": [c.model_dump(mode="json") for c in categories],
                "restaurant_info": restaurant_info.model_dump(mode="json"),
            })
            await queue.put(f"\x00RESULT\x00{payload}")
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            await queue.put(f"\x00ERROR\x00{exc}")
        finally:
            await queue.put(None)  # sentinel

    async def event_stream():
        task = asyncio.create_task(run_scrape())
        logging.info("SSE stream started for %s", request.url)
        try:
            while True:
                if await http_request.is_disconnected():
                    logging.info("SSE client disconnected for %s", request.url)
                    task.cancel()
                    return
                try:
                    item = await asyncio.wait_for(queue.get(), timeout=0.5)
                except asyncio.TimeoutError:
                    logging.debug("SSE keep-alive for %s", request.url)
                    yield ": keep-alive\n\n"
                    continue

                if item is None:
                    logging.info("SSE stream finished for %s", request.url)
                    return
                if item.startswith("\x00RESULT\x00"):
                    logging.info("SSE sending result event for %s", request.url)
                    yield f"event: result\ndata: {item[len(chr(0) + 'RESULT' + chr(0)):]}\n\n"
                    return
                if item.startswith("\x00ERROR\x00"):
                    logging.warning("SSE sending error event for %s: %s", request.url, item)
                    yield f"event: error\ndata: {item[len(chr(0) + 'ERROR' + chr(0)):]}\n\n"
                    return
                logging.info("SSE progress event: %s", item)
                yield f"event: progress\ndata: {item}\n\n"
        finally:
            if not task.done():
                task.cancel()

    return StreamingResponse(event_stream(), media_type="text/event-stream")


@app.get("/health")
async def health() -> dict[str, str]:
    """Health check endpoint."""
    return {"status": "ok"}
