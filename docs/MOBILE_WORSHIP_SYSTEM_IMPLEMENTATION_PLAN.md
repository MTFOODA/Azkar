# Mobile Worship System Implementation Plan

## Audit findings

- The application is Flutter 3.47.7 / Dart 3.13.5, with Riverpod 3, GoRouter, and Supabase. Flutter Web is a supported production target.
- The Android app inherits Flutter's current Android defaults (minSdk 24, targetSdk 36); the iOS deployment target is 15.0. Android package compatibility must be checked against those values before adding notification/widget dependencies.
- `lib/core/providers/app_providers.dart` is the central dependency-injection surface. It already exposes the authenticated account session, page-scoped content repositories, owned memorial pages, and the Quran dataset repository.
- Memorials use `MemorialPage`; content uses the shared `ContentItem` model and page-scoped repositories. Existing content rows include publication state and display ordering. The Quran dataset is bundled and validates its 114-surah/6,236-ayah structure.
- `lib/core/storage/local_database.dart` provides one Sembast database on mobile and IndexedDB on web. Reminder, completion, location, notification, and outbox records are namespaced by account where applicable; they remain on the device.
- Routes are centralized in `lib/core/routing/app_router.dart`. Existing `/dashboard` routes are memorial-management routes and must not be repurposed.
- Existing Tasbeeh counters are local and independent; new prayer completion must not reset or replace them.
- Supabase migrations establish per-user memorial ownership and RLS for published and owner-visible memorial content. There are no reminder-preference tables in the checked-in migrations.
- No local notification, prayer-time, location, app-widget, or WidgetKit implementation/dependency was found. Android currently has a basic `FlutterActivity`; iOS has the standard Flutter runner and no widget extension.
- The repository's current worktree is not clean. Several application, routing, repository, test, and migration files already have user changes. Those changes are out of scope and must be preserved; any later integration in a modified file requires reviewing and retaining its current edits.

## Proposed architecture

Keep the feature mobile-only at platform boundaries while leaving shared models and the existing web application compilable:

- Add focused feature areas for prayer times, reminders/prayer tracking, worship dashboard, and memorial widget content. Use existing Riverpod providers, `MemorialPageRepository`, page-scoped `ContentRepository`, `QuranDatasetRepository`, and `TasbeehCounterStore`; do not create duplicate content models or counters.
- Add an AlAdhan-backed prayer-time provider behind a small interface. Use location only after an explicit user choice; always retain manual location selection and identify calculation settings and manual adjustments.
- Keep scheduling on-device. Put platform notification and home-widget calls behind conditional/platform-specific adapters so web builds do not import mobile-only APIs. Keep scheduling logic and state transitions testable without platform channels.
- Use the existing Sembast database for account-namespaced preferences, completion state, bounded schedule bookkeeping, and offline caches. Retain account-scoped preferences for offline recovery while preventing cross-account reads; cancel the prior account's schedules and clear any future widget cache on account switch. Do not persist access tokens or put secrets in widget preferences.
- Keep Supabase as the source of truth for reminder settings. Add an incremental migration with owner-scoped tables, constraints/indexes, and RLS; any memorial reference must be constrained to a memorial owned by that same user. Do not run that migration against production.
- Add a separate authenticated worship route (not an existing memorial-management route) and connect it to mobile navigation without changing public memorial or web navigation behavior.

## Delivery sequence and phase gates

Each phase is to be implemented and tested independently. Do not proceed past a phase that fails its targeted checks.

