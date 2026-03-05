#!/bin/bash
set -euo pipefail

REPO="atom2ueki/cc-switcher"
INSTALL_DIR="${HOME}/bin"

# Detect platform
detect_platform() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    case "$os" in
        darwin*)
            case "$arch" in
                arm64|aarch64) echo "macos-arm64" ;;
                x86_64)        echo "macos-x86_64" ;;
                *)             echo "unsupported" ;;
            esac
            ;;
        linux*)
            case "$arch" in
                x86_64)        echo "linux-x86_64" ;;
                aarch64|arm64) echo "linux-arm64" ;;
                *)             echo "unsupported" ;;
            esac
            ;;
        *)
            echo "unsupported"
            ;;
    esac
}

# Parse arguments
TARGET=""
VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--target)
            TARGET="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-t|--target <platform>] [-v|--version <version>]"
            echo ""
            echo "Options:"
            echo "  -t, --target    Platform: macos-arm64, macos-x86_64, linux-x86_64, linux-arm64"
            echo "  -v, --version   Specific version to install (default: latest)"
            echo "  -h, --help      Show this help message"
            echo ""
            echo "If no target is specified, it will be auto-detected."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Auto-detect if not specified
if [[ -z "$TARGET" ]]; then
    TARGET=$(detect_platform)
    if [[ "$TARGET" == "unsupported" ]]; then
        echo "Error: Unsupported platform. Use -t to specify target."
        exit 1
    fi
    echo "Detected platform: $TARGET"
fi

# Validate target
case "$TARGET" in
    macos-arm64|macos-x86_64|linux-x86_64|linux-arm64) ;;
    *)
        echo "Error: Invalid target '$TARGET'. Valid options: macos-arm64, macos-x86_64, linux-x86_64, linux-arm64"
        exit 1
        ;;
esac

# Get version
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | \
        grep '"tag_name"' | sed 's/.*"\([^"]*\)".*/\1/'
}

if [[ -z "$VERSION" ]]; then
    echo "Fetching latest version..."
    VERSION=$(get_latest_version)
fi

echo "Installing CC-Switcher ${VERSION} for ${TARGET}..."

# Create install directory
mkdir -p "$INSTALL_DIR"

# Download binary with platform suffix
BINARY_URL="https://github.com/${REPO}/releases/download/${VERSION}/ccswitcher-${TARGET}"
echo "Downloading binary..."
curl -fsSL -L "$BINARY_URL" -o "${INSTALL_DIR}/ccswitcher" || {
    echo "Error: Failed to download binary from $BINARY_URL"
    echo "Please check if the release exists and contains the binary for your platform."
    exit 1
}
chmod +x "${INSTALL_DIR}/ccswitcher"

# Download providers.json
PROVIDERS_URL="https://github.com/${REPO}/releases/download/${VERSION}/providers.json"
curl -fsSL -L "$PROVIDERS_URL" -o "${INSTALL_DIR}/providers.json" || {
    echo "Warning: Failed to download providers.json, creating default..."
    echo '{"version":"1.0.0","providers":{}}' > "${INSTALL_DIR}/providers.json"
}

# Add to PATH if not already there
add_to_rc() {
    local rc_file="$1"
    if [[ -f "$rc_file" ]] && ! grep -Fq '# ccswitcher' "$rc_file"; then
        echo '' >> "$rc_file"
        echo '# ccswitcher' >> "$rc_file"
        echo 'export PATH="${HOME}/bin:${PATH}"' >> "$rc_file"
        echo '# end ccswitcher' >> "$rc_file"
        echo "Added ${HOME}/bin to PATH in $rc_file"
    fi
}

add_to_rc "${HOME}/.zshrc"
add_to_rc "${HOME}/.bashrc"

echo ""
echo "Installation complete!"
echo ""
echo "Restart your shell or run: source ~/.zshrc (or ~/.bashrc)"
echo ""
echo "Usage:"
echo "  ccswitcher -g -p zai      # Global provider"
echo "  ccswitcher -p minimax    # Project provider"
echo "  ccswitcher status         # Show status"
echo "  ccswitcher list          # List providers"
