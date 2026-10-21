# 0002 — Typography, colour, and light appearance

- **Status:** Accepted
- **Date:** 2026-10-09

## Context

The brand calls for an editorial look: soft black `#1A1A1A`, warm off-white `#F5F3EF`, muted grey `#8A8A8A`,
and deep olive `#6B6B4B`, with serif display type. The app must also meet WCAG AA contrast and support Dynamic
Type up to the largest accessibility sizes.

## Decision

- **Fonts:** Oranienbaum (display) and Unna (headings), both under the SIL Open Font License 1.1, are bundled
  and registered through `UIAppFonts`. Licences are in `docs/licenses/`. Custom fonts scale with Dynamic Type
  through `relativeTo:`.
- **Body and controls** use the system font, which gives the most reliable Dynamic Type behaviour and legibility
  at small sizes.
- **Secondary text** uses graphite `#56564F` (about 6.6:1 on the background) instead of muted grey, which falls
  below 4.5:1. Muted grey is reserved for decorative, non-informational elements.
- **Olive** is used for accents and overlines on light surfaces (about 4.95:1). Text on the olive-mist container
  uses soft black, because olive on olive-mist falls below 4.5:1.
- **Appearance:** the app ships in light appearance only (`UIUserInterfaceStyle = Light`). The palette is
  defined for warm light surfaces, and a dark palette would need its own contrast and photography review.
- **Enforcement:** `ColorContrastTests` checks every text and background pairing used by the design system.

## Consequences

- Consistent brand presentation, with accessibility checked by tests.
- Dark mode is not offered in the MVP. Adding it later means defining a dark palette and extending the
  contrast tests.
