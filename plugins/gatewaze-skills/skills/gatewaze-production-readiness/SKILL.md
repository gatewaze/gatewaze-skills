---
name: gatewaze-production-readiness
description: >
  Guardrails distilled from the multi-week production-hardening pass on the
  Gatewaze monorepo. Invoke when working on Gatewaze (admin / api / portal /
  shared) to keep new feature work from undoing the security, type, lint,
  and CI improvements that landed across the prod-hardening/phase-1..4
  branches. Encodes how to handle Supabase typing without a generated
  Database type, where the listing-primitive structural query-builder
  abstraction lives, the ICS / PostgREST / mass-assignment / rate-limit
  patterns, the lint baseline (admin = flat config, api = flat config,
  portal = next lint via root .eslintrc, shared = no-op), and the
  expected zero-error TypeScript baseline across all four packages.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Gatewaze production-readiness guardrails

This skill captures the conventions established during the Phase 1–4
production-readiness pass on `github.com/gatewaze/gatewaze`. New feature
work should follow the same path; the easiest way to keep the codebase
production-ready is to not write the patterns we already pulled out.

The skill is split into a top-level decision guide (this file) plus
topic-specific references in `references/`. Read the references on
demand; don't pre-load all of them.

## When to invoke

You're working in `/Users/dan/Git/gatewaze/gatewaze` (or a checkout of
`github.com/gatewaze/gatewaze`) and the task involves any of:

- Touching a Supabase query (`.from`, `.select`, `.insert`, `.update`,
  `.or`, `.rpc`, `.maybeSingle`, `.single`)
- Adding or changing an HTTP route handler in `packages/api/src/routes/**`
  or `packages/portal/app/api/**/route.ts`
- Adding or changing a React component, hook, or context in
  `packages/admin/src/**` or `packages/portal/{app,components,lib}/**`
- Touching the listing primitive in `packages/shared/src/listing/**`
- Editing CI (`.github/workflows/**`), pre-commit hooks (`.husky/**`),
  lint config (`.eslintrc.cjs`, `packages/*/eslint.config.js`), or
  `pnpm.overrides`
- Adding or modifying a public unauthenticated endpoint
- Anything that emits ICS / iCalendar output

## Non-negotiables

These are the gates the codebase already meets — every commit must
preserve them:

1. **TypeScript: 0 errors across all four packages** (`admin`, `api`,
   `portal`, `shared`). Run `pnpm --filter @gatewaze/<pkg> exec tsc
   --noEmit` before each commit. The CI typecheck job (.github/workflows/
   pr.yml) is **blocking** for all four — there's no `continue-on-error`
   safety net any more.

2. **Lint: 0 errors across all four packages.** Warnings are tolerated
   (admin ~95, portal ~36, api/shared 0) but each package's `lint`
   script must exit 0. See `references/lint-and-ci.md` for the per-package
   config layout.

3. **No new `: any` annotations.** The current count is 34, all in admin
   polymorphic-erasure UI components (`<E extends ElementType>` pattern)
   where narrowing breaks JSX inference at call sites. New code should
   not introduce `: any` without an explicit eslint-disable comment that
   explains why narrowing isn't possible. See
   `references/typescript-patterns.md` for the legitimate exceptions and
   how to type Supabase clients without generated Database types.

4. **No PostgREST `.or()` filter strings interpolating user input
   without a sanitiser.** The pattern is in `references/security-boundaries.md`.
   The fix is `String(value).replace(/[,()*\\]/g, '').slice(0, 100)`
   before interpolation — strip filter metacharacters and cap length.

5. **No raw `req.body` / unparsed user input passed straight to
   `.insert()` / `.update()`.** Use a `*_WRITE_FIELDS` allowlist and a
   `pickFields(body)` helper. See `references/security-boundaries.md`.

6. **No new public unauthenticated POST endpoint without IP rate
   limiting.** The portal already has `@/lib/rate-limit` (in-memory
   sliding window); use `checkRateLimit('<route>:${ip}', maxReq,
   windowMs)`. See `references/security-boundaries.md`.

7. **Hooks before early returns.** `react-hooks/rules-of-hooks` is
   `error` in the root .eslintrc.cjs and admin's flat config. The
   loading-guard early-return pattern goes BELOW hook calls, never
   above. See `references/react-patterns.md`.

8. **Pre-commit hook is sacred.** `pnpm exec lint-staged` runs on every
   commit via `.husky/pre-commit`. Never bypass with `--no-verify`
   unless the user explicitly authorises it.

