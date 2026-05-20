#!/usr/bin/env bash
set -euo pipefail

# Seed PLANOPT-CO-A and PLANOPT-CO-B with multi-year planning history for the
# pipeline smoke. Per ADR 0013.
#
# Flow:
#   1. Verify BC reachable
#   2. (--nuke only) docker compose restart bc
#   3. Compile seed/ via scripts/compile.sh
#   4. Publish seed extension via bc-linux/scripts/publish-app.sh
#   5. (--reset/--nuke only) POST TeardownCompanies in the default company,
#      then re-publish the extension after the companies are gone
#   6. POST CreateCompanies in the default company → both PLANOPT companies exist
#   7. POST SeedSingleCompany in PLANOPT-CO-A and PLANOPT-CO-B
#   8. Write .build/seed-marker.json (source hash + SEED_TODAY)
#   9. (--verify only) bc_api.py extract + shape report
#
# Usage:
#   ./scripts/seed-company.sh           # idempotent: skip if hash matches + < 14d stale + companies present
#   ./scripts/seed-company.sh --reset   # teardown + republish + re-seed
#   ./scripts/seed-company.sh --nuke    # docker compose restart bc + --reset
#   ./scripts/seed-company.sh --verify  # skip seeding; emit shape report from bc_api.py
#
# Env overrides:
#   BC_BASE_URL    default http://localhost:7048/BC
#   BC_DEV_URL     default http://localhost:7049/BC/dev
#   BC_AUTH        default BCRUNNER:Admin123!
#   SEED_TODAY     default $(date +%Y-%m-%d)
#   DEFAULT_COMPANY default first company returned by /companies (usually Cronus)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SEED_DIR="$ROOT_DIR/seed"
BUILD_DIR="$ROOT_DIR/.build"
MARKER_FILE="$BUILD_DIR/seed-marker.json"
STALENESS_DAYS=14
BC_LINUX_DIR="$ROOT_DIR/bc-linux"
OVERRIDES_DIR="$ROOT_DIR/scripts/bc-linux-overrides"

BASE_URL="${BC_BASE_URL:-http://localhost:7048/BC}"
API_URL="${BC_API_URL:-http://localhost:7052/BC}"
DEV_URL="${BC_DEV_URL:-http://localhost:7049/BC/dev}"
AUTH="${BC_AUTH:-BCRUNNER:Admin123!}"
SEED_TODAY="${SEED_TODAY:-$(date +%Y-%m-%d)}"
COMPANY_A="CRONUS-PLANOPT-A"
COMPANY_B="CRONUS-PLANOPT-B"
API_PATH="/api/fbakkensen/planningSeed/v1.0"
TRIGGER_PRIMARY_KEY="TRIGGER"

mode="idempotent"
for arg in "$@"; do
    case "$arg" in
        --reset)  mode="reset"  ;;
        --nuke)   mode="nuke"   ;;
        --verify) mode="verify" ;;
        -h|--help)
            sed -n '6,30p' "$0"
            exit 0
            ;;
        *)
            echo "seed-company.sh: unknown argument '$arg' (expected: --reset, --nuke, --verify)" >&2
            exit 2
            ;;
    esac
done

# ─── helpers ─────────────────────────────────────────────────────────────────

compute_source_hash() {
    ( cd "$ROOT_DIR" && find seed -type f \( -name '*.al' -o -name 'app.json' \) | sort | xargs sha256sum ) \
        | sha256sum | awk '{print $1}'
}

marker_get() {
    local key="$1"
    [ -f "$MARKER_FILE" ] || { echo ""; return; }
    python3 -c "
import json, sys
try:
    with open('$MARKER_FILE') as f:
        print(json.load(f).get('$key', ''))
except Exception:
    pass
"
}

write_marker() {
    local source_hash="$1"
    mkdir -p "$(dirname "$MARKER_FILE")"
    python3 -c "
import json
marker = {
    'source_hash': '$source_hash',
    'seed_today': '$SEED_TODAY',
    'company_a': '$COMPANY_A',
    'company_b': '$COMPANY_B',
}
with open('$MARKER_FILE', 'w') as f:
    json.dump(marker, f, indent=2)
"
}

days_since() {
    local iso="$1"
    [ -z "$iso" ] && { echo 99999; return; }
    python3 -c "
import datetime
try:
    d = datetime.date.fromisoformat('$iso')
    print((datetime.date.today() - d).days)
except Exception:
    print(99999)
"
}

