#!/usr/bin/env bash

set -u

input=$(cat)

cache_path="${PROMPTJUICE_CLAUDE_STATUS_CACHE:-$HOME/Library/Application Support/PromptJuice/ClaudeStatus/latest.json}"
delegate_command="${PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND:-}"
parser="${PROMPTJUICE_CLAUDE_STATUSLINE_PARSER:-plutil}"

extract_raw_plutil_expect() {
  local keypath="$1"
  local expected_type="$2"
  [ -x /usr/bin/plutil ] || return 1
  printf '%s' "$input" | /usr/bin/plutil -extract "$keypath" raw -expect "$expected_type" - -n 2>/dev/null
}

extract_raw_plutil_scalar() {
  local keypath="$1"
  shift

  local expected_type value
  for expected_type in "$@"; do
    if value=$(extract_raw_plutil_expect "$keypath" "$expected_type"); then
      printf '%s' "$value"
      return 0
    fi
  done

  return 1
}

trim_value() {
  /usr/bin/awk '{
    value = $0
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    printf "%s", value
  }'
}

json_escape() {
  /usr/bin/perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g; s/([\x00-\x08\x0b\x0c\x0e-\x1f])/sprintf("\\u%04x", ord($1))/eg'
}

normalize_nonnegative_number() {
  /usr/bin/awk -v value="$1" 'BEGIN {
    normalized = value + 0
    if (value ~ /^[[:space:]]*[+]?(([0-9]+([.][0-9]*)?)|([.][0-9]+))([eE][+-]?[0-9]+)?[[:space:]]*$/ && normalized >= 0 && normalized < 1e308) {
      printf "%.15g", normalized
      exit 0
    }
    exit 1
  }'
}

normalize_positive_integer() {
  /usr/bin/awk -v value="$1" 'BEGIN {
    normalized = value + 0
    if (value ~ /^[[:space:]]*[+]?(([0-9]+([.][0-9]*)?)|([.][0-9]+))([eE][+-]?[0-9]+)?[[:space:]]*$/ && normalized > 0 && normalized == int(normalized) && normalized < 2147483647) {
      printf "%d", normalized
      exit 0
    }
    exit 1
  }'
}

normalize_duration() {
  local raw_duration="${1:-}"
  local raw_window="${2:-}"
  local normalized

  if normalized=$(normalize_positive_integer "$raw_duration"); then
    printf '%s' "$normalized"
    return 0
  fi

  if normalized=$(normalize_positive_integer "$raw_window"); then
    printf '%s' "$normalized"
    return 0
  fi

  printf '300'
}

write_payload_atomic() {
  local payload="$1"
  [ -n "$payload" ] || return 1

  local cache_dir temp_file
  cache_dir=$(dirname "$cache_path")
  mkdir -p "$cache_dir" || return 1
  temp_file=$(mktemp "$cache_dir/.latest.json.XXXXXX") || return 1

  if printf '%s\n' "$payload" > "$temp_file"; then
    if ! mv "$temp_file" "$cache_path"; then
      rm -f "$temp_file"
      return 1
    fi
  else
    rm -f "$temp_file"
    return 1
  fi
}

write_promptjuice_cache_plutil() {
  local raw_used raw_resets raw_duration raw_window
  raw_used=$(extract_raw_plutil_scalar "rate_limits.five_hour.used_percentage" string integer float) || return 1
  raw_resets=$(extract_raw_plutil_scalar "rate_limits.five_hour.resets_at" string integer float date) || return 1
  raw_duration=$(extract_raw_plutil_scalar "rate_limits.five_hour.duration_minutes" string integer float) || true
  raw_window=$(extract_raw_plutil_scalar "rate_limits.five_hour.window_minutes" string integer float) || true

  local used resets duration escaped_resets payload
  used=$(normalize_nonnegative_number "$raw_used") || return 1
  resets=$(printf '%s' "$raw_resets" | trim_value)
  [ -n "$resets" ] || return 1
  duration=$(normalize_duration "$raw_duration" "$raw_window")
  escaped_resets=$(printf '%s' "$resets" | json_escape)

  payload='{"rate_limits":{"five_hour":{"used_percentage":'"$used"',"resets_at":"'"$escaped_resets"'","duration_minutes":'"$duration"'}}}'
  write_payload_atomic "$payload"
}

write_promptjuice_cache_jq() {
  command -v jq >/dev/null 2>&1 || return 1

  local payload
  payload=$(
    printf '%s' "$input" | jq -c '
      def numeric:
        if type == "number" then .
        elif type == "string" then try tonumber catch null
        else null
        end;

      (.rate_limits.five_hour // null) as $five
      | select($five != null)
      | ($five.used_percentage | numeric) as $used
      | select($used != null and $used >= 0)
      | select($five.resets_at != null)
      | {
          rate_limits: {
            five_hour: {
              used_percentage: $used,
              resets_at: ($five.resets_at | tostring),
              duration_minutes: (($five.duration_minutes // $five.window_minutes // 300) | numeric)
            }
          }
        }
      | if .rate_limits.five_hour.duration_minutes == null
        then del(.rate_limits.five_hour.duration_minutes)
        else .
        end
    ' 2>/dev/null
  ) || return 1

  [ -n "$payload" ] || return 1

  write_payload_atomic "$payload"
}

write_promptjuice_cache() {
  case "$parser" in
    jq)
      write_promptjuice_cache_jq
      ;;
    auto)
      write_promptjuice_cache_plutil || write_promptjuice_cache_jq
      ;;
    plutil|*)
      write_promptjuice_cache_plutil
      ;;
  esac
}

run_delegate() {
  if [ -n "$delegate_command" ]; then
    printf '%s' "$input" | /bin/bash -lc "$delegate_command"
    return $?
  fi

  if [ -f "$HOME/.claude/statusline-command.sh" ]; then
    printf '%s' "$input" | /bin/bash "$HOME/.claude/statusline-command.sh"
    return $?
  fi

  return 0
}

write_promptjuice_cache
run_delegate
