"""Shared LLM prompt fragments for menu extraction."""

MENU_ITEM_FIELDS: str = """For each item return:
- name: dish name exactly as written
- description: dish description if present, null otherwise
- price: numeric price if present, null otherwise
- currency: ISO currency code (USD, EUR, ILS, GBP, etc.), default USD
- unit: serving/portion size unit as a STRING — the unit label only, e.g. "L", "ml", "cl", "dl", "g", "kg", "pcs", "portion" — NEVER a number
- unit_size: serving/portion size quantity as a NUMBER — the numeric amount only, e.g. 0.5, 330, 100 — NEVER a string"""

MENU_ITEM_RULES: str = """- Extract every item that looks like a menu dish or drink, even if it has no price
- Keep original dish names and category names, do not translate
- If price has comma as decimal separator, convert to dot (e.g. 12,50 -> 12.50)
- If price is missing or not listed, set price to null
- unit and unit_size capture the serving volume, weight, or piece count: e.g. "Pilsner 0.5L 49 Kč" → unit="L", unit_size=0.5; "Svíčková 300g" → unit="g", unit_size=300; "Nuggets 5ks" → unit="ks", unit_size=5; "4 pieces of potatoes" → unit="pcs", unit_size=4
- unit is ALWAYS a string label, unit_size is ALWAYS a number. Split them correctly: "0.5 L" → unit_size=0.5, unit="L". NEVER: unit="0.5", unit_size=1
- If serving size is not mentioned, both unit and unit_size must be null
- If no items found, return empty list
- Do NOT invent items or categories that are not in the text"""