1. **Foundation and compatibility:** Confirm dependency/platform minimums, account lifecycle hooks, and existing dirty-file diffs. `MobileRuntime` now provides a tested, web-safe runtime-target boundary without importing mobile plugins; it does not claim that notifications or widgets are implemented or permitted. Record selected package versions in the lockfile only after compatibility is verified.
2. **Prayer times:** Implemented a replaceable AlAdhan monthly-calendar provider, Egypt method 5 default, manual city/country and optional-consent approximate location, IANA timezone parsing, and Sembast cache with validated offline fallback. No notification scheduling is included in this phase. Per-prayer adjustments remain future work.
3. **Preferences and local state:** Implemented account-scoped Sembast reminder preferences/configurations, revision-based offline synchronization with explicit conflict resolution, local-only prayer completion, and an unapplied owner-scoped Supabase migration. Notification action idempotency, schedule reconciliation, and content caches were deferred to later phases.
4. **Notification infrastructure (Phase 4):** Implemented web-safe Android/iOS adapters, explicit permission requests, channels/categories, stable IDs, account-scoped cancellation, and foreground/cold-start action delivery. Trigger preference sync on login, app resume, connectivity restoration, and preference edits; coalesce duplicate requests and safely merge independent fields while retaining incompatible conflicts for user resolution. Do not schedule prayer reminders or implement prayer completion behavior in this phase.
5. **Prayer completion state machine (Phase 5):** Persist each account/date/prayer/timezone occurrence locally; model completion and reminder states; schedule the first reminder at prayer time +10 minutes and at most one final reminder 20 minutes later after “لسه مصليتش”; cancel reminders on completion; and expose a stable-ID post-prayer Tasbeeh event. This accepted phase excludes quiet hours, rolling schedule horizons, and Tasbeeh UI; those are not prerequisites for this state-machine contract.
6. **Durable events and reminder scheduling engine (Phase 6):** Persist post-prayer Tasbeeh events atomically in a Sembast outbox and implement a bounded, idempotent local scheduler for prayer-time, completion, Tasbeeh, Azkar, custom, and Friday reminders. Reconcile account-safely from validated local calendars/preferences; the user-facing reminder and Tasbeeh UI were deferred to Phase 7.
7. **Worship dashboard, reminder UI, and onboarding (Phase 7):** Implemented the authenticated prayer dashboard and prayer-state controls, reminder and custom-reminder settings, manual/GPS location and calculation settings, permission education and explicit request, account-isolated personal Tasbeeh, and native first-launch onboarding. The interface uses the Phase 1–6 services and existing Sembast database. Web and public/deep-link routes bypass the onboarding gate; memorial-management routes are unchanged. No memorial widget content or native widgets are implemented.
8. **Memorial widget content:** Build an account-scoped, offline-capable content pipeline from the existing repositories. Filter ownership/publication/visibility before caching; preserve deceased name/gender; exclude videos; clear data on account changes. Test ordering, navigation state, empty/offline behavior, and deep links.
9. **Native widgets:** Implement Android RemoteViews/AppWidget actions and WidgetKit/App Groups as separate platform deliverables. Confirm minimum OS support and fallback behavior before coding. Add native targets/configuration only where required and document manual Xcode/device setup.
10. **Security, regression, and documentation:** Review RLS and cache lifecycle, run focused and full regression checks including web and Android builds, update setup/manual-test documentation, and report unverified platform behavior honestly.

## Scheduling and platform constraints

- Android/iOS may delay or throttle background work, widget refresh, and inexact alarms. Exact-alarm access must not be requested unless an approved product requirement and platform policy justify it.
- Use a rolling notification horizon and reconcile on app launch/resume, login, settings changes, timezone/location changes, and available OS callbacks. Arbitrarily long periods without opening the app cannot promise indefinitely refreshed schedules.
- Notification actions must be idempotent and persisted before acknowledging an action. Do not rely on a permanently running Dart isolate.
- iOS pending-notification limits require prioritizing near-term occurrences. WidgetKit refresh timing is system-controlled; interactive controls require a supported OS version and an older-version fallback.
- Native widget work requires platform-specific validation. This current Windows environment cannot compile or run the iOS app/widget; iOS claims require a compatible macOS/Xcode environment and physical-device checklist.
- Sembast uses app-private storage on mobile and IndexedDB on web; these stores are not encrypted by this implementation. Notification schedule metadata contains account-scoped IDs and stable keys, while visible OS notification content is outside Sembast and may appear on a lock screen unless generic privacy text is selected. A future remove-account-data action must explicitly cancel that account's OS notifications and remove its local records; no destructive account-data removal is performed automatically.
- Notification permissions are queried during setup but requested only through an explicit user action. Android scheduling uses inexact alarms, and the OS may delay delivery. The browser build compiles, but browser notifications are not scheduled by this mobile-only service. Native action callbacks use the foreground app path; headless background action processing is not implemented.
- `LocalNotificationService` persists account-owned notification IDs and stable keys before registering schedules; it rejects cross-account ID collisions, cancels incomplete schedules after an account switch, and filters notification actions by active-account fingerprint and stable ID. A launch action received before authentication is held only in memory until the account becomes available.
- The root app coordinates initial/login, resume, and connectivity-restoration preference sync. Duplicate requests for the same account are coalesced, with a follow-up when a forced event occurs during an active sync; settings save paths sync immediately. Connectivity is only a network-interface signal, not proof of Internet access. The revisioned sync service merges independent fields/configurations and retains incompatible edits for explicit resolution.
- No widget implementation or widget content cache exists yet, so there is no previous-account widget data to clear in this phase. Account-scoped Sembast records are retained; they are not encrypted. Removing an account's retained local records remains a future explicit user action.

