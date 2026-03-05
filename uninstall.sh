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
    sed -i '' '/# ccswitcher/,/# end ccswitcher/d' "${HOME}/.zshrc"
    # Clean up empty lines
    sed -i '' '/^$/N;/^\n$/d' "${HOME}/.zshrc"
    echo "Removed ccswitcher from ~/.zshrc"
fi

echo ""
echo "Uninstall complete!"
