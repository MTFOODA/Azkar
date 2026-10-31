# AZKAR | أذكار

AZKAR is a Flutter-based Islamic remembrance and memorial application for
Android, iOS, and Web. Users can create and share personalized memorial pages
containing published Quran verses, Azkar, Hadith, Duas, Tasbeeh, dedications,
videos, and other remembrance content.

## Main features

- Arabic-first, responsive UI with RTL layout and downloadable Arabic fonts.
- Supabase Auth for unified owner and platform-administrator sign-in,
  registration, and password recovery.
- A database-provisioned personal memorial page for each registered user.
- Owner dashboard settings for page title, unique slug, publication status,
  content, homepage layout, and appearance.
- Public `/m/:slug` pages that load without authentication and expose published
  content only, subject to Supabase Row Level Security (RLS).
- Public collections for Azkar, Quran, Hadith, Duas, dedications, and videos.
- Tasbeeh counters stored locally on the visitor's device/browser.
- Sharing and copy-link actions using the configured public site URL.

## Technology and supported platforms

- **UI:** Flutter and Dart.
- **Backend:** Supabase Auth, Postgres, and RLS.
- **Web hosting:** Cloudflare Workers Static Assets with Wrangler.
- **Platforms:** Android, iOS, and Web.

## Architecture

The Flutter client uses feature-oriented modules, Riverpod providers, and
GoRouter. Supabase owns authentication and shared content. Each tenant has one
memorial page, provisioned by the existing database trigger; content rows,
homepage cards, and appearance settings are scoped to that page. Database RLS
controls owner access and anonymous reads of published content. Public pages
use `/m/:slug`; changing the web path strategy does not add a second backend or
page-provisioning mechanism.

## Run locally

Create `config/dev.json` from `config/dev.example.json` and fill in the
development project's Supabase URL and publishable key. The credentials file
is ignored by Git. The Android and Edge launch configurations in VS Code load
it automatically and validate it before starting.

```powershell
flutter pub get
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_android_dev.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_web_dev.ps1
```

For F5, select **AZKAR — Android (Supabase Development)** or
**AZKAR — Web (Supabase Development)**. Plain `flutter run` does not inherit
VS Code launch arguments; pass `--dart-define-from-file=config/dev.json` or use
the scripts above. The Android script checks the configuration and connected
devices, then lets you select a device when more than one is available.

Demo Mode stores content locally and is not an authentication or production
security boundary. Missing Supabase configuration now shows a startup error
instead of silently selecting the demo backend. Demo Mode remains available
when explicitly requested with `--dart-define=AZKAR_DEMO_MODE=true`. A release
app requires Supabase configuration and refuses to start in Demo Mode.

## Supabase configuration

Flutter reads compile-time definitions; it does not load `.env` files.
`config/dev.json` supplies the project URL, **anon/publishable** key, and
development authentication flags. Never put a service-role key in the client
or in a checked-in file.

```powershell
flutter run -d edge --dart-define-from-file=config/dev.json
```

With either Supabase value missing, normal app launches show a configuration
error and do not initialize authentication or fall back to local demo data.
Admin writes must be protected by Supabase Auth and database RLS policies.

## Personal pages and tenant setup

The unified `/login` screen authenticates both regular users and platform
administrators through the same Supabase Auth project. Admin access is resolved
from an active `admin_profiles` row; signup metadata and editable user metadata
never grant administrator access. The `/admin/login` path redirects to `/login`
for compatibility. Registration uses `/register` and asks only for a display name,
email, password, and password confirmation. Supabase Auth metadata supplies the
display name and generated Arabic page title; the database trigger creates the
profile and exactly one unpublished memorial page with a unique UUID-derived
slug. Slug creation stays in the database, and owners can later edit the title
and slug in dashboard page settings.

