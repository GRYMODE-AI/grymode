/**
 * Public waitlist signup endpoint.
 *
 * 1. Validate + insert into waitlist_signups (service role)
 * 2. Mirror the row to Storage bucket `waitlist-backups` (data backup)
 * 3. Send a welcome email via Resend
 *
 * Secrets (supabase secrets set / supabase/.env for local):
 *   RESEND_API_KEY, RESEND_FROM_EMAIL
 * Optional:
 *   RESEND_AUDIENCE_ID  — also add contact to a Resend audience
 *   WAITLIST_SITE_URL   — link target in the email (default https://grymode.ai)
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const EMAIL_RE = /^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$/
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

type Body = {
  email?: string
  source?: string
  user_agent?: string | null
}

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase()
}

function welcomeHtml(email: string, siteUrl: string): string {
  const year = new Date().getFullYear()
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>You're on the Grymode AI waitlist</title>
</head>
<body style="margin:0;padding:0;background:#F5F3EF;color:#1A1A1A;font-family:Georgia,'Times New Roman',serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F5F3EF;padding:40px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width:520px;background:#FBFAF7;border:1px solid #DCD8CF;border-radius:16px;padding:36px 28px;">
          <tr>
            <td>
              <p style="margin:0 0 8px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:11px;letter-spacing:0.22em;text-transform:uppercase;color:#6B6B4B;">
                Grymode AI
              </p>
              <h1 style="margin:0 0 16px;font-size:28px;line-height:1.25;font-weight:400;">
                You're on the list.
              </h1>
              <p style="margin:0 0 14px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:15px;line-height:1.65;font-weight:300;color:#56564F;">
                Thanks for joining the Grymode AI waitlist${email ? ` (<span style="color:#1A1A1A">${email}</span>)` : ''}.
                We'll write when early access opens — discreetly, and only when it matters.
              </p>
              <p style="margin:0 0 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:15px;line-height:1.65;font-weight:300;color:#56564F;">
                Your wardrobe has more to say.
              </p>
              <a href="${siteUrl}" style="display:inline-block;background:#1A1A1A;color:#F5F3EF;text-decoration:none;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:13px;letter-spacing:0.04em;padding:12px 22px;border-radius:999px;">
                Visit Grymode
              </a>
              <p style="margin:28px 0 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:11px;line-height:1.5;color:#8A8A8A;">
                © ${year} Grymode AI. You received this because you joined the waitlist.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`
}

function welcomeText(email: string, siteUrl: string): string {
  return [
    `You're on the Grymode AI waitlist.`,
    ``,
    `Thanks for joining${email ? ` (${email})` : ''}. We'll write when early access opens.`,
    ``,
    `Your wardrobe has more to say.`,
    siteUrl,
  ].join('\n')
}

async function sendResend(opts: {
  apiKey: string
  from: string
  to: string
  siteUrl: string
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${opts.apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: opts.from,
      to: [opts.to],
      subject: "You're on the Grymode AI waitlist",
      html: welcomeHtml(opts.to, opts.siteUrl),
      text: welcomeText(opts.to, opts.siteUrl),
      tags: [{ name: 'category', value: 'waitlist_welcome' }],
    }),
  })

  if (!res.ok) {
    const detail = await res.text()
    return { ok: false, error: `resend_${res.status}: ${detail.slice(0, 400)}` }
  }
  return { ok: true }
}

async function addToAudience(opts: {
  apiKey: string
  audienceId: string
  email: string
}): Promise<void> {
  await fetch(`https://api.resend.com/audiences/${opts.audienceId}/contacts`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${opts.apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      email: opts.email,
      unsubscribed: false,
    }),
  }).catch(() => {
    /* audience mirror is best-effort */
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }
  if (req.method !== 'POST') {
    return json(405, { ok: false, message: 'Method not allowed' })
  }

  // Prefer WAITLIST_* so local `functions serve` can target hosted DB
  // (CLI blocks overriding env vars that start with SUPABASE_).
  const supabaseUrl =
    Deno.env.get('WAITLIST_SUPABASE_URL') ?? Deno.env.get('SUPABASE_URL')
  const serviceKey =
    Deno.env.get('WAITLIST_SERVICE_ROLE_KEY') ??
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const resendKey = Deno.env.get('RESEND_API_KEY')
  const resendFrom = Deno.env.get('RESEND_FROM_EMAIL')
  const audienceId = Deno.env.get('RESEND_AUDIENCE_ID')
  const siteUrl = Deno.env.get('WAITLIST_SITE_URL') ?? 'https://grymode.ai'

  if (!supabaseUrl || !serviceKey) {
    return json(500, { ok: false, message: 'Server misconfigured (Supabase).' })
  }

  let body: Body
  try {
    body = (await req.json()) as Body
  } catch {
    return json(400, { ok: false, message: 'Invalid JSON body.' })
  }

  const email = normalizeEmail(String(body.email ?? ''))
  if (!EMAIL_RE.test(email) || email.length > 254) {
    return json(400, { ok: false, message: 'Please enter a valid email address.' })
  }

  const source = String(body.source ?? 'landing').slice(0, 40) || 'landing'
  const userAgent =
    typeof body.user_agent === 'string' ? body.user_agent.slice(0, 512) : null

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  // One email → one row. Pre-check, then unique index as race guard.
  const { data: existingRow } = await admin
    .from('waitlist_signups')
    .select('id, backed_up_at, email_sent_at')
    .eq('email', email)
    .maybeSingle()

  if (existingRow) {
    return json(200, {
      ok: true,
      duplicate: true,
      backed_up: Boolean(existingRow.backed_up_at),
    })
  }

  const { data: row, error: insertError } = await admin
    .from('waitlist_signups')
    .insert({ email, source, user_agent: userAgent })
    .select('id, email, source, user_agent, created_at')
    .single()

  if (insertError) {
    if (insertError.code === '23505') {
      return json(200, { ok: true, duplicate: true })
    }
    console.error('waitlist_insert_failed', insertError.message)
    return json(500, {
      ok: false,
      message: 'Something went wrong. Please try again in a moment.',
    })
  }

  const record = row
  if (!record) {
    return json(500, { ok: false, message: 'Something went wrong. Please try again in a moment.' })
  }
  const duplicate = false

  // --- Durable backup (one JSON object per signup; idempotent upsert) ---
  let backedUp = Boolean(
    'backed_up_at' in record && (record as { backed_up_at?: string | null }).backed_up_at,
  )
  if (!backedUp) {
    const backupPath = `records/${record.id}.json`
    const payload = {
      id: record.id,
      email: record.email,
      source: record.source,
      user_agent: record.user_agent,
      created_at: record.created_at,
      backed_up_at: new Date().toISOString(),
      schema_version: 1,
    }
    const { error: uploadError } = await admin.storage
      .from('waitlist-backups')
      .upload(backupPath, JSON.stringify(payload, null, 2), {
        contentType: 'application/json',
        upsert: true,
      })

    if (uploadError) {
      console.error('waitlist_backup_failed', uploadError.message)
    } else {
      backedUp = true
      await admin
        .from('waitlist_signups')
        .update({ backed_up_at: new Date().toISOString() })
        .eq('id', record.id)
    }
  }

  // --- Welcome email (skip if already sent) ---
  const alreadySent = Boolean(
    'email_sent_at' in record && (record as { email_sent_at?: string | null }).email_sent_at,
  )

  if (!alreadySent) {
    if (!resendKey || !resendFrom) {
      console.error('resend_not_configured')
      await admin
        .from('waitlist_signups')
        .update({ email_error: 'RESEND_API_KEY or RESEND_FROM_EMAIL missing' })
        .eq('id', record.id)
    } else {
      const sent = await sendResend({
        apiKey: resendKey,
        from: resendFrom,
        to: email,
        siteUrl,
      })
      if (sent.ok) {
        await admin
          .from('waitlist_signups')
          .update({ email_sent_at: new Date().toISOString(), email_error: null })
          .eq('id', record.id)
        if (audienceId) {
          await addToAudience({ apiKey: resendKey, audienceId, email })
        }
      } else {
        console.error('waitlist_email_failed', sent.error)
        await admin
          .from('waitlist_signups')
          .update({ email_error: sent.error })
          .eq('id', record.id)
      }
    }
  }

  return json(200, { ok: true, duplicate, backed_up: backedUp })
})
