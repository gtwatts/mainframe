# MAINFRAME Demo Tapes

VHS tape files for generating animated demo GIFs of MAINFRAME features.

## Requirements

- **VHS**: `go install github.com/charmbracelet/vhs@latest`
- **ttyd**: Terminal web daemon (https://github.com/tsl0922/ttyd)

## Available Demos

### Agent Intelligence Demo

Demonstrates AI agent strategic codebase analysis with MAINFRAME.

**Generate:**
```bash
bash demos/tapes/mainframe/run-demo.sh
```

**Output:** `demos/gifs/agent-intelligence.gif`

## Directory Structure

```
tapes/
└── mainframe/
    ├── agent-intelligence.tape  # VHS tape definition
    ├── setup-demo-project.sh    # Creates realistic demo project
    └── run-demo.sh              # Generator script
```

## Theme

All demos use Catppuccin Mocha for visual consistency.
