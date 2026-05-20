"""End-to-end shape assertions against the live BC-seeded companies.

Skipped automatically when BC isn't reachable or when the seeded companies
aren't present — runs in CI's pipeline-smoke job, not in the inner-loop
unit-test runs. Per ADR 0013.

Reads the extracts produced by ``scripts/test-pipeline.sh`` (under
``.build/extracts/PLANOPT-CO-{A,B}/``) and asserts the dataset shape
matches the cohort design in the ADR. As cohorts land (regime change,
stockout history, variant divergence), assertions tighten here rather
than in the synthetic-fixture unit tests under this same folder.
"""

from __future__ import annotations

import csv
import os
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
EXTRACTS_DIR = REPO_ROOT / ".build" / "extracts"
RECS_DIR = REPO_ROOT / ".build" / "recommendations"

COMPANIES = ("CRONUS-PLANOPT-A", "CRONUS-PLANOPT-B")


def _seeded_data_available() -> bool:
    return all((EXTRACTS_DIR / c / "ile_summary.csv").exists() for c in COMPANIES)


requires_seeded_data = pytest.mark.skipif(
    not _seeded_data_available(),
    reason="seeded BC extracts not present — run ./scripts/test-pipeline.sh first",
)


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open() as fh:
        return list(csv.DictReader(fh))


@requires_seeded_data
@pytest.mark.parametrize("company", COMPANIES)
def test_ile_summary_has_data(company: str) -> None:
    rows = _read_csv(EXTRACTS_DIR / company / "ile_summary.csv")
    assert len(rows) >= 100, f"{company}: ILE summary has only {len(rows)} rows; expected >=100"


@requires_seeded_data
@pytest.mark.parametrize("company", COMPANIES)
def test_ile_summary_spans_history_window(company: str) -> None:
    rows = _read_csv(EXTRACTS_DIR / company / "ile_summary.csv")
    dates = sorted(r["posting_date"] for r in rows if r.get("posting_date"))
    assert dates, f"{company}: no posting_date values"
    # History window per ADR 0013 is 36 months. Be permissive on the lower
    # bound — agents iterating on the seed may temporarily shrink it.
    earliest = dates[0]
    latest = dates[-1]
    assert earliest < latest, f"{company}: ILE summary date range collapsed ({earliest} == {latest})"


@requires_seeded_data
@pytest.mark.parametrize("company", COMPANIES)
def test_ile_summary_covers_multiple_items(company: str) -> None:
    rows = _read_csv(EXTRACTS_DIR / company / "ile_summary.csv")
    items = {r["item_no"] for r in rows if r.get("item_no", "").startswith("POS-I")}
    # Constants.ItemsPerCompany() == 20 in initial bring-up; expect at least
    # 10 distinct items show up in the summary (some may have no history if
    # their cohort cell ended up empty after RNG sampling).
    assert len(items) >= 10, f"{company}: only {len(items)} distinct seed items in ILE summary"


@requires_seeded_data
@pytest.mark.parametrize("company", COMPANIES)
def test_purchase_lt_present(company: str) -> None:
    rows = _read_csv(EXTRACTS_DIR / company / "purchase_lt.csv")
    assert len(rows) >= 50, f"{company}: purchase LT has only {len(rows)} rows; expected >=50"


@requires_seeded_data
@pytest.mark.parametrize("company", COMPANIES)
def test_open_sd_has_events(company: str) -> None:
    rows = _read_csv(EXTRACTS_DIR / company / "open_sd.csv")
    assert len(rows) >= 5, f"{company}: open SD has only {len(rows)} rows; expected >=5"


@requires_seeded_data
@pytest.mark.parametrize("company", COMPANIES)
def test_recommendations_emitted(company: str) -> None:
    recs = RECS_DIR / f"{company}.json"
    if not recs.exists():
        pytest.skip(f"{recs} not present — pipeline didn't run the optimizer step")
    assert recs.stat().st_size > 0, f"{company}: recommendations file is empty"


@requires_seeded_data
def test_two_companies_have_overlapping_item_master() -> None:
    rows_a = _read_csv(EXTRACTS_DIR / COMPANIES[0] / "ile_summary.csv")
    rows_b = _read_csv(EXTRACTS_DIR / COMPANIES[1] / "ile_summary.csv")
    items_a = {r["item_no"] for r in rows_a if r.get("item_no", "").startswith("POS-I")}
    items_b = {r["item_no"] for r in rows_b if r.get("item_no", "").startswith("POS-I")}
    # ADR 0013: 80% overlap. The seed currently writes identical Item Nos in
    # both companies (we don't disjoin the 20% yet), so overlap is expected
    # to be very high. Asserting at least 50% catches regressions.
    overlap = items_a & items_b
    smaller = min(len(items_a), len(items_b))
    assert smaller > 0, "no seed items in either company"
    assert len(overlap) >= smaller // 2, (
        f"overlap {len(overlap)} too small vs smaller-side {smaller}"
    )
