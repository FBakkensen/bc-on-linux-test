from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

import pytest

FIXTURES = Path(__file__).parent / "fixtures"

ILE_HEADER = "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
PURCHASE_LT_HEADER = (
    "item_no,variant_code,location_code,vendor_no,po_order_date,"
    "receipt_posting_date,expected_receipt_date,quantity,document_no\n"
)


@pytest.fixture
def synthetic_ile_summary(tmp_path: Path) -> Path:
    """Copy the synthetic ILE-summary extract into a tmp dir so run() can write
    its output next to the input without polluting the repo.
    """
    src = FIXTURES / "synthetic_ile_summary.csv"
    dst = tmp_path / "synthetic_ile_summary.csv"
    shutil.copy(src, dst)
    return dst


def write_ile(tmp_path: Path, *rows: str) -> Path:
    extract = tmp_path / "ile.csv"
    extract.write_text(ILE_HEADER + "".join(rows))
    return extract


def write_purchase_lt(tmp_path: Path, *rows: str) -> None:
    (tmp_path / "purchase_lt.csv").write_text(PURCHASE_LT_HEADER + "".join(rows))


def load_recommendations(output_path: Path) -> dict[str, Any]:
    payload: dict[str, Any] = json.loads(output_path.read_text())
    return payload