check_bc_reachable() {
    echo "Checking Business Central availability..."
    curl -sf -u "$AUTH" "${BASE_URL}/ODataV4/Company" >/dev/null || {
        echo "seed-company.sh: BC unreachable at $BASE_URL — start the stack first (cd bc-linux && docker compose up -d --wait)" >&2
        exit 1
    }
}

fetch_companies_json() {
    curl -sf -u "$AUTH" "${API_URL}${API_PATH}/companies" || {
        echo "seed-company.sh: failed to fetch /companies — is the seed extension published?" >&2
        return 1
    }
}

company_id_by_name() {
    local target="$1"
    fetch_companies_json | python3 -c "
import json, sys, os
target = os.environ['TARGET']
data = json.load(sys.stdin)
for c in data.get('value', []):
    if c.get('name') == target:
        print(c.get('id'))
        sys.exit(0)
sys.exit(1)
" TARGET="$target" 2>/dev/null
    # Note: env var passed via TARGET=... at the end of -c command isn't standard;
    # use real env. Re-doing properly below.
}

# Proper helpers using env to avoid shell-quoting issues with JSON content.
company_id_by_name() {
    local target="$1"
    TARGET="$target" sh -c 'curl -sf -u "$0" "$1${2}/companies"' "$AUTH" "$API_URL" "$API_PATH" | \
        TARGET="$target" python3 -c '
import json, sys, os
target = os.environ["TARGET"]
data = json.load(sys.stdin)
for c in data.get("value", []):
    if c.get("name") == target:
        print(c.get("id"))
        sys.exit(0)
sys.exit(1)
'
}

first_available_company_id() {
    curl -sf -u "$AUTH" "${API_URL}${API_PATH}/companies" | \
        COMPANY_A="$COMPANY_A" COMPANY_B="$COMPANY_B" python3 -c '
import json, sys, os
co_a = os.environ["COMPANY_A"]
co_b = os.environ["COMPANY_B"]
data = json.load(sys.stdin)
for c in data.get("value", []):
    name = c.get("name", "")
    if name in (co_a, co_b):
        continue
    print(c.get("id"))
    sys.exit(0)
sys.exit(1)
'
}

trigger_row_id() {
    local company_id="$1"
    curl -sf -u "$AUTH" "${API_URL}${API_PATH}/companies(${company_id})/poSeedEndpoints" | \
        python3 -c '
import json, sys
data = json.load(sys.stdin)
rows = data.get("value", [])
if not rows:
    sys.exit(2)
print(rows[0]["id"])
'
}

invoke_action() {
    # invoke_action <company-id> <action> [body-json]
    local company_id="$1"
    local action="$2"
    local body="${3-}"
    [ -z "$body" ] && body='{}'
    local trigger_id
    trigger_id=$(trigger_row_id "$company_id") || {
        echo "seed-company.sh: no trigger row found in company $company_id — extension installed but install codeunit didn't run?" >&2
        return 1
    }
    local url="${API_URL}${API_PATH}/companies(${company_id})/poSeedEndpoints(${trigger_id})/Microsoft.NAV.${action}"
    local resp_body req_body
    resp_body=$(mktemp)
    req_body=$(mktemp)
    printf '%s' "$body" > "$req_body"
    local code
    code=$(curl -s -o "$resp_body" -w "%{http_code}" --max-time 1800 \
        -u "$AUTH" -X POST \
        -H "Content-Type: application/json" \
        --data-binary "@$req_body" \
        "$url" 2>/dev/null)
    rm -f "$req_body"
    if [ "$code" = "200" ] || [ "$code" = "204" ]; then
        rm -f "$resp_body"
        return 0
    fi
    echo "seed-company.sh: action '${action}' failed (HTTP ${code}) — body:" >&2
    sed 's/^/  /' "$resp_body" >&2
    rm -f "$resp_body"
    return 1
}

compile_and_publish() {
    # Compile both projects (compile.sh seed auto-pulls app in for symbols).
    "$ROOT_DIR/scripts/compile.sh" seed
    local app_app="$BUILD_DIR/BcLinuxSmoke.app"
    local seed_app="$BUILD_DIR/BcLinuxSmokePlanningSeed.app"
    [ -f "$app_app" ]  || { echo "seed-company.sh: production .app not found at $app_app" >&2; exit 1; }
    [ -f "$seed_app" ] || { echo "seed-company.sh: seed .app not found at $seed_app"      >&2; exit 1; }
    . "$ROOT_DIR/bc-linux/scripts/publish-app.sh"
    # Production app first — seed depends on it. Both publishes are
    # idempotent (publish-app.sh returns 0 on "already installed").
    # Seed extension publishes the install codeunit which creates the
    # PLANOPT companies via Assisted Company Setup (works because
    # fix-tenantid.sh set $ndo$tenantproperty.tenantid).
    echo "Publishing production app..."
    bc_publish_app "$app_app" "$DEV_URL" "$AUTH"
    echo "Publishing seed extension..."
    bc_publish_app "$seed_app" "$DEV_URL" "$AUTH"
}

