#!/usr/bin/env bash
# The subagents a Claude Code conversation is running, one per line:
#   description <tab> tool it last called <tab> seconds since it started
# Claude Code keeps each subagent's <id>.meta.json (description, finished) and
# <id>.jsonl (its transcript) in a subagents/ directory next to the
# conversation's transcript.
#   claude-agents.sh <subagents directory>

agents=$1
compgen -G "$agents/*.jsonl" >/dev/null || exit 0
now=$(date +%s)
# Every transcript's last change, start and path in one stat, since a long
# conversation keeps every subagent it ever ran. One quiet for 15 minutes has
# finished, or was left behind by a crash. Then one jq per meta file, so one
# caught half written hides only its own agent; control characters in a
# description would break the line
while read -r changed born log; do
  [ $((now - changed)) -lt 900 ] || continue
  description=$(jq -r 'select(.finished != true) | "x" + (.description // "agent" | gsub("[[:cntrl:]]"; " "))' "${log%.jsonl}.meta.json" 2>/dev/null)
  [ -n "$description" ] || continue
  tool=$(tail -n 60 "$log" | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .name' 2>/dev/null | tail -1)
  printf '%s\t%s\t%s\n' "${description#x}" "$tool" $((now - born))
done < <(stat -f '%m %B %N' "$agents"/*.jsonl)
