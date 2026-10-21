import { ContactProvider } from './components/contact/ContactProvider'
import { Footer } from './components/layout/Footer'
import { Header } from './components/layout/Header'
import { Dilemma } from './components/sections/Dilemma'
import { Hero } from './components/sections/Hero'
import { HowItWorks } from './components/sections/HowItWorks'
import { Mission } from './components/sections/Mission'
import { Occasions } from './components/sections/Occasions'
import { Versatility } from './components/sections/Versatility'
import { Waitlist } from './components/sections/Waitlist'

export default function App() {
  return (
    <ContactProvider>
      <div id="top" className="min-h-dvh overflow-x-hidden bg-warm-paper text-soft-black antialiased">
        <Header />
        <main className="pt-14 sm:pt-16 lg:pt-20">
          <Hero />
          <Dilemma />
          <HowItWorks />
          <Versatility />
          <Occasions />
          <Mission />
          <Waitlist />
        </main>
        <Footer />
      </div>
    </ContactProvider>
  )
}
