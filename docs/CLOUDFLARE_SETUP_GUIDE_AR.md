# دليل إعداد Cloudflare لموقع AZKAR — بالمصري وبالراحة

الدليل ده بيجهزك ترفع نسخة الويب الحالية من AZKAR على Cloudflare Pages. كل
الملفات هتفضل Flutter، وSupabase هيفضل مسؤول عن الحسابات والبيانات. **مفيش
حساب Cloudflare أو مشروع أو نشر اتعمل من داخل المشروع.**

> **مهم قبل أي خطوة إنشاء:** Cloudflare بيخلي اختيار طريقة النشر ثابت للمشروع.
> لو اخترت Direct Upload مش هتقدر تحوّله بعدين لـGit integration في نفس المشروع؛
> هتحتاج مشروع جديد. التوصية الحالية هي Direct Upload لأنه أبسط مع البناء
> المحلي على Windows ومفيش Git repository متاح في مساحة العمل دي. دي توصية بس؛
> استنى موافقتك قبل ما تنشئ المشروع.

## 1 — اعمل حساب Cloudflare

1. افتح الموقع الرسمي: [dash.cloudflare.com](https://dash.cloudflare.com/).
2. لو عندك حساب، اختار **Log in**. لو أول مرة، اختار **Sign up**.
3. اكتب بريدك وكلمة مرورك، وبعدها أكّد البريد لو Cloudflare طلب ده.
4. فعّل حماية الحساب بالطريقة اللي تناسبك، وما تبعتش كلمة المرور أو أكواد
   التحقق لأي حد.
5. بعد الدخول، اتأكد إنك داخل الحساب الصحيح من اسم الحساب أعلى لوحة التحكم.

**Checkpoint:** لوحة Cloudflare الرئيسية ظاهرة، ولسه ما أنشأتش أي مشروع.

## 2 — افتح Workers & Pages

1. من القائمة الجانبية افتح **Workers & Pages**. ممكن تلاقيها تحت **Compute**
   أو **Developer Platform** حسب شكل لوحة التحكم.
2. لو ظهر زر **Create application** أو **Create**, افتحه لمشاهدة الاختيارات.

**Checkpoint:** وصلت لقائمة إنشاء تطبيق، لكن لسه ما ضغطتش نشر أو إنشاء مشروع.

## 3 — اختار Cloudflare Pages

في بعض تحديثات لوحة التحكم Cloudflare بيوجهك الأول لـWorkers. اختار **Pages**
أو **Pages project** / **Upload assets** لو ظهر الاسم ده. Pages هو المناسب هنا
لأن Flutter بيبني ملفات HTML وJavaScript وصور ثابتة محلياً. Workers برنامج
server-side؛ مش مطلوب لرفع نسخة الويب الأساسية.

صفحة Cloudflare الرسمية قد تعرض Workers كخيارها الأحدث، لكن المهمة دي مجهزة
لـPages بناءً على اختيار الاستضافة المطلوب. ما تختارش Workers من نفسك كبديل.

## 4 — اختار طريقة النشر (وقّف هنا لو لسه محتاج موافقة)

غالباً هتلاقي اختيارين:

### Direct Upload — الرفع المباشر

- Flutter يبني الملفات على جهاز Windows بتاعك.
- Wrangler يرفع مجلد `build\web`.
- بسيط في التجربة والتشخيص ومناسب للشغل الحالي.
- تحديث الموقع محتاج تشغيل build وبعده deploy يدوي.
- **الاختيار ده ما بيتحولش بعدين لـGit integration في نفس المشروع.**

### Git integration — الربط بـGitHub أو GitLab

- Cloudflare يتابع repository ويعمل build/deploy تلقائي مع التغييرات.
- يوفر preview deployments ويدير إصدارات الفروع.
- محتاج repository مضبوط وخط بناء Flutter/Dart مناسب؛ مساحة العمل الحالية
  مش Git repository.
- **ما بيتحولش بعدين لمشروع Direct Upload.** توثيق Cloudflare يسمح بحالات رفع
  يدوية لبعض مشاريع Git، لكن ده مش نفس تغيير وضع المشروع.

**التوصية:** Direct Upload للمشروع الأول. ما تضغطش Create project دلوقتي إلا
بعد موافقتك على الاختيار النهائي.

مرجع Cloudflare الرسمي:
[Direct Upload](https://developers.cloudflare.com/pages/get-started/direct-upload/)
و[Git integration](https://developers.cloudflare.com/pages/get-started/git-integration/).

## 5 — إنشاء المشروع (بعد الموافقة على Direct Upload)

1. اختار **Direct Upload** أو **Upload assets**.
2. اكتب اسم مشروع مناسب بالإنجليزي وأرقام وشرطة، مثلاً
   `azkar-public-site` — ده مثال فقط، مش ضمان إن الاسم متاح.
3. Cloudflare هيعرض hostname بالشكل
   `https://<project-name>.pages.dev`. لو الاسم محجوز، اتبع الاسم البديل اللي
   تقترحه اللوحة وسجّل الـhostname النهائي بالضبط.
4. أكمل الإنشاء من لوحة Cloudflare. ما ترفعش ملفات Flutter قديمة في الخطوة دي.
5. انسخ الاسم والـhostname الفعليين في مكان محلي آمن عشان تستخدمهم في
   الإعدادات. ما تحطش مفاتيح Supabase في Cloudflare Pages كـsecrets؛ التطبيق
   Flutter عميل عام ومفتاحه لازم يكون publishable فقط.

**Checkpoint:** المشروع موجود في Cloudflare لكن مفيش نسخة AZKAR اتنشرت بعد.

## 6 — جهز نسخة Flutter محلياً

افتح PowerShell في مجلد المشروع:

```powershell
cd "D:\MTFOODA\Code\Flutter apps\Azkar"
Copy-Item config\production.example.json config\production.json
notepad config\production.json
```

املأ الملف محلياً بالقيم الحقيقية:

- `SUPABASE_URL`: رابط مشروع Supabase الصحيح.
- `SUPABASE_ANON_KEY`: مفتاح anon/publishable فقط.
- `AZKAR_DEMO_MODE`: `false`.
- `AZKAR_AUTH_SCHEMA_VERIFIED`: خليه `false` لحد ما مراجعة المخطط وRLS
  واختبارات المالكين المعتمدة تكتمل. سكربت البناء هيرفض البناء لحد ما يبقى
  `true`؛ ما تغيّروش لمجرد تخطي الرسالة.
- `PUBLIC_BASE_URL`: الـhostname الحقيقي اللي Cloudflare خصصه للمشروع، زي
  `https://اسم-مشروعك.pages.dev` من غير `/` في الآخر أو مسار.

ما تلصقش المفاتيح في محادثة أو screenshot أو ملف متعقب بـGit. الملف
`config/production.json` مستثنى من Git.

بعد ضبط إعداد Supabase الإنتاجي والتحقق المطلوب، شغّل:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_web_production.ps1
```

الملفات الجاهزة هتكون في:

```text
build\web
```

السكربت بيتأكد من القيم من غير ما يطبعها، Demo Mode مقفول، وبيانات Supabase
صالحة كمفتاح عام، وبيعمل Flutter Web release build. كمان بيكمل عنوان الصورة
والـmetadata بالـhostname الفعلي. ما تستخدمش `config/dev.json` بدل إعداد
الإنتاج عشان النشر الحي.

## 7 — ثبت Wrangler وسجّل الدخول

Wrangler أداة Cloudflare الرسمية. محتاج Node.js وnpm:

```powershell
node --version
npm --version
```

لو الأمرين مش معروفين، نزّل نسخة LTS من [nodejs.org](https://nodejs.org/)
وأعد فتح PowerShell.

ثبت Wrangler:

```powershell
npm install --global wrangler
wrangler --version
wrangler login
wrangler whoami
```

أمر `wrangler login` هيفتح المتصفح ويطلب موافقتك على ربط الأداة بحسابك.
ارجع لـPowerShell بعد نجاح تسجيل الدخول. `wrangler whoami` لازم يبين الحساب
الصح. ما تشاركش access token.

**Checkpoint:** نسخة البناء موجودة، وWrangler مسجل دخول على الحساب اللي عليه
المشروع.

## 8 — ارفع AZKAR

لازم تكون موافق على Direct Upload، والمشروع اتعمل يدوياً وموجود بالفعل. في
نفس نافذة PowerShell:

```powershell
$env:CLOUDFLARE_PAGES_PROJECT_NAME = "اسم-المشروع-الحقيقي"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy_cloudflare.ps1
```

السكربت هيعرض اسم المشروع والبيئة `production`، ويتأكد من تسجيل دخول Wrangler
ووجود المشروع ومجلد build. بعد كده هيطلب تكتب حرفياً:

```text
DEPLOY PRODUCTION
```

لو مش موافق، اكتب أي حاجة تانية؛ مش هيتم رفع ملفات. بعد التأكيد، هيشغل
`wrangler pages deploy build\web --project-name <اسم-المشروع>`.

**النتيجة المتوقعة:** Wrangler يعرض نجاح الرفع ورابط deployment. لو ظهر خطأ
مش واضح، احتفظ برسالة الخطأ من غير ما تعرض أي ملف إعدادات أو مفاتيح.

## 9 — هات رابط الموقع

1. ارجع لـCloudflare Dashboard.
2. افتح **Workers & Pages** ثم مشروع AZKAR.
3. افتح **Deployments** أو **Overview**.
4. انسخ رابط Production اللي Cloudflare عرضه. الـhostname قد يكون فيه لاحقة
   مختلفة لو الاسم اللي اخترته غير متاح؛ استخدم الرابط المعروض مش التخمين.

## 10 — اضبط الرابط العام

`PUBLIC_BASE_URL` لازم يساوي رابط Production النهائي، لأن AZKAR بيستخدمه في
روابط الصفحات ومشاركة الرابط وروابط استعادة كلمة المرور والـmetadata.

لو اكتشفت إن hostname اتغير:

1. عدّل `PUBLIC_BASE_URL` في `config/production.json`.
2. أعد `scripts\build_web_production.ps1`.
3. راجع الـpreview المحلي.
4. أعد النشر بعد التأكيد.

يعني ما فيش دائرة مغلقة: اعمل المشروع يدوي بعد الموافقة، خد الرابط منه، حطه
في الإعداد، ابنِ الملفات، وبعدها ارفعها.

## 11 — اختبر الصفحة الرئيسية

افتح رابط Production في نافذة خاصة:

1. اتأكد إن المتصفح بيعرض HTTPS وقفل الأمان.
2. اتأكد إن عنوان AZKAR والهوية والخط العربي ظاهرين.
3. افتح Developer Tools → **Console** و**Network** وشوف هل فيه أخطاء تحميل.
4. تأكد إن تسجيل الدخول والتصفح ما بيطلبوش حساب لمحتوى الموقع العام.

## 12 — اختبر صفحة تذكارية منشورة

استخدم slug حقيقي لصفحة اختبرها صاحبها وفعّل نشرها. الرابط بالشكل:

```text
https://اسم-المشروع.pages.dev/m/slug-منشور
```

ما تستخدمش صفحة خاصة أو slug عشوائي كاختبار بيانات. لو الصفحة منشورة، المفروض
تظهر محتوياتها المسموح بها بدون تسجيل دخول.

## 13 — اختبر الرابط من جلسة جديدة

انسخ رابط `/m/slug` وافتحه في نافذة خاصة أو متصفح تاني من غير تسجيل الدخول.
اضغط Refresh بعد ما الصفحة تظهر. لازم المسار يفضل `/m/slug`، وما يتحولش
لصفحة login أو Cloudflare 404. كرر مع `/login` و`/register`.

## 14 — اختبر مشاركة WhatsApp

1. من الصفحة المنشورة اختار مشاركة أو نسخ الرابط.
2. ابعت الرابط لنفسك أو جهاز تاني تملكه.
3. افتحه من WhatsApp وتأكد إنه رابط hostname الرسمي مش localhost أو عنوان
   emulator.
4. ممكن تظهر معاينة عامة للشعار والوصف بدل عنوان صفحة التذكار؛ ده متوقع لأن
   الموقع Flutter client-rendered، والمعاينة الديناميكية اختيار مستقبلي.

## 15 — تحديث الموقع بعدين

بعد تغيير الكود:

1. راجع الملفات والتغييرات.
2. شغّل `flutter analyze` و`flutter test`.
3. شغّل سكربت بناء الإنتاج.
4. اختبر محلياً بالأوامر الموجودة في قسم الاستكشاف.
5. شغّل سكربت النشر واكتب تأكيد الإنتاج بعد مراجعة اسم المشروع.

كل رفع جديد deployment جديد. لو ظهر خطأ، افتح صفحة **Deployments** واستخدم
النسخة السابقة المعروفة السليمة. الرجوع لملفات الويب لا يرجع بيانات Supabase.

## 16 — حل المشاكل

| المشكلة | جرّب إيه |
|---|---|
| 404 عند فتح `/m/slug` مباشرة | تأكد إن `build\web` هو مجلد الرفع ومافيش `404.html` في جذره. |
| صفحة بيضاء | افتح Console/Network، وتأكد من `index.html` و`flutter_bootstrap.js` وتحميل ملفات assets. |
| رسالة إعداد Supabase ناقص | راجع ملف الإنتاج محلياً واسم المفتاح، من غير ما تطبعه أو تبعته. |
| CORS أو تسجيل الدخول بيرجع خطأ | راجع Supabase Auth URL Configuration وروابط redirect للـhostname النهائي. ما توسعش RLS. |
| رابط المشاركة localhost أو غلط | راجع `PUBLIC_BASE_URL`، وبعدها اعمل build ونشر جديد. |
| خطوط أو صور مش ظاهرة | تأكد إن الملفات موجودة بمجلد `build\web` وإنه مفيش redirect للملفات الثابتة. |
| Wrangler مش مسجل دخول | نفذ `wrangler login` ثم `wrangler whoami` بالحساب الصحيح. |
| المشروع مش ظاهر في Wrangler | راجع الاسم والحساب ووضع Direct Upload؛ ما تعملش مشروع تاني تلقائياً. |
| التحديث القديم لسه ظاهر | راجع رابط deployment والنافذة الخاصة؛ Pages عنده كاش افتراضي، ما تضفش قواعد كاش عشوائية. |
| معاينة WhatsApp عامة | طبيعي حالياً؛ معاينات الصفحات الفردية server-side مش مفعلة. |
| build بيرفض `AZKAR_AUTH_SCHEMA_VERIFIED` | ده مقصود لحد ما مراجعة المخطط وسياسات RLS واختبارات القبول تخلص. |

للتجربة المحلية المشابهة لـPages، بعد build:

```powershell
wrangler pages dev build\web --port 8788
```

سيب النافذة مفتوحة وافتح `http://localhost:8788/` ثم جرّب المسارات المباشرة.
ده اختبار محلي، مش دليل إن نشر Cloudflare الحقيقي نجح.

## 17 — حدود الخطة المجانية

حسب [صفحة حدود Cloudflare Pages الرسمية](https://developers.cloudflare.com/pages/platform/limits/)،
تتضمن الحدود المنشورة للخطة المجانية حالياً 500 Git builds بالشهر وبناء واحد
متزامن، وحتى 20,000 ملف للموقع، وحجم أقصى 25 MiB للملف الواحد، وحتى 100
custom domains للمشروع. الرفع المباشر بيعمل build على جهازك وما بيشغّلش
Cloudflare build لكل رفع. Pages Functions بتستخدم حصص Workers. الأرقام ممكن
تتغير؛ راجع الرابط الرسمي قبل الاعتماد عليها.

## 18 — دومين خاص (اختياري)

ممكن بعدين تربط دومين تملكه من صفحة مشروع Pages عبر **Custom domains**. شراء
دومين مش مطلوب لاستخدام `pages.dev`. بعد الربط والتحقق من DNS/HTTPS، عدّل
`PUBLIC_BASE_URL` للدومين الجديد واعمل build ونشر جديد. راجع إعدادات Supabase
Auth redirects كمان. ما تشتريش دومين إلا لو حابب تعمل ده.
