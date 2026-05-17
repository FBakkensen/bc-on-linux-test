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
from functools import lru_cache
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

# Per-source AL Query mappings for the open Supply & Demand event stream
# (ADR 0001 inclusion policy, ADR 0007 simulator seed). Each Query exposes
# its native BC column shape; the fetchers below project each row into the
# unified event shape consumers see.
OPEN_SD_SALES_CAMEL_TO_SNAKE = {
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "shipmentDate": "event_date",
    "outstandingQtyBase": "qty",
    "documentType": "document_type",
}
OPEN_SD_PURCHASE_CAMEL_TO_SNAKE = {
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "expectedReceiptDate": "event_date",
    "outstandingQtyBase": "qty",
    "documentType": "document_type",
}
OPEN_SD_TRANSFER_IN_CAMEL_TO_SNAKE = {
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "receiptDate": "event_date",
    "outstandingQtyBase": "qty",
}
OPEN_SD_TRANSFER_OUT_CAMEL_TO_SNAKE = {
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "shipmentDate": "event_date",
    "outstandingQtyBase": "qty",
}
OPEN_SD_SERVICE_CAMEL_TO_SNAKE = {
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "neededByDate": "event_date",
    "outstandingQtyBase": "qty",
}
OPEN_SD_PROD_ORDER_LINE_CAMEL_TO_SNAKE = {
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "dueDate": "event_date",
    "remainingQtyBase": "qty",
}
OPEN_SD_ASSEMBLY_HEADER_CAMEL_TO_SNAKE = {
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "dueDate": "event_date",
    "remainingQtyBase": "qty",
}
OPEN_SD_JOB_PLANNING_CAMEL_TO_SNAKE = {
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "planningDate": "event_date",
    "remainingQtyBase": "qty",
    "lineType": "line_type",
}

OPEN_SD_EVENT_COLUMNS = [
    "item_no",
    "variant_code",
    "location_code",
    "event_date",
    "signed_quantity",
    "source_kind",
]

# Source-kind tags — match the BCEventSource per-source AppendEvent calls so
# drift between the Query path and the existing scalar-Max-Sellable path is
# detectable (integration test asserts the two agree on the same fixture).
SOURCE_SALES_ORDER = "sales_order"
SOURCE_SALES_RETURN_ORDER = "sales_return_order"
SOURCE_PURCHASE_ORDER = "purchase_order"
SOURCE_PURCHASE_RETURN_ORDER = "purchase_return_order"
SOURCE_TRANSFER_IN = "transfer_in"
SOURCE_TRANSFER_OUT = "transfer_out"
SOURCE_SERVICE_LINE = "service_line"
SOURCE_PROD_ORDER_LINE = "prod_order_line"
SOURCE_PROD_ORDER_COMPONENT = "prod_order_component"
SOURCE_ASSEMBLY_HEADER = "assembly_header"
SOURCE_ASSEMBLY_LINE = "assembly_line"
SOURCE_JOB_PLANNING_LINE = "job_planning_line"


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


def fetch_open_sd_events(config: BcApiConfig) -> list[JsonRow]:
    """Concatenate every open Supply & Demand source into the unified event shape.

    One round-trip per AL Query endpoint; per-source projection lives in the
    `project_*` helpers below. Equivalent to BCEventSource.CollectEvents
    looped across every Item — the integration test asserts that equivalence
    on a controlled fixture (ADR 0001 inclusion list, ADR 0007 simulator seed).
    """
    sources = (
        ("openSDSales", OPEN_SD_SALES_CAMEL_TO_SNAKE, project_sales),
        ("openSDPurchase", OPEN_SD_PURCHASE_CAMEL_TO_SNAKE, project_purchase),
        ("openSDTransferIn", OPEN_SD_TRANSFER_IN_CAMEL_TO_SNAKE, project_transfer_in),
        ("openSDTransferOut", OPEN_SD_TRANSFER_OUT_CAMEL_TO_SNAKE, project_transfer_out),
        ("openSDService", OPEN_SD_SERVICE_CAMEL_TO_SNAKE, project_service),
        ("openSDProdOrderLine", OPEN_SD_PROD_ORDER_LINE_CAMEL_TO_SNAKE, project_prod_order_line),
        ("openSDProdOrderComp", OPEN_SD_PROD_ORDER_LINE_CAMEL_TO_SNAKE, project_prod_order_comp),
        ("openSDAssemblyHeader", OPEN_SD_ASSEMBLY_HEADER_CAMEL_TO_SNAKE, project_assembly_header),
        ("openSDAssemblyLine", OPEN_SD_ASSEMBLY_HEADER_CAMEL_TO_SNAKE, project_assembly_line),
        ("openSDJobPlanning", OPEN_SD_JOB_PLANNING_CAMEL_TO_SNAKE, project_job_planning),
    )
    rows: list[JsonRow] = []
    for entity_set, mapping, projector in sources:
        rows.extend(projector(_fetch_paginated(config, entity_set, mapping)))
    return rows


