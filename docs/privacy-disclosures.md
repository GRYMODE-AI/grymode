# Privacy disclosures (App Store)

## Nutrition label summary

| Data type | Linked to user | Used for tracking | Purpose |
| --- | --- | --- | --- |
| Email address | Yes | No | App functionality (sign-in) |
| Photos / videos | Yes | No | Wardrobe + optional face for try-on |
| Other user content | Yes | No | Style preferences, garment labels, looks |
| Product interaction | Yes | No | App functionality / diagnostics |
| Purchase history | Yes | No | Subscription entitlement |

Tracking: **No**. No third-party advertising SDKs.

Service providers (not "third-party partners" for tracking): OpenAI processes wardrobe photos and
confirmed garment labels server-side for extraction and look composition (ADR 0011), and renders
look images from garment photos plus try-on images from the face photo, height, and build when
the user opens Try on (ADR 0012). Apple's
"Data used to track you" stays empty; disclose Photos and Other user content as collected and
linked, purpose App Functionality.

## Manifest

`ios/Grymode/PrivacyInfo.xcprivacy` declares the same categories and UserDefaults API reason `CA92.1`.

## Legal URLs in app

- Privacy: https://grymode.ai/privacy (`LegalLinks.privacy`)
- Terms: https://grymode.ai/terms (`LegalLinks.terms`)
- Support: mailto:support@grymode.ai (`LegalLinks.support`)

Rendered pages: landing-page routes `/privacy` and `/terms` (`landing-page/src/content/legal.ts`). Markdown mirrors live in `docs/legal/`.
