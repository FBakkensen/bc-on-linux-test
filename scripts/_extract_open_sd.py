"""Open Supply & Demand OData → CSV extract.

Driven by scripts/extract-open-sd.sh. Pulls rows from the 10 Open SD AL
Query endpoints (sales, purchase, transfer in/out, service, prod order
line/component, assembly header/line, job planning), projects each into
the unified `(item_no, variant_code, location_code, event_date,
signed_quantity, source_kind)` event shape (ADR 0007 simulator seed), and
writes them as one CSV for bc_files.read_open_sd_events to consume.
Orchestration lives in `_extract_common`.
"""

import sys

from _extract_common import ROOT, run_extract
from extracts.bc_api import OPEN_SD_EVENT_COLUMNS, fetch_open_sd_events

if __name__ == "__main__":
    sys.exit(
        run_extract(
            entity_label="openSD* (10 endpoints)",
            columns=OPEN_SD_EVENT_COLUMNS,
            fetcher=fetch_open_sd_events,
            default_output=ROOT / ".build" / "extracts" / "open-sd-events.csv",
        ),
    )
