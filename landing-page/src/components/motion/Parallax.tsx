import { motion, useReducedMotion, useScroll, useTransform } from 'framer-motion'
import type { ReactNode } from 'react'
import { useRef } from 'react'

type Props = {
  children: ReactNode
  className?: string
  /** Pixel travel across the scroll range. */
  distance?: number
  /** Scale the media slightly so parallax doesn’t show edges. */
  scale?: number
}

/** Subtle scroll-linked vertical drift — Apple product-page feel. */
export function Parallax({
  children,
  className,
  distance = 48,
  scale = 1.08,
}: Props) {
  const ref = useRef<HTMLDivElement>(null)
  const reduce = useReducedMotion()
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start end', 'end start'],
  })
  const y = useTransform(
    scrollYProgress,
    [0, 1],
    reduce ? [0, 0] : [distance / 2, -distance / 2],
  )

  return (
    <div ref={ref} className={`overflow-hidden ${className ?? ''}`}>
      <motion.div
        style={{ y, scale: reduce ? 1 : scale }}
        className="will-change-transform h-full w-full"
      >
        {children}
      </motion.div>
    </div>
  )
}
