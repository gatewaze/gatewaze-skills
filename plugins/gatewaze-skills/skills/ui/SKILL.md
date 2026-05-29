---
name: ui
description: >
  Gatewaze admin UI layout conventions. Invoke when creating or modifying any
  admin page in the Gatewaze monorepo (packages/admin) or a Gatewaze module's
  admin/pages — adding a new module surface, building a detail/drill-in page,
  or refactoring a hand-rolled header/tab bar onto the shared layout. Explains
  how to lay out any page with the shared WorkspaceLayout primitive (hero,
  primary tabs, the secondary-coloured breadcrumb "flag", sub-tabs) and how to
  decide which of those levels to render from the data's schema shape (flat
  list vs entity-with-sections vs nested sub-entity drill-in, e.g. newsletters
  → editions or meetups → series). Covers the hero-everywhere rule, title and
  breadcrumb conventions, primary vs secondary theming, and full-bleed editors.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Gatewaze UI — admin layout conventions

The Gatewaze admin is one app composed of many modules (Newsletters, Meetups,
Forms, Events, Podcasts, Blog, Sites, Ambassadors, …). Module admin pages live
in the module repos under `admin/pages/` and are bundled into `packages/admin`
at build time by `packages/admin/vite-plugin-gatewaze-modules.ts`. Inside a
module page, the `@/` import alias resolves to `packages/admin/src`.

## The golden rule: every admin page wears the hero

Every page renders the shared `WorkspaceLayout`, whose full-bleed brand hero
shows the module name. **From anywhere in Gatewaze you can always tell which
module you are in.** Never hand-roll a page header or tab bar — if you find one,
migrate it to `WorkspaceLayout`.

```tsx
import { WorkspaceLayout } from '@/components/ui';
import { Page } from '@/components/shared/Page';

<Page title="…">           {/* sets the browser tab title */}
  <WorkspaceLayout title="…" …>
    {/* page content */}
  </WorkspaceLayout>
</Page>
```

Component: `packages/admin/src/components/ui/WorkspaceLayout/index.tsx`.

## What WorkspaceLayout renders (top → bottom)

1. **Hero** — `title`. Always present.
2. **Primary tab strip** — `tabs` + `activeTabId` + `onTabChange`. Optional.
3. **Breadcrumb flag + sub-tab row** (one line) — rendered only when **both**
   `breadcrumbs` **and** `subTabs` are supplied. The breadcrumb is a
   secondary-coloured "flag" with a forward-slash trailing edge; the sub-tabs
   are slim underline tabs beside it.
4. **Actions sub-bar** — `actions` (right-aligned CTAs / contextual buttons).
   Optional.
5. **Content** — `children`.

If you pass only `breadcrumbs` you get a plain breadcrumb bar; only `subTabs`
gives a plain underline sub-tab strip. The coloured flag look needs both.

## Decision tree — render only the levels the schema needs

Recognise the data shape, then map it:

| Schema shape | Example | Hero | Primary tabs | Breadcrumb + sub-tabs |
| --- | --- | --- | --- | --- |
| **Flat list** (a collection of entities) | `/newsletters`, `/forms` | `title="<Module>"` | none | none |
| **Entity with sections** | a newsletter (Details/Template/Editions…) | `title="<Module>: <name>"` | the entity's sections | none |
| **Nested sub-entity drill-in** | a newsletter **edition**; a meetup **series**; a **form** (Builder/Submissions/Share) | `title="<Module>: <parent>"` (or `"<Module>"` when there is no parent entity above) | the parent's sections (lit on the section the sub-entity lives under) | **yes** — flag = `<Section> › <sub-entity id>`, sub-tabs = the sub-entity's views |

**Omit what isn't needed, but never omit the hero.** No sections → no tab strip.
No sub-entity below → no breadcrumb/sub-tabs. An empty tab strip is a bug.

## Conventions

### Hero title
- List page: `title="Newsletters"`.
- Entity / drill-in: `title="Newsletters: AAIF"` — `"<Module>: <entity>"`.

### Primary tabs
The current module/entity's sections, active one lit. `onTabChange` navigates
(use the URL when routes carry a `:tab` segment). Clicking the already-active
tab re-navigates to its base route — this is handled in the shared `Tabs`
component (`packages/admin/src/components/ui/Tabs/index.tsx`), so a drill-in
page's lit tab still returns you to the list.

### Breadcrumb flag
Mirror the meetup/newsletter pattern — `<Section> › <specific entity>`:

