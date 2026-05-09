#!/usr/bin/env bash
# G4 — CRLF self-heal
[ "${PORTFOLIO_CRLF_FIXED:-0}" = "1" ] || PORTFOLIO_CRLF_FIXED=1 exec bash <(tr -d '\r' < "$0") "$@"

# G1 — refuse WSL1
if grep -qi microsoft /proc/version 2>/dev/null && [ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
  echo "WSL1 unsupported. Run: wsl --set-version <distro> 2" >&2
  exit 1
fi
# G2 — strip Windows PATH in WSL2
if grep -qi microsoft /proc/version 2>/dev/null; then
  export PATH="$(echo "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | tr '\n' ':' | sed 's/:$//')"
fi

for cmd in curl bash; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Required: $cmd" >&2
    exit 1
  }
done

set -u -o pipefail

sanitized_args=()
for arg in "$@"; do
  sanitized_args+=("${arg//$'\r'/}")
done
set -- "${sanitized_args[@]}"

PORTFOLIO_ORG="${PORTFOLIO_ORG:-M00C1FER}"
PORTFOLIO_BRANCH="${PORTFOLIO_BRANCH:-main}"

PORTFOLIO_TOOLS=(
  "mcp-citation-research|citation-research-mcp|research|Hard-mandate research MCP server (4-axis source floor, BM25 citations, 0.90 confidence gate)"
  "memory-tool-conformance|memory-conformance|testing|LLM memory tool 6-op contract conformance suite"
  "contract-net-router|cnr|coordination|FIPA Contract Net Protocol for LLM agent dispatch (lifecycle states + budget conservation)"
  "consensus-engine|consensus|coordination|Quality-scored multi-agent consensus with confidence-gated synthesis"
  "multi-agent-council|council|coordination|7-phase deliberation framework (BRIEF/RECON/WARGAME/COUNCIL)"
  "clear-benchmark|clear-bench|evaluation|Composite scoring across HELM/MMLU/etc. axes (5 dimensions, 4-tier pluggable)"
  "common-operating-picture|cop|coordination|fcntl-locked task registry with bid/claim bounty board"
  "cli-parity-validator|cli-parity|tooling|MCP tool exposure validator across CLI configurations"
  "mcts-research-explorer|mcts-explorer|research|Monte Carlo Tree Search for adaptive research traversal"
  "mesh-review|mesh-review|tooling|Vendor-neutral multi-LLM PR review with adversarial Sigma falsification gate"
  "gh-portfolio|gh-portfolio|tooling|Multi-repo GitHub fleet operator (Bash + gh + jq)"
)

usage() {
  cat <<'USAGE'
Usage: install-portfolio.sh [OPTIONS]

  --all                Install all 11 tools (skips selection)
  --tools cnr,council  Install only these (comma-separated, by entry-point name)
  --pipx               Use pipx for all tools (recommended)
  --venv               Use venv for all tools
  --unattended         Skip all prompts (requires --all OR --tools, AND --pipx OR --venv)
  --list               Print the manifest and exit
  --help, -h           This help
USAGE
}

print_manifest() {
  printf '%-28s %-22s %-13s %s\n' "REPO" "ENTRY_POINT" "CATEGORY" "DESCRIPTION"
  for spec in "${PORTFOLIO_TOOLS[@]}"; do
    IFS='|' read -r repo entry category description <<<"$spec"
    printf '%-28s %-22s %-13s %s\n' "$repo" "$entry" "$category" "$description"
  done
}

LOG_FILE="${HOME}/.local/share/M00C1FER/install.log"
mkdir -p "$(dirname "$LOG_FILE")"

log_failure() {
  local repo="$1" stage="$2" detail="$3"
  printf '%s | %s | %s | %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$repo" "$stage" "$detail" >>"$LOG_FILE"
}

ALL_REPOS=()
ALL_ENTRIES=()
ALL_DESCRIPTIONS=()
declare -A ENTRY_TO_INDEX=()
for i in "${!PORTFOLIO_TOOLS[@]}"; do
  IFS='|' read -r repo entry _ description <<<"${PORTFOLIO_TOOLS[$i]}"
  ALL_REPOS+=("$repo")
  ALL_ENTRIES+=("$entry")
  ALL_DESCRIPTIONS+=("$description")
  ENTRY_TO_INDEX["$entry"]="$i"
done

