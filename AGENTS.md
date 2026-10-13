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
- **Append-only tables — the one documented exception to "every write goes to `audit_logs`"**:
  `receivable_notes` and `app_feedback` have **no UPDATE and no DELETE policy for anyone**, and so
  no `audit_logs` trigger and no `is_cancelled` column. The only possible action is inserting a new
  row, and a row can never change afterwards, so the table is already its own history — an
  `audit_logs` row would duplicate it character for character and add nothing.
  A wrong note is corrected by **writing another note**; both stay visible.
  They also have no `updated_at` / `updated_by` for the same reason (schema.md 1 and 3.6).
  Do not add UPDATE policies, `is_cancelled`, or audit triggers to these two tables without asking.
  Every *other* table keeps the full rule: audit trigger in the same migration, no DELETE.
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
- **Demos always use a test account — never the customer's real owner / sales account.**
  This applies to every demo: class presentations, screen recordings, showing a feature to
  anyone. Reason (7 Oct, written up in progress.md "ผลสัปดาห์แรก" item 3): a demo done with
  the real sales account left 2 companies, 2 cards and 2 payments inside the customer's real
  data. Cards and companies can be cancelled, but the `audit_logs` rows **can never be
  removed**, and in `receivable_notes` / `app_feedback` (append-only) nothing can be removed
  at all. Every report already excludes test data (`display_name` containing "ทดสอบ" and
  companies named `[TEST]%`), so a demo on a real account is the one way non-customer rows
  reach the success-criteria numbers. Create demo companies with the `[TEST]` prefix too.

## Hard rules — UI
- `docs/ui-reference.html` is the approved UI. Match its layout, colors, texts and Thai/English labels.
- **ui-reference.html is frozen at V0.1. Never edit it** — it is the record of what the customer approved.
  When the app changes because of customer feedback, the change is written up in `docs/progress.md`
  (which feedback item, what was decided, why) and **progress.md wins over ui-reference from then on**.
  Before matching ui-reference, read progress.md for a later decision about that screen.
  Any place where the app no longer matches ui-reference must be listed in progress.md.
- **Dates: every date and month field in the app uses `DateField` / `MonthField`
  (`src/components/DateField.jsx`). NEVER use `input type="date"` or `type="month"` anywhere in `src/`.**
  Reason (feedback round 1, 9 Oct): the browser's own fields are month/day/year with English month
  names, and sales entered wrong dates. The app cannot control either, so it owns both fields.
  The shape of these fields is settled; do not redesign them without asking:
  - **One text input the user can type in, plus a calendar icon** — the customer rejected a
    3-dropdown version on 11 Oct (see progress.md "V1 รอบ ก" item 1ก). Typing must stay possible.
  - Order is **`dd/mm/yyyy`** (`mm/yyyy` for the account month) in BOTH languages. Digits only;
    the app inserts the `/` itself. Backspace over an inserted `/` must still delete a digit.
  - A **4-digit year >= 2400 is B.E.** (minus 543), below that is C.E. Accepted range after
    conversion: C.E. 1900–2200.
  - Month names (calendar + the line under the field) follow the language: Thai month names and
    year B.E. in Thai, English month names and year C.E. in English. Weekday headers start Sunday.
  - The calendar is **the app's own**, no date library and no browser `showPicker()`. It closes on
    Esc (without closing the surrounding dialog) and on a click outside.
  - The line under the field shows the date the app understood, in full words
    ("ศุกร์ 9 ตุลาคม 2569"), or a warning when the text is incomplete or impossible.
  - The value in and out of these fields is always ISO C.E. (`YYYY-MM-DD` / `YYYY-MM`) — B.E. is a
    label only, so **always convert to C.E. before sending to the database**, and reject dates that
    do not exist (31 Feb) by emitting an empty value so the form cannot save.
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
