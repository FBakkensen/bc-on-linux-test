from pathlib import Path
import shutil

import pytest


FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture
def synthetic_extract(tmp_path: Path) -> Path:
    """Copy the synthetic 5-row extract into a tmp dir so run() can write
    its output next to the input without polluting the repo.
    """
    src = FIXTURES / "synthetic_extract.csv"
    dst = tmp_path / "synthetic_extract.csv"
    shutil.copy(src, dst)
    return dst
