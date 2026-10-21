import { getSupabase, isWaitlistConfigured, waitlistFunctionUrl } from './supabase'

export type WaitlistResult =
  | { ok: true; duplicate?: boolean; backed_up?: boolean }
  | { ok: false; message: string }

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase()
}

export function isValidEmail(email: string): boolean {
  return EMAIL_RE.test(email) && email.length <= 254
}

type FunctionResponse = {
  ok?: boolean
  duplicate?: boolean
  backed_up?: boolean
  message?: string
}

async function joinViaEdgeFunction(
  email: string,
  userAgent: string | null,
): Promise<WaitlistResult | null> {
  const url = waitlistFunctionUrl()
  const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined
  if (!url || !anonKey) return null

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${anonKey}`,
        apikey: anonKey,
      },
      body: JSON.stringify({
        email,
        source: 'landing',
        user_agent: userAgent,
      }),
    })

    // Function not deployed yet — let caller fall back to direct insert.
    if (res.status === 404 || res.status === 502) return null

    let data: FunctionResponse = {}
    try {
      data = (await res.json()) as FunctionResponse
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

    return {
      ok: true,
      duplicate: Boolean(data.duplicate),
      backed_up: Boolean(data.backed_up),
    }
  } catch (err) {
    console.error('waitlist_function_unreachable', err)
    return null
  }
}

async function joinViaDirectInsert(
  email: string,
  userAgent: string | null,
): Promise<WaitlistResult> {
  const supabase = getSupabase()
  if (!supabase) {
    return { ok: false, message: 'Could not reach the waitlist service.' }
  }

  const { error } = await supabase.from('waitlist_signups').insert({
    email,
    source: 'landing',
    user_agent: userAgent,
  })

  if (error) {
    if (error.code === '23505') {
      return { ok: true, duplicate: true }
    }
    console.error('waitlist_insert_failed', error.message)
    return { ok: false, message: 'Something went wrong. Please try again in a moment.' }
  }

  return { ok: true }
}

/**
 * Prefer the Edge Function (email + Storage backup). Falls back to a direct
 * table insert if the function is unreachable so signups are never blocked.
 */
export async function joinWaitlist(rawEmail: string): Promise<WaitlistResult> {
  const email = normalizeEmail(rawEmail)
  if (!isValidEmail(email)) {
    return { ok: false, message: 'Please enter a valid email address.' }
  }

  if (!isWaitlistConfigured()) {
    return {
      ok: false,
      message:
        'Waitlist isn’t configured yet. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY.',
    }
  }

  const userAgent =
    typeof navigator !== 'undefined' ? navigator.userAgent.slice(0, 512) : null

  const viaFn = await joinViaEdgeFunction(email, userAgent)
  if (viaFn) return viaFn

  return joinViaDirectInsert(email, userAgent)
}
