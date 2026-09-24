import re
import os
import sys
import shutil
import requests
from pathlib import Path
from bs4 import BeautifulSoup
from ruamel.yaml import YAML
    
yaml = YAML(typ="rt")

def log(message):
    print(message, flush=True)

def load_manifest():
    target = Path(sys.argv[1])
    if target.is_file() and target.name.endswith(".locale.en-US.yaml"):
        file_path = target
    elif target.is_dir():
        file_path = next(target.rglob("*.locale.en-US.yaml"), None)
        if file_path is None:
            raise RuntimeError("No .locale.en-US.yaml manifest was found.")
    else:
        raise RuntimeError("Not a manifest file or directory")

    log(f"Loading {file_path.name}...")
    output = file_path.resolve()
    with output.open("r", encoding="utf-8") as file:
        data = yaml.load(file)
    return output, data

def fetch(url, **kwargs):
    log(f"Fetching {url}...")
    if url.startswith("https://api.github.com/"):
        kwargs.setdefault("headers", {}).update({"Authorization": f"Bearer {token}"} if (token := os.getenv("GH_TOKEN")) else {})
        kwargs.setdefault("params", {}).update({"per_page": 100})
    response = requests.get(url, **kwargs)
    response.raise_for_status()
    return response

def asked_latest_version():
    return "--latest-version" in sys.argv

def create_backup(output):
    if "--no-backup" not in sys.argv:
        log("Creating backup...")
        shutil.copy2(output, output.with_name(output.name + ".rnbak"))

def write_release_notes(output, data, notes):
    data.pop("ReleaseNotes", None)
    with output.open("w", encoding="utf-8") as file:
        yaml.dump(data, file)
    with output.open("a", encoding="utf-8") as file:
        file.write("ReleaseNotes: |-\n")
        for note in notes:
            file.write(f"  {note}\n")
