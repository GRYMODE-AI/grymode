import { motion, useMotionValueEvent, useScroll } from 'framer-motion'
import { useState } from 'react'
import { nav } from '../../content/copy'
import { easeOutQuart } from '../../lib/motion'
import { Button } from '../ui/Button'
import { Wordmark } from '../ui/Wordmark'
import { Container } from './Container'

export function Header() {
  const [scrolled, setScrolled] = useState(false)
  const { scrollY } = useScroll()

  useMotionValueEvent(scrollY, 'change', (y) => {
    setScrolled(y > 12)
  })

  return (
    <motion.header
      className={`fixed inset-x-0 top-0 z-50 border-b ${
        scrolled
          ? 'border-soft-black/[0.06] bg-warm-paper/90 backdrop-blur-md'
          : 'border-transparent bg-warm-paper/80 backdrop-blur-sm'
      }`}
      initial={{ y: -16, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.7, ease: easeOutQuart }}
    >
      <Container className="flex h-14 items-center justify-between sm:h-16 lg:h-20">
        <div className="flex min-w-0 items-center gap-6 lg:gap-10">
          <Wordmark />
          <nav
            className="hidden items-center gap-6 lg:flex lg:gap-7"
            aria-label="Primary"
          >
            {nav.links.map((link) => (
              <a
                key={link.href}
                href={link.href}
                className="whitespace-nowrap text-[13px] font-medium tracking-wide text-graphite transition-colors hover:text-soft-black"
              >
                {link.label}
              </a>
            ))}
          </nav>
        </div>
        <Button
          href="#waitlist"
          className="!shrink-0 !px-3.5 !py-1.5 !text-[11px] sm:!px-5 sm:!py-2 sm:!text-xs md:!px-6 md:!py-2.5 md:!text-sm"
        >
          {nav.cta}
        </Button>
      </Container>
    </motion.header>
  )
}