## Phase 7 implementation notes

- Authenticated routes are `/worship`, `/worship/reminders`, `/worship/location`, `/worship/notifications`, and `/worship/tasbeeh`. The existing memorial-management `/dashboard` routes remain separate. The login redirect accepts only local worship destinations.
- The prayer dashboard uses the validated provider/cache and Phase 5 state machine, including manual completion/correction and the existing notification-action contract. It shows the next prayer and refreshes the displayed local day after a timezone date boundary. A validated Hijri-date source is not available, so no Hijri date is shown.
- Reminder controls map to the Phase 6 scheduler's existing categories, custom daily/weekday recurrence, quiet hours, privacy option, and post-prayer delay. Categories default off. Notification permission is explained and requested only after the user activates the permission screen action; denial also offers device settings.
- Manual city/country selection works without GPS permission and is synchronized as an ordinary preference. Coordinates remain in the local device-location store. GPS flow presents an in-app consent dialog before the operating-system permission request. If a preference conflict occurs, the user selects whether to retain local or account settings; canceling leaves the local pending edit intact.
- Personal Tasbeeh uses a distinct account-namespaced counter and does not reuse memorial-page counters. Prayer completion and outbox data remain local; completion is not synchronized.
- Onboarding completion is persisted in the existing Sembast preferences store. The first-launch redirect is restricted to an incomplete native `/` visit; Web and public memorial/deep-link routes bypass it. It is possible to reopen `/onboarding` from reminder settings.
- Automated tests cover onboarding persistence/eligibility/navigation and verify the notification screen does not request permission until an explicit tap. Full dashboard/location/editor workflows still require device/UI acceptance tests; physical notification delivery, iOS builds, and iOS permission/action behavior remain unverified on Windows.
- There is no memorial widget or widget cache. No claim is made for OS-independent exact notification delivery or continuous background scheduling.

## Phase 2 implementation notes

- Runtime dependencies are `http ^1.6.0`, `timezone ^0.11.2`, `geolocator ^14.1.2`, and `crypto ^3.0.8`; their SDK requirements are compatible with this project. The Android manifest requests approximate location only. iOS declares When-In-Use disclosure only; no background location capability is requested.
- The provider uses AlAdhan monthly city/country or coordinate endpoints, validates every day and six returned prayer times, and requires a valid IANA timezone from response metadata. For a GPS-selected location, latitude/longitude are sent to AlAdhan over HTTPS as request parameters; they are not sent to Supabase. `PrayerTimesService.fetchCalendarForInstant` resolves the correct local month even when it differs from UTC. Method 5 is selected for Egypt by country code/name or approximate GPS bounds; users can override the method.
- Device location is accessed only after the injected in-app consent callback confirms the user, and then only after the OS permission flow. Manual city/country calls require no location permission. A location-selection/settings screen is not part of this provider phase.
- The Sembast cache is keyed by a SHA-256 location fingerprint, month, calculation method, Asr method, and an explicitly selected timezone. Network errors use only a structurally and timezone-validated cached calendar; otherwise the service throws and does not synthesize times. Cache writes are local to the existing platform-specific database.
- The app currently exposes provider/service Riverpod bindings but no prayer-time dashboard or user-facing calculation/timezone controls. Per-prayer minute adjustments are not implemented in this phase.
- Release web and debug Android builds and automated tests passed on Windows. iOS compilation and device permission behavior remain unverified because macOS/Xcode are unavailable.
- Phase 3 location preference decision: sync a manually selected city/country; keep automatically detected GPS coordinates on-device only.

## Phase 3 implementation notes

