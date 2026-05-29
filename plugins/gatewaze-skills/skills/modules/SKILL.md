---
name: modules
description: >
  Gatewaze module development workflow. Invoke when fixing or building anything
  inside a Gatewaze module — admin UI, portal UI, api routes, edge functions,
  or migrations — e.g. newsletters, forms, meetups, events, ambassadors. The
  #1 rule: edit the canonical source in the module's OWN repo
  (~/Git/gatewaze/gatewaze-modules or ~/Git/gatewaze/lf-gatewaze-modules),
  NEVER the gitignored, generated `.gatewaze-modules/` staging directory in the
  gatewaze repo — its materialised copy is silently overwritten on rebuild.
  Covers where each module lives, module anatomy, how `.gatewaze-modules` is
  generated, how to confirm you're editing the real file, and the
  migrate / deploy / type-check workflow.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Gatewaze module development

Gatewaze is a thin host (`gatewaze` monorepo: `packages/{admin,api,portal,shared}`)
plus many **modules**, each a self-contained feature (admin UI, portal UI, api
routes, edge functions, migrations). Modules live in **separate repos** and are
composed into the host at dev/build time.

## ⚠️ The cardinal rule: never edit `.gatewaze-modules/`

`gatewaze/.gatewaze-modules/` is a **gitignored, generated staging directory** —
it is NOT source. It is produced by the dev/build tooling
(`packages/admin/vite-plugin-gatewaze-modules.ts`) and wiped by `make clean`.
Inside it:

- `local-<repo>-modules` → **symlinks** to your local module repos' `modules/`
  dirs (e.g. `local-lf-gatewaze-modules-modules → ~/Git/gatewaze/lf-gatewaze-modules/modules`).
- `github-com-gatewaze-gatewaze-modules` → a **materialised copy** fetched from
  the modules repo.

Editing the materialised copy is silently lost on the next rebuild and never
reaches a real repo. Editing through a symlink *does* reach the repo but is
confusing and easy to get wrong.

**Always edit the canonical source in the module's own repo. Treat
`.gatewaze-modules/` as read-only build output.**

## Where modules actually live

- `~/Git/gatewaze/gatewaze-modules/modules/<name>` — the **public, open-source**
  modules (Apache-2.0). The former premium modules were merged in here, so this
  is now the home for e.g. `newsletters`, `forms`, `events`, `tasks`, `sites`,
  `blog`, `calendars`, `engagement`, `stripe-payments`, `bulk-emailing`, …
- `~/Git/gatewaze/lf-gatewaze-modules/modules/<name>` — **Linux-Foundation /
  AAIF** modules: `ambassadors`, `meetup-ops`, `podcasts`, `press`, `projects`,
  `daily-briefing`, `membership`, `lfid-auth`, `content-discovery`,
  `content-pipeline`, `aaif-import`.
- `premium-gatewaze-modules` is **gone** — merged into `gatewaze-modules`. Any
  stale `.gatewaze-modules/local-premium-*` symlink is a dangling leftover;
  ignore it and use `gatewaze-modules`.

Find a module's repo:

```bash
grep -rl "\"id\": \"<name>\"" ~/Git/gatewaze/*/modules/*/module.json
# or resolve the running symlink:
readlink ~/Git/gatewaze/gatewaze/.gatewaze-modules/local-*-modules
```

## Before you edit — confirm you're on the real file

```bash
readlink -f <path>                 # resolve symlinks; must land in a module repo,
                                   # NOT under .gatewaze-modules/github-com-*
git -C <module-repo> status        # should show your change after you save
```

If `git status` is clean right after an edit, you edited a throwaway copy (or a
concurrent process already committed it) — re-check where the file physically
lives before continuing.

## Module anatomy

```text
modules/<name>/
├── module.json     # manifest: id, name, version, license, group, type, visibility
├── index.ts        # registration: adminRoutes, adminNavItems, portalRoutes,
│                   #   publicApiRoutes, migrations, functions, requiredFeature gating
├── admin/          # admin UI — pages/, components/, slots/, utils/
├── portal/         # public portal UI
├── api/            # server / proxy routes
├── functions/      # Supabase edge functions
├── migrations/     # numbered SQL migrations
├── guide.md  package.json  tsconfig.json  types/  lib/
```

- Admin pages are bundled into `packages/admin` by the vite plugin; inside them
  the `@/` alias resolves to `packages/admin/src`. For admin page layout, follow
  the **ui** skill (WorkspaceLayout: hero, tabs, breadcrumb, sub-tabs).
- Routes/features are declared in `index.ts` (`adminRoutes` with `path`,
  `component`, `requiredFeature`; `adminNavItems` for the left nav).

## Type-checking / linting caveat

A module's own `tsconfig.json` typically only includes `*.ts` / `types/` /
`lib/` — **not** `admin/` or `portal/` (those import host `@/` aliases that only
resolve in the host build). So `tsc` / `pnpm typecheck` in the module repo will
**not** validate admin or portal pages. The authoritative check for those is the
host **admin build** (`pnpm --filter @gatewaze/admin build` / dev server). Host
files you change directly in `gatewaze/packages/admin/src/**` *are* covered by
the gatewaze repo's `tsc`.

## Running locally & applying changes

- The dev server picks up edits to the module repo via the `local-*` symlink
  (HMR) — no copy step needed.
- Run module migrations: `pnpm modules:migrate`.
- Deploy module edge functions: `pnpm modules:deploy-functions`.
- To force a clean module re-sync: `make clean`, then restart dev/build.

## Committing

Commit in the **module repo** (`gatewaze-modules` or `lf-gatewaze-modules`) —
each is its own git repo with its own remote. The `gatewaze` repo gitignores
`.gatewaze-modules/`, so module changes will never show up there; don't look for
them in the host repo's `git status`.

## Don't

- Don't edit anything under `.gatewaze-modules/` (especially `github-com-*`).
- Don't expect module changes in the `gatewaze` repo's `git status` — they live
  in the module repo.
- Don't trust the module repo's `tsc` to catch admin/portal page errors — use
  the host admin build.
- Don't reintroduce `premium-gatewaze-modules`; those modules are in
  `gatewaze-modules` now.
