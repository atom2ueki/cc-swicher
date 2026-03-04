#!/usr/bin/env bash
############################################################
# CC-Switcher - Claude Code Model Switcher
# Version: 1.0.0
#
# Usage:
#   ccswitcher -g -p <provider>    # Set global provider
#   ccswitcher -p <provider>       # Set project provider
#   ccswitcher -g status           # Show global status
#   ccswitcher status              # Show project status
#   ccswitcher list                # List available providers
#   ccswitcher upgrade             # Upgrade to latest version
############################################################

set -euo pipefail

# Constants
# Version - update this when creating a new release tag
VERSION="1.0.10"
REPO_API="https://api.github.com/repos/atom2ueki/cc-switcher"

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

# Keys managed by ccswitcher (to be removed when switching to anthropic)
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
    # Use local providers.json from script directory (bundled with version)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    local local_config="$script_dir/providers.json"

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
    local env_depth=0
    local doc_depth=0
    local result=""

    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Count braces on this line for document depth tracking
        local opens="${line//[^\{]/}"
        local closes="${line//[^\}]/}"
        local prev_depth=$doc_depth
        (( doc_depth += ${#opens} - ${#closes} )) || true

        if [[ "$line" == *'"env"'*:*'{'* ]]; then
            env_depth=${#opens}
            (( env_depth -= ${#closes} )) || true
            if (( env_depth > 0 )); then
                in_env=true
            fi
            continue
        fi
        if $in_env; then
            (( env_depth += ${#opens} - ${#closes} )) || true
            if (( env_depth <= 0 )); then
                in_env=false
            fi
            continue
        fi

        # Trim the line for checking
        local cleaned="${line#"${line%%[![:space:]]*}"}"
        cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"
        [[ -z "$cleaned" ]] && continue

        # Skip only the outer document braces
        if [[ "$cleaned" == "{" ]] && (( prev_depth == 0 )); then
            continue
        fi
        if [[ "$cleaned" == "}" ]] && (( doc_depth == 0 )); then
            continue
        fi

        result+="$line"$'\n'
    done <<< "$settings"

    echo "$result"
}

# Rebuild settings file with new env values
rebuild_settings() {
    local settings="$1"
    shift

    # Get existing non-ccs env pairs
    local other_env
    other_env=$(get_other_env_keys "$settings")

    # Get non-env content
    local non_env
    non_env=$(get_non_env_content "$settings")

    # Build new JSON
    local result="{\n"

    # Build env block
    result+="  \"env\": {\n"

    # Collect all env pairs (other_env + new env pairs from "$@")
    local all_env=""
    # Add other env pairs first
    if [[ -n "$other_env" ]]; then
        all_env="$other_env"
    fi
    # Add new env pairs
    while [[ $# -gt 0 ]]; do
        if [[ -n "$1" ]]; then
            if [[ -n "$all_env" ]]; then
                all_env+=$'\n'"$1"
            else
                all_env="$1"
            fi
        fi
        shift
    done

    local count=0
    local total=0
    while IFS=: read -r pair; do
        [[ -n "$pair" ]] && ((total++)) || true
    done <<< "$all_env"

    while IFS=: read -r pair; do
        [[ -n "$pair" ]] || continue
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
    done <<< "$all_env"

    result+="  }"

    # Add non-env content if exists
    if [[ -n "$non_env" ]]; then
        # Strip trailing comma from last line (in case env was last in original)
        non_env=$(echo "$non_env" | sed '$ s/,[[:space:]]*$//')
        result+=",\n"
        # Add each line preserving original content
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
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
        echo -e "${YELLOW}No ccswitcher configuration found${NC}"
        echo ""
        echo "Switch to a provider:"
        echo "  ccswitcher -g -p zai      # Global"
        echo "  ccswitcher -p minimax     # Project"
    fi
}

############################################################
# Upgrade Function
############################################################

upgrade_self() {
    log_info "Upgrading ccswitcher..."

    # Fetch all tags and find the latest semantic version
    local tags_json remote_version
    if command -v curl &>/dev/null; then
        tags_json=$(curl -fsSL "${REPO_API}/tags" 2>/dev/null)
        remote_version=$(echo "$tags_json" | grep -o '"name": "[^"]*"' | sed 's/"name": "//;s/"//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    elif command -v wget &>/dev/null; then
        tags_json=$(wget -qO- "${REPO_API}/tags" 2>/dev/null)
        remote_version=$(echo "$tags_json" | grep -o '"name": "[^"]*"' | sed 's/"name": "//;s/"//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    else
        log_error "Need curl or wget"
        return 1
    fi

    if [[ -z "$remote_version" ]]; then
        log_error "Could not fetch remote version tags"
        return 1
    fi

    # Compare versions (simple string comparison works for semantic versioning)
    if [[ "$remote_version" == "$VERSION" ]]; then
        log_info "Already at latest version ($VERSION)"
        return 0
    fi

    if [[ "$remote_version" < "$VERSION" ]]; then
        log_warn "Remote version ($remote_version) is older than local ($VERSION)"
    else
        log_info "Upgrading from $VERSION to $remote_version"
    fi

    local tmp_script
    tmp_script=$(mktemp)

    # Download from the specific tag
    local tag_url="https://raw.githubusercontent.com/atom2ueki/cc-switcher/${remote_version}/ccswitcher.sh"
    if command -v curl &>/dev/null; then
        curl -fsSL "$tag_url" -o "$tmp_script"
    elif command -v wget &>/dev/null; then
        wget -qO "$tmp_script" "$tag_url"
    else
        log_error "Need curl or wget"
        rm -f "$tmp_script"
        return 1
    fi

    # Find where we're installed
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local script_path="$script_dir/ccswitcher.sh"

    if [[ ! -w "$script_path" ]]; then
        log_warn "Need sudo to write to $script_path"
        sudo cp "$tmp_script" "$script_path"
    else
        cp "$tmp_script" "$script_path"
    fi

    chmod +x "$script_path"
    rm -f "$tmp_script"

    # Also download providers.json
    local providers_url="https://raw.githubusercontent.com/atom2ueki/cc-switcher/${remote_version}/providers.json"
    local tmp_providers
    tmp_providers=$(mktemp)
    local providers_ok=false
    if command -v curl &>/dev/null; then
        curl -fsSL "$providers_url" -o "$tmp_providers" 2>/dev/null && providers_ok=true
    elif command -v wget &>/dev/null; then
        wget -qO "$tmp_providers" "$providers_url" 2>/dev/null && providers_ok=true
    fi

    if $providers_ok && [[ -s "$tmp_providers" ]]; then
        local providers_path="$script_dir/providers.json"
        if [[ ! -w "$script_dir" ]]; then
            sudo cp "$tmp_providers" "$providers_path"
        else
            cp "$tmp_providers" "$providers_path"
        fi
    else
        log_warn "Could not download providers.json"
    fi
    rm -f "$tmp_providers"

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
    echo "  ccswitcher -g -p <provider>    Set global provider"
    echo "  ccswitcher -p <provider>       Set project provider"
    echo "  ccswitcher -g -p <provider> -o <file>  Write to specific file"
    echo "  ccswitcher -g status           Show global status"
    echo "  ccswitcher status              Show project status"
    echo ""
    echo -e "${YELLOW}Commands:${NC}"
    echo "  status        Show current configuration"
    echo "  list          List available providers"
    echo "  version       Show version"
    echo "  upgrade       Update to latest version"
    echo "  help          Show this help"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  -g, --global   Apply to user-level settings"
    echo "  -p, --provider Set provider (zai, minimax, anthropic, lmstudio)"
    echo "  -o, --output   Write settings to specific file"
    echo ""
    echo -e "${YELLOW}Providers:${NC}"
    echo "  zai           Z.AI"
    echo "  minimax       MiniMax"
    echo "  anthropic     Claude Code"
    echo "  lmstudio      LM Studio"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  ccswitcher -g -p zai          # Use Z.AI globally"
    echo "  ccswitcher -p minimax         # Use MiniMax for this project"
    echo "  ccswitcher -g -p zai -o /tmp/test.json  # Write to test file"
    echo "  ccswitcher -g -p anthropic    # Reset to Claude Code official"
    echo "  ccswitcher status             # Show current config"
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
            status|list|upgrade|version|-v|--version|help|-h|--help)
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
        version|-v|--version)
            echo "CC-Switcher v${VERSION}"
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
