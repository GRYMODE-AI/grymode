import { motion, useReducedMotion } from 'framer-motion'
import type { MouseEventHandler, ReactNode } from 'react'
import { springSnappy } from '../../lib/motion'

type Variant = 'primary' | 'onDark' | 'ghost'

type Props = {
  children: ReactNode
  variant?: Variant
  className?: string
  href?: string
  type?: 'button' | 'submit' | 'reset'
  disabled?: boolean
  onClick?: MouseEventHandler<HTMLButtonElement>
}

const styles: Record<Variant, string> = {
  primary:
    'bg-soft-black text-warm-paper hover:bg-neutral-800 shadow-[0_4px_16px_rgba(26,26,26,0.12)]',
  onDark: 'bg-olive-mist text-soft-black hover:bg-[#E2E2CE]',
  ghost: 'bg-transparent text-soft-black border border-hairline hover:bg-stone/60',
}

export function Button({
  children,
  variant = 'primary',
  className = '',
  href,
  type = 'button',
  disabled,
  onClick,
}: Props) {
  const reduce = useReducedMotion()
  const base =
    'inline-flex items-center justify-center rounded-full px-6 py-3.5 text-sm font-medium tracking-wide whitespace-nowrap transition-colors duration-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-deep-olive/50 disabled:opacity-60 disabled:pointer-events-none'

  const cls = `${base} ${styles[variant]} ${className}`
  const motionProps = reduce
    ? {}
    : {
        whileHover: { scale: 1.03, y: -1 },
        whileTap: { scale: 0.97 },
        transition: springSnappy,
      }

  if (href) {
    return (
      <motion.a href={href} className={cls} {...motionProps}>
        {children}
      </motion.a>
    )
  }

  return (
    <motion.button
      type={type}
      className={cls}
      disabled={disabled}
      onClick={onClick}
      {...motionProps}
    >
      {children}
    </motion.button>
  )
}
