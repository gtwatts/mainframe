# Terminal UI Functions

Animations, output formatting, and ANSI colors.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## CLI Animation Functions (anim.sh)

### Spinner Functions

| Function | Signature | Example | Description |
|----------|-----------|---------|-------------|
| `spinner_list` | `spinner_list [theme]` | `spinner_list` | List available spinner names |
| `spinner_preview` | `spinner_preview name [duration] [theme]` | `spinner_preview dots 2` | Preview a spinner |
| `spinner_start` | `spinner_start name [message] [--color C] [--theme T]` | `spinner_start dots "Loading..."` | Start background spinner |
| `spinner_stop` | `spinner_stop [message] [status]` | `spinner_stop "Done" success` | Stop spinner, show result |
| `spinner_while` | `spinner_while name message cmd [args]` | `spinner_while moon "Installing" npm install` | Run command with spinner |

### Progress Bar Functions

| Function | Signature | Example | Description |
|----------|-----------|---------|-------------|
| `progress_bar` | `progress_bar cur total [--style S] [--label L]` | `progress_bar 50 100 --style gradient` | Animated progress bar |
| `progress_indeterminate_start` | `progress_indeterminate_start [message]` | `progress_indeterminate_start "Loading..."` | Bouncing progress bar |
| `progress_indeterminate_stop` | `progress_indeterminate_stop [message]` | `progress_indeterminate_stop "Done"` | Stop indeterminate progress |

### Visual Effect Functions

| Function | Signature | Example | Description |
|----------|-----------|---------|-------------|
| `typewriter` | `typewriter "text" [delay]` | `typewriter "Hello!" 0.05` | Type text character by character |
| `rainbow` | `rainbow "text"` | `rainbow "Colorful!"` | Print text in rainbow colors |
| `glitch` | `glitch "text" [iterations]` | `glitch "SYSTEM ONLINE"` | Glitchy text reveal |
| `reveal` | `reveal "text" [delay]` | `reveal "Secret"` | Random character reveal |

### Theme Functions

| Function | Signature | Example | Description |
|----------|-----------|---------|-------------|
| `anim_theme` | `anim_theme name` | `anim_theme minimal` | Set theme (minimal/modern/nerd/playful) |
| `anim_theme_auto` | `anim_theme_auto` | `anim_theme_auto` | Auto-detect best theme |

### Available Spinner Styles (modern theme)

| Category | Spinners |
|----------|----------|
| **Dots** | `dots`, `dots2`, `dots3`, `dots4`, `dots5`, `dots6`, `dots7`, `dots8`, `dots9`, `dots10`, `dots11` |
| **Lines/Bars** | `line`, `line2`, `pipe`, `bouncingBar`, `bouncingBall`, `aesthetic` |
| **Arrows** | `arrow`, `arrow2`, `arrow3` |
| **Shapes** | `triangle`, `arc`, `circle`, `squareCorners`, `circleQuarters`, `circleHalves` |
| **Time** | `clock` |
| **Space** | `earth`, `moon` |
| **Fun** | `shark`, `runner`, `smiley`, `monkey`, `hearts`, `star`, `christmas` |

### Progress Bar Styles

| Style | Description | Example |
|-------|-------------|---------|
| `bar` | Standard filled/empty (default) | `########----` |
| `gradient` | Dark to light gradient | `...:::::###` |
| `blocks` | Block characters | `#######....` |
| `dots` | Filled/empty circles | `@@@@@@@@....` |

---

## ANSI/Color Functions (ansi.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `ansi_red` | `ansi_red` | `echo "$(ansi_red)Error$(ansi_reset)"` | (red text) |
| `ansi_green` | `ansi_green` | `echo "$(ansi_green)OK$(ansi_reset)"` | (green text) |
| `ansi_yellow` | `ansi_yellow` | `echo "$(ansi_yellow)Warn$(ansi_reset)"` | (yellow text) |
| `ansi_blue` | `ansi_blue` | `echo "$(ansi_blue)Info$(ansi_reset)"` | (blue text) |
| `ansi_bold` | `ansi_bold` | `echo "$(ansi_bold)Bold$(ansi_reset)"` | (bold text) |
| `ansi_reset` | `ansi_reset` | `ansi_reset` | (reset formatting) |
| `ansi_print` | `ansi_print color text` | `ansi_print red "Error"` | (colored text) |
| `ansi_styled` | `ansi_styled "styles" text` | `ansi_styled "bold,red" "X"` | (styled text) |

---

## Config Functions (config.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `config_load` | `config_load "path"` | `config_load "app.conf"` | (loads config) |
| `config_get` | `config_get "key"` | `config_get "name"` | `value` |
| `config_get_int` | `config_get_int "key"` | `config_get_int "port"` | `8080` |
| `config_get_bool` | `config_get_bool "key"` | `config_get_bool "debug"` | (returns 0/1) |
| `config_set` | `config_set "key" "value"` | `config_set "name" "app"` | (sets value) |
| `config_has` | `config_has "key"` | `config_has "name"` | (returns 0/1) |
| `config_save` | `config_save "path"` | `config_save "app.conf"` | (saves config) |

---

## Quick Patterns

### Simple Spinner
```bash
spinner_start dots "Installing dependencies..."
npm install >/dev/null 2>&1
spinner_stop "Dependencies installed" success
```

### Progress Bar with Style
```bash
for i in {0..100..5}; do
    progress_bar $i 100 --style gradient --label "Download"
    sleep 0.1
done
echo ""
```

### Colored Spinner
```bash
spinner_start moon "Syncing..." --color cyan
sleep 3
spinner_stop "Synced!" success
```

### Theme Switching
```bash
if [[ -z "$DISPLAY" ]]; then
    anim_theme minimal  # SSH/basic terminal
else
    anim_theme modern   # Full Unicode support
fi
```

### Fun Welcome
```bash
rainbow "Welcome to MAINFRAME!"
typewriter "Initializing systems..." 0.03
```

### Colored Output
```bash
echo "$(ansi_red)Error:$(ansi_reset) Something went wrong"
echo "$(ansi_green)Success:$(ansi_reset) Operation completed"
ansi_print yellow "Warning: check configuration"
```

### Styled Text
```bash
ansi_styled "bold,blue" "Important Message"
ansi_styled "underline,green" "Click here"
```
