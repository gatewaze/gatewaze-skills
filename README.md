# gatewaze-skills

Agent skills for working on the [Gatewaze](https://github.com/gatewaze/gatewaze)
monorepo, packaged as a **plugin marketplace** so every contributor gets the
same skills without manual setup.

The repo is one marketplace (`.claude-plugin/marketplace.json`) exposing one
plugin (`gatewaze-skills`) that bundles all the skills. Each skill is a
`SKILL.md` plus an optional `references/` directory of topic-specific
deep-dives that an AI coding agent loads on demand.

## Layout

```
.claude-plugin/marketplace.json          # marketplace catalog
plugins/gatewaze-skills/
  .claude-plugin/plugin.json             # plugin manifest
  hooks/hooks.json                       # Claude Code hooks (after-commit nudge, before-push gate)
  scripts/                               # the hook scripts
  skills/
    review-round/
    evidence-review/
    test-coverage/
    preflight/
    production-readiness/
    ui/
    modules/
    gatewaze-memory/
    se-handoff/
```

## The review lifecycle

A branch gets one local review round before it is pushed, and a security pass
after every commit. The repo's `CLAUDE.md` carries a short "Pre-PR review"
section that names `/gatewaze-skills:review-round`; the rules live in the skill
so repos cannot drift. The shape follows the one the LFX repos adopted in
September 2026.

1. After each `git commit` the agent runs, the `after-commit` hook asks the
   session to run `pragma:security` on exactly that commit, pinned to the SHA
   and report-only. Confirmed findings go in a `fix(security):` commit.
2. When the branch is complete, `/gatewaze-skills:review-round` pins the branch
   range as two full SHAs and launches the reviewers in parallel as background
   subagents: `pragma:security`, `evidence-review`, `test-coverage`, and
   `pragma:typescript-style` when TypeScript changed. Each reads files with
   `git show`, never the working tree, and only reports. The main session
   verifies every finding and lands all accepted ones in one `fix(review):`
   commit, then writes a review stamp under the repo's git directory.
3. `/gatewaze-skills:preflight` runs the deterministic checks (typecheck, lint,
   build, tests, commit shape) and commits fixes as `fix(preflight):`.
4. The `before-push` hook refuses `git push` and `gh pr create` on a feature
   branch unless the stamp exists, the branch was not rewritten after it, and
   every later commit is a `(review)` or `(preflight)` fix. `GW_REVIEW_SKIP=1`
   on the command bypasses it for humans and emergencies.

Both hooks are opt-in per repo. They do nothing unless the repo's root
`CLAUDE.md` names `/gatewaze-skills:review-round`. They govern Claude Code
sessions only; a person committing from a terminal is unaffected, so git hooks
and CI remain the gates for humans. The stamp is a plain file the agent could
write by hand, which `CLAUDE.md` forbids; the gate stops the round being
forgotten, it does not resist a session that sets out to skip it.

## Skills in this repo

### [`review-round/`](./plugins/gatewaze-skills/skills/review-round/SKILL.md)

The one local review round, described above. Pins the range, launches the
reviewers, judges, one fix commit, writes the stamp.

### [`evidence-review/`](./plugins/gatewaze-skills/skills/evidence-review/SKILL.md)

Adversarial review that ships only findings it can prove at `file:line` by
tracing cause to consequence. Its highest-yield check is sibling divergence:
one module doing correctly what the module beside it does not.

### [`test-coverage/`](./plugins/gatewaze-skills/skills/test-coverage/SKILL.md)

The inversion test. For every new condition, invert it and ask which existing
test fails. If none would, the branch is unpinned.

### [`preflight/`](./plugins/gatewaze-skills/skills/preflight/SKILL.md)

Deterministic checks only, run after the review round and before the push.

### [`production-readiness/`](./plugins/gatewaze-skills/skills/production-readiness/SKILL.md)

Guardrails distilled from the Phase 1-4 production-hardening pass on
the gatewaze monorepo. Encodes the security boundaries (PostgREST
filter injection, mass assignment, ICS CR/LF, rate-limiting,
path-param validation), the TypeScript patterns we settled on
(structural Supabase builder, `.maybeSingle<RowShape>()`, the
legitimate `: any` floor), the React rules-of-hooks discipline, the
fast-refresh "components-only file" pattern, and the per-package lint
+ CI configuration.

The non-negotiables (ten of them) are summarised at the top of the
SKILL.md. Each topic has a `references/<topic>.md` with the canonical
existing-code pointers and the recipe for new work.

### [`ui/`](./plugins/gatewaze-skills/skills/ui/SKILL.md)

Admin UI layout conventions. How to lay out any admin page with the
shared `WorkspaceLayout` primitive (hero, primary tabs, the
secondary-coloured breadcrumb "flag", and sub-tabs), and a decision
tree for which of those levels to render based on the data's schema
shape: flat list (hero only), entity-with-sections (hero + primary
tabs), or nested sub-entity drill-in (hero + tabs + breadcrumb flag +
sub-tabs, e.g. newsletters → editions, meetups → series). Covers the
hero-everywhere rule, title/breadcrumb conventions, primary vs
secondary theming, and full-bleed editor handling.

### [`modules/`](./plugins/gatewaze-skills/skills/modules/SKILL.md)

Module development workflow. The cardinal rule: edit the canonical
source in the module's own repo (`gatewaze-modules` /
`lf-gatewaze-modules`), never the gitignored, generated
`.gatewaze-modules/` staging dir in the host repo. Covers where each
module lives, module anatomy (`module.json` / `index.ts` /
`admin` / `portal` / `api` / `functions` / `migrations`), how to
confirm you're editing the real file, the type-check caveat
(module `tsc` doesn't cover admin/portal pages), and the
migrate / deploy / commit workflow.

## How to use these skills

### Recommended: install via the marketplace

Add the marketplace once, then install the bundled plugin:

```shell
/plugin marketplace add gatewaze/gatewaze-skills
/plugin install gatewaze-skills@gatewaze-skills
```

The skills are namespaced under the plugin, e.g. type
`/gatewaze-skills:production-readiness` to invoke one
explicitly. You don't have to invoke explicitly; once installed, the
model can decide to load a SKILL.md when the task touches one of its
trigger areas (Supabase queries, route handlers, React components,
module edits, etc.).

### Make it automatic for a whole repo

A consuming repo can register this marketplace and auto-enable the
plugin for everyone who trusts the project folder, by committing this
to its `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "gatewaze-skills": {
      "source": { "source": "github", "repo": "gatewaze/gatewaze-skills" }
    }
  },
  "enabledPlugins": {
    "gatewaze-skills@gatewaze-skills": true
  }
}
```

## Updating a skill

This repo is intentionally evolving. When a new pattern emerges
during gatewaze work (a new security boundary, a new typing
challenge, a new lint configuration), add a section to the relevant
`references/<topic>.md` (or create a new reference file and link it
from `SKILL.md`).

The plugin manifest deliberately omits `version`, so every pushed
commit is treated as a new version and contributors pick up skill
updates automatically (run `/plugin marketplace update gatewaze-skills`
to refresh; a stale local copy is the usual reason a skill named in a
repo's `CLAUDE.md` fails to load).

To check the hook scripts without a Claude session, pipe a hook event at
them:

```shell
printf '{"tool_input":{"command":"git push origin HEAD"}}' \
  | bash plugins/gatewaze-skills/scripts/before-push.sh; echo "exit $?"
```

The existing fixes that motivated each rule are cited by file path
and commit hash. When you add a new rule, follow the same format;
it's the difference between a guideline and an enforceable
convention.

## Repo conventions

- One skill per directory under `plugins/gatewaze-skills/skills/`.
- `SKILL.md` is the entry point (frontmatter must include `name` and
  `description`).
- `references/` holds topic-specific deep-dives: one file per
  concern, linked from the SKILL.md decision tree.
- Don't bundle binaries or large assets; link to source files in the
  gatewaze repo by path.
- Commit messages follow the same conventions as the gatewaze repo:
  focus on WHY, not WHAT.

## License

Same license as the gatewaze repo (Apache-2.0).
