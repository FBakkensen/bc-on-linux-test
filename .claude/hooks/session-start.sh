#!/bin/bash
# SessionStart hook for Claude Code on the web.
#
# Mirrors .github/workflows/copilot-setup-steps.yml so that a fresh
# remote session starts with the same prepared state a Copilot-wired
# fork gets: bc-linux/ cloned, BC artifacts downloaded, .NET 8 + AL
# compiler installed, symbols staged into app/.alpackages and
# test/.alpackages, and BC booted and healthy.
#
# The agent's first command should then be `./scripts/smoke.sh`.
#
# Firewall note:
#   bcartifacts.blob.core.windows.net must be reachable. If artifact
#   download fails on first run with a DNS or 403 error, allowlist it
#   in your Claude Code on the web egress policy.

set -euo pipefail

# Only run in a remote (Claude Code on the web) environment. Local
# `claude` sessions should not be rebuilding BC every time.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

: "${CLAUDE_PROJECT_DIR:?CLAUDE_PROJECT_DIR is required}"
: "${CLAUDE_ENV_FILE:?CLAUDE_ENV_FILE is required}"

cd "$CLAUDE_PROJECT_DIR"

# -----------------------------------------------------------------------------
# 1. BC environment variables
# -----------------------------------------------------------------------------
BC_VERSION="27.5"
BC_COUNTRY="w1"
BC_TYPE="sandbox"
BC_RUNNER_IMAGE="ghcr.io/stefanmaron/msdyn365bc.on.linux/bc-runner:latest"
AL_TOOL_VERSION="16.2.28.57946"
BC_LINUX_REF="master"
APP_DIRS="app"
TEST_APP_DIRS="test"
TEST_CODEUNIT_RANGE="50100..50149"

{
  echo "export BC_VERSION=$BC_VERSION"
  echo "export BC_COUNTRY=$BC_COUNTRY"
  echo "export BC_TYPE=$BC_TYPE"
  echo "export BC_RUNNER_IMAGE=$BC_RUNNER_IMAGE"
  echo "export AL_TOOL_VERSION=$AL_TOOL_VERSION"
  echo "export BC_LINUX_REF=$BC_LINUX_REF"
  echo "export APP_DIRS=$APP_DIRS"
  echo "export TEST_APP_DIRS=$TEST_APP_DIRS"
  echo "export TEST_CODEUNIT_RANGE=$TEST_CODEUNIT_RANGE"
  echo "export BC_TEST_CODEUNIT_RANGE=$TEST_CODEUNIT_RANGE"
} >> "$CLAUDE_ENV_FILE"

export BC_VERSION BC_COUNTRY BC_TYPE BC_RUNNER_IMAGE AL_TOOL_VERSION \
       BC_LINUX_REF APP_DIRS TEST_APP_DIRS TEST_CODEUNIT_RANGE

# -----------------------------------------------------------------------------
# 2. Install Docker if needed, then make sure the daemon is running
# -----------------------------------------------------------------------------
# On Copilot's ubuntu-latest runners this is implicit — Docker is
# preinstalled and the daemon is up. Claude Code on the web sandboxes
# aren't guaranteed to have either, so install + start here. Steps 4
# (compose pull) and 10 (compose up) both need this.
as_root() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
  else
    sudo "$@"
  fi
}

if ! docker info >/dev/null 2>&1; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "Installing Docker via get.docker.com"
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    as_root sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
  fi

  # Try the normal init paths first, then fall back to launching dockerd directly.
  if command -v systemctl >/dev/null 2>&1 && \
       as_root systemctl start docker 2>/dev/null; then
    :
  elif command -v service >/dev/null 2>&1 && \
       as_root service docker start 2>/dev/null; then
    :
  else
    echo "No init system detected — starting dockerd in the background"
    as_root sh -c 'nohup dockerd > /var/log/dockerd.log 2>&1 &'
  fi

  # Wait up to 60s for the socket to accept connections.
  for attempt in $(seq 1 60); do
    if docker info >/dev/null 2>&1; then
      echo "Docker daemon ready after ${attempt}s"
      break
    fi
    sleep 1
  done

  docker info >/dev/null 2>&1 || {
    echo "Docker daemon failed to start; last 50 log lines:"
    as_root tail -50 /var/log/dockerd.log 2>/dev/null || true
    exit 1
  }
