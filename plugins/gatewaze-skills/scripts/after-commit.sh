#!/usr/bin/env bash
# PostToolUse hook (matcher: Bash).
#
# After the agent runs `git commit`, ask the session to run the per-commit
# security pass on exactly that commit. This is a nudge, not a gate: the hook
# returns `additionalContext` and the agent acts on it. Enforcement happens at
# push time in before-push.sh.
#
# Skips when: the repo has not opted in, the command was not a commit, HEAD is
# older than three minutes (the commit most likely failed), the commit is
# itself a review/preflight/security fix commit, or HEAD is already the
# stamped review SHA.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cmd=$(hook_command)
[ -n "$cmd" ] || exit 0
printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])git([[:space:]]+(-C|-c|--git-dir=?)[[:space:]]*[^[:space:]]*)*[[:space:]]+commit([[:space:]]|$)' || exit 0

dir=$(hook_git_dir "$cmd")
repo_opted_in "$dir" || exit 0
g() { git -C "$dir" "$@"; }

head=$(g rev-parse --verify -q HEAD 2>/dev/null) || exit 0
age=$(( $(date +%s) - $(g log -1 --format=%ct) ))
[ "$age" -le 180 ] || exit 0

subject=$(g log -1 --format=%s)
is_fix_commit_subject "$subject" && exit 0

stamp=$(stamp_path "$dir" || true)
if [ -n "$stamp" ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$head" ]; then
  exit 0
fi

branch=$(g symbolic-ref --short -q HEAD || echo "detached HEAD")
short=${head:0:10}
if g rev-parse --verify -q "${head}^" >/dev/null 2>&1; then
  range="git diff ${head}^ ${head}"
else
  range="git show ${head} (root commit)"
fi

ctx="Commit ${short} (\"${subject}\") landed on ${branch}. CLAUDE.md requires a security pass on every commit. Launch ONE background subagent now (subagent_type general-purpose, report-only) that loads the pragma:security skill and reviews exactly \`${range}\`, reading files with \`git show ${head}:<path>\`, never from the working tree. Tell it to apply .claude/rules/security-boundaries.md and the docs/reviews/knowledge-base/ entries routed by that directory's README, with known-false-positives.md applied last, and to ignore its own instruction to derive the diff from HEAD~1. Carry on with other work while it runs. Verify each finding yourself; fix confirmed ones in a follow-up commit with the subject prefix \`fix(security):\`. The full review round (/gatewaze-skills:review-round) still runs once before push; the push gate refuses until it has."

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$(json_escape "$ctx")"
exit 0
