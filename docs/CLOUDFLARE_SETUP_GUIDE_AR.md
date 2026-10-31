# دليل نشر AZKAR على Cloudflare Workers — بالمصري

## قبل ما تبدأ

النشر الحالي لـAZKAR بيستخدم **Cloudflare Workers مع Static Assets**، مش
Cloudflare Pages. الـWorker الموجود هو `azkar-sadaqa`، والرابط العام المطلوب:

```text
https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev
```

النسخة الحالية على الرابط لسه مش سليمة: الصفحة الرئيسية بترجع HTML قالب
Flutter الخام، وفتح `/m/...` مباشرة بيرجع 404. متعتبرش ظهور **Ready** في
Cloudflare دليل إن الموقع اتنشر صح.

التدفق المختار هو GitHub Actions: يثبت Flutter 3.47.7، يشغل التحليل والاختبارات،
يبني Flutter Web release، ويتأكد إن `build/web` فيه التطبيق المترجم، وبعدها
ينشر نفس Worker باستخدام Wrangler 4.156.0. مش هنستخدم إعدادات أو أوامر Pages.

## إعداد GitHub مرة واحدة

1. افتح مستودع `MTFOODA/Azkar` ثم **Settings → Environments** وأنشئ environment
   باسم `production`.
2. فعّل **Required reviewers** واختار مراجعاً يوافق صراحة على نشر الإنتاج.
   وجود اسم environment في الملف وحده مش كفاية لو مفيش approval protection.
3. أضف القيم دي كـ**Environment secrets** في `production`:

   | الاسم | القيمة |
   |---|---|
   | `AZKAR_SUPABASE_URL` | رابط مشروع Supabase الإنتاجي |
   | `AZKAR_SUPABASE_PUBLISHABLE_KEY` | anon/publishable key فقط |
   | `CLOUDFLARE_ACCOUNT_ID` | Account ID للحساب اللي عليه الـWorker |
   | `CLOUDFLARE_API_TOKEN` | Token محدود بصلاحية **Edit Cloudflare Workers** وعلى الحساب المطلوب فقط |

4. أضف **Environment variable** باسم `AZKAR_AUTH_SCHEMA_VERIFIED` وقيمته
   `false` حالياً. ما تغيّروش لـ`true` إلا بعد اختبار إنتاج معتمد يثبت
   provisioning وعزل المالكين وسياسات RLS.
5. ما تضيفش `PUBLIC_BASE_URL` كـCloudflare runtime variable؛ Flutter محتاجه
   وقت الـbuild، والـworkflow بيحقنه بقيمة الـWorker الصحيحة.

## إعداد Cloudflare مرة واحدة

1. افتح **Cloudflare Dashboard → Workers & Pages → azkar-sadaqa → Settings →
   Builds**.
2. افصل Git build connection الحالي، أو عطّل production builds منه لو اللوحة
   بتوفر الاختيار ده. **ما تحذفش الـWorker.**
3. السبب: الإعداد السابق مفيهوش Build command وكان بينشر مجلد المصدر `web/`.
   لازم يبقى فيه طريق نشر واحد بس: GitHub Actions.
4. احتفظ باسم الـWorker والرابط الحالي زي ما هما. ملف
   `wrangler.jsonc` بينشر `build/web` ويفعّل SPA fallback لمسارات Flutter.

فصل Git Builds ما بينشرش نسخة جديدة وما يغيرش النسخة النشطة؛ التغيير بيحصل عند
تشغيل workflow بعد موافقة GitHub.

## إعداد Supabase قبل اختبار الحسابات

الكود بيطلب redirect بعد تأكيد التسجيل إلى `/dashboard`، وبعد استعادة كلمة
المرور إلى `/reset-password`. في:

**Supabase Dashboard → Authentication → URL Configuration**

- **Site URL:** `https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev`
- **Redirect URLs:** أضف:
  - `https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev/dashboard`
  - `https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev/reset-password`

احتفظ بكل روابط التطوير الموجودة؛ ما تمسحش ولا تستبدل إعدادات تانية. المفتاح
اللي هيدخل GitHub لازم يبقى publishable فقط، وممنوع تحط service-role أو كلمة
سر قاعدة البيانات في Flutter أو GitHub.

## بناء واختبار محلي

على جهاز المطور، انسخ
`config/production.example.json` إلى `config/production.json`، واملأ رابط
Supabase ومفتاح publishable المعتمدين محلياً فقط. خلي
`AZKAR_AUTH_SCHEMA_VERIFIED` = `false` لحد ما اختبار RLS يتوافق عليه. سكربت
الإنتاج هيرفض البناء لحد التحقق المطلوب؛ ماتغيّرش القيمة لتخطي الفحص.

