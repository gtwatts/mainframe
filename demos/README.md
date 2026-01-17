# Basher Demos

VHS demonstrations for Basher scripts. [VHS](https://github.com/charmbracelet/vhs) is a tool for creating terminal GIFs from tape files.

## Demo Priority (Most Impressive First)

### Tier 1: Hero Demos (Top of README)
1. **json-to-csv** - Visual transformation with color output
2. **agent-spawn** - Parallel execution with progress indicators
3. **git-smart-commit** - AI-assisted commit messages
4. **file-organize** - Auto-organizing files by rules

### Tier 2: Feature Highlights
5. **json-merge** - Deep merging with conflict resolution
6. **agent-monitor** - Real-time dashboard
7. **git-pr-create** - Full PR workflow
8. **http-request** - API interaction with auth

### Tier 3: Utility Showcases
9. **csv-query** - SQL on CSV files
10. **file-dedupe** - Finding and handling duplicates
11. **log-tail** - Multi-file log following

## Recording Standards

### Dimensions
- Width: 120 characters
- Height: 30 lines
- Font size: 16px

### Timing
- Type speed: 50ms (fast but readable)
- Pause after output: 2000ms
- Pause after command: 500ms

### Content
- Clear, relatable examples
- Show both success and error handling
- Include helpful prompts

## VHS Tape Template

```tape
# Demo: script-name
# Description: Brief description

Output demos/gifs/script-name.gif
Set FontSize 16
Set Width 1200
Set Height 600
Set Theme "Catppuccin Mocha"
Set TypingSpeed 50ms

# Title
Type "# Basher: script-name demo"
Enter
Sleep 1s

# Setup
Type "cd /tmp/demo"
Enter
Sleep 500ms

# Main demo
Type "script-name input.json"
Enter
Sleep 2s

# Show result
Type "cat output.csv"
Enter
Sleep 2s

# Cleanup
Type "# Done!"
Sleep 3s
```

## File Organization

```
demos/
├── tapes/
│   ├── data/
│   │   ├── json-to-csv.tape
│   │   ├── csv-to-json.tape
│   │   └── ...
│   ├── agent/
│   │   ├── agent-spawn.tape
│   │   └── ...
│   └── ...
├── gifs/
│   ├── data/
│   ├── agent/
│   └── ...
├── assets/
│   └── sample-data/          # Demo data files
└── README.md
```

## Generating Demos

```bash
# Generate single demo
vhs demos/tapes/data/json-to-csv.tape

# Generate all demos
make demos

# Generate demos for category
make demos-data
make demos-agent
```

## Embedding in README

```markdown
## Data Transformation

### json-to-csv

Convert JSON arrays to CSV with header detection.

![json-to-csv demo](demos/gifs/data/json-to-csv.gif)
```

## CI/CD Demo Generation

Demos are regenerated automatically when:
- Tape files change
- Scripts change
- Manual workflow trigger

See `.github/workflows/demos.yml`
