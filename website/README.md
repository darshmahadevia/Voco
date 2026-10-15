# Voco website

Voco's public product and download page lives here, independently of the Electron app.

## Develop

From this directory, run `npm ci`, then `npm run dev`. The local site uses port 4173.

Run `npm run build` to produce `dist/`. `npm run preview` serves the production build.

## Assets and motion

The site uses Voco's committed logo, bundled Manrope font, and actual app-renderer captures with sample data. The sample notices remain visible. From the repository root, rebuild the app, then run:

```sh
env -u ELECTRON_RUN_AS_NODE ./node_modules/.bin/electron website/scripts/capture-app.cjs
```

This writes optimized WebP screenshots to `public/images/` and requires `cwebp`.

The original animated voice ribbon takes its visual cue from [Maple Research's ASCII posters on Vibrant](https://vibrant.design/feed/xjwkcs7-maple-research-ascii-posters). Individual text-reveal and accordion recipes come from the [transitions.dev skill](https://github.com/Jakubantalik/transitions.dev/tree/main/skills/transitions-dev). No reference-site artwork is redistributed.

## Downloads

`public/release.json` records the published version, installer URL, requirements, size, checksum, signing status, and app source revision. Keep its fallback download link in `index.html` synchronized so downloading also works without JavaScript.

Public binaries and release notes live in [voco-releases](https://github.com/darshmahadevia/voco-releases). The application repository remains private. The current early-access build has a local development signature and is not notarized by Apple. Explain that limitation next to the download.

## Deploy

The Vercel project is `voco`. Its root directory is `website`, framework is Vite, and production URL is https://getvoco.vercel.app. The shorter `voco.vercel.app` was already assigned to another project.

Run `vercel --prod` from the repository root after linking it to the `voco` project. The root `.vercelignore` uploads only the website and excludes local credentials and build artifacts. Keep `.vercel/` and `.env*` out of Git.

Vercel's GitHub integration could not access the private repository during setup. CLI deployments work; automatic deployment on push requires granting the Vercel GitHub app access to this repository and reconnecting it. Standard Vercel protection keeps preview and unique deployment URLs protected while the production alias is public.
