#!/bin/bash
set -euo pipefail

REPO="atom2ueki/cc-switcher"
INSTALL_DIR="${HOME}/bin"

# Get latest release version
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | \
        grep '"tag_name"' | sed 's/.*"\([^"]*\)".*/\1/'
}

echo "Fetching latest version..."
LATEST_VERSION=$(get_latest_version)
echo "Installing CC-Switcher ${LATEST_VERSION}..."

# Create install directory
mkdir -p "$INSTALL_DIR"

# Download binary
BINARY_URL="https://github.com/${REPO}/releases/download/${LATEST_VERSION}/ccswitcher"
echo "Downloading binary..."
curl -fsSL "$BINARY_URL" -o "${INSTALL_DIR}/ccswitcher"
chmod +x "${INSTALL_DIR}/ccswitcher"

# Download providers.json
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
echo "  ccswitcher -g -p zai      # Global provider"
echo "  ccswitcher -p minimax    # Project provider"
echo "  ccswitcher status         # Show status"
echo "  ccswitcher list          # List providers"
