# AZKAR Production Acceptance Report

**Assessment date:** 2026-10-31
**Release decision:** **NOT READY**

## Deployment information

| Item | Observed value |
|---|---|
| Repository | `MTFOODA/Azkar` |
| Branch | `main` |
| GitHub `main` at inspection | `ecf668941752530fb4fc430c7692ae5a8129e9dd` |
| Preparation revision | Local commit; not pushed or deployed |
| Worker | `azkar-sadaqa` |
| Production URL | `https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev` |
| Production deployment commit/build/version ID | Not available from the accessible evidence |
| Production deployment date | Unknown; endpoint was checked on 2026-10-31 |
| Flutter / Dart | Flutter 3.47.7 / Dart 3.13.5 |
| Wrangler | 4.156.0 (pinned; dry-run and local preview executed) |

No Cloudflare deployment was performed during this assessment. The GitHub
Actions deployment workflow is prepared locally and requires dashboard
configuration, production secrets, and explicit production approval.

## Build verification

| Check | Result | Evidence |
|---|---|---|
| `flutter analyze` | **PASS** | No issues found after the changes. |
| `flutter test` | **PASS** | 74 tests passed, including registration, route, memorial privacy, settings, and share-link tests. |
| Flutter Web production build with real production config | **BLOCKED** | `config/production.json` is absent; the script and workflow correctly fail closed without approved production values. |
| Existing local Flutter Web artifact | **PASS — local artifact only** | `build/web` has compiled `main.dart.js`, Flutter bootstrap, manifest, icon, asset manifest, and Arabic fonts. It is not certified as a production build. |
| Wrangler config dry run | **PASS** | Wrangler 4.156.0 read 102 assets from `build/web`; dry-run exited without upload. |
| Local Workers SPA preview | **PASS — static routing only** | `/`, `/login`, `/register`, `/reset-password`, and `/m/azkar-preview-check` returned HTTP 200 for navigation requests; `flutter_bootstrap.js` and `main.dart.js` were served. |
| Android regression build | **NOT RUN** | No app implementation changed; the prior checkpoint recorded a successful debug APK build. |
| Cloudflare production build/deploy | **NOT RUN** | Explicit production approval and dashboard/GitHub setup are pending. |

## Functional acceptance matrix

| Area | Result | Evidence / limitation |
|---|---|---|
| Production homepage | **FAIL** | HTTP 200 currently returns the Flutter source template, including `$FLUTTER_BASE_HREF`, rather than the compiled application. |
| Production `/m/:slug` direct access | **FAIL** | `/m/azkar-production-check` returned HTTP 404. |
| Local route fallback | **PASS — local only** | Wrangler local preview returned the Flutter index for SPA navigation paths. This does not certify production. |
| Registration form | **PASS — widget test** | Automated UI test verifies the four fields: name, email, password, and confirmation. No live registration was attempted. |
| Login and password recovery | **PASS — unit/widget coverage; live flow BLOCKED** | Existing tests cover UI/routing; live Supabase account use needs approval and correct redirect configuration. |
| Dashboard and page settings | **PASS — widget coverage** | Existing tests cover dashboard routing and title/slug settings. No live account was used. |
| Automatic memorial provisioning | **NOT RUN live** | The existing database trigger is present in the checked-in migration; no database was modified or exercised. |
| Public published/unpublished memorial behavior | **PASS — local tests; live BLOCKED** | Repository tests cover published filtering; real anonymous access requires a live Supabase acceptance test. |
| Share URL and slug encoding | **PASS — unit test** | Public-origin route and encoded path-segment tests passed. Production link opening is not verified. |
| Browser refresh/back/forward in production | **FAIL / NOT RUN** | A direct production memorial request returns 404; browser execution and console inspection were not performed. |
| Responsive desktop/tablet/mobile and RTL | **NOT RUN** | No browser/device visual acceptance was performed in this task. |
| Copy Link/native sharing on devices | **NOT RUN** | No physical-device test was run. |

## Security and Supabase

The migration statically defines RLS for the application tables, owner-scoped
writes, published-page/content read conditions, active database-backed
administrator checks, and the single `azkar_provision_owner_page` trigger.
This is **code inspection, not proof of the live Supabase project's state or
behavior**.

| Security check | Result |
|---|---|
| No service-role key used in the Flutter deployment configuration | **PASS — workflow design**; actual production configuration is not available locally |
| Demo Mode disabled in the production config writer | **PASS — code inspection** |
| Live User A/User B tenant isolation | **BLOCKED** — requires an isolated test project or explicit account/data approval |
| Anonymous published-only reads and no writes | **BLOCKED** — not tested against live Supabase |
| Live administrator authorization | **BLOCKED** — not tested against live Supabase |
| Production auth redirect allowlist | **BLOCKED** — Supabase dashboard was not accessed |
| Database schema or RLS migration execution | **NOT RUN** — no SQL was executed or changed |

## Cloudflare and GitHub

| Check | Result | Evidence / limitation |
|---|---|---|
| Existing Worker retained | **PASS — configuration target** | `wrangler.jsonc` names `azkar-sadaqa` and preserves `workers.dev`. |
| Static asset source | **PASS — local dry run** | Wrangler reads `./build/web`; it does not point at source `web/`. |
| Deep-link fallback configuration | **PASS — local preview** | Workers Static Assets uses `single-page-application`; local navigation paths returned the index. |
| GitHub workflow | **PREPARED, NOT RUN** | Main-only workflow pins Flutter/Wrangler, requires tests, and uses the `production` environment. Its deploy job is skipped until `AZKAR_AUTH_SCHEMA_VERIFIED=true`; GitHub environment protection/secrets are not configured here. |
| Existing Cloudflare Workers Build connection | **BLOCKED — manual change** | Must be disconnected/disabled before activating Actions to prevent a duplicate and incorrect deployment. |
| Production API token / secrets | **NOT CONFIGURED** | No credentials were requested or added. |
| Production deployment and smoke test | **NOT RUN** | Must wait for explicit approval. |

## Outstanding blockers

1. Disconnect or disable the existing Cloudflare Workers Build connection while
   preserving the Worker.
2. Configure the GitHub `production` environment, required reviewer, and
   required environment secrets.
3. Configure Supabase production Site URL and the `/dashboard` and
   `/reset-password` redirect allowlist entries, preserving development URLs.
4. Obtain approval for an isolated/live test setup and verify provisioning,
   owner isolation, anonymous access, and administrator checks before setting
   `AZKAR_AUTH_SCHEMA_VERIFIED=true`.
5. Explicitly approve pushing the prepared changes to production-connected
   `main` and approve the GitHub deployment gate.
6. After deployment, verify the compiled application, direct public memorial
   links, browser behavior, authentication, sharing, responsive UI, and device
   behavior.

## Release decision: NOT READY

The production hostname is reachable, but its homepage is the uncompiled
Flutter source template and its memorial route returns 404. A valid production
build cannot run without the approved local/GitHub production configuration,
and live Supabase isolation/authentication have not been tested. Therefore
neither public launch nor limited beta is supported by verified evidence.