def _normalize_enum(value: object) -> str:
    """Collapse BC enum serialization variants to a single comparable key.

    BC OData has serialized enum captions both with spaces ("Return Order",
    "Both Budget and Billable") and without ("ReturnOrder",
    "BothBudgetAndBillable") across releases — collapse both forms so a
    single equality check works.
    """
    return str(value).replace(" ", "").lower() if value is not None else ""


def _event_row(row: JsonRow, source_kind: str, sign: int) -> JsonRow:
    return {
        "item_no": row["item_no"],
        "variant_code": row["variant_code"],
        "location_code": row["location_code"],
        "event_date": row["event_date"],
        "signed_quantity": sign * float(row["qty"]),
        "source_kind": source_kind,
    }


def project_sales(rows: list[JsonRow]) -> list[JsonRow]:
    """Project Open SD Sales rows: Order → demand (-), Return Order → supply (+)."""
    out: list[JsonRow] = []
    for r in rows:
        is_return = _normalize_enum(r.get("document_type")) == "returnorder"
        kind = SOURCE_SALES_RETURN_ORDER if is_return else SOURCE_SALES_ORDER
        sign = 1 if is_return else -1
        out.append(_event_row(r, kind, sign))
    return out


def project_purchase(rows: list[JsonRow]) -> list[JsonRow]:
    """Project Open SD Purchase rows: Order → supply (+), Return Order → demand (-)."""
    out: list[JsonRow] = []
    for r in rows:
        is_return = _normalize_enum(r.get("document_type")) == "returnorder"
        kind = SOURCE_PURCHASE_RETURN_ORDER if is_return else SOURCE_PURCHASE_ORDER
        sign = -1 if is_return else 1
        out.append(_event_row(r, kind, sign))
    return out


def project_transfer_in(rows: list[JsonRow]) -> list[JsonRow]:
    """Project Open SD Transfer In rows: receipt-side supply at destination.

    BC's IsReceipt=true filter doesn't add Outstanding<>0 (only the
    IsReceipt=false path does), so we drop zero-qty rows here to keep
    fully-received in-transits out of the event stream.
    """
    return [_event_row(r, SOURCE_TRANSFER_IN, 1) for r in rows if float(r["qty"]) != 0]


def project_transfer_out(rows: list[JsonRow]) -> list[JsonRow]:
    """Project Open SD Transfer Out rows: shipment-side demand at source."""
    return [_event_row(r, SOURCE_TRANSFER_OUT, -1) for r in rows]


def project_service(rows: list[JsonRow]) -> list[JsonRow]:
    """Project Open SD Service rows: always demand (-)."""
    return [_event_row(r, SOURCE_SERVICE_LINE, -1) for r in rows]


def project_prod_order_line(rows: list[JsonRow]) -> list[JsonRow]:
    """Project Open SD Prod Order Line rows: output side is supply (+)."""
    return [_event_row(r, SOURCE_PROD_ORDER_LINE, 1) for r in rows]


def project_prod_order_comp(rows: list[JsonRow]) -> list[JsonRow]:
    """Project Open SD Prod Order Component rows: consumption side is demand (-)."""
    return [_event_row(r, SOURCE_PROD_ORDER_COMPONENT, -1) for r in rows]


def project_assembly_header(rows: list[JsonRow]) -> list[JsonRow]:
    """Project Open SD Assembly Header rows: assembled output is supply (+)."""
    return [_event_row(r, SOURCE_ASSEMBLY_HEADER, 1) for r in rows]


def project_assembly_line(rows: list[JsonRow]) -> list[JsonRow]:
    """Project Open SD Assembly Line rows: component consumption is demand (-)."""
    return [_event_row(r, SOURCE_ASSEMBLY_LINE, -1) for r in rows]


def project_job_planning(rows: list[JsonRow]) -> list[JsonRow]:
    """Project Open SD Job Planning rows: demand (-), with double-emit per ADR 0001 dev #3.

    BC's Job availability views count Line Type = "Both Budget and Billable"
    twice (once as Budget, once as Billable). We replicate the double-count
    Python-side rather than re-encoding it in AL — a single SELECT can't
    emit a row twice.
    """
    out: list[JsonRow] = []
    for r in rows:
        event = _event_row(r, SOURCE_JOB_PLANNING_LINE, -1)
        out.append(event)
        if _normalize_enum(r.get("line_type")) == "bothbudgetandbillable":
            out.append(event)
    return out


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


@lru_cache(maxsize=8)
def _resolve_company_id(config: BcApiConfig) -> str:
    # Cached so a multi-endpoint extract (e.g. fetch_open_sd_events hits 10
    # Queries) pays the /companies round-trip once. BcApiConfig is frozen,
    # so equality keys correctly on (base_url, auth, company_name).
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
