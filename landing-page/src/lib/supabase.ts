import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined
const functionUrlOverride = import.meta.env.VITE_WAITLIST_FUNCTION_URL as
  | string
  | undefined
const contactUrlOverride = import.meta.env.VITE_CONTACT_FUNCTION_URL as
  | string
  | undefined

let client: SupabaseClient | null = null

export function getSupabase(): SupabaseClient | null {
  if (!url || !anonKey) return null
  if (!client) {
    client = createClient(url, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
  }
  return client
}

export function isWaitlistConfigured(): boolean {
  return Boolean(url && anonKey)
}

/** Edge Function that inserts, backs up, and sends the Resend welcome email. */
export function waitlistFunctionUrl(): string | null {
  if (functionUrlOverride?.trim()) return functionUrlOverride.trim()
  if (!url) return null
  return `${url.replace(/\/$/, '')}/functions/v1/waitlist-signup`
}

/** Edge Function that emails contact form submissions to the admin inbox. */
export function contactFunctionUrl(): string | null {
  if (contactUrlOverride?.trim()) return contactUrlOverride.trim()
  if (!url) return null
  return `${url.replace(/\/$/, '')}/functions/v1/contact-message`
}
