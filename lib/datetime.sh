#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/datetime.sh - Pure Bash Date/Time Library
# =============================================================================
# Description: Date/time operations without external tools (date, gdate)
# Requires: Bash 4.2+ (for printf '%()T' format)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_DATETIME_LOADED:-}" ]] && return 0

# pure-util.sh owns the canonical dual-shape format_date implementation.
# Load it explicitly so direct `source lib/datetime.sh` users receive the same
# API as users loading through common.sh.
source "${BASH_SOURCE[0]%/*}/pure-util.sh"

readonly _MAINFRAME_DATETIME_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

readonly _DT_SECONDS_PER_MINUTE=60
readonly _DT_SECONDS_PER_HOUR=3600
readonly _DT_SECONDS_PER_DAY=86400
readonly _DT_SECONDS_PER_WEEK=604800
readonly _DT_DAYS_PER_YEAR=365
readonly _DT_DAYS_PER_LEAP_YEAR=366

# Days in each month (non-leap year)
readonly _DT_DAYS_IN_MONTH=(0 31 28 31 30 31 30 31 31 30 31 30 31)

_dt_fmt_utc() {
    local epoch="${1:--1}"
    local format="$2"

    # Historical name notwithstanding, public datetime helpers operate in local
    # time, so boundary/component extraction should match local strftime output.
    if date -r "$epoch" +"$format" 2>/dev/null; then
        return 0
    fi

    if date -d "@$epoch" +"$format" 2>/dev/null; then
        return 0
    fi

    printf "%(${format})T\n" "$epoch"
}

_dt_to_epoch_local() {
    local year="$1" month="$2" day="$3" hour="$4" minute="$5" second="$6"
    local dt
    printf -v dt '%04d-%02d-%02d %02d:%02d:%02d' \
        "$year" "$month" "$day" "$hour" "$minute" "$second"

    if date -j -f '%Y-%m-%d %H:%M:%S' "$dt" '+%s' >/dev/null 2>&1; then
        date -j -f '%Y-%m-%d %H:%M:%S' "$dt" '+%s'
        return 0
    fi

    if date -d "$dt" '+%s' >/dev/null 2>&1; then
        date -d "$dt" '+%s'
        return 0
    fi

    _dt_to_epoch "$year" "$month" "$day" "$hour" "$minute" "$second"
}

# =============================================================================
# CURRENT TIME
# =============================================================================

# Get current Unix timestamp (seconds since epoch)
# Usage: now
now() {
    printf '%(%s)T\n' -1
}

# Get current time in milliseconds (approximation - bash doesn't have sub-second)
# Usage: now_ms
now_ms() {
    printf '%(%s)T000\n' -1
}

# Get current time as ISO 8601 string
# Usage: now_iso
now_iso() {
    printf '%(%Y-%m-%dT%H:%M:%S%z)T\n' -1
}

# Get current time as RFC 2822 string (email format)
# Usage: now_rfc2822
now_rfc2822() {
    printf '%(%a, %d %b %Y %H:%M:%S %z)T\n' -1
}

# =============================================================================
# PARSING
# =============================================================================

