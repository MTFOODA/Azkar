# AZKAR Cloudflare Workers Deployment

## Selected architecture

AZKAR is deployed as **Cloudflare Workers Static Assets**, not Cloudflare
Pages. The existing Worker is `azkar-sadaqa`, with the production hostname
[`azkar-sadaqa.mohamed-fooda-mtf.workers.dev`](https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev).
Supabase remains the authentication and data backend.

The production pipeline is GitHub Actions. Cloudflare's current Git-connected
Workers Build was configured with no build command and deployed `web/`; a
production request returned the unbuilt Flutter template, and `/m/...` returned
404. GitHub Actions is selected because it installs the project's pinned
Flutter SDK with caching, runs analysis and tests, compiles Flutter Web, checks
the compiled output, then deploys the existing Worker with a pinned Wrangler
version. The Cloudflare Workers Build connection must be disconnected before
the Actions workflow is enabled, so a commit cannot trigger two deployments.

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
| `AZKAR_AUTH_SCHEMA_VERIFIED` variable | Must be `true` only after production schema, provisioning, and RLS checks |
| Android APK download URL | Published v1.0.0 release asset; update only after a newer APK is published |
| `CLOUDFLARE_API_TOKEN` secret | Least-privilege token for deploying the existing Worker |
| `CLOUDFLARE_ACCOUNT_ID` secret | Account that owns the Worker |

The workflow writes the ignored `config/production.json` only on its runner.
It sets `AZKAR_DEMO_MODE` to `false` and the existing public origin to
`https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev`. It fails closed unless
the Supabase URL/key are valid and `AZKAR_AUTH_SCHEMA_VERIFIED` is explicitly
set to `false` until production signup is verified. Do not put a service-role
key, database password, Cloudflare token, or other privileged secret in Flutter
defines. The Web build is pinned to the published APK at
`https://github.com/MTFOODA/Azkar/releases/download/v1.0.0/AZKAR-v1.0.0-android.apk`;
the build fails if a different or unpublished URL is configured.

For a local release build, copy
[`config/production.example.json`](../config/production.example.json) to the
ignored `config/production.json`, enter the approved production URL and
publishable key locally, and keep schema verification false until its checks
are complete. Then run:

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

No local production Supabase configuration is currently present, so this
production build has not been run with real production settings.

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

The deployment job is skipped unless the production environment variable
`AZKAR_AUTH_SCHEMA_VERIFIED` is exactly `true`; it remains false until the live
provisioning and RLS acceptance checks are complete. After those checks, set
the variable and dispatch the workflow on `main` or push an approved update.

The workflow grants `GITHUB_TOKEN` read-only `contents` permission. It does not
deploy preview branches or run on pull requests. The production environment
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

No production users, content, or schema were created or changed for this
preparation. Live RLS verification and account-flow testing remain blocked
until an isolated test project or explicit account/test-data approval is
available.

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

## Current verification status

| Check | Result |
|---|---|
| Current production homepage response | **FAIL** — HTTP 200 returns the source HTML template, including `$FLUTTER_BASE_HREF` |
| Current production `/m/azkar-production-check` | **FAIL** — HTTP 404 |
| Local Flutter SDK | **PASS** — Flutter 3.47.7 / Dart 3.13.5 |
| Current Flutter Web output exists locally | **PASS** — compiled `main.dart.js`, bootstrap, icons, manifest, and font assets exist; not verified as a production build |
| Production configuration | **BLOCKED** — ignored `config/production.json` is absent |
| Live Supabase tenant isolation | **BLOCKED** — no approved isolated test accounts/data |
| Cloudflare/GitHub deployment | **NOT RUN** — requires dashboard changes, environment secrets, review, and explicit production approval |

See the
[`production manual actions`](PRODUCTION_MANUAL_ACTIONS_AR.md),
[`acceptance report`](PRODUCTION_ACCEPTANCE_REPORT.md), and
[`deployment checklist`](DEPLOYMENT_CHECKLIST.md) for gates and current
evidence.
