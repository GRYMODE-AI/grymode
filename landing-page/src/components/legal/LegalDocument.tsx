import type { LegalSection } from '../../content/legal'
import { legalMeta } from '../../content/legal'
import { Container } from '../layout/Container'
import { Reveal } from '../motion/Reveal'

type Props = {
  eyebrow: string
  title: string
  intro: string
  sections: readonly LegalSection[]
}

export function LegalDocument({ eyebrow, title, intro, sections }: Props) {
  return (
    <article className="border-b border-soft-black/[0.03] bg-warm-paper pb-20 pt-10 sm:pb-24 sm:pt-12 lg:pb-32 lg:pt-16">
      <Container narrow>
        <Reveal>
          <header className="text-center">
            <span className="mb-3 block text-[10px] font-medium uppercase tracking-[var(--tracking-ultra)] text-deep-olive sm:mb-4 sm:text-[11px]">
              {eyebrow}
            </span>
            <h1 className="font-display text-[32px] leading-tight text-soft-black sm:text-[40px] md:text-[48px] lg:leading-[1.15]">
              {title}
            </h1>
            <p className="mt-3 text-[11px] uppercase tracking-[var(--tracking-caps)] text-muted-grey">
              Last updated {legalMeta.lastUpdated}
            </p>
            <p className="mx-auto mt-6 max-w-xl text-left text-[14px] font-light leading-relaxed text-graphite sm:mt-8 sm:text-[15px] lg:text-base">
              {intro}
            </p>
          </header>
        </Reveal>

        <div className="mx-auto mt-12 max-w-xl space-y-10 text-left sm:mt-14 sm:space-y-12">
          {sections.map((section) => (
            <Reveal key={section.title}>
              <section>
                <h2 className="font-heading text-[20px] text-soft-black sm:text-[22px] lg:text-[24px]">
                  {section.title}
                </h2>
                <div className="mt-3 space-y-3 text-[14px] font-light leading-relaxed text-graphite sm:text-[15px] lg:text-base">
                  {section.paragraphs.map((p) => (
                    <p key={p.slice(0, 48)}>{p}</p>
                  ))}
                  {section.bullets && section.bullets.length > 0 ? (
                    <ul className="list-disc space-y-2 pl-5 marker:text-deep-olive">
                      {section.bullets.map((item) => (
                        <li key={item.slice(0, 64)}>{item}</li>
                      ))}
                    </ul>
                  ) : null}
                </div>
              </section>
            </Reveal>
          ))}
        </div>
      </Container>
    </article>
  )
}
