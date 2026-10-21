import { motion, useReducedMotion } from 'framer-motion'
import type { ReactNode } from 'react'
import {
  blurUp,
  easeOutExpo,
  fadeScale,
  fadeUp,
  viewportOnce,
} from '../../lib/motion'

type VariantName = 'fadeUp' | 'fadeScale' | 'blurUp'

type Props = {
  children: ReactNode
  className?: string
  delay?: number
  /** Override rise distance for fadeUp. */
  y?: number
  variant?: VariantName
  /** Animate on mount instead of scroll. */
  immediate?: boolean
}

/** Scroll-triggered reveal. Honours prefers-reduced-motion. */
export function Reveal({
  children,
  className,
  delay = 0,
  y = 28,
  variant = 'fadeUp',
  immediate = false,
}: Props) {
  const reduce = useReducedMotion()

  if (reduce) {
    return <div className={className}>{children}</div>
  }

  const base =
    variant === 'blurUp' ? blurUp : variant === 'fadeScale' ? fadeScale : fadeUp

  const hidden =
    variant === 'fadeUp'
      ? { opacity: 0, y }
      : variant === 'fadeScale'
        ? { opacity: 0, y: y + 8, scale: 0.96 }
        : { opacity: 0, y: Math.min(y, 24), filter: 'blur(8px)' }

  const show =
    variant === 'fadeScale'
      ? { opacity: 1, y: 0, scale: 1 }
      : variant === 'blurUp'
        ? { opacity: 1, y: 0, filter: 'blur(0px)' }
        : { opacity: 1, y: 0 }

  const duration =
    typeof base.show === 'object' &&
    base.show &&
    'transition' in base.show &&
    base.show.transition &&
    typeof base.show.transition === 'object' &&
    'duration' in base.show.transition
      ? (base.show.transition.duration as number)
      : 0.85

  const props = {
    className,
    initial: hidden,
    transition: { duration, delay, ease: easeOutExpo },
  }

  if (immediate) {
    return (
      <motion.div {...props} animate={show}>
        {children}
      </motion.div>
    )
  }

  return (
    <motion.div {...props} whileInView={show} viewport={viewportOnce}>
      {children}
    </motion.div>
  )
}
