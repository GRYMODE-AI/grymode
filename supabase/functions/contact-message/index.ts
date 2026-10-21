/**
 * Public contact form → emails the admin inbox via Resend.
 *
 * Secrets: RESEND_API_KEY, RESEND_FROM_EMAIL
 * Optional: CONTACT_TO_EMAIL (default hello@grymode.com)
 */
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

type Body = {
  first_name?: string
  last_name?: string
  email?: string
  message?: string
}

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

function clean(raw: unknown, max: number): string {
  return String(raw ?? '')
    .trim()
    .replace(/\s+/g, ' ')
    .slice(0, max)
}

const EMAIL_RE = /^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$/

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }
  if (req.method !== 'POST') {
    return json(405, { ok: false, message: 'Method not allowed' })
  }

  const resendKey = Deno.env.get('RESEND_API_KEY')
  const resendFrom = Deno.env.get('RESEND_FROM_EMAIL')
  const to = Deno.env.get('CONTACT_TO_EMAIL') ?? 'hello@grymode.com'

  if (!resendKey || !resendFrom) {
    console.error('resend_not_configured')
    return json(500, {
      ok: false,
      message: 'Contact isn’t available right now. Please try again later.',
    })
  }

  let body: Body
  try {
    body = (await req.json()) as Body
  } catch {
    return json(400, { ok: false, message: 'Invalid JSON body.' })
  }

  const firstName = clean(body.first_name, 80)
  const lastName = clean(body.last_name, 80)
  const email = clean(body.email, 254).toLowerCase()
  const message = String(body.message ?? '').trim().slice(0, 5000)

  if (firstName.length < 1 || lastName.length < 1) {
    return json(400, { ok: false, message: 'Please enter your first and last name.' })
  }
  if (!EMAIL_RE.test(email)) {
    return json(400, { ok: false, message: 'Please enter a valid email address.' })
  }
  if (message.length < 10) {
    return json(400, {
      ok: false,
      message: 'Please share a little more in your message (at least a sentence).',
    })
  }

  const fullName = `${firstName} ${lastName}`
  const html = `<!DOCTYPE html>
<html lang="en">
<body style="margin:0;padding:24px;background:#F5F3EF;color:#1A1A1A;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">
  <table role="presentation" width="100%" style="max-width:560px;margin:0 auto;background:#FBFAF7;border:1px solid #DCD8CF;border-radius:16px;padding:28px;">
    <tr><td>
      <p style="margin:0 0 6px;font-size:11px;letter-spacing:0.2em;text-transform:uppercase;color:#6B6B4B;">Contact</p>
      <h1 style="margin:0 0 20px;font-family:Georgia,serif;font-size:24px;font-weight:400;">Message from ${fullName}</h1>
      <p style="margin:0 0 8px;font-size:13px;color:#56564F;"><strong>From:</strong> ${fullName}</p>
      <p style="margin:0 0 8px;font-size:13px;color:#56564F;"><strong>Email:</strong> ${email}</p>
      <hr style="border:none;border-top:1px solid #DCD8CF;margin:20px 0;" />
      <p style="margin:0;font-size:15px;line-height:1.65;white-space:pre-wrap;">${message
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')}</p>
    </td></tr>
  </table>
</body>
</html>`

  const text = [
    `Contact from ${fullName}`,
    `Email: ${email}`,
    '',
    message,
  ].join('\n')

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: resendFrom,
      to: [to],
      reply_to: email,
      subject: `Contact · ${fullName}`,
      html,
      text,
      tags: [{ name: 'category', value: 'contact_form' }],
    }),
  })

  if (!res.ok) {
    const detail = await res.text()
    console.error('contact_email_failed', detail.slice(0, 400))
    return json(500, {
      ok: false,
      message: 'Something went wrong. Please try again in a moment.',
    })
  }

  return json(200, { ok: true })
})
