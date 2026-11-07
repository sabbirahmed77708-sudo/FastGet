"""Lets SDM install on older phones (Android 5.0+ / API 21) instead of the
newer minimum the Flutter template picks. Run after `flutter create`.
If a library really needs a newer Android, the build fails loudly (manifest
merger) and this step must be removed."""
import os
import re
import sys

MIN = "21"
for path in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    if not os.path.exists(path):
        continue
    s = open(path, encoding="utf-8").read()
    n = re.sub(r"minSdk(Version)?(\s*=\s*|\s+)flutter\.minSdkVersion",
               lambda m: f"minSdk{m.group(1) or ''}{m.group(2)}{MIN}", s)
    if n == s:
        print("minSdk line not found in", path, "- left unchanged")
    else:
        open(path, "w", encoding="utf-8").write(n)
        print("minSdk set to", MIN, "in", path)
    sys.exit(0)
sys.exit("android/app/build.gradle(.kts) not found")
