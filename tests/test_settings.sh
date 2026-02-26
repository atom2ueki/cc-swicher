#!/bin/bash
# Test cases for ccswicher settings management functions
# Run: ./tests/test_settings.sh
#
# This test file contains copies of the functions being tested to allow
# isolated testing without running the main ccswicher.sh script.

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
# Functions under test (copied from ccswicher.sh)
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

# ccswicher-managed env keys
CCSWICHER_ENV_KEYS=(
    "ANTHROPIC_BASE_URL"
    "ANTHROPIC_MODEL"
    "ANTHROPIC_DEFAULT_SONNET_MODEL"
    "ANTHROPIC_DEFAULT_OPUS_MODEL"
    "ANTHROPIC_DEFAULT_HAIKU_MODEL"
    "CLAUDE_CODE_SUBAGENT_MODEL"
    "ANTHROPIC_AUTH_TOKEN"
)

# Check if key is ccswicher-managed
is_ccswicher_env_key() {
    local key="$1"
    for ccswicher_key in "${CCSWICHER_ENV_KEYS[@]}"; do
        [[ "$key" == "$ccswicher_key" ]] && return 0
    done
    return 1
}

# Shared helper: Write ccswicher settings file (pure bash, no dependencies)
write_ccswicher_settings() {
    local settings_path="$1"
    local provider="$2"
    local base_url="$3"
    local model="$4"
    local token="$5"

    local escaped_base escaped_model escaped_token
    escaped_base=$(json_escape "$base_url")
    escaped_model=$(json_escape "$model")

    # Extract existing non-ccswicher env keys and top-level keys from file if it exists
    local existing_env_pairs=""
    local existing_top_pairs=""
    if [[ -f "$settings_path" ]]; then
        local in_env=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip opening/closing braces
            [[ "$line" =~ ^\{[[:space:]]*$ || "$line" =~ ^\}[[:space:]]*$ ]] && continue

            if [[ "$line" =~ \"env\"[[:space:]]*:[[:space:]]*\{ ]]; then
                in_env=1
                continue
            fi
            if [[ $in_env -eq 1 ]]; then
                if [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*[,[:space:]]*$ ]]; then
                    in_env=0
                    continue
                fi
                # Skip ccswicher keys
                if [[ "$line" =~ \"ANTHROPIC_BASE_URL\" || "$line" =~ \"ANTHROPIC_MODEL\" || \
                      "$line" =~ \"ANTHROPIC_DEFAULT_ || "$line" =~ \"CLAUDE_CODE_SUBAGENT_MODEL\" || \
                      "$line" =~ \"ANTHROPIC_AUTH_TOKEN\" ]]; then
                    continue
                fi
                # Extract key-value pair (keep the whole line, just trim whitespace and comma)
                local trimmed="${line#"${line%%[![:space:]]*}"}"
                trimmed="${trimmed%,}"
                if [[ -n "$trimmed" && "$trimmed" =~ \" ]]; then
                    existing_env_pairs="${existing_env_pairs}${trimmed}"$'\n'
                fi
            else
                # Top-level keys (outside env block)
                local trimmed="${line#"${line%%[![:space:]]*}"}"
                trimmed="${trimmed%,}"
                if [[ -n "$trimmed" && "$trimmed" =~ \" ]]; then
                    existing_top_pairs="${existing_top_pairs}${trimmed}"$'\n'
                fi
            fi
        done < "$settings_path"
    fi

    # Build new JSON file
    {
        echo "{"
        echo "  \"env\": {"

        # Add existing non-ccswicher env pairs first (with commas)
        if [[ -n "$existing_env_pairs" ]]; then
            while IFS= read -r pair; do
                if [[ -n "$pair" ]]; then
                    echo "    ${pair},"
                fi
            done <<< "$existing_env_pairs"
        fi

        # Add ccswicher env keys
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

        echo "  }"

        # Add existing top-level keys after env (last item has no comma)
        if [[ -n "$existing_top_pairs" ]]; then
            # Convert to array for proper comma handling
            local top_array=()
            while IFS= read -r pair; do
                [[ -n "$pair" ]] && top_array+=("$pair")
            done <<< "$existing_top_pairs"

            local i=0
            for pair in "${top_array[@]}"; do
                ((i++))
                if [[ $i -lt ${#top_array[@]} ]]; then
                    echo "  ${pair},"
                else
                    echo "  ${pair}"
                fi
            done
        fi

        echo "}"
    } > "$settings_path"

    chmod 600 "$settings_path"
}

# Shared helper: Remove ccswicher-managed keys from settings, preserve others (pure bash)
remove_ccswicher_settings() {
    local settings_path="$1"

    # Extract non-ccswicher env keys and other top-level keys
    local env_pairs=()
    local other_pairs=()
    local in_env=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ \"env\"[[:space:]]*:[[:space:]]*\{ ]]; then
            in_env=1
            continue
        fi
        if [[ $in_env -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*[,[:space:]]*$ ]]; then
                in_env=0
                continue
            fi
            # Skip ccswicher-managed keys
            [[ "$line" =~ \"ANTHROPIC_BASE_URL\" || "$line" =~ \"ANTHROPIC_MODEL\" ]] && continue
            [[ "$line" =~ \"ANTHROPIC_DEFAULT_ || "$line" =~ \"CLAUDE_CODE_SUBAGENT_MODEL\" ]] && continue
            [[ "$line" =~ \"ANTHROPIC_AUTH_TOKEN\" ]] && continue
            # Keep non-ccswicher key
            local trimmed="${line%,}"
            trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
            [[ -n "$trimmed" && "$trimmed" =~ \" ]] && env_pairs+=("$trimmed")
        else
            # Outside env block
            [[ "$line" =~ ^\{[[:space:]]*$ || "$line" =~ ^\}[[:space:]]*$ ]] && continue
            local trimmed="${line%,}"
            trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
            [[ -n "$trimmed" && "$trimmed" =~ \" ]] && other_pairs+=("$trimmed")
        fi
    done < "$settings_path"

    # If nothing left, remove the file
    if [[ ${#env_pairs[@]} -eq 0 && ${#other_pairs[@]} -eq 0 ]]; then
        rm -f "$settings_path"
        echo "removed"
        return
    fi

    # Rebuild JSON
    local total=$(( ${#other_pairs[@]} + (${#env_pairs[@]} > 0 ? 1 : 0) ))
    local count=0

    {
        echo "{"

        # Add other top-level keys
        for pair in "${other_pairs[@]}"; do
            ((count++))
            if [[ $count -lt $total ]]; then
                echo "  ${pair},"
            else
                echo "  ${pair}"
            fi
        done

        # Add env block if there are env keys
        if [[ ${#env_pairs[@]} -gt 0 ]]; then
            ((count++))
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

test_write_ccswicher_settings_new_file() {
    echo -e "\n${YELLOW}=== Test: write_ccswicher_settings new file ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    write_ccswicher_settings "$settings_file" "zai" "https://api.z.ai/api/anthropic" "glm-5" ""

    assert_file_contains "$settings_file" '"ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic"' "Contains base URL"
    assert_file_contains "$settings_file" '"ANTHROPIC_MODEL": "glm-5"' "Contains model"
    assert_file_not_contains "$settings_file" '"ANTHROPIC_AUTH_TOKEN"' "No token when empty"

    teardown
}

test_write_ccswicher_settings_with_token() {
    echo -e "\n${YELLOW}=== Test: write_ccswicher_settings with token ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    write_ccswicher_settings "$settings_file" "minimax" "https://api.minimax.io/anthropic" "MiniMax-M2.5" "sk-test-token"

    assert_file_contains "$settings_file" '"ANTHROPIC_AUTH_TOKEN": "sk-test-token"' "Contains token"

    teardown
}

test_write_ccswicher_settings_preserves_existing() {
    echo -e "\n${YELLOW}=== Test: write_ccswicher_settings preserves existing keys ===${NC}"
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

    write_ccswicher_settings "$settings_file" "zai" "https://api.z.ai/api/anthropic" "glm-5" ""

    assert_file_contains "$settings_file" '"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"' "Preserved AGENT_TEAMS"
    assert_file_contains "$settings_file" '"CUSTOM_API_KEY": "my-secret-key"' "Preserved CUSTOM_API_KEY"
    assert_file_contains "$settings_file" '"SOME_OTHER_SETTING": "value"' "Preserved OTHER_SETTING"
    assert_file_contains "$settings_file" '"ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic"' "Added ccswicher base URL"
    assert_file_contains "$settings_file" '"ANTHROPIC_MODEL": "glm-5"' "Added ccswicher model"

    teardown
}

test_write_ccswicher_settings_overwrites_old_ccswicher_keys() {
    echo -e "\n${YELLOW}=== Test: write_ccswicher_settings overwrites old ccswicher keys ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create initial settings with old ccswicher values
    cat > "$settings_file" << 'EOF'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://old-url.com",
    "ANTHROPIC_MODEL": "old-model",
    "CUSTOM_KEY": "keep-this"
  }
}
EOF

    write_ccswicher_settings "$settings_file" "new-provider" "https://new-url.com" "new-model" ""

    assert_file_contains "$settings_file" '"ANTHROPIC_BASE_URL": "https://new-url.com"' "Updated base URL"
    assert_file_contains "$settings_file" '"ANTHROPIC_MODEL": "new-model"' "Updated model"
    assert_file_contains "$settings_file" '"CUSTOM_KEY": "keep-this"' "Preserved custom key"
    # Check old values are gone
    local content
    content=$(cat "$settings_file")
    assert_not_contains "$content" "old-url.com" "Removed old URL"

    teardown
}

test_write_ccswicher_settings_special_chars() {
    echo -e "\n${YELLOW}=== Test: write_ccswicher_settings with special characters ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Test with URL containing special chars and token with special chars
    write_ccswicher_settings "$settings_file" "test" "https://api.example.com/path?query=1" 'model"name' 'token"with"quotes'

    assert_file_contains "$settings_file" 'https://api.example.com/path?query=1' "URL preserved"
    # Use literal search for escaped quotes (grep needs special handling)
    assert_file_contains "$settings_file" 'model\\"name' "Model name escaped"
    assert_file_contains "$settings_file" 'token\\"with\\"quotes' "Token escaped"
    teardown
}

test_remove_ccswicher_settings_preserves_others() {
    echo -e "\n${YELLOW}=== Test: remove_ccswicher_settings preserves non-ccswicher keys ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create settings with ccswicher and non-ccswicher keys
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
    result=$(remove_ccswicher_settings "$settings_file")

    assert_equals "preserved" "$result" "Returns 'preserved' when keys remain"
    assert_file_contains "$settings_file" '"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"' "Preserved AGENT_TEAMS"
    assert_file_contains "$settings_file" '"CUSTOM_KEY": "preserve-this"' "Preserved CUSTOM_KEY"
    assert_file_contains "$settings_file" '"ANOTHER_KEY": "keep-this-too"' "Preserved ANOTHER_KEY"
    assert_file_contains "$settings_file" '"someOtherTopLevel": "value"' "Preserved top-level key"

    # Check ccswicher keys are removed
    local content
    content=$(cat "$settings_file")
    assert_not_contains "$content" "ANTHROPIC_BASE_URL" "Removed ANTHROPIC_BASE_URL"
    assert_not_contains "$content" "ANTHROPIC_MODEL" "Removed ANTHROPIC_MODEL"
    assert_not_contains "$content" "ANTHROPIC_AUTH_TOKEN" "Removed token"
    teardown
}

test_remove_ccswicher_settings_removes_file_when_empty() {
    echo -e "\n${YELLOW}=== Test: remove_ccswicher_settings removes file when empty ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create settings with only ccswicher keys
    cat > "$settings_file" << 'EOF'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
    "ANTHROPIC_MODEL": "glm-5"
  }
}
EOF

    local result
    result=$(remove_ccswicher_settings "$settings_file")

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

test_remove_ccswicher_settings_handles_nonexistent_file() {
    echo -e "\n${YELLOW}=== Test: remove_ccswicher_settings handles nonexistent file ===${NC}"
    setup

    local settings_file="$TEST_DIR/nonexistent.json"

    # Should not error, just return
    if remove_ccswicher_settings "$settings_file" 2>/dev/null; then
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

    # Write ccswicher settings
    write_ccswicher_settings "$settings_file" "zai" "https://api.z.ai/api/anthropic" "glm-5" "test-token"

    # Verify ccswicher settings were added
    assert_file_contains "$settings_file" '"ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic"' "ccswicher settings added"

    # Remove ccswicher settings
    remove_ccswicher_settings "$settings_file"

    # Verify original keys are preserved
    assert_file_contains "$settings_file" '"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"' "Original AGENT_TEAMS preserved"
    assert_file_contains "$settings_file" '"MY_CUSTOM_VAR": "custom-value"' "Original custom var preserved"
    assert_file_contains "$settings_file" '"topLevelKey": "topLevelValue"' "Original top-level preserved"
    teardown
}

test_write_ccswicher_settings_empty_env() {
    echo -e "\n${YELLOW}=== Test: write_ccswicher_settings with empty existing env ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create settings with empty env
    cat > "$settings_file" << 'EOF'
{
  "env": {},
  "otherKey": "value"
}
EOF

    write_ccswicher_settings "$settings_file" "minimax" "https://api.minimax.io/anthropic" "MiniMax-M2.5" ""

    assert_file_contains "$settings_file" '"ANTHROPIC_MODEL": "MiniMax-M2.5"' "ccswicher model added"
    assert_file_contains "$settings_file" '"otherKey": "value"' "Other key preserved"
    teardown
}

test_write_ccswicher_settings_no_env_block() {
    echo -e "\n${YELLOW}=== Test: write_ccswicher_settings with no existing env block ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Create settings without env block
    cat > "$settings_file" << 'EOF'
{
  "someKey": "someValue"
}
EOF

    write_ccswicher_settings "$settings_file" "minimax" "https://api.minimax.io/anthropic" "MiniMax-M2.5" ""

    assert_file_contains "$settings_file" '"ANTHROPIC_MODEL": "MiniMax-M2.5"' "ccswicher model added"
    assert_file_contains "$settings_file" '"someKey": "someValue"' "Existing key preserved"
    teardown
}

test_valid_json_output() {
    echo -e "\n${YELLOW}=== Test: Valid JSON output ===${NC}"
    setup

    local settings_file="$TEST_DIR/settings.json"

    # Test write produces valid JSON
    write_ccswicher_settings "$settings_file" "test" "https://api.test.com" "test-model" "test-token"

    # Use Python to validate JSON (if available)
    if command -v python3 &>/dev/null; then
        ((TESTS_RUN++))
        if python3 -c "import json; json.load(open('$settings_file'))" 2>/dev/null; then
            echo -e "${GREEN}PASS:${NC} write_ccswicher_settings produces valid JSON"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL:${NC} write_ccswicher_settings produces invalid JSON"
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

    write_ccswicher_settings "$settings_file" "test" "https://api.test.com" "test-model" ""

    if command -v python3 &>/dev/null; then
        ((TESTS_RUN++))
        if python3 -c "import json; json.load(open('$settings_file'))" 2>/dev/null; then
            echo -e "${GREEN}PASS:${NC} write_ccswicher_settings with existing keys produces valid JSON"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL:${NC} write_ccswicher_settings with existing keys produces invalid JSON"
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
    echo -e "${YELLOW}ccswicher Settings Management Test Suite${NC}"
    echo -e "${YELLOW}============================================${NC}"

    # Run all tests
    test_json_escape_simple
    test_json_escape_quotes
    test_json_escape_backslash
    test_json_escape_newline
    test_json_escape_tab
    test_json_escape_combined

    test_write_ccswicher_settings_new_file
    test_write_ccswicher_settings_with_token
    test_write_ccswicher_settings_preserves_existing
    test_write_ccswicher_settings_overwrites_old_ccswicher_keys
    test_write_ccswicher_settings_special_chars
    test_write_ccswicher_settings_empty_env
    test_write_ccswicher_settings_no_env_block

    test_remove_ccswicher_settings_preserves_others
    test_remove_ccswicher_settings_removes_file_when_empty
    test_remove_ccswicher_settings_handles_nonexistent_file

    test_roundtrip_preserve_settings
    test_valid_json_output

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
