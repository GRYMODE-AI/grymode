import { AnimatePresence, motion, useReducedMotion } from 'framer-motion'
import { useEffect, useId, useRef, useState, type FormEvent } from 'react'
import { contact as copy } from '../../content/copy'
import { easeOutExpo, springSnappy } from '../../lib/motion'
import { submitContact } from '../../lib/contact'
import { Button } from '../ui/Button'

type Props = {
  open: boolean
  onClose: () => void
}

const fieldClass =
  'w-full rounded-xl border border-hairline bg-surface px-4 py-3 text-sm text-soft-black placeholder:text-muted-grey transition-colors focus:border-deep-olive/40 focus:outline-none disabled:opacity-60'

export function ContactModal({ open, onClose }: Props) {
  const reduce = useReducedMotion()
  const titleId = useId()
  const firstFieldRef = useRef<HTMLInputElement>(null)
  const [firstName, setFirstName] = useState('')
  const [lastName, setLastName] = useState('')
  const [email, setEmail] = useState('')
  const [message, setMessage] = useState('')
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>(
    'idle',
  )
  const [error, setError] = useState('')

  useEffect(() => {
    if (!open) return
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    const t = window.setTimeout(() => firstFieldRef.current?.focus(), 40)
    return () => {
      document.body.style.overflow = prev
      window.clearTimeout(t)
    }
  }, [open])

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  useEffect(() => {
    if (!open) {
      setStatus('idle')
      setError('')
      setFirstName('')
      setLastName('')
      setEmail('')
      setMessage('')
    }
  }, [open])

  async function onSubmit(event: FormEvent) {
    event.preventDefault()
    setStatus('loading')
    setError('')
    const result = await submitContact({ firstName, lastName, email, message })
    if (result.ok) {
      setStatus('success')
    } else {
      setStatus('error')
      setError(result.message)
    }
  }

  return (
    <AnimatePresence>
      {open ? (
        <div className="fixed inset-0 z-[100] flex items-end justify-center p-0 sm:items-center sm:p-6">
          <motion.button
            type="button"
            aria-label="Dismiss"
            className="absolute inset-0 bg-soft-black/35 backdrop-blur-[2px]"
            initial={reduce ? false : { opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.28, ease: easeOutExpo }}
            onClick={onClose}
          />

          <motion.div
            role="dialog"
            aria-modal="true"
            aria-labelledby={titleId}
            className="relative z-10 flex max-h-[min(92dvh,720px)] w-full max-w-[440px] flex-col overflow-hidden rounded-t-3xl border border-soft-black/[0.06] bg-warm-paper shadow-[0_24px_80px_-24px_rgba(26,26,26,0.35)] sm:rounded-3xl"
            initial={reduce ? false : { opacity: 0, y: 28, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 16, scale: 0.98 }}
            transition={
              reduce
                ? { duration: 0.15 }
                : { type: 'spring', stiffness: 320, damping: 32 }
            }
          >
            <div className="flex items-start justify-between gap-4 border-b border-soft-black/[0.04] px-6 pb-4 pt-5 sm:px-7 sm:pt-6">
              <div className="min-w-0">
                <p className="text-[10px] font-medium uppercase tracking-[var(--tracking-ultra)] text-deep-olive">
                  {copy.eyebrow}
                </p>
                <h2
                  id={titleId}
                  className="mt-1 font-display text-[26px] leading-tight text-soft-black sm:text-[28px]"
                >
                  {copy.title}
                </h2>
                <p className="mt-1.5 text-[13px] font-light leading-relaxed text-graphite">
                  {copy.body}
                </p>
              </div>
              <motion.button
                type="button"
                onClick={onClose}
                aria-label={copy.close}
                className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-hairline text-graphite transition-colors hover:border-soft-black/20 hover:text-soft-black"
                whileTap={reduce ? undefined : { scale: 0.94 }}
                transition={springSnappy}
              >
                <span aria-hidden className="text-lg leading-none">
                  ×
                </span>
              </motion.button>
            </div>

            <div className="overflow-y-auto px-6 py-5 sm:px-7 sm:py-6">
              {status === 'success' ? (
                <motion.div
                  initial={reduce ? false : { opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="flex flex-col items-center py-8 text-center"
                >
                  <p className="font-heading text-xl text-soft-black">
                    {copy.successTitle}
                  </p>
                  <p className="mt-2 max-w-xs text-[13px] font-light text-graphite">
                    {copy.successBody}
                  </p>
                  <Button
                    type="button"
                    onClick={onClose}
                    className="mt-8 !px-7 !py-3"
                  >
                    {copy.close}
                  </Button>
                </motion.div>
              ) : (
                <form onSubmit={onSubmit} className="flex flex-col gap-4">
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 sm:gap-3">
                    <div>
                      <label
                        htmlFor="contact-first"
                        className="mb-1.5 block text-[11px] font-medium uppercase tracking-[var(--tracking-caps)] text-graphite"
                      >
                        {copy.firstName}
                      </label>
                      <input
                        ref={firstFieldRef}
                        id="contact-first"
                        name="first_name"
                        autoComplete="given-name"
                        required
                        value={firstName}
                        onChange={(e) => setFirstName(e.target.value)}
                        disabled={status === 'loading'}
                        className={fieldClass}
                      />
                    </div>
                    <div>
                      <label
                        htmlFor="contact-last"
                        className="mb-1.5 block text-[11px] font-medium uppercase tracking-[var(--tracking-caps)] text-graphite"
                      >
                        {copy.lastName}
                      </label>
                      <input
                        id="contact-last"
                        name="last_name"
                        autoComplete="family-name"
                        required
                        value={lastName}
                        onChange={(e) => setLastName(e.target.value)}
                        disabled={status === 'loading'}
                        className={fieldClass}
                      />
                    </div>
                  </div>

                  <div>
                    <label
                      htmlFor="contact-email"
                      className="mb-1.5 block text-[11px] font-medium uppercase tracking-[var(--tracking-caps)] text-graphite"
                    >
                      {copy.email}
                    </label>
                    <input
                      id="contact-email"
                      name="email"
                      type="email"
                      autoComplete="email"
                      required
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      disabled={status === 'loading'}
                      className={fieldClass}
                    />
                  </div>

                  <div>
                    <label
                      htmlFor="contact-message"
                      className="mb-1.5 block text-[11px] font-medium uppercase tracking-[var(--tracking-caps)] text-graphite"
                    >
                      {copy.message}
                    </label>
                    <textarea
                      id="contact-message"
                      name="message"
                      required
                      rows={5}
                      value={message}
                      onChange={(e) => setMessage(e.target.value)}
                      placeholder={copy.messagePlaceholder}
                      disabled={status === 'loading'}
                      className={`${fieldClass} min-h-[120px] resize-y leading-relaxed`}
                    />
                  </div>

                  {status === 'error' && error ? (
                    <p className="text-[12px] text-red-700" role="alert">
                      {error}
                    </p>
                  ) : null}

                  <Button
                    type="submit"
                    disabled={status === 'loading'}
                    className="mt-1 w-full !py-3.5"
                  >
                    {status === 'loading' ? copy.sending : copy.submit}
                  </Button>
                </form>
              )}
            </div>
          </motion.div>
        </div>
      ) : null}
    </AnimatePresence>
  )
}