else
  echo "Docker daemon already running — skipping install"
fi

# -----------------------------------------------------------------------------
# 3. Clone MsDyn365Bc.On.Linux into bc-linux/
# -----------------------------------------------------------------------------
if [ ! -d bc-linux/.git ]; then
  echo "Cloning StefanMaron/MsDyn365Bc.On.Linux ($BC_LINUX_REF) into bc-linux/"
  git clone --depth=1 --branch "$BC_LINUX_REF" \
    https://github.com/StefanMaron/MsDyn365Bc.On.Linux.git bc-linux
else
  echo "bc-linux/ already cloned — skipping"
fi

# -----------------------------------------------------------------------------
# 4. Download BC artifacts + docker compose pull (parallel, with retries)
# -----------------------------------------------------------------------------
mkdir -p ".bc-artifacts/$BC_VERSION"

(
  bc-linux/scripts/download-artifacts.sh \
    "$BC_TYPE" "$BC_VERSION" "$BC_COUNTRY" \
    "$PWD/.bc-artifacts/$BC_VERSION"
) &
ART_PID=$!

(
  cd bc-linux
  for attempt in 1 2 3 4 5; do
    if BC_RUNNER_IMAGE="$BC_RUNNER_IMAGE" docker compose pull --quiet; then break; fi
    echo "docker compose pull failed (attempt $attempt/5); retrying in 15s..."
    sleep 15
  done
) &
PULL_PID=$!

wait $ART_PID  || { echo "artifact download failed"; exit 1; }
wait $PULL_PID || { echo "docker pull failed"; exit 1; }

# -----------------------------------------------------------------------------
# 5. Resolve selective keep-app set from consumer app.json files
# -----------------------------------------------------------------------------
# Include bc-linux's own TestRunnerExtension app.json so its dep on
# Microsoft Test Runner walks into the keep closure — without this
# the test publish later fails with AL1024.
ARGS="--app-json bc-linux/extensions/TestRunnerExtension/app.json"
for d in $APP_DIRS $TEST_APP_DIRS; do
  [ -z "$d" ] && continue
  if [ -f "$d/app.json" ]; then
    ARGS="$ARGS --app-json $d/app.json"
  fi
done
# shellcheck disable=SC2086
KEEP_IDS=$(python3 bc-linux/scripts/resolve-keep-app-ids.py \
  $ARGS \
  --artifact-dir ".bc-artifacts/$BC_VERSION")
echo "Resolved keep set: $KEEP_IDS"
mkdir -p .bc-cache
{
  echo "BC_CLEAR_ALL_APPS=selective"
  echo "BC_KEEP_APP_IDS=$KEEP_IDS"
  echo "BC_VERSION=$BC_VERSION"
  echo "BC_COUNTRY=$BC_COUNTRY"
  echo "BC_TYPE=$BC_TYPE"
  echo "BC_RUNNER_IMAGE=$BC_RUNNER_IMAGE"
} > .bc-cache/env

# -----------------------------------------------------------------------------
# 6. Install .NET 8 SDK (idempotent)
# -----------------------------------------------------------------------------
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"

needs_dotnet=1
if command -v dotnet >/dev/null 2>&1; then
  if dotnet --list-sdks 2>/dev/null | grep -q '^8\.'; then
    needs_dotnet=0
  fi
fi

if [ "$needs_dotnet" = "1" ]; then
  echo "Installing .NET 8 SDK into $DOTNET_ROOT"
  mkdir -p "$DOTNET_ROOT"
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  chmod +x /tmp/dotnet-install.sh
  /tmp/dotnet-install.sh --channel 8.0 --install-dir "$DOTNET_ROOT"
  rm -f /tmp/dotnet-install.sh