# Parse ISO 8601 string to epoch
# Usage: parse_iso "2024-01-15T10:30:00Z"
# Note: Pure bash parsing - handles basic ISO formats
parse_iso() {
    local input="$1"
    local year month day hour minute second
    local has_explicit_tz=0

    # Remove trailing Z if present
    if [[ "$input" == *Z ]]; then
        has_explicit_tz=1
        input="${input%Z}"
    fi

    # Handle timezone offset (+HH:MM or -HH:MM)
    local tz_offset=0
    if [[ "$input" =~ ([+-])([0-9]{2}):?([0-9]{2})$ ]]; then
        has_explicit_tz=1
        local tz_sign="${BASH_REMATCH[1]}"
        local tz_hours="${BASH_REMATCH[2]#0}"  # Remove leading zero
        local tz_mins="${BASH_REMATCH[3]#0}"
        tz_offset=$(( (tz_hours * 60 + tz_mins) * 60 ))
        [[ "$tz_sign" == "+" ]] && tz_offset=$(( -tz_offset ))
        input="${input%[+-]*}"
    fi

    # Parse date and time components
    if [[ "$input" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2}) ]]; then
        year="${BASH_REMATCH[1]}"
        month="${BASH_REMATCH[2]#0}"
        day="${BASH_REMATCH[3]#0}"
        hour="${BASH_REMATCH[4]#0}"
        minute="${BASH_REMATCH[5]#0}"
        second="${BASH_REMATCH[6]#0}"
    elif [[ "$input" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2})$ ]]; then
        year="${BASH_REMATCH[1]}"
        month="${BASH_REMATCH[2]#0}"
        day="${BASH_REMATCH[3]#0}"
        hour="${BASH_REMATCH[4]#0}"
        minute="${BASH_REMATCH[5]#0}"
        second=0
    elif [[ "$input" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
        year="${BASH_REMATCH[1]}"
        month="${BASH_REMATCH[2]#0}"
        day="${BASH_REMATCH[3]#0}"
        hour=0
        minute=0
        second=0
    else
        printf '%s\n' "0"
        return 1
    fi

    local epoch
    if (( has_explicit_tz )); then
        epoch=$(_dt_to_epoch "$year" "$month" "$day" "$hour" "$minute" "$second")
    else
        epoch=$(_dt_to_epoch_local "$year" "$month" "$day" "$hour" "$minute" "$second")
    fi
    echo $(( epoch + tz_offset ))
}

# Parse date string to epoch (YYYY-MM-DD)
# Usage: parse_date "2024-01-15"
parse_date() {
    local input="$1"

    if [[ "$input" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
        local year="${BASH_REMATCH[1]}"
        local month="${BASH_REMATCH[2]#0}"
        local day="${BASH_REMATCH[3]#0}"
        _dt_to_epoch_local "$year" "$month" "$day" 0 0 0
    else
        printf '%s\n' "0"
        return 1
    fi
}

# Parse datetime string to epoch (YYYY-MM-DD HH:MM:SS)
# Usage: parse_datetime "2024-01-15 10:30:00"
parse_datetime() {
    local input="$1"

    if [[ "$input" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})\ ([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
        local year="${BASH_REMATCH[1]}"
        local month="${BASH_REMATCH[2]#0}"
        local day="${BASH_REMATCH[3]#0}"
        local hour="${BASH_REMATCH[4]#0}"
        local minute="${BASH_REMATCH[5]#0}"
        local second="${BASH_REMATCH[6]#0}"
        _dt_to_epoch_local "$year" "$month" "$day" "$hour" "$minute" "$second"
    elif [[ "$input" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})\ ([0-9]{2}):([0-9]{2})$ ]]; then
        local year="${BASH_REMATCH[1]}"
        local month="${BASH_REMATCH[2]#0}"
        local day="${BASH_REMATCH[3]#0}"
        local hour="${BASH_REMATCH[4]#0}"
        local minute="${BASH_REMATCH[5]#0}"
        _dt_to_epoch_local "$year" "$month" "$day" "$hour" "$minute" 0
    else
        printf '%s\n' "0"
        return 1
    fi
}

# Internal: Convert date components to epoch
# Usage: _dt_to_epoch year month day hour minute second
_dt_to_epoch() {
    local year=$1 month=$2 day=$3 hour=$4 minute=$5 second=$6

    # Calculate days from year 1970
    local total_days=0
    local y

    # Add days for complete years
    for ((y = 1970; y < year; y++)); do
        if _dt_is_leap_year "$y"; then
            ((total_days += _DT_DAYS_PER_LEAP_YEAR))
        else
            ((total_days += _DT_DAYS_PER_YEAR))
        fi
    done

    # Handle years before 1970
    for ((y = 1969; y >= year; y--)); do
        if _dt_is_leap_year "$y"; then
            ((total_days -= _DT_DAYS_PER_LEAP_YEAR))
        else
            ((total_days -= _DT_DAYS_PER_YEAR))
        fi
    done

    # Add days for complete months
    local m
    for ((m = 1; m < month; m++)); do
        ((total_days += ${_DT_DAYS_IN_MONTH[m]}))
        # February in leap year
        if ((m == 2)) && _dt_is_leap_year "$year"; then
            ((total_days++))
        fi
    done

    # Add remaining days (minus 1 since day 1 is start of day)
    ((total_days += day - 1))

    # Convert to seconds and add time
    local epoch=$(( total_days * _DT_SECONDS_PER_DAY + hour * _DT_SECONDS_PER_HOUR + minute * _DT_SECONDS_PER_MINUTE + second ))
    printf '%d\n' "$epoch"
}

# Internal: Check if year is a leap year
_dt_is_leap_year() {
    local year=$1
    (( (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0) ))
}

# =============================================================================
# FORMATTING
# =============================================================================

# Format epoch with strftime format
# Usage: format_epoch "epoch" "format"
# If epoch not provided, uses current time
format_epoch() {
    local epoch="${1:--1}"
    local format="${2:-%Y-%m-%d %H:%M:%S}"
    printf "%($format)T\n" "$epoch"
}

# Format epoch as ISO 8601
# Usage: format_iso "epoch"
format_iso() {
    local epoch="${1:--1}"
    printf '%(%Y-%m-%dT%H:%M:%S%z)T\n' "$epoch"
}

# Format epoch as time (HH:MM:SS)
# Usage: format_time "epoch"
format_time() {
    local epoch="${1:--1}"
    printf '%(%H:%M:%S)T\n' "$epoch"
}

# Format epoch as datetime (YYYY-MM-DD HH:MM:SS)
# Usage: format_datetime "epoch"
format_datetime() {
    local epoch="${1:--1}"
    printf '%(%Y-%m-%d %H:%M:%S)T\n' "$epoch"
}

# Format epoch as relative time ("2 hours ago", "in 3 days")
# Usage: format_relative "epoch"
format_relative() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)

    local current
    current=$(now)
    local diff=$(( current - epoch ))
    local abs_diff=${diff#-}
    local prefix="" suffix=""

    if ((diff > 0)); then
        suffix=" ago"
    elif ((diff < 0)); then
        prefix="in "
        diff=$(( -diff ))
    else
        printf '%s\n' "just now"
        return
    fi

    local value unit

    if ((abs_diff < _DT_SECONDS_PER_MINUTE)); then
        value=$abs_diff
        unit="second"
    elif ((abs_diff < _DT_SECONDS_PER_HOUR)); then
        value=$(( abs_diff / _DT_SECONDS_PER_MINUTE ))
        unit="minute"
    elif ((abs_diff < _DT_SECONDS_PER_DAY)); then
        value=$(( abs_diff / _DT_SECONDS_PER_HOUR ))
        unit="hour"
    elif ((abs_diff < _DT_SECONDS_PER_WEEK)); then
        value=$(( abs_diff / _DT_SECONDS_PER_DAY ))
        unit="day"
    elif ((abs_diff < _DT_SECONDS_PER_DAY * 30)); then
        value=$(( abs_diff / _DT_SECONDS_PER_WEEK ))
        unit="week"
    elif ((abs_diff < _DT_SECONDS_PER_DAY * 365)); then
        value=$(( abs_diff / (_DT_SECONDS_PER_DAY * 30) ))
        unit="month"
    else
        value=$(( abs_diff / (_DT_SECONDS_PER_DAY * 365) ))
        unit="year"
    fi

    # Pluralize
    ((value != 1)) && unit="${unit}s"

    printf '%s%d %s%s\n' "$prefix" "$value" "$unit" "$suffix"
}

# =============================================================================
# ARITHMETIC
# =============================================================================

# Parse duration string to seconds
# Usage: _dt_parse_duration "2d3h30m"
_dt_parse_duration() {
    local duration="$1"
    local total=0
    local num=""
    local i char

    for ((i = 0; i < ${#duration}; i++)); do
        char="${duration:i:1}"
        case "$char" in
            [0-9])
                num+="$char"
                ;;
            w|W)
                ((total += ${num:-0} * _DT_SECONDS_PER_WEEK))
                num=""
                ;;
            d|D)
                ((total += ${num:-0} * _DT_SECONDS_PER_DAY))
                num=""
                ;;
            h|H)
                ((total += ${num:-0} * _DT_SECONDS_PER_HOUR))
                num=""
                ;;
            m|M)
                ((total += ${num:-0} * _DT_SECONDS_PER_MINUTE))
                num=""
                ;;
            s|S)
                ((total += ${num:-0}))
                num=""
                ;;
        esac
    done

    # Treat any remaining number as seconds
    ((total += ${num:-0}))

    printf '%d\n' "$total"
}

