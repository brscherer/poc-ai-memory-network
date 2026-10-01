import json
from pathlib import Path

CATALOG = json.loads((Path(__file__).parent.parent / "catalog.json").read_text())


class Cart:
    def __init__(self):
        self.lines = {}  # sku -> quantity

    def add(self, sku, quantity=1):
        if sku not in CATALOG:
            raise KeyError(f"unknown sku: {sku}")
        if quantity < 1:
            raise ValueError("quantity must be at least 1")
        self.lines[sku] = self.lines.get(sku, 0) + quantity

    def remove(self, sku):
        self.lines.pop(sku, None)
