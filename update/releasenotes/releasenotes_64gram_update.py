import re
import sys
import shutil
import requests
from pathlib import Path
from ruamel.yaml import YAML

target = Path(sys.argv[1])
yaml = YAML(typ='rt')

if (target.is_file() and target.name.endswith(".locale.en-US.yaml")):
    file_path = target
elif target.is_dir():
    file_path = next(target.rglob("*.locale.en-US.yaml"), None)
else:
    raise RuntimeError("Not a file")

print(f"Loading {file_path.name}...")
output = file_path.resolve()
with open(output, "r", encoding="utf-8") as f:
    data = yaml.load(f)
    version = data.get("PackageVersion")

url = f"https://api.github.com/repos/TDesktop-x64/tdesktop/releases"
print(f"Fetching {url}...")
response = requests.get(url, params={"per_page": 100}, timeout=30)
response.raise_for_status()
releases = response.json()

if "--latest-version" in sys.argv:
    if not releases:
        raise RuntimeError("No releases found.")
    latest_release = releases[0]
    new_version = re.sub(r"^v", "", latest_release["tag_name"])
    print(f"Latest version: {new_version}")
    sys.exit()

if "--no-backup" not in sys.argv:
    print(f"Creating backup...")
    shutil.copy2(output, output.with_name(output.name + ".rnbak"))

target_version = f"v{version}"
for release in releases:
    if release.get("tag_name") != target_version:
        continue
    
    notes = release.get("body")
    if notes is None:
        raise RuntimeError(f"No release notes found for {target_version}")
    
    print(f"Found release notes for version {version}:\n'{notes}'")
    print(f"Deleting existing release notes...")
    data.pop("ReleaseNotes", None)
    with open(output, "w", encoding="utf-8") as f:
        yaml.dump(data, f)
    
    print(f"Writing new release notes...")
    with open(output, "a", encoding="utf-8") as f:
        first_line = next((line.strip() for line in notes.splitlines() if line.strip()), "")
        f.write("ReleaseNotes: |-\n")
        f.write(f"  {first_line}\n")
        for note in notes.splitlines():
            note = note.strip()
            if not note or note == first_line:
                continue
            note = re.sub(r"^\d+\.\s+", "", note)
            f.write(f"  - {note}\n")
    print("Done.")
    break
else:
    raise RuntimeError(f"{target_version} was not found.")
