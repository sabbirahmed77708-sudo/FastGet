# FastGet – ডাউনলোড ম্যানেজার (Android)

ফিচার: মাল্টি-সেগমেন্ট (৪টি সংযোগ) ডাউনলোড, পজ/রিজিউম, অ্যাপ বন্ধ করে খুললেও রিজিউম, নোটিফিকেশনে স্পিড, ব্রাউজার থেকে "Share" করে লিংক পাঠানো।
ডাউনলোড শেষে ফাইল `Downloads/FastGet` ফোল্ডারে সেভ হয়।

## APK বানানোর সহজ উপায় (Android Studio ছাড়া)

1. github.com এ ফ্রি অ্যাকাউন্ট খুলুন, নতুন একটি repository বানান (নাম: FastGet)।
2. এই প্রজেক্টের সব ফাইল (`.github` ফোল্ডারসহ) আপলোড করুন। ফোনে/পিসিতে "Add file → Upload files" ব্যবহার করতে পারেন।
3. repository-র **Actions** ট্যাবে যান। "Build APK" নিজে থেকে চলবে (না চললে "Run workflow" চাপুন)।
4. ৩-৫ মিনিট পর কাজ শেষ হলে ওই run খুলে নিচে **Artifacts → FastGet-debug-apk** ডাউনলোড করুন।
5. zip খুলে `app-debug.apk` ফোনে ইনস্টল করুন (Unknown sources অনুমতি দিতে হবে)।

## Android Studio থাকলে
প্রজেক্ট ফোল্ডার Open করে **Build → Build APK(s)** দিন।

## নোট
- সার্ভার Range সাপোর্ট করলে ৪ ভাগে ডাউনলোড হয় (দ্রুত + রিজিউমযোগ্য); না করলে সিঙ্গেল স্ট্রিমে হয় (রিজিউম হবে না)।
- এটা debug APK। Play Store-এর জন্য signed release build লাগবে।
