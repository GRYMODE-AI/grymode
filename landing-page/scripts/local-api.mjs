/**
 * Local waitlist + contact API for testing without Docker Edge Runtime.
 * Writes to hosted Supabase and sends mail via Resend.
 *
 *   node scripts/local-api.mjs
 *
 * Reads secrets from ../supabase/.env.serve (or ../supabase/.env).
 */
import { createServer } from 'node:http'
import { readFileSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const envPath = [resolve(root, 'supabase/.env.serve'), resolve(root, 'supabase/.env')].find(
  (p) => existsSync(p),
)

function loadEnv(path) {
  const out = {}
  if (!path) return out
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    const t = line.trim()
    if (!t || t.startsWith('#')) continue
    const i = t.indexOf('=')
    if (i < 0) continue
    out[t.slice(0, i)] = t.slice(i + 1)
  }
  return out
}

const env = loadEnv(envPath)
const PORT = Number(process.env.PORT || 8787)
const SUPABASE_URL = env.WAITLIST_SUPABASE_URL || env.SUPABASE_URL
const SERVICE_KEY = env.WAITLIST_SERVICE_ROLE_KEY || env.SUPABASE_SERVICE_ROLE_KEY
const RESEND_KEY = env.RESEND_API_KEY
const RESEND_FROM = env.RESEND_FROM_EMAIL || 'Grymode AI <hello@grymode.com>'
const CONTACT_TO = env.CONTACT_TO_EMAIL || 'hello@grymode.com'
const SITE_URL = env.WAITLIST_SITE_URL || 'http://127.0.0.1:5173'

const EMAIL_RE = /^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$/

function json(res, status, body) {
  const payload = JSON.stringify(body)
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  })
  res.end(payload)
}

async function readBody(req) {
  const chunks = []
  for await (const c of req) chunks.push(c)
  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}')
}

