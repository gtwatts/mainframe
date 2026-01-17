#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/semver.sh - Semantic Versioning Library
# =============================================================================
# Description: Parse, compare, and manipulate semantic versions
# Category:    Library
# WOW Factor:  9/10
# Spec:        https://semver.org/spec/v2.0.0.html
# Inspired by: https://github.com/cloudflare/semver_bash
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SEMVER_LOADED:-}" ]] && return 0
readonly _MAINFRAME_SEMVER_LOADED=1

# =============================================================================
# GLOBAL VARIABLES (set by semver_parse)
# =============================================================================

SEMVER_MAJOR=""
SEMVER_MINOR=""
SEMVER_PATCH=""
SEMVER_PRERELEASE=""
SEMVER_BUILD=""

# =============================================================================
# PARSING
# =============================================================================

# Parse semantic version string
# Usage: semver_parse "1.2.3-alpha.1+build.123"
# Sets: SEMVER_MAJOR, SEMVER_MINOR, SEMVER_PATCH, SEMVER_PRERELEASE, SEMVER_BUILD
semver_parse() {
    local version="$1"

    # Regex for semver (with optional v prefix)
    local RE='^[vV]?([0-9]+)\.([0-9]+)\.([0-9]+)(-([0-9A-Za-z.-]+))?(\+([0-9A-Za-z.-]+))?$'

    if [[ $version =~ $RE ]]; then
        SEMVER_MAJOR="${BASH_REMATCH[1]}"
        SEMVER_MINOR="${BASH_REMATCH[2]}"
        SEMVER_PATCH="${BASH_REMATCH[3]}"
        SEMVER_PRERELEASE="${BASH_REMATCH[5]}"
        SEMVER_BUILD="${BASH_REMATCH[7]}"
        return 0
    fi

    # Clear variables on parse failure
    SEMVER_MAJOR=""
    SEMVER_MINOR=""
    SEMVER_PATCH=""
    SEMVER_PRERELEASE=""
    SEMVER_BUILD=""
    return 1
}

# Check if string is valid semver
# Usage: semver_valid "1.2.3" && echo "valid"
semver_valid() {
    local version="$1"
    local RE='^[vV]?([0-9]+)\.([0-9]+)\.([0-9]+)(-([0-9A-Za-z.-]+))?(\+([0-9A-Za-z.-]+))?$'
    [[ $version =~ $RE ]]
}

# Normalize version (remove v prefix, ensure all parts)
# Usage: semver_normalize "v1.2"  # Returns "1.2.0"
semver_normalize() {
    local version="$1"

    # Remove v/V prefix
    version="${version#v}"
    version="${version#V}"

    # Parse what we can
    local IFS='.-+'
    read -ra parts <<< "$version"

    local major="${parts[0]:-0}"
    local minor="${parts[1]:-0}"
    local patch="${parts[2]:-0}"

    printf '%d.%d.%d\n' "$major" "$minor" "$patch"
}

# =============================================================================
# COMPARISON
# =============================================================================

# Compare two semantic versions
# Returns: 0 if equal, 1 if v1 > v2, 2 if v1 < v2
# Usage: semver_compare "1.2.3" "1.2.4"
semver_compare() {
    local v1="$1"
    local v2="$2"

    # Parse first version
    semver_parse "$v1" || return 3
    local v1_major=$SEMVER_MAJOR
    local v1_minor=$SEMVER_MINOR
    local v1_patch=$SEMVER_PATCH
    local v1_pre=$SEMVER_PRERELEASE

    # Parse second version
    semver_parse "$v2" || return 3
    local v2_major=$SEMVER_MAJOR
    local v2_minor=$SEMVER_MINOR
    local v2_patch=$SEMVER_PATCH
    local v2_pre=$SEMVER_PRERELEASE

    # Compare major
    if ((v1_major > v2_major)); then return 1; fi
    if ((v1_major < v2_major)); then return 2; fi

    # Compare minor
    if ((v1_minor > v2_minor)); then return 1; fi
    if ((v1_minor < v2_minor)); then return 2; fi

    # Compare patch
    if ((v1_patch > v2_patch)); then return 1; fi
    if ((v1_patch < v2_patch)); then return 2; fi

    # Compare prerelease (no prerelease > prerelease)
    if [[ -z "$v1_pre" && -n "$v2_pre" ]]; then return 1; fi
    if [[ -n "$v1_pre" && -z "$v2_pre" ]]; then return 2; fi
    if [[ -z "$v1_pre" && -z "$v2_pre" ]]; then return 0; fi

    # Compare prerelease strings lexically
    if [[ "$v1_pre" > "$v2_pre" ]]; then return 1; fi
    if [[ "$v1_pre" < "$v2_pre" ]]; then return 2; fi

    return 0
}

