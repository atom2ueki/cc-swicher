---
name: ccswitcher-release
description: This skill should be used when releasing a new version of CC-Switcher, creating git tags for releases, managing semantic versioning, running the release workflow, or fixing failed releases. Use when asked to "release", "tag version", "bump version", "create release", "publish new version", "retrigger release", or "fix failed build".
version: 1.1.0
---

# CC-Switcher Release Guide

Manage version releases for CC-Switcher using semantic versioning.

## Version Strategy

**Single source of truth: Cargo.toml**

The version is defined in `Cargo.toml`:
```toml
[package]
version = "1.2.0"
```

## When to Bump Version

| Change Type | Example | Version Bump |
|------------|---------|--------------|
| **Patch** | Bug fixes, small improvements | 1.0.0 → 1.0.1 |
| **Minor** | New features, backward compatible | 1.0.0 → 1.1.0 |
| **Major** | Breaking changes | 1.0.0 → 2.0.0 |

**IMPORTANT: Never bump version if the previous release failed. Fix the issue and use the SAME version number.**

## Release Workflow

### Step 1: Update Version in Cargo.toml (ONLY if previous release succeeded)

Edit the version number:
```toml
[package]
version = "1.2.1"  # bump as needed
```

### Step 2: Commit and Tag

```bash
git add -A
git commit -m "release: v1.2.1"
git tag 1.2.1
git push origin main
git push origin 1.2.1
```

**IMPORTANT: Push main FIRST, then the tag. The tag push triggers the release workflow.**

### Step 3: Monitor Build

GitHub Actions will build TWO platforms:
- `macos-latest` → `ccswitcher-macos-arm64`
- `ubuntu-latest` → `ccswitcher-linux-x86_64`

Check progress at: https://github.com/atom2ueki/cc-switcher/actions

## Failed Release - How to Fix and Retrigger

### Common Failure Reasons

1. **Binary path error**: Binary is at `target/<target>/release/ccswitcher`, not `target/release/ccswitcher`
2. **Missing cross-compiler**: Linux builds need `gcc-x86_64-linux-gnu`
3. **Workflow syntax errors**

### Fix and Retrigger (SAME version - don't bump!)

```bash
# Fix the issue in the code
# Edit the file that needs fixing

# Commit with descriptive message (NOT "release: vX.X.X")
git add -A
git commit -m "fix: correct binary path for cross-compilation"

# Push to main (this updates the code)
git push origin main

# Delete old tag from local and remote
git tag -d 1.2.1
git push origin :refs/tags/1.2.1

# Recreate tag on the new commit
git tag 1.2.1
git push origin 1.2.1
```

**Key points:**
- Use SAME version number (don't increment!)
- Commit message should describe the FIX, not "release"
- Delete and recreate tag to retrigger workflow
- The workflow triggers on TAG PUSH, not commit push

## How Upgrade Works (Runtime)

The `ccswitcher upgrade` command:
1. Fetches latest release from GitHub API
2. Compares with current binary's version (from Cargo.toml)
3. If newer, downloads new binary and replaces itself

## Installation for Users

```bash
# Auto-detect platform
curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/install.sh | bash

# Manual platform selection
curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/install.sh | bash -s -- -t macos-arm64
curl -fsSL https://raw.githubusercontent.com/atom2ueki/cc-switcher/main/install.sh | bash -s -- -t linux-x86_64
```

## Important Rules

- Version in Cargo.toml MUST match the git tag
- Use semantic versioning: X.Y.Z
- NEVER bump version if previous release failed
- Use SAME version number when fixing a failed release
- CI builds for TWO platforms: macos-arm64 AND linux-x86_64
- The release is triggered by TAG push, not commit push
