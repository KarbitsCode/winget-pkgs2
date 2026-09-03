import re
import os
import sys
import time
import json
import atexit
import shutil
import tempfile
import requests
import threading
import subprocess
import importlib.util
from pathlib import Path
from contextlib import contextmanager

_submit_q = []
_update_results = []
_submission_urls = {}

def log(message):
    print(message, flush=True)

def version_key(version):
    return tuple(int(part) for part in re.findall(r"\d+", version))

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

def update_and_replace(updater, package_folder, batch_args, replace):
    return update_package_local(updater, package_folder, batch_args, replace)

def submit_package(tool, version_folder, options=""):
    if tool == "wingetcreate":
        command = "wingetcreate submit --no-open"
    elif tool == "komac":
        command = "komac submit --submit"
    
    found_pr = json.loads(run_without_stream(
        f"powershell -ExecutionPolicy Bypass -File Tools\\GitHubPRSearch.ps1 {version_folder}"
    ))
    
    if found_pr:
        # _submission_urls[str(version_folder)] = f"https://github.com/microsoft/winget-pkgs/pull/{found_pr[0]["number"]}"
        log(f"{"::warning title=Duplicate PR::" if os.getenv("GITHUB_ACTIONS") else ""}{version_folder} found in already opened PR(s): {", ".join(str(i["number"]) for i in found_pr)}")
    else:
        run_with_stream(
            f"git add {version_folder.parent} && git --no-pager diff --color=always HEAD {version_folder.parent}"
        )
        _submit_q.append((f"{command} {version_folder} {options}", version_folder))

def submit_flush():
    for command, version_folder in _submit_q:
        try:
            log(f"Submitting {version_folder}...")
            submit_output = run_with_stream(
                f"{command}"
            )
            pr_url = re.search(r"https://github\.com/microsoft/winget-pkgs/pull/\d+", submit_output).group(0)
            _submission_urls[str(version_folder)] = pr_url
            run_with_stream(
                f"powershell -ExecutionPolicy Bypass -File Tools\\UpdatePRBody.ps1 Tools\\PRBodyTemplate\\PRBodyModify.md -pr {pr_url.split("/")[-1]}"
            )
        except Exception as e:
            log(f"{"::error title=Failed submission::" if os.getenv("GITHUB_ACTIONS") else ""}Failed to submit {version_folder}: {type(e).__name__}: {e}")
    _submit_q.clear()

def sync_manifests():
    run_with_stream(
        f"powershell -ExecutionPolicy Bypass -File Tools\\SyncManifests.ps1"
    )

@contextmanager
def _manifest_snapshot():
    manifest_root = Path("manifests")
    git_index = Path(run_without_stream("git rev-parse --git-path index").strip()).resolve()
    submission_count = len(_submit_q)
    with tempfile.TemporaryDirectory(prefix="winget-manifests-") as t:
        snapshot = Path(t) / "manifests"
        index_snapshot = Path(t) / "index"
        shutil.copytree(manifest_root, snapshot)
        shutil.copy2(git_index, index_snapshot)
        try:
            yield
        except Exception:
            shutil.rmtree(manifest_root)
            shutil.copytree(snapshot, manifest_root)
            shutil.copy2(index_snapshot, git_index)
            del _submit_q[submission_count:]
            raise

@contextmanager
def _log_group(title):
    if os.getenv("GITHUB_ACTIONS"):
        log(f"::group::{title}")
    else:
        log(f"--- {title} ---")
    try:
        yield
    finally:
        if os.getenv("GITHUB_ACTIONS"):
            log("::endgroup::")

def _write_summary():
    path = os.getenv("GITHUB_STEP_SUMMARY")
    if path:
        updated = sum(item["updates"] > 0 and not item.get("failed") for item in _update_results)
        failed = sum(bool(item.get("failed")) for item in _update_results)
        unchanged = len(_update_results) - updated - failed
        lines = [
            "## autoupdater summary\n",
            f"**{updated} updated** · **{unchanged} unchanged** · **{failed} failed**\n",
            "| updater | result | updates | execution time |",
            "| --- | --- | ---: | ---: |",
        ]
        for item in _update_results:
            status = "failed" if item.get("failed") else "updated" if item["updates"] else "no updates"
            lines.append(f"| {item["name"]} | {status} | {item["updates"]} | {item["duration"]:.1f}s |")
        changes = [
            change
            for item in _update_results
            for change in item.get("changes", [])
        ]
        if changes:
            lines.extend([
                "\n| package | before | after | pr |",
                "| --- | --- | --- | --- |",
            ])
            for change in changes:
                pr_url = _submission_urls.get(change["submission_key"])
                pr_link = f"[#{pr_url.rsplit("/", 1)[-1]}]({pr_url})" if pr_url else "—"
                lines.append(
                    f"| {change["package"]} | {change["before"]} | {change["after"]} | {pr_link} |"
                )
        with open(path, "a", encoding="utf-8") as summary:
            summary.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    atexit.register(_write_summary)
    for path in Path(__file__).parent.glob("auto_*.py"):
        if path.stem == Path(__file__).stem:
            continue
        spec = importlib.util.spec_from_file_location(path.stem, path)
        module = importlib.util.module_from_spec(spec)
        inject_context(module.__dict__)
        spec.loader.exec_module(module)
        started = time.monotonic()
        with _log_group(path.stem.removeprefix("auto_")):
            try:
                with _manifest_snapshot():
                    changes = module.run()
                    updates = len(changes)
            except Exception as error:
                elapsed = time.monotonic() - started
                _update_results.append({"name": path.stem, "updates": 0, "duration": elapsed, "changes": [], "failed": True})
                message = f"{type(error).__name__}: {error}"
                log(f"::error title={path.stem} failed::{message}" if os.getenv("GITHUB_ACTIONS") else f"{path.stem} failed: {message}")
                continue
        elapsed = time.monotonic() - started
        _update_results.append({"name": path.stem, "updates": updates, "duration": elapsed, "changes": changes})
        message = f"{path.stem}: {"updated" if updates else "no updates"} ({updates}) {"package(s)" if updates else ""} in {elapsed:.1f}s"
        log(f"::notice::{message}" if os.getenv("GITHUB_ACTIONS") else message)
    with _log_group("pull_request_submission"):
        submit_flush()
    with _log_group("synchronize_manifests"):
        sync_manifests()
