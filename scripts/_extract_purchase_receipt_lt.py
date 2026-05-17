"""Purchase Receipt LT OData → CSV extract.

Driven by scripts/extract-purchase-receipt-lt.sh. Drop-shipments and special
orders are excluded server-side by the AL Query (per ADR 0006). The
`expected_receipt_date` cell may be blank when the source PO has been
deleted or never carried an expected date at creation time — that's a real
signal, not bad data. Orchestration lives in `_extract_common`.
"""

import sys

from _extract_common import ROOT, run_extract
from extracts.bc_api import PURCHASE_RECEIPT_LT_COLUMNS, fetch_purchase_receipt_lt

if __name__ == "__main__":
    sys.exit(
        run_extract(
            entity_label="purchaseReceiptLT",
            columns=PURCHASE_RECEIPT_LT_COLUMNS,
            fetcher=fetch_purchase_receipt_lt,
            default_output=ROOT / ".build" / "extracts" / "purchase-receipt-lt.csv",
        ),
    )