```powershell
flutter analyze
flutter test
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_web_production.ps1
npx.cmd --yes wrangler@4.156.0 dev --local --ip 127.0.0.1 --port 8787
```

بعدها اختبر `/` و`/login` و`/register` و`/reset-password` و`/m/<slug>` مع
تحديث المتصفح. المحلي ما يثبتش إن الإنتاج أو RLS اشتغلوا.

## تشغيل نشر الإنتاج

النشر متوقف لحد ما مالك المشروع يوافق. بعد إعداد الـsecrets والحماية:

1. راجع **Actions → Deploy AZKAR Worker**.
2. اتأكد إن `Analyze and test` نجح.
3. راجع commit والـdiff؛ موافقة GitHub environment مطلوبة قبل خطوات البناء
   والنشر.
4. بعد الموافقة، اتأكد إن الـworkflow عمل Flutter release build ونشر
   `build/web` للـWorker `azkar-sadaqa`.
5. راجع مخرجات Wrangler ثم اختبر رابط الإنتاج و`/m/<slug>` مباشرةً.

الـworkflow لا يشغّل على الفروع أو Pull Requests، ومش هيعمل deploy لو التحليل
أو الاختبارات أو إعداد الإنتاج فشل. سكربت `deploy_cloudflare.ps1` يفضل مسار
يدوي احتياطي يتطلب تأكيد كتابة `DEPLOY PRODUCTION`؛ استخدمه فقط بطلب وموافقة
واضحين، لتجنب نشرين متنافسين.

## الرجوع لنسخة سليمة

من **Workers & Pages → azkar-sadaqa → Deployments/Version history** اختار
آخر نسخة سليمة وارجع لها حسب إجراء Cloudflare الظاهر في اللوحة. بعدها اختبر
الرابط. الرجوع لنسخة Worker لا يرجع تغييرات Supabase أو بيانات المستخدمين.

## اختبارات القبول

جرّب الصفحة الرئيسية، تسجيل الدخول والتسجيل واستعادة كلمة المرور، روابط
الميموريال المباشرة، تحديث المتصفح، المشاركة، الخطوط العربية، وأحجام شاشة
مختلفة. التسجيل لازم يفضل 4 حقول فقط؛ الصفحة بتتعمل بآلية قاعدة البيانات
الموجودة، والعنوان والـslug بيتغيروا من **لوحة التحكم ← إعدادات صفحتي**.

ما تعملش حسابات حقيقية أو بيانات اختبار على production من غير موافقة. راجع
[`الإجراءات اليدوية المطلوبة`](PRODUCTION_MANUAL_ACTIONS_AR.md) و
[`تقرير القبول الحالي`](PRODUCTION_ACCEPTANCE_REPORT.md) لمعرفة الخطوات
المتوقفة والدليل المتاح.

## استكشاف المشاكل

| المشكلة | التحقق |
|---|---|
| الصفحة الرئيسية تفتح بس مفيش تطبيق Flutter | اتأكد إن Wrangler رفع `build/web` مش مجلد `web` المصدري. |
| `/m/slug` بيرجع 404 | راجع `assets.not_found_handling` في `wrangler.jsonc` ونسخة الـWorker المنشورة. |
| رسالة إعداد Supabase | راجع GitHub environment secrets وإعداد build-time؛ ماتطبعش القيم. |
| رابط المشاركة host غلط | راجع `PUBLIC_BASE_URL` في إعداد الإنتاج واطلب build جديد. |
| فشل تسجيل الدخول/الاستعادة | راجع روابط Supabase Auth المحددة فوق وسجلات Supabase بدون كشف بيانات شخصية. |
| fonts أو icons ناقصة | راجع `build/web/assets` وملفات `icons`، وماتعملش fallback يعيد HTML لطلبات الأصول. |
| ظهرت صفحتين نشر/تكرار build | افصل Workers Builds القديم، وخلي GitHub Actions مسار النشر الوحيد. |

## مراجع

- [Cloudflare Workers Static Assets](https://developers.cloudflare.com/workers/static-assets/)
- [Cloudflare Workers SPA routing](https://developers.cloudflare.com/workers/static-assets/routing/single-page-application/)
- [Cloudflare Workers Builds](https://developers.cloudflare.com/workers/ci-cd/builds/)
- [Cloudflare GitHub Actions](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/)
