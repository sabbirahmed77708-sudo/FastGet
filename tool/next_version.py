"""Works out the app version by itself. Prints  MAJOR.MINOR.PATCH.

  python3 tool/next_version.py BUILD_NUMBER

Starts from the version of the previous release (its title is
"SDM <version> (build N)"; older releases fall back to pubspec.yaml) and looks
at the commit subjects since that release:
  feat!: / fix!: / "BREAKING"  -> major  (1.4.2 -> 2.0.0)
  feat:  / feat(...):          -> minor  (1.4.2 -> 1.5.0)
  anything else                -> patch  (1.4.2 -> 1.4.3)
Needs the gh CLI (GH_TOKEN), GITHUB_REPOSITORY and a full git history."""
import os
import re
import subprocess
import sys


def run(*cmd):
    return subprocess.run(cmd, check=True, text=True,
                          capture_output=True).stdout


def pubspec_version():
    m = re.search(r"^version:\s*(\d+)\.(\d+)\.(\d+)", open("pubspec.yaml").read(),
                  re.M)
    return tuple(int(x) for x in m.groups())


def previous(build):
    repo = os.environ["GITHUB_REPOSITORY"]
    out = run("gh", "api", f"repos/{repo}/releases", "--paginate", "-q",
              '.[] | "\\(.tag_name)\\t\\(.name)"')
    best = None
    for line in out.splitlines():
        tag, _, name = line.partition("\t")
        m = re.fullmatch(r"build-(\d+)", tag)
        if m and int(m.group(1)) < build and (best is None or
                                              int(m.group(1)) > best[0]):
            best = (int(m.group(1)), tag, name)
    return best


def main():
    build = int(sys.argv[1])
    ver, since = pubspec_version(), None
    try:
        prev = previous(build)
    except Exception as e:
        print(f"no release info ({e})", file=sys.stderr)
        prev = None
    if prev:
        _, tag, name = prev
        since = tag
        m = re.search(r"(\d+)\.(\d+)\.(\d+)", name or "")
        if m:
            ver = tuple(int(x) for x in m.groups())
        else:  # old release without a version in its title: keep pubspec's
            since = tag
    rng = f"{since}..HEAD" if since else "HEAD~1..HEAD"
    try:
        subjects = run("git", "log", "--format=%s", rng).splitlines()
    except Exception:
        subjects = run("git", "log", "-1", "--format=%s").splitlines()
    major = any(re.match(r"^\w+(\(.*\))?!:", s) or "BREAKING" in s
                for s in subjects)
    minor = any(re.match(r"^feat(\(.*\))?:", s, re.I) for s in subjects)
    first_versioned = prev and not re.search(r"\d+\.\d+\.\d+", prev[2] or "")
    if first_versioned:
        pass  # first automatic build: keep the current version as it is
    elif major:
        ver = (ver[0] + 1, 0, 0)
    elif minor:
        ver = (ver[0], ver[1] + 1, 0)
    else:
        ver = (ver[0], ver[1], ver[2] + 1)
    print(".".join(map(str, ver)))


if __name__ == "__main__":
    main()
