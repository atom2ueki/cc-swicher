#!/usr/bin/env bash
set -euo pipefail

# Installer for CC-Switcher
# Default: user-level install (PATH-based)
# Optional: system-level, project-level, rc-function injection

# GitHub repository info
GITHUB_REPO="${GITHUB_REPO:-atom2ueki/cc-switcher}"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}"

# Detect HTTP client
if command -v curl &>/dev/null; then
    HTTP_CLIENT="curl"
elif command -v wget &>/dev/null; then
    HTTP_CLIENT="wget"
fi

# Get latest release tag (default to main if no tags or error)
get_latest_tag() {
    local tags_json
    if [[ "$HTTP_CLIENT" == "curl" ]]; then
        tags_json=$(curl -fsSL "${GITHUB_API}/tags" 2>/dev/null) || return 1
    elif [[ "$HTTP_CLIENT" == "wget" ]]; then
        tags_json=$(wget -qO- "${GITHUB_API}/tags" 2>/dev/null) || return 1
    else
        return 1
    fi
    echo "$tags_json" | grep -o '"name": "[^"]*"' | sed 's/"name": "//;s/"//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
}

# Set GITHUB_BRANCH to latest tag if not specified
GITHUB_BRANCH="${GITHUB_BRANCH:-$(get_latest_tag 2>/dev/null)}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"

# Detect if running from local directory or piped from curl
if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  LOCAL_MODE=true
else
  SCRIPT_DIR=""
  LOCAL_MODE=false
fi

BEGIN_MARK="# >>> ccswitcher function begin >>>"
END_MARK="# <<< ccswitcher function end <<<"

MODE="user"
PREFIX=""
ENABLE_RC=true
CLEANUP_LEGACY=false
ASSUME_YES=false
PROJECT_DIR=""
INTERACTIVE=false

log_info() {
  echo "==> $*"
}

log_warn() {
  echo "Warning: $*" >&2
}

log_error() {
  echo "Error: $*" >&2
}

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Options:
  --user                User-level install (default)
  --system              System-level install (may require sudo)
  --project             Project-level install into .ccswitcher/ (current dir)
  --prefix <dir>        Override install bin directory
  --rc                  Inject ccswitcher function into shell rc (default)
  --no-rc               Do not inject ccswitcher function into shell rc
  --cleanup-legacy      Remove legacy rc blocks and old install dirs
  --interactive         Force interactive prompts
  -y, --yes             Assume yes for prompts
  -h, --help            Show this help

Examples:
  ./install.sh
  ./install.sh --user
  ./install.sh --system
  ./install.sh --project
  ./install.sh --prefix "$HOME/bin"
  ./install.sh --cleanup-legacy
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        MODE="user"
        ;;
      --system)
        MODE="system"
        ;;
      --project)
        MODE="project"
        PROJECT_DIR="${PROJECT_DIR:-$PWD}"
        ;;
      --prefix)
        shift || true
        PREFIX="${1:-}"
        ;;
      --rc)
        ENABLE_RC=true
        ;;
      --no-rc)
        ENABLE_RC=false
        ;;
      --cleanup-legacy|--migrate)
        CLEANUP_LEGACY=true
        ;;
      --interactive)
        INTERACTIVE=true
        ;;
      -y|--yes)
        ASSUME_YES=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
    shift || true
  done
}

in_path() {
  echo "$PATH" | tr ':' '\n' | grep -Fqx "$1"
}

needs_sudo() {
  local dir="$1"
  [[ -d "$dir" && ! -w "$dir" ]]
}

run_cmd() {
  local dir="$1"
  shift
  if needs_sudo "$dir"; then
    sudo "$@"
  else
    "$@"
  fi
}

find_user_bin_dir() {
  if [[ -n "${XDG_BIN_HOME:-}" ]]; then
    echo "$XDG_BIN_HOME"
    return 0
  fi
  if [[ -d "$HOME/.local/bin" || ! -d "$HOME/bin" ]]; then
    echo "$HOME/.local/bin"
    return 0
  fi
  echo "$HOME/bin"
}