```tsx
breadcrumbs={[
  { label: 'Editions', to: `/newsletters/${slug}/editions` }, // section → list
  { label: editionDateLabel },                                // current (no `to`)
]}
onBreadcrumbNavigate={(to) => navigate(to)}
```

- First crumb = the collection/section, linking to its list (e.g. `Editions`,
  `Series`, `Forms`). Last crumb = the specific entity (edition date, series
  title, form name) and has no `to` (it's where you are).
- **Do not put the module name in the breadcrumb** — the hero already shows it.

### Sub-tabs
The sub-entity's own views (e.g. `Editor / Details / Sending`;
`Overview / Themes / Schedule / Settings`; `Builder / Submissions / Share`).
Their active text + underline automatically use the **secondary** colour —
WorkspaceLayout handles this; you don't style it per page.

### Actions
Contextual CTAs (Save, Create, Refresh) and small status/meta badges go in
`actions`, right-aligned in a sub-bar between the tabs and the content.

## Theming: primary vs secondary

Two brand colours are configured in Settings → Admin
(`packages/admin/src/app/pages/settings/sections/Branding.tsx`) and stored in
`platform_settings` as `admin_accent_color` and `admin_secondary_color`:

- **Primary** = the Radix `<Theme>` accent → `--accent-*`. Used for buttons,
  links, primary tabs.
- **Secondary** = `--secondary-*`, aliased onto a Radix colour scale by
  `packages/admin/src/app/contexts/theme/Provider.tsx` (sets
  `--secondary-1/-2/-9/-11` on `<html>`, defaulting to the primary when unset).
  Used for the breadcrumb flag (`--secondary-9` fill, `--secondary-1` row
  background) and the active sub-tab (`--secondary-9` underline /
  `--secondary-11` text).

When you need a faint/saturated/text shade of the secondary, reuse those vars —
don't hard-code a hex.

## Props reference

```ts
interface WorkspaceLayoutProps {
  title: string;
  actions?: ReactNode;
  tabs?: Tab[];                 // primary strip
  activeTabId?: string;
  onTabChange?: (id: string) => void;
  breadcrumbs?: { label: string; to?: string }[];
  onBreadcrumbNavigate?: (to: string) => void;
  subTabs?: Tab[];              // Tab = { id, label, icon?, count? }
  activeSubTabId?: string;
  onSubTabChange?: (id: string) => void;
  children: ReactNode;
}
```

`Tab` is imported from `@/components/ui/Tabs`. WorkspaceLayout is router-free:
navigation is delegated to the consumer via `onTabChange` /
`onBreadcrumbNavigate` / `onSubTabChange`.

## Module layout wrappers

A module with module-level sections (a top nav shared by every page, like
Meetups: Dashboard/Programme/Series/Venues/…) wraps WorkspaceLayout once in a
module layout that owns the `TABS` and URL-driven active-tab logic, then each
page passes only `breadcrumbs`/`subTabs`/`actions`. See
`meetup-ops/admin/components/MeetupOpsLayout.tsx`. Modules without a module-level
nav (Newsletters, Forms) use WorkspaceLayout directly per page.

## Full-bleed content (editors, canvases)

WorkspaceLayout pads its content (`px-6`, top/bottom). A full-bleed editor must
escape that padding and reclaim height:

```tsx
<div className="-mx-[calc(var(--margin-x)+1.5rem)] -mt-4 -mb-6" style={{ height: measuredHeight }}>
```

Measure the wrapper's `top` against the viewport (ResizeObserver) so the height
adapts to whatever chrome sits above — never hard-code a `100vh - Npx` offset.
See `newsletters/admin/pages/editions/[id].tsx` (the Puck editor tab).

## Worked examples (read these before building)

- **Flat list**: `newsletters/admin/pages/list.tsx`,
  `forms/admin/pages/index.tsx` — hero only, CTAs in `actions`.
- **Entity with sections**: `newsletters/admin/pages/detail.tsx` —
  `Newsletters: <name>` + section tabs.
- **Sub-entity drill-in**: `newsletters/admin/pages/editions/[id].tsx`,
  `meetup-ops/admin/pages/SeriesDetailPage.tsx`,
  `forms/admin/pages/detail/index.tsx` — hero + tabs + flag + sub-tabs.

## Don't

- Don't hand-roll a hero or tab bar; use WorkspaceLayout.
- Don't render a tab strip with no tabs, or a breadcrumb that has no sub-entity
  to point at.
- Don't repeat the module name in the breadcrumb (it's in the hero).
- Don't colour the breadcrumb flag or active sub-tab with the primary accent —
  they use the secondary scale.
- Don't hard-code brand hexes; use `--accent-*` / `--secondary-*`.
