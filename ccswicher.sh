#!/usr/bin/env bash
############################################################
# CC-Switcher - Claude Code Model Switcher
# Version: 3.1.0
#
# Usage:
#   ccswicher -g -p <provider>    # Set global provider
#   ccswicher -p <provider>       # Set project provider
#   ccswicher -g status           # Show global status
#   ccswicher status              # Show project status
#   ccswicher list                # List available providers
#   ccswicher upgrade             # Upgrade to latest version
############################################################

set -euo pipefail

# Constants
VERSION="3.1.0"
REPO_RAW="https://raw.githubusercontent.com/atom2ueki/cc-swicher/main"
PROVIDERS_URL="${REPO_RAW}/providers.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ccswicher"
CACHE_FILE="$CACHE_DIR/providers.json"
CACHE_TTL=86400  # 24 hours

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Disable colors if stdout is not a terminal
if [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# Settings paths
USER_SETTINGS="$HOME/.claude/settings.json"
PROJECT_SETTINGS=".claude/settings.local.json"

# Keys managed by ccswicher (to be removed when switching to anthropic)
CCS_KEYS=(
    "ANTHROPIC_BASE_URL"
    "ANTHROPIC_AUTH_TOKEN"
    "ANTHROPIC_MODEL"
    "ANTHROPIC_DEFAULT_HAIKU_MODEL"
    "ANTHROPIC_DEFAULT_SONNET_MODEL"
    "ANTHROPIC_DEFAULT_OPUS_MODEL"
    "CLAUDE_CODE_SUBAGENT_MODEL"
)

############################################################
# Utility Functions
############################################################

log_info()  { echo -e "${GREEN}==>${NC} $*"; }
log_warn()  { echo -e "${YELLOW}Warning:${NC} $*" >&2; }
log_error() { echo -e "${RED}Error:${NC} $*" >&2; }

json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

mask_token() {
    local t="$1"
    if [[ -z "$t" ]]; then
        echo "[not set]"
    elif [[ "$t" == '${'*'}' ]]; then
        echo "[env: ${t:2:-1}]"
    elif (( ${#t} <= 8 )); then
        echo "[set] ****"
    else
        echo "[set] ${t:0:4}...${t: -4}"
    fi
}

############################################################
# Remote Config Functions
############################################################

fetch_providers() {
    mkdir -p "$CACHE_DIR"

    # Determine script directory for local fallback
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    local local_config="$script_dir/providers.json"

    local use_cache=false
    if [[ -f "$CACHE_FILE" ]]; then
        local cache_age
        cache_age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
        if (( cache_age < CACHE_TTL )); then
            use_cache=true
        fi
    fi

    if $use_cache; then
        cat "$CACHE_FILE"
        return 0
    fi

    # Try remote fetch
    local success=false
    if command -v curl &>/dev/null; then
        if curl -fsSL --connect-timeout 5 "$PROVIDERS_URL" -o "$CACHE_FILE" 2>/dev/null; then
            success=true
        fi
    elif command -v wget &>/dev/null; then
        if wget -qO "$CACHE_FILE" --timeout=5 "$PROVIDERS_URL" 2>/dev/null; then
            success=true
        fi
    fi

    if $success && [[ -s "$CACHE_FILE" ]]; then
        cat "$CACHE_FILE"
        return 0
    fi

    # Fall back to local providers.json
    if [[ -f "$local_config" ]]; then
        cat "$local_config"
        return 0
    fi

    log_error "No provider config available" >&2
    return 1
}

get_provider_config() {
    local provider="$1"
    local json
    json=$(fetch_providers) || return 1

    # Simple extraction: find provider block
    local in_provider=false
    local depth=0
    local result=""
    local got_first_brace=false

    while IFS= read -r line; do
        if [[ "$line" == *'"providers"'*':'* ]]; then
            continue
        fi
        if [[ "$line" == *'"'"$provider"'"'*':'* ]]; then
            in_provider=true
            # Skip the "zai": { line, start from next line
            continue
        fi
        if $in_provider; then
            result+="$line"$'\n'
            if ! $got_first_brace && [[ "$line" == *'{'* ]]; then
                got_first_brace=true
                depth=1
                continue
            fi
            if [[ "$line" == *'{'* ]]; then
                ((depth++)) || true
            fi
            if [[ "$line" == *'}'* ]]; then
                ((depth--)) || true
                if (( depth <= 0 )); then
                    break
                fi
            fi
        fi
    done <<< "$json"

    if [[ -z "$result" ]]; then
        return 1
    fi
    echo "$result"
}

parse_json_value() {
    local json="$1"
    local key="$2"

    local line
    line=$(echo "$json" | grep "\"$key\"" | head -1) || return 1

    # Extract value after colon
    local value="${line#*:}"
    # Trim whitespace
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    # Remove quotes and comma
    value="${value#\"}"
    value="${value%\",*}"
    value="${value%\"}"
    value="${value%,}"

    if [[ -z "$value" || "$value" == "null" ]]; then
        return 1
    fi
    echo "$value"
}

parse_models() {
    local json="$1"

    # Check if models is null or missing
    if [[ "$json" == *"null"* ]] || ! echo "$json" | grep -q "models"; then
        return 0
    fi

    # Find models block and extract key-value pairs using sed
    echo "$json" | sed -n '/"models": {/,/}/p' | while IFS= read -r line; do
        case "$line" in
            *\"haiku\"*)
                value=$(echo "$line" | sed 's/.*"haiku": *"\([^"]*\)".*/\1/')
                [[ -n "$value" ]] && echo "haiku:$value"
                ;;
            *\"sonnet\"*)
                value=$(echo "$line" | sed 's/.*"sonnet": *"\([^"]*\)".*/\1/')
                [[ -n "$value" ]] && echo "sonnet:$value"
                ;;
            *\"opus\"*)
                value=$(echo "$line" | sed 's/.*"opus": *"\([^"]*\)".*/\1/')
                [[ -n "$value" ]] && echo "opus:$value"
                ;;
            *\"default\"*)
                value=$(echo "$line" | sed 's/.*"default": *"\([^"]*\)".*/\1/')
                [[ -n "$value" ]] && echo "default:$value"
                ;;
        esac
    done
}

list_providers() {
    local json
    json=$(fetch_providers) || return 1

    echo -e "${BLUE}Available Providers:${NC}"
    echo ""

    # Extract provider keys from "providers": { ... }
    # Only match lines with exactly 4 spaces of indentation (top level in providers)
    local providers=()

    while IFS= read -r line; do
        # Match lines like:     "zai": {
        # (exactly 4 spaces, then "name":)
        if [[ "$line" =~ ^[[:space:]]{4}\"([a-z]+)\"[[:space:]]*:[[:space:]]*\{ ]]; then
            providers+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$json"

    for provider in "${providers[@]}"; do
        local config
        config=$(get_provider_config "$provider" <<< "$json") || continue

        local name base_url
        name=$(parse_json_value "$config" "name") || name="$provider"
        base_url=$(parse_json_value "$config" "base_url") || true

        printf "  ${GREEN}%-12s${NC} %s\n" "$provider" "$name"
        if [[ -n "$base_url" ]]; then
            echo "               URL: $base_url"
        fi

        local models
        models=$(parse_models "$config")
        if [[ -n "$models" ]]; then
            echo -n "               Models: "
            echo "$models" | tr '\n' ' ' | sed 's/:/=/g; s/ $//'
            echo ""
        fi
        echo ""
    done
}

############################################################
# Settings Functions
############################################################

read_settings() {
    local path="$1"
    if [[ -f "$path" ]]; then
        cat "$path"
    else
        echo "{}"
    fi
}

get_env_value() {
    local settings="$1"
    local key="$2"

    echo "$settings" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | cut -d'"' -f4
}

# Extract all non-ccs keys from env block
get_other_env_keys() {
    local settings="$1"
    local in_env=false

    while IFS= read -r line; do
        if [[ "$line" == *'"env"'*:*'{'* ]]; then
            in_env=true
            continue
        fi
        if $in_env; then
            if [[ "$line" == *'}'* ]] && [[ "$line" != *':'* ]]; then
                break
            fi
            # Check if this is a ccs key
            local is_ccs=false
            for key in "${CCS_KEYS[@]}"; do
                if [[ "$line" == *'"'$key'"'* ]]; then
                    is_ccs=true
                    break
                fi
            done
            if ! $is_ccs && [[ "$line" =~ \"([A-Za-z_][A-Za-z0-9_]*)\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                echo "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
            fi
        fi
    done <<< "$settings"
}

# Get all keys outside of env block (preserving structure)
get_non_env_content() {
    local settings="$1"
    local in_env=false
    local depth=0
    local result=""

    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        if [[ "$line" == *'"env"'*:*'{'* ]]; then
            in_env=true
            depth=1
            continue
        fi
        if $in_env; then
            if [[ "$line" == *'{'* ]]; then
                ((depth++)) || true
            fi
            if [[ "$line" == *'}'* ]]; then
                ((depth--)) || true
                if (( depth <= 0 )); then
                    in_env=false
                fi
            fi
            continue
        fi

        # Clean the line
        local cleaned="${line#"${line%%[![:space:]]*}"}"
        cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"

        # Skip braces and empty
        [[ "$cleaned" == "{" ]] && continue
        [[ "$cleaned" == "}" ]] && continue
        [[ "$cleaned" == "{}" ]] && continue
        [[ -z "$cleaned" ]] && continue

        result+="$cleaned"$'\n'
    done <<< "$settings"

    echo "$result"
}

# Rebuild settings file with new env values
rebuild_settings() {
    local settings="$1"
    shift
    local new_env_pairs=("$@")

    # Get existing non-ccs env pairs
    local other_env=()
    while IFS=: read -r key value; do
        [[ -n "$key" ]] && other_env+=("$key:$value")
    done <<< "$(get_other_env_keys "$settings")"

    # Get non-env content
    local non_env
    non_env=$(get_non_env_content "$settings")

    # Build new JSON
    local result="{\n"

    # Build env block
    result+="  \"env\": {\n"

    local all_env=()
    # Add other env pairs first
    for pair in "${other_env[@]}"; do
        all_env+=("$pair")
    done
    # Add new env pairs
    for pair in "${new_env_pairs[@]}"; do
        all_env+=("$pair")
    done

    local total=${#all_env[@]}
    local count=0
    for pair in "${all_env[@]}"; do
        ((count++))
        local key="${pair%%:*}"
        local value="${pair#*:}"
        local escaped
        escaped=$(json_escape "$value")
        if (( count < total )); then
            result+="    \"$key\": \"$escaped\",\n"
        else
            result+="    \"$key\": \"$escaped\"\n"
        fi
    done

    result+="  }"

    # Add non-env content if exists
    if [[ -n "$non_env" ]]; then
        result+=",\n"
        # Add each line with proper formatting
        while IFS= read -r line; do
            result+="$line\n"
        done <<< "$non_env"
    else
        result+="\n"
    fi

    result+="}"

    echo -e "$result"
}

write_settings() {
    local path="$1"
    local content="$2"

    mkdir -p "$(dirname "$path")"
    echo "$content" > "$path"
    chmod 600 "$path"
}

############################################################
# Provider Switch Functions
############################################################

apply_provider() {
    local provider="$1"
    local scope="$2"  # "global" or "project"
    local output_path="${3:-}"  # Optional output path

    # Skip API key check for anthropic
    if [[ "$provider" == "anthropic" ]]; then
        # Just remove all ccs keys - no API key needed
        provider="anthropic"
    fi

    local settings_path
    if [[ -n "$output_path" ]]; then
        settings_path="$output_path"
    elif [[ "$scope" == "global" ]]; then
        settings_path="$USER_SETTINGS"
    else
        settings_path="$PROJECT_SETTINGS"
    fi

    local config_json
    config_json=$(get_provider_config "$provider") || return 1

    local settings
    settings=$(read_settings "$settings_path")

    # Build new env pairs for this provider
    local new_env_pairs=()

    # Get provider config values
    local base_url
    base_url=$(parse_json_value "$config_json" "base_url") || true

    # Add base_url if present
    if [[ -n "$base_url" ]]; then
        new_env_pairs+=("ANTHROPIC_BASE_URL:$base_url")
    fi

    # Handle auth token - check existing settings, then prompt
    local token=""
    # Check if there's a token in existing settings
    token=$(get_env_value "$settings" "ANTHROPIC_AUTH_TOKEN") || true
    if [[ -z "$token" ]]; then
        # Prompt user for API key
        echo -e "${YELLOW}Enter your API Token:${NC}"
        read -rsp "> " token
        echo ""
    fi
    if [[ -n "$token" ]]; then
        new_env_pairs+=("ANTHROPIC_AUTH_TOKEN:$token")
    fi

    # Add models
    local models
    models=$(parse_models "$config_json")

    if [[ -n "$models" ]]; then
        while IFS=: read -r model_type model_value; do
            [[ -z "$model_type" ]] && continue

            case "$model_type" in
                haiku)
                    new_env_pairs+=("ANTHROPIC_DEFAULT_HAIKU_MODEL:$model_value")
                    ;;
                sonnet)
                    new_env_pairs+=("ANTHROPIC_DEFAULT_SONNET_MODEL:$model_value")
                    ;;
                opus)
                    new_env_pairs+=("ANTHROPIC_DEFAULT_OPUS_MODEL:$model_value")
                    ;;
                default)
                    new_env_pairs+=("ANTHROPIC_MODEL:$model_value")
                    ;;
            esac
        done <<< "$models"
    fi

    # Rebuild settings with new env pairs
    local new_settings
    new_settings=$(rebuild_settings "$settings" "${new_env_pairs[@]}")

    write_settings "$settings_path" "$new_settings"

    log_info "Switched to ${GREEN}$provider${NC} ($scope)"
    log_info "Settings: $settings_path"
}

############################################################
# Status Functions
############################################################

show_status() {
    local scope="$1"  # "global", "project", or "all"
    local shown=false

    if [[ "$scope" == "global" || "$scope" == "all" ]]; then
        if [[ -f "$USER_SETTINGS" ]]; then
            local settings
            settings=$(cat "$USER_SETTINGS")

            local base_url model token
            base_url=$(get_env_value "$settings" "ANTHROPIC_BASE_URL") || true
            model=$(get_env_value "$settings" "ANTHROPIC_MODEL") || true
            token=$(get_env_value "$settings" "ANTHROPIC_AUTH_TOKEN") || true

            if [[ -n "$base_url" || -n "$model" || -n "$token" ]]; then
                echo -e "${GREEN}Global:${NC} $USER_SETTINGS"
                [[ -n "$base_url" ]] && echo "   BASE_URL: $base_url"
                [[ -n "$model" ]] && echo "   MODEL: $model"
                local haiku sonnet opus
                haiku=$(get_env_value "$settings" "ANTHROPIC_DEFAULT_HAIKU_MODEL") || true
                sonnet=$(get_env_value "$settings" "ANTHROPIC_DEFAULT_SONNET_MODEL") || true
                opus=$(get_env_value "$settings" "ANTHROPIC_DEFAULT_OPUS_MODEL") || true
                [[ -n "$haiku" ]] && echo "   HAIKU: $haiku"
                [[ -n "$sonnet" ]] && echo "   SONNET: $sonnet"
                [[ -n "$opus" ]] && echo "   OPUS: $opus"
                echo "   AUTH_TOKEN: $(mask_token "$token")"
                shown=true
            fi
        fi
    fi

    if [[ "$scope" == "project" || "$scope" == "all" ]]; then
        if [[ -f "$PROJECT_SETTINGS" ]]; then
            local settings
            settings=$(cat "$PROJECT_SETTINGS")

            local base_url model token
            base_url=$(get_env_value "$settings" "ANTHROPIC_BASE_URL") || true
            model=$(get_env_value "$settings" "ANTHROPIC_MODEL") || true
            token=$(get_env_value "$settings" "ANTHROPIC_AUTH_TOKEN") || true

            if [[ -n "$base_url" || -n "$model" || -n "$token" ]]; then
                [[ "$shown" == true ]] && echo ""
                echo -e "${BLUE}Project:${NC} $PROJECT_SETTINGS"
                [[ -n "$base_url" ]] && echo "   BASE_URL: $base_url"
                [[ -n "$model" ]] && echo "   MODEL: $model"
                local haiku sonnet opus
                haiku=$(get_env_value "$settings" "ANTHROPIC_DEFAULT_HAIKU_MODEL") || true
                sonnet=$(get_env_value "$settings" "ANTHROPIC_DEFAULT_SONNET_MODEL") || true
                opus=$(get_env_value "$settings" "ANTHROPIC_DEFAULT_OPUS_MODEL") || true
                [[ -n "$haiku" ]] && echo "   HAIKU: $haiku"
                [[ -n "$sonnet" ]] && echo "   SONNET: $sonnet"
                [[ -n "$opus" ]] && echo "   OPUS: $opus"
                echo "   AUTH_TOKEN: $(mask_token "$token")"
                shown=true
            fi
        fi
    fi

    if [[ "$shown" == false ]]; then
        echo -e "${YELLOW}No ccswicher configuration found${NC}"
        echo ""
        echo "Set up API keys in your shell:"
        echo '  export ZAI_API_KEY="your-key"'
        echo '  export MINIMAX_API_KEY="your-key"'
        echo ""
        echo "Then switch to a provider:"
        echo "  ccswicher -g -p zai      # Global"
        echo "  ccswicher -p minimax     # Project"
    fi
}

############################################################
# Upgrade Function
############################################################

upgrade_self() {
    log_info "Upgrading ccswicher..."

    local tmp_script
    tmp_script=$(mktemp)

    if command -v curl &>/dev/null; then
        curl -fsSL "${REPO_RAW}/ccswicher.sh" -o "$tmp_script"
    elif command -v wget &>/dev/null; then
        wget -qO "$tmp_script" "${REPO_RAW}/ccswicher.sh"
    else
        log_error "Need curl or wget"
        return 1
    fi

    # Find where we're installed
    local script_path
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ccswicher.sh"

    if [[ ! -w "$script_path" ]]; then
        log_warn "Need sudo to write to $script_path"
        sudo cp "$tmp_script" "$script_path"
    else
        cp "$tmp_script" "$script_path"
    fi

    chmod +x "$script_path"
    rm -f "$tmp_script"

    # Also update providers cache
    rm -f "$CACHE_FILE"

    log_info "Upgrade complete!"
}

############################################################
# Help
############################################################

show_help() {
    echo -e "${BLUE}CC-Switcher v${VERSION}${NC}"
    echo ""
    echo "Switch between AI providers for Claude Code"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  ccswicher -g -p <provider>    Set global provider"
    echo "  ccswicher -p <provider>       Set project provider"
    echo "  ccswicher -g -p <provider> -o <file>  Write to specific file"
    echo "  ccswicher -g status           Show global status"
    echo "  ccswicher status              Show project status"
    echo ""
    echo -e "${YELLOW}Commands:${NC}"
    echo "  status        Show current configuration"
    echo "  list          List available providers"
    echo "  upgrade       Update to latest version"
    echo "  help          Show this help"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  -g, --global   Apply to user-level settings"
    echo "  -p, --provider Set provider (zai, minimax, anthropic, lmstudio)"
    echo "  -o, --output   Write settings to specific file"
    echo ""
    echo -e "${YELLOW}Providers:${NC}"
    echo "  zai           Z.AI (uses ZAI_API_KEY)"
    echo "  minimax       MiniMax (uses MINIMAX_API_KEY)"
    echo "  anthropic     Claude Code official (removes custom config)"
    echo "  lmstudio      LM Studio local (uses LMSTUDIO_API_TOKEN)"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  ccswicher -g -p zai          # Use Z.AI globally"
    echo "  ccswicher -p minimax         # Use MiniMax for this project"
    echo "  ccswicher -g -p zai -o /tmp/test.json  # Write to test file"
    echo "  ccswicher -g -p anthropic    # Reset to Claude Code official"
    echo "  ccswicher status             # Show current config"
}

############################################################
# Main
############################################################

main() {
    local scope="project"
    local provider=""
    local command=""
    local output_path=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -g|--global)
                scope="global"
                shift
                ;;
            -p|--provider)
                shift
                provider="${1:-}"
                shift
                ;;
            -o|--output)
                shift
                output_path="${1:-}"
                shift
                ;;
            status|list|upgrade|help|-h|--help)
                command="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Handle -p flag (set provider)
    if [[ -n "$provider" ]]; then
        # Determine output path
        if [[ -z "$output_path" ]]; then
            if [[ "$scope" == "global" ]]; then
                output_path="$USER_SETTINGS"
            else
                output_path="$PROJECT_SETTINGS"
            fi
        fi
        apply_provider "$provider" "$scope" "$output_path"
        exit $?
    fi

    # Handle commands
    case "${command:-}" in
        status)
            if [[ "$scope" == "global" ]]; then
                show_status "global"
            else
                show_status "all"
            fi
            ;;
        list)
            list_providers
            ;;
        upgrade)
            upgrade_self
            ;;
        help|-h|--help|"")
            show_help
            ;;
    esac
}

main "$@"
