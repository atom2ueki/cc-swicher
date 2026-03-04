#!/bin/bash
# Test cases for ccswitcher settings management functions
# Run: ./tests/test_settings.sh
#
# This test file contains copies of the functions being tested to allow
# isolated testing without running the main ccswitcher.sh script.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temporary directory for test files
TEST_DIR=""

# ============================================
# Functions under test (copied from ccswitcher.sh)
# ============================================

# Shared helper: Escape string for JSON (handles quotes, backslashes, newlines)
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"      # Escape backslashes first
    str="${str//\"/\\\"}"      # Escape quotes
    str="${str//$'\n'/\\n}"    # Escape newlines
    str="${str//$'\r'/\\r}"    # Escape carriage returns
    str="${str//$'\t'/\\t}"    # Escape tabs
    printf '%s' "$str"
}

# Shared helper: Backup settings file
backup_settings() {
    local path="$1"
    local ts
    ts="$(date "+%Y%m%d-%H%M%S")"
    cp -f "$path" "${path}.bak.${ts}"
}

# ccswitcher-managed env keys
CCSWICHER_ENV_KEYS=(
    "ANTHROPIC_BASE_URL"
    "ANTHROPIC_MODEL"
    "ANTHROPIC_DEFAULT_SONNET_MODEL"
    "ANTHROPIC_DEFAULT_OPUS_MODEL"
    "ANTHROPIC_DEFAULT_HAIKU_MODEL"
    "CLAUDE_CODE_SUBAGENT_MODEL"
    "ANTHROPIC_AUTH_TOKEN"
)

# Check if key is ccswitcher-managed
is_ccswitcher_env_key() {
    local key="$1"
    for ccswitcher_key in "${CCSWICHER_ENV_KEYS[@]}"; do
        [[ "$key" == "$ccswitcher_key" ]] && return 0
    done
    return 1
}

