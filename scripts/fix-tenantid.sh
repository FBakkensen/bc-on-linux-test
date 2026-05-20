#!/usr/bin/env bash
set -euo pipefail

# Patches the BC Docker container's known runtime issues so PLANOPT seed
# companies can be created. Two fixes, both idempotent:
#
# 1. **tenantid**: bc-linux's entrypoint.sh sets [$ndo$tenantproperty].tenanttype=1
#    but leaves tenantid blank. BC's platform then fails Company.Insert with
#    "Tenant numeric id must be set" (navcontainerhelper #1166 / #1254).
#    Fix: UPDATE [$ndo$tenantproperty] SET tenantid = 'default'.
#
# 2. **SQL Full-Text Search**: bc-linux's mssql-2022 SQL image doesn't include
#    mssql-server-fts. BC requires it for the full-text indexes on per-company
#    tables that AL's Database.CopyCompany / Assisted Company Setup create.
#    Fix: apt-get install -y mssql-server-fts inside the SQL container.
#
# After either fix, the SQL service is restarted so the changes take effect,
# then BC is restarted so it re-reads $ndo$tenantproperty and reconnects.
#
# Despite the historical name, this script now fixes BOTH issues.
# Called by scripts/seed-company.sh on every invocation; safe to call manually.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SQL_CONTAINER="${SQL_CONTAINER:-bc-linux-sql-1}"
BC_CONTAINER="${BC_CONTAINER:-bc-linux-bc-1}"
SA_PASSWORD="${SA_PASSWORD:-Passw0rd123!}"
BC_DB="${BC_DB:-CRONUS}"
BC_BASE_URL="${BC_BASE_URL:-http://localhost:7048/BC}"
BC_AUTH="${BC_AUTH:-BCRUNNER:Admin123!}"
SQLCMD=(docker exec -u root "$SQL_CONTAINER" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -d "$BC_DB")

restart_required=0

# ─── Fix 1: tenantid ────────────────────────────────────────────────────────
current_tenantid=$("${SQLCMD[@]}" -h -1 -W -Q "SET NOCOUNT ON; SELECT ISNULL(tenantid, '') FROM [\$ndo\$tenantproperty]" 2>/dev/null | head -n1 | tr -d '[:space:]')
if [ -n "$current_tenantid" ]; then
    echo "fix-tenantid.sh: tenantid already set to '$current_tenantid' — skipping."
else
    echo "fix-tenantid.sh: tenantid is blank — setting to 'default'..."
    "${SQLCMD[@]}" -Q "UPDATE [\$ndo\$tenantproperty] SET tenantid = N'default' WHERE tenantid IS NULL OR tenantid = N''" >/dev/null
    restart_required=1
fi

# ─── Fix 2: SQL Full-Text Search (verify only) ──────────────────────────────
# FTS is baked into the SQL image by bc-linux/sql-fts.Dockerfile +
# docker-compose.override.yml. We just verify it's present; if missing,
# the user is using the wrong image and needs to rebuild.
fts_installed=$(docker exec -u root "$SQL_CONTAINER" bash -c "dpkg -l mssql-server-fts 2>/dev/null | awk '/^ii/ {print \$1}'" | head -n1)
if [ -z "$fts_installed" ]; then
    echo "fix-tenantid.sh: mssql-server-fts NOT installed in the SQL container." >&2
    echo "                 The bc-linux/docker-compose.override.yml should point at" >&2
    echo "                 bc-linux-sql-fts:local (built from bc-linux/sql-fts.Dockerfile)." >&2
    echo "                 Run: (cd bc-linux && docker compose build sql && docker compose up -d --wait)" >&2
    exit 1
fi
echo "fix-tenantid.sh: mssql-server-fts present in SQL container."

# ─── Restart if anything changed ────────────────────────────────────────────
if [ "$restart_required" = "0" ]; then
    echo "fix-tenantid.sh: nothing to do."
    exit 0
fi

echo "fix-tenantid.sh: restarting BC container so it re-reads tenant config..."
# Restart BC only. Restarting SQL would wipe its tmpfs (tmpfs is per-
# container-start in Docker), losing Cronus + every seeded company. FTS is
# baked into the SQL image by docker-compose.override.yml, so SQL doesn't
# need a restart for that fix either.
( cd "$ROOT_DIR/bc-linux" && docker compose restart bc ) >/dev/null

echo "fix-tenantid.sh: waiting for BC to come back..."
for _ in $(seq 1 60); do
    if curl -sf -u "$BC_AUTH" "${BC_BASE_URL}/ODataV4/Company" >/dev/null 2>&1; then
        echo "fix-tenantid.sh: BC reachable. Fixes applied."
        exit 0
    fi
    sleep 5
done

echo "fix-tenantid.sh: BC did not come back within timeout" >&2
exit 1
