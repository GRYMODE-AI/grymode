/** Copy for hosted Privacy Policy and Terms of Use pages. */

export const legalMeta = {
  product: 'Grymode AI',
  supportEmail: 'support@grymode.ai',
  siteEmail: 'hello@grymode.com',
  lastUpdated: '21 October 2026',
} as const

export type LegalSection = {
  title: string
  paragraphs: string[]
  bullets?: string[]
}

export const privacyPolicy = {
  eyebrow: 'Legal',
  title: 'Privacy Policy',
  intro:
    'This Privacy Policy explains what Grymode AI (“Grymode”, “we”, “us”) collects, how we use it, and the choices you have. It covers our website (including the waitlist and contact form) and the Grymode AI iOS app.',
  sections: [
    {
      title: 'What we collect',
      paragraphs: [
        'Depending on how you use Grymode, we may collect:',
      ],
      bullets: [
        'Waitlist: email address, optional source label, and basic technical details such as browser user agent.',
        'Contact form: first name, last name, email address, and your message.',
        'App account: email address used to sign in (for example via one-time code).',
        'Style preferences you choose in the app.',
        'Wardrobe photos you upload and labels derived from them (garment type and related metadata).',
        'Optional fit profile for personal try-on: height, body build, and a face photo.',
        'Looks and try-on images generated for your account.',
        'Subscription entitlement status from Apple when you purchase or restore a plan.',
        'Technical request identifiers and product-interaction signals needed to run and diagnose the service (not used for advertising).',
      ],
    },
    {
      title: 'How we use it',
      paragraphs: [
        'We use this information only to operate Grymode:',
      ],
      bullets: [
        'Notify you about launch and early product updates if you join the waitlist.',
        'Respond to messages you send through the contact form.',
        'Authenticate you and keep your wardrobe, looks, and preferences in your account.',
        'Identify garments from photos you upload and compose looks grounded in clothes you own.',
        'Create personal try-on previews when you choose to use that feature.',
        'Provide subscription access and honour App Store purchases.',
        'Keep the service secure and reliable.',
      ],
    },
    {
      title: 'Website waitlist and contact',
      paragraphs: [
        'If you join the waitlist, we store your email (and related signup details) so we can send launch updates. We may send a welcome email when you sign up. We keep a private operational backup of waitlist records to help us run the list reliably. You can ask us to remove your waitlist email at any time by contacting us.',
        'If you use the contact form, we use your details to reply. Messages are delivered to our inbox; we do not publish them.',
      ],
    },
    {
      title: 'Service providers',
      paragraphs: [
        'We use trusted processors to run Grymode. They act on our instructions and only as needed for the service:',
      ],
      bullets: [
        'Supabase — authentication, database, and private storage (including wardrobe media and operational waitlist backups).',
        'OpenAI — processes wardrobe photos to identify garments; uses your confirmed garment labels and style preferences to compose looks; and, when you open Try on, creates styled images of you wearing a look using your face photo, height, and body build. Requests are sent from our servers. Your account email is not sent for wardrobe extraction or look composition steps.',
        'Apple — processes App Store subscription purchases and related entitlement status.',
        'Resend — sends waitlist welcome emails and delivers contact-form messages to us.',
      ],
    },
    {
      title: 'What we do not do',
      paragraphs: [],
      bullets: [
        'We do not sell your personal information, wardrobe photos, or face photos.',
        'We do not show your looks or wardrobe to other users.',
        'We do not use your content for advertising or third-party ad targeting.',
        'We do not use your wardrobe or face photos to train our own models. Third-party model providers are used under their API terms for providing the feature; we do not opt your content into advertising products.',
      ],
    },
    {
      title: 'Retention and deletion',
      paragraphs: [
        'App accounts: you can delete your account in Profile. Deletion removes your auth identity, profile, wardrobe media, looks, avatar face photo, and related account data we hold for the product. App Store subscriptions are managed separately in Apple’s settings and are not cancelled automatically by account deletion.',
        'Waitlist and contact: we keep waitlist emails until you ask to be removed or we no longer need them for launch communications. Contact messages are retained as needed to handle your enquiry.',
        'Technical logs used for reliability are short-lived and do not include your photos or message bodies.',
      ],
    },
    {
      title: 'Children',
      paragraphs: [
        'Grymode is not directed at children under 13. Do not use the waitlist, contact form, or app if you are under 13. If you believe we have collected information from a child under 13, contact us and we will delete it.',
      ],
    },
    {
      title: 'Your choices',
      paragraphs: [
        'You can stop waitlist emails by contacting us. You can delete your app account in Profile. You can choose not to upload a face photo or use try-on. For access, correction, or deletion requests related to waitlist or contact data, email us at the address below.',
      ],
    },
    {
      title: 'Contact',
      paragraphs: [
        `Privacy and account requests: ${legalMeta.supportEmail}`,
        `Website and general enquiries: ${legalMeta.siteEmail}`,
      ],
    },
    {
      title: 'Updates',
      paragraphs: [
        'We may update this policy as the product evolves. The “Last updated” date at the top of this page will change when we do. Continued use of the site or app after an update means you accept the revised policy.',
      ],
    },
  ] satisfies LegalSection[],
} as const

