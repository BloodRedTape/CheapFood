"""Shared LLM prompt fragments for menu extraction."""

MENU_ITEM_FIELDS: str = """For each item return:
- name: dish name exactly as written
- description: dish description if present, null otherwise
- variations: array of price/size variations for this item. Each variation has:
  - price: numeric price if present, null otherwise
  - currency: ISO currency code (USD, EUR, CZK, ILS, GBP, etc.) — detect from menu context (e.g. "Kč"/"CZK"/"49,- Kč" → "CZK", "€" → "EUR", "$" → "USD"); if the same currency appears throughout the menu, apply it to all items; if truly unknown, null
  - unit: serving/portion size unit as a STRING — the unit label only, e.g. "L", "ml", "cl", "dl", "g", "kg", "pcs", "portion" — NEVER a number
  - unit_size: serving/portion size quantity as a NUMBER — the numeric amount only, e.g. 0.5, 330, 100 — NEVER a string"""

MENU_ITEM_RULES: str = """- Extract every item that looks like a menu dish or drink, even if it has no price
- Keep original dish names and category names, do not translate
- Normalize capitalization: sentence case (first letter capital, rest lowercase) except for proper nouns and brand names. E.g. "SVÍČKOVÁ NA SMETANĚ" → "Svíčková na smetaně", "ČEPOVANÁ PIVA" → "Čepovaná piva", "Pilsner Urquell" stays as is, "COCA COLA" → "Coca Cola". Never lowercase the very first letter of a name.
- Strip leading numbering or codes from dish names. E.g. "12. Svíčková" → "Svíčková", "A3 Smažený sýr" → "Smažený sýr"
- If a serving size (volume, weight, piece count) is extracted into unit/unit_size of a variation, remove it from the item name — whether it appears before or after the name. E.g. "Pilsner 0.5L" → name="Pilsner"; "0,2 l Víno čepované" → name="Víno čepované", unit_size=0.2, unit="l"
- If price has comma as decimal separator, convert to dot (e.g. 12,50 -> 12.50); "49,-" means 49.00 (the ",-" is a Czech notation for whole number price)
- If price is missing or not listed, set price to null in the variation
- Most items have a single variation. Use multiple variations when the item is explicitly offered in different sizes/portions with different prices, e.g. "Pilsner 0.3L 39 Kč / 0.5L 49 Kč" → two variations
- unit and unit_size capture the serving volume, weight, or piece count: e.g. "Pilsner 0.5L 49 Kč" → unit="L", unit_size=0.5; "Svíčková 300g" → unit="g", unit_size=300; "Nuggets 5ks" → unit="ks", unit_size=5; "4 pieces of potatoes" → unit="pcs", unit_size=4
- unit is ALWAYS a string label, unit_size is ALWAYS a number. Split them correctly: "0.5 L" → unit_size=0.5, unit="L". NEVER: unit="0.5", unit_size=1
- If serving size is not mentioned, both unit and unit_size must be null
- variations must never be empty — always include at least one variation (with nulls if no price/size info)
- If no items found, return empty list
- Do NOT invent items or categories that are not in the text"""
