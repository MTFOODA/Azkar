# AZKAR Cloudflare Pages Deployment Checklist

## Before deployment

- [ ] Confirm the hosting mode with the project owner. Direct Upload cannot be
      converted to Git integration in place.
- [ ] Confirm the production Supabase project and approved release plan.
- [ ] Verify `SUPABASE_URL` and anon/publishable key in local
      `config/production.json`; never use a service-role key.
- [ ] Confirm `AZKAR_DEMO_MODE` is `false`.
- [ ] Set `AZKAR_AUTH_SCHEMA_VERIFIED` to `true` only after schema,
      provisioning trigger, and RLS acceptance checks pass.
- [ ] Set `PUBLIC_BASE_URL` to the final HTTPS Pages origin.
- [ ] Review the checked-in policies and run anonymous/draft and
      cross-owner RLS acceptance checks using approved test accounts.
- [ ] Run `flutter analyze` and `flutter test`.
- [ ] Build with `scripts/build_web_production.ps1`.
- [ ] Verify `build/web/index.html`, Flutter bootstrap, metadata hostname, and
      absence of a top-level `404.html`.
- [ ] Preview with `wrangler pages dev build\web --port 8788`.
- [ ] Confirm `/`, `/login`, `/register`, `/reset-password`, `/m/<slug>`,
      direct navigation, browser refresh, and back/forward.
- [ ] Confirm an unpublished page does not expose page/content data.
- [ ] Confirm no private key or service credential is present in build output.
- [ ] Confirm share URLs use the configured public hostname.

## During deployment

- [ ] Pages project was created manually only after mode approval.
- [ ] Project name and assigned production hostname were recorded.
- [ ] Selected project is the intended existing Direct Upload project.
- [ ] Wrangler is authenticated to the account that owns that project.
- [ ] `build\web` is the upload directory.
- [ ] Review the script's production target, then type the exact confirmation
      `DEPLOY PRODUCTION`.
- [ ] Record the deployment URL and deployment identifier from Wrangler or
      Cloudflare Dashboard.

## After deployment

- [ ] Homepage loads over HTTPS.
- [ ] Login, registration, and password recovery routes load directly.
- [ ] Registration still contains only name, email, password, and confirm
      password.
- [ ] A real published memorial URL loads in a signed-out browser.
- [ ] Direct URL entry and browser refresh work on `/m/<slug>`.
- [ ] Invalid/unpublished slugs show a friendly unavailable state.
- [ ] Published content and theme load; drafts/private content remain absent.
- [ ] Share/copy actions point to the production hostname.
- [ ] Arabic RTL, fonts, mobile layout, and browser back/forward work.
- [ ] Supabase logs and browser console contain no unexpected failures.
- [ ] Android/iOS shared application behavior remains unaffected.
- [ ] Keep a known-good Pages deployment available for rollback.

## Not yet a deployment result

- [ ] Do not mark the site live until a real Pages deployment and all post-
      deployment checks above have actually completed.

