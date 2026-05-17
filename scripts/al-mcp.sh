#!/usr/bin/env bash
# Launch the AL Model Context Protocol server (altool launchmcpserver)
# for this workspace. Locates the AL Language extension dynamically and
# configures --packagecachepath / --ruleset / --codeanalyzers to match
# scripts/compile.sh so MCP-driven builds run under the same strict gate.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"
cd "$ROOT_DIR"

shopt -s nullglob
mapfile -t AL_EXTS < <(printf '%s\n' "$HOME"/.vscode/extensions/ms-dynamics-smb.al-*/ | sort -V)
if (( ${#AL_EXTS[@]} == 0 )); then
    echo "al-mcp: AL Language extension not found under ~/.vscode/extensions/ms-dynamics-smb.al-*/" >&2
    exit 1
fi
AL_EXT="${AL_EXTS[-1]%/}"
ALTOOL="$AL_EXT/bin/linux/altool"
ANALYZERS_DIR="$AL_EXT/bin/Analyzers"

if [[ ! -x "$ALTOOL" ]]; then
    chmod +x "$ALTOOL" 2>/dev/null || true
fi
[[ -x "$ALTOOL" ]] || { echo "al-mcp: $ALTOOL is not executable" >&2; exit 1; }

CODEANALYZERS='${CodeCop};${UICop};${PerTenantExtensionCop}'
for cop in ALCops.Common ALCops.LinterCop ALCops.ApplicationCop \
           ALCops.FormattingCop ALCops.PlatformCop ALCops.DocumentationCop \
           ALCops.TestAutomationCop; do
    CODEANALYZERS+=";$ANALYZERS_DIR/$cop.dll"
done

exec "$ALTOOL" launchmcpserver app test integration-test \
    --transport stdio \
    --packagecachepath ../.alpackages \
    --ruleset ../custom.ruleset.json \
    --codeanalyzers "$CODEANALYZERS"
