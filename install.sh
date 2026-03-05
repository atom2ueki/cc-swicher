#!/bin/bash
set -euo pipefail

REPO="atom2ueki/cc-switcher"
INSTALL_DIR="${HOME}/bin"

# Detect platform
detect_platform() {
    case "$(uname -s)" in
        Darwin*)  echo "apple-darwin" ;;
        Linux*)   echo "unknown-linux-gnu" ;;
        *)        echo "Unsupported platform" && exit 1 ;;
    esac
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64)   echo "x86_64" ;;
        arm64|aarch64)  echo "aarch64" ;;
        *)        echo "Unsupported architecture" && exit 1 ;;
    esac
}

# Get latest release version (no v prefix)
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | \
        grep '"tag_name"' | sed 's/.*"\([^"]*\)".*/\1/'
}

PLATFORM=$(detect_platform)
ARCH=$(detect_arch)

echo "Fetching latest version..."
LATEST_VERSION=$(get_latest_version)
echo "Installing CC-Switcher ${LATEST_VERSION}..."

# Create install directory
mkdir -p "$INSTALL_DIR"

# Download binary (no v prefix in URL)
BINARY_URL="https://github.com/${REPO}/releases/download/${LATEST_VERSION}/ccswitcher-${PLATFORM}-${ARCH}"
echo "Downloading binary from: $BINARY_URL"
curl -fsSL "$BINARY_URL" -o "${INSTALL_DIR}/ccswitcher"
chmod +x "${INSTALL_DIR}/ccswitcher"

# Download providers.json to same directory
PROVIDERS_URL="https://github.com/${REPO}/releases/download/${LATEST_VERSION}/providers.json"
curl -fsSL "$PROVIDERS_URL" -o "${INSTALL_DIR}/providers.json"

# Add to PATH if not already there
SHELL_RC="${HOME}/.zshrc"
PATH_EXPORT='export PATH="${HOME}/bin:${PATH}"'
if [[ -f "$SHELL_RC" ]] && ! grep -Fq 'export PATH="${HOME}/bin:' "$SHELL_RC"; then
    echo "$PATH_EXPORT" >> "$SHELL_RC"
    echo "Added ${HOME}/bin to PATH in ~/.zshrc"
fi

echo ""
echo "Installation complete!"
echo ""
echo "Restart your shell or run: source ~/.zshrc"
echo ""
echo "Usage:"
echo "  ccswitcher -g -p zai      # Set global provider"
echo "  ccswitcher -p minimax    # Project provider"
echo "  ccswitcher status         # Show status"
echo "  ccswitcher list          # List providers"
