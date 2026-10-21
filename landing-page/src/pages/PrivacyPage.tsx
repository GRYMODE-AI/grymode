import { LegalDocument } from '../components/legal/LegalDocument'
import { privacyPolicy } from '../content/legal'

export function PrivacyPage() {
  return (
    <LegalDocument
      eyebrow={privacyPolicy.eyebrow}
      title={privacyPolicy.title}
      intro={privacyPolicy.intro}
      sections={privacyPolicy.sections}
    />
  )
}
