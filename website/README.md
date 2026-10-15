# Voco website

Voco's public product and download page lives here, independently of the Electron app.

## Develop

From this directory, run `npm ci`, then `npm run dev`. The local site uses port 4173.

Run `npm run build` to produce `dist/`. `npm run preview` serves the production build.

## Verify

Run `npm run verify:build` after building. It checks the real deployment output, section links, local assets, installer metadata, and fallback download link.

For browser verification, serve the production build on port 4174 with `npm run preview -- --port 4174`, then run `npm run verify:browser` in another terminal. The browser script uses installed Google Chrome and checks desktop, mobile, and 320px layouts, keyboard interactions, demo replay, reduced motion, offscreen animation pause, JavaScript-free content, release-metadata failure, and automated WCAG accessibility rules. It writes captures and a JSON report to the repository's ignored `.impeccable/review/` folder.

Set `VOCO_WEBSITE_URL` to verify a deployed URL instead of the local server.

## Assets and motion

The site uses Voco's committed logo, bundled Manrope font, and actual app-renderer captures with sample data. The sample notices remain visible. From the repository root, rebuild the app, then run:

```sh
env -u ELECTRON_RUN_AS_NODE ./node_modules/.bin/electron website/scripts/capture-app.cjs
```

This writes optimized WebP screenshots to `public/images/` and requires `cwebp`.

Run `env -u ELECTRON_RUN_AS_NODE ./node_modules/.bin/electron website/scripts/capture-social.cjs` from the repository root to regenerate the social preview image.

The original animated voice ribbon takes its visual cue from [Maple Research's ASCII posters on Vibrant](https://vibrant.design/feed/xjwkcs7-maple-research-ascii-posters). Individual text-reveal and accordion recipes come from the [transitions.dev skill](https://github.com/Jakubantalik/transitions.dev/tree/main/skills/transitions-dev). No reference-site artwork is redistributed.

## Downloads

`public/release.json` records the published version, installer URL, requirements, size, checksum, signing status, and app source revision. Keep its fallback download link in `index.html` synchronized so downloading also works without JavaScript.

Public binaries and release notes live in [voco-releases](https://github.com/darshmahadevia/voco-releases). The application repository remains private. The current early-access build has a local development signature and is not notarized by Apple. Explain that limitation next to the download.

## Deploy

The Vercel project is `voco`. Its root directory is `website`, framework is Vite, and production URL is https://voco-mac.vercel.app. The shorter `voco.vercel.app` was already assigned to another project.

Run `vercel --prod --scope mahadeviadarsh-gmailcoms-projects` from the repository root after linking it to the `voco` project. Confirm the current CLI user is `mahadeviadarsh-9908` and project ID is `prj_hBlibLftP2NlCHgNJhPaLP1T4tIL` before deploying. The root `.vercelignore` uploads only the website and excludes local credentials and build artifacts. Keep `.vercel/` and `.env*` out of Git.

The project is linked to the private GitHub repository in the personal workspace `mahadeviadarsh-gmailcoms-projects`. Pushes to `main` trigger production deployment from `website/`. Standard Vercel protection keeps preview and unique deployment URLs protected while the production alias is public.
