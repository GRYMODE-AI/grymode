import { isWaitlistConfigured, contactFunctionUrl } from './supabase'

export type ContactPayload = {
  firstName: string
  lastName: string
  email: string
  message: string
}

export type ContactResult = { ok: true } | { ok: false; message: string }

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export async function submitContact(payload: ContactPayload): Promise<ContactResult> {
  const firstName = payload.firstName.trim()
  const lastName = payload.lastName.trim()
  const email = payload.email.trim().toLowerCase()
  const message = payload.message.trim()

  if (!firstName || !lastName) {
    return { ok: false, message: 'Please enter your first and last name.' }
  }
  if (!EMAIL_RE.test(email) || email.length > 254) {
    return { ok: false, message: 'Please enter a valid email address.' }
  }
  if (message.length < 10) {
    return {
      ok: false,
      message: 'Please share a little more in your message (at least a sentence).',
    }
  }

  if (!isWaitlistConfigured()) {
    return {
      ok: false,
      message: 'Contact isn’t configured yet. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY.',
    }
  }

  const url = contactFunctionUrl()
  const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined
  if (!url || !anonKey) {
    return { ok: false, message: 'Could not reach the contact service.' }
  }

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${anonKey}`,
        apikey: anonKey,
      },
      body: JSON.stringify({
        first_name: firstName.slice(0, 80),
        last_name: lastName.slice(0, 80),
        email,
        message: message.slice(0, 5000),
      }),
    })

    let data: { ok?: boolean; message?: string } = {}
    try {
      data = (await res.json()) as { ok?: boolean; message?: string }
    } catch {
      /* ignore */
    }

    if (!res.ok || !data.ok) {
      return {
        ok: false,
        message:
          data.message || 'Something went wrong. Please try again in a moment.',
      }
    }

    return { ok: true }
  } catch (err) {
    console.error('contact_function_unreachable', err)
    return {
      ok: false,
      message: 'Something went wrong. Please try again in a moment.',
    }
  }
}
