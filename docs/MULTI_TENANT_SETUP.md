# AZKAR multi-tenant Supabase setup

## Current project status

The configured Supabase project has already been initialized. The required 13
public tables, RLS enablement, and `azkar_provision_owner_page` AFTER INSERT
trigger on `auth.users` were verified on 2026-10-30. Do not run the initial
schema SQL against this project. Those structural checks do not prove live
signup, ownership, or cross-tenant RLS behavior; acceptance testing still
requires approved test accounts.

## Initial schema for a new project

For a separate, newly created project only, the single initial schema is
[`20261030_multi_tenant_foundation.sql`](../supabase/migrations/20261030_multi_tenant_foundation.sql).
It is a fresh-install schema, not a migration or data-copy script. It refuses
to run if public base tables already exist.

1. Confirm this is the intended Supabase project and re-check that
   `information_schema.tables` contains no `public` base tables. Check Auth
   users separately: zero public tables does not prove that the Auth user
   store is empty.
2. Save an approved recovery plan. Do not copy or share service-role keys.
3. In Supabase Dashboard, open **SQL Editor**, create a new query, paste the
   complete SQL file, and run it as the project database administrator. Run
   the complete file once; its DDL is transaction-wrapped. Do not run parts
   independently and do not use it as an upgrade script.
4. Review the post-deployment verification queries at the end of the SQL file.
   Then perform the two-owner and anonymous RLS tests below before opening
   registration to production users.
5. In **Authentication → URL Configuration**, configure the production site
   URL and allow the `/dashboard`, `/login`, and `/reset-password` redirects.
   Set the email-confirmation behavior and email templates intentionally.

The SQL creates `profiles` and one unpublished `memorial_pages` row inside a
transactional `auth.users` insert trigger. A duplicate slug or invalid slug
rejects signup; the Auth insert, profile, and page roll back together. Slugs
are normalized, limited to 3–40 lowercase ASCII letters/digits/hyphens,
checked against reserved route names, and globally unique. A request without a
slug gets a stable `member-<user UUID>` slug. The app validates titles to 160
characters; the database independently enforces the limit.

The trigger handles **new** Auth users only. The empty public schema does not
establish whether Auth already contains users. Review that separately before
deployment; existing users are not silently backfilled. If any exist, decide
and test a separate, approved onboarding procedure before allowing those users
to use the owner dashboard.

## Flutter configuration and signup

For local development, create the ignored `config/dev.json` from
`config/dev.example.json` and supply the Supabase URL and anon/publishable key.
VS Code's Android and Edge launch configurations load it automatically. For
web release, also configure the canonical HTTPS public URL:

```powershell
flutter run -d chrome `
  --dart-define=SUPABASE_URL=https://akublcdzlmwyyelwtzrb.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-publishable-key `
  --dart-define=PUBLIC_BASE_URL=https://your-site.example
```

Never put a service-role key in Flutter, a browser, or a checked-in file.
`config/dev.json` is ignored by Git. Flutter does not load `.env` files.
Anonymous users receive table privileges for `SELECT` only; the narrowly
granted helper-function `EXECUTE` rights are used by RLS policies and do not
grant data writes. RLS limits reads to published pages and content. Owners can
manage only their own page and rows.
An active `admin_profiles` entry is a separate platform-admin grant, not
created by ordinary signup. Provision platform admins only through a trusted
administrative process after verifying their Auth user ID.

At `/register`, a user submits display name, email, password, and password
confirmation. The app supplies `display_name` and a generated Arabic
`page_title` in Auth metadata; it omits `page_slug`. The verified database
trigger creates the profile and exactly one private page, assigning the
stable, UUID-derived `member-<user UUID>` slug. The unique owner and slug
constraints prevent duplicate pages and slugs. With email confirmation
enabled, the user confirms first and then signs in. The owner can edit the
page title and slug in dashboard settings; the page becomes public only after
the owner sets `is_published`.

The app disables registration unless built with
`--dart-define=AZKAR_AUTH_SCHEMA_VERIFIED=true`. This local project's
development config enables that guard because its schema, trigger, and RLS
enablement were structurally verified. This compile-time guard is not a
security boundary; the database remains responsible for authorization.

## Schema and RLS verification

The SQL file includes catalog queries to inspect table RLS, policies, grants,
and security-definer search paths. Also run these acceptance scenarios using
two distinct test accounts and requests authenticated with the anon key or
each user's own session (never the service-role key):

1. Register Owner A and Owner B with different slugs. Confirm each has exactly
   one profile and one unpublished page, and the user/page IDs do not overlap.
2. Attempt a duplicate slug and invalid/reserved slugs. Confirm signup fails
   and leaves no Auth user, profile, or page from the failed attempt.
3. As Owner A, create a draft and published content row. A can read and edit
   both; Owner B cannot read or modify A's rows, and cannot insert a row using
   A's `page_id`.
4. Attempt to add a homepage card under A's page that references B's content.
   The database must reject it. A same-page reference should succeed.
5. Before page publication, anonymous requests cannot read the page or its
   content. After publication, anonymous visitors can read the page, published
   content, enabled/valid homepage cards, and its theme—but not drafts,
   unpublished pages, or disabled cards.
6. Anonymous `INSERT`, `UPDATE`, and `DELETE` attempts on every public table
   must fail with insufficient privilege. Authenticated cross-tenant writes
   must be denied by RLS.
7. An ordinary owner cannot manage global content or `admin_profiles`. An
   active platform admin may manage global content but is not made the owner
   of a tenant page.
8. Tasbeeh interactions must create no database records. Counter data remains
   local and page/card scoped in Flutter.

Flutter unit/widget tests cannot prove Supabase RLS. Do not certify isolation
until these tests pass against a non-production Supabase project using real
sessions, then repeat a minimal smoke test after deployment.

## Implementation boundaries and remaining deployment work

- The initial schema defines the exact seven content tables used by
  `ContentType`, plus `homepage_cards`, `theme_settings`, profile, page,
  administrator, and audit tables. Tasbeeh counts are intentionally absent.
- Content rows have nullable `page_id`: `NULL` is the explicit global-content
  namespace for the existing top-level public site and platform admins. A
  page owner's row must reference their memorial page. There is no legacy
  content to migrate or assign based on the verified empty public schema.
- `dedications` includes both `arabic_text` and `dua_text`: the current
  repository writes both fields, and the schema constrains them to match.
- Homepage references use UUID content IDs and a security-definer validator
  because the reference is polymorphic across seven tables. The function uses
  a fixed `pg_catalog` search path and limits checks to public content or a
  page the caller owns.
- Tasbeeh counters remain local to each visitor's device/browser. No counter
  values are sent to Supabase.
- Security-definer functions are not callable by `PUBLIC`; only policy helper
  functions are executable by the roles that need them. The Auth provisioning
  function is trigger-only. Keep the Supabase service-role key server-side.
- Auth email confirmation, reset-link redirects, production admin bootstrap,
  hosting rewrites for social crawler metadata, and real-device/browser tests
  are configuration/deployment tasks not performed by this SQL file.
- `/m/:slug` social previews are not guaranteed by Flutter's static web
  hosting; the prepared Edge Function still requires a reviewed deployment
  and hosting/CDN rewrite.