find_system_bin_dir() {
  if command -v brew >/dev/null 2>&1; then
    local brew_bin
    brew_bin="$(brew --prefix)/bin"
    if [[ -d "$brew_bin" ]]; then
      echo "$brew_bin"
      return 0
    fi
  fi
  echo "/usr/local/bin"
}

select_bin_dir() {
  if [[ -n "$PREFIX" ]]; then
    echo "$PREFIX"
    return 0
  fi
  if [[ "$MODE" == "system" ]]; then
    find_system_bin_dir
  else
    find_user_bin_dir
  fi
}

select_data_dir() {
  if [[ "$MODE" == "system" ]]; then
    echo "/usr/local/share/ccswitcher"
    return 0
  fi
  echo "${XDG_DATA_HOME:-$HOME/.local/share}/ccswitcher"
}

detect_rc_files() {
  local rc_files=()
  [[ -f "$HOME/.zshrc" ]] && rc_files+=("$HOME/.zshrc")
  [[ -f "$HOME/.zprofile" ]] && rc_files+=("$HOME/.zprofile")
  [[ -f "$HOME/.bashrc" ]] && rc_files+=("$HOME/.bashrc")
  [[ -f "$HOME/.bash_profile" ]] && rc_files+=("$HOME/.bash_profile")
  [[ -f "$HOME/.profile" ]] && rc_files+=("$HOME/.profile")
  echo "${rc_files[*]}"
}

remove_existing_block() {
  local rc="$1"
  [[ -f "$rc" ]] || return 0
  if grep -qF "$BEGIN_MARK" "$rc"; then
    local tmp
    tmp="$(mktemp)"
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
      $0==b {inblock=1; next}
      $0==e {inblock=0; next}
      !inblock {print}
    ' "$rc" > "$tmp" && mv "$tmp" "$rc"
  fi
}

append_function_block() {
  local rc="$1"
  local script_path="$2"
  mkdir -p "$(dirname "$rc")"
  [[ -f "$rc" ]] || touch "$rc"
  cat >> "$rc" <<EOF
$BEGIN_MARK
# ccswitcher: define a shell function that applies exports to current shell
unalias ccswitcher 2>/dev/null || true
unset -f ccswitcher 2>/dev/null || true
ccswitcher() {
  local script="$script_path"
  if [[ ! -f "\$script" ]]; then
    local default1="\${XDG_DATA_HOME:-\$HOME/.local/share}/ccswitcher/ccswitcher.sh"
    local default2="\$HOME/.ccswitcher/ccswitcher.sh"
    if [[ -f "\$default1" ]]; then
      script="\$default1"
    elif [[ -f "\$default2" ]]; then
      script="\$default2"
    fi
  fi
  if [[ ! -f "\$script" ]]; then
    echo "ccswitcher error: script not found at \$script" >&2
    return 1
  fi

  case "\$1" in
    ""|"help"|"-h"|"--help"|"status"|"st"|"config"|"cfg"|"project"|"user")
      "\$script" "\$@"
      ;;
    *)
      eval "\$("\$script" "\$@")"
      ;;
  esac
}
$END_MARK
EOF
}

legacy_detect() {
  local current_data_dir="${1:-}"
  local found=false
  local legacy_msgs=()
  local rc_files
  rc_files=( $(detect_rc_files) )
  local rc
  for rc in "${rc_files[@]:-}"; do
    if grep -qF "$BEGIN_MARK" "$rc"; then
      found=true
      legacy_msgs+=("- legacy rc block in $rc")
    fi
  done
  if [[ -d "$HOME/.ccswitcher" ]]; then
    found=true
    legacy_msgs+=("- legacy dir $HOME/.ccswitcher")
  fi
  local user_data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/ccswitcher"
  if [[ -d "$user_data_dir" && "$user_data_dir" != "$current_data_dir" ]]; then
    legacy_msgs+=("- legacy dir $user_data_dir")
    found=true
  fi

  if $found; then
    printf '%s\n' "${legacy_msgs[@]}"
    return 0
  fi
  return 1
}

