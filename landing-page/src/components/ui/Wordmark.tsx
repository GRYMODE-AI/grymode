import { brand } from '../../content/copy'

type Props = {
  className?: string
  light?: boolean
}

export function Wordmark({ className = '', light = false }: Props) {
  return (
    <a
      href="#top"
      className={`group inline-flex items-baseline gap-1.5 focus:outline-none focus-visible:ring-2 focus-visible:ring-deep-olive/40 rounded-sm ${className}`}
      aria-label={brand.product}
    >
      <span
        className={`font-heading text-xl tracking-[0.12em] uppercase ${
          light ? 'text-warm-paper' : 'text-soft-black group-hover:opacity-80'
        } transition-opacity`}
      >
        {brand.name}
      </span>
      <span
        className={`text-[10px] font-medium uppercase tracking-[var(--tracking-ultra)] ${
          light ? 'text-olive-mist' : 'text-deep-olive'
        }`}
      >
        AI
      </span>
    </a>
  )
}
