import re
import os
import sys
import time
import json
import atexit
import shutil
import requests
import threading
import subprocess
import importlib.util
from pathlib import Path
from contextlib import contextmanager

submit_q = []
update_results = []

def log(message):
    print(message, flush=True)

@contextmanager
def log_group(title):
    if os.getenv("GITHUB_ACTIONS"):
        log(f"::group::{title}")
    else:
        log(f"--- {title} ---")
    try:
        yield
    finally:
        if os.getenv("GITHUB_ACTIONS"):
            log("::endgroup::")

def write_summary():
    path = os.getenv("GITHUB_STEP_SUMMARY")
    if not path:
        return
    
    updated = sum(item["updates"] > 0 and not item.get("failed") for item in update_results)
    failed = sum(item.get("failed") for item in update_results)
    unchanged = len(update_results) - updated - failed
    lines = [
        "## Automated updater summary\n",
        f"**{updated} updated** · **{unchanged} unchanged** · **{failed} failed**\n",
        "| Updater | Result | Updates | Duration |",
        "| --- | --- | ---: | ---: |",
    ]
    for item in update_results:
        status = "Failed" if item.get("failed") else "Updated" if item["updates"] else "No updates"
        lines.append(f"| {item["name"]} | {status} | {item["updates"]} | {item["duration"]:.1f}s |")
    
    with open(path, "a", encoding="utf-8") as summary:
        summary.write("\n".join(lines) + "\n")
atexit.register(write_summary)

def inject_context(target):
    target.update({
        k: v
        for k, v in globals().items()
        if not k.startswith("__")
    })

def run_with_stream(*args, **kwargs):
    def pump(stream, collect=False):
        for line in stream:
            print(line, end="")
            if collect:
                output.append(line)
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
    t1 = threading.Thread(target=pump, args=(proc.stdout, True))
    t2 = threading.Thread(target=pump, args=(proc.stderr, False))
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

def check_mismatches(package_folder):
    check_output = run_without_stream(
        f"\"{sys.executable}\" Tools\\TestLinks.py {package_folder}\\*.installer.*",
    )
    
    files = []
    urls = []
    packages = []
    seen = set()
    
    blocks = check_output.strip().split("\n\n")
    for block in blocks:
        if "Installer hash mismatch!" not in block:
            continue
        
        log(block)
        file = re.search(r"^File:\s+(\S+)$", block, re.MULTILINE).group(1)
        url = re.search(r"^URL:\s+(\S+)$", block, re.MULTILINE).group(1)
        
        package = file.rsplit("\\", 1)[1].replace(".installer.yaml", "")
        if package in seen:
            continue

        seen.add(package)
        files.append(file)
        urls.append(url)
        packages.append(package)
    
    return files, urls, packages

def check_releases(url):
    releases = requests.get(url, params={"per_page": 100}, timeout=10).json()
    return [
        release["tag_name"].removeprefix("v")
        for release in releases
        if not release["draft"] and not release["prerelease"]
    ]

def update_package_local(updater, package_folder, batch_args, replace_folder=""):
    run_with_stream(
        f"update\\{updater}.bat {batch_args}"
    )
    if replace_folder:
        shutil.rmtree(replace_folder)
    run_with_stream(
        f"git add {package_folder} && git --no-pager diff --color=always HEAD {package_folder}"
    )

def update_and_replace(updater, package_folder, batch_args, replace):
    return update_package_local(updater, package_folder, batch_args, replace)

def submit_package(tool, version_folder, options=""):
    if tool == "wingetcreate":
        command = "wingetcreate submit --no-open"
    elif tool == "komac":
        command = "komac submit --submit"
    
    found_pr = json.loads(run_with_stream(
        f"powershell -ExecutionPolicy Bypass -File Tools\\GitHubPRSearch.ps1 {version_folder}"
    ))
    
    if found_pr:
        log(f"{"::warning title=Duplicate PR::" if os.getenv("GITHUB_ACTIONS") else ""}{version_folder} found in already opened PR(s): {", ".join(str(i["number"]) for i in found_pr)}")
    else:
        submit_q.append((f"{command} {version_folder} {options}", version_folder))

def submit_flush():
    for command, version_folder in submit_q:
        try:
            log(f"Submitting {version_folder}...")
            submit_output = run_with_stream(
                f"{command}"
            )
            pr_url = re.search(r"https://github\.com/microsoft/winget-pkgs/pull/\d+", submit_output).group(0)
            run_with_stream(
                f"powershell -ExecutionPolicy Bypass -File Tools\\UpdatePRBody.ps1 Tools\\PRBodyTemplate\\PRBodyModify.md -pr {pr_url.split("/")[-1]}"
            )
        except Exception as e:
            log(f"{"::error title=Failed submission::" if os.getenv("GITHUB_ACTIONS") else ""}Failed to submit {version_folder}: {type(e).__name__}: {e}")
    submit_q.clear()

def sync_manifests():
    run_with_stream(
        f"powershell -ExecutionPolicy Bypass -File Tools\\SyncManifests.ps1"
    )


if __name__ == "__main__":
    for path in Path(__file__).parent.glob("auto_*.py"):
        if path.stem == Path(__file__).stem:
            continue
        spec = importlib.util.spec_from_file_location(path.stem, path)
        module = importlib.util.module_from_spec(spec)
        inject_context(module.__dict__)
        spec.loader.exec_module(module)
        started = time.monotonic()
        with log_group(path.stem.removeprefix("auto_")):
            try:
                updates = module.run()
            except Exception as error:
                elapsed = time.monotonic() - started
                update_results.append({"name": path.stem, "updates": 0, "duration": elapsed, "failed": True})
                message = f"{type(error).__name__}: {error}"
                log(f"::error title={path.stem} failed::{message}" if os.getenv("GITHUB_ACTIONS") else f"{path.stem} failed: {message}")
                continue
        elapsed = time.monotonic() - started
        update_results.append({"name": path.stem, "updates": updates, "duration": elapsed})
        message = f"{path.stem}: {"updated" if updates else "no updates"} ({updates}) in {elapsed:.1f}s"
        log(f"::notice::{message}" if os.getenv("GITHUB_ACTIONS") else message)
    submit_flush()
    sync_manifests()
