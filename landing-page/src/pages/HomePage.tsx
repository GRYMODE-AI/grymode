import { Dilemma } from '../components/sections/Dilemma'
import { Hero } from '../components/sections/Hero'
import { HowItWorks } from '../components/sections/HowItWorks'
import { Mission } from '../components/sections/Mission'
import { Occasions } from '../components/sections/Occasions'
import { Versatility } from '../components/sections/Versatility'
import { Waitlist } from '../components/sections/Waitlist'

export function HomePage() {
  return (
    <>
      <Hero />
      <Dilemma />
      <HowItWorks />
      <Versatility />
      <Occasions />
      <Mission />
      <Waitlist />
    </>
  )
}
