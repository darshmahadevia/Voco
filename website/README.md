# Voco website

Voco's public product and download page lives here, independently of the Electron app.

## Develop

From this directory, run `npm ci`, then `npm run dev`. The local site uses port 4173.

Run `npm run build` to produce `dist/`. `npm run preview` serves the production build.

## Verify

Run `npm run verify:build` after building. It checks the real deployment output, section links, local assets, installer metadata, and fallback download link.

For browser verification, serve the production build on port 4174 with `npm run preview -- --port 4174`, then run `npm run verify:browser` in another terminal. The browser script uses installed Google Chrome and checks 1440px, 1280px, 768px, 390px, and 320px layouts, keyboard interactions, demo samples, replay, cancellation, screenshot viewing, reduced motion, JavaScript-free content, release-metadata failure, and automated WCAG accessibility rules. It writes captures and a JSON report to the repository's ignored `.impeccable/review/` folder.

Set `VOCO_WEBSITE_URL` to verify a deployed URL instead of the local server.

## Assets and motion

The site uses Voco's committed logo, bundled Manrope font, and actual app-renderer captures with sample data. The sample notices remain visible. From the repository root, rebuild the app, then run:

```sh
env -u ELECTRON_RUN_AS_NODE ./node_modules/.bin/electron website/scripts/capture-app.cjs
```

This writes optimized WebP screenshots to `public/images/` and requires `cwebp`.

Run `env -u ELECTRON_RUN_AS_NODE ./node_modules/.bin/electron website/scripts/capture-social.cjs` from the repository root to regenerate the social preview image.

The marketing page matches Voco’s dark graphite, soft-white, and orange theme, with a deeper graphite demonstration section. Its tactile Fn key draws on [Beside's spacious hero](https://vibrant.design/website/pcyiyzl-beside-s-hero-section). The dark editorial pacing draws on [Griffin](https://vibrant.design/website/yovgmpb-griffin-the-bank-you-can-build-on). Reference artwork is not redistributed. Site-specific tokens and behavior are documented in [DESIGN.md](DESIGN.md), independently of the desktop app's design system.

The simulated demo has three sample records and one explicit phase: idle, listening, transcribing, or complete. The hero key and play control use the same state machine. Switching examples, pressing Cancel or Escape, or hiding the page cancels outstanding timers. Full text appears only when transcription completes. No audio plays and no browser microphone permission is requested. Reduced motion completes the demonstration immediately.

The screenshot gallery supports arrow keys, Home, and End. View full size opens the selected screenshot in a native modal dialog with horizontal scrolling on small screens. Escape and Close restore focus to the opener. Keep sample-data notices in the source captures. Captures use an 1100 × 880 CSS-pixel viewport at the display's native scale. PNG metadata and WebP JSON sidecars record asset origins.

## Downloads

`public/release.json` records the published version, installer URL, requirements, size, checksum, signing status, and app source revision. Keep its fallback download link in `index.html` synchronized so downloading also works without JavaScript.

Public binaries and release notes live in [voco-releases](https://github.com/darshmahadevia/voco-releases). The application repository remains private. The current early-access build has a local development signature and is not notarized by Apple. Explain that limitation next to the download.

## Deploy

The primary Vercel project is `voco` in the personal workspace `mahadeviadarsh-gmailcoms-projects`. Its root directory is `website`, and its framework is Vite. The requested production address is https://getvoco.vercel.app. The alias transfer and live verification are pending.

Run `vercel --prod --scope mahadeviadarsh-gmailcoms-projects` from the repository root after linking it to the `voco` project. Confirm the current CLI user is `mahadeviadarsh-9908` and project ID is `prj_hBlibLftP2NlCHgNJhPaLP1T4tIL` before deploying. The root `.vercelignore` uploads only the website and excludes local credentials and build artifacts. Keep `.vercel/` and `.env*` out of Git.

The project is linked to the private GitHub repository in the personal workspace `mahadeviadarsh-gmailcoms-projects`. Pushes to `main` trigger production deployment from `website/`. Standard Vercel protection keeps preview and unique deployment URLs protected while the production alias is public.