The schema, provisioning trigger, and RLS enablement have been verified in the
configured Supabase project. Do not rerun the initial schema there. Runtime
registration and cross-owner RLS behavior still need acceptance testing with
approved test accounts. Signup is enabled in the local development config;
the flag is only an operational guard, not a security control. See
[`docs/MULTI_TENANT_SETUP.md`](docs/MULTI_TENANT_SETUP.md) for the schema and
RLS boundaries. To enable signup in another build, use
`--dart-define=AZKAR_AUTH_SCHEMA_VERIFIED=true` only after independently
verifying that project's schema and RLS.

## Web deployment status

The existing production Worker is `azkar-sadaqa` at
`https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev`. A check on 2026-10-31
found that its homepage returns the raw Flutter source template and a direct
`/m/...` request returns HTTP 404; the production site is **not accepted as
working**.

The production workflow is prepared at
`.github/workflows/deploy-worker.yml`. It pins Flutter 3.47.7 and Wrangler
4.156.0, runs analysis and tests, compiles Flutter Web into `build/web`, checks
the compiled output, and deploys the existing Worker with SPA fallback. Before
enabling it, disconnect the current Cloudflare Workers Build connection and
configure the protected GitHub `production` environment. No deployment has
been made from this workflow.

Production Supabase settings are injected at build time from GitHub environment
secrets; Cloudflare runtime variables do not configure Flutter's compiled
JavaScript. For local builds, `config/production.json` is ignored and can be
created from [`config/production.example.json`](config/production.example.json).
Never use a service-role key or Cloudflare token in Flutter.

## Brand assets

The AZKAR brand mark, vector wordmarks, platform icons, and regeneration
instructions are documented in [`BRANDING_GUIDE.md`](BRANDING_GUIDE.md).

## Quran assets

`assets/data/quran_uthmani.json` is the authoritative text asset. To rebuild the
surah index and the homepage Bismillah from that same source:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build_quran_index.ps1
```

The index is derived metadata; do not edit or regenerate the Quranic text.

## Checks and builds

```powershell
flutter analyze
flutter test
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_web_production.ps1
flutter build apk --debug --dart-define-from-file=config/dev.json
```

The production build script requires a real, local `config/production.json`
copied from `config/production.example.json`. It validates the production
settings without printing them, builds Flutter Web, and prepares generic social
metadata. The deployment script targets only the existing Worker, validates
the Wrangler dry run, creates a fresh validated build, and asks for an explicit
production confirmation. Run it separately only as a manual fallback; the
GitHub Actions workflow is the selected automated path, so do not use both
deployment paths for the same change.

See the
[complete AZKAR project documentation](docs/AZKAR_COMPLETE_PROJECT_DOCUMENTATION.md),
[beginner Cloudflare guide in Egyptian Arabic](docs/CLOUDFLARE_SETUP_GUIDE_AR.md),
[technical deployment guide](docs/CLOUDFLARE_DEPLOYMENT.md), and
[deployment checklist](docs/DEPLOYMENT_CHECKLIST.md),
[manual actions in Egyptian Arabic](docs/PRODUCTION_MANUAL_ACTIONS_AR.md), and
[current production acceptance report](docs/PRODUCTION_ACCEPTANCE_REPORT.md).
The existing
[multi-tenant setup notes](docs/MULTI_TENANT_SETUP.md) describe the Supabase
schema and RLS verification boundaries.

## Project status

The Flutter application, Supabase integration, memorial-page workflows, tests,
and Workers deployment preparation are present. The Worker exists, but its
current deployed assets fail direct-route acceptance. A production build with
approved Supabase configuration, live RLS acceptance, GitHub/Cloudflare
configuration, and the first corrected deployment remain pending.

## Security

Local development and production configuration files, environment files,
signing credentials, Wrangler state, logs, build output, and local caches are
excluded by `.gitignore`. Only safe configuration templates belong in Git.
Supabase publishable keys are intended for browser/mobile clients, but must
be paired with correctly verified RLS. Never commit a service-role key,
database password, access token, or private signing key.
