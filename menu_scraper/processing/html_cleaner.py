import trafilatura

def clean_html(html: str) -> str:
    # extract() возвращает чистый текст с правильным форматированием
    text = trafilatura.extract(html)
    return text if text else ""