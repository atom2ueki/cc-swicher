#!/bin/bash
set -euo pipefail

INSTALL_DIR="${HOME}/bin"

echo "Uninstalling CC-Switcher..."

# Remove binary
if [[ -f "${INSTALL_DIR}/ccswitcher" ]]; then
    rm -f "${INSTALL_DIR}/ccswitcher"
    echo "Removed: ${INSTALL_DIR}/ccswitcher"
fi

# Remove providers.json
if [[ -f "${INSTALL_DIR}/providers.json" ]]; then
    rm -f "${INSTALL_DIR}/providers.json"
    echo "Removed: ${INSTALL_DIR}/providers.json"
fi

# Remove PATH export from .zshrc
if [[ -f "${HOME}/.zshrc" ]]; then
    sed -i '' '/export PATH="\$HOME\/bin:\$PATH"/d' "${HOME}/.zshrc"
    echo "Removed PATH export from ~/.zshrc"
fi

echo ""
echo "Uninstall complete!"
