import { dilemma } from '../../content/copy'
import { Container } from '../layout/Container'
import { HoverLift } from '../motion/HoverLift'
import { Parallax } from '../motion/Parallax'
import { Reveal } from '../motion/Reveal'
import { Stagger, StaggerItem } from '../motion/Stagger'

export function Dilemma() {
  return (
    <section className="w-full border-y border-soft-black/[0.03] bg-stone/60 py-16 sm:py-20 lg:py-24">
      <Container>
        <div className="grid items-start gap-10 md:grid-cols-12 md:gap-8 lg:gap-10">
          <Reveal className="md:col-span-5" variant="blurUp" y={32}>
            <span className="mb-3 block text-[10px] font-medium uppercase tracking-[var(--tracking-ultra)] text-deep-olive sm:text-[11px]">
              {dilemma.eyebrow}
            </span>
            <h2 className="whitespace-pre-line font-display text-[28px] leading-tight text-soft-black sm:text-[30px] md:text-[36px] lg:text-[44px] lg:leading-[1.18]">
              {dilemma.headline}
            </h2>
            <p className="mt-4 max-w-md text-[14px] font-light leading-relaxed text-graphite sm:text-[15px] lg:text-base">
              {dilemma.body}
            </p>
          </Reveal>

          <Stagger className="grid grid-cols-2 gap-3 sm:gap-4 md:col-span-7 md:gap-5 lg:gap-6">
            {dilemma.vignettes.map((v) => (
              <StaggerItem key={v.label} variant="fadeScale">
                <HoverLift className="group flex flex-col">
                  <div className="mb-2 aspect-[4/5] overflow-hidden rounded-xl bg-stone sm:mb-2.5 sm:rounded-2xl">
                    <Parallax className="h-full w-full" distance={36} scale={1.12}>
                      <img
                        src={v.image}
                        alt={v.alt}
                        className="h-full w-full object-cover"
                        style={{ objectPosition: v.objectPosition }}
                        loading="lazy"
                      />
                    </Parallax>
                  </div>
                  <span className="text-[9px] font-medium uppercase tracking-[var(--tracking-caps)] text-deep-olive sm:text-[10px]">
                    {v.label}
                  </span>
                  <span className="mt-0.5 text-[12px] font-light leading-snug text-soft-black sm:text-[13px]">
                    {v.caption}
                  </span>
                </HoverLift>
              </StaggerItem>
            ))}
          </Stagger>
        </div>

        <Reveal
          delay={0.12}
          variant="blurUp"
          className="mx-auto mt-12 max-w-3xl border-t border-soft-black/[0.06] px-2 py-8 text-center sm:mt-14 sm:px-4 sm:py-10 md:mt-16 lg:mt-20 lg:rounded-3xl lg:border-0 lg:bg-warm-paper/80 lg:px-10 lg:py-16"
        >
          <blockquote className="font-heading text-[18px] italic font-normal leading-relaxed text-soft-black sm:text-[20px] md:font-display md:text-[28px] lg:text-[32px] lg:leading-[1.35]">
            “{dilemma.quote}”
          </blockquote>
        </Reveal>
      </Container>
    </section>
  )
}
