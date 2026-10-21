import { motion, useReducedMotion } from 'framer-motion'
import { waitlist } from '../../content/copy'
import { fadeUp, staggerContainer } from '../../lib/motion'
import { Container } from '../layout/Container'
import { WaitlistForm } from '../ui/WaitlistForm'

export function Waitlist() {
  const reduce = useReducedMotion()

  return (
    <section
      id="waitlist"
      className="relative w-full scroll-mt-20 overflow-hidden bg-soft-black py-20 text-warm-paper sm:py-24 lg:scroll-mt-24 lg:py-28"
    >
      <motion.div
        aria-hidden
        className="pointer-events-none absolute -right-1/4 -top-40 h-72 w-72 rounded-full bg-deep-olive/20 blur-3xl sm:h-96 sm:w-96"
        animate={
          reduce
            ? undefined
            : {
                opacity: [0.45, 0.8, 0.45],
                scale: [0.95, 1.08, 0.95],
              }
        }
        transition={
          reduce
            ? undefined
            : { duration: 7, repeat: Infinity, ease: 'easeInOut' }
        }
      />
      <Container>
        <motion.div
          className="relative z-10 mx-auto flex max-w-md flex-col text-center md:max-w-2xl lg:max-w-3xl"
          initial={reduce ? false : 'hidden'}
          whileInView="show"
          viewport={{ once: true, amount: 0.35 }}
          variants={reduce ? undefined : staggerContainer}
        >
          <motion.span
            variants={reduce ? undefined : fadeUp}
            className="mb-3 text-[10px] font-semibold uppercase tracking-[var(--tracking-ultra)] text-olive-mist"
          >
            {waitlist.eyebrow}
          </motion.span>
          <motion.h2
            variants={reduce ? undefined : fadeUp}
            className="font-display text-[26px] leading-snug text-warm-paper sm:text-[28px] md:text-[36px] lg:text-[48px] lg:leading-[1.15]"
          >
            {waitlist.headline}
          </motion.h2>
          <motion.p
            variants={reduce ? undefined : fadeUp}
            className="mx-auto mt-4 max-w-xl text-[13px] font-light leading-relaxed text-hairline/90 sm:text-[14px] lg:text-base"
          >
            {waitlist.body}
          </motion.p>
          <motion.div
            variants={reduce ? undefined : fadeUp}
            className="mx-auto mt-8 w-full max-w-lg lg:mt-10"
          >
            <WaitlistForm variant="dark" inlineOnDesktop />
          </motion.div>
          <motion.p
            variants={reduce ? undefined : fadeUp}
            className="mt-5 text-[11px] font-light text-neutral-500"
          >
            {waitlist.disclaimer}
          </motion.p>
          <motion.p
            variants={reduce ? undefined : fadeUp}
            className="mt-2 text-[11px] font-light text-neutral-500"
          >
            {waitlist.privacyNote}
          </motion.p>
        </motion.div>
      </Container>
    </section>
  )
}
