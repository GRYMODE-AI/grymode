import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { ContactModal } from './ContactModal'

type ContactContextValue = {
  open: boolean
  openContact: () => void
  closeContact: () => void
}

const ContactContext = createContext<ContactContextValue | null>(null)

export function ContactProvider({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false)
  const openContact = useCallback(() => setOpen(true), [])
  const closeContact = useCallback(() => setOpen(false), [])
  const value = useMemo(
    () => ({ open, openContact, closeContact }),
    [open, openContact, closeContact],
  )

  return (
    <ContactContext.Provider value={value}>
      {children}
      <ContactModal open={open} onClose={closeContact} />
    </ContactContext.Provider>
  )
}

export function useContact(): ContactContextValue {
  const ctx = useContext(ContactContext)
  if (!ctx) {
    throw new Error('useContact must be used within ContactProvider')
  }
  return ctx
}