run_seed_orchestration() {
    # With $ndo$tenantproperty.tenantid set to 'default' (fix-tenantid.sh),
    # the seed extension's OnInstallAppPerDatabase trigger creates both
    # PLANOPT companies as part of the publish. No external invocation
    # needed for company creation — just look up the IDs and seed.
    local co_a_id co_b_id
    co_a_id=$(company_id_by_name "$COMPANY_A") || {
        echo "seed-company.sh: $COMPANY_A not visible via /api/.../companies" >&2
        exit 1
    }
    co_b_id=$(company_id_by_name "$COMPANY_B") || {
        echo "seed-company.sh: $COMPANY_B not visible via /api/.../companies" >&2
        exit 1
    }
    echo "Found $COMPANY_A id=$co_a_id, $COMPANY_B id=$co_b_id"

    echo "Seeding $COMPANY_A..."
    invoke_action "$co_a_id" "SeedSingleCompany" "{\"seedToday\":\"$SEED_TODAY\"}" || exit 1
    echo "Seeding $COMPANY_B..."
    invoke_action "$co_b_id" "SeedSingleCompany" "{\"seedToday\":\"$SEED_TODAY\"}" || exit 1
}

run_teardown_orchestration() {
    local bootstrap_company_id
    if bootstrap_company_id=$(first_available_company_id 2>/dev/null); then
        echo "Invoking TeardownCompanies..."
        invoke_action "$bootstrap_company_id" "TeardownCompanies" || {
            echo "seed-company.sh: TeardownCompanies failed — continuing anyway, --nuke may help" >&2
        }
    else
        echo "seed-company.sh: no company available for teardown (skipping)" >&2
    fi
}

run_verify_report() {
    echo "--verify: emitting shape report from bc_api.py..."
    local extracts_dir="$BUILD_DIR/extracts"
    mkdir -p "$extracts_dir"
    for company in "$COMPANY_A" "$COMPANY_B"; do
        local out="$extracts_dir/$company"
        mkdir -p "$out"
        echo "  - $company → $out"
        BC_API_BASE_URL="$API_URL" \
        BC_AUTH="$AUTH" \
        BC_COMPANY_NAME="$company" \
            python3 -c "
import csv
import sys
from pathlib import Path
sys.path.insert(0, '$ROOT_DIR/planning-optimizer')
from extracts import bc_api
cfg = bc_api.BcApiConfig.from_env()
out = Path('$out')
out.mkdir(parents=True, exist_ok=True)

def write(name, rows, columns):
    path = out / name
    with path.open('w', newline='') as fh:
        writer = csv.DictWriter(fh, fieldnames=columns)
        writer.writeheader()
        for r in rows:
            writer.writerow({k: r.get(k, '') for k in columns})
    print(f'      {name}: {len(rows)} rows')

write('ile_summary.csv', bc_api.fetch_item_ledger_summaries(cfg), bc_api.ILE_SUMMARY_COLUMNS)
write('purchase_lt.csv', bc_api.fetch_purchase_receipt_lt(cfg), bc_api.PURCHASE_RECEIPT_LT_COLUMNS)
write('open_sd.csv', bc_api.fetch_open_sd_events(cfg), bc_api.OPEN_SD_EVENT_COLUMNS)
" || echo "    (extract failed — check that the extension is published and the company exists)"
    done
}

# ─── mode dispatch ───────────────────────────────────────────────────────────

case "$mode" in
    nuke)
        echo "--nuke: restarting BC container..."
        ( cd "$ROOT_DIR/bc-linux" && docker compose restart bc )
        echo "--nuke: waiting for BC to come back..."
        for _ in $(seq 1 60); do
            curl -sf -u "$AUTH" "${BASE_URL}/ODataV4/Company" >/dev/null && break
            sleep 5
        done
        mode="reset"
        ;;
esac

