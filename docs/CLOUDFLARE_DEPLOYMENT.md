# AZKAR Cloudflare Workers Deployment

## Selected architecture

AZKAR is deployed as **Cloudflare Workers Static Assets**, not Cloudflare
Pages. The existing Worker is `azkar-sadaqa`, with the production hostname
[`azkar-sadaqa.mohamed-fooda-mtf.workers.dev`](https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev).
Supabase remains the authentication and data backend.

The production pipeline is GitHub Actions. The source-template and routing
failures recorded on 2026-10-31 are historical; subsequent production Actions
runs succeeded. The pipeline installs the pinned Flutter SDK, runs analysis
and tests, builds Flutter Web, checks the compiled output, and deploys the
existing Worker with pinned Wrangler. Keep the old Cloudflare Git build
connection disabled to avoid competing deployments.

This repository does not create a Worker or change its hostname. Production
deployment is gated by the GitHub `production` environment and requires a
reviewer approval configured in GitHub settings.

## Build-time Supabase configuration

`lib/core/config/app_config.dart` reads Flutter compile-time Dart defines.
Cloudflare runtime variables do **not** populate the compiled Flutter
JavaScript. The protected GitHub environment therefore supplies:

| GitHub environment value | Purpose |
|---|---|
| `AZKAR_SUPABASE_URL` secret | Existing production Supabase HTTPS URL |
| `AZKAR_SUPABASE_PUBLISHABLE_KEY` secret | Supabase anon/publishable client key only |
| `AZKAR_AUTH_SCHEMA_VERIFIED` workflow value | `true` in the approved production configuration after the recorded schema/RLS checks |
| Android APK download URL | Published v1.0.2 release asset; update only after a newer APK is published |
| `CLOUDFLARE_API_TOKEN` secret | Least-privilege token for deploying the existing Worker |
| `CLOUDFLARE_ACCOUNT_ID` secret | Account that owns the Worker |

The workflow writes the ignored `config/production.json` only on its runner.
It sets `AZKAR_DEMO_MODE` to `false` and the existing public origin to
`https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev`. It fails closed unless
the Supabase URL/key are valid and `AZKAR_AUTH_SCHEMA_VERIFIED` is an explicit
boolean. The approved production workflow preserves its verified `true` value. Do not put a service-role
key, database password, Cloudflare token, or other privileged secret in Flutter
defines. The Web build is pinned to the published APK at
`https://github.com/MTFOODA/Azkar/releases/download/v1.0.2/AZKAR-v1.0.2-android.apk`;
the build fails if a different or unpublished URL is configured.

For a local release build, copy
[`config/production.example.json`](../config/production.example.json) to the
ignored `config/production.json`, enter the approved production URL and
publishable key locally, and use the already approved verification setting for
this project. Other projects require their own schema/RLS checks. Then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_web_production.ps1
```

The build requires the exact production hostname, valid HTTPS Supabase
configuration, Demo Mode disabled, and schema verification enabled. It builds
with Flutter release mode and validates:

- `build/web/index.html`, root base URL, and Flutter bootstrap.
- Compiled `main.dart.js` containing the configured public site origin.
- Flutter asset manifest, web manifest, icon, and an Arabic font asset.
- Replacement of the generic social metadata URL placeholder.
- Absence of `pages.dev`, localhost, and loopback URLs from generated metadata.

The build also writes public `release.json` containing the source commit,
application version and build time. This metadata contains no credentials.
The local production configuration is ignored by Git.

## Wrangler Static Assets and SPA routing

[`wrangler.jsonc`](../wrangler.jsonc) is the source of truth for deployment:

- Worker name: `azkar-sadaqa`.
- Static asset directory: `./build/web` (never the source `web/` directory).
- `workers_dev: true`, preserving the existing Worker hostname.
- `assets.not_found_handling: "single-page-application"`.

Cloudflare Workers Static Assets serves matching files as-is and returns
`index.html` for unmatched navigation requests. This supports Flutter's
path-based `/m/:slug` route, browser refresh, login, registration, recovery,
and dashboard navigation without a Pages `_redirects` file or a custom Worker
entry point. Missing non-navigation assets remain missing rather than being
silently rewritten to HTML.

The build output contains only the compiled public client and its assets. The
ignored production configuration file is outside `build/web` and is not
uploaded. `PUBLIC_BASE_URL` is a compile-time value used for share links, Auth
redirects, and generic social metadata.

## GitHub Actions deployment

The workflow is
[`deploy-worker.yml`](../.github/workflows/deploy-worker.yml). It:

1. Runs on pushes to `main` or an explicit workflow dispatch on `main`.
2. Uses Flutter 3.47.7, runs `flutter analyze` and `flutter test`, and blocks
   deployment if either fails.
3. Waits for the protected GitHub environment `production`.
4. Creates the local production config from environment secrets and builds the
   compiled Web application.
5. Uses Wrangler 4.156.0 and `wrangler.jsonc` to deploy the existing Worker.

The workflow retains the production authentication setting approved on `main`.
It deploys only `main` and waits for the existing production environment
review. Its download link targets the already published v1.0.2 APK.

The workflow grants `GITHUB_TOKEN` read-only `contents` permission. It does not
deploy preview branches. Pull requests run the validation job only. The production environment
must have required reviewers configured; merely naming an environment does
not create an approval gate.

### One-time Cloudflare change

Before enabling this workflow, open **Cloudflare Dashboard → Workers & Pages →
`azkar-sadaqa` → Settings → Builds** and disconnect the existing Git build
connection (or disable its production builds if the dashboard offers that
option). Do not delete the Worker. This leaves the current active deployment
untouched and prevents the old build, which uploaded source `web/`, from
competing with GitHub Actions.

### Wrangler versions and local checks

The GitHub workflow pins Flutter 3.47.7 and Wrangler 4.156.0. With a local
Node.js installation and an authenticated Cloudflare account, the manual
deployment script uses the same Wrangler version. It performs an authenticated
account check and a dry run, then requires typing `DEPLOY PRODUCTION` before
uploading:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy_cloudflare.ps1
```