else
  echo ".NET 8 SDK already installed — skipping"
fi

{
  echo "export DOTNET_ROOT=$DOTNET_ROOT"
  echo "export PATH=$DOTNET_ROOT:$DOTNET_ROOT/tools:\$PATH"
} >> "$CLAUDE_ENV_FILE"

# -----------------------------------------------------------------------------
# 7. Install Linux AL compiler
# -----------------------------------------------------------------------------
if [ ! -x "$DOTNET_ROOT/tools/AL" ] && [ ! -x "$DOTNET_ROOT/tools/al" ]; then
  echo "Installing Microsoft.Dynamics.BusinessCentral.Development.Tools.Linux $AL_TOOL_VERSION"
  dotnet tool install -g \
    Microsoft.Dynamics.BusinessCentral.Development.Tools.Linux \
    --version "$AL_TOOL_VERSION"
else
  echo "AL compiler already installed — skipping"
fi

# Recent packages install as uppercase `AL`, older ones as lowercase
# `al`. smoke.sh calls `al compile`, so make sure the lowercase name
# resolves either way.
if [ -x "$DOTNET_ROOT/tools/AL" ] && [ ! -e "$DOTNET_ROOT/tools/al" ]; then
  ln -s AL "$DOTNET_ROOT/tools/al"
fi

# -----------------------------------------------------------------------------
# 8. Stage BC symbols into app/.alpackages and test/.alpackages
# -----------------------------------------------------------------------------
# stage-symbols.py reads the transitive dep closure directly from the
# artifact bundle — no running BC needed.
mkdir -p .symbols app/.alpackages test/.alpackages
python3 bc-linux/scripts/stage-symbols.py \
  --app-json app/app.json \
  --app-json test/app.json \
  --artifact-dir ".bc-artifacts/$BC_VERSION" \
  --out-dir .symbols \
  || true
cp .symbols/*.app app/.alpackages/
cp .symbols/*.app test/.alpackages/
echo "app/.alpackages:  $(ls app/.alpackages/*.app 2>/dev/null | wc -l) .app files"
echo "test/.alpackages: $(ls test/.alpackages/*.app 2>/dev/null | wc -l) .app files"

# -----------------------------------------------------------------------------
# 9. Sanity-check that smoke.sh will find everything it needs
# -----------------------------------------------------------------------------
test -d bc-linux/scripts            || { echo "missing bc-linux/scripts"; exit 1; }
test -d ".bc-artifacts/$BC_VERSION" || { echo "missing artifacts"; exit 1; }
test -d app/.alpackages             || { echo "missing app symbols"; exit 1; }
test -d test/.alpackages            || { echo "missing test symbols"; exit 1; }
command -v al >/dev/null            || { echo "AL compiler not on PATH"; exit 1; }
test -f .bc-cache/env               || { echo "missing .bc-cache/env"; exit 1; }
echo "Setup OK."

# -----------------------------------------------------------------------------
# 10. Boot BC and wait for healthy
# -----------------------------------------------------------------------------
# Propagate the resolved config into bc-linux/.env so any later
# `docker compose up -d --wait` the agent runs sees identical config
# (no container recreation, no artifact re-download).
set -a
# shellcheck disable=SC1091
. .bc-cache/env
set +a
{
  cat .bc-cache/env
  echo "BC_ARTIFACTS_DIR=$PWD/.bc-artifacts/$BC_VERSION"
} >> bc-linux/.env

(
  cd bc-linux
  if docker compose ps --status running 2>/dev/null | grep -q bc-runner; then
    echo "bc-runner already running — skipping boot"
  else
    docker compose up -d
  fi
  ./scripts/wait-for-bc-healthy.sh
  echo "BC is healthy. Current status:"
  docker compose ps
)

echo "Session environment ready. Run ./scripts/smoke.sh to verify."
