import { occasions } from '../../content/copy'
import { Container } from '../layout/Container'
import { HoverLift } from '../motion/HoverLift'
import { Parallax } from '../motion/Parallax'
import { Reveal } from '../motion/Reveal'
import { Stagger, StaggerItem } from '../motion/Stagger'

export function Occasions() {
  return (
    <section
      id="occasions"
      className="w-full scroll-mt-20 bg-warm-paper py-16 sm:py-20 lg:scroll-mt-24 lg:py-28"
    >
      <Container>
        <Reveal className="mb-8 max-w-2xl sm:mb-10 lg:mb-14" variant="blurUp">
          <span className="mb-3 block text-[10px] font-medium uppercase tracking-[var(--tracking-ultra)] text-deep-olive sm:text-[11px]">
            {occasions.eyebrow}
          </span>
          <h2 className="font-display text-[28px] leading-tight text-soft-black sm:text-[30px] md:text-[40px] lg:text-[48px]">
            {occasions.headline}
          </h2>
          <p className="mt-3 text-[14px] font-light leading-relaxed text-graphite sm:text-[15px] lg:text-base">
            {occasions.body}
          </p>
        </Reveal>

        <Stagger
          className="grid grid-cols-1 gap-8 sm:grid-cols-2 lg:grid-cols-4 lg:gap-6"
          fast
        >
          {occasions.items.map((item) => (
            <StaggerItem key={item.n} variant="fadeScale" className="h-full">
              <HoverLift className="group flex h-full flex-col">
                <article className="flex h-full flex-col">
                  <div className="relative mb-3 aspect-[4/5] overflow-hidden rounded-2xl bg-stone sm:mb-4">
                    <Parallax className="absolute inset-0" distance={32} scale={1.12}>
                      <img
                        src={item.image}
                        alt={item.alt}
                        className="h-full w-full object-cover object-center"
                        loading="lazy"
                      />
                    </Parallax>
                    <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-soft-black/35 to-transparent" />
                    <span className="absolute bottom-3 left-3 text-[10px] font-medium uppercase tracking-[var(--tracking-caps)] text-warm-paper">
                      Context {item.n}
                    </span>
                  </div>
                  <h3 className="font-heading text-[16px] text-soft-black sm:text-[17px]">
                    {item.n} · {item.title}
                  </h3>
                  <p className="mt-1 text-[12px] font-light text-graphite sm:text-[13px]">
                    {item.detail}
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
