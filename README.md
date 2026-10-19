# Kodi tvOS

**Kodi for Apple TV with the Aether player and Dex Hub built in.**
Dolby Vision, HDR10, Dolby Atmos, Arabic subtitles, and the Dex Hub interface in one app.

> **Unofficial build.** Not made or supported by Team Kodi or the XBMC Foundation.
> Kodi® is a registered trademark of the XBMC Foundation.

[English](#english) · [العربية](#بالعربي)

## English

### What it is
A modified Kodi 22 for Apple TV with:
- **Aether 7.40.1** as the default player: Dolby Vision, HDR10 and HLG (source and display permitting), H.264, HEVC and AV1, automatic frame rate matching.
- **Dolby Atmos and DTS:X:** E-AC-3 JOC automatically. TrueHD Atmos and DTS:X keep their heights: they are rendered to Apple spatial audio (APAC) and output as Dolby MAT, at 7.1.4 by default, or your own speaker layout picked in settings (5.1.2 to 9.1.6, or off for the lossless 7.1). This is not raw TrueHD or DTS passthrough. Needs tvOS 26.
- **Three ways to play:** Aether, Kodi's own player, or an external app (Infuse, VidHub, SenPlayer, VLC, Native Player, Outplayer or nPlayer) with resume and subtitle hand-off where the app takes them.
- **Dex Hub add-on and skin** installed on first launch, with Arabic subtitle fonts.
- **Performance:** Release build; the interface runs in the Apple TV's own mode (60 Hz).
- **Set up from your phone.** tvOS has no file browser and typing with the remote is slow, so Dex Hub shows a QR code on the TV. Scan it and a page opens on your phone (same Wi‑Fi) where you link accounts (Nuvio, Trakt, Stremio, Plex, Emby, Jellyfin, IPTV), pick the Home layout, arrange rows, choose one of 28 themes and the language, and move files both ways: add-on ZIPs, subtitles, fonts, backups and restores. Every change reaches the TV right away.

### Requirements
- Apple TV 4K on **tvOS 26** or later.
- To install: a signing tool and an Apple account (see below).
- To build from source only: an Apple Silicon Mac with Xcode 26 or later and at least 20 GB free.

### ⚠️ The app must be signed
The IPA on the Releases page is **unsigned**. Apple TV will not install an unsigned app, so you sign it yourself before installing:

1. Download `Kodi-DexHub-AetherOnly-*-unsigned.ipa` from [Releases](../../releases).
2. Sign it with an Apple TV capable signing tool (Sideloadly or whatever you use) and an Apple account:
   - **Free Apple account:** the signature expires after 7 days; sign again.
   - **Paid developer account:** valid for a year.
3. **Sign the whole app including the Frameworks folder.** It carries the Aether and FFmpeg libraries; one unsigned library stops the install.
4. To update an installed copy and keep its data, use the same bundle ID and account.

**If you get** `ApplicationVerificationFailed ... invalid signature` on an `Aether*.framework`, run on a Mac:
```bash
bash FIX-SIGNING.command /path/to/file.ipa
```
Sign and install the `-fixed.ipa` it writes. Builds from v20 on do this already.

### Repository layout
| Path | What |
|---|---|
| `src/plugin.video.dexhub.tvos` | Dex Hub add-on for Apple TV (5.10.342) |
| `src/skin.dexhub.tvos` | Dex Hub skin for Apple TV (3.28.79) |
| `native/`, `apply_bridge.py`, `native_player_adapter.py` | Kodi source changes |
| `DexAetherEmbedded.swift` | Swift bridge between Kodi and Aether |
| `script.dexhub.tvos.players`, `script.module.dexhub.tvos.compat` | player choice and tvOS compatibility add-ons |
| `assets/` | third-party add-ons bundled in the app |
| `tests/` | Linux tests for the scripts and add-on parts |

### Update source and playback performance

The bundled repository is `repository.dexworld.appletv` 1.0.2 at
https://dexworld.cc/appletv/. On an app upgrade the player service enables it
and disables the old `repository.dexhub` only when it points to the former
`https://dexworld.cc/dexhub/` source. Existing newer add-ons and user settings
are retained. `DEX_REPO_URL` can override the bundled source for a private fork.

Aether 7.40.1 is pinned with LibTrueHD/LibDTSX 3.0.0. The build explicitly enables
its `TrueHDObjectAudio` and `DTSXObjectAudio` traits. Subtitle snapshots use a
binary index over the retained cues instead of scanning the entire subtitle
file every 100 ms. This reduces subtitle work without changing cue timing.

### Build from source (Mac)
First time on a Mac (downloads Kodi 22 RC1 and builds its dependencies once; this takes a while):
```bash
git clone https://github.com/6ahd/Kodi-tvOS.git ~/Developer/DexHub-tvOS/DexHub-tvOS
bash ~/Developer/DexHub-tvOS/DexHub-tvOS/update-kodi.sh 22.0rc1-Piers
```
Every build after that:
```bash
bash ~/Developer/DexHub-tvOS/DexHub-tvOS/BUILD.command
```
The unsigned IPA lands in Downloads; sign it as above.

The build pins Aether 7.40.1 (commit `93d54e5`) and its packages, builds the small Swift bridge, applies the Kodi changes in `native/` through `apply_bridge.py` (with a backup and `--restore`), builds Kodi in Release, bundles the add-ons in `assets/`, prepares the frameworks for signing and writes the IPA. The Dex Hub add-on and skin are built from their source in `src/` by `release_assets.py` (if `src/` is missing, `get-dexhub.sh` downloads them from the Apple TV repository).

### Licence
- Build scripts, Kodi changes and the Aether bridge in this repository: **GPL-2.0-or-later**, © 2026 DexWorld.
- **The Dex Hub add-on and skin in `src/` are not covered by this licence.** Their source is published so you can read and build it, under their own licences: `src/plugin.video.dexhub.tvos/LICENSE.txt` (proprietary, source available: redistributing, modifying, rebranding or selling it needs written permission) and the skin's licence files (Estuary GPL-2.0, Arctic Fuse 3 CC BY-NC-SA 4.0).
- Other components keep their own licences; see [NOTICE.md](NOTICE.md).

---

## بالعربي

### ما هو
تطبيق Kodi 22 معدّل لـ Apple TV، فيه:
- **مشغل Aether 7.40.1** افتراضي: Dolby Vision وHDR10 وHLG حسب المصدر والشاشة، H.264 وHEVC وAV1، ومطابقة معدل الإطارات تلقائيا.
- **Dolby Atmos وDTS:X:** صيغة E-AC-3 JOC تلقائيا. صيغتا TrueHD Atmos وDTS:X تحتفظان بالقنوات العلوية: تتحولان إلى صوت مكاني (APAC) يخرج كـ Dolby MAT، على 7.1.4 افتراضيا، أو توزيع سماعاتك من الإعدادات (5.1.2 إلى 9.1.6، أو إيقاف للـ 7.1 بدون ضغط). هذا ليس تمرير TrueHD أو DTS خام. يحتاج tvOS 26.
- **ثلاثة خيارات تشغيل:** Aether، ومشغل Kodi الأصلي، أو تطبيق خارجي (Infuse، VidHub، SenPlayer، VLC، Native Player، Outplayer أو nPlayer) مع تمرير الوقت والترجمة للتطبيقات اللي تقبلها.
- **إضافة Dex Hub وسكين Dex Hub** مثبتة داخل التطبيق من أول تشغيل، مع خطوط عربية للترجمة.
- **أداء:** بناء Release، والواجهة على معدل Apple TV نفسه (60Hz).
- **الإعداد من الجوال.** Apple TV ما فيه متصفح ملفات، والكتابة بالريموت بطيئة، فـ Dex Hub يعرض رمز QR على التلفزيون. امسحه وتفتح صفحة على جوالك (نفس شبكة الواي فاي) تربط منها الحسابات (Nuvio وTrakt وStremio وPlex وEmby وJellyfin وIPTV)، وتختار شكل الرئيسية، وترتب الصفوف، وتختار من 28 ثيم واللغة، وتنقل الملفات بالاتجاهين: إضافات ZIP والترجمات والخطوط والنسخ الاحتياطية والاسترجاع. أي تغيير يوصل التلفزيون فورا.

### المتطلبات
- Apple TV 4K بنظام **tvOS 26** أو أحدث.
- للتثبيت: أداة توقيع وحساب Apple (تفاصيلها تحت).
- للبناء من السورس فقط: ماك Apple Silicon مع Xcode 26 أو أحدث، و20 GB مساحة فاضية على الأقل.

### ⚠️ التطبيق يحتاج توقيع
ملف IPA في صفحة Releases **غير موقّع**. Apple TV لا يقبل تثبيت تطبيق غير موقّع، فلازم توقّعه أنت بحسابك قبل التثبيت:

1. حمّل `Kodi-DexHub-AetherOnly-*-unsigned.ipa` من [Releases](../../releases).
2. وقّعه بأداة توقيع تدعم Apple TV، مثل Sideloadly أو أي أداة تستخدمها، بحساب Apple:
   - **حساب Apple مجاني:** التوقيع ينتهي بعد 7 أيام وتعيد التوقيع.
   - **حساب مطوّر مدفوع:** التوقيع سنة كاملة.
3. **وقّع التطبيق كامل مع مجلد Frameworks.** فيه مكتبات Aether وFFmpeg، وأي مكتبة غير موقّعة توقف التثبيت.
4. لتحديث نسخة مثبتة بدون ما تفقد بياناتك، استخدم نفس معرّف التطبيق (Bundle ID) ونفس الحساب.

**لو ظهر خطأ** `ApplicationVerificationFailed ... invalid signature` على أحد ملفات `Aether*.framework`، شغّل على الماك:
```bash
bash FIX-SIGNING.command /path/to/file.ipa
```
يطلع ملف جديد ينتهي بـ `-fixed.ipa`، وقّعه وثبّته. الإصدارات من v20 فما فوق تطلع جاهزة بدون هذه الخطوة.

### محتوى المستودع
| المسار | المحتوى |
|---|---|
| `src/plugin.video.dexhub.tvos` | إضافة Dex Hub لـ Apple TV (5.10.342) |
| `src/skin.dexhub.tvos` | سكين Dex Hub لـ Apple TV (3.28.79) |
| `native/` و`apply_bridge.py` و`native_player_adapter.py` | تعديلات سورس Kodi |
| `DexAetherEmbedded.swift` | جسر Swift بين Kodi وAether |
| `script.dexhub.tvos.players` و`script.module.dexhub.tvos.compat` | اختيار المشغل وتوافق tvOS |
| `assets/` | إضافات خارجية مضمّنة في التطبيق |
| `tests/` | اختبارات Linux للسكربتات والإضافة |

### البناء من السورس (ماك)
أول مرة على الماك (ينزل Kodi 22 RC1 ويبني اعتمادياته مرة واحدة، ويطول):
```bash
git clone https://github.com/6ahd/Kodi-tvOS.git ~/Developer/DexHub-tvOS/DexHub-tvOS
bash ~/Developer/DexHub-tvOS/DexHub-tvOS/update-kodi.sh 22.0rc1-Piers
```
بعدها أي بناء جديد:
```bash
bash ~/Developer/DexHub-tvOS/DexHub-tvOS/BUILD.command
```
الناتج في Downloads باسم `Kodi-DexHub-AetherOnly-v21.42-TEST-unsigned-<وقت>.ipa`، ثم وقّعه كما فوق.

ما يسويه البناء:
1. ينزل محرك Aether 7.40.1 ويثبت إصدارات مكتباته (FFmpegBuild وLibDovi وLibTrueHD وLibDTSX وSMBClient).
2. يبني جسر Swift صغير (`DexAetherEmbedded.swift`) يربط Aether بـ Kodi.
3. يطبّق تعديلات Kodi من مجلد `native/` عبر `apply_bridge.py`، مع نسخة احتياطية، ويقدر يرجعها.
4. يبني Kodi بوضع Release، ويضيف الإضافات من `assets/`، ويجهّز المكتبات للتوقيع، ثم يطلع IPA.

إضافة Dex Hub والسكين يتبنون من السورس في `src/` عن طريق `release_assets.py`. لو `src/` مو موجود، ينزلهم `get-dexhub.sh` من Releases.

### الحقوق
- سكربتات البناء وتعديلات Kodi وجسر Aether في هذا المستودع: **GPL-2.0-or-later**، © 2026 DexWorld.
- **سورس إضافة Dex Hub والسكين في `src/` ليس ضمن هذا الترخيص.** منشور للقراءة والبناء، ولكل واحد ترخيصه: `src/plugin.video.dexhub.tvos/LICENSE.txt` (ملكية خاصة مع إتاحة السورس: إعادة التوزيع أو التعديل أو تغيير الاسم أو البيع تحتاج إذنا مكتوبا)، وملفات ترخيص السكين (Estuary بترخيص GPL-2.0، وArctic Fuse 3 بترخيص CC BY-NC-SA 4.0).
- المكونات الأخرى لها تراخيصها، والتفاصيل في [NOTICE.md](NOTICE.md).

