"""End-to-end recommendation pipeline.

`run(extract_path)` reads an Item Ledger Entry summary CSV plus four optional
sibling LT extracts and writes a `recommendations.json` next to the input.
Missing LT files are treated as zero historical samples — the affected SKUs
flag `Insufficient data` and emit a null recommendation.
"""

from __future__ import annotations

import json
import math
from collections.abc import Callable
from pathlib import Path
from typing import Any, cast

import pandas as pd
from extracts.bc_files import (
    read_assembly_lt,
    read_ile_summary,
    read_production_lt,
    read_purchase_receipt_lt,
    read_transfer_lt,
)

from .classifier import ClassifierConfig, classify
from .lead_time import extract_lt_series
from .recommender import SKU_COLUMNS, BootstrapConfig, recommend_with_bootstrap

DEFAULT_N_DRAWS = 10_000


def run(
    extract_path: Path,
    *,
    config_path: Path | None = None,
    asof_date: pd.Timestamp | str | None = None,
    seed: int = 0,
    n_draws: int = DEFAULT_N_DRAWS,
) -> Path:
    """Read the extracts, write recommendations.json beside the ILE CSV, return that path.

    `config_path` points at a JSON setup file (`abc_cut_points`,
    `revenue_window_months`, `history_window_months`, `strategic_skus`,
    `service_level_by_abc`); absent keys take ADR defaults. `asof_date`
    overrides the windowing anchor. `seed` is the ModelRunId salt mixed into
    every per-SKU bootstrap seed for reproducibility. `n_draws` sets the
    bootstrap sample size — callers can drop it for fast tests.
    """
    extract_path = Path(extract_path)
    ile_summary = read_ile_summary(extract_path)
    config = _load_config(config_path)
    resolved_asof = _resolve_asof(asof_date, ile_summary)

    classifier_df = classify(ile_summary, asof_date=resolved_asof, config=config)
    lt_result = extract_lt_series(
        **_load_lt_extracts(extract_path.parent),
        ile_summary=ile_summary,
    )

    recommendations = recommend_with_bootstrap(
        lt_pairs=lt_result.pairs,
        lt_summary=lt_result.summary,
        classifier=classifier_df,
        config=BootstrapConfig(
            service_level_by_abc=config.service_level_by_abc,
            n_draws=n_draws,
            model_run_id_seed=seed,
        ),
    )
    enriched = _enrich_with_classifier(recommendations, classifier_df)

    output_path = extract_path.parent / "recommendations.json"
    output_path.write_text(json.dumps({"recommendations": enriched}))
    return output_path


def _load_config(config_path: Path | None) -> ClassifierConfig:
    if config_path is None:
        return ClassifierConfig()
    return ClassifierConfig.from_json(json.loads(Path(config_path).read_text()))


def _resolve_asof(
    asof_date: pd.Timestamp | str | None,
    ile_summary: pd.DataFrame,
) -> pd.Timestamp:
    if asof_date is not None:
        return pd.Timestamp(asof_date)
    if ile_summary.empty:
        return pd.Timestamp.utcnow().normalize()
    return pd.Timestamp(ile_summary["posting_date"].max())