9. **Every new feature ships with tests.** The minimum bar is one
   happy-path test plus one test per validation rule, security
   boundary, or 4xx/5xx code path the feature introduces. "I'll add
   tests later" doesn't survive the merge — without the test, a
   future refactor silently regresses behaviour and you'll spend more
   time tracking it down than writing the test would have cost. See
   `references/testing-patterns.md` for the per-layer recipe (api
   route, portal route handler, admin component, shared utility).
   Fixing a bug? Add the regression test that proves the bug existed
   AND now doesn't — the test is the evidence the fix is durable.

## Decision tree

| Task | Read |
|------|------|
| Adding a Supabase query / handling `never` row types | `references/typescript-patterns.md` |
| Building or modifying an HTTP route | `references/security-boundaries.md` |
| Working with React components, hooks, contexts | `references/react-patterns.md` |
| Editing the listing primitive (shared/listing) | `references/listing-primitive.md` |
| Emitting ICS / iCalendar feed | `references/ics-output.md` |
| Adding a test or hitting a pre-existing test failure | `references/testing-patterns.md` |
| Touching CI, lint, audit, lockfile | `references/lint-and-ci.md` |
| Working with the module registry (gitignored generated files) | `references/module-registry.md` |

## Behavioural defaults

- **Run tests before claiming success.** TypeScript clean does not mean
  the change works. For UI work, you must verify in the browser before
  reporting done — type-check + test run only proves correctness, not
  feature behaviour.

- **Pre-existing failures get a `git stash` compare.** If a test fails,
  stash your changes and run the test on the parent commit. If it
  fails there too, it's pre-existing — say so explicitly in the
  commit body so reviewers don't assume your change caused it.

- **Lint warnings are partitioned, not silenced.** The 95 admin
  warnings + 36 portal warnings are real; auto-fix what's mechanical
  (unused imports, prefer-const), leave `react-hooks/exhaustive-deps`
  alone unless you can verify the fix in a browser (potential infinite
  loops). Do not bulk-add `// eslint-disable-next-line` to drop the
  count — the patterns are signal, not noise.

- **Commit messages explain WHY, not WHAT.** The diff shows the what.
  Each non-trivial commit body should call out the constraint, hidden
  invariant, or prior incident that motivates the change. The
  prod-hardening/phase-* commit history is the reference style.

- **`pnpm -r lint` exits 0** is the CI floor. If you change a lint
  script, run it locally; if you change the lint-staged config, install
  any binaries you reference.

## What NOT to do

These are anti-patterns that have already cost time on this codebase
and were explicitly removed:

- **Don't write `as any`** to silence a Supabase typing complaint —
  prefer a local `interface RowShape { … }` and `.maybeSingle<RowShape>()`.
  See `references/typescript-patterns.md`.

- **Don't add a re-export to a `'use client'` component file** — it
  breaks fast refresh. Move the helper / hook / constant to a sibling
  module. The 8 react-refresh/only-export-components warnings cleared
  in commit `e9894fd` document the canonical pattern.

- **Don't `clearTimeout(undefined)` to dodge a `let` declaration** —
  combine the `setTimeout` and the `let` into a single `const`
  declaration where possible. `auth/Provider.tsx` shows the pattern.

- **Don't write `new Image()` if `Image` is imported as `next/image`** —
  use `new window.Image()` to get the DOM constructor.

- **Don't add `lint` scripts that call binaries the package doesn't
  install.** Either install the binary or use `echo 'no lint
  configured'`. CI's `pnpm -r lint` will fail on ENOENT.

- **Don't pin `path-to-regexp@<0.1.13` or `undici@<7.24.0`.** Both have
  pnpm overrides at the workspace root that force patched versions —
  see `pnpm.overrides` in `package.json`.

- **Don't try to "fix" the two remaining `lodash _.template` audit
  highs.** The cited patched version (4.18.0) doesn't exist on npm. We
  verified no `_.template` call sites in the repo via `rg` — the
  advisories are not exploitable here.

## Reference index

- `references/typescript-patterns.md` — Supabase typing, `: any`
  exceptions, `ListingQueryBuilder`, generated Database types
- `references/security-boundaries.md` — PostgREST injection,
  ICS/CR-LF, mass-assignment, rate-limit, path-param, service-role
- `references/react-patterns.md` — rules-of-hooks, fast refresh,
  `next/image` shadowing, exhaustive-deps audit
- `references/listing-primitive.md` — structural builder type, virtual
  filters, schema validator
- `references/ics-output.md` — `escapeICSText` vs `sanitizeICSLineValue`,
  fold-line correctness
- `references/testing-patterns.md` — vitest + supertest patterns, mock
  Supabase, regression-test conventions
- `references/lint-and-ci.md` — per-package eslint, pnpm overrides,
  `pnpm -r lint` floor, husky / lint-staged
- `references/module-registry.md` — generator behaviour, alias paths,
  external module repos
