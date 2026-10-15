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

The rebuilt page uses a near-black canvas, soft-white text, orange voice traces, and an editorial opening. [REBUILD.md](REBUILD.md) records the reference observations and section sequence. [DESIGN.md](DESIGN.md) records the website system independently of the desktop app.

The illustrative demo has three samples and one explicit phase. It moves through idle, listening, transcribing, and complete. Switching samples, Cancel, Escape, and hiding the page clear pending timers. The transcript arrives together after processing. No browser microphone is used. Reduced-motion playback resolves immediately. The canvas voice traces stop while offscreen or hidden and become static under reduced motion.

The real interface recording shows Home, Settings, Models, Stats, and Home again. It uses the renderer's ready-state preview with sample data. Native dictation is inactive. To reproduce it, run `npm run dev:ui` from the repository root, then run `node website/scripts/capture-walkthrough.cjs`. Capture uses installed Google Chrome and requires `ffmpeg` and `ffprobe`. The script trims browser startup from the clip and verifies its dimensions and duration. Captions describe the silent interface sequence.

The screenshot gallery supports arrow keys, Home, and End. View full size opens the selected screenshot in a native dialog. Escape and Close restore focus to the opener. Preserve sample-data notices in all captures.

## Downloads

`public/release.json` records the published version, installer URL, requirements, size, checksum, signing status, and app source revision. Keep its fallback download link in `index.html` synchronized so downloading also works without JavaScript.

Public binaries and release notes live in [voco-releases](https://github.com/darshmahadevia/voco-releases). The application repository remains private. The current early-access build has a local development signature and is not notarized by Apple. Explain that limitation next to the download.

## Deploy

The primary Vercel project is `voco` in the personal workspace `mahadeviadarsh-gmailcoms-projects`. Its root directory is `website`, and its framework is Vite. The live production address is https://getvoco.vercel.app. This hostname belongs to the personal project. The previous address, https://voco-mac.vercel.app, redirects to it with HTTP 308. Canonical and social metadata, the sitemap, and robots.txt use `getvoco.vercel.app`.

Run `vercel --prod --scope mahadeviadarsh-gmailcoms-projects` from the repository root after linking it to the `voco` project. Confirm the current CLI user is `mahadeviadarsh-9908` and project ID is `prj_hBlibLftP2NlCHgNJhPaLP1T4tIL` before deploying. The root `.vercelignore` uploads only the website and excludes local credentials and build artifacts. Keep `.vercel/` and `.env*` out of Git.

The project is linked to the private GitHub repository in the personal workspace `mahadeviadarsh-gmailcoms-projects`. Pushes to `main` trigger production deployment from `website/`. Standard Vercel protection keeps preview and unique deployment URLs protected while the production alias is public.
