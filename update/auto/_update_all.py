import re
import sys
import shutil
import subprocess
import importlib.util
from pathlib import Path

def inject_context(target):
    target.update({
        k: v
        for k, v in globals().items()
        if not k.startswith("__")
    })

def run_with_stream(*args, **kwargs):
    output = []
    proc = subprocess.Popen(
        *args,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        shell=True,
        **kwargs,
    )
    for line in proc.stdout:
        print(line, end="")
        output.append(line)
    proc.wait()
    if proc.returncode:
        raise subprocess.CalledProcessError(proc.returncode, proc.args)
    return "".join(output)

def check_mismatches(package_folder):
    check_output = run_with_stream(
        f"\"{sys.executable}\" -u Tools\\TestLinks.py {package_folder}\\*.installer.*",
    )
    
    files = []
    urls = []
    packages = []
    seen = set()
    
    blocks = check_output.strip().split("\n\n")
    for block in blocks:
        if "Installer hash mismatch!" not in block:
            continue
        
        file = re.search(r"^File:\s+(\S+)$", block, re.MULTILINE).group(1)
        url = re.search(r"^URL:\s+(\S+)$", block, re.MULTILINE).group(1)
        
        if not url.endswith(".exe"):
            continue
        
        package = file.rsplit("\\", 1)[1].replace(".installer.yaml", "")
        key = (file, url, package)
        if key in seen:
            continue
        
        seen.add(key)
        files.append(file)
        urls.append(url)
        packages.append(package)
    
    return files, urls, packages

def update_package_local(updater, old_version_folder, package_name, new_version, replace=False):
    package_folder = old_version_folder.parent
    new_version_folder = package_folder / new_version
    run_with_stream(
        f"update\\{updater}.bat {package_name.split(".")[1]} {new_version}"
    )
    if replace:
        shutil.rmtree(old_version_folder)
    run_with_stream(
        f"git add {package_folder} && git --no-pager diff HEAD {package_folder}"
    )
    return new_version_folder

def update_and_replace(updater, old_version_folder, package_name, new_version):
    return update_package_local(updater, old_version_folder, package_name, new_version, replace=True)

def submit_package(tool, version_folder, options):
    if tool == "wingetcreate":
        command = "wingetcreate submit --no-open"
    elif tool == "komac":
        command = "komac submit --submit"
    
    submit_output = run_with_stream(
        f"{command} {version_folder} {options}"
    )
    pr_url = re.search(r"^Pull request can be found here:\s*(\S+)$", submit_output, re.MULTILINE).group(1)
    run_with_stream(
        f"powershell -ExecutionPolicy Bypass -File Tools\\UpdatePRBody.ps1 Tools\\PRBodyTemplate\\PRBodyModify.md -pr {pr_url.split('/')[-1]}"
    )

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
        module.run()
    sync_manifests()
