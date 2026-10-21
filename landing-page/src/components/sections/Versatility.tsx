import { versatility } from '../../content/copy'
import { Container } from '../layout/Container'
import { HoverLift } from '../motion/HoverLift'
import { Parallax } from '../motion/Parallax'
import { Reveal } from '../motion/Reveal'
import { Stagger, StaggerItem } from '../motion/Stagger'

export function Versatility() {
  return (
    <section className="w-full border-t border-soft-black/[0.03] bg-stone/50 py-16 sm:py-20 lg:py-28">
      <Container>
        <div className="mb-8 flex flex-col gap-5 sm:mb-10 md:mb-14 md:flex-row md:items-end md:justify-between md:gap-8">
          <Reveal className="max-w-2xl" variant="blurUp">
            <span className="mb-3 block text-[10px] font-medium uppercase tracking-[var(--tracking-ultra)] text-deep-olive sm:text-[11px]">
              {versatility.eyebrow}
            </span>
            <h2 className="whitespace-pre-line font-display text-[28px] leading-tight text-soft-black sm:text-[30px] md:text-[40px] lg:text-[48px]">
              {versatility.headline}
            </h2>
            <p className="mt-3 text-[14px] font-light leading-relaxed text-graphite sm:text-[15px] lg:text-base">
              {versatility.body}
            </p>
          </Reveal>
          <Reveal delay={0.12} className="flex flex-wrap gap-2 md:max-w-sm md:justify-end">
            {versatility.staples.map((s) => (
              <span
                key={s}
                className="rounded-full border border-soft-black/[0.04] bg-surface px-3 py-1 text-[9px] uppercase tracking-wider text-soft-black sm:text-[10px]"
              >
                {s}
              </span>
            ))}
          </Reveal>
        </div>

        <Stagger className="grid gap-5 sm:gap-6 md:grid-cols-3" fast>
          {versatility.looks.map((look) => (
            <StaggerItem key={look.label} variant="fadeScale" className="h-full">
              <HoverLift className="flex h-full flex-col overflow-hidden rounded-2xl border border-soft-black/[0.04] bg-surface shadow-[0_4px_20px_rgba(0,0,0,0.03)]">
                <article className="flex h-full flex-col">
                  <div className="relative aspect-[4/3] overflow-hidden bg-stone sm:aspect-[3/4]">
                    <Parallax className="absolute inset-0" distance={40} scale={1.12}>
                      <img
                        src={look.image}
                        alt={`${look.title} — ${look.detail}`}
                        className="h-full w-full object-cover object-center"
                        loading="lazy"
                      />
                    </Parallax>
                    <span className="absolute left-3 top-3 rounded-full bg-soft-black/80 px-2.5 py-0.5 text-[9px] uppercase tracking-wider text-warm-paper backdrop-blur-sm">
                      {look.label}
                    </span>
                  </div>
                  <div className="flex flex-1 flex-col p-4 sm:p-5">
                    <div className="mb-1 flex flex-col gap-1">
                      <h3 className="font-heading text-base text-soft-black sm:text-lg">
                        {look.title}
                      </h3>
                      <span className="text-[10px] font-medium uppercase tracking-wider text-deep-olive">
                        {look.tone}
                      </span>
                    </div>
                    <p className="mt-1 text-[12px] font-light leading-relaxed text-graphite sm:text-[13px]">
                      {look.detail}
                    </p>
                  </div>
                </article>
              </HoverLift>
            </StaggerItem>
          ))}
        </Stagger>
      </Container>
    </section>
  )
}
