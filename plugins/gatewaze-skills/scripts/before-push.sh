#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash).
#
# Refuses `git push` and `gh pr create` on a feature branch until the branch
# carries a review stamp written by /gatewaze-skills:review-round. Exit 2
# blocks the command and shows the message to the agent.
#
# Allowed without a stamp: pushes on main/master, detached HEAD, --dry-run,
# --delete, --tags, and any command carrying GW_REVIEW_SKIP=1 (or that variable
# set in the environment). The skip is for humans and emergencies; CLAUDE.md
# requires saying so when it is used.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cmd=$(hook_command)
[ -n "$cmd" ] || exit 0

is_push=0; is_pr=0
printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])git([[:space:]]+(-C|-c|--git-dir=?)[[:space:]]*[^[:space:]]*)*[[:space:]]+push([[:space:]]|$)' && is_push=1
printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' && is_pr=1
[ "$is_push" = 1 ] || [ "$is_pr" = 1 ] || exit 0

if [ "${GW_REVIEW_SKIP:-}" = "1" ] || printf '%s' "$cmd" | grep -q 'GW_REVIEW_SKIP=1'; then
  exit 0
fi
if [ "$is_push" = 1 ] && printf '%s' "$cmd" | grep -Eq -- '--dry-run|--delete|[[:space:]]-d[[:space:]]|--tags'; then
  exit 0
fi

dir=$(hook_git_dir "$cmd")
repo_opted_in "$dir" || exit 0
g() { git -C "$dir" "$@"; }

branch=$(g symbolic-ref --short -q HEAD) || exit 0
case "$branch" in main|master) exit 0 ;; esac

refuse() {
  {
    echo "Review gate: refusing '$1' on branch '$branch'."
    echo "$2"
    echo "Run /gatewaze-skills:review-round (then /gatewaze-skills:preflight) and try again."
    echo "Emergency bypass for humans: prefix the command with GW_REVIEW_SKIP=1 and say so explicitly. CI still runs every check."
  } >&2
  exit 2
}

what="git push"; [ "$is_pr" = 1 ] && what="gh pr create"
stamp=$(stamp_path "$dir") || exit 0
[ -f "$stamp" ] || refuse "$what" "No review stamp exists for this branch. The branch has not had its review round."

reviewed=$(head -n1 "$stamp" | tr -d '[:space:]')
g cat-file -e "${reviewed}^{commit}" 2>/dev/null || refuse "$what" "The review stamp points at a commit ($reviewed) that no longer exists."
g merge-base --is-ancestor "$reviewed" HEAD 2>/dev/null || refuse "$what" "The branch was rewritten after the review round (reviewed ${reviewed:0:10} is no longer an ancestor of HEAD)."

if g rev-parse --verify -q origin/main >/dev/null 2>&1 && g merge-base --is-ancestor "$reviewed" origin/main 2>/dev/null; then
  refuse "$what" "The review stamp is stale: reviewed ${reviewed:0:10} is already on origin/main, so this branch's own commits have not been reviewed."
fi

offenders=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  subj=${line#* }
  is_gate_exempt_subject "$subj" || offenders="${offenders}  ${line}"$'\n'
done < <(g log --format='%h %s' "${reviewed}..HEAD")

if [ -n "$offenders" ]; then
  refuse "$what" "Commits after the reviewed SHA ${reviewed:0:10} are not review or preflight fix commits (subject must start with <type>(review): or <type>(preflight):):"$'\n'"$offenders"
fi

exit 0
