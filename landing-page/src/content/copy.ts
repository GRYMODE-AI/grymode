/** Product strings aligned with the Grymode iOS app (Welcome, Style, Home). */

export const brand = {
  name: 'Grymode',
  product: 'Grymode AI',
  tagline: 'Your personal stylist.',
  domain: 'grymode.ai',
  year: 2026,
} as const

export const hero = {
  eyebrow: 'Your Personal AI Stylist',
  headline: 'Your wardrobe has more to say.',
  support:
    'Grymode finds new ways to wear the clothes you already own. Add your wardrobe and we’ll build a personal library of complete outfits from it.',
  cta: 'Join the Waitlist',
  comingSoon: 'Coming Soon · Private Beta',
} as const

export const dilemma = {
  eyebrow: 'The Dilemma',
  headline: 'A full wardrobe.\nStill nothing to wear?',
  body: 'You have the shirts. The trousers. The dresses. The shoes. But finding the right combination shouldn’t be the hardest part of getting dressed each morning.',
  vignettes: [
    {
      label: '01 · Overwhelm',
      caption: 'Pieces lost in closet corners',
      image: '/images/dilemma-overwhelm.jpg',
      alt: 'A full closet packed with hanging coats and garments',
      objectPosition: 'center',
    },
    {
      label: '02 · Repetition',
      caption: 'Reaching for the same pieces',
      image: '/images/dilemma-repetition.jpg',
      alt: 'A rack of nearly identical shirts and trousers',
      objectPosition: 'center',
    },
  ],
  quote: 'Sometimes, you don’t need more clothes. Just a better way to style them.',
} as const

export const howItWorks = {
  eyebrow: 'A Smarter Way to Get Dressed',
  headline: 'Your wardrobe.\nReimagined.',
  steps: [
    {
      n: '01',
      title: 'Capture your clothes',
      body: 'Upload photos of your wardrobe. Grymode identifies pieces and you confirm what we found.',
    },
    {
      n: '02',
      title: 'Discover your looks',
      body: 'Get complete outfits made only from what you own — ordered by occasion, weather, and how you like to dress.',
    },
    {
      n: '03',
      title: 'Save & try on',
      body: 'Archive favourites into your library, then see how a look sits on you from multiple angles.',
    },
  ],
} as const

export const versatility = {
  eyebrow: 'From Your Closet',
  headline: 'More outfits.\nSame wardrobe.',
  body: 'Fresh ways to wear the pieces you already love — one wardrobe, many occasions. These looks are assembled only from clothes you own.',
  staples: ['Navy Polo', 'Chinos', 'Blazer', 'Loafers', 'Field Jacket', 'Desert Boots'],
  looks: [
    {
      label: 'Look 01',
      title: 'Easy Navy Classic',
      tone: 'Weekend · Smart casual',
      detail: 'Navy polo · Chinos · Loafers · Wristwatch · Sunglasses',
      image: '/images/look-easy-navy-classic.jpg',
    },
    {
      label: 'Look 02',
      title: 'Blue City Stroll',
      tone: 'Weekend · Dinner',
      detail: 'Button-up · Straight jeans · Desert boots · Trench · Watch',
      image: '/images/look-blue-city-stroll.jpg',
    },
    {
      label: 'Look 03',
      title: 'Understated Dinner',
      tone: 'Evening · Dinner',
      detail: 'White shirt · Dress pants · Loafers · Navy blazer · Watch',
      image: '/images/look-understated-dinner.jpg',
    },
  ],
} as const

export const occasions = {
  eyebrow: 'Contextual Dressing',
  headline: 'For wherever life takes you.',
  body: 'From everyday plans to moments worth dressing up for. Grymode adapts to cultural codes and contemporary elegance.',
  items: [
    {
      n: '01',
      title: 'Work & Executive',
      detail: 'Crisp lines, quiet authority, easy neutrals',
      image: '/images/look-understated-dinner.jpg',
      alt: 'Navy blazer look for work and executive settings',
    },
    {
      n: '02',
      title: 'Dinner & Intimate',
      detail: 'Subtle drape, evening silk, soft lighting',
      image: '/images/look-camel-after-dark.jpg',
      alt: 'Camel sweater evening dinner look',
    },
    {
      n: '03',
      title: 'Weddings & Owambe',
      detail:
        'Tailored Agbada, structured kaftans & silks — heritage silhouettes with modern precision.',
      image: '/images/occasion-owambe.jpg',
      alt: 'Contemporary Agbada for weddings and Owambe',
    },
    {
      n: '04',
      title: 'Weekends',
      detail: 'Relaxed linen, premium cotton basics',
      image: '/images/look-autumn-field-notes.jpg',
      alt: 'Casual weekend field jacket look',
    },
  ],
} as const

export const mission = {
  eyebrow: 'Why We’re Building Grymode AI',
  headline: 'Good style shouldn’t require a bigger wardrobe.',
  paragraphs: [
    'We believe getting dressed should feel effortless, intentional, and deeply personal.',
    'Grymode AI helps you discover more possibilities in the clothes you already own.',
  ],
  closer: 'Less guessing. More confidence.',
} as const

export const waitlist = {
  eyebrow: 'Grymode AI · Coming Soon',
  headline: 'Your next favourite outfit might already be in your wardrobe.',
  body: 'Be among the first to know when Grymode AI launches. Discreet, curated early access.',
  placeholder: 'Enter your email',
  submit: 'Join the Waitlist',
  successTitle: 'You’re on the list',
  successBody: 'We’ll let you know when Grymode AI is ready. No noise — just elevated style.',
  alreadyTitle: 'You’re already on the list',
  alreadyBody: 'This email is already registered. We’ll be in touch when Grymode AI launches.',
  disclaimer: 'Get notified about our launch and early product updates. No spam.',
  privacyNote: 'Your wardrobe photos stay private to your account.',
} as const

export const nav = {
  links: [
    { label: 'How it works', href: '#how-it-works' },
    { label: 'Occasions', href: '#occasions' },
    { label: 'Why Grymode', href: '#mission' },
  ],
  cta: 'Join Waitlist',
} as const

export const footer = {
  links: [
    { label: 'Privacy', href: '/privacy' },
    { label: 'Terms', href: '/terms' },
    { label: 'Contact', href: '#contact', action: 'contact' as const },
  ],
  social: [
    {
      label: 'Instagram',
      href: 'https://www.instagram.com/grymodeai',
    },
    {
      label: 'TikTok',
      href: 'https://www.tiktok.com/@grymodeai',
    },
    {
      label: 'X',
      href: 'https://x.com/grymodeai',
    },
  ],
} as const

export const contact = {
  eyebrow: 'Contact',
  title: 'Get in touch.',
  body: 'Tell us what’s on your mind. We read every message.',
  firstName: 'First name',
  lastName: 'Last name',
  email: 'Email',
  message: 'Message',
  messagePlaceholder: 'What would you like to share?',
  submit: 'Send message',
  sending: 'Sending…',
  successTitle: 'Message sent.',
  successBody: 'Thanks — we’ll get back to you at the email you provided.',
  close: 'Close',
} as const
