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
xml = re.sub(r'android:label="[^"]*"', 'android:label="FastGet"', xml, count=1)

with open(PATH, "w", encoding="utf-8") as f:
    f.write(xml)

print("Manifest patched")
