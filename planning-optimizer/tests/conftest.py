import shutil
from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture
def synthetic_ile_summary(tmp_path: Path) -> Path:
    """Copy the synthetic ILE-summary extract into a tmp dir so run() can write
    its output next to the input without polluting the repo.
    """
    src = FIXTURES / "synthetic_ile_summary.csv"
    dst = tmp_path / "synthetic_ile_summary.csv"
    shutil.copy(src, dst)
    return dst