# Check if v1 equals v2
# Usage: semver_eq "1.2.3" "1.2.3" && echo "equal"
semver_eq() {
    semver_compare "$1" "$2"
    [[ $? -eq 0 ]]
}

# Check if v1 not equals v2
# Usage: semver_ne "1.2.3" "1.2.4" && echo "not equal"
semver_ne() {
    semver_compare "$1" "$2"
    [[ $? -ne 0 ]]
}

# Check if v1 > v2
# Usage: semver_gt "1.2.4" "1.2.3" && echo "greater"
semver_gt() {
    semver_compare "$1" "$2"
    [[ $? -eq 1 ]]
}

# Check if v1 >= v2
# Usage: semver_ge "1.2.3" "1.2.3" && echo "greater or equal"
semver_ge() {
    semver_compare "$1" "$2"
    local result=$?
    [[ $result -eq 0 || $result -eq 1 ]]
}

# Check if v1 < v2
# Usage: semver_lt "1.2.3" "1.2.4" && echo "less"
semver_lt() {
    semver_compare "$1" "$2"
    [[ $? -eq 2 ]]
}

# Check if v1 <= v2
# Usage: semver_le "1.2.3" "1.2.3" && echo "less or equal"
semver_le() {
    semver_compare "$1" "$2"
    local result=$?
    [[ $result -eq 0 || $result -eq 2 ]]
}

# =============================================================================
# MANIPULATION
# =============================================================================

# Bump major version
# Usage: semver_bump_major "1.2.3"  # Returns "2.0.0"
semver_bump_major() {
    semver_parse "$1" || return 1
    printf '%d.%d.%d\n' "$((SEMVER_MAJOR + 1))" "0" "0"
}

# Bump minor version
# Usage: semver_bump_minor "1.2.3"  # Returns "1.3.0"
semver_bump_minor() {
    semver_parse "$1" || return 1
    printf '%d.%d.%d\n' "$SEMVER_MAJOR" "$((SEMVER_MINOR + 1))" "0"
}

# Bump patch version
# Usage: semver_bump_patch "1.2.3"  # Returns "1.2.4"
semver_bump_patch() {
    semver_parse "$1" || return 1
    printf '%d.%d.%d\n' "$SEMVER_MAJOR" "$SEMVER_MINOR" "$((SEMVER_PATCH + 1))"
}

# Set prerelease
# Usage: semver_set_prerelease "1.2.3" "alpha.1"  # Returns "1.2.3-alpha.1"
semver_set_prerelease() {
    semver_parse "$1" || return 1
    local prerelease="$2"

    if [[ -n "$prerelease" ]]; then
        printf '%d.%d.%d-%s\n' "$SEMVER_MAJOR" "$SEMVER_MINOR" "$SEMVER_PATCH" "$prerelease"
    else
        printf '%d.%d.%d\n' "$SEMVER_MAJOR" "$SEMVER_MINOR" "$SEMVER_PATCH"
    fi
}

# Set build metadata
# Usage: semver_set_build "1.2.3" "build.123"  # Returns "1.2.3+build.123"
semver_set_build() {
    semver_parse "$1" || return 1
    local build="$2"
    local result

    if [[ -n "$SEMVER_PRERELEASE" ]]; then
        result=$(printf '%d.%d.%d-%s' "$SEMVER_MAJOR" "$SEMVER_MINOR" "$SEMVER_PATCH" "$SEMVER_PRERELEASE")
    else
        result=$(printf '%d.%d.%d' "$SEMVER_MAJOR" "$SEMVER_MINOR" "$SEMVER_PATCH")
    fi

    if [[ -n "$build" ]]; then
        printf '%s+%s\n' "$result" "$build"
    else
        printf '%s\n' "$result"
    fi
}

