"""End-to-end walking-skeleton entry point.

`run(extract_path)` reads an aggregated extract CSV, computes naive
recommendations per SKU, and writes a `recommendations.json` file next to the
input. Real pipeline (classifier → forecaster → simulator → recommender) lands
in later slices.
"""

import json
from pathlib import Path

from extracts.bc_files import read_extract

from .recommender import recommend


def run(extract_path: Path) -> Path:
    extract_path = Path(extract_path)
    observations = read_extract(extract_path)
    recommendations = recommend(observations)

    output_path = extract_path.parent / "recommendations.json"
    output_path.write_text(json.dumps({"recommendations": recommendations}))
    return output_path
