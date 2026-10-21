import { LegalDocument } from '../components/legal/LegalDocument'
import { termsOfUse } from '../content/legal'

export function TermsPage() {
  return (
    <LegalDocument
      eyebrow={termsOfUse.eyebrow}
      title={termsOfUse.title}
      intro={termsOfUse.intro}
      sections={termsOfUse.sections}
    />
  )
}
