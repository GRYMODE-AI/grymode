import { motion, useReducedMotion } from 'framer-motion'
import type { ReactNode } from 'react'
import { springSnappy } from '../../lib/motion'

type Props = {
  children: ReactNode
  className?: string
  /** Lift distance in px. */
  y?: number
  scale?: number
}

/** Soft pressable lift for cards and media tiles. */
export function HoverLift({
  children,
  className,
  y = -4,
  scale = 1.015,
}: Props) {
  const reduce = useReducedMotion()

  if (reduce) {
    return <div className={className}>{children}</div>
  }

  return (
    <motion.div
      className={className}
      whileHover={{ y, scale }}
      whileTap={{ scale: 0.985 }}
      transition={springSnappy}
    >
      {children}
    </motion.div>
  )
}
