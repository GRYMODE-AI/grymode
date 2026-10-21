import type { ReactNode } from 'react'

type Props = {
  children: ReactNode
  className?: string
  /** Narrower reading measure for centered editorial blocks. */
  narrow?: boolean
}

/**
 * Shared page gutters matching the marketing HTML refs:
 * mobile ~20–24px, tablet ~40px, desktop ~56px, max 1440px.
 */
export function Container({ children, className = '', narrow = false }: Props) {
  return (
    <div
      className={`mx-auto w-full ${
        narrow ? 'max-w-xl md:max-w-3xl' : 'max-w-[1440px]'
      } px-5 sm:px-6 md:px-10 lg:px-14 ${className}`}
    >
      {children}
    </div>
  )
}