# Add duration to epoch
# Usage: date_add "epoch" "duration"  (duration: "2d", "3h", "30m", "1w")
date_add() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)
    local duration="$2"

    local seconds
    seconds=$(_dt_parse_duration "$duration")
    printf '%d\n' $(( epoch + seconds ))
}

# Subtract duration from epoch
# Usage: date_subtract "epoch" "duration"
date_subtract() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)
    local duration="$2"

    local seconds
    seconds=$(_dt_parse_duration "$duration")
    printf '%d\n' $(( epoch - seconds ))
}

# Get difference between two epochs in seconds
# Usage: date_diff "epoch1" "epoch2"
date_diff() {
    local epoch1="${1:-0}"
    local epoch2="${2:-0}"
    local diff=$(( epoch2 - epoch1 ))
    printf '%d\n' "${diff#-}"
}

# Get human-readable difference between two epochs
# Usage: date_diff_human "epoch1" "epoch2"
date_diff_human() {
    local epoch1="${1:-0}"
    local epoch2="${2:-0}"
    local diff=$(( epoch2 - epoch1 ))
    local abs_diff=${diff#-}

    local days=$(( abs_diff / _DT_SECONDS_PER_DAY ))
    local remaining=$(( abs_diff % _DT_SECONDS_PER_DAY ))
    local hours=$(( remaining / _DT_SECONDS_PER_HOUR ))
    remaining=$(( remaining % _DT_SECONDS_PER_HOUR ))
    local minutes=$(( remaining / _DT_SECONDS_PER_MINUTE ))
    local seconds=$(( remaining % _DT_SECONDS_PER_MINUTE ))

    local parts=()
    ((days > 0)) && parts+=("$days day$( ((days != 1)) && echo "s" )")
    ((hours > 0)) && parts+=("$hours hour$( ((hours != 1)) && echo "s" )")
    ((minutes > 0)) && parts+=("$minutes minute$( ((minutes != 1)) && echo "s" )")
    ((seconds > 0 || ${#parts[@]} == 0)) && parts+=("$seconds second$( ((seconds != 1)) && echo "s" )")

    # Join with commas
    local result=""
    local i
    for ((i = 0; i < ${#parts[@]}; i++)); do
        ((i > 0)) && result+=", "
        result+="${parts[i]}"
    done

    printf '%s\n' "$result"
}

# =============================================================================
# COMPONENTS
# =============================================================================

# Extract year from epoch
# Usage: year "epoch"
year() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)
    _dt_fmt_utc "$epoch" '%Y'
}

# Extract month from epoch (1-12)
# Usage: month "epoch"
month() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)
    local m
    m=$(_dt_fmt_utc "$epoch" '%m')
    printf '%d\n' "${m#0}"
}

# Extract day from epoch (1-31)
# Usage: day "epoch"
day() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)
    local d
    d=$(_dt_fmt_utc "$epoch" '%d')
    printf '%d\n' "${d#0}"
}

# Extract hour from epoch (0-23)
# Usage: hour "epoch"
hour() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)
    local h
    h=$(_dt_fmt_utc "$epoch" '%H')
    printf '%d\n' "${h#0}"
}