cleanup_legacy() {
  log_info "Cleaning legacy installation artifacts..."
  local rc_files
  rc_files=( $(detect_rc_files) )
  local rc
  for rc in "${rc_files[@]:-}"; do
    remove_existing_block "$rc"
  done
  rm -rf "$HOME/.ccswitcher" || true
  rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/ccswitcher" || true
}

download_from_github() {
  local url="$1"
  local dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
  else
    log_error "Neither curl nor wget found"
    return 1
  fi
}

install_assets() {
  local data_dir="$1"
  local dest_ccswitcher_sh="$data_dir/ccswitcher.sh"

  run_cmd "$data_dir" mkdir -p "$data_dir"

  if $LOCAL_MODE && [[ -f "$SCRIPT_DIR/ccswitcher.sh" ]]; then
    log_info "Installing from local directory..."
    run_cmd "$data_dir" cp -f "$SCRIPT_DIR/ccswitcher.sh" "$dest_ccswitcher_sh"
  else
    log_info "Installing from GitHub..."
    download_from_github "${GITHUB_RAW}/ccswitcher.sh" "$dest_ccswitcher_sh" || {
      log_error "failed to download ccswitcher.sh"
      exit 1
    }
  fi

  run_cmd "$data_dir" chmod +x "$dest_ccswitcher_sh"
}

write_ccswitcher_wrapper() {
  local bin_dir="$1"
  local mode="$2"
  local data_dir="$3"
  local target="$bin_dir/ccswitcher"

  run_cmd "$bin_dir" mkdir -p "$bin_dir"

  if [[ "$mode" == "project" ]]; then
    cat > "$target" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CCM_SH="$SCRIPT_DIR/../ccswitcher.sh"
if [[ ! -f "$CCM_SH" ]]; then
  echo "ccswitcher error: missing $CCM_SH" >&2
  exit 1
fi
exec "$CCM_SH" "$@"
EOF
  else
    local content
    content="$(cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CCM_SH="__DATA_DIR__/ccswitcher.sh"
if [[ ! -f "$CCM_SH" ]]; then
  echo "ccswitcher error: missing $CCM_SH" >&2
  exit 1
fi
exec "$CCM_SH" "$@"
EOF
)"
    content="${content//__DATA_DIR__/$data_dir}"
    printf '%s\n' "$content" > "$target"
  fi

  run_cmd "$bin_dir" chmod +x "$target"
}

write_project_activate() {
  local project_dir="$1"
  local activate_path="$project_dir/.ccswitcher/activate"
  cat > "$activate_path" <<'EOF'
# ccswitcher project activation
# Usage: source .ccswitcher/activate

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export PATH="$SCRIPT_DIR/bin:$PATH"
EOF
  chmod +x "$activate_path"
}

