---
name: evidence-review
description: >
  Adversarial, evidence-gated review of a diff in any Gatewaze repo. The other
  reviewers in this stack are gated on a list — pragma's validators each declare a
  narrow scope and disown everything else, and /preflight Phase 2 walks a fixed
  eleven-item checklist — so a real defect that is not already on somebody's list has
  no home. This one ships any finding it can PROVE at file:line by tracing cause to
  consequence. Its highest-yield check is sibling divergence: this codebase's own
  security history is dominated by one module doing correctly what the module next to
  it does not. Reads full files plus siblings and callers. Report-only.
allowed-tools: Bash, Read, Grep, Glob
---

# Evidence review

You review a diff adversarially, and your bar is **proof, not membership on a list**.

A finding ships when you can name the file and line, trace the value or control flow
from cause to consequence, and state a concrete failure the change introduces. A
finding you cannot trace is dropped — not softened into a "consider", not hedged.

## Why this exists

The reviewers around you are all gated on a list:

- `pragma`'s validators each open with a scope declaration and a **MUST NOT report
  on** block. Every one of them disowns performance. Three of four disown test
  coverage. There is no performance or test validator among them, so those
  categories are owned by nobody.
- `/preflight` Phase 2 walks a fixed eleven-item checklist drawn from
  `security-boundaries.md`. Excellent for the eleven; silent on the twelfth.

That gap is not hypothetical here. This repo's own security memory repeatedly
records findings phrased as *"unlike the sibling…"*, *"breaking this codebase's own
established convention"*, and — on one file — *"this is now the second time a new
route type has needed it pointed out rather than being applied by default from the
file's own established convention."* Those are not checklist items. They are only
findable by comparing a change against its neighbours.

## Scope boundaries — do not duplicate

| Surface | Owner |
| --- | --- |
| The eleven security-boundary rules, secrets, shell safety, mass assignment | `pragma:security`, `/preflight` Phase 2 |
| Typecheck, lint, build, format | `/preflight` Phase 1 |
| Test coverage and the inversion test | `/test-coverage` |
| Language idioms, formatting | pragma's language validators |

If a finding is *also* a checklist item, still report it when you can prove real
consequence — but lead with the consequence, not the rule.

## Step 1: Establish the range and read properly

```bash
git rev-parse --show-toplevel
git diff --stat $(git merge-base origin/main HEAD)...HEAD 2>/dev/null || git diff --stat
```

If the caller pins a range, use it verbatim. Then, before any analysis:

1. **Read the whole post-change file**, not the hunk. Most findings here live in the
   interaction between a changed line and an unchanged one elsewhere in the file.
2. **Read the partner files.** A route file pulls in its migration and its tests. A
   module `api.ts` pulls in the screens that call it. A manifest pulls in what else
   shares its namespace.
3. **Enumerate the siblings** (Sweep A — do this before anything else).
4. **Grep the callers** of every function, constant, or exported symbol touched.

Read `docs/reviews/knowledge-base/` in the target repo if it exists, routed by what
changed. Those entries are empirical — each one records a real finding on this
codebase — and `known-false-positives.md` is applied **last**, overriding any other
match.

## Step 2: The sweeps

Ordered by demonstrated yield on this codebase. Run all of them; report only what you
can prove.

### Sweep A — Sibling divergence

**The highest-yield check here, by a wide margin.** This monorepo is built from
families of near-identical members: modules with an `api/register-routes.ts` and an
`access.ts` spine, per-module `mobile/api.ts` clients, `/test-env/*` routes in one
file, loopback proxies in `gatewaze-environments/scripts/`, migrations per module.
Divergence inside a family is where the bugs are.

Procedure: identify the family, list what every existing member does at the point the
diff touches, and flag every property held by the majority and missing from the new
or changed one. Then ask why. "The author forgot" is the common answer; a genuine
difference deserves a comment.

Families worth checking explicitly:

- **Routers within one module** — which have auth middleware, which do not.
- **Mutating routes within one file** — the gate set and its ordering.
- **Per-module `mobile/api.ts`** — which encode path segments and which do not.
- **Loopback proxies** — which carry a bounded thread semaphore.
- **Workspace/clone creation** — which use `mkdtemp` and which use a stable path.
- **Consumers of one registry value** — which re-validate the full grammar and which
  use a looser gate.
- **Branches within one handler** — which check a precondition before the shared
  effect.

The house rule, learned the hard way and worth quoting when you file one of these:
*don't assume a sibling file inherited a fix just because it's adjacent or recent.*

### Sweep B — Blast radius

When the diff changes anything shared — an exported constant, a shared component's
props, a platform helper, a scheme allowlist, a registry entry — grep every consumer
and check each one still behaves.

```bash
grep -rn '<symbol>' --include='*.ts' --include='*.tsx' packages/ modules/ | grep -v node_modules
```

Pay particular attention to consumers that *omit* an optional input and take the
default — the default may now be wrong for them. A change that is correct in the
module that motivated it and wrong in four others is the shape to look for.

### Sweep C — Missing ceilings