# Extract minute from epoch (0-59)
# Usage: minute "epoch"
minute() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)
    local m
    m=$(_dt_fmt_utc "$epoch" '%M')
    printf '%d\n' "${m#0}"
}

# Extract second from epoch (0-59)
# Usage: second "epoch"
second() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)
    local s
    s=$(_dt_fmt_utc "$epoch" '%S')
    printf '%d\n' "${s#0}"
}

# Get day of week name
# Usage: day_of_week "epoch"
day_of_week() {
    local epoch="${1:--1}"
    _dt_fmt_utc "$epoch" '%A'
}

# Get day of year (1-366)
# Usage: day_of_year "epoch"
day_of_year() {
    local epoch="${1:--1}"
    local doy
    doy=$(_dt_fmt_utc "$epoch" '%j')
    printf '%d\n' "${doy#0}"
}

# Get week of year (1-53)
# Usage: week_of_year "epoch"
week_of_year() {
    local epoch="${1:--1}"
    local week
    week=$(_dt_fmt_utc "$epoch" '%V')
    printf '%d\n' "${week#0}"
}

# Check if year is a leap year
# Usage: is_leap_year "year"
is_leap_year() {
    local year="$1"
    _dt_is_leap_year "$year"
}

# =============================================================================
# COMPARISONS
# =============================================================================

# Check if epoch1 is before epoch2
# Usage: is_before "epoch1" "epoch2"
is_before() {
    local epoch1="${1:-0}"
    local epoch2="${2:-0}"
    ((epoch1 < epoch2))
}

# Check if epoch1 is after epoch2
# Usage: is_after "epoch1" "epoch2"
is_after() {
    local epoch1="${1:-0}"
    local epoch2="${2:-0}"
    ((epoch1 > epoch2))
}

# Check if two epochs are on the same calendar day
# Usage: is_same_day "epoch1" "epoch2"
is_same_day() {
    local epoch1="${1:-0}"
    local epoch2="${2:-0}"

    local date1 date2
    printf -v date1 '%(%Y-%m-%d)T' "$epoch1"
    printf -v date2 '%(%Y-%m-%d)T' "$epoch2"

    [[ "$date1" == "$date2" ]]
}

