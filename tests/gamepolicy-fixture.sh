#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" >> "$ROOT/commands.log"
case "$2" in
  status)
    POLICY="$(cat "$ROOT/policy")"
    if [ "$POLICY" = on ]; then
      printf 'Game mode is \033[0;32mon\033[0;0m.\nGame mode enablement policy is currently disabled. Game mode is forced always on.\n'
    elif [ "$POLICY" = off ]; then
      printf 'Game mode is off.\nGame mode is forced always off.\n'
    else
      printf 'Game mode is off.\nGame mode enablement policy is currently automatic.\n'
    fi
    ;;
  set)
    if [ "$3" = on ] && [ -f "$ROOT/fail-enable" ]; then exit 1; fi
    if [ "$3" != on ] && [ -f "$ROOT/fail-restore" ]; then exit 1; fi
    printf '%s\n' "$3" > "$ROOT/policy"
    if [ "$3" = on ] && [ -f "$ROOT/partial-enable" ]; then exit 1; fi
    ;;
  *) exit 2 ;;
esac
