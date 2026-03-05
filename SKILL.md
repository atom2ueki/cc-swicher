---
name: ccswitcher-release
description: This skill should be used when releasing a new version of CC-Switcher, creating git tags for releases, managing semantic versioning, or running the release workflow. Use when asked to "release", "tag version", "bump version", "create release", or "publish new version".
version: 1.0.0
---

# CC-Switcher Release Guide

Manage version releases for CC-Switcher using semantic versioning.

## Version Strategy

**Single source of truth: Cargo.toml**

The version is defined in `Cargo.toml`:
```toml
[package]
version = "1.0.0"
```

## When to Bump Version

| Change Type | Example | Version Bump |
|------------|---------|--------------|
| **Patch** | Bug fixes, small improvements | 1.0.0 → 1.0.1 |
| **Minor** | New features, backward compatible | 1.0.0 → 1.1.0 |
| **Major** | Breaking changes | 1.0.0 → 2.0.0 |

## Release Workflow

### Step 1: Update Version in Cargo.toml

Edit the version number according to the change type:
```toml
[package]
version = "1.0.1"  # bump as needed
```

### Step 2: Commit and Tag

```bash
# Edit Cargo.toml first, then:
git add Cargo.toml
git commit -m "bump version to 1.0.1"
git tag 1.0.1
git push origin main --tags
```

### Step 3: CI Builds and Releases

GitHub Actions will:
1. Build the binary
2. Create GitHub Release with tag from git tag

## How Upgrade Works (Runtime)

The `ccswitcher upgrade` command:
1. Fetches latest release from GitHub API
2. Compares with current binary's version (from Cargo.toml)
3. If newer, downloads new binary and replaces itself

## Installation for Users

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/install.sh)"
```

## Important Rules

- Version in Cargo.toml MUST match the git tag
- Use semantic versioning: X.Y.Z
- CI builds for: apple-darwin (Apple Silicon)
