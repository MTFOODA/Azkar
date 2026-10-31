# AZKAR Cloudflare Workers Production Checklist

## Before enabling deployment

- [ ] Confirm the existing Worker is `azkar-sadaqa`; do not create a replacement.
- [ ] Keep the production hostname
      `https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev`.
- [ ] Confirm Cloudflare Workers Static Assets is the hosting mode; Pages
      commands and `pages.dev` hostnames are not used.
- [ ] Review `wrangler.jsonc`; its Worker name must match and its assets
      directory must be `build/web`.
- [ ] Disconnect or disable the existing Cloudflare Workers Build connection
      before enabling GitHub Actions, preventing duplicate production deploys.
- [ ] Configure the GitHub `production` environment with required reviewers.
- [ ] Add only the required Supabase and Cloudflare Environment secrets.
- [ ] Keep `AZKAR_AUTH_SCHEMA_VERIFIED=false` until production RLS, provisioning,
      and tenant-isolation checks are approved and complete.
- [ ] In Supabase Auth URL Configuration, preserve existing redirects and add
      the production `/dashboard` and `/reset-password` URLs.
- [ ] Do not use a service-role key, database password, or Cloudflare token in
      Flutter Dart defines.

## Automated checks and build

- [ ] `flutter analyze` succeeds.
- [ ] `flutter test` succeeds; record the actual test count.
- [ ] GitHub Actions uses Flutter 3.47.7 and Wrangler 4.156.0.
- [ ] The production build has Demo Mode disabled and the exact production URL.
- [ ] `build/web/index.html` contains the root base href and resolved generic
      metadata, not `$FLUTTER_BASE_HREF` or the metadata placeholder.
- [ ] Compiled `main.dart.js`, `flutter_bootstrap.js`, asset manifest, icons,
      manifest, and Arabic fonts are present.
- [ ] Wrangler deploy configuration uses `build/web` and SPA fallback; never
      upload source `web/`.
- [ ] No ignored production configuration or private credentials are staged.
- [ ] Production build and deployment are explicitly approved before running.

## After Cloudflare deployment

- [ ] Wrangler output identifies the existing `azkar-sadaqa` Worker.
- [ ] Production homepage returns the compiled Flutter application, not source
      HTML or the Flutter template.
- [ ] Direct navigation and refresh work for `/login`, `/register`,
      `/reset-password`, and `/m/<published-slug>`.
- [ ] Published memorial data loads anonymously; unpublished pages/content
      remain unavailable.
- [ ] Registration still contains only name, email, password, and confirmation.
- [ ] Share links use the production Worker origin and the correct encoded slug.
- [ ] Verify Copy Link and native sharing on a real device when available.
- [ ] Check browser console/network, fonts, icons, Arabic RTL, responsive sizes,
      back/forward navigation, and Supabase errors.
- [ ] Run authorized Supabase isolation tests for two owners and anonymous
      access; static policy inspection is not live proof.
- [ ] Record the deployment/version ID and keep a known-good Worker version for
      rollback.
- [ ] Do not declare launch readiness while critical authentication or RLS
      checks remain blocked.

## Current observed status

- [x] Existing homepage returns HTTP 200 but contains the raw Flutter source
      template; this is a failed deployment, not an acceptance pass.
- [x] Existing `/m/azkar-production-check` request returns HTTP 404.
- [ ] Corrected production build deployed — pending explicit approval.
- [ ] Production authentication and RLS tests — pending approved test setup.