# Strip prerelease and build
# Usage: semver_release "1.2.3-alpha+build"  # Returns "1.2.3"
semver_release() {
    semver_parse "$1" || return 1
    printf '%d.%d.%d\n' "$SEMVER_MAJOR" "$SEMVER_MINOR" "$SEMVER_PATCH"
}

# =============================================================================
# RANGE CHECKING
# =============================================================================

# Check if version satisfies range (basic)
# Supports: =, >, <, >=, <=, ^, ~
# Usage: semver_satisfies "1.2.3" ">=1.0.0"
semver_satisfies() {
    local version="$1"
    local range="$2"

    # Extract operator and version from range
    local op=""
    local target=""

    if [[ "$range" =~ ^(\^|~|>=|<=|>|<|=)?(.+)$ ]]; then
        op="${BASH_REMATCH[1]:-=}"
        target="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    case "$op" in
        "=")
            semver_eq "$version" "$target"
            ;;
        ">")
            semver_gt "$version" "$target"
            ;;
        "<")
            semver_lt "$version" "$target"
            ;;
        ">=")
            semver_ge "$version" "$target"
            ;;
        "<=")
            semver_le "$version" "$target"
            ;;
        "^")
            # Caret: allows changes that do not modify the left-most non-zero digit
            semver_parse "$target" || return 1
            local t_major=$SEMVER_MAJOR
            local t_minor=$SEMVER_MINOR
            local t_patch=$SEMVER_PATCH

            semver_parse "$version" || return 1

            if ((t_major > 0)); then
                # ^1.2.3 := >=1.2.3 <2.0.0
                [[ $SEMVER_MAJOR -eq $t_major ]] && semver_ge "$version" "$target"
            elif ((t_minor > 0)); then
                # ^0.2.3 := >=0.2.3 <0.3.0
                [[ $SEMVER_MAJOR -eq 0 && $SEMVER_MINOR -eq $t_minor ]] && semver_ge "$version" "$target"
            else
                # ^0.0.3 := >=0.0.3 <0.0.4
                [[ $SEMVER_MAJOR -eq 0 && $SEMVER_MINOR -eq 0 && $SEMVER_PATCH -eq $t_patch ]]
            fi
            ;;
        "~")
            # Tilde: allows patch-level changes
            semver_parse "$target" || return 1
            local t_major=$SEMVER_MAJOR
            local t_minor=$SEMVER_MINOR

            semver_parse "$version" || return 1

            # ~1.2.3 := >=1.2.3 <1.3.0
            [[ $SEMVER_MAJOR -eq $t_major && $SEMVER_MINOR -eq $t_minor ]] && semver_ge "$version" "$target"
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# UTILITY
# =============================================================================

# Get latest version from list
# Usage: semver_latest "1.0.0" "1.2.0" "1.1.0"  # Returns "1.2.0"
semver_latest() {
    local latest="$1"
    shift

    for version in "$@"; do
        if semver_gt "$version" "$latest"; then
            latest="$version"
        fi
    done

    printf '%s\n' "$latest"
}

# Sort versions (ascending)
# Usage: semver_sort "1.2.0" "1.0.0" "1.1.0"  # Returns "1.0.0\n1.1.0\n1.2.0"
semver_sort() {
    local versions=("$@")
    local n=${#versions[@]}

    # Bubble sort
    for ((i=0; i<n; i++)); do
        for ((j=0; j<n-i-1; j++)); do
            if semver_gt "${versions[j]}" "${versions[j+1]}"; then
                local tmp="${versions[j]}"
                versions[j]="${versions[j+1]}"
                versions[j+1]="$tmp"
            fi
        done
    done

    printf '%s\n' "${versions[@]}"
}

# Format version with optional prefix
# Usage: semver_format "1.2.3" "v"  # Returns "v1.2.3"
semver_format() {
    local version="$1"
    local prefix="${2:-}"

    semver_parse "$version" || return 1

    local result="${prefix}${SEMVER_MAJOR}.${SEMVER_MINOR}.${SEMVER_PATCH}"
    [[ -n "$SEMVER_PRERELEASE" ]] && result="${result}-${SEMVER_PRERELEASE}"
    [[ -n "$SEMVER_BUILD" ]] && result="${result}+${SEMVER_BUILD}"

    printf '%s\n' "$result"
}

