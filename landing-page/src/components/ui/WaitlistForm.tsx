import { useState, type FormEvent } from 'react'
import { waitlist as copy } from '../../content/copy'
import { joinWaitlist } from '../../lib/waitlist'
import { Button } from './Button'

type Props = {
  variant?: 'dark' | 'light'
  className?: string
  idPrefix?: string
  /** Stack on mobile; horizontal from `sm` up when true. */
  inlineOnDesktop?: boolean
}

export function WaitlistForm({
  variant = 'dark',
  className = '',
  idPrefix = 'waitlist',
  inlineOnDesktop = false,
}: Props) {
  const [email, setEmail] = useState('')
  const [status, setStatus] = useState<
    'idle' | 'loading' | 'success' | 'already' | 'error'
  >('idle')
  const [message, setMessage] = useState('')

  async function onSubmit(event: FormEvent) {
    event.preventDefault()
    setStatus('loading')
    setMessage('')
    const result = await joinWaitlist(email)
    if (result.ok) {
      setStatus(result.duplicate ? 'already' : 'success')
      setEmail('')
    } else {
      setStatus('error')
      setMessage(result.message)
    }
  }

  const inputClass =
    variant === 'dark'
      ? 'bg-white/10 text-warm-paper placeholder:text-neutral-500 border-white/10 focus:border-white/30'
      : 'bg-surface text-soft-black placeholder:text-muted-grey border-hairline focus:border-deep-olive/40'

  if (status === 'success' || status === 'already') {
    const title = status === 'already' ? copy.alreadyTitle : copy.successTitle
    const body = status === 'already' ? copy.alreadyBody : copy.successBody
    return (
      <div
        className={`rounded-2xl border px-5 py-6 text-center ${
          variant === 'dark'
            ? 'border-white/10 bg-white/5 text-warm-paper'
            : 'border-hairline bg-surface text-soft-black'
        } ${className}`}
        role="status"
      >
        <p className="font-heading text-lg">{title}</p>
        <p
          className={`mt-1 text-xs font-light ${
            variant === 'dark' ? 'text-hairline/80' : 'text-graphite'
          }`}
        >
          {body}
        </p>
      </div>
    )
  }

  return (
    <form
      onSubmit={onSubmit}
      className={`flex w-full flex-col gap-3 ${
        inlineOnDesktop ? 'sm:flex-row sm:items-stretch' : ''
      } ${className}`}
    >
      <label className="sr-only" htmlFor={`${idPrefix}-email`}>
        Email
      </label>
      <input
        id={`${idPrefix}-email`}
        type="email"
        name="email"
        autoComplete="email"
        required
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        placeholder={copy.placeholder}
        disabled={status === 'loading'}
        className={`w-full rounded-full border px-5 py-3.5 text-center text-sm transition-all focus:outline-none sm:flex-1 sm:text-left ${inputClass}`}
      />
      <Button
        type="submit"
        variant={variant === 'dark' ? 'onDark' : 'primary'}
        disabled={status === 'loading'}
        className={`w-full ${inlineOnDesktop ? 'sm:w-auto sm:shrink-0' : ''}`}
      >
        {status === 'loading' ? 'Joining…' : copy.submit}
      </Button>
      {status === 'error' && message ? (
        <p
          className={`text-center text-xs text-red-400 sm:basis-full sm:text-left ${
            variant === 'light' ? 'text-red-700' : ''
          }`}
          role="alert"
        >
          {message}
        </p>
      ) : null}
    </form>
  )
}