# Bootstrap bc-linux/ with our durable overrides BEFORE the container needs
# them. bc-linux/ is a gitignored upstream checkout; on a fresh clone the
# overrides are absent and SQL boots without FTS / memory bump. The source
# of truth lives in scripts/bc-linux-overrides/ (tracked in this repo).
sync_bc_overrides() {
    local changed=0
    if [ ! -d "$BC_LINUX_DIR" ]; then
        echo "seed-company.sh: bc-linux/ checkout missing — clone StefanMaron/MsDyn365Bc.On.Linux first" >&2
        exit 1
    fi
    for f in sql-fts.Dockerfile docker-compose.override.yml; do
        local src="$OVERRIDES_DIR/$f"
        local dst="$BC_LINUX_DIR/$f"
        if [ ! -f "$src" ]; then
            echo "seed-company.sh: missing override source $src" >&2
            exit 1
        fi
        if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
            cp "$src" "$dst"
            echo "seed-company.sh: synced bc-linux/$f from scripts/bc-linux-overrides/"
            changed=1
        fi
    done
    # If overrides changed and the SQL container is already running on the
    # OLD image, we'd need a down+up to pick up the new sql-fts image. We
    # don't force this — flag it instead so the user / caller knows.
    if [ "$changed" = "1" ] && docker ps --format '{{.Names}}' | grep -q '^bc-linux-sql-1$'; then
        echo "seed-company.sh: overrides updated but bc-linux containers are running — run (cd bc-linux && docker compose down && docker compose up -d --wait) to rebuild SQL with new image" >&2
    fi
}

ensure_bc_running() {
    # If the BC stack isn't up, bring it up. docker compose will see the
    # override (just synced) and auto-build the bc-linux-sql-fts:local image.
    if curl -sf -u "$AUTH" "${BASE_URL}/ODataV4/Company" >/dev/null 2>&1; then
        return 0
    fi
    echo "seed-company.sh: BC not reachable — running (cd bc-linux && docker compose up -d --wait)..."
    ( cd "$BC_LINUX_DIR" && docker compose up -d --wait ) || {
        echo "seed-company.sh: docker compose up failed" >&2
        exit 1
    }
}

sync_bc_overrides
ensure_bc_running

# Patch known container runtime issues (tenantid + FTS) before anything else.
# Idempotent — fast no-op once applied to this container.
"$ROOT_DIR/scripts/fix-tenantid.sh"

check_bc_reachable

case "$mode" in
    idempotent)
        current_hash=$(compute_source_hash)
        marker_hash=$(marker_get source_hash)
        marker_seed_today=$(marker_get seed_today)
        stale_days=$(days_since "$marker_seed_today")
        companies_present=0
        if curl -sf -u "$AUTH" "${BASE_URL}/ODataV4/Company" 2>/dev/null | grep -q "$COMPANY_A" && \
           curl -sf -u "$AUTH" "${BASE_URL}/ODataV4/Company" 2>/dev/null | grep -q "$COMPANY_B"; then
            companies_present=1
        fi

        if [ "$current_hash" = "$marker_hash" ] && [ "$stale_days" -le "$STALENESS_DAYS" ] && [ "$companies_present" = "1" ]; then
            echo "seed-company.sh: marker matches (hash=$current_hash, seed_today=$marker_seed_today, age=${stale_days}d ≤ $STALENESS_DAYS, companies present) — nothing to do."
            exit 0
        fi

        if [ "$companies_present" != "1" ]; then
            echo "seed-company.sh: companies missing from BC (container restart wiped tmpfs?) — re-seeding."
        elif [ "$current_hash" != "$marker_hash" ]; then
            echo "seed-company.sh: seed source hash changed (marker=$marker_hash, current=$current_hash) — re-seeding."
        else
            echo "seed-company.sh: marker SEED_TODAY=$marker_seed_today is ${stale_days}d old (> $STALENESS_DAYS) — re-seeding to refresh dates."
        fi
        compile_and_publish
        run_seed_orchestration
        write_marker "$current_hash"
        echo "seed-company.sh: done. SEED_TODAY=$SEED_TODAY."
        ;;
    reset)
        echo "--reset: teardown + re-seed."
        compile_and_publish
        run_teardown_orchestration
        # Re-publish in case teardown deleted the extension state from the new companies.
        compile_and_publish
        run_seed_orchestration
        write_marker "$(compute_source_hash)"
        echo "seed-company.sh: --reset done. SEED_TODAY=$SEED_TODAY."
        ;;
    verify)
        run_verify_report
        ;;
esac
