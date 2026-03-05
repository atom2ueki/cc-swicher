# CC-Switcher

A CLI tool to switch Claude Code between different AI providers.

## Installation

### Quick Install (auto-detects your platform)

```bash
curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/install.sh | bash
```

### Manual Install (with specific platform)

```bash
# macOS Apple Silicon (M1/M2/M3)
curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/install.sh | bash -s -- -t macos-arm64

# macOS Intel
curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/install.sh | bash -s -- -t macos-x86_64

# Linux x86_64
curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/install.sh | bash -s -- -t linux-x86_64

# Linux ARM64
curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/install.sh | bash -s -- -t linux-arm64
```

Install a specific version:

```bash
GITHUB_BRANCH=1.0.0 curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/install.sh | bash -s -- -t macos-arm64
```

Or clone and install locally:

```bash
git clone https://github.com/atom2ueki/cc-switcher.git
cd cc-switcher
git checkout 1.0.0
./install.sh
```

## Usage

### Set provider

```bash
ccswitcher -p zai         # Set project provider
ccswitcher -g -p zai      # Set global provider
```

### Check status

```bash
ccswitcher status         # Show all configurations
ccswitcher -g status      # Show global configuration
```

### Other commands

```bash
ccswitcher list           # List available providers
ccswitcher version        # Show version
ccswitcher upgrade        # Upgrade to latest version
```

## Supported Providers

- zai - Z.AI
- minimax - MiniMax
- lmstudio - LM Studio (local)
- anthropic - Claude Code official

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/uninstall.sh | bash
```

## License

MIT
