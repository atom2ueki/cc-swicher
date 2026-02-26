#!/usr/bin/env bash
set -euo pipefail

# Uninstaller for CC-Switcher
# - Removes ccswicher function blocks from shell rc files
# - Removes PATH-installed ccswicher wrappers
# - Removes installed assets under standard data dirs

BEGIN_MARK="# >>> ccswicher function begin >>>"
END_MARK="# <<< ccswicher function end <<<"

log_info() {
  echo "==> $*"
}

log_warn() {
  echo "Warning: $*" >&2
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

remove_block() {
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
    echo "Removed ccswicher function from: $rc"
  fi
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

find_candidate_bin_dirs() {
  local bins=()
  if [[ -n "${XDG_BIN_HOME:-}" ]]; then
    bins+=("$XDG_BIN_HOME")
  fi
  bins+=("$HOME/.local/bin" "$HOME/bin" "/usr/local/bin")
  if command -v brew >/dev/null 2>&1; then
    bins+=("$(brew --prefix)/bin")
  fi
  echo "${bins[*]}"
}

is_ccswicher_wrapper() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  if [[ -L "$path" ]]; then
    local target
    target="$(readlink "$path" 2>/dev/null || true)"
    if [[ "$target" == *"/ccswicher.sh" || "$target" == *".ccswicher/ccswicher.sh" ]]; then
      return 0
    fi
  fi
  if grep -q "ccswicher error: missing" "$path" && grep -q "CCM_SH=" "$path"; then
    return 0
  fi
  return 1
}

remove_wrappers() {
  local removed_any=false
  local bin_dirs
  bin_dirs=( $(find_candidate_bin_dirs) )
  local bin_dir
  for bin_dir in "${bin_dirs[@]:-}"; do
    [[ -d "$bin_dir" ]] || continue
    local ccswicher_path="$bin_dir/ccswicher"
    if is_ccswicher_wrapper "$ccswicher_path"; then
      run_cmd "$bin_dir" rm -f "$ccswicher_path"
      echo "Removed ccswicher wrapper: $ccswicher_path"
      removed_any=true
    fi
  done

  if ! $removed_any; then
    log_warn "No PATH-installed ccswicher wrappers detected"
  fi
}

remove_data_dirs() {
  local user_dir="${XDG_DATA_HOME:-$HOME/.local/share}/ccswicher"
  local legacy_dir="$HOME/.ccswicher"
  local system_dir="/usr/local/share/ccswicher"

  if [[ -d "$user_dir" ]]; then
    rm -rf "$user_dir"
    echo "Removed installed ccswicher assets at: $user_dir"
  fi

  if [[ -d "$legacy_dir" ]]; then
    rm -rf "$legacy_dir"
    echo "Removed legacy ccswicher assets at: $legacy_dir"
  fi

  if [[ -d "$system_dir" ]]; then
    run_cmd "$system_dir" rm -rf "$system_dir"
    echo "Removed system ccswicher assets at: $system_dir"
  fi
}

main() {
  local rc_files
  rc_files=( $(detect_rc_files) )
  local rc
  for rc in "${rc_files[@]:-}"; do
    remove_block "$rc"
  done

  remove_wrappers
  remove_data_dirs

  echo "Uninstall complete. Reload your shell if you used rc functions."
}

main "$@"