tier3_select() {
  local choice_entry
  local final_selection
  local options=()
  local entry
  declare -A selected_map=()
  for entry in "${ALL_ENTRIES[@]}"; do
    options+=("$entry")
  done
  options+=("all" "none" "done")

  PS3="Choose tool to toggle (all/none/done): "
  while true; do
    select opt in "${options[@]}"; do
      case "${opt:-}" in
        all)
          for choice_entry in "${ALL_ENTRIES[@]}"; do
            selected_map["$choice_entry"]=1
          done
          echo "Selected all tools."
          ;;
        none)
          declare -A selected_map=()
          echo "Cleared selection."
          ;;
        done)
          final_selection=()
          for entry in "${ALL_ENTRIES[@]}"; do
            [ "${selected_map[$entry]:-0}" = "1" ] && final_selection+=("$entry")
          done
          if [ "${#final_selection[@]}" -eq 0 ]; then
            echo "No tools selected yet." >&2
          else
            printf '%s\n' "${final_selection[@]}"
            return 0
          fi
          ;;
        "")
          echo "Invalid selection." >&2
          ;;
        *)
          if [ "${selected_map[$opt]:-0}" = "1" ]; then
            unset "selected_map[$opt]"
            echo "Removed: $opt"
          else
            selected_map["$opt"]=1
            echo "Added: $opt"
          fi
          ;;
      esac
      break
    done
  done
}

interactive_select_tools() {
  if command -v gum >/dev/null 2>&1; then
    mapfile -t selection < <(gum choose --no-limit --header "Select tools to install" "${ALL_ENTRIES[@]}")
  elif command -v fzf >/dev/null 2>&1; then
    mapfile -t selection < <(printf '%s\n' "${ALL_ENTRIES[@]}" | fzf -m --prompt "Tools> ")
  else
    mapfile -t selection < <(tier3_select)
  fi
  if [ "${#selection[@]}" -eq 0 ]; then
    echo "No tools selected." >&2
    return 1
  fi
  printf '%s\n' "${selection[@]}"
}

choose_isolation() {
  echo "Choose isolation mode for all selected tools:"
  echo "[1] pipx install (recommended; isolated; in PATH automatically)"
  echo "[2] venv (created at ~/.local/share/M00C1FER/<tool>/.venv)"
  echo "[3] system pip (--break-system-packages on PEP 668 distros; not recommended)"
  echo "[4] each tool prompts individually"
  while true; do
    read -r -p "Enter choice [1-4]: " choice
    case "$choice" in
      1) echo "pipx"; return 0 ;;
      2) echo "venv"; return 0 ;;
      3) echo "pip"; return 0 ;;
      4) echo "each"; return 0 ;;
      *) echo "Invalid choice. Please enter 1-4." >&2 ;;
    esac
  done
}

install_all=false
tools_csv=""
isolation_mode=""
unattended=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      install_all=true
      ;;
    --tools)
      shift
      [ "$#" -gt 0 ] || {
        echo "Missing value for --tools" >&2
        exit 1
      }
      tools_csv="$1"
      ;;
    --pipx)
      isolation_mode="pipx"
      ;;
    --venv)
      isolation_mode="venv"
      ;;
    --unattended)
      unattended=true
      ;;
    --list)
      print_manifest
      exit 0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

$install_all && [ -n "$tools_csv" ] && {
  echo "Use either --all or --tools, not both." >&2
  exit 1
}

if $unattended; then
  if ! $install_all && [ -z "$tools_csv" ]; then
    echo "--unattended requires --all or --tools." >&2
    exit 1
  fi
  if [ "$isolation_mode" != "pipx" ] && [ "$isolation_mode" != "venv" ]; then
    echo "--unattended requires --pipx or --venv." >&2
    exit 1
  fi
fi

selected_entries=()
if $install_all; then
  selected_entries=("${ALL_ENTRIES[@]}")
elif [ -n "$tools_csv" ]; then
  IFS=',' read -r -a requested_entries <<<"$tools_csv"
  for entry in "${requested_entries[@]}"; do
    entry="${entry//[[:space:]]/}"
    if [ -z "$entry" ]; then
      continue
    fi
    if [ -z "${ENTRY_TO_INDEX[$entry]+x}" ]; then
      echo "Unknown tool entry-point: $entry" >&2
      echo "Run --list to see valid tools." >&2
      exit 1
    fi
    selected_entries+=("$entry")
  done
  [ "${#selected_entries[@]}" -gt 0 ] || {
    echo "No valid tools provided via --tools." >&2
    exit 1
  }
