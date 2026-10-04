\# Rules

\- Read docs/prd.md before any work.

\- NEVER put the Supabase secret / service\_role key, passwords or admin tokens in client code.

&#x20; Only VITE\_SUPABASE\_URL and VITE\_SUPABASE\_PUBLISHABLE\_KEY may be used in the browser.

\- Secrets live in .env.local, which must be in .gitignore.

\- Work on ONE milestone at a time. Do not start the next one unless asked.

\- docs/ui-reference.html is the approved UI. When building screens, match its layout,

&#x20; colors and texts. It is a static mockup: replace its in-memory demo data with real

&#x20; Supabase data. Do not copy its demo data into the app.

