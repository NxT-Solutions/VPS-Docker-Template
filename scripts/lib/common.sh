#!/usr/bin/env bash

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

bool_enabled() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | on | ON)
      return 0
      ;;
    0 | false | FALSE | no | NO | off | OFF | '')
      return 1
      ;;
    *)
      die "Expected a boolean value but received: ${1}"
      ;;
  esac
}

resolve_path() {
  local input_path="$1"
  local base_dir="${2:-$PWD}"

  if [[ "$input_path" = /* ]]; then
    printf '%s\n' "$input_path"
    return 0
  fi

  printf '%s\n' "$(cd "$base_dir" && cd "$(dirname "$input_path")" && pwd)/$(basename "$input_path")"
}