else
  mapfile -t selected_entries < <(interactive_select_tools) || exit 1
fi

if [ -z "$isolation_mode" ]; then
  isolation_mode="$(choose_isolation)"
fi

export PATH="$HOME/.local/bin:$PATH"

dry_run="${PORTFOLIO_DRY_RUN:-0}"
if [ "$dry_run" = "1" ]; then
  echo "[dry-run] Skipping remote fetch/install/smoke verification."
fi

successful=()
failed=()
declare -A FAILURE_STAGE=()
declare -A SUCCESS_MAP=()

for entry in "${selected_entries[@]}"; do
  idx="${ENTRY_TO_INDEX[$entry]}"
  repo="${ALL_REPOS[$idx]}"
  description="${ALL_DESCRIPTIONS[$idx]}"
  tmp_script="/tmp/install-${repo}.sh"

  echo "=== Installing ${repo}: ${description} ==="

  if [ "$dry_run" = "1" ]; then
    successful+=("$entry")
    SUCCESS_MAP["$entry"]=1
    continue
  fi

  if ! curl -fsSL "https://raw.githubusercontent.com/${PORTFOLIO_ORG}/${repo}/${PORTFOLIO_BRANCH}/install.sh" -o "$tmp_script"; then
    failed+=("$entry")
    FAILURE_STAGE["$entry"]="fetch"
    log_failure "$repo" "fetch" "failed to download install.sh"
    continue
  fi

  if ! head -1 "$tmp_script" | grep -q '^#!/.*bash'; then
    failed+=("$entry")
    FAILURE_STAGE["$entry"]="validate"
    log_failure "$repo" "validate" "install.sh missing bash shebang"
    continue
  fi

  install_args=("--unattended")
  case "$isolation_mode" in
    pipx) install_args=("--pipx" "--unattended") ;;
    venv) install_args=("--venv" "--unattended") ;;
    pip) install_args=("--pip" "--unattended") ;;
    each) install_args=("--unattended") ;;
    *)
      failed+=("$entry")
      FAILURE_STAGE["$entry"]="config"
      log_failure "$repo" "config" "unsupported isolation mode: $isolation_mode"
      continue
      ;;
  esac

  if ! bash "$tmp_script" "${install_args[@]}"; then
    failed+=("$entry")
    FAILURE_STAGE["$entry"]="install"
    log_failure "$repo" "install" "install script returned non-zero"
    continue
  fi

  smoke_ok=false
  if command -v "$entry" >/dev/null 2>&1 && "$entry" --help 2>&1 | grep -qE 'Usage:|usage:'; then
    smoke_ok=true
  elif [ -x "$HOME/.local/bin/$entry" ] && "$HOME/.local/bin/$entry" --help 2>&1 | grep -qE 'Usage:|usage:'; then
    smoke_ok=true
  fi
  if ! $smoke_ok; then
    failed+=("$entry")
    FAILURE_STAGE["$entry"]="smoke-verify"
    log_failure "$repo" "smoke-verify" "${entry} --help did not match Usage pattern"
    continue
  fi

  successful+=("$entry")
  SUCCESS_MAP["$entry"]=1
done

echo
echo "=== Portfolio install complete ==="
for entry in "${selected_entries[@]}"; do
  idx="${ENTRY_TO_INDEX[$entry]}"
  repo="${ALL_REPOS[$idx]}"
  if [ "${SUCCESS_MAP[$entry]:-0}" = "1" ]; then
    printf '✓ %-28s %s\n' "$repo" "$entry"
  else
    printf '✗ %-28s (failed at %s; see %s)\n' "$repo" "${FAILURE_STAGE[$entry]}" "$LOG_FILE"
  fi
done

echo
echo "Next: ensure ~/.local/bin is in your PATH:"
echo '  export PATH="$HOME/.local/bin:$PATH"'
echo
echo "Re-run for any failed tools individually:"
echo "  bash <(curl -fsSL https://raw.githubusercontent.com/${PORTFOLIO_ORG}/<tool>/${PORTFOLIO_BRANCH}/install.sh)"

[ "${#failed[@]}" -eq 0 ]
