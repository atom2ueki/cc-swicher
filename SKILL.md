---
name: ccswitcher-release
description: This skill should be used when releasing a new version of CC-Switcher, creating git tags for releases, managing semantic versioning, or running the release workflow. Use when asked to "release", "tag version", "bump version", "create release", or "publish new version".
version: 1.0.0
---

# CC-Switcher Release Guide

Manage version releases for CC-Switcher using semantic versioning.

## Version Strategy

**Single source of truth: Git tags**

The version is determined from the latest GitHub release tag. The binary reads version from git tag at runtime.

## Release Workflow

### Step 1: Build Release Binary

```bash
cargo build --release
```

### Step 2: Test Locally

```bash
./target/release/ccswitcher --version
./target/release/ccswitcher list
```

### Step 3: Create Git Tag

Create a tag WITHOUT the `v` prefix:

```bash
git tag 1.0.0
```

### Step 4: Push Tag to Remote

```bash
git push origin main --tags
```

### Step 5: Verify Release

GitHub Actions will build and upload the binary. Check:
- GitHub Releases page
- CI workflow run status

## How Upgrade Works

The `ccswitcher upgrade` command:

1. Fetches latest release from GitHub API: `https://api.github.com/repos/atom2ueki/cc-switcher/releases/latest`
2. Compares with current binary's version (from VERSION env var)
3. If newer, downloads new binary to temp location
4. Replaces the current binary
5. Shows success message

## Important Rules

- Tags are WITHOUT `v` prefix (e.g., use `1.0.0` not `v1.0.0`)
- Tags must follow semantic versioning: X.Y.Z
- CI builds for: apple-darwin (macOS ARM + x86)

## Installation for Users

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/install.sh)"
```

Or manually:

```bash
# Download binary
curl -fsSL https://github.com/atom2ueki/cc-switcher/releases/latest/download/ccswitcher-apple-darwin-$(uname -m) -o ~/bin/ccswitcher
chmod +x ~/bin/ccswitcher

# Add to PATH (add to ~/.zshrc)
export PATH="$HOME/bin:$PATH"
```
