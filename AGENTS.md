# AGENTS.md — Standing rules for AI coding agents

Project: OK receivables tracker (multi-user PWA). Read this file at the start of every session.

## Before any work
- Read `docs/prd.md`, `docs/schema.md`, `docs/architecture.md`, `docs/implementation-plan.md`, `docs/progress.md`.
- Work on ONE milestone from implementation-plan.md at a time. Do not start the next one unless asked.
- If a rule in the docs is ambiguous or the docs disagree with each other, STOP and list the questions. Do not guess.

## Hard rules — security
- NEVER put the Supabase secret / service_role key, database password or any admin token in client code, `.env.example`, docs or commits.
  Only `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` may be used in the browser.
- Every table has row-level security ON. Write its policies in the same migration that creates the table.
- Role checks happen in RLS policies (via `public.my_role()`), not only in the UI. Hiding a button is not security.
- No DELETE on any table. No DELETE policies. Use `is_cancelled` / `is_active`.
- `audit_logs` is written only by database triggers. Never insert, update or delete it from the app.
- Users cannot change their own role. No UPDATE policy on `profiles`.
- Sign-up is disabled. Do not build a sign-up screen.

## Hard rules — data
- Follow `docs/schema.md` exactly. Do not rename, add or remove tables or columns without asking.
  If a change is approved, update schema.md in the same commit as the migration.
- Database changes only through new files in `supabase/migrations/` (numbered, never edit one that has been run).
- Money: `numeric(14,2)` in the database. All money and date calculations live in the `receivable_summary` view.
  The app only formats numbers. Never compute balances with JavaScript floats.
- "Today" is Thai time: `(now() at time zone 'Asia/Bangkok')::date`. Never use plain `current_date`.
- Never seed or copy the demo data from `docs/ui-reference.html` into the database or the app.

## Hard rules — UI
- `docs/ui-reference.html` is the approved UI. Match its layout, colors, texts and Thai/English labels.
- Mobile-first. Must work on iPhone Safari and Android Chrome.
- NEVER use `window.alert`, `window.confirm` or `window.prompt` (blocked in some PWA and embedded contexts).
  Use in-app dialogs. Destructive actions use the two-step confirm pattern from ui-reference.
- Every screen has a loading state, an empty state and a clear error message (no signal, permission denied, validation).
- Service worker caches the app shell only. Never cache Supabase API responses.

## Definition of done (every milestone)
- [ ] Tested with TWO accounts of different roles (owner + sales) in two browsers.
- [ ] Every cell of the prd.md permissions table that this milestone touches was tested with the WRONG role and was blocked.
- [ ] Works on a phone. No errors in the browser console.
- [ ] `npm run build` and `npm run lint` pass.
- [ ] No secrets in the repo (search for `service_role`, `secret`, real key values).
- [ ] `docs/progress.md` updated: what was done, what is broken, migrations run.
- [ ] If behavior differs from the docs, the docs are updated in the same commit.
- [ ] Committed with a clear message, e.g. `feat(M2): tables, RLS and audit triggers`.

## When you finish
Summarize: files changed, how to test it (with which account), and anything you were unsure about.
