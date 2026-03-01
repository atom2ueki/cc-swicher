# CC-Switcher

A CLI tool to switch Claude Code between different AI providers with interactive model selection.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/install.sh | bash
```

Or clone and install locally:

```bash
git clone https://github.com/atom2ueki/cc-switcher.git
cd cc-switcher
./install.sh
```

## Usage

### Set provider (global or project)

```bash
ccswitcher -g -p zai        # Set global provider
ccswitcher -p zai          # Set project provider
ccswitcher -p zai -o /tmp/test.json  # Write to specific file
```

### Check status

```bash
ccswitcher status          # Show all configurations
ccswitcher -g status       # Show global configuration only
```

### List available providers

```bash
ccswitcher list
```

### Upgrade to latest version

```bash
ccswitcher upgrade
```

### Check version

```bash
ccswitcher version
```

## Supported Providers

- Z.AI (zai)
- MiniMax (minimax)
- Anthropic (official Claude Code)
- LM Studio (local)

See `ccswitcher list` for all available providers and their models.

## Configuration

Settings are stored in:
- Global: `~/.claude/settings.json`
- Project: `.claude/settings.local.json`

The tool automatically reads your API keys from environment variables (e.g., `ZAI_API_KEY`, `MINIMAX_API_KEY`) when switching providers.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/uninstall.sh | bash
```

Or run locally:

```bash
./uninstall.sh
```

## License

MIT
