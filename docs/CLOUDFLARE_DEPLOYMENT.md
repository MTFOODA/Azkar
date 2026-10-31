# AZKAR Cloudflare Pages Deployment

## Architecture and hosting choice

AZKAR reuses the existing Flutter Web client and Supabase project. Cloudflare
Pages serves the compiled static files; Auth, database, and content remain on
Supabase. No Cloudflare account, project, Git connection, or deployment is
created by this preparation.

For the current Windows/local-build workflow and the absence of a Git repository
in the workspace, **Direct Upload with Wrangler is the recommended initial
choice**. It lets Flutter build on the developer machine and uploads only
`build/web`. The choice is not reversible in-place: Cloudflare says a
Direct Upload project cannot later be changed to Git integration, and a
Git-integrated project cannot be converted to Direct Upload. Choose only after
approval. Git integration remains an alternative for automatic builds and
branch previews once a suitable Git repository and reproducible Flutter build
environment exist.

Official references:

- [Cloudflare Pages Direct Upload](https://developers.cloudflare.com/pages/get-started/direct-upload/)
- [Cloudflare Pages Git integration](https://developers.cloudflare.com/pages/get-started/git-integration/)
- [Cloudflare Pages serving and SPA behavior](https://developers.cloudflare.com/pages/configuration/serving-pages/)

## Prerequisites

- Windows PowerShell and Flutter/Dart compatible with `pubspec.yaml`.
- A real production Supabase URL and anon/publishable key. Never use a
  service-role or secret key in this browser app.
- Production schema, provisioning trigger, and RLS reviewed and tested before
  setting `AZKAR_AUTH_SCHEMA_VERIFIED` to `true`.
- A final HTTPS Pages hostname for `PUBLIC_BASE_URL`.
- Node.js/npm and Wrangler for local Pages preview and deployment.
- An existing Cloudflare Pages project in Direct Upload mode. The deploy
  script will not create one.

## Production configuration

Copy the safe template and fill it in locally:

```powershell
Copy-Item config\production.example.json config\production.json
notepad config\production.json
```

Required values:

| Define | Requirement |
|---|---|
| `SUPABASE_URL` | Valid HTTPS project URL |
| `SUPABASE_ANON_KEY` | Supabase anon JWT or `sb_publishable_...` key |
| `AZKAR_DEMO_MODE` | JSON boolean `false` |
| `AZKAR_AUTH_SCHEMA_VERIFIED` | JSON boolean `true` only after production schema/RLS checks |
| `PUBLIC_BASE_URL` | Final HTTPS origin, for example `https://actual-name.pages.dev` |

`config/production.json` is ignored by Git. Flutter Dart defines are compiled
into the browser bundle and are not secrets. Do not copy any service-role key
into this file. The build script validates values without printing them,
executes the Flutter release build, substitutes the configured site origin in
the Open Graph tags in the generated `index.html`, and checks the SPA hosting
requirements.

## Build

Run from the project root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_web_production.ps1
```

The script runs the equivalent Flutter release build with:

```powershell
flutter build web --release --base-href / --dart-define-from-file=config/production.json
```

It then verifies `build/web/index.html` and `flutter_bootstrap.js`, requires the
site-root base URL, generates absolute generic social-image URLs, and rejects a
top-level `404.html`. A real production config is intentionally required. Do
not substitute fake production credentials or deploy a development build.

## SPA routing on Pages

`lib/main.dart` enables Flutter's path URL strategy for web builds. The actual
routes are `/`, `/login`, `/register`, `/reset-password`, `/m/:slug`,
`/m/:slug/:type`, and the dashboard/admin routes. Cloudflare Pages serves an
exact static asset when it exists; for paths that do not map to a file, Pages
uses the SPA root automatically **when there is no top-level `404.html`**.
Therefore:

- Keep Flutter assets and `index.html` in the deployment root (`build/web`).
- Do not add a blanket `_redirects` rule; it is unnecessary for this setup and
  can mask missing assets.
- Do not add a top-level `404.html` unless the SPA fallback design is revised.
- Do not rewrite requests for JS, CSS, fonts, icons, manifest, or service
  worker files.

Cloudflare reference: [Serving Pages](https://developers.cloudflare.com/pages/configuration/serving-pages/).

## Local production-output preview

Install Wrangler if needed, then serve the generated output using the Pages
development server:

```powershell
npm install --global wrangler
wrangler pages dev build\web --port 8788
```

Keep that terminal open and check `http://localhost:8788/`, `/login`,
`/register`, and a `/m/<published-slug>` route. Test a direct URL and refresh,
not only in-app navigation. The local browser still contacts Supabase; only
publicly published data should be returned to an anonymous visitor. A local
preview is not proof of a real Cloudflare deployment or live RLS acceptance.

## Create and deploy the Pages project manually

After confirming the irreversible Direct Upload choice, create the Pages
project in Cloudflare Dashboard. Pick a project name and note the exact
`pages.dev` hostname Cloudflare assigns. No deployment script creates the
project.

Authenticate Wrangler:

```powershell
wrangler login
wrangler whoami
wrangler pages project list
```

Set the project name in the current PowerShell session and ensure
`PUBLIC_BASE_URL` in the production config matches the final public origin:

```powershell
$env:CLOUDFLARE_PAGES_PROJECT_NAME = "actual-project-name"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_web_production.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy_cloudflare.ps1
```

The deployment script verifies the build files, Wrangler installation,
authentication, and existence of the named project. It prints the target and
asks you to type `DEPLOY PRODUCTION`. It then runs the Pages-specific command:

```powershell
wrangler pages deploy build\web --project-name actual-project-name
```

This script is for a pre-existing Direct Upload project. Git-integrated
projects have their own automatic deployment behavior; do not use this script
as a substitute for deciding and configuring the Git deployment workflow.
Wrangler may still be used with Git projects under Cloudflare's documented
conditions, but that is not the prepared deployment mode.

## Production URL and updating the site

Use the production hostname shown in the Pages project's **Deployments** page
or Wrangler success output. The same origin must be in `PUBLIC_BASE_URL` before
building, so page-share links, password recovery redirects, and social image
metadata use the public host. If the assigned hostname or custom domain changes,
update the local production config and rebuild before deploying.

For updates: review the code/config, run analysis and tests, build, preview with
`wrangler pages dev`, inspect the generated metadata and route behavior, then
deploy with confirmation. Cloudflare retains prior deployments in the
dashboard; select a known-good prior deployment and use its rollback/redeploy
action if a release must be reverted. A rollback of static assets does not
roll back Supabase schema or content.

Avoid custom cache rules initially. Pages already applies its static asset
caching behavior, and custom caching can leave stale Flutter bundles or
interfere with routing/Functions.

## Security checklist

- No service-role key, secret key, or admin credential in Dart defines or
  `build/web`.
- Demo Mode is false.
- Registration guard is enabled only after schema and RLS acceptance.
- Public memorial, content, homepage-card, and theme reads are limited to
  published resources by Supabase RLS.
- Owner writes remain owner-scoped; platform administration remains separate.
- Test anonymous access to a draft/unpublished slug and verify no private
  content is returned.
- Do not loosen RLS or add broad database grants to fix a hosting issue.
- Configure Supabase Auth allowed redirect URLs for the final Pages hostname
  and relevant login/dashboard/reset routes.

The checked-in SQL can be reviewed locally. Live policy behavior is not
certified by a Flutter test or by the presence of policy definitions; test the
intended Supabase project with approved accounts before production signup.

## Generic and dynamic link previews

The HTML entry response contains a generic AZKAR title, Arabic description,
Open Graph metadata, Twitter summary card, favicon, manifest, and an approved
AZKAR icon. Flutter cannot reliably set per-memorial metadata for social
crawlers after the client-side app loads.

Dynamic previews are a future, optional Pages Function/Worker. It would return
crawler HTML only after a server-side lookup for a published slug, use a
publicly scoped anon key or safe read-only endpoint, avoid secrets, return a
generic unavailable response for drafts/missing pages, and avoid caching
private or stale publication data. Functions use Workers runtime quotas; check
the current plan/pricing before adding them. Do not deploy this enhancement
without a separate review.

## Cloudflare Free plan considerations

Cloudflare's [Pages limits](https://developers.cloudflare.com/pages/platform/limits/)
currently document, among other limits, 500 Git builds per month, one
concurrent build, up to 20,000 files per Free site, a 25 MiB maximum per
individual asset, and up to 100 custom domains per project. Build-count limits
apply to Pages builds; Direct Upload builds locally and uploads static assets.
Limits and plan details can change, so confirm the linked official page before
relying on a specific quota. Pages Functions usage is governed by Workers
quotas.

## Troubleshooting

| Symptom | Check |
|---|---|
| Deep URL returns a Cloudflare 404 | Confirm `build/web` was deployed, no root `404.html` exists, and path strategy is active. |
| Blank page | Check browser console/network, `index.html` base href, bootstrap file, and current asset deployment. |
| Supabase configuration error | Recheck production JSON keys and release build arguments; never print the values. |
| CORS/Auth failure | Check Supabase Auth redirect allowlist and project API/auth configuration; do not bypass RLS. |
| Share URL points to the wrong host | Correct `PUBLIC_BASE_URL`, rebuild, and redeploy. |
| Missing fonts or images | Confirm asset paths/files exist in `build/web`; do not rewrite static asset routes. |
| Wrangler says unauthenticated | Run `wrangler login`, then `wrangler whoami` with the account that owns the Pages project. |
| Wrangler says project missing | Verify account, exact Pages project name, and selected upload mode; do not auto-create a second project. |
| Old UI remains after deploy | Check the deployment URL and browser cache; avoid custom cache rules until needed. |
| Social preview is generic | Expected for a client-rendered route; dynamic per-page metadata is not implemented. |

