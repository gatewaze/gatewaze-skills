---
name: preflight
description: >
  Pre-submission self-review for any Gatewaze repo. Run it BEFORE you consider a
  change done — after you finish editing, before the diff is handed off for a PR.
  Phase 1 runs the repo's own mechanical checks (typecheck, lint, build, format)
  and auto-fixes what is safely auto-fixable; Phase 2 reviews the diff against the
  repo's CLAUDE.md and .claude/rules (security boundaries, mass-assignment, shell
  safety, secrets) and reports what a human reviewer would otherwise catch. Adapts
  to whatever the repo actually declares — it reads the repo's rules, it does not
  assume a fixed toolchain. Especially useful for autonomous agents whose work
  goes straight to a pull request.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Preflight — self-review before you hand off a change

You have finished editing and are about to declare the work done (an autonomous
run will open a PR from it; a human contributor is about to commit). This is the
last cheap moment to catch what CI or a reviewer would bounce. Run both phases.

**This skill is repo-agnostic by design.** It does not hardcode a toolchain — it
reads the repo's *own* working agreement and scripts and runs those. The single
most important input is the repo's `CLAUDE.md` (and any `.claude/rules/*.md`);
everything below is how to apply it, not a substitute for it.

**Modes:**

- **Default** — run both phases. Phase 1 auto-fixes the safely-mechanical things
  (formatting, import order, obvious lint autofixes). Phase 2 is report-only.
- **`--skip-review`** — Phase 1 only. Use mid-development to just check build/lint.
- **"report only" / "dry run"** — Phase 1 reports without writing fixes.

**Non-negotiable:** never make a check pass by weakening it. Do not add
`// eslint-disable`, `@ts-ignore`, `--no-verify`, `continue-on-error`, `.skip`,
or delete an assertion to get to green. Fix the code, or report the failure as
unresolved. Disabling a gate to pass is itself a Phase 2 finding.

---

## Step 0: Read the repo's rules

```bash
git rev-parse --show-toplevel   # confirm which repo you are in
```

For **each** writable repo in the workspace:

1. Read its `CLAUDE.md` at the repo root — this is the contract. Note anything it
   lists under "never do", "security", or a commit/push checklist.
2. Read every `.claude/rules/*.md`. In this monorepo the security boundaries live
   in `.claude/rules/security-boundaries.md` and the lint/CI baseline in
   `.claude/rules/lint-and-ci.md`. A rule file with a `paths:` frontmatter only
   applies to files matching that glob — apply the most specific match to each
   changed file.
3. Read `package.json` "scripts" to discover the actual check commands (the names
   below are the common ones; use what the repo declares).

Everything after this adapts to what you just read.

---

# Phase 1: Mechanical checks (auto-fix where safe)

Scope the checks to what changed. Establish the diff first:

```bash
git status
git diff --stat $(git merge-base origin/main HEAD)...HEAD 2>/dev/null || git diff --stat
```

Run the repo's declared checks. In the Gatewaze monorepo these are typically:

| Check | Typical command | Auto-fix? |
|-------|-----------------|-----------|
| Typecheck | `pnpm -r typecheck` (or per-package) | No — fix the code |
| Lint | `pnpm -r lint` | Partially — `eslint --fix` for import-order/unused; logic issues by hand |
| Format | the repo's formatter, if one is configured | Yes |
| Build | `pnpm --filter <pkg> build` | No — fix the code |
| Tests | `pnpm --filter <pkg> test` | No — fix the code or the test if the behaviour legitimately changed |

Rules for Phase 1:

- **Only run what the repo actually has.** If there is no format script, skip it —
  do not invent one. `shared`'s lint is a deliberate no-op; that is not a failure.
- **Auto-fix only the mechanical, reversible things** (formatting, import order,
  trivially auto-fixable lint). For anything requiring a judgement call (a type
  error, a failing test, a logic-level lint error), fix it deliberately and
  explain what you changed — never silence it.
- **Re-run after fixing.** If Phase 1 changed files, re-run lint/typecheck to
  confirm the fix did not introduce a new problem.
- If a check **cannot** be run here (needs a service, a DB, a browser), say so
  explicitly rather than reporting it as passed. CI will still run it.

---

# Phase 2: Diff review against the repo's rules (report-only)

Walk the changed lines — not the whole repo — and check each against the rules you
read in Step 0. This is where you catch what lint can't. Report findings; do not
silently rewrite (the point is a reviewable list). The high-signal checks in this
monorepo, straight from `security-boundaries.md`:

1. **Secrets.** No key/token/password/bearer value in tracked source, tests,
   READMEs, or example files — not even as an `env || 'literal'` fallback. Example
   files carry placeholders only.
2. **Mass assignment.** No `req.body` inserted/updated directly — an allowlist of
   writable fields only.
3. **PostgREST `.or()` / filter injection.** User input must be sanitised before it
   reaches a `.or()` filter, a constructed SQL string, an ICS line, or a built URL.
4. **Enum / string-union validation.** Values that must be one of a known set are
   checked against that set before use, not trusted from the request.
5. **Service-role null-guards.** A service-role client bypasses RLS — guard for the
   null/absent case so a missing value can't widen access.
6. **Shell safety.** No `child_process.exec`, `execSync` with a single string, or
   `spawn` with `shell: true` outside the repo's sanctioned wrapper
   (`packages/api/src/lib/safe-exec.ts`). Never build a shell string from user input.
7. **Path-param / ICS CR-LF / SSRF.** Validate path params; strip CR/LF from values
   interpolated into ICS lines; validate the host of any URL you construct/fetch.
8. **Rate-limiting.** Public POST endpoints are rate-limited.
9. **GitHub Actions.** No widened `permissions:` block and no action unpinned from
   its commit SHA without a stated reason.
10. **Radix singleton.** No `@radix-ui/themes` imported directly inside a module
    file (it duplicates the singleton in prod and crashes `useThemeContext`).
11. **No gate weakened to pass.** A disabled rule/validator/CI gate is a finding.

Also apply anything specific the repo's own `CLAUDE.md` adds that is not in this
list — the repo contract wins.

For each changed file, ask: does this line cross a trust boundary (parses untrusted
input, builds a query/command/URL from user data, handles a credential, enforces
authz)? If yes, verify it against the matching rule above. If a repo ships the
`pragma:security` skill, prefer running that over eyeballing — it is the validator
these rules were written for.

---

# Output

Produce a compact report, not prose:

```
PREFLIGHT — <repo> @ <short-sha>
Phase 1 (mechanical):
  ✓ typecheck   ✓ lint (2 files auto-formatted)   ✓ build   ⚠ tests: 1 skipped (needs DB — CI will run)
Phase 2 (rules):
  ✗ packages/api/src/routes/foo.ts:41 — inserts req.body directly (mass assignment). Use a writable-field allowlist.
  ✓ no secrets, no unsafe shell, no unpinned actions, no .or() injection
Verdict: NOT READY — 1 blocking finding above. Fix before handoff.
```

- **Auto-fixes you applied** in Phase 1 are already in the working tree; list them.
- **Phase 2 findings** are report-only — fix the blocking ones, then re-run
  preflight until the verdict is READY.
- If a check couldn't run in this environment, mark it `⚠ (deferred to CI)` — never
  claim a check passed that you did not run.
