# AZKAR Web Deployment Final Report

## Status

**BLOCKED — the safe gated deployment has not been published.** The earlier
GitHub Actions run `41532968742` did complete a Cloudflare deployment, but its
logs explicitly show `AZKAR_AUTH_SCHEMA_VERIFIED=true`. That deployment did not
keep registration gated and must not be treated as the safe release requested
here. The gated workflow/script correction in this report is still local until
merged and deployed.

## Source and deployment target

- Source base: `87fb90c558c8549682860f45a083c3bfb1bfcd08`
- Existing Worker: `azkar-sadaqa`
- Existing public URL: <https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev>
- Run `41532968742` deployed from that main commit at 2026-11-02 23:03 UTC.
  GitHub reports both validation and deployment jobs succeeded. The deploy job
  log confirms the build configuration received
  `AZKAR_AUTH_SCHEMA_VERIFIED: true`; therefore registration was not gated by
  that build.

Run `41532968742` is now completed, not awaiting approval. Do not retry or reuse
that run's artifacts. A new run from the gated workflow is required.

## Changes prepared locally

- `supabase/production_verification/07_ACCOUNT_PROVISIONING_TRIGGER_CHECK.sql`
  checks the expected trigger, function, security metadata, destination columns,
  and constraints without writing data. It explicitly reports real signup as
  `NOT_VERIFIED`.
- `supabase/production_verification/README.md` documents the check and its
  limitations in Arabic.
- `scripts/write_production_config.ps1` and
  `scripts/build_web_production.ps1` accept an explicit `false` verification
  value and reject a Supabase URL that does not target
  `akublcdzlmwyyelwtzrb.supabase.co`.
- `.github/workflows/deploy-worker.yml` pins
  `AZKAR_AUTH_SCHEMA_VERIFIED` to `false` for deployment, keeping registration
  gated until a later verified change.

These changes preserve authentication and existing RLS controls. They do not
grant anonymous access to private records.

## Local validation

| Check | Result |
|---|---|
| PowerShell syntax parsing for the config/build scripts | PASS |
| Approved Supabase project URL guard; incorrect host rejected | PASS |
| `flutter analyze` | PASS — no issues found |
| `flutter test test/account_isolation_regression_test.dart` | PASS — 5 tests |
| `flutter build web --release --base-href / --dart-define-from-file=config/production.json` | PASS |
| Local Flutter Web homepage | PASS — Arabic homepage rendered; no browser console/runtime errors observed |
| Mobile viewport smoke check | PASS — 390 px viewport, no horizontal overflow |
| Compiled bundle credential scan | PASS — no service-role JWT or modern secret-key value found |
| `git diff --check` | PASS |
| Final invocation of the PowerShell config/build wrappers | Not run — this host's execution policy is `Restricted`; scripts parsed successfully, the URL-validation predicate was checked, and the Flutter build was run directly |
| Full `flutter test` suite | Not run; no Dart implementation changed and the full suite was not repeated |

The generated `config/production.json` was checked without displaying its
values: it targeted the approved project, used a publishable key, disabled demo
mode, and set registration verification to `false`. The generated config and
disposable local PostgreSQL test files were removed after validation. The web
build remains in ignored `build/web` for local inspection.

The successful deployment job indicates the Supabase and Cloudflare credentials
were available to that run; their values were not inspected or exposed. The
new workflow continues to use the same GitHub secret names, and the new
protected-environment configuration should be confirmed by the workflow itself.

## Supabase status

- The owner-supplied checks 01–03 reported required schema objects, RLS policy
  metadata, and permissions as passing; the migration ledger remained
  `NOT_VERIFIED`. Those results were not repeated.
- The new trigger script was run only against a disposable local PostgreSQL
  instance populated from the project migrations. Trigger existence, enabled
  state, function binding, expected source markers, function security settings,
  destination columns, and constraints all passed locally. The script's real
  signup check correctly returned `NOT_VERIFIED`.
- Script 07 has **not** been run against Production, so Production trigger
  metadata is `NOT_VERIFIED` here. Catalog inspection alone cannot prove that a
  real Supabase Auth signup successfully provisions an account.
- Anonymous read-only REST checks against the configured project returned
  HTTP 200 with a published sample for memorial pages and tasbeeh cards.
  Published samples were empty for azkar, Quran verses, hadith, duas, YouTube
  videos, and dedications during this check; successful empty responses do not
  establish that those content categories currently have published data.
- An anonymous query for unpublished memorial pages returned zero rows.
  Reminder preference and configuration table reads returned HTTP 401.
  These checks did not exercise authenticated ownership or every private table.

## Website and deployment smoke tests

The existing Worker returned HTTP 200 for `/`, `/about-developer`, and `/azkar`
after run `41532968742`; these responses do not independently prove the
registration gate or private-data isolation. The local gated release build
rendered the Arabic homepage without observed browser errors. A deployment of
that gated build and its post-deployment smoke tests remain pending.

## Authentication and security

- Registration is gated in the locally prepared production build because
  `AZKAR_AUTH_SCHEMA_VERIFIED=false`.
- The existing deployment run used `AZKAR_AUTH_SCHEMA_VERIFIED=true`; no real
  signup or authenticated runtime verification was documented here. Treat
  production registration readiness as unverified until separately tested.
- No real signup, login, OAuth redirect, authenticated ownership test, or
  cross-user isolation test was performed against Production in this task.
- Anonymous private-table checks were read-only and did not reveal row contents.
- No production SQL, production data changes, or destructive operations were
  performed.

## Required next steps

1. Do not approve or reuse the completed run `41532968742`.
2. Merge the reviewed gated-deployment changes through normal repository
   protection. The workflow must pass validation and build with
   `AZKAR_AUTH_SCHEMA_VERIFIED=false`.
3. Approve only the new protected Production deployment run after verifying its
   commit and configuration.
4. After the gated build deploys, verify the live Flutter app and public
   content, then confirm anonymous private-data denial. Do not claim safe
   deployment success before those checks complete.
