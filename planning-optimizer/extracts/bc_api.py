"""API page / API Query reads + recommendation POSTs.

Per ADR 0009, this module is the only BC-talking surface for the math
package. Bulk historical reads are exposed by AL Query objects with
`QueryType = API`; this module follows `@odata.nextLink`, maps the
camelCase response keys to the snake_case shape downstream code (the file
seam and the recommender) consumes, and returns plain dicts ready to write
as CSV.

Slice #12 lands the first fetcher — `fetch_item_ledger_summaries`. Future
slices grow one fetcher per AL API Query (purchase receipt LT, prod /
assembly / transfer LT, open S&D, …) and the recommendation POST surface.
"""

import base64
import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass


API_PATH = "/api/fbakkensen/planningOptimizer/v1.0"

ILE_SUMMARY_CAMEL_TO_SNAKE = {
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "postingDate": "posting_date",
    "quantity": "quantity",
}
ILE_SUMMARY_COLUMNS = list(ILE_SUMMARY_CAMEL_TO_SNAKE.values())


@dataclass(frozen=True)
class BcApiConfig:
    base_url: str = "http://localhost:7052/BC"
    auth: str = "BCRUNNER:Admin123!"
    company_name: str = "CRONUS International Ltd."

    @classmethod
    def from_env(cls) -> "BcApiConfig":
        return cls(
            base_url=os.environ.get("BC_API_BASE_URL", cls.base_url),
            auth=os.environ.get("BC_AUTH", cls.auth),
            company_name=os.environ.get("BC_COMPANY_NAME", cls.company_name),
        )


def fetch_item_ledger_summaries(config: BcApiConfig) -> list[dict]:
    """Paginate the itemLedgerSummary API Query for the configured company.

    Returns rows in the snake_case shape consumers expect — the BC-side
    camelCase is hidden inside this seam.
    """
    company_id = _resolve_company_id(config)
    rows: list[dict] = []
    url = f"{config.base_url}{API_PATH}/companies({company_id})/itemLedgerSummaries"
    while url:
        data = _get_json(config, url)
        rows.extend(_to_snake_case(r, ILE_SUMMARY_CAMEL_TO_SNAKE) for r in data["value"])
        url = data.get("@odata.nextLink", "")
    return rows


def _resolve_company_id(config: BcApiConfig) -> str:
    data = _get_json(config, f"{config.base_url}{API_PATH}/companies")
    for company in data["value"]:
        if company["name"] == config.company_name:
            return company["id"]
    raise RuntimeError(f"Company not found: {config.company_name}")


def _to_snake_case(camel_row: dict, mapping: dict) -> dict:
    return {snake: camel_row[camel] for camel, snake in mapping.items()}


def _get_json(config: BcApiConfig, url: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": _auth_header(config.auth)})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} on {url}\n{body}") from exc


def _auth_header(auth: str) -> str:
    return "Basic " + base64.b64encode(auth.encode("utf-8")).decode("ascii")
