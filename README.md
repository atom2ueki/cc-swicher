# CC-Switcher

A CLI tool to switch Claude Code between different AI providers with interactive model selection.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-swicher/main/install.sh | bash
```

Or clone and install locally:

```bash
git clone https://github.com/atom2ueki/cc-swicher.git
cd cc-swicher
./install.sh
```

## Supported Providers

- DeepSeek
- Kimi (Moonshot)
- GLM (Zhipu)
- Qwen (Alibaba)
- MiniMax
- Seed/Doubao
- StepFun
- Claude (official)
- OpenRouter

## Usage

### Switch provider (shows model picker)

```bash
ccswitcher deepseek
ccswitcher glm china
```

### Quick switch with specific model

```bash
ccswitcher deepseek --model deepseek-reasoner
ccswitcher deepseek --skip-picker  # Use default
```

### Check status

```bash
ccswitcher status
```

### User-level settings (persistent)

```bash
ccswitcher user glm global
ccswitcher user reset
```

## Configuration

Config file: `~/.ccswitcher_config`

Add your API keys:

```bash
ccswitcher config
```

## License

MIT
