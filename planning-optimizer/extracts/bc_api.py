"""API page / API Query reads + recommendation POSTs.

Per ADR 0009, this module is the only BC-talking surface for the math
package. Bulk historical reads are exposed by AL Query objects with
`QueryType = API`; this module follows `@odata.nextLink`, maps the
camelCase response keys to the snake_case shape downstream code (the file
seam and the recommender) consumes, and returns plain dicts ready to write
as CSV.

One fetcher per AL API Query (ILE summary, purchase-receipt LT, and —
later — prod / assembly / transfer LT, open S&D), plus the recommendation
POST surface.
"""

import base64
import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, cast

# JSON-shaped rows: keys are the snake_case column names; values come from BC's
# OData payload and can be any JSON-scalar. `Any` is the honest type at this seam.
JsonRow = dict[str, Any]

API_PATH = "/api/fbakkensen/planningOptimizer/v1.0"

ILE_SUMMARY_CAMEL_TO_SNAKE = {
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "postingDate": "posting_date",
    "quantity": "quantity",
}
ILE_SUMMARY_COLUMNS = list(ILE_SUMMARY_CAMEL_TO_SNAKE.values())

PURCHASE_RECEIPT_LT_CAMEL_TO_SNAKE = {
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "vendorNo": "vendor_no",
    "poOrderDate": "po_order_date",
    "receiptPostingDate": "receipt_posting_date",
    "expectedReceiptDate": "expected_receipt_date",
    "quantity": "quantity",
    "documentNo": "document_no",
}
PURCHASE_RECEIPT_LT_COLUMNS = list(PURCHASE_RECEIPT_LT_CAMEL_TO_SNAKE.values())

PRODUCTION_LT_CAMEL_TO_SNAKE = {
    "prodOrderNo": "prod_order_no",
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "entryKind": "entry_kind",
    "postingDate": "posting_date",
    "prodOrderStartingDate": "prod_order_starting_date",
    "prodOrderFinishingDate": "prod_order_finishing_date",
    "prodOrderEndingDate": "prod_order_ending_date",
}
PRODUCTION_LT_COLUMNS = list(PRODUCTION_LT_CAMEL_TO_SNAKE.values())

ASSEMBLY_LT_CAMEL_TO_SNAKE = {
    "assemblyDocNo": "assembly_doc_no",
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "startingDate": "starting_date",
    "postingDate": "posting_date",
}
ASSEMBLY_LT_COLUMNS = list(ASSEMBLY_LT_CAMEL_TO_SNAKE.values())

TRANSFER_LT_CAMEL_TO_SNAKE = {
    "documentNo": "document_no",
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "postingDate": "posting_date",
    "quantity": "quantity",
}
TRANSFER_LT_COLUMNS = list(TRANSFER_LT_CAMEL_TO_SNAKE.values())


@dataclass(frozen=True)
class BcApiConfig:
    """BC API endpoint + auth + company. Defaults target the local Docker tier."""

    base_url: str = "http://localhost:7052/BC"
    auth: str = "BCRUNNER:Admin123!"
    company_name: str = "CRONUS International Ltd."

    @classmethod
    def from_env(cls) -> "BcApiConfig":
        """Build from BC_API_BASE_URL / BC_AUTH / BC_COMPANY_NAME, falling back to defaults."""
        return cls(
            base_url=os.environ.get("BC_API_BASE_URL", cls.base_url),
            auth=os.environ.get("BC_AUTH", cls.auth),
            company_name=os.environ.get("BC_COMPANY_NAME", cls.company_name),
        )


def fetch_item_ledger_summaries(config: BcApiConfig) -> list[JsonRow]:
    """Paginate the itemLedgerSummary API Query for the configured company.

    Returns rows in the snake_case shape consumers expect — the BC-side
    camelCase is hidden inside this seam.
    """
    return _fetch_paginated(config, "itemLedgerSummaries", ILE_SUMMARY_CAMEL_TO_SNAKE)


def fetch_purchase_receipt_lt(config: BcApiConfig) -> list[JsonRow]:
    """Paginate the purchaseReceiptLT API Query for the configured company.

    Drop-shipments and special orders are excluded server-side by the AL
    Query; `expected_receipt_date` may be null when the source PO has been
    deleted or never had one captured at creation time (per ADR 0006).
    """
    return _fetch_paginated(config, "purchaseReceiptLT", PURCHASE_RECEIPT_LT_CAMEL_TO_SNAKE)


def fetch_production_lt(config: BcApiConfig) -> list[JsonRow]:
    """Paginate the productionLT API Query for the configured company.

    Long-format extract — one row per (finished prod order, ILE entry).
    Cancelled / scrapped prod orders are excluded server-side; the Python
    parser derives `max(Output) − min(Consumption)` per ADR 0006 and falls
    back to header dates when no consumption ILE exists.
    """
    return _fetch_paginated(config, "productionLT", PRODUCTION_LT_CAMEL_TO_SNAKE)


def fetch_assembly_lt(config: BcApiConfig) -> list[JsonRow]:
    """Paginate the assemblyLT API Query — one row per finished posted assembly."""
    return _fetch_paginated(config, "assemblyLT", ASSEMBLY_LT_CAMEL_TO_SNAKE)


def fetch_transfer_lt(config: BcApiConfig) -> list[JsonRow]:
    """Paginate the transferLT API Query — one row per ILE Transfer entry.

    Both source (negative quantity) and destination (positive quantity) rows
    come through; the Python parser pairs them by (document_no, item_no,
    variant_code) per ADR 0006.
    """
    return _fetch_paginated(config, "transferLT", TRANSFER_LT_CAMEL_TO_SNAKE)


def _fetch_paginated(
    config: BcApiConfig, entity_set: str, mapping: dict[str, str]
) -> list[JsonRow]:
    company_id = _resolve_company_id(config)
    rows: list[JsonRow] = []
    url = f"{config.base_url}{API_PATH}/companies({company_id})/{entity_set}"
    while url:
        data = _get_json(config, url)
        rows.extend(_to_snake_case(r, mapping) for r in data["value"])
        url = data.get("@odata.nextLink", "")
    return rows


def _resolve_company_id(config: BcApiConfig) -> str:
    data = _get_json(config, f"{config.base_url}{API_PATH}/companies")
    for company in data["value"]:
        if company["name"] == config.company_name:
            return cast("str", company["id"])
    raise RuntimeError(f"Company not found: {config.company_name}")


def _to_snake_case(camel_row: JsonRow, mapping: dict[str, str]) -> JsonRow:
    return {snake: camel_row[camel] for camel, snake in mapping.items()}


def _get_json(config: BcApiConfig, url: str) -> JsonRow:
    # S310: URL comes from BcApiConfig.base_url (env-driven, http(s)-only by construction).
    # No file:// risk — this is the BC API seam, not an arbitrary URL fetcher.
    req = urllib.request.Request(url, headers={"Authorization": _auth_header(config.auth)})  # noqa: S310
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:  # noqa: S310
            return cast("JsonRow", json.loads(resp.read()))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} on {url}\n{body}") from exc


def _auth_header(auth: str) -> str:
    return "Basic " + base64.b64encode(auth.encode("utf-8")).decode("ascii")
