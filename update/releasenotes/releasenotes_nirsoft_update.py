import re
import sys
import yaml
import shutil
import requests
from pathlib import Path
from bs4 import BeautifulSoup

target = Path(sys.argv[1])

if (target.is_file() and target.name.endswith(".locale.en-US.yaml")):
    file_path = target
elif target.is_dir():
    file_path = next(target.rglob("*.locale.en-US.yaml"), None)
else:
    raise RuntimeError("Not a file")

with open(file_path.resolve(), "r", encoding="utf-8") as f:
    data = yaml.safe_load(f)
    url = data.get("PackageUrl")
    version = data.get("PackageVersion")

shutil.copy2(file_path, file_path.with_name(file_path.name + ".rnbak"))
output = file_path

response = requests.get(url, timeout=30)
response.raise_for_status()
soup = BeautifulSoup(response.text, "html.parser")
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

    with open(output, "a", encoding="utf-8", newline="\n") as file:
        file.write("ReleaseNotes: |-\n")
        file.write(f"  - {target_version}:\n")
        for note in notes.find_all("li", recursive=False):
            text = note.get_text(" ", strip=True)
            file.write(f"    - {text}\n")
    break
else:
    raise RuntimeError(f"{target_version} was not found.")

