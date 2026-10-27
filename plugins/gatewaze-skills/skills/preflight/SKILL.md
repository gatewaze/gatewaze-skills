---
name: preflight
description: >
  Deterministic pre-push checks for any Gatewaze repo. Run it after the review
  round (/gatewaze-skills:review-round) has landed its fix commit and before you
  push. It runs the repo's own mechanical checks (typecheck, lint, format,
  build, tests) and auto-fixes what is safely auto-fixable, then verifies the
  commits are shaped right (signed, signed off, conventional subjects). It is
  not a review: rule-based and judgement findings belong to the review round.
  Adapts to whatever the repo actually declares in its package.json scripts and
  CLAUDE.md. Pass --report-only to run without writing fixes.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Preflight

You have finished the review round and are about to push. Every check here is
shell-driven, no judgement calls. Convention and pattern review is owned by
`/gatewaze-skills:review-round` and does not run again here.

This skill is repo-agnostic by design. It reads the repo's own working
agreement and scripts and runs those. The inputs are the repo's `CLAUDE.md`,
its `.claude/rules/lint-and-ci.md` if present, and the `scripts` block of each
`package.json`.

Modes:

- Default. Run every check and auto-fix the safely mechanical things
  (formatting, import order, lint autofixes).
- `--report-only`. Run every check, write nothing.

Never make a check pass by weakening it. Do not add `eslint-disable`,
`@ts-ignore`, `--no-verify`, `continue-on-error`, `.skip`, or delete an
assertion to get to green. Fix the code, or report the failure as unresolved.

## Step 0: Read the repo's checks

```bash
git rev-parse --show-toplevel
git rev-parse --abbrev-ref HEAD
git status --porcelain
git diff --stat "$(git merge-base origin/main HEAD)...HEAD"
```

Read `CLAUDE.md` and `.claude/rules/lint-and-ci.md` for the declared check
commands and any known exceptions (e.g. a package whose lint is a deliberate
no-op). Read each changed package's `package.json` scripts. Run what the repo
declares, nothing it does not.

If the tree is dirty, stop and tell the developer. Preflight runs on committed
work.

## Step 1: Mechanical checks

Scope to the packages the branch touched. In the Gatewaze monorepo the usual
commands are:

| Check | Typical command | Auto-fix |
| --- | --- | --- |
| Typecheck | `pnpm --filter <pkg> typecheck` | No. Fix the code |
| Lint | `pnpm --filter <pkg> lint` | Partly. `eslint --fix` for import order and unused imports; logic errors by hand |
| Format | the repo's formatter, if one is configured | Yes |
| Build | `pnpm --filter <pkg> build` | No. Fix the code |
| Tests | `pnpm --filter <pkg> test` | No. Fix the code, or the test if the behaviour changed on purpose |
| Shell-call audit | `pnpm exec tsx scripts/audit-shell-calls.ts` | No |

Rules:

- Only run what the repo has. No format script means no format step.
- Auto-fix only the mechanical, reversible things. Anything needing judgement
  (a type error, a failing test, a logic lint error) you fix deliberately and
  explain.
- Re-run after fixing. A fix must not introduce a new failure.
- If a check cannot run here (needs a database, a browser, a service), say so
  and mark it deferred to CI. Never report it as passed.

## Step 2: Commit the fixes

If Step 1 changed files, commit them in their own commit, signed and signed
off, with the `(preflight)` scope:

```bash
git commit -s -S -m "fix(preflight): <what the checks reported>"
```

The `(preflight)` scope is what the plugin's push gate accepts after the
review stamp. Use `style(preflight):` or `test(preflight):` where that is the
truer type; the scope is what matters. Do not rerun the review round on these
commits.

## Step 3: Commit shape

```bash
git log --format='%G? %h %s' "$(git merge-base origin/main HEAD)..HEAD"
git log --format=%B "$(git merge-base origin/main HEAD)..HEAD" | grep -c '^Signed-off-by:'
```

- Every commit has a good signature (`G`, or `U` when the key is not in the
  local trust database).
- Every commit carries a `Signed-off-by:` trailer.
- Every subject is `type(scope): description`, lower case, under 72 characters.
- No commit message carries an AI authorship trailer.

A commit that fails these needs an amend or an interactive rebase. The push
gate refuses a rewritten branch, so if you rewrite history here, run the
review round again before pushing.

## Step 4: Report

```text
PREFLIGHT  <repo> @ <short-sha>  (<branch>, N commits ahead of origin/main)
  typecheck   ok
  lint        ok (2 files auto-fixed, committed as a1b2c3d)
  build       ok
  tests       deferred to CI (needs Postgres)
  shell audit ok
  commits     ok (signed, signed off, conventional)
Verdict: READY TO PUSH
```

Or `Verdict: NOT READY` with the failing lines above it. Never claim a check
passed that you did not run.