- Reminder preferences and reminder configurations are persisted in the existing Sembast database, namespaced by authenticated Supabase user ID. Provider, local-store, and remote-store boundaries validate the active account before accessing account-specific records; prior-account records are retained for offline recovery but are never returned through a different active account.
- Prayer completion records remain device-local, keyed by account, local calendar date, and prayer. They are not part of any remote payload or migration table.
- Offline changes remain marked pending. Synchronization uses monotonically increasing server revisions and compare-and-save; a divergent server edit returns both versions without overwriting either. The caller must explicitly choose a version to resolve a conflict.
- Migration `supabase/migrations/20261103_reminder_preferences.sql` adds `user_reminder_preferences` and `user_reminder_configurations`. Both tables have RLS enabled and authenticated users can select only their own rows. Direct writes are revoked; authenticated writes use a security-definer RPC that verifies `auth.uid()`, checks expected revision, validates settings, and restricts memorial references to a memorial owned by that same user.
- GPS coordinates, location-shaped JSON keys, and GPS-derived timezones are rejected or omitted from Supabase persistence. Coordinates remain in the local database but are transmitted to AlAdhan over HTTPS when requesting a coordinate-based prayer calendar. Manually selected city/country, its optional country code/timezone, and non-location reminder settings/configurations may sync. The migration has not been applied to production.
- No notification scheduling, notification permission prompts, or production database operations are part of Phase 3.
- Earlier project notes record a disposable local PostgreSQL test with synthetic accounts. This audit could not independently reproduce it because the available local PostgreSQL service requires a password; the current migration revision therefore still needs isolated database validation. Supabase-specific project setup and migration history also require a non-production project check.

## Phase 5 implementation notes

- Prayer completion is a domain state machine behind persistence and reminder-scheduler interfaces. Its Sembast adapter uses the existing local database and keeps occurrences scoped to the active authenticated account; the notification adapter reuses Phase 4's stable notification IDs and registry.
- Occurrences are identified by account, local prayer date, prayer, IANA timezone, and the UTC offset at that prayer time. The prayer instant is retained separately so an adjusted prayer time can reschedule the same occurrence, while date/timezone-context changes do not reuse an incompatible identity.
- The state machine persists the five prayers independently and supports not-confirmed, reminder-sent, not-yet-prayed, and completed states; manual completion/correction; a first reminder at +10 minutes; and only one optional final reminder at +30 minutes total. Ignoring a reminder does not create retries. Pending schedule intent remains persisted if OS scheduling fails and is retried during reconciliation.
- Completion creates a deterministic Tasbeeh event ID as part of the persisted state transition, suppressing duplicate actions, duplicate manual completion, and re-completion after correction. Durable event persistence and acknowledgment are implemented in Phase 6; the state machine's broadcast remains an in-process convenience and is not the recovery mechanism.
- Automated coverage includes all five prayers, reminder timing/limits, ignored and duplicate actions, scheduler failure/restart recovery, manual correction, account isolation, DST offsets, timezone changes, prayer-time adjustments, and notification action validation.
- This phase does not implement quiet hours, rolling-horizon scheduling, notification UI/settings, or Tasbeeh UI. Notification delivery timing remains OS-controlled, and native iOS behavior remains unverified on this Windows environment.

## Phase 6 implementation notes

- The completion transition and deterministic Tasbeeh event are written atomically to separate stores in the existing single Sembast database. Delivery uses account-scoped claim leases, retry/release, and acknowledgment only after consumer success. The notification consumer uses a stable event-derived key, so replay after a crash does not duplicate an already registered Tasbeeh notification; external notification delivery and Sembast acknowledgment cannot be made one atomic operation.
- The unified local scheduler covers prayer-time alerts, the existing two-reminder completion state machine, post-prayer Tasbeeh, morning/evening Azkar, custom daily/specific-weekday reminders, and Friday Al-Kahf. Its rolling horizon is three local calendar days; engine-managed schedules are capped at 30 and the shared per-account registry at 60. Reconciliation cancels obsolete schedules before using capacity for completion reminders and reports capacity deferrals.
- Prayer schedules require a validated calendar no more than 45 days old. Fresh validated monthly calendars are reused locally to avoid unnecessary provider requests; failed/missing/stale data never produces fabricated prayer times. Manual city/country remains in synchronized preferences; explicitly selected GPS coordinates remain in an account-namespaced device-only store.
- Reconciliation runs on app start/resume, account changes, connectivity restoration, preference synchronization, and local setting/location saves. Concurrent reconciliations for one account are serialized. Notification permission is checked without prompting; denied permission leaves existing schedules unchanged until the user grants access through a future user-facing flow.
- Quiet hours defer remembrance, custom, Friday, and Tasbeeh alerts. Prayer-time alerts inside quiet hours are skipped; completion reminder timing remains the approved exact +10/+30-minute rule. Invalid DST wall-clock times are skipped rather than normalized.
- Scheduling is native-mobile only and uses the existing Android/iOS adapter. Android uses inexact alarms; OS delivery timing and background recovery are not guaranteed. The web build remains compatible but does not schedule browser notifications. iOS/device behavior is unverified without macOS/Xcode and physical-device tests. No reminder settings UI, permission-education UI, or Tasbeeh UI is included in this phase.

