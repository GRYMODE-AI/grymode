# Grymode Privacy Policy (draft for hosting)

_Last updated: 11 October 2026_

This draft is the source for `https://grymode.ai/privacy`. Host the rendered page before App Store submission.

## What we collect

- Account email (sign-in)
- Style preferences you choose
- Wardrobe photos and derived garment labels
- Optional fit profile (height, body build, face photo) for personal try-on previews
- Subscription entitlement status from Apple when you purchase
- Technical request identifiers needed to operate the service

## How we use it

Only to provide Grymode: authenticate you, extract wardrobe pieces, generate looks grounded in clothes you own, personal try-on previews, and subscription access.

## Service providers

- **OpenAI** processes wardrobe photos (to identify garments) and your confirmed garment labels and style preferences (to compose looks). Requests are sent from our servers only and are handled under OpenAI's API data-usage terms (verify the current retention and training terms before publishing). Your email and face photo are not sent for these steps.
- **OpenAI** also creates the styled image of each look from your garment photos and, only when you open Try on, an image of you wearing the look from four angles using your face photo, height, and body build. The generated images are stored privately in your Grymode account and deleted with it.
- **Supabase** hosts authentication, the database, and private photo storage.
- **Apple** processes subscription purchases.

## What we do not do

- We do not sell your wardrobe or face photos
- We do not show your looks to other users
- We do not use your content for advertising

## Retention and deletion

You can delete your account in Profile. Deletion removes Auth identity, profile, wardrobe media, looks, avatar face photo, and related rows. See `docs/data-retention.md` for technical detail.

## Contact

support@grymode.ai
