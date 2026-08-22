---
name: se-handoff
description: Hand off a locally-written spec to the Software Engineer module — creates a GitHub issue with the spec embedded and the agent:spec labels so the SE run skips its own (billed) spec phase. Use when the user says /se-handoff, "hand this spec to SE", "queue this for the SE module", or has just finished writing a spec they want implemented autonomously.
---

# SE Handoff — locally-authored spec → SE module run

Purpose: the user writes specs interactively (on their Claude plan, effectively free) and the SE
module implements them autonomously (API-billed). This skill performs the handoff: it packages a
spec into a GitHub issue that the SE module's intake understands, so the run **skips the spec and
spec-review phases entirely** (≈ a third of a run's API cost) and starts from the human spec gate
or straight at implementation.

## Inputs to establish (ask only for what's missing)

1. **The spec** — usually the document just written in this session (a file, or the conversation's
   final spec text). If ambiguous, ask which file/text is the spec.
   **No spec yet? Write it first — that is part of this skill.** If the user invokes the handoff
   with only an idea or feature description, author the spec in-session before doing anything with
   GitHub: gather the goal, scope/non-goals, constraints, and concrete acceptance criteria (ask the
   minimum questions needed — one batched round), then draft a complete spec (Problem, Approach,
   Scope, Acceptance criteria, Open questions) and show it for approval. Iterate until the user is
   happy — this authoring happens locally on the user's plan precisely so the SE module never bills
   for it. Save the approved spec to a file: `specs/spec-<slug>.md` in the roadmap repo
   (`~/Git/danthebaker/gatewaze-roadmap`) for gatewaze work — commit and push it there — or a
   sensible location the user names for other repos. Then continue with the handoff below.
2. **Target repo** — the GitHub repo the issue goes to (infer from cwd's `git remote get-url origin`
   when inside a repo; otherwise ask). Works for any repo the SE module watches (gatewaze org and
   linuxfoundation LFX repos alike).
3. **Title** — derive from the spec's H1 or first line; confirm only if unclear.
4. **Approval mode** — ask one question unless the user already said:
   - "gate" (default): run parks at the spec gate for approval in the admin UI.
   - "pre-approved": run goes straight to implement (adds `agent:spec:approved`).

## Steps

1. Read the spec content. Sanity-check it is a spec (goal, scope, some acceptance criteria) — if it
   is clearly a fragment, say so and confirm before proceeding. Cap: 64KB (intake rejects larger).
2. Create the issue with `gh`:

   ```bash
   gh issue create --repo <owner>/<repo> \
     --title "<title>" \
     --label "agent:spec:provided" \
     --body "$(cat <<'EOF'
   <one-paragraph summary for humans skimming the issue>

   <!-- se:spec -->
   <the full spec verbatim>
   <!-- /se:spec -->
   EOF
   )"
   ```

   - Pre-approved mode: add `--label "agent:spec:approved"` as well.
   - Optional model pin: if the user asked for a specific model, add `--label "agent:model:<alias>"`
     (`opus` | `sonnet` | `haiku`).
   - If a label does not exist in the repo, create it first
     (`gh label create "agent:spec:provided" --repo <owner>/<repo> --color 5319e7 || true`), then retry.
3. Print the created issue URL and remind the user where the run appears:
   staging admin → Software Engineer → Runs (webhook-driven; the run shows within ~a minute), and —
   in gate mode — that the run will wait at "awaiting spec" for their approval.

## Rules

- The spec goes in the body **between the `<!-- se:spec -->` markers, verbatim** — do not summarize,
  reformat, or truncate it. The human-readable paragraph above the markers is separate.
- Never add `agent:spec:approved` unless the user explicitly chose pre-approved.
- This skill creates issues only — it never modifies the spec content and never merges/closes anything.
