"""Tests for `bc_files.read_assembly_lt`.

ADR 0006: assembly LT = `Posted Assembly Header.Posting Date − Starting Date`.
One row per finished posted assembly. No fallback path — Posted Assembly
Header always has both dates.

CSV shape (one row per posted assembly):

    assembly_doc_no, item_no, variant_code, location_code,
    starting_date, posting_date

Returns the unified shape used by all replenishment-system readers.
"""

from pathlib import Path

from extracts.bc_files import read_assembly_lt

HEADER = "assembly_doc_no,item_no,variant_code,location_code,starting_date,posting_date\n"


def _write(tmp_path: Path, *rows: str) -> Path:
    extract = tmp_path / "assembly-lt.csv"
    extract.write_text(HEADER + "".join(rows))
    return extract


def test_lt_is_posting_minus_starting(tmp_path):
    extract = _write(
        tmp_path,
        "ASM-001,KIT-A,,BLUE,2026-04-01,2026-04-05\n",
    )

    df = read_assembly_lt(extract)

    assert len(df) == 1
    row = df.iloc[0]
    assert row["item_no"] == "KIT-A"
    assert row["variant_code"] == ""
    assert row["location_code"] == "BLUE"
    assert row["lead_time_days"] == 4
    assert row["replenishment_system"] == "assembly"
    assert row["source"] == "assembly_header"
    assert row["shared_sample_key"] == "ASM-001"


def test_multi_row_keeps_lt_independent(tmp_path):
    extract = _write(
        tmp_path,
        "ASM-001,KIT-A,,BLUE,2026-04-01,2026-04-05\n",
        "ASM-002,KIT-B,RED,GREEN,2026-05-01,2026-05-10\n",
    )

    df = read_assembly_lt(extract)

    by_doc = {row["shared_sample_key"]: row for _, row in df.iterrows()}
    assert by_doc["ASM-001"]["lead_time_days"] == 4
    assert by_doc["ASM-002"]["lead_time_days"] == 9


def test_empty_extract_returns_empty_frame_with_schema(tmp_path):
    extract = _write(tmp_path)  # header only

    df = read_assembly_lt(extract)

    assert len(df) == 0
    for col in (
        "item_no",
        "variant_code",
        "location_code",
        "lead_time_days",
        "replenishment_system",
        "source",
        "shared_sample_key",
        "plan_to_actual_days",
    ):
        assert col in df.columns
