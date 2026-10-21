import type { Transition, Variants } from 'framer-motion'

/** Apple-adjacent ease-out — soft deceleration, no bounce. */
export const easeOutExpo: [number, number, number, number] = [0.16, 1, 0.3, 1]

/** Slightly snappier for UI chrome (header, buttons). */
export const easeOutQuart: [number, number, number, number] = [0.25, 1, 0.5, 1]

export const duration = {
  fast: 0.35,
  base: 0.7,
  slow: 1.05,
  hero: 1.15,
} as const

export const transitionBase: Transition = {
  duration: duration.base,
  ease: easeOutExpo,
}

export const transitionSlow: Transition = {
  duration: duration.slow,
  ease: easeOutExpo,
}

export const transitionHero: Transition = {
  duration: duration.hero,
  ease: easeOutExpo,
}

export const springSoft: Transition = {
  type: 'spring',
  stiffness: 120,
  damping: 22,
  mass: 0.9,
}

export const springSnappy: Transition = {
  type: 'spring',
  stiffness: 380,
  damping: 28,
}

/** Parent: orchestrates staggered children. */
export const staggerContainer: Variants = {
  hidden: {},
  show: {
    transition: {
      staggerChildren: 0.09,
      delayChildren: 0.06,
    },
  },
}

export const staggerFast: Variants = {
  hidden: {},
  show: {
    transition: {
      staggerChildren: 0.06,
      delayChildren: 0.04,
    },
  },
}

/** Classic Apple fade-up. */
export const fadeUp: Variants = {
  hidden: { opacity: 0, y: 28 },
  show: {
    opacity: 1,
    y: 0,
    transition: transitionSlow,
  },
}

/** Soft scale + rise — for devices, cards, media. */
export const fadeScale: Variants = {
  hidden: { opacity: 0, y: 36, scale: 0.96 },
  show: {
    opacity: 1,
    y: 0,
    scale: 1,
    transition: transitionHero,
  },
}

/** Blur-to-sharp entrance (hero headlines). */
export const blurUp: Variants = {
  hidden: { opacity: 0, y: 24, filter: 'blur(8px)' },
  show: {
    opacity: 1,
    y: 0,
    filter: 'blur(0px)',
    transition: transitionHero,
  },
}

export const fadeOnly: Variants = {
  hidden: { opacity: 0 },
  show: {
    opacity: 1,
    transition: { duration: duration.base, ease: easeOutExpo },
  },
}

export const viewportOnce = {
  once: true,
  margin: '-10% 0px -6% 0px',
  amount: 0.2 as const,
}