For local routing verification after a valid release build:

```powershell
npx.cmd --yes wrangler@4.156.0 dev --local --ip 127.0.0.1 --port 8787
```

Open `http://127.0.0.1:8787/` and directly request `/login`,
`/register`, `/reset-password`, and `/m/<published-slug>`. This verifies local
static-asset routing only; it is not proof of a production release or live
Supabase access.

## Authentication redirect allowlist

The application requests these exact redirects:

- Signup/email confirmation: `https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev/dashboard`
- Password recovery: `https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev/reset-password`

In **Supabase Dashboard → Authentication → URL Configuration**, set the Site
URL to the production origin and add those exact URLs to the Redirect URLs
allowlist. Preserve existing development URLs. Do not guess callback paths or
remove unrelated redirects.

## Data provisioning and tenant security

The client uses the existing Supabase Auth flow. The signup service sends a
display name and page-title metadata; it does not create memorial pages.
`azkar_provision_owner_page` remains the single database provisioning trigger.
The registration UI has four fields, and page title/slug management remains in
Dashboard → Page Settings.

The committed SQL defines RLS on the application tables, owner-scoped writes,
published-only anonymous reads, and active database-backed administrator
checks. Static review of these definitions is not proof that the live
Supabase project matches them. Do not rerun the initial schema, disable RLS,
or set `AZKAR_AUTH_SCHEMA_VERIFIED=true` until approved, isolated acceptance
tests establish owner isolation, unpublished-page privacy, and anonymous
read-only behavior.

The mobile/widget release does not alter production users, content, or schema.
It preserves the previously approved production authentication setting. New
live account-flow tests still require appropriate isolated test accounts.

## Rollback and operational limits

For a bad Worker release, use **Workers & Pages → `azkar-sadaqa` →
Deployments/Version history** to promote the last known-good Worker version.
Verify the production URL after rollback. A Worker rollback does not revert
Supabase data, Auth settings, or schema.

Generic Open Graph and Twitter metadata are present. Per-memorial social
previews are not implemented because the site renders memorial content in the
Flutter client. Dynamic, publication-aware previews are a separate future
enhancement and are not part of this deployment.

## Cloudflare Pages is not the selected hosting mode

Pages commands such as `wrangler pages deploy`, `wrangler pages dev`, and
`pages.dev` hostnames do not apply to the existing Worker. Do not create a
Pages project or use Pages-specific fallback behavior for this deployment.

## Identifying the deployed release

Read `/release.json` on the production origin and compare `commit` with the
merged `main` commit and the corresponding successful
[Actions run](https://github.com/MTFOODA/Azkar/actions/workflows/deploy-worker.yml).
Verify HTTP 200 for the homepage, compiled bootstrap/application, assets, and
navigation requests to `/login` and `/m/<slug>`.

A successful SPA response does not prove a particular memorial exists or
establish live RLS behavior. iOS widgets require separate macOS/Xcode checks;
Android home-screen widgets are native and are not rendered on the website.
Older production acceptance reports retain their original dated observations.