main() {
  local arg_count=$#
  parse_args "$@"

  echo ""
  log_info "CC-Switcher Installer"
  echo "Default: user-level PATH install + rc injection"
  echo "Options: --project (project-local), --system (system-wide), --no-rc (disable rc)"
  echo ""

  if [[ "$INTERACTIVE" == "false" && "$arg_count" -eq 0 && -t 0 && "$ASSUME_YES" == "false" ]]; then
    INTERACTIVE=true
  fi

  if $INTERACTIVE; then
    log_info "Interactive setup"
    echo "Select install mode:"
    echo "  1) User (recommended)"
    echo "  2) System (may require sudo)"
    echo "  3) Project (current directory only)"
    read -r -p "Choose [1-3] (default 1): " mode_choice
    case "$mode_choice" in
      2) MODE="system" ;;
      3) MODE="project" ;;
      *) MODE="user" ;;
    esac

    if [[ "$MODE" == "project" ]]; then
      read -r -p "Project directory (default: $PWD): " proj_choice
      PROJECT_DIR="${proj_choice:-$PWD}"
    fi

    if [[ "$MODE" != "project" ]]; then
      read -r -p "Inject ccswitcher function into shell rc? [Y/n]: " rc_choice
      rc_choice="${rc_choice:-Y}"
      case "$rc_choice" in
        n|N|no|NO) ENABLE_RC=false ;;
        *) ENABLE_RC=true ;;
      esac
    fi
  fi

  if [[ "$MODE" == "project" ]]; then
    PROJECT_DIR="${PROJECT_DIR:-$PWD}"
    ENABLE_RC=false
  fi

  if [[ "$MODE" == "project" && -n "$PREFIX" ]]; then
    log_error "--prefix cannot be used with --project"
    exit 1
  fi

  local bin_dir
  local data_dir
  if [[ "$MODE" == "project" ]]; then
    bin_dir="$PROJECT_DIR/.ccswitcher/bin"
    data_dir="$PROJECT_DIR/.ccswitcher"
  else
    bin_dir="$(select_bin_dir)"
    data_dir="$(select_data_dir)"
  fi

  log_info "Install plan"
  echo "  Mode: $MODE"
  if [[ "$MODE" == "project" ]]; then
    echo "  Project: $PROJECT_DIR"
  fi
  echo "  Bin:  $bin_dir"
  echo "  Data: $data_dir"
  if $ENABLE_RC; then
    echo "  RC injection: enabled"
  else
    echo "  RC injection: disabled"
  fi

  # Legacy detection and guidance
  local legacy_info=""
  if legacy_info=$(legacy_detect "$data_dir"); then
    echo ""
    log_warn "Legacy installation detected:"
    echo "$legacy_info"
    echo ""
    echo "This can override the new PATH-based install."
    echo "- To clean automatically, run: ./install.sh --cleanup-legacy"
    echo ""
    if ! $CLEANUP_LEGACY; then
      if [[ -t 0 && "$ASSUME_YES" == "false" ]]; then
        read -r -p "Clean legacy install now? [y/N] " reply
        case "$reply" in
          y|Y|yes|YES)
            CLEANUP_LEGACY=true
            ;;
        esac
      fi
    fi
  fi

  if $CLEANUP_LEGACY; then
    cleanup_legacy
  fi

  # Install assets
  install_assets "$data_dir"

  # Install wrapper
  write_ccswitcher_wrapper "$bin_dir" "$MODE" "$data_dir"

  # Optional rc injection
  if $ENABLE_RC && [[ "$MODE" != "project" ]]; then
    local rc_files
    rc_files=( $(detect_rc_files) )
    local rc_target="${rc_files[0]:-$HOME/.zshrc}"
    remove_existing_block "$rc_target"
    append_function_block "$rc_target" "$data_dir/ccswitcher.sh"
    log_info "Injected ccswitcher function into: $rc_target"
  fi

  if [[ "$MODE" == "project" ]]; then
    write_project_activate "$PROJECT_DIR"
  fi

  echo ""
  log_info "Installation complete"
  echo "   Mode: $MODE"
  echo "   Bin:  $bin_dir"
  echo "   Data: $data_dir"

  if ! in_path "$bin_dir"; then
    echo ""
    log_warn "$bin_dir is not in your PATH"
    echo "Add this to your shell rc (~/.zshrc or ~/.bashrc):"
    echo "  export PATH=\"$bin_dir:\$PATH\""
  fi

  echo ""
  echo "Next steps:"
  if [[ "$MODE" == "project" ]]; then
    echo "  source .ccswitcher/activate"
    echo "  ccswitcher status"
  else
    if $ENABLE_RC; then
      echo "  source ~/.zshrc (or ~/.bashrc)"
      echo "  ccswitcher status"
    else
      echo "  eval \"\$(ccswitcher zai)\"   # Apply env to current shell"
    fi
  fi
}

main "$@"
