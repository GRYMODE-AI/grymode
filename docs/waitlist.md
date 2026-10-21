# Waitlist: Supabase + Resend + backup

Signup flow for the marketing site (`landing-page/`):

1. Browser posts to Edge Function `waitlist-signup` (anon JWT).
2. Function inserts into `public.waitlist_signups` (service role).
3. Function writes a JSON mirror to Storage bucket `waitlist-backups` (`records/{id}.json`).
4. Function sends a welcome email via [Resend](https://resend.com).
5. If the function is unreachable, the form falls back to a direct anon insert (email/backup skipped until the function is deployed).

## Migrations

```bash
supabase db push
# or locally:
supabase migration up --local
```

Relevant files:

- `supabase/migrations/20261019160000_waitlist_signups.sql` — table + RLS
- `supabase/migrations/20261020120000_waitlist_email_backup.sql` — tracking columns + backup bucket

## Environment

| Location | Keys |
|----------|------|
| `landing-page/.env` | `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` |
| `supabase/.env` (local functions) / `supabase secrets` (hosted) | `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, optional `RESEND_AUDIENCE_ID`, `WAITLIST_SITE_URL` |

Never put `RESEND_*` or the **service role** key in the Vite app.

```bash
cp supabase/.env.example supabase/.env
# edit RESEND_API_KEY + RESEND_FROM_EMAIL

cp landing-page/.env.example landing-page/.env
# edit VITE_SUPABASE_*
```

### Deploy the function

```bash
supabase functions deploy waitlist-signup
supabase secrets set --env-file supabase/.env
```

### Local serve

```bash
supabase start
supabase functions serve waitlist-signup --env-file supabase/.env
```

Point `landing-page` at the local API URL from `supabase status`.

## Backup & restore

Primary store: Postgres `waitlist_signups`.

**Backup mirrors:** private Storage bucket `waitlist-backups`, one file per signup:

```
records/<uuid>.json
```

Example object:

```json
{
  "id": "…",
  "email": "someone@example.com",
  "source": "landing",
  "user_agent": "…",
  "created_at": "2026-10-20T…",
  "backed_up_at": "2026-10-20T…",
  "schema_version": 1
}
```

Download (service role / dashboard):

```bash
supabase storage ls waitlist-backups/records --experimental
# or use the Supabase Dashboard → Storage → waitlist-backups
```

Tracking columns on the row: `backed_up_at`, `email_sent_at`, `email_error`.

Optional second mirror: set `RESEND_AUDIENCE_ID` so each signup is also added as a Resend Contact.

## Contact form

Footer **Contact** opens a modal (first name, last name, email, message). Submissions go through Edge Function `contact-message` → Resend → `CONTACT_TO_EMAIL` (default `hello@grymode.com`), with `reply_to` set to the visitor’s email.

```bash
supabase functions deploy contact-message
supabase secrets set --env-file supabase/.env
```
