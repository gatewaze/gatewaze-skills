#!/usr/bin/env bash
# Shared helpers for the gatewaze-skills Claude Code hooks.
#
# Both hooks read the hook event JSON on stdin, pull out the Bash command the
# agent ran (or is about to run), and act only when that command is a git
# commit or a git push. They are opt-in per repo: a repo adopts them by naming
# `/gatewaze-skills:review-round` in its root CLAUDE.md. In any other repo
# both hooks exit 0 without doing anything.
#
# Review stamps live under `<git-dir>/gatewaze-review/<branch>` (one file per
# branch, containing the full SHA the review round covered). `review-round`
# writes the stamp; `before-push.sh` checks it.

# Print the `tool_input.command` string from the hook JSON on stdin.
# Falls back through jq, then python3, then prints nothing.
hook_command() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.tool_input.command // empty' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print((d.get("tool_input") or {}).get("command", ""))
except Exception:
    pass' 2>/dev/null
  else
    cat >/dev/null
  fi
}

# Work out which directory the git command targets. Honours `git -C <dir>` and
# a leading `cd <dir> &&`; otherwise the hook's own cwd (the project root).
hook_git_dir() {
  local cmd="$1" dir=""
  if [[ $cmd =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
    dir=${BASH_REMATCH[1]}
  elif [[ $cmd =~ (^|[\;\&\|][[:space:]]*)cd[[:space:]]+([^[:space:]\;\&\|]+) ]]; then
    dir=${BASH_REMATCH[2]}
  fi
  dir=${dir//\"/}; dir=${dir//\'/}
  printf '%s' "${dir:-.}"
}

# True when the repo at $1 has opted in to the review hooks.
repo_opted_in() {
  local root
  root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -f "$root/CLAUDE.md" ] && grep -q 'gatewaze-skills:review-round' "$root/CLAUDE.md"
}

# Path of the review stamp for the current branch of the repo at $1.
# Prints nothing when HEAD is detached.
stamp_path() {
  local gitdir branch
  gitdir=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  branch=$(git -C "$1" symbolic-ref --short -q HEAD) || return 1
  printf '%s/gatewaze-review/%s' "$gitdir" "${branch//\//__}"
}

# Commit subjects the gate accepts after the reviewed SHA: the single review
# fix commit and any preflight fix commits. The after-commit nudge also skips
# these (and `(security)` fix commits) so a fix never triggers another pass.
is_fix_commit_subject() {
  printf '%s' "$1" | grep -Eq '^[a-z]+\((review|preflight|security)\)'
}

is_gate_exempt_subject() {
  printf '%s' "$1" | grep -Eq '^[a-z]+\((review|preflight)\)'
}

# Escape $1 for use inside a JSON string literal.
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | awk 'BEGIN{ORS="\\n"} {print}' | sed 's/\\n$//'
}
