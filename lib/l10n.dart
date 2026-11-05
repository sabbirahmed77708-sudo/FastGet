import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App language. English is the default; Bengali is selectable in the menu.
/// Strings are written in English in the code and translated through [tr].
class L10n extends ChangeNotifier {
  L10n._();
  static final L10n instance = L10n._();

  String code = 'en'; // 'en' | 'bn'
  bool get isBn => code == 'bn';

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    code = p.getString('lang') ?? 'en';
  }

  Future<void> setLanguage(String c) async {
    if (c == code) return;
    code = c;
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', c);
    notifyListeners();
  }
}

/// Translate an English UI string. Unknown strings stay in English.
String tr(String en) {
  if (!L10n.instance.isBn) return en;
  return _bn[en] ?? en;
}

/// "50 MB of 1.4 GB" / "50 MB / 1.4 GB"
String trOf(String a, String b) => L10n.instance.isBn ? '$a / $b' : '$a of $b';

/// `const`-friendly translated text.
class T extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  const T(this.text,
      {super.key, this.style, this.maxLines, this.overflow, this.textAlign});

  @override
  Widget build(BuildContext context) => Text(
        tr(text),
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
}

const Map<String, String> _bn = {
  "Can't open this page": 'পেজটি খোলা যাচ্ছে না',
  'checking…': 'চেক করা হচ্ছে…',
  'size unknown': 'সাইজ অজানা',
  'Wi-Fi only is on': 'শুধু ওয়াই-ফাই চালু',
  'Wi-Fi only is off': 'শুধু ওয়াই-ফাই বন্ধ',
  // --- app menu / settings / about
  'Redownload': 'আবার ডাউনলোড',
  'Wi-Fi only': 'শুধু ওয়াই-ফাই',
  'Download only when connected to Wi-Fi': 'শুধু ওয়াই-ফাই সংযোগে ডাউনলোড হবে',
  'Night mode': 'নাইট মোড',
  'Light mode': 'লাইট মোড',
  'Language': 'ভাষা',
  'Choose language': 'ভাষা বাছাই করুন',
  'About': 'সম্পর্কে',
  'Exit': 'বের হন',
  'Version': 'সংস্করণ',
  'Download folder': 'ডাউনলোড ফোল্ডার',
  'Browser settings': 'ব্রাউজার সেটিংস',
  'Downloads': 'ডাউনলোড',
  'Waiting for Wi-Fi': 'ওয়াই-ফাইয়ের অপেক্ষায়',
  'Paused': 'পজড',
  'Completed': 'সম্পন্ন',
  'Loading…': 'লোড হচ্ছে…',
  'Redownload this file?': 'ফাইলটি আবার ডাউনলোড করবেন?',
  'The partial or finished file will be deleted and downloaded again.':
      'আংশিক বা সম্পূর্ণ ফাইলটি মুছে নতুন করে ডাউনলোড হবে।',
  'Fast download manager with a built-in browser.':
      'বিল্ট-ইন ব্রাউজারসহ দ্রুত ডাউনলোড ম্যানেজার।',
  // --- error messages
  'Enter a valid http/https link': 'সঠিক http/https লিংক দিন',
  'This link opens a web page, not a downloadable file':
      'এই লিংক একটি ওয়েবপেজ খোলে, ডাউনলোডযোগ্য ফাইল নয়',
  'YouTube links are not supported. Use YouTube Premium for offline videos.':
      'ইউটিউব লিংক সাপোর্ট করা হয় না। অফলাইন ভিডিওর জন্য YouTube Premium ব্যবহার করুন।',
  'No internet connection or server unreachable':
      'ইন্টারনেট সংযোগ নেই বা সার্ভারে পৌঁছানো যাচ্ছে না',
  'Connection timed out': 'সংযোগে টাইমআউট হয়েছে',
  'Unknown error': 'অজানা সমস্যা',
  // --- browser menu
  'Menu': 'মেনু',
  'Back': 'পেছনে',
  'Forward': 'সামনে',
  'Bookmark': 'বুকমার্ক',
  'Refresh': 'রিফ্রেশ',
  'Settings': 'সেটিংস',
  'New Tab': 'নতুন ট্যাব',
  'Block Ads': 'বিজ্ঞাপন ব্লক',
  'Capture Audio/Video': 'অডিও/ভিডিও ক্যাপচার',
  'View Page Resources': 'পেজ রিসোর্স দেখুন',
  'History': 'ইতিহাস',
  'Find in Page': 'পেজে খুঁজুন',
  'Desktop Mode': 'ডেস্কটপ মোড',
  'Clear Browsing Data': 'ব্রাউজিং ডেটা মুছুন',
  'Return to DROM': 'DROM-এ ফিরুন',
  'About DROM': 'DROM সম্পর্কে',
  // --- browser screen
  'Added to DROM downloads': 'DROM ডাউনলোডে যোগ হয়েছে',
  'View': 'দেখুন',
  'Search or type a URL': 'সার্চ করুন বা লিংক লিখুন',
  'Stop': 'থামান',
  'Find in page': 'পেজে খুঁজুন',
  'Previous': 'আগেরটা',
  'Next': 'পরেরটা',
  'Close': 'বন্ধ করুন',
  'New tab': 'নতুন ট্যাব',
  // --- download prompt
  'File': 'ফাইল',
  'DROM Download': 'DROM ডাউনলোড',
  'This server does not support fast multi-part download or resume.':
      'এই সার্ভার দ্রুত মাল্টি-পার্ট ডাউনলোড বা রিজিউম সাপোর্ট করে না।',
  'This link returns a web page, not a downloadable file.':
      'এই লিংক একটি ওয়েবপেজ দেখাচ্ছে, ডাউনলোডযোগ্য ফাইল নয়।',
  'Cancel': 'বাতিল',
  'Download': 'ডাউনলোড',
  // --- browser home
  'Add shortcut': 'শর্টকাট যোগ করুন',
  'Name': 'নাম',
  'Website address': 'ওয়েবসাইটের ঠিকানা',
  'Add': 'যোগ করুন',
  'Fast. Private. Yours.': 'দ্রুত। ব্যক্তিগত। আপনার।',
  'Search': 'সার্চ',
  'Remove': 'সরান',
  // --- sheets / settings
  'Page resources': 'পেজ রিসোর্স',
  'No resources were recorded for this page yet.':
      'এই পেজের কোনো রিসোর্স এখনো রেকর্ড হয়নি।',
  'Audio / video on this page': 'এই পেজের অডিও / ভিডিও',
  'No direct media files found on this page.':
      'এই পেজে সরাসরি মিডিয়া ফাইল পাওয়া যায়নি।',
  'Filter': 'ফিল্টার',
  'Link copied': 'লিংক কপি হয়েছে',
  'Download with DROM': 'DROM দিয়ে ডাউনলোড',
  'Clear history': 'ইতিহাস মুছুন',
  'Clear history?': 'ইতিহাস মুছবেন?',
  'Clear': 'মুছুন',
  'Bookmarks': 'বুকমার্ক',
  'No history yet': 'এখনো কোনো ইতিহাস নেই',
  'No bookmarks yet': 'এখনো কোনো বুকমার্ক নেই',
  'Block ads': 'বিজ্ঞাপন ব্লক করুন',
  'Blocks common ad and tracker domains':
      'পরিচিত বিজ্ঞাপন ও ট্র্যাকার ডোমেইন ব্লক করে',
  'Desktop mode': 'ডেস্কটপ মোড',
  'Request the desktop version of sites': 'সাইটের ডেস্কটপ সংস্করণ চান',
  'Capture audio / video': 'অডিও / ভিডিও ক্যাপচার',
  'Lists direct media files found on a page':
      'পেজে পাওয়া সরাসরি মিডিয়া ফাইলের তালিকা দেখায়',
  'Theme': 'থিম',
  'System': 'সিস্টেম',
  'Light': 'লাইট',
  'Dark': 'ডার্ক',
  'Clear browsing data': 'ব্রাউজিং ডেটা মুছুন',
  'History, cache, cookies and site data': 'ইতিহাস, ক্যাশ, কুকি ও সাইটের ডেটা',
  'Clear browsing data?': 'ব্রাউজিং ডেটা মুছবেন?',
  'This removes history, cache, cookies and saved site data. ':
      'এতে ইতিহাস, ক্যাশ, কুকি ও সংরক্ষিত সাইট ডেটা মুছে যাবে। ',
  'You will be signed out of websites.':
      'ওয়েবসাইট থেকে আপনি সাইন আউট হয়ে যাবেন।',
  'Browsing data cleared': 'ব্রাউজিং ডেটা মুছে ফেলা হয়েছে',
  'The page could not be loaded': 'পেজটি লোড করা যায়নি',
  'Try again': 'আবার চেষ্টা করুন',
  // --- tabs drawer
  'No matching tabs': 'মিলে এমন কোনো ট্যাব নেই',
  'Search tabs': 'ট্যাব খুঁজুন',
  'Tabs': 'ট্যাব',
  'Home': 'হোম',
  'Homepage': 'হোমপেজ',
  'Close tab': 'ট্যাব বন্ধ করুন',
  // --- downloads screen
  'New download': 'নতুন ডাউনলোড',
  'Paste a direct link to a file': 'ফাইলের সরাসরি লিংক পেস্ট করুন',
  'Paste': 'পেস্ট',
  'Start download': 'ডাউনলোড শুরু করুন',
  'Copy link': 'লিংক কপি',
  'Remove from list': 'তালিকা থেকে সরান',
  'Delete file too': 'ফাইলসহ মুছুন',
  'Browser': 'ব্রাউজার',
  'Add link': 'লিংক যোগ করুন',
  'Current speed': 'বর্তমান স্পিড',
  'Active': 'চলছে',
  'Done': 'শেষ',
  'All': 'সব',
  'No downloads here': 'এখানে কোনো ডাউনলোড নেই',
  'Tap "Add link" to paste a file URL,\nor use the browser to find files.':
      'ফাইলের লিংক পেস্ট করতে "লিংক যোগ করুন" চাপুন,\nঅথবা ব্রাউজার দিয়ে ফাইল খুঁজুন।',
  'Failed': 'ব্যর্থ',
  'Open': 'খুলুন',
  'Pause': 'পজ',
  'Retry': 'আবার চেষ্টা',
  'Resume': 'রিজিউম',
  'More': 'আরও',
  'Single stream · no resume': 'সিঙ্গেল স্ট্রিম · রিজিউম নেই',
  // --- share / about / update / notifications
  'Share app': 'অ্যাপ শেয়ার করুন',
  'Get DROM - a fast download manager with a built-in browser.':
      'DROM নিন - বিল্ট-ইন ব্রাউজারসহ দ্রুত ডাউনলোড ম্যানেজার।',
  'Check for update': 'আপডেট চেক করুন',
  'Checking for updates…': 'আপডেট চেক করা হচ্ছে…',
  'You are up to date': 'আপনার অ্যাপ সর্বশেষ ভার্সনে আছে',
  'New version available': 'নতুন আপডেট এসেছে',
  'Download update': 'আপডেট ডাউনলোড করুন',
  'Could not check for updates': 'আপডেট চেক করা যায়নি',
  'Update added to downloads. Open it when it finishes to install.':
      'আপডেট ডাউনলোডে যোগ হয়েছে। শেষ হলে খুলে ইনস্টল করুন।',
  'Pause all': 'সব পজ',
  'Resume all': 'সব রিজিউম',
  'Download complete': 'ডাউনলোড সম্পূর্ণ',
  'Download failed': 'ডাউনলোড ব্যর্থ',
  'New update': 'নতুন আপডেট',
};
