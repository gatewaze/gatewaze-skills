#!/usr/bin/env bash
# Shared helpers for the gatewaze-skills Claude Code hooks.
#
# Both hooks read the hook event JSON on stdin, pull out the Bash command the
# agent ran (or is about to run), and act only when that command is a git
# commit or a git push. They are opt-in per repo: a repo adopts them by naming
# `/gatewaze-skills:review-round` in its root CLAUDE.md. In any other repo
# both hooks exit 0 without doing anything.
#
# Review stamps live under `<git-dir>/gatewaze-review/<encoded branch>`, one
# file per branch, containing the full SHA the review round covered.
# `review-round` writes the stamp; `before-push.sh` checks it. The stamp is
# not integrity-protected: the agent could write it by hand, which CLAUDE.md
# forbids. The gate exists to stop the step being forgotten, not to resist a
# session that sets out to skip it.

# The raw event JSON. Scripts set this once from stdin.
hook_input=""

# Print one string field of the event. $1 is a jq path such as
# `.tool_input.command`. Falls back through jq, then python3. With neither
# available the raw event text stands in for the command field, so the
# detectors still see the command rather than failing open on an empty string.
hook_json_get() {
  local path="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$hook_input" | jq -r "$path // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$hook_input" | python3 -I -c 'import json, sys
keys = sys.argv[1].strip(".").split(".")
try:
    d = json.load(sys.stdin)
    for k in keys:
        d = d.get(k) if isinstance(d, dict) else None
    print(d if isinstance(d, str) else "")
except Exception:
    pass' "$path" 2>/dev/null
  elif [ "$path" = ".tool_input.command" ]; then
    printf '%s' "$hook_input"
  fi
}

# Regex building blocks (ERE). A git global option may take a value, possibly
# quoted; the subcommand may itself be quoted; a terminator is whitespace,
# a shell operator, or end of string.
GIT_OPTS='([[:space:]]+-[^[:space:]]*([[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]-][^[:space:]]*))?)*'
Q='["'"'"']?'
SUB_TERM='([[:space:];&|)]|$)'

# ERE matching `git [global opts] <subcommand>` where $1 is an ERE for the
# subcommand(s), e.g. `push` or `(commit|merge)`.
git_sub_re() {
  printf '(^|[^[:alnum:]_-])git%s[[:space:]]+%s%s%s%s' "$GIT_OPTS" "$Q" "$1" "$Q" "$SUB_TERM"
}

# ERE matching `gh [global opts] pr create`.
gh_pr_create_re() {
  printf '(^|[^[:alnum:]_-])gh%s[[:space:]]+pr[[:space:]]+create%s' "$GIT_OPTS" "$SUB_TERM"
}

# Print the last `git ... <sub> ...` segment of the command, up to the next
# shell operator. $1 is the subcommand ERE.
git_segment() {
  printf '%s' "$2" | grep -oE "git${GIT_OPTS}[[:space:]]+${Q}$1${Q}[^;&|]*" | tail -1
}

# Strip one layer of matching quotes from $1.
unquote() {
  local v="$1"
  case "$v" in
    \"*\") v=${v#\"}; v=${v%\"} ;;
    \'*\') v=${v#\'}; v=${v%\'} ;;
  esac
  printf '%s' "$v"
}

# Resolve the directory a git command targets, as an absolute path.
#   $1 = command, $2 = the event's cwd (may be empty), $3 = segment (may be
#   empty; when given, a `-C <path>` is read from it rather than the command)
# Honours the last `cd <path>` in the command and a `-C <path>` on the git
# call. Expands a leading `~`. Returns 1 when the path uses shell expansion
# we cannot evaluate, or does not exist, so callers can fail closed.
hook_git_dir() {
  local cmd="$1" base="$2" seg="$3" m cdpath cpath
  [ -n "$base" ] || base=$PWD
  m=$(printf '%s' "$cmd" | grep -oE '(^|[;&|(][[:space:]]*)cd[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|)]+)' | tail -1)
  if [ -n "$m" ]; then
    cdpath=$(printf '%s' "$m" | sed -E 's/^.*cd[[:space:]]+//')
    base=$(resolve_path "$(unquote "$cdpath")" "$base") || return 1
  fi
  m=$(printf '%s' "${seg:-$cmd}" | grep -oE -- '-C[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+)' | tail -1)
  if [ -n "$m" ]; then
    cpath=$(printf '%s' "$m" | sed -E 's/^-C[[:space:]]+//')
    base=$(resolve_path "$(unquote "$cpath")" "$base") || return 1
  fi
  [ -d "$base" ] || return 1
  printf '%s' "$base"
}

# $1 = path, $2 = base for a relative path. Refuses unexpanded shell syntax.
resolve_path() {
  local p="$1"
  # shellcheck disable=SC2088  # the quoted tilde patterns are literal on purpose
  case "$p" in
    *'$'*|*'`'*) return 1 ;;
    '~') p=$HOME ;;
    '~/'*) p="$HOME/${p#\~/}" ;;
    /*) ;;
    *) p="$2/$p" ;;
  esac
  [ -d "$p" ] || return 1
  (cd "$p" && pwd -P)
}

# True when the repo at $1 has opted in to the review hooks.
repo_opted_in() {
  local root
  root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -f "$root/CLAUDE.md" ] && grep -Eq '(^|[^[:alnum:]])/gatewaze-skills:review-round([^[:alnum:]-]|$)' "$root/CLAUDE.md"
}

# Injective encoding of a branch name for use as a file name.
encode_branch() {
  printf '%s' "$1" | sed -e 's/%/%25/g' -e 's#/#%2F#g'
}

# Path of the review stamp for branch $2 of the repo at $1.
stamp_path() {
  local gitdir
  gitdir=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  printf '%s/gatewaze-review/%s' "$gitdir" "$(encode_branch "$2")"
}

# Commit subjects the after-commit nudge skips: review, preflight and
# security fix commits, so a fix never triggers another pass.
is_fix_commit_subject() {
  printf '%s' "$1" | grep -Eq '^[a-z]+\((review|preflight|security)\)!?:'
}

# Commit subjects the push gate accepts after the reviewed SHA.
is_gate_exempt_subject() {
  printf '%s' "$1" | grep -Eq '^[a-z]+\((review|preflight)\)!?:'
}

# Print $1 as a JSON string literal, quotes included.
json_string() {
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg s "$1" '$s'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"
  else
    printf '"%s"' "$(printf '%s' "$1" | tr -d '\000-\037\177' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  fi
}
