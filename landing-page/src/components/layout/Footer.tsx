import { brand, footer, hero } from '../../content/copy'
import { useContact } from '../contact/ContactProvider'
import { Reveal } from '../motion/Reveal'
import { Wordmark } from '../ui/Wordmark'
import { Container } from './Container'

export function Footer() {
  const { openContact } = useContact()

  return (
    <footer className="border-t border-soft-black/[0.04] bg-warm-paper py-12 md:py-14 lg:py-16">
      <Container>
        <Reveal>
          <div className="flex flex-col items-center gap-8 border-b border-soft-black/[0.04] pb-10 text-center md:flex-row md:items-start md:justify-between md:text-left">
            <div className="flex max-w-sm flex-col items-center md:items-start">
              <Wordmark />
              <p className="mt-2 text-sm font-light text-graphite">
                {hero.support.split('.')[0]}.
              </p>
            </div>
            <div className="flex flex-col items-center gap-6 md:items-end">
              <div className="flex flex-wrap justify-center gap-x-6 gap-y-3 text-xs font-medium tracking-wide text-soft-black">
                {footer.links.map((link) =>
                  'action' in link && link.action === 'contact' ? (
                    <button
                      key={link.label}
                      type="button"
                      onClick={openContact}
                      className="transition-colors hover:text-deep-olive"
                    >
                      {link.label}
                    </button>
                  ) : (
                    <a
                      key={link.label}
                      href={link.href}
                      className="transition-colors hover:text-deep-olive"
                    >
                      {link.label}
                    </a>
                  ),
                )}
              </div>
              <div className="flex flex-wrap justify-center gap-5 text-[11px] uppercase tracking-[var(--tracking-caps)] text-graphite md:border-l md:border-soft-black/[0.06] md:pl-6">
                {footer.social.map((link) => (
                  <a
                    key={link.label}
                    href={link.href}
                    className="transition-colors hover:text-soft-black"
                  >
                    {link.label}
                  </a>
                ))}
              </div>
            </div>
          </div>
          <p className="pt-6 text-center text-[10px] uppercase tracking-[var(--tracking-ultra)] text-muted-grey md:text-left">
            © {brand.year} {brand.product}. All rights reserved.
          </p>
        </Reveal>
      </Container>
    </footer>
  )
}
