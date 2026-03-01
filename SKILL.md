---
name: ccswitcher-release
description: This skill should be used when releasing a new version of CC-Switcher, creating git tags for releases, managing semantic versioning, or running the release workflow. Use when asked to "release", "tag version", "bump version", "create release", or "publish new version".
version: 1.0.0
---

# CC-Switcher Release Guide

Manage version releases for CC-Switcher using semantic versioning without the `v` prefix.

## Version Strategy

**Single source of truth: Git tags + VERSION in ccswitcher.sh**

When releasing:
1. Update VERSION in ccswitcher.sh (line ~30)
2. Create git tag matching the VERSION
3. Push tag to remote

## Release Workflow

### Step 1: Update VERSION Constant

Edit `ccswitcher.sh` - update VERSION on line ~30:

```bash
VERSION="1.0.0"
```

### Step 2: Commit Version Change

```bash
git add ccswitcher.sh
git commit -m "chore: bump version to 1.0.0"
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

```bash
git ls-remote --tags origin
```

Test upgrade:

```bash
ccswitcher upgrade
```

## How Upgrade Works

The `ccswitcher upgrade` command:

1. Fetches tags from GitHub API
2. Filters tags matching: `^[0-9]+\.[0-9]+\.[0-9]+$`
3. Sorts using semantic version: `sort -V`
4. Downloads from: `https://raw.githubusercontent.com/atom2ueki/cc-switcher/{version}/ccswitcher.sh`
5. Compares with local VERSION to determine if upgrade needed

## Important Rules

- NEVER use `v` prefix in tags (e.g., use `1.0.0` not `v1.0.0`)
- VERSION in ccswitcher.sh must exactly match the git tag
- Tags must follow semantic versioning: X.Y.Z

## Troubleshooting

### Upgrade says "Already at latest"

- Clear cache: `rm -rf ~/.cache/ccswitcher/`
- Verify tag exists: `git ls-remote --tags origin`

### "Could not fetch remote version tags"

- Check GitHub API rate limits
- Verify repo is public
