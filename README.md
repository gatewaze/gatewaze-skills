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
  skills/
    production-readiness/
    ui/
    modules/
```

## Skills in this repo

### [`production-readiness/`](./plugins/gatewaze-skills/skills/production-readiness/SKILL.md)

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

### [`ui/`](./plugins/gatewaze-skills/skills/ui/SKILL.md)

Admin UI layout conventions. How to lay out any admin page with the
shared `WorkspaceLayout` primitive (hero, primary tabs, the
secondary-coloured breadcrumb "flag", and sub-tabs), and a decision
tree for which of those levels to render based on the data's schema
shape — flat list (hero only), entity-with-sections (hero + primary
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
explicitly. You don't have to invoke explicitly — once installed, the
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
during gatewaze work — a new security boundary, a new typing
challenge, a new lint configuration — add a section to the relevant
`references/<topic>.md` (or create a new reference file and link it
from `SKILL.md`).

The plugin manifest deliberately omits `version`, so every pushed
commit is treated as a new version and contributors pick up skill
updates automatically (run `/plugin marketplace update` to refresh).

The existing fixes that motivated each rule are cited by file path
and commit hash. When you add a new rule, follow the same format —
it's the difference between a guideline and an enforceable
convention.

## Repo conventions

- One skill per directory under `plugins/gatewaze-skills/skills/`.
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
