# AZKAR Production Acceptance Report

**Original assessment date:** 2026-10-31
**Release decision:** **NOT READY**

The findings below were recorded at the original assessment date. The
2026-11-03 reconciliation at the end of this report is the current status
where it supersedes those point-in-time observations.

## Deployment information

| Item | Observed value |
|---|---|
| Repository | `MTFOODA/Azkar` |
| Branch | `main` |
| GitHub `main` at latest verification | `87fb90c558c8549682860f45a083c3bfb1bfcd08` |
| Preparation revision | PR #1 merged to `main`; production deployment remains pending |
| Worker | `azkar-sadaqa` |
| Production URL | `https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev` |
| Production deployment commit/build/version ID | No deployment performed; current Worker version ID unavailable |
| Production deployment date | No deployment performed by the 2026-11-03 reconciliation |
| GitHub Actions run | [Run 41532968742](https://github.com/MTFOODA/Azkar/actions/runs/41532968742); Analyze and test passed; production job is waiting for protected-environment approval |
| Flutter / Dart | Flutter 3.47.7 / Dart 3.13.5 |
| Wrangler | 4.156.0 (pinned; dry-run and local preview executed) |

No Cloudflare deployment was performed during the original assessment. The
GitHub Actions workflow is now merged to `main`; its production job remains
waiting for protected-environment approval.

## Build verification

| Check | Result | Evidence |
|---|---|---|
| `flutter analyze` | **PASS** | No issues found after the changes. |
| `flutter test` | **PASS** | 269 tests passed on merged `main` during the 2026-11-03 reconciliation; the earlier 77-test count was from the original assessment. |
| Flutter Web production build with real production config | **BLOCKED** | `config/production.json` is absent and the production verification variable is unverified. The current Actions deploy job is waiting for protected-environment approval; no production build ran. |
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
| Production homepage | **PARTIAL — rechecked 2026-11-03** | Read-only GET returned HTTP 200 and HTML containing the Flutter bootstrap; the source-base placeholder was absent. Browser rendering and application runtime were not verified, so the original browser failure is historical rather than current evidence. |
| Production `/m/:slug` direct access | **NOT VERIFIED** | The earlier `/m/azkar-production-check` request returned 404. A 2026-11-03 request for a deliberately nonexistent route returned HTTP 200, which confirms only an HTTP fallback and does not verify a real memorial page. |
| Local route fallback | **PASS — local only** | Wrangler local preview returned the Flutter index for SPA navigation paths. This does not certify production. |
| Registration form | **PASS — widget test and live flow** | Automated UI test verifies the four fields: name, email, password, and confirmation. The temporary account was also registered through the normal local UI and verified by the user. |
| Login and password recovery | **PARTIAL — historical local test** | The secondary dashboard was rendered locally in the prior test session. No authenticated session is currently available; primary identity was not verified there. Password recovery was not tested. |
| Dashboard and page settings | **PARTIAL** | Widget tests cover routing/title/slug settings; the user confirmed the primary dashboard and existing page loaded locally. |
| Primary account dashboard | **NOT VERIFIED** | The prior session was user-confirmed, but no isolated primary session or active local app is available for this reconciliation. No primary data was modified. |
| Temporary account registration | **PASS — user-confirmed** | The account was registered through the normal local UI, email verification was completed by the user, and the signup gate was restored to false. No credentials are included in this report. |
| Temporary account login | **PARTIAL — historical local dashboard** | The secondary private, unpublished page rendered with zero content counts. The app checks returned page ownership, but the active email identity was not independently inspected; no current session is available. |
| Automatic memorial-page provisioning | **PARTIAL — historical authenticated app read** | The secondary dashboard loaded one owner-filtered page through `fetchMine()` and `maybeSingle()`. This did not verify the primary page or current production state. No page or content was modified. |
| Profile-row provisioning | **PARTIAL** | The signup trigger in the checked-in migration inserts a profile and page atomically, and registration plus page loading succeeded. The live profile row itself was not independently queried through an authenticated client. |
| Anonymous published memorial read | **PASS — read-only live query** | The publishable-key anonymous request returned HTTP 200 and one published-row result, selecting only `is_published`. No row contents were inspected. |
| Anonymous unpublished memorial isolation | **PASS — known unpublished fixture** | The authenticated temporary dashboard showed its private, unpublished page. A separate request using only the publishable key and no Authorization header returned zero unpublished memorial rows (HTTP 200). |
| Anonymous unpublished-content isolation | **PARTIAL** | Anonymous queries for unpublished rows in all seven content tables returned zero rows (HTTP 200). No specific unpublished content row was independently confirmed in the authenticated app, so the complete content-fixture check remains open. |
| Anonymous writes | **NOT RUN** | No potentially mutating probe was sent. |
| Cross-tenant reads and writes | **BLOCKED** | No authenticated cross-tenant read or write probe was performed. Two isolated authenticated sessions and safe test fixtures are still required; no active local session is available. Do not probe existing private records. |
| Share URL and slug encoding | **PASS — local runtime and config tests** | The signed-in dashboard displayed the required Worker origin; focused tests passed with the dev config and an explicit production-origin define. Production link opening is not verified. |
| Dashboard provider-scope regression | **PASS — deterministic regression test** | Before the fix, nested owner dashboard content resolved the root repository instead of the page-scoped override. The regression test now verifies the scoped repository is used. |
| Account-switch page cache regression | **PASS — deterministic regression test** | Before the fix, the current memorial page could remain cached across account changes. The provider now depends on the authenticated user ID, and the regression test verifies reload on identity change and sign-out. |
| Unexpected page-owner response | **PASS — deterministic regression test** | The current page provider rejects a page whose owner ID differs from the authenticated user ID; the regression test verifies fail-closed behavior. |
| Browser refresh/back/forward in production | **NOT RUN** | No real memorial slug was available; the 2026-11-03 generic route response does not test rendered route behavior. |
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
| Live User A/User B tenant isolation | **BLOCKED** — independently verified primary and secondary sessions and cross-tenant probes are still required; no active session is available |
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
| GitHub workflow | **VALIDATION PASS; DEPLOY PENDING** | Run 41532968742 passed Analyze and test on merged `main`; its production job is waiting for the protected environment. GitHub environment settings and secret/variable presence were not independently inspectable. |
| Existing Cloudflare Workers Build connection | **REPORTED DISABLED** | User reports it is disconnected/disabled; dashboard state was not independently inspected. |
| Production API token / secrets | **REPORTED CONFIGURED — UNVERIFIED** | User reports required environment secrets exist; the available tools could not inspect secret or variable presence/values. |
| Production deployment and application smoke test | **NOT RUN / BLOCKED** | Live authenticated Supabase acceptance checks remain undocumented; no production deployment was triggered. The current Worker has HTTP 200 responses for the homepage, generic navigation paths, and Flutter bootstrap, but no browser-rendered app check was completed. |

## Outstanding blockers

1. Provide sanitized, independently reviewable evidence for successful
   authentication in dedicated test accounts A and B and owner-scoped reads
   for each account. Do not share credentials, tokens, or private user data.
2. Complete read-only cross-account isolation checks and safe authorization
   denials using dedicated fixtures; do not mutate existing production
   records.
3. Verify live provisioning/profile behavior, administrator authorization,
   Supabase Site URL, and `/dashboard` plus `/reset-password` redirect
   allowlist entries.
4. Perform an approved read-only check of live schema objects, RLS policies,
   grants, and RPC permissions. Do not rerun or apply migrations.
5. After acceptance evidence is substantiated, update the production
   verification variable through repository settings and have an authorized
   owner approve the protected GitHub deployment environment. User deployment
   authorization does not bypass this gate.
6. After deployment, verify a real public memorial route and app rendering,
   then check authentication, sharing, responsive UI, and device behavior.

## Release decision: NOT READY

Current checks confirm the Worker responds with HTTP 200 and serves a Flutter
bootstrap, but do not establish that the current app renders correctly. PR #1
is merged at `87fb90c558c8549682860f45a083c3bfb1bfcd08`; GitHub Actions run
41532968742 passed analysis and tests, while production deployment is still
waiting for environment approval. The earlier 77-test count and main SHA are
superseded by the merged-main results. The 2026-11-02 anonymous memorial
count of four supersedes the older count of three; neither verifies owner
access to all four pages.

No authenticated production test results were found in this report, the
2026-11-02 production integration report, available local test output, or
GitHub Actions. The user reports that the tests passed, but there is no
sanitized test artifact or log to substantiate that claim. The exact missing
checks are: (1) isolated sign-in and identity confirmation for dedicated
accounts A and B; (2) authenticated owner-scoped profile, memorial, reminder
preference and configuration reads; (3) read-only cross-account denial checks;
(4) safe cross-owner operation/RPC denial checks using dedicated fixtures;
(5) live provisioning/profile and administrator authorization checks;
(6) verification of production auth redirect allowlists; and (7) live
read-only schema, RLS, grants and RPC permission checks. These could not be
run because no authenticated test session or credentials were available, and
the shared local browser is disconnected. No credentials were requested in
chat, and no production write was attempted.

The local production config is absent, GitHub production secret and variable
values were not inspectable with the available tools, and
`AZKAR_AUTH_SCHEMA_VERIFIED` remains false locally and unverified in
production. No production SQL, data change, or deployment was performed.
Therefore production readiness remains **NOT READY**.

## Latest reconciliation — 2026-11-03

- The original `main` SHA, unmerged preparation status, 77-test count,
  three-row anonymous memorial count, and homepage failure are historical
  snapshots. Current evidence is the merged-main SHA/CI result above, a 269-test
  local run, the four-row anonymous count documented on 2026-11-02, and
  2026-11-03 HTTP 200 checks. These updates do not prove authentication or
  successful browser rendering.
- The shared `127.0.0.1:8770` page is disconnected
  (`ERR_CONNECTION_REFUSED`) and has no rendered app snapshot.
- Static inspection of the merged migration source shows owner-scoped RLS
  policies, restricted reminder table grants, and a save RPC that compares
  the requested user to `auth.uid()`. This is not proof of the live database
  state.
- No production query requiring authentication or any production write was
  attempted during reconciliation. Required migrations were not rerun.
