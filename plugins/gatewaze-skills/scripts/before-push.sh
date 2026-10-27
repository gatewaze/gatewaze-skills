#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash).
#
# Refuses `git push` and `gh pr create` on a feature branch until the branch
# carries a review stamp written by /gatewaze-skills:review-round. Exit 2
# blocks the command and shows the message to the agent.
#
# Allowed without a stamp: pushes of main/master, detached HEAD, --dry-run,
# --delete / -d / a `:dst` delete refspec, --tags, and any command carrying
# GW_REVIEW_SKIP=1 as its own word (or that variable set in the environment).
# The skip is for humans and emergencies; CLAUDE.md requires saying so when it
# is used.
#
# Refused outright, independent of the stamp: a push combined in one command
# with a git command that changes the repo (commit, switch, merge...), since
# the hook sees the repo before those run; --all / --mirror; a refspec whose
# source is not a local branch; and a `cd` or `-C` path the hook cannot
# resolve. Each message says what to run instead.
set -u
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck disable=SC2034  # read by the lib.sh helpers
hook_input=$(cat)
cmd=$(hook_json_get '.tool_input.command')
[ -n "$cmd" ] || exit 0

is_push=0; is_pr=0
printf '%s' "$cmd" | grep -Eq "$(git_sub_re push)" && is_push=1
printf '%s' "$cmd" | grep -Eq "$(gh_pr_create_re)" && is_pr=1
[ "$is_push" = 1 ] || [ "$is_pr" = 1 ] || exit 0

if [ "${GW_REVIEW_SKIP:-}" = "1" ] || printf '%s' "$cmd" | grep -Eq '(^|[[:space:];&|(])GW_REVIEW_SKIP=1([[:space:]]|$)'; then
  exit 0
fi

what="git push"; [ "$is_push" = 1 ] || what="gh pr create"

refuse() {
  {
    echo "Review gate: refusing '$what'."
    echo "$1"
    echo "Run /gatewaze-skills:review-round (then /gatewaze-skills:preflight) and try again."
    echo "Emergency bypass for humans: prefix the command with GW_REVIEW_SKIP=1 and say so explicitly. CI still runs every check."
  } >&2
  exit 2
}

cwd=$(hook_json_get '.cwd')
seg=""
[ "$is_push" = 1 ] && seg=$(git_segment push "$cmd")

if ! dir=$(hook_git_dir "$cmd" "$cwd" "$seg"); then
  # Cannot tell which repo the command targets. Fail closed only when the
  # session's own repo has opted in; otherwise this hook is not in play.
  if repo_opted_in "${cwd:-.}"; then
    refuse "The command changes directory or uses -C with a path this hook cannot resolve (a variable, or a path that does not exist). Run the push as a plain command from the repo."
  fi
  exit 0
fi
repo_opted_in "$dir" || exit 0
g() { git -C "$dir" "$@"; }

# A push chained with a repo-changing git command is judged against the
# wrong state, so it is refused regardless of the stamp.
if printf '%s' "$cmd" | grep -Eq "$(git_sub_re '(commit|checkout|switch|merge|rebase|reset|cherry-pick|am|revert|stash|branch|tag|filter-branch|worktree)')"; then
  refuse "The command combines '$what' with a git command that changes the repo. Run them as separate commands so the gate sees the state being pushed."
fi

# Work out which local branch is being pushed. Default: the current branch.
branch=""
if [ "$is_push" = 1 ]; then
  read -r -a words <<< "$seg"
  positional=()
  i=0; n=${#words[@]}
  # skip up to and including the `push` word
  while [ "$i" -lt "$n" ]; do
    w=$(unquote "${words[$i]}"); i=$((i+1))
    [ "$w" = push ] && break
  done
  while [ "$i" -lt "$n" ]; do
    w=${words[$i]}; i=$((i+1))
    case "$w" in
      --dry-run|-n|--delete|-d|--tags) exit 0 ;;
      --all|--mirror|--branches) refuse "'$w' pushes more than one branch. Push the reviewed branch by name." ;;
      -o|--push-option|--repo|--receive-pack|--exec) i=$((i+1)) ;;
      -*) ;;
      *) positional+=("$(unquote "$w")") ;;
    esac
  done
  if [ "${#positional[@]}" -ge 2 ]; then
    refspec=${positional[1]#+}
    src=${refspec%%:*}
    [ -n "$src" ] || exit 0            # `:dst` deletes the remote branch
    src=${src#refs/heads/}
    if [ "$src" != HEAD ]; then
      g show-ref --verify -q "refs/heads/$src" || refuse "'$src' is not a local branch. Push the reviewed branch by name, or push HEAD."
      branch=$src
    fi
  fi
fi
if [ -z "$branch" ]; then
  branch=$(g symbolic-ref --short -q HEAD) || exit 0
fi
case "$branch" in main|master) exit 0 ;; esac
tip=$(g rev-parse --verify -q "refs/heads/$branch") || refuse "Cannot resolve branch '$branch'."

stamp=$(stamp_path "$dir" "$branch") || exit 0
[ -f "$stamp" ] || refuse "No review stamp exists for branch '$branch'. The branch has not had its review round."

reviewed=$(head -n1 "$stamp" | tr -d '[:space:]')
[[ $reviewed =~ ^[0-9a-f]{40}$ ]] || refuse "The review stamp for '$branch' does not hold a full commit SHA."
g cat-file -e "${reviewed}^{commit}" 2>/dev/null || refuse "The review stamp points at a commit ($reviewed) that no longer exists."
g merge-base --is-ancestor "$reviewed" "$tip" 2>/dev/null || refuse "Branch '$branch' was rewritten after the review round (reviewed ${reviewed:0:10} is no longer an ancestor of its tip)."

if g rev-parse --verify -q origin/main >/dev/null 2>&1 && g merge-base --is-ancestor "$reviewed" origin/main 2>/dev/null; then
  refuse "The review stamp is stale: reviewed ${reviewed:0:10} is already on origin/main, so this branch's own commits have not been reviewed."
fi

later=$(g log --format='%h %s' "${reviewed}..${tip}") || refuse "Could not list the commits after the reviewed SHA."
count=0; offenders=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  count=$((count+1))
  subj=${line#* }
  is_gate_exempt_subject "$subj" || offenders="${offenders}  ${line}"$'\n'
done <<< "$later"

if [ -n "$offenders" ]; then
  refuse "Commits after the reviewed SHA ${reviewed:0:10} are not review or preflight fix commits (subject must start with <type>(review): or <type>(preflight):):"$'\n'"$offenders"
fi
if [ "$count" -gt 5 ]; then
  refuse "$count commits sit after the reviewed SHA ${reviewed:0:10}. The round covers one fix commit plus a few preflight fixes; run it again."
fi

exit 0
