#!/usr/bin/env bash
# PostToolUse hook (matcher: Bash).
#
# After the agent runs `git commit`, ask the session to run the per-commit
# security pass on exactly that commit. This is a nudge, not a gate: the hook
# returns `additionalContext` and the agent acts on it. Enforcement happens at
# push time in before-push.sh.
#
# Skips when: the repo has not opted in, the command was not a commit, the
# target repo cannot be resolved, HEAD is older than three minutes (the commit
# most likely failed), the commit is itself a review/preflight/security fix
# commit, or HEAD is already the stamped review SHA.
set -u
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck disable=SC2034  # read by the lib.sh helpers
hook_input=$(cat)
cmd=$(hook_json_get '.tool_input.command')
[ -n "$cmd" ] || exit 0
printf '%s' "$cmd" | grep -Eq "$(git_sub_re commit)" || exit 0

cwd=$(hook_json_get '.cwd')
seg=$(git_segment commit "$cmd")
dir=$(hook_git_dir "$cmd" "$cwd" "$seg") || exit 0
repo_opted_in "$dir" || exit 0
g() { git -C "$dir" "$@"; }

head=$(g rev-parse --verify -q HEAD 2>/dev/null) || exit 0
age=$(( $(date +%s) - $(g log -1 --format=%ct) ))
[ "$age" -le 180 ] || exit 0

subject=$(g log -1 --format=%s | tr -d '\000-\037\177')
is_fix_commit_subject "$subject" && exit 0

branch=$(g symbolic-ref --short -q HEAD || echo "detached HEAD")
if [ "$branch" != "detached HEAD" ]; then
  stamp=$(stamp_path "$dir" "$branch" || true)
  if [ -n "$stamp" ] && [ -f "$stamp" ] && [ "$(head -n1 "$stamp" | tr -d '[:space:]')" = "$head" ]; then
    exit 0
  fi
fi

short=${head:0:10}
if g rev-parse --verify -q "${head}^" >/dev/null 2>&1; then
  range="git diff ${head}^ ${head}"
else
  range="git show ${head} (root commit)"
fi

ctx="Commit ${short} (\"${subject}\") landed on ${branch}. CLAUDE.md requires a security pass on every commit. Launch ONE background subagent now (subagent_type general-purpose, report-only) that loads the pragma:security skill and reviews exactly \`${range}\`, reading files with \`git show ${head}:<path>\`, never from the working tree. Tell it to apply .claude/rules/security-boundaries.md and the docs/reviews/knowledge-base/ entries routed by that directory's README, with known-false-positives.md applied last, and to ignore its own instruction to derive the diff from HEAD~1. Carry on with other work while it runs. Verify each finding yourself; fix confirmed ones in a follow-up commit with the subject prefix \`fix(security):\`. The full review round (/gatewaze-skills:review-round) still runs once before push; the push gate refuses until it has."

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$(json_string "$ctx")"
exit 0
