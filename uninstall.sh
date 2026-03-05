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
    # Remove ccswitcher block (between # ccswitcher and # end ccswitcher)
    sed -i '/# ccswitcher/,/# end ccswitcher/d' "${HOME}/.zshrc"
    # Clean up empty lines (works on both macOS and Linux)
    sed -i '/^$/N;/^\n$/d' "${HOME}/.zshrc"
    echo "Removed ccswitcher from ~/.zshrc"
fi

# Also handle .bashrc for Linux users
if [[ -f "${HOME}/.bashrc" ]]; then
    sed -i '/# ccswitcher/,/# end ccswitcher/d' "${HOME}/.bashrc"
    sed -i '/^$/N;/^\n$/d' "${HOME}/.bashrc"
    echo "Removed ccswitcher from ~/.bashrc"
fi

echo ""
echo "Uninstall complete!"
