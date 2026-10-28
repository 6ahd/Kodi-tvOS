# بيئة البناء على الهارديسك

كل شي يتبني داخل مجلد واحد على الهارديسك الخارجي، وما ينكتب شي على قرص
الماك (حتى الملفات المؤقتة وذاكرة المترجم).

## المكان

`/Volumes/Backup/DexHub-Env`

| المجلد | المحتوى |
|---|---|
| `Kodi-tvOS/` | هذا المستودع (فرع `apple-mode`) |
| `depends/` | اعتماديات Kodi الجاهزة لـ tvOS وأدوات البناء (منقولة من `/Users/Shared/xbmc-depends`) |
| `kodi-src/` | نسخة Kodi 22.0rc1-Piers نظيفة، يُطبّق عليها باتش Dex Hub |
| `base/` | آخر IPA منشور، تُنقل منه باقي الإضافات والخطوط |
| `addons/` | إضافة Dex Hub والسكين لـ Apple TV (`tvos/`) وملفات General اللي تطابقها (`general/`) |
| `build/` | كل نواتج البناء: Kodi وجسر Aether، والسجلات |
| `releases/` | ملفات IPA الجاهزة، مجلد لكل إصدار |

## البناء

```bash
bash /Volumes/Backup/DexHub-Env/Kodi-tvOS/env/build.sh
```

يسوي بالترتيب:
1. يطبّق `native/kodi-22.0rc1-dexhub.patch` على Kodi، ويرسم الأيقونة وشاشة الإطلاق.
2. يبني Kodi بوضع Release لـ Apple TV.
3. يبني جسر Aether (الإصدار في `ENGINE-RELEASE.json`).
4. يشيك مجلد Kodi-General على أحدث إضافة وسكين، ولو فيه أحدث يدمجه في نسخة Apple TV
   (`tools/sync_from_general.py`) مع الحفاظ على تعديلات Apple TV.
5. يجمع IPA غير موقّع (مع آخر إضافة وسكين ومشغلات) في `releases/v<الإصدار>/`، ويفحصه: سلامة الأرشيف،
   اكتمال المكتبات، صحة التواقيع، وإن إضافات Dex Hub مثل ما تبنّت.

أول مرة يطول (يبني Kodi كامل). بعدها يبني اللي تغيّر بس.

## تغيير الإصدار

رقم الإصدار في `ENGINE-RELEASE.json` (`app_version`). الإضافة والسكين يتحدثون
تلقائيا من Kodi-General؛ باقي الإضافات المضمّنة من IPA في `base/` (واحد بس).

## المتطلبات

ماك Apple Silicon مع Xcode 27 أو أحدث، واتصال إنترنت لأول بناء لجسر Aether
(ينزل مكتباته).
