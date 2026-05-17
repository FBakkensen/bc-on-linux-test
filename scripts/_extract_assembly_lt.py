"""Assembly LT OData → CSV extract.

Driven by scripts/extract-assembly-lt.sh. One row per finished Posted
Assembly Header; the Python parser derives `lead_time_days = posting_date
− starting_date` per ADR 0006. Orchestration lives in `_extract_common`.
"""

import sys

from _extract_common import ROOT, run_extract
from extracts.bc_api import ASSEMBLY_LT_COLUMNS, fetch_assembly_lt

if __name__ == "__main__":
    sys.exit(
        run_extract(
            entity_label="assemblyLT",
            columns=ASSEMBLY_LT_COLUMNS,
            fetcher=fetch_assembly_lt,
            default_output=ROOT / ".build" / "extracts" / "assembly-lt.csv",
        ),
    )
