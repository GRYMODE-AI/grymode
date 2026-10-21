# Release checklist (Phase 8 → 9)

## Before TestFlight / App Review

- [ ] Host live Privacy Policy and Terms from `docs/legal/` at `https://grymode.ai/privacy` and `/terms`
- [ ] Confirm Profile → Legal & support opens those URLs + `mailto:support@grymode.ai`
- [ ] `PrivacyInfo.xcprivacy` present in the app target
- [ ] Local/review demo: `./scripts/dev-stack.sh` then `./scripts/seed-demo-account.sh`
- [ ] Sign in as `review@grymode.test` (OTP via Mailpit locally)
- [ ] Home shows today’s look; Looks shows 9 seeded looks; free reveal + premium library
- [ ] Account deletion completes and user cannot sign back in with the same session
- [ ] StoreKit: `Products.storekit` configured for Debug; production JWS keys when available
- [ ] No secrets in the iOS binary (`Info.plist` / xcconfig review)

## App Store Connect — Review Notes (paste)

```
Demo account
Email: review@grymode.test
Sign-in: request email one-time code (or use the password provided in the secure review notes for hosted builds).

After sign-in the account already has a confirmed wardrobe and nine outfit looks.
• Home — today’s look, Try on (fit profile; face photo optional for full personal preview)
• Looks — full library (demo entitlement is premium), occasion filters, save
• Wardrobe — confirmed sample pieces
• Profile — Privacy Policy, Terms of Use, Contact support, Delete Account

Subscriptions use StoreKit. Sandbox testers can purchase Grymode Monthly/Yearly.
```

## Phase 9 (next)

- Physical device matrix (iPhone SE → Pro Max, iPad portrait/landscape)
- Accessibility Dynamic Type / VoiceOver spot check
- App Store screenshot capture (`build/capture-screenshots.sh`)
- TestFlight build + final compliance pass

## Deferred to AI phase (still MVP)

- Immersive 3D / VR try-on (ADR 0010) when real AI processing is wired