_PURCHASE_LT_DTYPES: dict[str, str] = {
    "item_no": "string",
    "variant_code": "string",
    "location_code": "string",
    "vendor_no": "string",
    "document_no": "string",
    "po_order_date": "datetime64[ns]",
    "receipt_posting_date": "datetime64[ns]",
    "expected_receipt_date": "datetime64[ns]",
    "quantity": "float64",
    "order_to_receipt_days": "int64",
    "plan_to_receipt_days": "int64",
    "trigger_date": "datetime64[ns]",
}
_PRODUCTION_LT_DTYPES: dict[str, str] = {
    "prod_order_no": "string",
    "item_no": "string",
    "variant_code": "string",
    "location_code": "string",
    "lead_time_days": "int64",
    "source": "string",
    "replenishment_system": "string",
    "shared_sample_key": "string",
    "plan_to_actual_days": "int64",
    "trigger_date": "datetime64[ns]",
}
_TRANSFER_LT_DTYPES: dict[str, str] = {
    "document_no": "string",
    "item_no": "string",
    "variant_code": "string",
    "location_code": "string",
    "lead_time_days": "int64",
    "source": "string",
    "replenishment_system": "string",
    "shared_sample_key": "string",
    "plan_to_actual_days": "object",
    "trigger_date": "datetime64[ns]",
}
_ASSEMBLY_LT_DTYPES: dict[str, str] = {
    "assembly_doc_no": "string",
    "item_no": "string",
    "variant_code": "string",
    "location_code": "string",
    "lead_time_days": "int64",
    "replenishment_system": "string",
    "source": "string",
    "shared_sample_key": "string",
    "plan_to_actual_days": "object",
    "trigger_date": "datetime64[ns]",
}

_LtReader = Callable[[Path], pd.DataFrame]
# kwarg name on `extract_lt_series` → (sibling filename, reader, empty-frame dtypes).
_LT_EXTRACTS: dict[str, tuple[str, _LtReader, dict[str, str]]] = {
    "purchase_lt": ("purchase_lt.csv", read_purchase_receipt_lt, _PURCHASE_LT_DTYPES),
    "production_lt": ("production_lt.csv", read_production_lt, _PRODUCTION_LT_DTYPES),
    "transfer_lt": ("transfer_lt.csv", read_transfer_lt, _TRANSFER_LT_DTYPES),
    "assembly_lt": ("assembly_lt.csv", read_assembly_lt, _ASSEMBLY_LT_DTYPES),
}


def _load_lt_extracts(extract_dir: Path) -> dict[str, pd.DataFrame]:
    """Return the four LT extracts keyed by `extract_lt_series` kwarg name."""
    extracts: dict[str, pd.DataFrame] = {}
    for kwarg, (filename, reader, dtypes) in _LT_EXTRACTS.items():
        candidate = extract_dir / filename
        extracts[kwarg] = reader(candidate) if candidate.exists() else _empty_frame(dtypes)
    return extracts


def _empty_frame(dtypes: dict[str, str]) -> pd.DataFrame:
    return pd.DataFrame({col: pd.Series(dtype=dt) for col, dt in dtypes.items()})


def _enrich_with_classifier(
    recommendations: list[dict[str, Any]],
    classifier_df: pd.DataFrame,
) -> list[dict[str, Any]]:
    """Merge classifier columns onto each recommendation dict by SKU triplet."""
    classifier_rows = cast(
        "list[dict[str, Any]]",
        classifier_df.to_dict(orient="records"),
    )
    by_sku: dict[tuple[str, str, str], dict[str, Any]] = {
        (
            cast("str", row["item_no"]),
            cast("str", row["variant_code"]),
            cast("str", row["location_code"]),
        ): row
        for row in classifier_rows
    }
    enriched: list[dict[str, Any]] = []
    for rec in recommendations:
        key = (rec["item_no"], rec["variant_code"], rec["location_code"])
        row = by_sku.get(key)
        if row is None:
            enriched.append(rec)
            continue
        enriched.append(
            {
                **rec,
                "abc_class": str(row["abc_class"]),
                "demand_pattern_class": str(row["demand_pattern_class"]),
                "adi": _nan_to_none(float(row["adi"])),
                "cv_squared": _nan_to_none(float(row["cv_squared"])),
                "revenue_window_total": float(row["revenue_window_total"]),
                "is_strategic": bool(row["is_strategic"]),
            },
        )
    return enriched


def _nan_to_none(value: float) -> float | None:
    # JSON has no NaN; emit null instead so consumers don't choke.
    return None if math.isnan(value) else value


__all__ = ["SKU_COLUMNS", "run"]