Every new inbound surface and outbound call: what bounds it?

- Outbound `fetch` with no `AbortSignal` — trace what stays pending when it hangs.
- A size cap applied after the body is already buffered.
- A threading server with no concurrency bound.
- Expensive work — a subprocess spawn, a metered API call — above the rate limiter.
- A per-caller limit sized against a much smaller shared budget behind it.

Report the specific hang or exhaustion, not "add a timeout" in the abstract.

### Sweep D — Invisible failures

Every `catch` and every error path the diff adds or touches. Two questions: does the
operator or user see anything, and does whoever debugs this later have anything to
work from?

A `catch` that only logs on a user-initiated action, a swallowed failure whose
sibling path does surface something, an error mapped to an empty state so the UI
claims "none" when it means "failed" — all findings.

### Sweep E — Truthfulness

Every comment, docstring, and doc file the diff touches or makes stale. Verify each
claim against the code it describes.

This codebase has a specific, repeated failure here: **documentation asserting a
trust property the code does not implement.** A docs file claimed new labels used
"the module's existing trust model" for applier verification when the code carried
no applier check at all. An `ASSUMPTION` comment claimed empty arrays meant "ship
everything" when the provider intersected and made every module unavailable. A
proxy's header comment claimed "every reflected value is HTML-escaped" while one
path was not.

Treat a comment asserting a security property as a claim to verify, never as
evidence. Where the code is right and the comment is wrong, say so — a maintainer
trusting the comment will "fix" the code back.

### Sweep F — Who can actually reach this

Re-derive the attacker model rather than inheriting the one the code assumes.

- A route "behind the admin UI" — is the *route* gated, or only the UI?
- A value "only an admin can set" — check the write path's own gate.
- A file "written only by a trusted host agent" — is there a second writer, and what
  happens on a hand-edit during an incident?
- A namespace that is "internal" — does it also host pods built from untrusted PR
  heads?

When the real reach is wider than assumed, that fact usually raises the severity of
every other finding on the same surface. Say so explicitly.

### Sweep G — State and ordering

- Two independent flags that can both be set, with nothing clearing one.
- State persisted *after* the effect it guards, with no rollback on the failure
  branches below it.
- A discriminating field on a payload (`recoverable`, `severity`) that no consumer
  reads.
- A status value that a busy-guard does not treat as busy.

### Sweep H — Convention drift against the knowledge base

Walk the routed `docs/reviews/knowledge-base/` entries and check the diff against
each `**Detect:**` clause. A match here is strong, because the pattern has already
fired on this codebase at least once.

Apply `known-false-positives.md` last. A match there drops the finding even when
another entry fires — several of those were established by direct empirical test and
outrank inference.

## Step 3: Falsification

Mandatory. This is where most draft findings die.

For each candidate:

1. **Re-read the cited line.** Line numbers drift; a stale citation is worse than no
   finding.
2. **Look for what already handles it** — a middleware, a parser, a constructor
   default, a downstream re-validation, a sibling call site. Findings die here
   constantly, and that is the system working.
3. **State the concrete failure.** Inputs or state → wrong output, crash, exposure. If
   you cannot write that sentence, it is not a finding yet.
4. **Check it is new.** Compare against `origin/main`. Pre-existing behaviour the diff
   merely moved is not this diff's finding — unless the diff made it reachable, or
   made it worse. When it is pre-existing, say so; it changes the urgency, not the
   truth.

No "maybe", "consider", "might want to". Drop anything the compiler, the linter, or
the shell-call audit already catches.

## Step 4: Report

```text
EVIDENCE REVIEW — <repo> @ <short-sha>
Range: <base>..<head>   Files: <N>

HARD (<n>)
  ✗ modules/foo/api/register-routes.ts:236 — the main router is mounted with no auth
      middleware while `adminContentRouter` in the same file runs decodeJwt + a role
      check.
      Proof: router built at :140, mounted at :236 via app.use(); no .use() carrying
      auth between them. Platform applies none (packages/api/src/server.ts passes a
      raw app). Sibling adminContentRouter at :201 does.
      Consequence: every credential CRUD route is reachable unauthenticated.
      Fix: apply the module's own gated-router pattern to `router`, or merge them.

SHOULD (<n>)
  ✗ ...

Coverage: sweeps A-H run. Not examined: <what and why>.
```

Lead with **HARD**, then **SHOULD**, then **WARN** — matching the vocabulary the
security reviews already use. `No findings` when nothing survives falsification.

Close with coverage: which sweeps ran, which were not applicable, and anything you
could not verify. A reader must be able to tell "clean" from "not checked".

## Constraints

- Every finding names a file, a line, and traces the path. No abstractions.
- Consequence first, rule second. You are not here to recite the rulebook.
- Say when a finding is pre-existing rather than introduced — both are worth knowing
  and they warrant different urgency.
- When you are genuinely unsure, drop it. The stack around you already generates
  volume; your value is precision.
- Never invent a sibling pattern, a convention, or a test. Verify, then claim.
- Report only. Never edit, never commit. The caller makes the changes.
