import { motion, useReducedMotion } from 'framer-motion'
import type { ReactNode } from 'react'
import {
  easeOutExpo,
  fadeScale,
  fadeUp,
  staggerContainer,
  staggerFast,
  viewportOnce,
} from '../../lib/motion'

type Props = {
  children: ReactNode
  className?: string
  /** Tighter stagger for denser grids. */
  fast?: boolean
  /** Extra delay before the first child. */
  delayChildren?: number
}

/**
 * Staggers children on scroll — wrap direct motion children, or use
 * `StaggerItem` for plain DOM children.
 */
export function Stagger({
  children,
  className,
  fast = false,
  delayChildren,
}: Props) {
  const reduce = useReducedMotion()

  if (reduce) {
    return <div className={className}>{children}</div>
  }

  const container = fast ? staggerFast : staggerContainer
  const show = {
    ...container.show,
    transition: {
      ...(typeof container.show === 'object' &&
      container.show &&
      'transition' in container.show
        ? container.show.transition
        : {}),
      ...(delayChildren !== undefined ? { delayChildren } : {}),
    },
  }

  return (
    <motion.div
      className={className}
      initial="hidden"
      whileInView="show"
      viewport={viewportOnce}
      variants={{ hidden: {}, show }}
    >
      {children}
    </motion.div>
  )
}

type ItemProps = {
  children: ReactNode
  className?: string
  variant?: 'fadeUp' | 'fadeScale'
}

/** Child of `Stagger` — inherits stagger timing from the parent. */
export function StaggerItem({
  children,
  className,
  variant = 'fadeUp',
}: ItemProps) {
  const reduce = useReducedMotion()

  if (reduce) {
    return <div className={className}>{children}</div>
  }

  return (
    <motion.div
      className={className}
      variants={variant === 'fadeScale' ? fadeScale : fadeUp}
    >
      {children}
    </motion.div>
  )
}

/** Standalone item with explicit delay when not inside Stagger. */
export function Rise({
  children,
  className,
  delay = 0,
}: {
  children: ReactNode
  className?: string
  delay?: number
}) {
  const reduce = useReducedMotion()
  if (reduce) return <div className={className}>{children}</div>

  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={viewportOnce}
      transition={{ duration: 0.8, delay, ease: easeOutExpo }}
    >
      {children}
    </motion.div>
  )
}
