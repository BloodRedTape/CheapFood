from __future__ import annotations


class GeminiOCRProcessor:
    """Stub for future Gemini-based menu image/PDF processing.

    Will send images to Gemini Vision API to extract menu text.
    """

    async def process_image(self, image_path: str) -> str | None:
        """Extract menu text from an image file. Not yet implemented."""
        # TODO: Implement with google-generativeai SDK
        # Will send image to Gemini with prompt:
        # "Extract all menu items with names, descriptions, and prices from this image"
        return None

    async def process_pdf(self, pdf_path: str) -> str | None:
        """Extract menu text from a PDF file. Not yet implemented."""
        # TODO: Implement with Gemini PDF support
        return None
