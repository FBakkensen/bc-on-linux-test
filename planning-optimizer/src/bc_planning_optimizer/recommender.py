"""Per-SKU recommendation math.

Walking-skeleton implementation: ROP = mean(daily_demand) × mean(lead_time_days),
safety_stock = ROP / 2, no policy change. Real ROP / ROQ / policy logic
(bootstrap LTD α-quantile, simulator-verified) lands in a later slice.
"""

from typing import Any

import pandas as pd

SKU_COLUMNS = ["item_no", "variant_code", "location_code"]


def recommend(observations: pd.DataFrame) -> list[dict[str, Any]]:
    """Return one recommendation dict per (item_no, variant_code, location_code) row."""
    grouped = observations.groupby(SKU_COLUMNS, sort=False)
    recommendations: list[dict[str, Any]] = []
    for (item_no, variant_code, location_code), group in grouped:
        reorder_point = float(group["daily_demand"].mean() * group["lead_time_days"].mean())
        safety_stock = reorder_point / 2
        recommendations.append(
            {
                "item_no": item_no,
                "variant_code": variant_code,
                "location_code": location_code,
                "reorder_point": reorder_point,
                "safety_stock": safety_stock,
            }
        )
    return recommendations