## Manual Supabase setup for Phase 3

1. Confirm the existing `memorial_pages` table has `id uuid` and `owner_user_id uuid`, and that the project has applied the checked-in multi-memorial migration before `20261103_reminder_preferences.sql`.
2. Review the migration and apply it only to a disposable/local or explicitly designated non-production Supabase project using the project's normal migration workflow. Do not use the production project for this validation.
3. Verify `user_reminder_preferences` and `user_reminder_configurations` have RLS enabled; authenticated `SELECT` policies use `user_id = auth.uid()`; anonymous and authenticated direct table writes are unavailable; and only authenticated users can execute `save_user_reminder_preferences`.
4. With two test accounts, verify each can read only its own rows, a caller cannot save using the other account's ID, and a memorial configuration cannot reference another owner's memorial. Verify a stale expected revision returns the current snapshot without replacing it.
5. Verify the RPC rejects nested GPS/location keys and invalid settings, and that deleting a referenced memorial removes its linked reminder configuration. Inspect only synthetic test data.
6. Configure the Flutter app's existing Supabase URL and public key through its current build configuration. The migration adds no secrets or new client credentials.

## Security and migration safeguards

- RLS must scope every preference/reminder row to `auth.uid()`. Memorial references must not allow cross-user IDs, including through inserts/updates.
- Only content allowed by the user's memorial ownership and publication/visibility rules may enter widget or notification caches. No unpublished content may be surfaced by a notification.
- Account changes must cancel the prior account's schedules and clear its widget cache before loading the next account.
- Never include credentials, tokens, or sensitive reminder text in logs. Provide notification preview privacy controls where supported.
- Migration SQL is a reviewed deliverable only. Do not apply it to production or alter production records without explicit approval. Phase 7 requested source push and deployment through the existing protected GitHub workflow; production deployment remains subject to workflow validation and the required `production` environment approval. The reminder migration remains a prerequisite for cross-device preference synchronization and is not included in the deployment workflow.

## Verification strategy

- Add unit tests around prayer calculations/parsing, timezone transitions, reminder state transitions and deduplication, content eligibility, account-scoped cache clearing, and widget navigation state.
- Focused UI tests cover onboarding completion/eligibility/navigation and explicit notification-permission action. Add or extend dashboard/settings and deep-link tests as the widget screens stabilize. Add migration/RLS validation instructions and test cases; do not use production data.
- After each Dart/Flutter code change, run the focused tests/analyzer/build checks and a Flutter hot reload or hot restart when an attached runtime is available.
- Final regression targets: formatting, `flutter analyze`, `flutter test`, `flutter build web --release`, and `flutter build apk --debug`. Run iOS validation only with macOS/Xcode; report it as unverified otherwise.
- Validate notification delivery/actions and home-screen widgets on physical Android/iOS devices where available. Do not label OS-dependent timing as guaranteed.

### Phase 7 manual acceptance

1. On a clean Android/iOS install, open `/` and verify onboarding appears once; skip or finish it, restart the app, and verify it does not reappear.
2. Verify Web, a public `/m/:slug` URL, and other deep links bypass the first-launch gate. Verify `/onboarding` can still be opened from reminder settings.
3. Open `/worship` while signed out and verify login returns to the requested local worship route after authentication. Confirm memorial `/dashboard` behavior remains unchanged.
4. Save a manual city/country without granting location permission. Separately test GPS only after accepting the in-app explanation; verify coordinates remain local and are absent from Supabase requests.
5. Explicitly grant notification permission, enable one reminder category, and verify scheduling/reconciliation on device. Repeat after changing accounts, timezone, quiet hours, and app restart; treat delivery time as OS-controlled.
6. With two approved test accounts, verify reminder preference synchronization only after applying and validating the unapplied Phase 3 migration on a non-production project.

## Approval checkpoint

The Phase 0 plan was approved before Phase 1 and Phase 2 implementation. Continue one phase at a time. Phase 7 authorizes a push and use of the existing protected production workflow after validation; do not bypass its environment approval. Production migrations and production configuration changes remain separate approval gates.