# Shared helper: Write ccswitcher settings file (pure bash, no dependencies)
write_ccswitcher_settings() {
    local settings_path="$1"
    local provider="$2"
    local base_url="$3"
    local model="$4"
    local token="$5"

    local escaped_base escaped_model escaped_token
    escaped_base=$(json_escape "$base_url")
    escaped_model=$(json_escape "$model")

    # Extract existing non-ccswitcher env keys and non-env content from file if it exists
    local existing_env_pairs=""
    local other_content=""
    if [[ -f "$settings_path" ]]; then
        local in_env=0
        local env_depth=0
        local doc_depth=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" ]] && continue

            # Count braces for depth tracking
            local opens="${line//[^\{]/}"
            local closes="${line//[^\}]/}"
            local prev_depth=$doc_depth
            (( doc_depth += ${#opens} - ${#closes} )) || true

            if [[ "$line" =~ \"env\"[[:space:]]*:[[:space:]]*\{ ]]; then
                env_depth=${#opens}
                (( env_depth -= ${#closes} )) || true
                if (( env_depth > 0 )); then
                    in_env=1
                fi
                # env self-contained on one line (e.g. "env": {})
                continue
            fi
            if [[ $in_env -eq 1 ]]; then
                (( env_depth += ${#opens} - ${#closes} )) || true
                if (( env_depth <= 0 )); then
                    in_env=0
                    continue
                fi
                # Skip ccswitcher keys but keep others
                if [[ "$line" =~ \"ANTHROPIC_BASE_URL\" || "$line" =~ \"ANTHROPIC_MODEL\" || \
                      "$line" =~ \"ANTHROPIC_DEFAULT_ || "$line" =~ \"CLAUDE_CODE_SUBAGENT_MODEL\" || \
                      "$line" =~ \"ANTHROPIC_AUTH_TOKEN\" ]]; then
                    continue
                fi
                local trimmed="${line#"${line%%[![:space:]]*}"}"
                trimmed="${trimmed%,}"
                if [[ -n "$trimmed" && "$trimmed" =~ \" ]]; then
                    existing_env_pairs="${existing_env_pairs}${trimmed}"$'\n'
                fi
                continue
            fi

            # Skip only outer document braces
            local cleaned="${line#"${line%%[![:space:]]*}"}"
            cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"
            [[ -z "$cleaned" ]] && continue
            if [[ "$cleaned" == "{" ]] && (( prev_depth == 0 )); then
                continue
            fi
            if [[ "$cleaned" == "}" ]] && (( doc_depth == 0 )); then
                continue
            fi

            other_content+="$line"$'\n'
        done < "$settings_path"
    fi

    # Build new JSON file
    {
        echo "{"
        echo "  \"env\": {"

        # Add existing non-ccswitcher env pairs first (with commas)
        if [[ -n "$existing_env_pairs" ]]; then
            while IFS= read -r pair; do
                if [[ -n "$pair" ]]; then
                    echo "    ${pair},"
                fi
            done <<< "$existing_env_pairs"
        fi

        # Add ccswitcher env keys
        echo "    \"ANTHROPIC_BASE_URL\": \"${escaped_base}\","
        echo "    \"ANTHROPIC_MODEL\": \"${escaped_model}\","
        echo "    \"ANTHROPIC_DEFAULT_SONNET_MODEL\": \"${escaped_model}\","
        echo "    \"ANTHROPIC_DEFAULT_OPUS_MODEL\": \"${escaped_model}\","
        echo "    \"ANTHROPIC_DEFAULT_HAIKU_MODEL\": \"${escaped_model}\","
        if [[ -n "$token" ]]; then
            escaped_token=$(json_escape "$token")
            echo "    \"CLAUDE_CODE_SUBAGENT_MODEL\": \"${escaped_model}\","
            echo "    \"ANTHROPIC_AUTH_TOKEN\": \"${escaped_token}\""
        else
            echo "    \"CLAUDE_CODE_SUBAGENT_MODEL\": \"${escaped_model}\""
        fi

        if [[ -n "$other_content" ]]; then
            echo "  },"
            # Strip leading/trailing standalone commas and trailing comma from last line
            other_content=$(echo "$other_content" | sed '/^[[:space:]]*,[[:space:]]*$/d' | sed '$ s/,[[:space:]]*$//')
            while IFS= read -r line; do
                [[ -n "$line" ]] && echo "$line"
            done <<< "$other_content"
        else
            echo "  }"
        fi

        echo "}"
    } > "$settings_path"

    chmod 600 "$settings_path"
}

# Shared helper: Remove ccswitcher-managed keys from settings, preserve others (pure bash)
remove_ccswitcher_settings() {
    local settings_path="$1"

    # Extract non-ccswitcher env keys and other non-env content
    local env_pairs=()
    local other_content=""
    local in_env=0
    local env_depth=0
    local doc_depth=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue

        # Count braces for depth tracking
        local opens="${line//[^\{]/}"
        local closes="${line//[^\}]/}"
        local prev_depth=$doc_depth
        (( doc_depth += ${#opens} - ${#closes} )) || true

        if [[ "$line" =~ \"env\"[[:space:]]*:[[:space:]]*\{ ]]; then
            env_depth=${#opens}
            (( env_depth -= ${#closes} )) || true
            if (( env_depth > 0 )); then
                in_env=1
            fi
            continue
        fi
        if [[ $in_env -eq 1 ]]; then
            (( env_depth += ${#opens} - ${#closes} )) || true
            if (( env_depth <= 0 )); then
                in_env=0
                continue
            fi
            # Skip ccswitcher-managed keys
            [[ "$line" =~ \"ANTHROPIC_BASE_URL\" || "$line" =~ \"ANTHROPIC_MODEL\" ]] && continue
            [[ "$line" =~ \"ANTHROPIC_DEFAULT_ || "$line" =~ \"CLAUDE_CODE_SUBAGENT_MODEL\" ]] && continue
            [[ "$line" =~ \"ANTHROPIC_AUTH_TOKEN\" ]] && continue
            # Keep non-ccswitcher key
            local trimmed="${line%,}"
            trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
            [[ -n "$trimmed" && "$trimmed" =~ \" ]] && env_pairs+=("$trimmed")
            continue
        fi

        # Skip only outer document braces
        local cleaned="${line#"${line%%[![:space:]]*}"}"
        cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"
        [[ -z "$cleaned" ]] && continue
        if [[ "$cleaned" == "{" ]] && (( prev_depth == 0 )); then
            continue
        fi
        if [[ "$cleaned" == "}" ]] && (( doc_depth == 0 )); then
            continue
        fi

        other_content+="$line"$'\n'
    done < "$settings_path"

    # If nothing left, remove the file
    if [[ ${#env_pairs[@]} -eq 0 && -z "$other_content" ]]; then
        rm -f "$settings_path"
        echo "removed"
        return
    fi

    # Rebuild JSON
    {
        echo "{"

        # Add non-env content as raw block
        if [[ -n "$other_content" ]]; then
            # Strip standalone comma lines and trailing comma from last line
            other_content=$(echo "$other_content" | sed '/^[[:space:]]*,[[:space:]]*$/d' | sed '$ s/,[[:space:]]*$//')
            if [[ ${#env_pairs[@]} -gt 0 ]]; then
                # More content coming, emit lines then a comma separator
                while IFS= read -r line; do
                    [[ -n "$line" ]] && echo "$line"
                done <<< "$other_content"
                echo ","
            else
                while IFS= read -r line; do
                    [[ -n "$line" ]] && echo "$line"
                done <<< "$other_content"
            fi
        fi

        # Add env block if there are env keys
        if [[ ${#env_pairs[@]} -gt 0 ]]; then
            echo "  \"env\": {"
            local env_count=0
            for pair in "${env_pairs[@]}"; do
                ((env_count++))
                if [[ $env_count -lt ${#env_pairs[@]} ]]; then
                    echo "    ${pair},"
                else
                    echo "    ${pair}"
                fi
            done
            echo "  }"
        fi

        echo "}"
    } > "$settings_path"

    echo "preserved"
}

# ============================================
# Test helper functions
# ============================================

setup() {
    TEST_DIR=$(mktemp -d)
}

teardown() {
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    ((TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}PASS:${NC} $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        echo -e "  Expected: $expected"
        echo -e "  Actual:   $actual"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    ((TESTS_RUN++))

    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}PASS:${NC} $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        echo -e "  Expected to contain: $needle"
        echo -e "  Actual: $haystack"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    ((TESTS_RUN++))

    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "${GREEN}PASS:${NC} $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        echo -e "  Expected NOT to contain: $needle"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_file_contains() {
    local file="$1"
    local needle="$2"
    local message="$3"

    ((TESTS_RUN++))

    if grep -q "$needle" "$file" 2>/dev/null; then
        echo -e "${GREEN}PASS:${NC} $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        echo -e "  Expected file to contain: $needle"
        echo -e "  File contents:"
        cat "$file" | head -20
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_file_not_contains() {
    local file="$1"
    local needle="$2"
    local message="$3"

    ((TESTS_RUN++))

    if ! grep -q "$needle" "$file" 2>/dev/null; then
        echo -e "${GREEN}PASS:${NC} $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL:${NC} $message"
        echo -e "  Expected file NOT to contain: $needle"
        echo -e "  File contents:"
        cat "$file" | head -20
        ((TESTS_FAILED++))
        return 1
    fi
}

# ============================================
# Test Cases
# ============================================

test_json_escape_simple() {
    echo -e "\n${YELLOW}=== Test: json_escape simple strings ===${NC}"

    local result
    result=$(json_escape "hello")
    assert_equals "hello" "$result" "Simple string unchanged"

    result=$(json_escape "hello world")
    assert_equals "hello world" "$result" "String with space unchanged"
}

test_json_escape_quotes() {
    echo -e "\n${YELLOW}=== Test: json_escape quotes ===${NC}"

    local result
    result=$(json_escape 'say "hello"')
    assert_equals 'say \"hello\"' "$result" "Escape double quotes"
}

test_json_escape_backslash() {
    echo -e "\n${YELLOW}=== Test: json_escape backslash ===${NC}"

    local result
    result=$(json_escape 'path\to\file')
    assert_equals 'path\\to\\file' "$result" "Escape backslashes"
}

test_json_escape_newline() {
    echo -e "\n${YELLOW}=== Test: json_escape newline ===${NC}"

    local result
    result=$(json_escape $'line1\nline2')
    assert_equals 'line1\nline2' "$result" "Escape newline"
}

test_json_escape_tab() {
    echo -e "\n${YELLOW}=== Test: json_escape tab ===${NC}"

    local result
    result=$(json_escape $'col1\tcol2')
    assert_equals 'col1\tcol2' "$result" "Escape tab"
}

test_json_escape_combined() {
    echo -e "\n${YELLOW}=== Test: json_escape combined ===${NC}"

    local result
    result=$(json_escape 'He said "path\to\file"')
    assert_equals 'He said \"path\\to\\file\"' "$result" "Escape quotes and backslashes"
}

test_write_ccswitcher_settings_new_file() {
    echo -e "\n${YELLOW}=== Test: write_ccswitcher_settings new file ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    write_ccswitcher_settings "$settings_file" "zai" "https://api.z.ai/api/anthropic" "glm-5" ""

    assert_file_contains "$settings_file" '"ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic"' "Contains base URL"
    assert_file_contains "$settings_file" '"ANTHROPIC_MODEL": "glm-5"' "Contains model"
    assert_file_not_contains "$settings_file" '"ANTHROPIC_AUTH_TOKEN"' "No token when empty"

    teardown
}

test_write_ccswitcher_settings_with_token() {
    echo -e "\n${YELLOW}=== Test: write_ccswitcher_settings with token ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    write_ccswitcher_settings "$settings_file" "minimax" "https://api.minimax.io/anthropic" "MiniMax-M2.5" "sk-test-token"

    assert_file_contains "$settings_file" '"ANTHROPIC_AUTH_TOKEN": "sk-test-token"' "Contains token"

    teardown
}

test_write_ccswitcher_settings_preserves_existing() {
    echo -e "\n${YELLOW}=== Test: write_ccswitcher_settings preserves existing keys ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create initial settings with custom keys
    cat > "$settings_file" << 'EOF'
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CUSTOM_API_KEY": "my-secret-key",
    "SOME_OTHER_SETTING": "value"
  },
  "otherKey": "preserved"
}
EOF

    write_ccswitcher_settings "$settings_file" "zai" "https://api.z.ai/api/anthropic" "glm-5" ""

    assert_file_contains "$settings_file" '"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"' "Preserved AGENT_TEAMS"
    assert_file_contains "$settings_file" '"CUSTOM_API_KEY": "my-secret-key"' "Preserved CUSTOM_API_KEY"
    assert_file_contains "$settings_file" '"SOME_OTHER_SETTING": "value"' "Preserved OTHER_SETTING"
    assert_file_contains "$settings_file" '"ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic"' "Added ccswitcher base URL"
    assert_file_contains "$settings_file" '"ANTHROPIC_MODEL": "glm-5"' "Added ccswitcher model"

    teardown
}

test_write_ccswitcher_settings_overwrites_old_ccswitcher_keys() {
    echo -e "\n${YELLOW}=== Test: write_ccswitcher_settings overwrites old ccswitcher keys ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create initial settings with old ccswitcher values
    cat > "$settings_file" << 'EOF'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://old-url.com",
    "ANTHROPIC_MODEL": "old-model",
    "CUSTOM_KEY": "keep-this"
  }
}
EOF

    write_ccswitcher_settings "$settings_file" "new-provider" "https://new-url.com" "new-model" ""

    assert_file_contains "$settings_file" '"ANTHROPIC_BASE_URL": "https://new-url.com"' "Updated base URL"
    assert_file_contains "$settings_file" '"ANTHROPIC_MODEL": "new-model"' "Updated model"
    assert_file_contains "$settings_file" '"CUSTOM_KEY": "keep-this"' "Preserved custom key"
    # Check old values are gone
    local content
    content=$(cat "$settings_file")
    assert_not_contains "$content" "old-url.com" "Removed old URL"

    teardown
}

test_write_ccswitcher_settings_special_chars() {
    echo -e "\n${YELLOW}=== Test: write_ccswitcher_settings with special characters ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Test with URL containing special chars and token with special chars
    write_ccswitcher_settings "$settings_file" "test" "https://api.example.com/path?query=1" 'model"name' 'token"with"quotes'

    assert_file_contains "$settings_file" 'https://api.example.com/path?query=1' "URL preserved"
    # Use literal search for escaped quotes (grep needs special handling)
    assert_file_contains "$settings_file" 'model\\"name' "Model name escaped"
    assert_file_contains "$settings_file" 'token\\"with\\"quotes' "Token escaped"
    teardown
}

test_remove_ccswitcher_settings_preserves_others() {
    echo -e "\n${YELLOW}=== Test: remove_ccswitcher_settings preserves non-ccswitcher keys ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create settings with ccswitcher and non-ccswitcher keys
    cat > "$settings_file" << 'EOF'
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
    "ANTHROPIC_MODEL": "glm-5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-5",
    "CLAUDE_CODE_SUBAGENT_MODEL": "glm-5",
    "ANTHROPIC_AUTH_TOKEN": "test-token",
    "CUSTOM_KEY": "preserve-this",
    "ANOTHER_KEY": "keep-this-too"
  },
  "someOtherTopLevel": "value"
}
EOF

    local result
    result=$(remove_ccswitcher_settings "$settings_file")

    assert_equals "preserved" "$result" "Returns 'preserved' when keys remain"
    assert_file_contains "$settings_file" '"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"' "Preserved AGENT_TEAMS"
    assert_file_contains "$settings_file" '"CUSTOM_KEY": "preserve-this"' "Preserved CUSTOM_KEY"
    assert_file_contains "$settings_file" '"ANOTHER_KEY": "keep-this-too"' "Preserved ANOTHER_KEY"
    assert_file_contains "$settings_file" '"someOtherTopLevel": "value"' "Preserved top-level key"

    # Check ccswitcher keys are removed
    local content
    content=$(cat "$settings_file")
    assert_not_contains "$content" "ANTHROPIC_BASE_URL" "Removed ANTHROPIC_BASE_URL"
    assert_not_contains "$content" "ANTHROPIC_MODEL" "Removed ANTHROPIC_MODEL"
    assert_not_contains "$content" "ANTHROPIC_AUTH_TOKEN" "Removed token"
    teardown
}

test_remove_ccswitcher_settings_removes_file_when_empty() {
    echo -e "\n${YELLOW}=== Test: remove_ccswitcher_settings removes file when empty ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create settings with only ccswitcher keys
    cat > "$settings_file" << 'EOF'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
    "ANTHROPIC_MODEL": "glm-5"
  }
}
EOF

    local result
    result=$(remove_ccswitcher_settings "$settings_file")

    assert_equals "removed" "$result" "Returns 'removed' when file is deleted"

    if [[ ! -f "$settings_file" ]]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS:${NC} File was deleted"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL:${NC} File should have been deleted"
        ((TESTS_FAILED++))
    fi
    teardown
}

test_remove_ccswitcher_settings_handles_nonexistent_file() {
    echo -e "\n${YELLOW}=== Test: remove_ccswitcher_settings handles nonexistent file ===${NC}"
    setup

    local settings_file="$TEST_DIR/nonexistent.json"

    # Should not error, just return
    if remove_ccswitcher_settings "$settings_file" 2>/dev/null; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS:${NC} Handles nonexistent file gracefully"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL:${NC} Should handle nonexistent file gracefully"
        ((TESTS_FAILED++))
    fi
    teardown
}

test_roundtrip_preserve_settings() {
    echo -e "\n${YELLOW}=== Test: Roundtrip - write then reset preserves original ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create original settings
    cat > "$settings_file" << 'EOF'
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "MY_CUSTOM_VAR": "custom-value"
  },
  "topLevelKey": "topLevelValue"
}
EOF

    # Write ccswitcher settings
    write_ccswitcher_settings "$settings_file" "zai" "https://api.z.ai/api/anthropic" "glm-5" "test-token"

    # Verify ccswitcher settings were added
    assert_file_contains "$settings_file" '"ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic"' "ccswitcher settings added"

    # Remove ccswitcher settings
    remove_ccswitcher_settings "$settings_file"

    # Verify original keys are preserved
    assert_file_contains "$settings_file" '"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"' "Original AGENT_TEAMS preserved"
    assert_file_contains "$settings_file" '"MY_CUSTOM_VAR": "custom-value"' "Original custom var preserved"
    assert_file_contains "$settings_file" '"topLevelKey": "topLevelValue"' "Original top-level preserved"
    teardown
}

test_write_ccswitcher_settings_empty_env() {
    echo -e "\n${YELLOW}=== Test: write_ccswitcher_settings with empty existing env ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create settings with empty env
    cat > "$settings_file" << 'EOF'
{
  "env": {},
  "otherKey": "value"
}
EOF

    write_ccswitcher_settings "$settings_file" "minimax" "https://api.minimax.io/anthropic" "MiniMax-M2.5" ""

    assert_file_contains "$settings_file" '"ANTHROPIC_MODEL": "MiniMax-M2.5"' "ccswitcher model added"
    assert_file_contains "$settings_file" '"otherKey": "value"' "Other key preserved"
    teardown
}

test_write_ccswitcher_settings_no_env_block() {
    echo -e "\n${YELLOW}=== Test: write_ccswitcher_settings with no existing env block ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create settings without env block
    cat > "$settings_file" << 'EOF'
{
  "someKey": "someValue"
}
EOF

    write_ccswitcher_settings "$settings_file" "minimax" "https://api.minimax.io/anthropic" "MiniMax-M2.5" ""

    assert_file_contains "$settings_file" '"ANTHROPIC_MODEL": "MiniMax-M2.5"' "ccswitcher model added"
    assert_file_contains "$settings_file" '"someKey": "someValue"' "Existing key preserved"
    teardown
}

test_write_ccswitcher_settings_with_permissions_block() {
    echo -e "\n${YELLOW}=== Test: write_ccswitcher_settings preserves permissions with nested arrays ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create settings matching real-world .claude/settings.local.json with permissions block
    cat > "$settings_file" << 'EOF'
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "allow": [
      "WebSearch",
      "WebFetch",
      "Bash(git:*)",
      "Bash(gh:*)",
      "Bash(npm:*)",
      "Bash(npx:*)",
      "mcp__plugin_github_github__*"
    ]
  }
}
EOF

    write_ccswitcher_settings "$settings_file" "zai" "https://api.z.ai/api/anthropic" "glm-5" ""

    # Verify provider settings were added
    assert_file_contains "$settings_file" '"ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic"' "Provider base URL added"
    assert_file_contains "$settings_file" '"ANTHROPIC_MODEL": "glm-5"' "Provider model added"

    # Verify existing env key preserved
    assert_file_contains "$settings_file" '"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"' "Existing env key preserved"

    # Verify permissions block is fully preserved
    assert_file_contains "$settings_file" '"permissions"' "permissions key preserved"
    assert_file_contains "$settings_file" '"allow"' "allow key preserved"
    assert_file_contains "$settings_file" '"WebSearch"' "WebSearch permission preserved"
    assert_file_contains "$settings_file" '"Bash(git:\*)"' "Bash permission preserved"
    assert_file_contains "$settings_file" '"mcp__plugin_github_github__\*"' "MCP permission preserved"

    # CRITICAL: Validate JSON structure - the closing braces must be correct
    if command -v python3 &>/dev/null; then
        ((TESTS_RUN++))
        if python3 -c "import json; json.load(open('$settings_file'))" 2>/dev/null; then
            echo -e "${GREEN}PASS:${NC} Output is valid JSON with permissions block"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL:${NC} Output is INVALID JSON - permissions block corrupted"
            echo -e "  File contents:"
            cat "$settings_file"
            ((TESTS_FAILED++))
        fi
    fi

    teardown
}

test_remove_ccswitcher_settings_with_permissions_block() {
    echo -e "\n${YELLOW}=== Test: remove_ccswitcher_settings preserves permissions with nested arrays ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create settings with both ccswitcher keys and permissions block
    cat > "$settings_file" << 'EOF'
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
    "ANTHROPIC_MODEL": "glm-5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-5",
    "CLAUDE_CODE_SUBAGENT_MODEL": "glm-5",
    "ANTHROPIC_AUTH_TOKEN": "test-token"
  },
  "permissions": {
    "allow": [
      "WebSearch",
      "WebFetch",
      "Bash(git:*)",
      "Bash(gh:*)",
      "Bash(npm:*)",
      "mcp__plugin_github_github__*"
    ]
  }
}
EOF

    local result
    result=$(remove_ccswitcher_settings "$settings_file")

    assert_equals "preserved" "$result" "Returns 'preserved' when permissions remain"

    # Verify ccswitcher keys are removed
    local content
    content=$(cat "$settings_file")
    assert_not_contains "$content" "ANTHROPIC_BASE_URL" "Removed ANTHROPIC_BASE_URL"
    assert_not_contains "$content" "ANTHROPIC_MODEL" "Removed ANTHROPIC_MODEL"

    # Verify env key preserved
    assert_file_contains "$settings_file" '"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"' "Env key preserved"

    # Verify permissions block is fully preserved
    assert_file_contains "$settings_file" '"permissions"' "permissions key preserved"
    assert_file_contains "$settings_file" '"allow"' "allow key preserved"
    assert_file_contains "$settings_file" '"WebSearch"' "WebSearch preserved"
    assert_file_contains "$settings_file" '"Bash(git:\*)"' "Bash permission preserved"

    # CRITICAL: Validate JSON structure
    if command -v python3 &>/dev/null; then
        ((TESTS_RUN++))
        if python3 -c "import json; json.load(open('$settings_file'))" 2>/dev/null; then
            echo -e "${GREEN}PASS:${NC} Output is valid JSON after removing ccswitcher keys"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL:${NC} Output is INVALID JSON - permissions block corrupted after removal"
            echo -e "  File contents:"
            cat "$settings_file"
            ((TESTS_FAILED++))
        fi
    fi

    teardown
}

test_roundtrip_with_permissions_block() {
    echo -e "\n${YELLOW}=== Test: Roundtrip with permissions block produces valid JSON ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create original settings matching real-world config
    cat > "$settings_file" << 'EOF'
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "allow": [
      "WebSearch",
      "WebFetch",
      "Bash(git:*)",
      "Bash(gh:*)",
      "Bash(npm:*)",
      "Bash(npx:*)",
      "Bash(pnpm:*)",
      "Bash(curl:*)",
      "Bash(cat:*)",
      "Bash(ls:*)",
      "Bash(tree:*)",
      "Bash(jq:*)",
      "Bash(chmod:*)",
      "Bash(python3:*)",
      "mcp__plugin_github_github__*",
      "mcp__plugin_supabase_supabase__*",
      "mcp__plugin_context7_context7__*"
    ]
  }
}
EOF

    # Write ccswitcher settings (switch to provider)
    write_ccswitcher_settings "$settings_file" "zai" "https://api.z.ai/api/anthropic" "glm-5" "test-token"

    # Validate JSON after write
    if command -v python3 &>/dev/null; then
        ((TESTS_RUN++))
        if python3 -c "import json; json.load(open('$settings_file'))" 2>/dev/null; then
            echo -e "${GREEN}PASS:${NC} Valid JSON after provider write"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL:${NC} Invalid JSON after provider write"
            echo -e "  File contents:"
            cat "$settings_file"
            ((TESTS_FAILED++))
        fi
    fi

    # Verify permissions still present after write
    assert_file_contains "$settings_file" '"permissions"' "permissions key present after write"
    assert_file_contains "$settings_file" '"allow"' "allow key present after write"
    assert_file_contains "$settings_file" '"WebSearch"' "WebSearch present after write"

    # Remove ccswitcher settings (switch to anthropic)
    remove_ccswitcher_settings "$settings_file"

    # Validate JSON after remove
    if command -v python3 &>/dev/null; then
        ((TESTS_RUN++))
        if python3 -c "import json; json.load(open('$settings_file'))" 2>/dev/null; then
            echo -e "${GREEN}PASS:${NC} Valid JSON after provider removal"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL:${NC} Invalid JSON after provider removal"
            echo -e "  File contents:"
            cat "$settings_file"
            ((TESTS_FAILED++))
        fi
    fi

    # Verify permissions still present after remove
    assert_file_contains "$settings_file" '"permissions"' "permissions key present after remove"
    assert_file_contains "$settings_file" '"WebSearch"' "WebSearch present after remove"

    # Verify env preserved
    assert_file_contains "$settings_file" '"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"' "Env key preserved through roundtrip"

    teardown
}

test_write_ccswitcher_settings_with_nested_objects() {
    echo -e "\n${YELLOW}=== Test: write_ccswitcher_settings preserves deeply nested objects ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create settings with multiple levels of nesting
    cat > "$settings_file" << 'EOF'
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "allow": [
      "WebSearch",
      "Bash(git:*)"
    ]
  },
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"]
    }
  }
}
EOF

    write_ccswitcher_settings "$settings_file" "zai" "https://api.z.ai/api/anthropic" "glm-5" ""

    # Verify provider settings added
    assert_file_contains "$settings_file" '"ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic"' "Provider added"

    # Verify all nested structures preserved
    assert_file_contains "$settings_file" '"permissions"' "permissions preserved"
    assert_file_contains "$settings_file" '"mcpServers"' "mcpServers preserved"
    assert_file_contains "$settings_file" '"github"' "github nested object preserved"
    assert_file_contains "$settings_file" '"command": "npx"' "command value preserved"

    # CRITICAL: Validate JSON
    if command -v python3 &>/dev/null; then
        ((TESTS_RUN++))
        if python3 -c "import json; json.load(open('$settings_file'))" 2>/dev/null; then
            echo -e "${GREEN}PASS:${NC} Valid JSON with nested objects"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL:${NC} Invalid JSON - nested objects corrupted"
            echo -e "  File contents:"
            cat "$settings_file"
            ((TESTS_FAILED++))
        fi
    fi

    teardown
}

test_valid_json_output() {
    echo -e "\n${YELLOW}=== Test: Valid JSON output ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Test write produces valid JSON
    write_ccswitcher_settings "$settings_file" "test" "https://api.test.com" "test-model" "test-token"

    # Use Python to validate JSON (if available)
    if command -v python3 &>/dev/null; then
        ((TESTS_RUN++))
        if python3 -c "import json; json.load(open('$settings_file'))" 2>/dev/null; then
            echo -e "${GREEN}PASS:${NC} write_ccswitcher_settings produces valid JSON"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL:${NC} write_ccswitcher_settings produces invalid JSON"
            cat "$settings_file"
            ((TESTS_FAILED++))
        fi
    else
        echo -e "${YELLOW}SKIP:${NC} Python not available for JSON validation"
    fi

    # Test with existing keys
    cat > "$settings_file" << 'EOF'
{
  "env": {
    "EXISTING_KEY": "value"
  }
}
EOF

    write_ccswitcher_settings "$settings_file" "test" "https://api.test.com" "test-model" ""

    if command -v python3 &>/dev/null; then
        ((TESTS_RUN++))
        if python3 -c "import json; json.load(open('$settings_file'))" 2>/dev/null; then
            echo -e "${GREEN}PASS:${NC} write_ccswitcher_settings with existing keys produces valid JSON"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL:${NC} write_ccswitcher_settings with existing keys produces invalid JSON"
            cat "$settings_file"
            ((TESTS_FAILED++))
        fi
    fi
    teardown
}

# ============================================
# Run all tests
# ============================================

main() {
    echo -e "${YELLOW}============================================${NC}"
    echo -e "${YELLOW}ccswitcher Settings Management Test Suite${NC}"
    echo -e "${YELLOW}============================================${NC}"

    # Run all tests
    test_json_escape_simple
    test_json_escape_quotes
    test_json_escape_backslash
    test_json_escape_newline
    test_json_escape_tab
    test_json_escape_combined

    test_write_ccswitcher_settings_new_file
    test_write_ccswitcher_settings_with_token
    test_write_ccswitcher_settings_preserves_existing
    test_write_ccswitcher_settings_overwrites_old_ccswitcher_keys
    test_write_ccswitcher_settings_special_chars
    test_write_ccswitcher_settings_empty_env
    test_write_ccswitcher_settings_no_env_block

    test_remove_ccswitcher_settings_preserves_others
    test_remove_ccswitcher_settings_removes_file_when_empty
    test_remove_ccswitcher_settings_handles_nonexistent_file

    test_roundtrip_preserve_settings
    test_valid_json_output

    test_write_ccswitcher_settings_with_permissions_block
    test_remove_ccswitcher_settings_with_permissions_block
    test_roundtrip_with_permissions_block
    test_write_ccswitcher_settings_with_nested_objects

    # Summary
    echo -e "\n${YELLOW}============================================${NC}"
    echo -e "${YELLOW}Test Summary${NC}"
    echo -e "${YELLOW}============================================${NC}"
    echo -e "Tests run:    $TESTS_RUN"
    echo -e "${GREEN}Passed:       $TESTS_PASSED${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed:       $TESTS_FAILED${NC}"
        exit 1
    else
        echo -e "Failed:       0"
        echo -e "\n${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

main "$@"
