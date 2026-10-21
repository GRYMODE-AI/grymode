import {
  motion,
  useReducedMotion,
  useScroll,
  useSpring,
  useTransform,
} from 'framer-motion'
import { useRef } from 'react'

/** Editorial device frame showing a real Grymode home screenshot. */
export function PhoneMockup() {
  const ref = useRef<HTMLDivElement>(null)
  const reduce = useReducedMotion()
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start end', 'end start'],
  })

  const yRaw = useTransform(scrollYProgress, [0, 1], reduce ? [0, 0] : [40, -40])
  const rotateRaw = useTransform(
    scrollYProgress,
    [0, 1],
    reduce ? [0, 0] : [1.2, -1.2],
  )
  const shadowScale = useTransform(
    scrollYProgress,
    [0, 0.5, 1],
    reduce ? [1, 1, 1] : [0.85, 1.05, 0.9],
  )
  const shadowOpacity = useTransform(
    scrollYProgress,
    [0, 0.5, 1],
    reduce ? [0.55, 0.55, 0.55] : [0.45, 0.75, 0.4],
  )
  const y = useSpring(yRaw, { stiffness: 80, damping: 28, mass: 0.6 })
  const rotate = useSpring(rotateRaw, { stiffness: 80, damping: 28, mass: 0.6 })

  return (
    <div ref={ref} className="relative mx-auto w-full select-none">
      <motion.div
        aria-hidden
        className="absolute -bottom-6 inset-x-4 -z-10 h-10 rounded-full bg-black/[0.08] blur-2xl sm:-bottom-8 sm:inset-x-6 sm:h-12"
        style={{ scaleX: shadowScale, opacity: shadowOpacity }}
      />
      <motion.div
        style={{ y, rotate }}
        className="will-change-transform origin-center"
      >
        <div className="rounded-[36px] bg-[#E8E4DD] p-2 shadow-[0_20px_50px_-12px_rgba(0,0,0,0.15)] ring-1 ring-black/[0.05] sm:rounded-[44px] sm:p-2.5">
          <div className="flex max-h-[560px] flex-col overflow-hidden rounded-[28px] border border-black/[0.04] bg-warm-paper sm:max-h-[600px] sm:rounded-[36px] md:max-h-[580px] lg:max-h-[670px]">
            <div className="relative z-10 flex shrink-0 items-center justify-between bg-warm-paper px-4 pb-1.5 pt-2.5 sm:px-6 sm:pb-2 sm:pt-3">
              <span className="text-[10px] font-medium text-soft-black sm:text-[11px]">
                9:41
              </span>
              <div className="h-3.5 w-14 rounded-full bg-soft-black sm:h-4 sm:w-16" />
              <div className="flex gap-1 text-soft-black/70">
                <span className="block h-2 w-2.5 rounded-sm bg-current opacity-80 sm:h-2.5 sm:w-3" />
                <span className="block h-2 w-2.5 rounded-sm bg-current opacity-60 sm:h-2.5 sm:w-3" />
                <span className="block h-2 w-3.5 rounded-sm bg-current sm:h-2.5 sm:w-4" />
              </div>
            </div>
            <div className="min-h-0 flex-1 overflow-hidden leading-none">
              <img
                src="/images/app-home.png"
                alt="Grymode home — Wear this today look from your wardrobe"
                className="block w-full -translate-y-[5.8%] [margin-bottom:-5.8%]"
                width={680}
                height={1200}
                decoding="async"
              />
            </div>
          </div>
        </div>
      </motion.div>
    </div>
  )
}
