"""Adds the permissions FastGet needs to the generated AndroidManifest.xml."""
import re
import sys

PATH = "android/app/src/main/AndroidManifest.xml"

PERMS = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.MANAGE_EXTERNAL_STORAGE",
    "android.permission.POST_NOTIFICATIONS",
]

with open(PATH, encoding="utf-8") as f:
    xml = f.read()

add = ""
for p in PERMS:
    if p not in xml:
        add += f'    <uses-permission android:name="{p}"/>\n'

if "<application" not in xml:
    sys.exit("AndroidManifest.xml has no <application> tag")

xml = xml.replace("<application", add + "    <application", 1)

# http:// লিংকও কাজ করবে, আর পুরোনো স্টোরেজ মডেল চলবে
if "usesCleartextTraffic" not in xml:
    xml = xml.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
if "requestLegacyExternalStorage" not in xml:
    xml = xml.replace("<application", '<application android:requestLegacyExternalStorage="true"', 1)

# অ্যাপের নাম
xml = re.sub(r'android:label="[^"]*"', 'android:label="DROX"', xml, count=1)

# Accept "Share" of text/links from other apps into the main activity.
if "android.intent.action.SEND" not in xml:
    share_filter = (
        "        <intent-filter>\n"
        '            <action android:name="android.intent.action.SEND"/>\n'
        '            <category android:name="android.intent.category.DEFAULT"/>\n'
        '            <data android:mimeType="text/plain"/>\n'
        "        </intent-filter>\n"
    )
    if "</activity>" not in xml:
        sys.exit("AndroidManifest.xml has no </activity> tag")
    xml = xml.replace("</activity>", share_filter + "    </activity>", 1)

with open(PATH, "w", encoding="utf-8") as f:
    f.write(xml)

# Install our MainActivity (share receiver) over the generated one.
import glob
found = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
if not found:
    sys.exit("generated MainActivity.kt not found")
target = found[0]
with open(target, encoding="utf-8") as f:
    pkg = re.search(r"^package\s+([\w.]+)", f.read(), re.M).group(1)
with open("tool/MainActivity.kt.tpl", encoding="utf-8") as f:
    kt = f.read().replace("__PACKAGE__", pkg)
with open(target, "w", encoding="utf-8") as f:
    f.write(kt)

print("Manifest patched, MainActivity installed for package", pkg)
