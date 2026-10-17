إعداد التحديث الإجباري لتطبيق أذكار مسلم

1) نفّذ flutter pub get.
2) افتح Firebase Console للمشروع walied-f4f1b ثم Realtime Database.
3) أنشئ عقدة باسم app_update بالقيم الموجودة في update_config.example.json.
4) استبدل apkUrl برابط HTTPS مباشر لملف APK المنشور فعلًا.
5) ارفع إصدار التطبيق الجديد مع زيادة version في pubspec.yaml، مثال: version: 1.0.1+2.
6) اجعل latestVersion هو الإصدار المنشور. اجعل minVersion أقل إصدار مسموح له بالعمل. لفرض التحديث على كل إصدار أقدم، ضع minVersion على الإصدار الجديد و forceUpdate على true.
7) يجب السماح بقراءة العقدة app_update من التطبيق عبر Firebase Realtime Database Rules. لا تجعل قاعدة البيانات كلها قابلة للكتابة العامة. استخدم قواعد محدودة وآمنة؛ هذا المشروع يقرأ /app_update.json عبر REST.
8) ملف google-services.json وحده لا ينشئ إعدادات قاعدة البيانات ولا يضيف رابط APK. الاتصال المستخدم هنا عبر Firebase Realtime Database REST URL.

شكل البيانات:
{
  "latestVersion": "1.0.1",
  "minVersion": "1.0.1",
  "forceUpdate": true,
  "apkUrl": "https://YOUR-DOMAIN.example/azkar-muslim.apk",
  "releaseNotes": "تحسينات وإصلاحات"
}

ملاحظات مهمة:
- يجب وضع رابط APK الحقيقي؛ رابط المثال لا يعمل.
- التطبيق يمنع تجاوز شاشة التحديث داخل التطبيق، لكنه لا يستطيع منع المستخدم من إغلاق التطبيق أو تثبيت نسخة أخرى يدويًا.
- إذا تعذر الوصول إلى Firebase أو لم تكن عقدة app_update موجودة، تظهر شاشة إعادة المحاولة بدل فتح التطبيق، لأن وضع التحديث الإجباري لا يمكن التحقق منه.
- لم يتم اختبار البناء داخل KlenCode IDE في هذه البيئة.
