"""Transfer LT OData → CSV extract.

Driven by scripts/extract-transfer-lt.sh. The Python parser pairs ILE
Transfer source (negative qty) and destination (positive qty) rows by
(document_no, item_no, variant_code) per ADR 0006; unmatched in-flight
transfers drop out at parse time. Orchestration lives in `_extract_common`.
"""

import sys

from _extract_common import ROOT, run_extract
from extracts.bc_api import TRANSFER_LT_COLUMNS, fetch_transfer_lt

if __name__ == "__main__":
    sys.exit(
        run_extract(
            entity_label="transferLT",
            columns=TRANSFER_LT_COLUMNS,
            fetcher=fetch_transfer_lt,
            default_output=ROOT / ".build" / "extracts" / "transfer-lt.csv",
        ),
    )