# Check if epoch falls on a weekend (Saturday or Sunday)
# Usage: is_weekend "epoch"
is_weekend() {
    local epoch="${1:--1}"
    local dow
    dow=$(_dt_fmt_utc "$epoch" '%u')  # 1=Monday, 7=Sunday
    ((dow == 6 || dow == 7))
}

# Check if epoch falls on a weekday (Monday-Friday)
# Usage: is_weekday "epoch"
is_weekday() {
    local epoch="${1:--1}"
    local dow
    dow=$(_dt_fmt_utc "$epoch" '%u')  # 1=Monday, 7=Sunday
    ((dow >= 1 && dow <= 5))
}

# =============================================================================
# BOUNDARIES
# =============================================================================

# Get start of day (midnight) for given epoch
# Usage: start_of_day "epoch"
start_of_day() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)

    local y m d
    y=$(year "$epoch")
    m=$(month "$epoch")
    d=$(day "$epoch")

    _dt_to_epoch_local "$y" "$m" "$d" 0 0 0
}

# Get end of day (23:59:59) for given epoch
# Usage: end_of_day "epoch"
end_of_day() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)

    local y m d
    y=$(year "$epoch")
    m=$(month "$epoch")
    d=$(day "$epoch")

    _dt_to_epoch_local "$y" "$m" "$d" 23 59 59
}

# Get start of month for given epoch
# Usage: start_of_month "epoch"
start_of_month() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)

    local y m
    y=$(year "$epoch")
    m=$(month "$epoch")

    _dt_to_epoch_local "$y" "$m" 1 0 0 0
}

# Get end of month for given epoch
# Usage: end_of_month "epoch"
end_of_month() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)

    local y m
    y=$(year "$epoch")
    m=$(month "$epoch")

    # Get days in this month
    local dim
    dim=$(days_in_month "$y" "$m")

    _dt_to_epoch_local "$y" "$m" "$dim" 23 59 59
}

# Get start of year for given epoch
# Usage: start_of_year "epoch"
start_of_year() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)

    local y
    y=$(year "$epoch")

    _dt_to_epoch_local "$y" 1 1 0 0 0
}

# Get end of year for given epoch
# Usage: end_of_year "epoch"
end_of_year() {
    local epoch="${1:--1}"
    [[ "$epoch" == "-1" ]] && epoch=$(now)

    local y
    y=$(year "$epoch")

    local end
    end=$(_dt_to_epoch_local "$y" 12 31 23 59 59)
    printf '%d\n' "$end"
}

# =============================================================================
# ADDITIONAL UTILITIES
# =============================================================================

# Get days in a specific month
# Usage: days_in_month "year" "month"
days_in_month() {
    local year="$1"
    local month="$2"

    local days=${_DT_DAYS_IN_MONTH[month]}
    if ((month == 2)) && _dt_is_leap_year "$year"; then
        ((days++))
    fi
    printf '%d\n' "$days"
}

# Get the epoch for a specific date/time
# Usage: make_datetime "year" "month" "day" ["hour"] ["minute"] ["second"]
make_datetime() {
    local year="$1"
    local month="$2"
    local day="$3"
    local hour="${4:-0}"
    local minute="${5:-0}"
    local second="${6:-0}"

    _dt_to_epoch_local "$year" "$month" "$day" "$hour" "$minute" "$second"
}

# Get timezone offset in seconds
# Usage: tz_offset
tz_offset() {
    local offset
    printf -v offset '%(%z)T' -1

    # Parse +HHMM or -HHMM format
    local sign="${offset:0:1}"
    local hours="${offset:1:2}"
    local mins="${offset:3:2}"

    hours="${hours#0}"
    mins="${mins#0}"
    [[ -z "$hours" ]] && hours=0
    [[ -z "$mins" ]] && mins=0

    local total=$(( hours * _DT_SECONDS_PER_HOUR + mins * _DT_SECONDS_PER_MINUTE ))
    [[ "$sign" == "-" ]] && total=$(( -total ))

    printf '%d\n' "$total"
}

# Get timezone name
# Usage: tz_name
tz_name() {
    printf '%(%Z)T\n' -1
}

# Check if currently in DST
# Usage: is_dst
is_dst() {
    local std winter summer

    # Compare January (winter) and July (summer) timezone names
    # This is a heuristic - DST rules vary by locale
    printf -v winter '%(%Z)T' 0
    printf -v summer '%(%Z)T' 15768000  # ~6 months later

    local current
    printf -v current '%(%Z)T' -1

    # If current matches summer and differs from winter, likely DST
    [[ "$current" == "$summer" && "$winter" != "$summer" ]]
}
