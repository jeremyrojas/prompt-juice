#!/usr/bin/env bash

set -u

input=$(cat)

cache_path="${PROMPTJUICE_CLAUDE_STATUS_CACHE:-$HOME/Library/Application Support/PromptJuice/ClaudeStatus/latest.json}"
delegate_command="${PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND:-}"

write_promptjuice_cache() {
  command -v jq >/dev/null 2>&1 || return 0

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
  ) || return 0

  [ -n "$payload" ] || return 0

  local cache_dir temp_file
  cache_dir=$(dirname "$cache_path")
  mkdir -p "$cache_dir" || return 0
  temp_file=$(mktemp "$cache_dir/.latest.json.XXXXXX") || return 0

  if printf '%s\n' "$payload" > "$temp_file"; then
    mv "$temp_file" "$cache_path" || rm -f "$temp_file"
  else
    rm -f "$temp_file"
  fi
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
