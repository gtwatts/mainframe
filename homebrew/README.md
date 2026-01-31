# MAINFRAME Homebrew Tap

Install MAINFRAME with a single command.

## Installation

```bash
# Add the tap and install
brew tap gtwatts/mainframe
brew install mainframe

# Or in one command
brew install gtwatts/mainframe/mainframe
```

## Usage

After installation, add this to the top of your bash scripts:

```bash
#!/usr/bin/env bash
source "$(brew --prefix)/opt/mainframe/lib/common.sh"
```

Or for shell integration, add to your `~/.bashrc` or `~/.zshrc`:

```bash
source "$(brew --prefix)/opt/mainframe/libexec/init.sh"
```

## What You Get

- **4,000+ pure bash functions** across 117 libraries
- **Zero dependencies** (except bash 4.4+)
- **AI agent support** (AWM, IPC, bURL)
- **Auto-detection** by AI coding tools

## Quick Test

```bash
source "$(brew --prefix)/opt/mainframe/lib/common.sh"

# Try some functions
json_object "name=MAINFRAME" "version=6.0"
uuid
now_iso
```

## Updating

```bash
brew upgrade mainframe
```

## Uninstalling

```bash
brew uninstall mainframe
brew untap gtwatts/mainframe
```

## Setting Up the Tap Repository

To publish this tap, create a new GitHub repository called `homebrew-mainframe`:

```bash
# Create the tap repo
mkdir homebrew-mainframe
cd homebrew-mainframe
git init

# Copy the formula
cp Formula/mainframe.rb .

# Commit and push
git add mainframe.rb
git commit -m "Add MAINFRAME formula"
git remote add origin git@github.com:gtwatts/homebrew-mainframe.git
git push -u origin main
```

The repository must be named `homebrew-mainframe` for `brew tap gtwatts/mainframe` to work.
