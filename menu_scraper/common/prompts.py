"""Shared LLM prompt fragments for menu extraction."""

MENU_ITEM_FIELDS: str = """For each item return:
- name: dish name exactly as written
- description: dish description if present, null otherwise
- variations: array of price/size variations for this item. Each variation has:
  - price: numeric price if present, null otherwise
  - currency: ISO currency code — detect from menu context in this priority order:
    1. Explicit currency symbol or code in the text (e.g. "Kč"/"CZK"/"49,- Kč" → "CZK", "€" → "EUR", "$" → "USD", "zł" → "PLN", "грн" → "UAH")
    2. Language of the menu text (Czech → "CZK", Polish → "PLN", Ukrainian → "UAH", Hungarian → "HUF", Romanian → "RON", Croatian → "HRK", Bulgarian → "BGN", Swedish/Norwegian/Danish → infer from context)
    3. If truly unknown: null
    Apply the same currency to all items in the menu.
  - unit: serving/portion size unit as a STRING — the unit label only, e.g. "L", "ml", "cl", "dl", "g", "kg", "pcs", "portion" — NEVER a number
  - unit_size: serving/portion size quantity as a NUMBER — the numeric amount only, e.g. 0.5, 330, 100 — NEVER a string"""

MENU_ITEM_RULES: str = """- Extract every item that looks like a menu dish or drink, even if it has no price
- Keep original dish names and category names, do not translate
- Normalize capitalization: sentence case (first letter capital, rest lowercase) except for proper nouns and brand names. E.g. "SVÍČKOVÁ NA SMETANĚ" → "Svíčková na smetaně", "ČEPOVANÁ PIVA" → "Čepovaná piva", "Pilsner Urquell" stays as is, "COCA COLA" → "Coca Cola". Never lowercase the very first letter of a name.
- Strip leading numbering or codes from dish names. E.g. "12. Svíčková" → "Svíčková", "A3 Smažený sýr" → "Smažený sýr"
- Serving size always belongs in unit/unit_size, never in the name. If a number+unit appears before or after the dish name, extract it into unit/unit_size and remove it from the name. E.g. "0,35 l Voda" → name="Voda", unit_size=0.35, unit="l"; "0,2 l Víno čepované" → name="Víno čepované", unit_size=0.2, unit="l"; "Pilsner 0.5L" → name="Pilsner", unit_size=0.5, unit="L"
- If price has comma as decimal separator, convert to dot (e.g. 12,50 -> 12.50); "49,-" means 49.00 (the ",-" is a Czech notation for whole number price)
- If price is missing or not listed, set price to null in the variation
- Most items have a single variation. Use multiple variations when the item is explicitly offered in different sizes/portions with different prices, e.g. "Pilsner 0.3L 39 Kč / 0.5L 49 Kč" → two variations
- unit and unit_size capture the serving volume, weight, or piece count: e.g. "Pilsner 0.5L 49 Kč" → unit="L", unit_size=0.5; "Svíčková 300g" → unit="g", unit_size=300; "Nuggets 5ks" → unit="ks", unit_size=5; "4 pieces of potatoes" → unit="pcs", unit_size=4
- unit is ALWAYS a string label, unit_size is ALWAYS a number. Split them correctly: "0.5 L" → unit_size=0.5, unit="L". NEVER: unit="0.5", unit_size=1
- If serving size is not mentioned, both unit and unit_size must be null
- variations must never be empty — always include at least one variation (with nulls if no price/size info)
- If no items found, return empty list
- Do NOT invent items or categories that are not in the text"""
