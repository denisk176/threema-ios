#!/bin/bash
# Shared color and logging helpers for Threema shell scripts.
#
# Source from any shell script:
#     source "$(git rev-parse --show-toplevel)/scripts/lib/colors.sh"
#
# Each caller can set LOG_TAG before sourcing (or before the first log call)
# to prefix every line with "[<tag>] " so output from different scripts is
# greppable when interleaved.
#
# Colors are auto-disabled when stdout is not a terminal or when NO_COLOR is
# set (see https://no-color.org/), so log output stays clean in CI/log files.

# Guard against being sourced twice in the same shell.
[ -n "${_THREEMA_COLORS_LOADED:-}" ] && return 0
_THREEMA_COLORS_LOADED=1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    NORMAL=$'\033[0m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    UNDERLINE=$'\033[4m'
    BLACK=$'\033[30m'
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    BLUE=$'\033[34m'
    MAGENTA=$'\033[35m'
    CYAN=$'\033[36m'
    GRAY=$'\033[90m'
    WHITE=$'\033[97m'
    LIGHT_RED=$'\033[91m'
    LIGHT_GREEN=$'\033[92m'
    LIGHT_YELLOW=$'\033[93m'
else
    NORMAL=''; BOLD=''; DIM=''; UNDERLINE=''
    BLACK=''; RED=''; GREEN=''; YELLOW=''; BLUE=''
    MAGENTA=''; CYAN=''; GRAY=''; WHITE=''
    LIGHT_RED=''; LIGHT_GREEN=''; LIGHT_YELLOW=''
fi
NC="$NORMAL"

# Text glyphs used as log-line markers. Plain Unicode, no emoji, so they
# render cleanly in any monospaced terminal font without falling back to
# variable-width emoji presentation.
CHECK="✓"
CROSS="✗"
ARROW="→"
BULLET="•"
WARN_MARK="!"

# Optional caller-supplied tag. When set, every log line is prefixed with
# "[<tag>] " in dim style for grep-ability across interleaved script output.
: "${LOG_TAG:=}"

_log_prefix() {
    [ -n "$LOG_TAG" ] || return 0
    printf '%s[%s]%s ' "$DIM" "$LOG_TAG" "$NC"
}

info()    { printf '%s%s%s%s %s\n' "$(_log_prefix)" "$BLUE"   "$ARROW"     "$NC" "$1"; }
success() { printf '%s%s%s%s %s\n' "$(_log_prefix)" "$GREEN"  "$CHECK"     "$NC" "$1"; }
warn()    { printf '%s%s%s%s %s\n' "$(_log_prefix)" "$YELLOW" "$WARN_MARK" "$NC" "$1" >&2; }
error()   { printf '%s%s%s%s %s\n' "$(_log_prefix)" "$RED"    "$CROSS"     "$NC" "$1" >&2; }
step()    { printf '%s%s%s %s%s%s\n' "$(_log_prefix)" "$CYAN" "$ARROW" "$BOLD" "$1" "$NC"; }
dim_log() { printf '%s%s%s%s\n' "$(_log_prefix)" "$DIM" "$1" "$NC"; }
