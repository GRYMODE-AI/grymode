import { motion, useReducedMotion } from 'framer-motion'
import { hero } from '../../content/copy'
import {
  blurUp,
  easeOutExpo,
  fadeScale,
  fadeUp,
  staggerContainer,
} from '../../lib/motion'
import { Container } from '../layout/Container'
import { PhoneMockup } from '../mockups/PhoneMockup'
import { Button } from '../ui/Button'

export function Hero() {
  const reduce = useReducedMotion()

  return (
    <section className="w-full overflow-x-clip pb-14 pt-8 sm:pb-16 sm:pt-10 md:pb-20 lg:pb-24 lg:pt-14">
      <Container>
        <div className="grid grid-cols-1 items-center gap-10 md:grid-cols-12 md:gap-6 lg:gap-10 xl:gap-12">
          <motion.div
            className="flex flex-col items-center text-center md:col-span-7 md:items-start md:pr-4 md:text-left lg:pr-8 xl:pr-10"
            initial={reduce ? false : 'hidden'}
            animate="show"
            variants={reduce ? undefined : staggerContainer}
          >
            <motion.span
              variants={reduce ? undefined : fadeUp}
              className="mb-3 text-[10px] font-medium uppercase tracking-[var(--tracking-ultra)] text-deep-olive sm:mb-4 sm:text-[11px]"
            >
              {hero.eyebrow}
            </motion.span>
            <motion.h1
              variants={reduce ? undefined : blurUp}
              className="font-display text-[30px] leading-[1.22] tracking-tight text-soft-black sm:text-[34px] md:text-[36px] md:leading-[1.15] lg:text-[48px] lg:leading-[1.12] xl:text-[56px] xl:leading-[1.1]"
            >
              {hero.headline}
            </motion.h1>
            <motion.p
              variants={reduce ? undefined : fadeUp}
              className="mt-4 max-w-md text-[14px] font-light leading-[1.65] text-graphite sm:mt-5 sm:max-w-lg sm:text-[15px] md:max-w-none lg:max-w-xl lg:text-base lg:leading-relaxed"
            >
              {hero.support}
            </motion.p>
            <motion.div
              variants={reduce ? undefined : fadeUp}
              className="mt-7 flex w-full max-w-[300px] flex-col items-center gap-3 sm:mt-8 sm:max-w-none sm:flex-row sm:flex-wrap sm:justify-center md:justify-start lg:gap-5"
            >
              <Button
                href="#waitlist"
                className="w-full whitespace-nowrap sm:w-auto sm:px-7 sm:py-3.5 lg:px-8 lg:py-4"
              >
                {hero.cta}
              </Button>
              <span className="shrink-0 text-[10px] font-medium uppercase tracking-[var(--tracking-ultra)] text-muted-grey">
                {hero.comingSoon}
              </span>
            </motion.div>
          </motion.div>

          <motion.div
            className="relative flex min-w-0 justify-center md:col-span-5 md:justify-end"
            initial={reduce ? false : 'hidden'}
            animate="show"
            variants={reduce ? undefined : fadeScale}
            transition={{ duration: 1.2, delay: 0.18, ease: easeOutExpo }}
          >
            <div className="w-full max-w-[280px] sm:max-w-[305px] md:w-[min(100%,260px)] md:max-w-none lg:w-[320px] xl:w-[360px]">
              <PhoneMockup />
            </div>
          </motion.div>
        </div>
      </Container>
    </section>
  )
}
