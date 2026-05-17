"""Production LT OData → CSV extract.

Driven by scripts/extract-production-lt.sh. Cancelled / scrapped prod
orders are excluded server-side (Status = Finished filter); the Python
parser derives max(Output) − min(Consumption) per ADR 0006 and falls back
to header dates when no consumption ILE exists. Orchestration lives in
`_extract_common`.
"""

import sys

from _extract_common import ROOT, run_extract
from extracts.bc_api import PRODUCTION_LT_COLUMNS, fetch_production_lt

if __name__ == "__main__":
    sys.exit(
        run_extract(
            entity_label="productionLT",
            columns=PRODUCTION_LT_COLUMNS,
            fetcher=fetch_production_lt,
            default_output=ROOT / ".build" / "extracts" / "production-lt.csv",
        ),
    )
