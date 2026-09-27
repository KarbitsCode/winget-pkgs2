import re
import os
import sys
import shutil
import requests
import tempfile
import threading
import subprocess
from pathlib import Path
from datetime import datetime
from bs4 import BeautifulSoup
from ruamel.yaml import YAML

yaml = YAML(typ="rt")

def log(message):
    print(message, flush=True)

def inject_context(target):
    target.update({
        k: v
        for k, v in globals().items()
        if not k.startswith("_")
    })

def run_with_stream(*args, **kwargs):
    def pump(stream, collect=None):
        for line in stream:
            print(line, end="")
            if isinstance(collect, list):
                collect.append(line)
    output = []
    command = args[0]
    if isinstance(command, str):
        interpreter = re.search(
            r'(?i)(?:^|&&|\|\||[;&])\s*("[^\"]*python(?:\.exe)?"|\'[^\']*python(?:\.exe)?\'|python(?:\.exe)?|py(?:\.exe)?)(?=\s|$)',
            command,
        )
        if interpreter:
            remainder = command[interpreter.end():]
            if not re.match(r"\s+-u(?:\s|$)", remainder, re.IGNORECASE):
                command = f"{command[:interpreter.end()]} -u{remainder}"
    args = (command, *args[1:])
    proc = subprocess.Popen(
        *args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        shell=True,
        **kwargs,
    )
    t1 = threading.Thread(target=pump, args=(proc.stdout, output))
    t2 = threading.Thread(target=pump, args=(proc.stderr, None))
    t1.start()
    t2.start()
    t1.join()
    t2.join()
    proc.wait()
    if proc.returncode:
        raise subprocess.CalledProcessError(proc.returncode, proc.args)
    return "".join(output)

def run_without_stream(*args, **kwargs):
    proc = subprocess.Popen(
        *args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        shell=True,
        **kwargs,
    )
    output, _ = proc.communicate()
    if proc.returncode:
        raise subprocess.CalledProcessError(proc.returncode, proc.args)
    return output

def load_manifest():
    target = Path([arg for arg in sys.argv if not arg.startswith("-")][1])
    if target.is_file() and target.name.endswith(".yaml"):
        file_paths = [target]
    elif target.is_dir():
        file_paths = sorted(target.rglob("*.yaml"))
        if not file_paths:
            raise RuntimeError("No manifest files were found.")
    else:
        raise RuntimeError("Not a manifest file or directory")
    manifests = {}
    for file_path in file_paths:
        log(f"Loading {file_path.name}...")
        output = file_path.resolve()
        with output.open("r", encoding="utf-8") as file:
            manifests[output] = yaml.load(file)
    return manifests

def get_manifest(manifests, target):
    for path, data in manifests.items():
        if path.name.endswith(f".{target}.yaml"):
            return path, data
    raise RuntimeError(f"No manifest found for {target}")

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