export const termsOfUse = {
  eyebrow: 'Legal',
  title: 'Terms of Use',
  intro:
    'These Terms of Use govern your use of the Grymode AI website (including the waitlist and contact form) and the Grymode AI iOS app. By using Grymode, you agree to these terms.',
  sections: [
    {
      title: 'The service',
      paragraphs: [
        'Grymode AI helps you discover outfits from clothes you already own. The website lets you join a launch waitlist and contact us. The iOS app lets you upload wardrobe photos, generate looks grounded in your confirmed pieces, optionally try looks on with a personal fit profile, and unlock the full library with a subscription.',
        'Features may change as we improve the product. Pre-launch waitlist access does not guarantee a launch date, invite, or pricing.',
      ],
    },
    {
      title: 'Eligibility',
      paragraphs: [
        'You must be at least 13 years old. If you are under 18 (or the age of majority where you live), you may only use Grymode with a parent or guardian’s permission. You must be able to form a binding contract where required for App Store purchases.',
      ],
    },
    {
      title: 'Your account and content',
      paragraphs: [
        'You are responsible for the email and device access used to sign in. You retain rights to photos and other content you upload. You grant Grymode a limited licence to host, process, and display that content solely to provide the service (including sending it to our processors as described in the Privacy Policy).',
        'You confirm you have the rights needed to upload the photos you submit (for example, photos of your own clothes and your own likeness for try-on).',
      ],
    },
    {
      title: 'Waitlist and communications',
      paragraphs: [
        'Joining the waitlist means you ask us to contact you about Grymode’s launch and related product updates. You can ask to be removed at any time. Contact-form messages should be truthful and not abusive or unlawful.',
      ],
    },
    {
      title: 'Subscriptions',
      paragraphs: [
        'Paid plans are sold through Apple. They renew automatically until you cancel in Apple’s subscription settings. Pricing and terms shown in the App Store product sheet at purchase control the transaction. Deleting your Grymode account does not by itself cancel an Apple subscription.',
      ],
    },
    {
      title: 'Acceptable use',
      paragraphs: [
        'You agree not to:',
      ],
      bullets: [
        'Upload content you do not have rights to, or content that is illegal, harmful, or infringing.',
        'Attempt to access another user’s wardrobe, looks, or account.',
        'Probe, overload, or disrupt the service, or reverse engineer it except where the law allows.',
        'Use Grymode to build a competing model or dataset from other users’ content.',
        'Misrepresent your identity when contacting us or joining the waitlist.',
      ],
    },
    {
      title: 'AI-generated results',
      paragraphs: [
        'Looks and try-on previews are generated automatically and may be imperfect. They are for inspiration and personal styling help, not professional advice. You decide what you wear.',
      ],
    },
    {
      title: 'Availability and changes',
      paragraphs: [
        'We may modify, suspend, or discontinue features. We are not liable for downtime outside our reasonable control. We may update these Terms; the “Last updated” date will change when we do. Material changes may be called out in the app or by email when practical.',
      ],
    },
    {
      title: 'Disclaimer and liability',
      paragraphs: [
        'The service is provided “as is” to the fullest extent permitted by law. We do not warrant uninterrupted or error-free operation. To the extent allowed by law, Grymode is not liable for indirect or consequential damages arising from your use of the site or app. Some jurisdictions do not allow certain limitations; in those places, our liability is limited to the maximum extent permitted.',
      ],
    },
    {
      title: 'Contact',
      paragraphs: [
        `Support: ${legalMeta.supportEmail}`,
        `Website: ${legalMeta.siteEmail}`,
      ],
    },
  ] satisfies LegalSection[],
} as const
