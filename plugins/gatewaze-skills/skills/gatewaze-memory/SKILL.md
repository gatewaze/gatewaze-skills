---
name: gatewaze-memory
description: >
  Use the project's accumulated engineering MEMORY while developing Gatewaze
  locally — the same durable knowledge the Software Engineer agent uses. It
  lives in the AI memory wiki and is git-synced to a dedicated memory repo
  (danthebaker/gatewaze-memory for the gatewaze monorepo;
  danthebaker/lfx-memory for LFX). Invoke at the START of a task on a
  Gatewaze/LFX repo ("what do we already know about X", "recall memory",
  "anything to watch out for here"), BEFORE committing (to check your changes
  against known gotchas/conventions), and when you learn something durable
  ("record a learning", "remember that ..."). This closes the loop: local dev
  and the SE agent share one brain — you read what the agent learned, and your
  learnings flow back to it.
allowed-tools: Bash, Read, Grep, Glob, Write
---

# Gatewaze project memory (local)

The Software Engineer module keeps **durable, per-project engineering memory** in
the AI wiki and **git-syncs the approved memory to a dedicated repo** after every
approval. That repo is the local, read-only mirror you use here. Recalling it
locally means you develop with the *same* accumulated knowledge — architecture,
conventions, gotchas, past incidents — that the agent has, and your new learnings
can flow back to it.

**Source of truth:** the AI wiki. The repo's `wiki/` tree is a **mirror** —
never hand-edit it; it is overwritten on the next sync. The write path is
`proposals/` (see step 4), which a human promotes into the wiki.

## Which memory repo

| Working on | Memory repo |
|---|---|
| the `gatewaze` monorepo (packages/*) or `gatewaze-modules` | `danthebaker/gatewaze-memory` |
| LFX (`linuxfoundation/lfx-*`) | `danthebaker/lfx-memory` |

Pick by the repo you're in; if unsure, ask. Below, `$MEMREPO` is that `owner/name`.

## 1. Sync the mirror locally (do this first)

Clone or fast-forward the memory repo into a cache dir (uses your own git/gh
credentials — you have access):

```bash
MEMREPO="danthebaker/gatewaze-memory"          # or danthebaker/lfx-memory
CACHE="$HOME/.cache/gatewaze-memory/${MEMREPO##*/}"
if [ -d "$CACHE/.git" ]; then
  git -C "$CACHE" pull --ff-only --quiet
else
  mkdir -p "$(dirname "$CACHE")"
  git clone --quiet "https://github.com/$MEMREPO.git" "$CACHE"
fi
ls "$CACHE/wiki" 2>/dev/null | head
```

`index.md` lists every page; `wiki/imported/memory.md` is the top-level index of
project facts. Pages are one fact each (architecture, conventions, gotchas,
incidents), mirroring the agent's memory.

## 2. RECALL — pull in what's relevant to the task

Don't dump everything. Find the pages that bear on what you're about to do:

```bash
# by keyword across all memory pages (e.g. the feature/area you're touching)
grep -rli "newsletter\|sendgrid\|<your keywords>" "$CACHE/wiki" | head
```

Read the top matches (`Read`), plus `wiki/imported/memory.md` for the index, and
fold the relevant facts into how you approach the task. Prefer memory over
guessing — it records real decisions and past failures. Cite the page when you
rely on it (e.g. "per `wiki/imported/project-docker-dep-float-hazard.md` …").

## 3. CHECK — review local changes against memory before committing

Before you commit, cross-check your diff against known hazards/conventions:

```bash
git diff --name-only            # what you changed
```

For each changed area, grep memory for warnings (gotchas, "never do X",
conventions) and flag anything your change trips. Examples the memory encodes:
module files must not import `@radix-ui/themes`; edit modules in their source
repo not the `.gatewaze-modules` cache; caret-dep float hazards; etc. Report
matches as "⚠ memory says: … (`wiki/<page>`)" so the human can decide.

## 4. PROPOSE A LEARNING — write back durable knowledge

When you discover something durable and reusable (a gotcha, a convention, a
"we tried X, it failed because Y"), record it — but **never edit `wiki/`** (the
sync overwrites it). Write to `proposals/` instead, which survives the sync, then
commit + push so a human can promote it into the wiki (the SE admin approval
gate keeps memory trustworthy):

```bash
SLUG="short-kebab-slug"                          # e.g. portal-runtime-import-crash
mkdir -p "$CACHE/proposals"
cat > "$CACHE/proposals/$SLUG.md" <<'MD'
---
type: project | feedback | reference
proposed_by: local-dev
---

<the durable fact. For feedback/project add **Why:** and **How to apply:** lines.
Link related pages with [[their-slug]].>
MD
git -C "$CACHE" add "proposals/$SLUG.md"
git -C "$CACHE" commit -qm "propose(memory): $SLUG"
git -C "$CACHE" push --quiet
echo "Proposed — a maintainer promotes proposals/ into the wiki via the SE admin."
```

Keep one fact per file (same shape the agent's memory uses). Check `proposals/`
first so you update an existing proposal rather than duplicating it.

## Notes
- **Read from `wiki/`, write to `proposals/`.** The `wiki/` mirror is regenerated
  from the AI wiki on every SE memory approval, so hand-edits there are lost.
- If `git pull` shows nothing and `wiki/` is empty, that project simply has no
  approved memory yet — proceed without it and propose learnings as you go.
- This is the same memory the SE agent recalls (via the wiki's RAG), so what you
  contribute here becomes context for future automated runs once promoted.
