#!/usr/bin/env bash
# Strict Python lint / type / complexity / coverage gate.
# Mirrors scripts/compile.sh for AL: same fail-fast posture, agent-driven inner loop.
#
# Bootstraps a pinned tool venv (uv) on first run, then runs:
#   - ruff check         (select=ALL with curated ignores in planning-optimizer/pyproject.toml)
#   - ruff format --check
#   - mypy --strict
#   - radon mi           (Maintainability Index must be grade A: >= 20 per module)
#   - xenon              (Cyclomatic Complexity: abs <= B, modules avg = A, project avg = A)
#   - pytest --cov       (planning-optimizer/, fail under 90 %)
#
# Scope: planning-optimizer/ (src + extracts + tests + notebooks) and the
# repo-root extract scripts. bc-linux/scripts/*.py is upstream-vendored and
# excluded by path.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VENV="$ROOT/.venv-python-check"
PROJECT="$ROOT/planning-optimizer"
CONFIG="$PROJECT/pyproject.toml"

EXTRACT_SCRIPTS=(
    scripts/_extract_ile_summary.py
    scripts/_extract_purchase_receipt_lt.py
)

# Ruff scans everything including notebooks.
RUFF_TARGETS=(
    "$PROJECT"
    "${EXTRACT_SCRIPTS[@]}"
)

# Mypy: every .py we own. Notebooks excluded (no native mypy support; Ruff covers them).
MYPY_TARGETS=(
    "$PROJECT/src"
    "$PROJECT/extracts"
    "$PROJECT/tests"
    "${EXTRACT_SCRIPTS[@]}"
)

# Complexity / MI: production code only. Tests are linear by design; their
# CC / MI numbers would be noise.
COMPLEXITY_TARGETS=(
    "$PROJECT/src"
    "$PROJECT/extracts"
    "${EXTRACT_SCRIPTS[@]}"
)

bootstrap_venv() {
    if [[ -x "$VENV/bin/ruff" && -x "$VENV/bin/mypy" && -x "$VENV/bin/xenon" && -x "$VENV/bin/pytest" ]]; then
        return 0
    fi
    if ! command -v uv >/dev/null 2>&1; then
        echo "ERROR: uv not found on PATH. Install Astral uv (https://docs.astral.sh/uv) and retry." >&2
        exit 1
    fi
    echo "==> Bootstrapping Python tool venv at $VENV"
    uv venv --python 3.11 "$VENV" >/dev/null
    uv pip install --quiet --python "$VENV/bin/python" -e "$PROJECT[dev]"
}

bootstrap_venv

RUFF="$VENV/bin/ruff"
MYPY="$VENV/bin/mypy"
RADON="$VENV/bin/radon"
XENON="$VENV/bin/xenon"
PYTEST="$VENV/bin/pytest"

echo "==> Ruff lint"
"$RUFF" check --config "$CONFIG" "${RUFF_TARGETS[@]}"

echo "==> Ruff format check"
"$RUFF" format --check --config "$CONFIG" "${RUFF_TARGETS[@]}"

echo "==> mypy --strict"
"$MYPY" --config-file "$CONFIG" "${MYPY_TARGETS[@]}"

echo "==> Radon Maintainability Index (min grade A)"
# radon mi exits 0 even on bad scores; gate ourselves.
# Output format: "<path> - <grade> (<score>)". Fail if any module is below A.
mi_output="$("$RADON" mi -s "${COMPLEXITY_TARGETS[@]}")"
printf '%s\n' "$mi_output"
non_a="$(printf '%s\n' "$mi_output" | awk -F' - ' 'NF >= 2 && $2 !~ /^A / { print }')"
if [[ -n "$non_a" ]]; then
    echo "ERROR: modules below MI grade A:" >&2
    printf '%s\n' "$non_a" >&2
    exit 1
fi

echo "==> Xenon (CC: abs<=B, modules avg=A, project avg=A)"
"$XENON" --max-absolute B --max-modules A --max-average A "${COMPLEXITY_TARGETS[@]}"

echo "==> pytest --cov (planning-optimizer/, fail under 90 %)"
( cd "$PROJECT" && "$PYTEST" )

echo "==> All Python checks passed."
