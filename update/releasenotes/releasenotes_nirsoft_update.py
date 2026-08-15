import re
import sys
import shutil
import requests
from pathlib import Path
from bs4 import BeautifulSoup
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
    url = data.get("PackageUrl")
    version = data.get("PackageVersion")

print(f"Fetching {url}...")
response = requests.get(url, timeout=30)
response.raise_for_status()

print(f"Parsing page...")
soup = BeautifulSoup(response.text, "lxml")
history_heading = soup.find(
    "h4",
    class_="utilsubject",
    string=lambda text: text and text.strip() == "Versions History"
)
if history_heading is None:
    raise RuntimeError("Versions History section was not found.")

history = history_heading.find_next("ul")
if history is None:
    raise RuntimeError("Versions History list was not found.")

if "--latest-version" in sys.argv:
    latest_entry = history.find("li", recursive=False)
    if latest_entry is None:
        raise RuntimeError("No versions found.")
    latest_label = next((text.strip() for text in latest_entry.find_all(string=True, recursive=False)), "")
    new_version = re.sub(r"^Version\s+", "", latest_label).rstrip(":")
    print(f"Latest version: {new_version}")
    sys.exit()

if "--no-backup" not in sys.argv:
    print(f"Creating backup...")
    shutil.copy2(output, output.with_name(output.name + ".rnbak"))

target_version = f"Version {version}"
for entry in history.find_all("li", recursive=False):
    # The text directly inside the outer <li> is the version label.
    label = next((text.strip() for text in entry.find_all(string=True, recursive=False)), "")
    match = re.fullmatch(rf"{re.escape(target_version)}:?", label)
    if not match:
        continue
    
    notes = entry.find("ul", recursive=False)
    if notes is None:
        raise RuntimeError(f"No release notes found for {target_version}")
    
    print(f"Found release notes for version {version}:\n'{' '.join(str(notes or '').split())}'")
    print(f"Deleting existing release notes...")
    data.pop("ReleaseNotes", None)
    with open(output, "w", encoding="utf-8") as f:
        yaml.dump(data, f)
    
    print(f"Writing new release notes...")
    with open(output, "a", encoding="utf-8") as f:
        f.write("ReleaseNotes: |-\n")
        f.write(f"  - {target_version}:\n")
        for note in notes.find_all("li", recursive=False):
            text = re.sub(r"\s+", " ", note.get_text(" ", strip=True))
            f.write(f"    - {text}\n")
    print("Done.")
    break
else:
    raise RuntimeError(f"{target_version} was not found.")