async function sb(path, { method = 'GET', body, prefer } = {}) {
  const headers = {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    'Content-Type': 'application/json',
  }
  if (prefer) headers.Prefer = prefer
  const res = await fetch(`${SUPABASE_URL}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  let data = null
  try {
    data = text ? JSON.parse(text) : null
  } catch {
    data = text
  }
  return { ok: res.ok, status: res.status, data }
}

async function sendResend({ to, subject, html, text, replyTo }) {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: RESEND_FROM,
      to: [to],
      subject,
      html,
      text,
      ...(replyTo ? { reply_to: replyTo } : {}),
      tags: [{ name: 'category', value: 'waitlist_or_contact' }],
    }),
  })
  const detail = await res.text()
  return { ok: res.ok, status: res.status, detail }
}

async function handleWaitlist(body) {
  const email = String(body.email || '')
    .trim()
    .toLowerCase()
  if (!EMAIL_RE.test(email) || email.length > 254) {
    return { status: 400, body: { ok: false, message: 'Please enter a valid email address.' } }
  }
  const source = String(body.source || 'landing').slice(0, 40) || 'landing'
  const user_agent =
    typeof body.user_agent === 'string' ? body.user_agent.slice(0, 512) : null

  // One email → one row. Check first, then rely on unique index as a race guard.
  const existing = await sb(
    `/rest/v1/waitlist_signups?email=eq.${encodeURIComponent(email)}&select=id,email,backed_up_at,email_sent_at&limit=1`,
  )
  if (Array.isArray(existing.data) && existing.data[0]) {
    return {
      status: 200,
      body: {
        ok: true,
        duplicate: true,
        backed_up: Boolean(existing.data[0].backed_up_at),
      },
    }
  }

  const inserted = await sb('/rest/v1/waitlist_signups', {
    method: 'POST',
    prefer: 'return=representation',
    body: { email, source, user_agent },
  })

  let record = null
  if (inserted.ok && Array.isArray(inserted.data) && inserted.data[0]) {
    record = inserted.data[0]
  } else if (
    inserted.status === 409 ||
    (typeof inserted.data === 'object' && inserted.data?.code === '23505')
  ) {
    // Race: another request inserted the same email first.
    return { status: 200, body: { ok: true, duplicate: true } }
  } else {
    console.error('waitlist_insert_failed', inserted.status, inserted.data)
    return {
      status: 500,
      body: { ok: false, message: 'Something went wrong. Please try again in a moment.' },
    }
  }

  let backed_up = false
  const payload = {
    id: record.id,
    email: record.email,
    source: record.source,
    user_agent: record.user_agent,
    created_at: record.created_at,
    backed_up_at: new Date().toISOString(),
    schema_version: 1,
  }
  const up = await fetch(
    `${SUPABASE_URL}/storage/v1/object/waitlist-backups/records/${record.id}.json`,
    {
      method: 'POST',
      headers: {
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
        'Content-Type': 'application/json',
        'x-upsert': 'true',
      },
      body: JSON.stringify(payload, null, 2),
    },
  )
  if (up.ok) {
    backed_up = true
    await sb(`/rest/v1/waitlist_signups?id=eq.${record.id}`, {
      method: 'PATCH',
      body: { backed_up_at: new Date().toISOString() },
    })
  } else {
    console.error('waitlist_backup_failed', await up.text())
  }

  const sent = await sendResend({
    to: email,
    subject: "You're on the Grymode AI waitlist",
    text: `You're on the Grymode AI waitlist.\n\nThanks for joining (${email}). We'll write when early access opens.\n\nYour wardrobe has more to say.\n${SITE_URL}`,
    html: `<p>You're on the <strong>Grymode AI</strong> waitlist.</p><p>Thanks for joining (<em>${email}</em>). We'll write when early access opens.</p><p>Your wardrobe has more to say.</p>`,
  })
  if (sent.ok) {
    await sb(`/rest/v1/waitlist_signups?id=eq.${record.id}`, {
      method: 'PATCH',
      body: { email_sent_at: new Date().toISOString(), email_error: null },
    })
  } else {
    console.error('waitlist_email_failed', sent.status, sent.detail)
    await sb(`/rest/v1/waitlist_signups?id=eq.${record.id}`, {
      method: 'PATCH',
      body: { email_error: `resend_${sent.status}: ${sent.detail.slice(0, 400)}` },
    })
  }

  return { status: 200, body: { ok: true, duplicate: false, backed_up } }
}

async function handleContact(body) {
  const first = String(body.first_name || '').trim().slice(0, 80)
  const last = String(body.last_name || '').trim().slice(0, 80)
  const email = String(body.email || '')
    .trim()
    .toLowerCase()
  const message = String(body.message || '').trim().slice(0, 5000)
  if (!first || !last) {
    return { status: 400, body: { ok: false, message: 'Please enter your first and last name.' } }
  }
  if (!EMAIL_RE.test(email)) {
    return { status: 400, body: { ok: false, message: 'Please enter a valid email address.' } }
  }
  if (message.length < 10) {
    return {
      status: 400,
      body: {
        ok: false,
        message: 'Please share a little more in your message (at least a sentence).',
      },
    }
  }
  const full = `${first} ${last}`
  const sent = await sendResend({
    to: CONTACT_TO,
    replyTo: email,
    subject: `Contact · ${full}`,
    text: `Contact from ${full}\nEmail: ${email}\n\n${message}`,
    html: `<p><strong>From:</strong> ${full} &lt;${email}&gt;</p><pre style="white-space:pre-wrap;font-family:sans-serif">${message
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')}</pre>`,
  })
  if (!sent.ok) {
    console.error('contact_email_failed', sent.status, sent.detail)
    return {
      status: 500,
      body: { ok: false, message: 'Something went wrong. Please try again in a moment.' },
    }
  }
  return { status: 200, body: { ok: true } }
}

if (!SUPABASE_URL || !SERVICE_KEY || !RESEND_KEY) {
  console.error('Missing WAITLIST_SUPABASE_URL / WAITLIST_SERVICE_ROLE_KEY / RESEND_API_KEY in', envPath)
  process.exit(1)
}

createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    return json(res, 200, { ok: true })
  }
  const url = new URL(req.url || '/', `http://127.0.0.1:${PORT}`)
  try {
    if (req.method === 'POST' && url.pathname.endsWith('/waitlist-signup')) {
      const body = await readBody(req)
      const out = await handleWaitlist(body)
      return json(res, out.status, out.body)
    }
    if (req.method === 'POST' && url.pathname.endsWith('/contact-message')) {
      const body = await readBody(req)
      const out = await handleContact(body)
      return json(res, out.status, out.body)
    }
    return json(res, 404, { ok: false, message: 'Not found' })
  } catch (err) {
    console.error(err)
    return json(res, 500, { ok: false, message: 'Something went wrong. Please try again in a moment.' })
  }
}).listen(PORT, '127.0.0.1', () => {
  console.log(`Local waitlist/contact API on http://127.0.0.1:${PORT}`)
  console.log(`  POST /waitlist-signup`)
  console.log(`  POST /contact-message`)
  console.log(`  DB: ${SUPABASE_URL}`)
  console.log(`  From: ${RESEND_FROM}`)
})
