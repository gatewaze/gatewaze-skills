# gatewaze-skills

Claude skills for working on the [Gatewaze](https://github.com/gatewaze/gatewaze)
monorepo. Each subdirectory is a self-contained
[Claude skill](https://docs.claude.com/en/docs/claude-code/skills)
with a `SKILL.md` plus a `references/` directory of topic-specific
deep-dives.

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

## How to use these skills

### Symlink into `~/.claude/skills/`

Each skill's directory is a symlink target. To make a skill available
across all sessions:

```bash
ln -sf "$(pwd)/gatewaze-production-readiness" ~/.claude/skills/gatewaze-production-readiness
```

Claude will discover it on next session start.

### Invoke explicitly

If a skill is registered in your `~/.claude/skills/`, type
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
