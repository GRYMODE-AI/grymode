import { useEffect } from 'react'
import { useLocation } from 'react-router-dom'

/** Scroll to top on pathname change so legal pages open at the heading. */
export function ScrollToTop() {
  const { pathname } = useLocation()

  useEffect(() => {
    window.scrollTo(0, 0)
  }, [pathname])

  return null
}
