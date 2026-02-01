# DateTime Functions

Date/time parsing, formatting, and arithmetic.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## DateTime Functions (datetime.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `now` | `now` | `now` | `1705312896` (Unix timestamp) |
| `now_ms` | `now_ms` | `now_ms` | `1705312896123` |
| `now_iso` | `now_iso` | `now_iso` | `2024-01-15T10:30:00-0500` |
| `now_rfc2822` | `now_rfc2822` | `now_rfc2822` | `Mon, 15 Jan 2024 10:30:00 -0500` |
| `parse_iso` | `parse_iso "iso_string"` | `parse_iso "2024-01-15T10:30:00Z"` | `1705312200` |
| `parse_date` | `parse_date "date_string"` | `parse_date "2024-01-15"` | `1705276800` |
| `format_epoch` | `format_epoch epoch "format"` | `format_epoch 1705312896 "%Y-%m-%d"` | `2024-01-15` |
| `format_iso` | `format_iso [epoch]` | `format_iso` | `2024-01-15T10:30:00Z` |
| `format_date` | `format_date [epoch]` | `format_date` | `2024-01-15` |
| `format_time` | `format_time [epoch]` | `format_time` | `10:30:00` |
| `format_relative` | `format_relative epoch` | `format_relative $(($(now)-3600))` | `1 hour ago` |
| `date_add` | `date_add epoch "duration"` | `date_add $(now) "2d"` | (epoch + 2 days) |
| `date_subtract` | `date_subtract epoch "duration"` | `date_subtract $(now) "1w"` | (epoch - 1 week) |
| `date_diff` | `date_diff epoch1 epoch2` | `date_diff 1705312896 1705226496` | `86400` (seconds) |
| `date_diff_human` | `date_diff_human epoch1 epoch2` | `date_diff_human $e1 $e2` | `1 day, 2 hours` |
| `year` | `year [epoch]` | `year` | `2024` |
| `month` | `month [epoch]` | `month` | `1` |
| `day` | `day [epoch]` | `day` | `15` |
| `day_of_week` | `day_of_week [epoch]` | `day_of_week` | `Monday` |
| `is_weekend` | `is_weekend [epoch]` | `is_weekend` | (returns 0/1) |
| `is_weekday` | `is_weekday [epoch]` | `is_weekday` | (returns 0/1) |
| `is_leap_year` | `is_leap_year year` | `is_leap_year 2024` | (returns 0/1) |
| `start_of_day` | `start_of_day [epoch]` | `start_of_day` | (midnight epoch) |
| `end_of_day` | `end_of_day [epoch]` | `end_of_day` | (23:59:59 epoch) |
| `start_of_month` | `start_of_month [epoch]` | `start_of_month` | (first day epoch) |
| `end_of_month` | `end_of_month [epoch]` | `end_of_month` | (last day epoch) |

---

## Quick Patterns

### Get Current Time
```bash
# Get current time
echo "Now: $(now_iso)"
echo "Epoch: $(now)"
```

### Time Arithmetic
```bash
tomorrow=$(date_add $(now) "1d")
last_week=$(date_subtract $(now) "1w")
```

### Human-Readable Diff
```bash
echo "$(format_relative $last_week)"  # "1 week ago"
```

### Date Formatting
```bash
# Custom format
format_epoch $(now) "%Y-%m-%d %H:%M:%S"

# Standard formats
format_date   # 2024-01-15
format_time   # 10:30:00
format_iso    # 2024-01-15T10:30:00Z
```

### Day Calculations
```bash
# Check if weekend
if is_weekend; then
    echo "It's the weekend!"
fi

# Get day info
echo "Day: $(day_of_week)"  # Monday
echo "Year: $(year)"        # 2024
```

### Duration Formats

Duration strings for `date_add` and `date_subtract`:
- `1s` - seconds
- `1m` - minutes
- `1h` - hours
- `1d` - days
- `1w` - weeks
