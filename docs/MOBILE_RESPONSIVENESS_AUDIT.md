# AZKAR Mobile Responsiveness Audit

**Audit date:** 2026-11-02  
**Scope:** Source-level inventory of the Flutter routes, shared navigation
surfaces, and modal UI, followed by focused responsive regression tests.

The supplied attachment contained the issue descriptions but no screenshot
image. Findings below are based on the checked-in Flutter source and widget
tests; no claim is made that every route or state was visually rendered.

## Screen and route inventory

| Area | Route(s) | Screen/component |
|---|---|---|
| Public | `/` | `HomePage` |
| Public content | `ContentType.route` for each `ContentType` | `ContentCollectionPage` |
| Public content | `/c/:type/:id` | `SharedContentPage` |
| Memorial | `/m/:slug`, `/m/:slug/:type` | `PublicMemorialPage` with memorial section navigation |
| Public utility | `/about-developer` | `AboutDeveloperPage` |
| Account | `/login` | `AccountLoginPage` |
| Account | `/register` | `AccountRegistrationPage` |
| Account | `/forgot-password` | Redirect to password reset |
| Account | `/reset-password` | `PasswordResetPage` |
| Native onboarding | `/onboarding` | `OnboardingPage`, including its final login/register/explore actions |
| Worship | `/worship` | `PrayerDashboardPage` |
| Worship | `/worship/reminders` | `ReminderSettingsPage` |
| Worship | `/worship/location` | `PrayerLocationSettingsPage` |
| Worship | `/worship/notifications` | `NotificationPermissionPage` |
| Worship | `/worship/tasbeeh` | `PersonalTasbeehPage` |
| Owner | `/dashboard` | `OwnerMemorialPagesPage` |
| Owner | `/dashboard/pages/:pageId` | `OwnerDashboardHomePage` |
| Owner | `/dashboard/pages/:pageId/settings` | `OwnerPageSettingsPage` |
| Owner | `/dashboard/pages/:pageId/homepage` | `OwnerDashboardHomepagePage` |
| Owner | `/dashboard/pages/:pageId/appearance` | `OwnerDashboardAppearancePage` |
| Owner content | `/dashboard/pages/:pageId/content/:type` | `OwnerDashboardContentListPage` |
| Owner content | `/dashboard/pages/:pageId/content/:type/new` | `OwnerDashboardContentEditorPage` |
| Owner content | `/dashboard/pages/:pageId/content/:type/:id/edit` | `OwnerDashboardContentEditorPage` |
| Owner preview | `/dashboard/pages/:pageId/preview` | `OwnerMemorialPreviewPage` |
| Admin | `/admin/dashboard` | `AdminDashboardPage` |
| Admin | `/admin/homepage` | `AdminHomepagePage` |
| Admin | `/admin/appearance` | `AdminAppearancePage` |
| Admin | `/admin/settings` | `AdminSettingsPage` |
| Admin content | `/admin/content/:type` | `AdminContentListPage` |
| Admin content | `/admin/content/:type/new` | `AdminContentEditorPage` |
| Admin content | `/admin/content/:type/:id/edit` | `AdminContentEditorPage` |
| Error | Unknown or invalid content route | `RouteNotFoundPage` |
| Configuration | Missing Supabase configuration at startup | `SupabaseConfigurationErrorPage` |

Admin and owner route guards, `/admin` and `/dashboard` aliases, and legacy
owner routes are defined in `lib/core/routing/app_router.dart`.

## Shared responsive components and patterns

- `AppBreakpoints`, `AdaptiveCardGrid`, and `PageContent` provide shared
  breakpoints, wrapping card layouts, and constrained reading widths in
  `lib/core/widgets/adaptive_layout.dart`.
- `PublicScaffold` owns the public app bar, SafeArea body, share controls, and
  public navigation drawer.
- `AdminShell` switches from a drawer to a navigation rail at 1000 px.
- The owner dashboard uses a drawer below its wide-layout breakpoint and a
  fixed side navigation on wide screens.
- Account forms use a `SingleChildScrollView` within a constrained card.
- Public content, prayer settings, and several editor pages use scrollable
  bodies; memorial and content cards are shared components.
- The existing share action uses a modal bottom sheet. Confirmations and
  editing flows use `AlertDialog` surfaces.

## Dialogs, sheets, and navigation surfaces

- Public navigation drawer: `PublicNavigationDrawer` in
  `lib/features/sharing/public_scaffold.dart`.
- Admin drawer / wide navigation: `AdminShell` in
  `lib/features/admin/dashboard/presentation/admin_shell.dart`.
- Owner drawer / wide navigation: owner shell in
  `lib/features/account/presentation/owner_dashboard_pages.dart`.
- Share sheet: `lib/features/sharing/share_widgets.dart`.
- Account, memorial-owner, admin editor, reminder, prayer-location, tasbeeh,
  and unsaved-changes dialogs are in their corresponding presentation files;
  they use Material `AlertDialog` constraints and are not individually covered
  by this focused responsive suite.

## Confirmed responsive findings and changes

1. The onboarding final actions shared a horizontal `Row` with a spacer and a
   multi-action `Wrap`. At narrow widths, the header/action rows could exceed
   available width. The final actions now stack at narrow widths, the
   intermediate actions wrap, and the onboarding slide content scrolls when
   its available height is short. The header uses the compact brand mark on
   narrow layouts.
2. Material's default drawer width could exceed the viewport on very narrow
   devices. Public, admin, and owner drawers now use the same adaptive width
   (88% of viewport, capped at 360 logical pixels). Their existing `ListView`
   and `SafeArea` behavior keeps navigation/footer content reachable.
3. About Developer content is width-constrained and vertically scrollable.
4. The Android download entry is visible in the public drawer, validates an
   optional HTTPS `.apk` URL, and reports an unavailable/failed link rather
   than navigating to a broken URL.

## Responsive verification coverage

Automated widget coverage exercises the onboarding final actions at 280, 320,
360, 375, 390, 412, 430, 480, 600, 768, and 1024 logical pixels with 1.0x and
1.3x text scaling, at a short 480 px height. Public drawer and About page tests
exercise 280, 320, and 360 px widths; the drawer tests use short 360 px height
and 1.3x text scaling. Focused prayer settings regression tests also cover 320,
360, 375, 390, 430, 768, and 1200 px in Arabic/RTL and English/LTR.

These are focused component tests, not complete visual coverage of every route.
Keyboard-open layouts, landscape device rendering, long owner identities,
long memorial names, every dialog/bottom sheet, every loading/error state, and
all admin/owner screens remain candidates for manual or additional route-level
acceptance testing. No production data was accessed or changed for these tests.
