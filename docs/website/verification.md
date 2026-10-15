# Website verification

The website was checked on October 15, 2026.

## Verified

- The desktop app built and packaged as `Voco-0.2.1-arm64.dmg`. Its bundle signature and native microphone entitlement passed the existing packaging checks. `hdiutil verify` passed.
- All 27 existing application unit tests passed.
- An anonymous download of the published installer matched the SHA-256 recorded in `website/public/release.json`.
- The website production build passed. `website/scripts/verify-build.mjs` checked local assets, section links, unique IDs, installer metadata, the JavaScript-free download, and deployment contents.
- `website/scripts/verify-browser.mjs` drove the built site in Google Chrome at 1440×1000, 390×844, and 320×740. No horizontal overflow or JavaScript errors occurred.
- Mobile navigation opens, closes with Escape, and restores focus. Gallery tabs support arrow navigation and wrapping. FAQ controls update their expanded state and make collapsed contents inert.
- The illustrative demo inserts the completed text after its processing state and can replay. The ribbon animates in view, pauses offscreen, and stays still with reduced motion enabled.
- The product copy, download link, and FAQ remain available without JavaScript. A failed release-manifest fetch preserves the fallback download link.
- Axe found no WCAG A/AA violations in the three checked layouts. This is automated coverage, not a complete assistive-technology audit.

The browser script writes screenshots and its report to `.impeccable/review/`. The T3 shared-browser screenshot capture produced duplicated images and reported a viewport that did not match the requested size. Those malformed images were discarded; the local Chrome captures supplied the visual evidence.

## Limits and hosting correction

The installer is early access, uses a local development signature, and is not notarized by Apple. Installation and recognition on a clean second Mac were not tested. The website and public release notes state the signing limitation.

The source repository remains private. Public distribution uses the separate binary-only `darshmahadevia/voco-releases` repository.

The initial CLI login belonged to Qurvo. An empty project was created there but never deployed. After the user's correction and Vercel reauthentication, the checkout was linked to project `prj_hBlibLftP2NlCHgNJhPaLP1T4tIL` in the personal workspace `mahadeviadarsh-gmailcoms-projects`. That project is connected to `darshmahadevia/Voco`, uses root directory `website`, and has production branch `main`.

`voco.vercel.app` was already assigned to another project. The personal workspace owns `voco-mac.vercel.app`. The earlier `getvoco.vercel.app` reservation remains on the unused Qurvo project, which the new login cannot access.

The requested Claude review provider was disabled and Grok was absent. An independent GPT-6-Astra review substitutes for the unavailable cross-family review.

## Independent finish review

GPT-6-Astra inspected the source and local browser captures. It found no blocking functional defect or material visual shortfall. Both required corrections were applied: `PRODUCT.md` now describes MIT-licensed code in a private repository with public binary distribution, and the release-notes link uses the existing SVG external-link icon.

The reviewer accepted the EARLY ACCESS badge and the concise brand copy. The original ribbon, responsive typography, demo labeling, download fallback, keyboard behavior, reduced-motion behavior, and verbatim upstream transition snippets and comments were preserved.

The review did not cover live production or independently execute the installer. There was no approved comp or QUALITY BAR card for this code-led build. The user explicitly delegated direction selection; no concept seed was used.

## Production verification

Commit `5fd2764` was pushed to `main` without force. The connected GitHub integration automatically deployed it as `dpl_DV8stN6fSv7ddJph7ivZoSSDKhpc`, with Vercel reporting Ready and GitHub reporting a successful deployment. No duplicate CLI deployment was needed.

Before and after deployment, the CLI identified user `mahadeviadarsh-9908` and project `prj_hBlibLftP2NlCHgNJhPaLP1T4tIL` in `mahadeviadarsh-gmailcoms-projects`, with root directory `website`. The production alias is https://voco-mac.vercel.app.

The same Chrome verification script passed against that public production alias at 1440, 390, and 320px. All interaction, reduced-motion, offscreen-pause, JavaScript-disabled, and manifest-failure checks passed, with no JavaScript errors, horizontal overflow, or automated WCAG violations. Anonymous HTTP requests returned 200 for all 14 deployment files, with each response matching the local production build byte for byte. The public installer link followed redirects to HTTP 200 and reported the expected 147,079,383-byte size. Its full anonymous-download checksum was verified earlier in this task.

GitHub reports `darshmahadevia/Voco` as private and `darshmahadevia/voco-releases` as public. The early-access signing and clean-second-Mac limitations above still apply.

## Mechanical detector

The Impeccable detector reported a flat typography hierarchy because it did not resolve the CSS imported by JavaScript. Actual desktop heading size is 94px, while supporting text is smaller. Its repeated short-sentence copy warning was passed to the independent finish reviewer.
