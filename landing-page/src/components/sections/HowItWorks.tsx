import { howItWorks } from '../../content/copy'
import { Container } from '../layout/Container'
import { HoverLift } from '../motion/HoverLift'
import { Reveal } from '../motion/Reveal'
import { Stagger, StaggerItem } from '../motion/Stagger'

export function HowItWorks() {
  return (
    <section
      id="how-it-works"
      className="w-full scroll-mt-20 bg-warm-paper py-16 sm:py-20 lg:scroll-mt-24 lg:py-28"
    >
      <Container>
        <Reveal className="mb-10 max-w-3xl sm:mb-12 lg:mb-16" variant="blurUp">
          <span className="mb-3 block text-[10px] font-medium uppercase tracking-[var(--tracking-ultra)] text-deep-olive sm:text-[11px]">
            {howItWorks.eyebrow}
          </span>
          <h2 className="whitespace-pre-line font-display text-[28px] leading-tight text-soft-black sm:text-[30px] md:text-[40px] lg:text-[48px]">
            {howItWorks.headline}
          </h2>
        </Reveal>

        <Stagger className="grid gap-8 sm:gap-10 md:grid-cols-3 md:gap-5 lg:gap-6">
          {howItWorks.steps.map((step) => (
            <StaggerItem
              key={step.n}
              variant="fadeScale"
              className="h-full border-b border-soft-black/[0.04] pb-8 last:border-0 last:pb-0 sm:pb-10 md:border-0 md:pb-0"
            >
              <HoverLift
                y={-3}
                scale={1.01}
                className="h-full md:rounded-3xl md:bg-stone/50 md:p-6 lg:p-8"
              >
                <article>
                  <div className="mb-2 flex items-baseline gap-3">
                    <span className="font-heading text-xl italic text-deep-olive sm:text-2xl">
                      {step.n}
                    </span>
                    <h3 className="font-heading text-[19px] tracking-tight text-soft-black sm:text-[21px]">
                      {step.title}
                    </h3>
                  </div>
                  <p className="pl-7 text-[13px] font-light leading-relaxed text-graphite sm:pl-8 sm:text-[14px] md:pl-0 md:pt-2">
                    {step.body}
                  </p>
                </article>
              </HoverLift>
            </StaggerItem>
          ))}
        </Stagger>
      </Container>
    </section>
  )
}
