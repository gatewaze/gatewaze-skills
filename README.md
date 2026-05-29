# gatewaze-skills

Agent skills for working on the [Gatewaze](https://github.com/gatewaze/gatewaze)
monorepo. Each subdirectory is a self-contained Agent Skill — a `SKILL.md`
plus a `references/` directory of topic-specific deep-dives — that an AI
coding agent loads on demand.

## Skills in this repo

### [`gatewaze-production-readiness/`](./gatewaze-production-readiness/SKILL.md)

Guardrails distilled from the Phase 1–4 production-hardening pass on
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

### [`gatewaze-ui/`](./gatewaze-ui/SKILL.md)

Admin UI layout conventions. How to lay out any admin page with the
shared `WorkspaceLayout` primitive (hero, primary tabs, the
secondary-coloured breadcrumb "flag", and sub-tabs), and a decision
tree for which of those levels to render based on the data's schema
shape — flat list (hero only), entity-with-sections (hero + primary
tabs), or nested sub-entity drill-in (hero + tabs + breadcrumb flag +
sub-tabs, e.g. newsletters → editions, meetups → series). Covers the
hero-everywhere rule, title/breadcrumb conventions, primary vs
secondary theming, and full-bleed editor handling.

### [`gatewaze-modules/`](./gatewaze-modules/SKILL.md)

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

### Symlink into your agent's skills directory

Each skill's directory is a symlink target. To make a skill available
across all sessions, symlink it into your coding agent's skills
directory:

```bash
ln -sf "$(pwd)/gatewaze-production-readiness" ~/.claude/skills/gatewaze-production-readiness
```

Your agent will discover it on next session start.

### Invoke explicitly

Once a skill is registered in your agent's skills directory, type
`/gatewaze-production-readiness` to invoke it. The model will load
the SKILL.md and pull references on demand.

You don't have to invoke explicitly — once the skill is symlinked,
the model can decide to read the SKILL.md if the task touches one of
the trigger areas (Supabase queries, route handlers, React
components, etc.).

## Updating a skill

This repo is intentionally evolving. When a new pattern emerges
during gatewaze work — a new security boundary, a new typing
challenge, a new lint configuration — add a section to the relevant
`references/<topic>.md` (or create a new reference file and link it
from `SKILL.md`).

The existing fixes that motivated each rule are cited by file path
and commit hash. When you add a new rule, follow the same format —
it's the difference between a guideline and an enforceable
convention.

## Repo conventions

- One skill per top-level directory.
- `SKILL.md` is the entry point (frontmatter must include `name` and
  `description`).
- `references/` holds topic-specific deep-dives — one file per
  concern, linked from the SKILL.md decision tree.
- Don't bundle binaries or large assets; link to source files in the
  gatewaze repo by path.
- Commit messages follow the same conventions as the gatewaze repo:
  focus on WHY, not WHAT.

## License

Same license as the gatewaze repo (Apache-2.0).
