<p align="center"><img src="../assets/rawya-mark.svg" width="160" alt="شعار Rawya"></p>
<h1 align="center">Rawya</h1>
<p align="center">مشغل مجاني ومفتوح المصدر لنظام macOS ينشئ الترجمة النصية ويترجمها تلقائيا.</p>

<p align="center"><a href="../../README.md">English</a> · <a href="README.zh.md">简体中文</a> · <a href="README.zh-hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.pt.md">Português</a> · <a href="README.ru.md">Русский</a> · <strong>العربية</strong></p>

<p align="center"><a href="https://rawya.app/ar/">الموقع</a> · <a href="https://github.com/rawya-ai-player/client-macos/releases/latest">تنزيل</a> · <a href="https://github.com/rawya-ai-player/client-macos/issues">الإبلاغ عن مشكلة</a></p>

## ما هو Rawya؟

Rawya مشغل أصلي لنظام macOS لمن يشاهدون مقاطع فيديو بلغات مختلفة. ينشئ الترجمة النصية من الكلام ثم يترجمها إلى اللغة التي تقرأها.

## أبرز المزايا

- إنشاء الترجمة النصية وترجمتها تلقائيا بلغات متعددة
- عرض الترجمة الجاهزة بينما تستمر معالجة بقية الفيديو
- معالجة الصوت محليا باستخدام ذكاء Apple على أجهزة Mac المدعومة
- تشغيل صيغ الفيديو والصوت الشائعة
- إدارة الترجمة وقوائم التشغيل والفصول وصورة داخل صورة وسجل المشاهدة
- تخصيص الفيديو والصوت والترجمة ولوحة المفاتيح والفأرة ولوحة اللمس والإيماءات

## المتطلبات

- ترجمة Apple AI المحلية: macOS 26 أو أحدث
- التشغيل الأساسي على Apple Silicon: macOS 12 أو أحدث
- التشغيل الأساسي على Intel Mac: macOS 10.15 أو أحدث

## التنزيل

نزّل أحدث ملف DMG من [GitHub Releases](https://github.com/rawya-ai-player/client-macos/releases/latest) ثم انقل Rawya إلى مجلد التطبيقات. الإصدارات المستقرة موقعة بهوية المطور وموثقة من Apple.

## التحديثات

يتحقق Rawya تلقائيا من التحديثات المستقرة مرة واحدة يوميا. يمكنك أيضا اختيار **التحقق من وجود تحديثات…** من قائمة التطبيق في أي وقت. فعّل **تنزيل التحديثات وتثبيتها تلقائيا** من **الإعدادات > عام** لتنزيل التحديثات التي تم التحقق منها في الخلفية وتثبيتها عند إنهاء Rawya.

تستخدم التحديثات التلقائية والتنزيلات اليدوية إصدار GitHub Release المستقر نفسه. ويتضمن كل إصدار مستقر أيضا أرشيف الشفرة المصدرية وملفات التحقق SHA-256.

## البناء محليا

ثبّت أحدث إصدار من Xcode، وشغّل `./other/download_libs.sh`، ثم افتح ملف `.xcodeproj` في Xcode وابن مخطط التطبيق الرئيسي.

## الترخيص

يصدر Rawya بموجب [GNU General Public License v3.0](../../LICENSE). تحتفظ المكونات والموارد الخارجية بتراخيصها الخاصة.
