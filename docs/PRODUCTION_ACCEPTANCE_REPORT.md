# AZKAR Production Acceptance Report

**Assessment date:** 2026-10-31
**Release decision:** **NOT READY**

## Deployment information

| Item | Observed value |
|---|---|
| Repository | `MTFOODA/Azkar` |
| Branch | `main` |
| GitHub `main` at inspection | `bf1f5529f17d9749bcabea13f31c54729b9293f6` |
| Preparation revision | Pushed to `main`; validation passed, not deployed |
| Worker | `azkar-sadaqa` |
| Production URL | `https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev` |
| Production deployment commit/build/version ID | No deployment performed; current Worker version ID unavailable |
| Production deployment date | Unknown; endpoint rechecked on 2026-10-31 |
| GitHub Actions run | [Run 41204873609](https://github.com/MTFOODA/Azkar/actions/runs/41204873609); validation succeeded and deployment was skipped by the schema gate |
| Flutter / Dart | Flutter 3.47.7 / Dart 3.13.5 |
| Wrangler | 4.156.0 (pinned; dry-run and local preview executed) |

No Cloudflare deployment was performed during this assessment. The GitHub
Actions deployment workflow is prepared locally and requires dashboard
configuration, production secrets, and explicit production approval.

## Build verification

| Check | Result | Evidence |
|---|---|---|
| `flutter analyze` | **PASS** | No issues found after the changes. |
| `flutter test` | **PASS** | 77 tests passed, including three regressions for owner-provider scoping, account-switch page refresh, and fail-closed owner validation. |
| Flutter Web production build with real production config | **BLOCKED** | `config/production.json` is absent; the deploy job was skipped because the schema-verification gate is not enabled. |
| Existing local Flutter Web artifact | **PASS — local artifact only** | `build/web` has compiled `main.dart.js`, Flutter bootstrap, manifest, icon, asset manifest, and Arabic fonts. It is not certified as a production build. |
| Local Flutter Web application | **PARTIAL — debug runtime** | Fresh instances served on `http://localhost:8875` and `http://localhost:8876`. The secondary private draft rendered on `8876`; `8875` also rendered that draft, so a separate primary-account session is not verified. |
| Share URL origin | **PASS — local runtime and config tests** | The rendered dashboard showed the configured Worker origin. Focused tests passed with the dev config (default origin) and an explicit production-origin define. |
| Hot reload / hot restart | **PARTIAL** | Hot reload succeeded on both instances. Hot restart failed through the web-server proxy with a JSON/HTML parse error; both instances were subsequently restarted cleanly. |
| Wrangler config dry run | **PASS** | Wrangler 4.156.0 read 102 assets from `build/web`; dry-run exited without upload. |
| Local Workers SPA preview | **PASS — static routing only** | `/`, `/login`, `/register`, `/reset-password`, and `/m/azkar-preview-check` returned HTTP 200 for navigation requests; `flutter_bootstrap.js` and `main.dart.js` were served. |
| Android regression build | **NOT RUN** | The provider/isolation changes were not followed by a new Android build; the prior debug APK result does not validate this revision. |
| Cloudflare production build/deploy | **NOT RUN** | Explicit production approval and dashboard/GitHub setup are pending. |

## Dashboard isolation regression

The reproduced defect is application-side dashboard isolation, not evidence of
a live RLS bypass. The owner dashboard overrides the content repository in a
nested Riverpod scope, but providers consuming that override did not declare
their scope dependencies. As a result, nested dashboard consumers could resolve
the root repository and display content from another page; published rows may
also be readable under the intended public-content policy. Separately, the
current memorial-page provider was not keyed to the authenticated user ID, so
an account switch could retain the previous page.

The fix declares the relevant provider-scope dependencies, binds the current
page load to the signed-in user ID, rejects a returned page with a different
owner, and keys the owner dashboard scope by page ID. Regression tests first
reproduced the root-repository selection and stale-page behavior, then passed
after the fix. Changes are in `../lib/core/providers/app_providers.dart`,
`../lib/features/admin/content_management/providers/admin_providers.dart`,
`../lib/features/content/providers/content_providers.dart`,
`../lib/features/account/presentation/owner_dashboard_pages.dart`, and
`../test/owner_dashboard_isolation_test.dart`. No database policy, trigger,
schema, or primary-account data was changed. Live authenticated RLS behavior
remains unverified.

## Functional acceptance matrix

| Area | Result | Evidence / limitation |
|---|---|---|
| Production homepage | **FAIL** | Live browser opened the URL but showed no rendered app; its console reported a 404 resource. A fresh response contains the Flutter source template and `$FLUTTER_BASE_HREF`, not the compiled application. |
| Production `/m/:slug` direct access | **FAIL** | `/m/azkar-production-check` returned HTTP 404. This was a route check only; no real published slug was available. |
| Local route fallback | **PASS — local only** | Wrangler local preview returned the Flutter index for SPA navigation paths. This does not certify production. |
| Registration form | **PASS — widget test and live flow** | Automated UI test verifies the four fields: name, email, password, and confirmation. The temporary account was also registered through the normal local UI and verified by the user. |
| Login and password recovery | **PARTIAL** | The secondary dashboard is rendered locally. The current `8875` tab also shows the secondary private draft, so primary identity is not verified in the isolated primary session. Password recovery was not tested. |
| Dashboard and page settings | **PARTIAL** | Widget tests cover routing/title/slug settings; the user confirmed the primary dashboard and existing page loaded locally. |
| Primary account dashboard | **BLOCKED — current isolated session not verified** | A prior session was user-confirmed, but the fresh `8875` tab currently shows the secondary private draft rather than the known primary published page. No primary data was modified. |
| Temporary account registration | **PASS — user-confirmed** | The account was registered through the normal local UI, email verification was completed by the user, and the signup gate was restored to false. No credentials are included in this report. |
| Temporary account login | **PARTIAL — local dashboard rendered** | The secondary private, unpublished page rendered with zero content counts. The current user ID is checked against the returned page owner before the page provider succeeds; the active email identity was not independently inspected. |
| Automatic memorial-page provisioning | **PARTIAL — authenticated app read** | The secondary dashboard loaded one owner-filtered page through `fetchMine()` and `maybeSingle()`. The primary page was not verified in the fresh isolated session. No page or content was modified. |
| Profile-row provisioning | **PARTIAL** | The signup trigger in the checked-in migration inserts a profile and page atomically, and registration plus page loading succeeded. The live profile row itself was not independently queried through an authenticated client. |
| Anonymous published memorial read | **PASS — read-only live query** | The publishable-key anonymous request returned HTTP 200 and one published-row result, selecting only `is_published`. No row contents were inspected. |
| Anonymous unpublished memorial isolation | **PASS — known unpublished fixture** | The authenticated temporary dashboard showed its private, unpublished page. A separate request using only the publishable key and no Authorization header returned zero unpublished memorial rows (HTTP 200). |
| Anonymous unpublished-content isolation | **PARTIAL** | Anonymous queries for unpublished rows in all seven content tables returned zero rows (HTTP 200). No specific unpublished content row was independently confirmed in the authenticated app, so the complete content-fixture check remains open. |
| Anonymous writes | **NOT RUN** | No potentially mutating probe was sent. |
| Cross-tenant reads and writes | **BLOCKED** | No authenticated cross-tenant read or write probe was performed. The current `8875` tab shows the secondary draft, so a separate primary session is still needed. The primary page is published and is not a suitable private-content fixture. |
| Share URL and slug encoding | **PASS — local runtime and config tests** | The signed-in dashboard displayed the required Worker origin; focused tests passed with the dev config and an explicit production-origin define. Production link opening is not verified. |
| Dashboard provider-scope regression | **PASS — deterministic regression test** | Before the fix, nested owner dashboard content resolved the root repository instead of the page-scoped override. The regression test now verifies the scoped repository is used. |
| Account-switch page cache regression | **PASS — deterministic regression test** | Before the fix, the current memorial page could remain cached across account changes. The provider now depends on the authenticated user ID, and the regression test verifies reload on identity change and sign-out. |
| Unexpected page-owner response | **PASS — deterministic regression test** | The current page provider rejects a page whose owner ID differs from the authenticated user ID; the regression test verifies fail-closed behavior. |
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
| Live User A/User B tenant isolation | **BLOCKED** — the current primary-origin tab shows the secondary private draft; independently verified primary and secondary sessions and cross-tenant probes are still required |
| Anonymous published reads | **PASS — read-only query** | An anonymous request returned one row marked published. |
| Anonymous unpublished-page isolation | **PASS — known fixture** | The temporary account's dashboard showed an unpublished page; anonymous table queries returned zero unpublished pages. |
| Anonymous unpublished-content isolation | **PARTIAL** — all seven unpublished-content queries returned zero rows, but no specific unpublished content fixture was confirmed |
| Anonymous writes | **NOT RUN** — no potentially mutating probe was sent |
| Ownership/admin-privilege mutation protection | **NOT RUN** — no write probes were sent; live cross-tenant write denial is unverified |
| Live administrator authorization | **BLOCKED** — not tested against live Supabase |
| Production auth redirect allowlist | **BLOCKED** — Supabase dashboard was not accessed |
| Database schema or RLS migration execution | **NOT RUN** — no SQL was executed or changed |

## Cloudflare and GitHub

| Check | Result | Evidence / limitation |
|---|---|---|
| Existing Worker retained | **PASS — configuration target** | `wrangler.jsonc` names `azkar-sadaqa` and preserves `workers.dev`. |
| Static asset source | **PASS — local dry run** | Wrangler reads `./build/web`; it does not point at source `web/`. |
| Deep-link fallback configuration | **PASS — local preview** | Workers Static Assets uses `single-page-application`; local navigation paths returned the index. |
| GitHub workflow | **PASS — validation only** | Run 41204873609 succeeded for analyze/tests; the deploy job was skipped by the `AZKAR_AUTH_SCHEMA_VERIFIED` gate. User reports the production environment and required reviewer are configured; these settings were not independently inspected. |
| Existing Cloudflare Workers Build connection | **REPORTED DISABLED** | User reports it is disconnected/disabled; dashboard state was not independently inspected. |
| Production API token / secrets | **REPORTED CONFIGURED** | User reports required environment secrets exist; secret values were not accessed. |
| Production deployment and smoke test | **NOT RUN / BLOCKED** | Live Supabase and account acceptance checks are incomplete; no production deployment was triggered. |

## Outstanding blockers

1. Establish and verify the primary session on the isolated `localhost:8875`
   origin; it currently renders the secondary private draft. Keep
   `localhost:8876` unchanged while doing so.
2. Complete authenticated cross-tenant read-isolation checks and safe
   write-denial checks using the normal app sessions. Do not probe writes
   against primary-owned records or extract session tokens.
3. Independently query the temporary user's profile row through the normal
   authenticated client, and confirm a specific unpublished content fixture
   before claiming content-level anonymous isolation.
4. Configure/verify Supabase production Site URL and the `/dashboard` and
   `/reset-password` redirect allowlist entries, preserving development URLs.
5. Verify live administrator authorization and the anon/authenticated write
   privilege boundaries before setting `AZKAR_AUTH_SCHEMA_VERIFIED=true`.
6. After the acceptance tests pass, explain the gate change and obtain explicit
   approval before enabling it or triggering deployment.
7. After deployment, verify the compiled application, direct public memorial
   links, browser behavior, authentication, sharing, responsive UI, and device
   behavior.

## Release decision: NOT READY

The production hostname is reachable, but its homepage serves the uncompiled
Flutter source template and its memorial route returns 404. GitHub validation
passed, but deployment was correctly skipped. Local regression tests reproduced
and fixed the dashboard provider-scope leak and stale page cache; `flutter
analyze` passed and 77 tests passed. The secondary private draft renders on the
local app, but the fresh primary-origin tab also shows that draft, so the
primary session is not verified. Anonymous queries found one published page
and no unpublished pages despite the known private fixture. Live cross-tenant
authorization, profile-row access, authenticated write-denial, and live
administrator checks remain incomplete. The local and production
`AZKAR_AUTH_SCHEMA_VERIFIED` gates remain false; no push or deployment was
performed. Therefore neither public launch nor limited beta is supported by
verified evidence.
