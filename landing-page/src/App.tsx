import { Route, Routes } from 'react-router-dom'
import { ContactProvider } from './components/contact/ContactProvider'
import { Footer } from './components/layout/Footer'
import { Header } from './components/layout/Header'
import { ScrollToTop } from './components/layout/ScrollToTop'
import { HomePage } from './pages/HomePage'
import { PrivacyPage } from './pages/PrivacyPage'
import { TermsPage } from './pages/TermsPage'

export default function App() {
  return (
    <ContactProvider>
      <ScrollToTop />
      <div id="top" className="min-h-dvh overflow-x-hidden bg-warm-paper text-soft-black antialiased">
        <Header />
        <main className="pt-14 sm:pt-16 lg:pt-20">
          <Routes>
            <Route path="/" element={<HomePage />} />
            <Route path="/privacy" element={<PrivacyPage />} />
            <Route path="/terms" element={<TermsPage />} />
          </Routes>
        </main>
        <Footer />
      </div>
    </ContactProvider>
  )
}
