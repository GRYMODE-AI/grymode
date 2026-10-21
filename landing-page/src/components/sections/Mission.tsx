import { motion, useReducedMotion } from 'framer-motion'
import { mission } from '../../content/copy'
import { easeOutExpo } from '../../lib/motion'
import { Container } from '../layout/Container'
import { Stagger, StaggerItem } from '../motion/Stagger'

export function Mission() {
  const reduce = useReducedMotion()

  return (
    <section
      id="mission"
      className="w-full scroll-mt-20 border-t border-soft-black/[0.03] bg-stone/60 py-20 text-center sm:py-24 lg:scroll-mt-24 lg:py-32"
    >
      <Container narrow>
        <Stagger
          className="mx-auto flex flex-col items-center px-1"
          delayChildren={0.08}
        >
          <StaggerItem>
            <span className="mb-3 text-[10px] font-medium uppercase tracking-[var(--tracking-ultra)] text-deep-olive sm:mb-4 sm:text-[11px]">
              {mission.eyebrow}
            </span>
          </StaggerItem>
          <StaggerItem>
            <h2 className="font-display text-[28px] leading-tight text-soft-black sm:text-[30px] md:text-[40px] lg:text-[48px] lg:leading-[1.15]">
              {mission.headline}
            </h2>
          </StaggerItem>
          <StaggerItem className="mt-5 max-w-xl space-y-4 text-[14px] font-light leading-relaxed text-graphite sm:mt-6 sm:text-[15px] lg:text-base">
            {mission.paragraphs.map((p) => (
              <p key={p}>{p}</p>
            ))}
          </StaggerItem>
          <StaggerItem>
            <p className="mt-7 font-heading text-[18px] italic text-soft-black sm:mt-8 sm:text-[20px] lg:text-[28px]">
              {mission.closer}
            </p>
          </StaggerItem>
          <StaggerItem className="mt-10 sm:mt-12">
            <motion.div
              className="mx-auto h-px w-20 origin-center bg-hairline sm:w-24"
              aria-hidden
              initial={reduce ? false : { scaleX: 0, opacity: 0 }}
              whileInView={{ scaleX: 1, opacity: 1 }}
              viewport={{ once: true }}
              transition={{ duration: 0.9, ease: easeOutExpo, delay: 0.15 }}
            />
          </StaggerItem>
        </Stagger>
      </Container>
    </section>
  )
}
