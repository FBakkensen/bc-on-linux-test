"""Item Ledger Summary OData → CSV extract.

Driven by scripts/extract-ile-summary.sh. ADR 0009: extracts/bc_api is the
only BC-talking layer; this wrapper hands its (entity, columns, fetcher)
triple to the shared orchestrator in `_extract_common`.
"""

import sys

from _extract_common import ROOT, run_extract
from extracts.bc_api import ILE_SUMMARY_COLUMNS, fetch_item_ledger_summaries

if __name__ == "__main__":
    sys.exit(
        run_extract(
            entity_label="itemLedgerSummaries",
            columns=ILE_SUMMARY_COLUMNS,
            fetcher=fetch_item_ledger_summaries,
            default_output=ROOT / ".build" / "extracts" / "ile-summary.csv",
        ),
    )
