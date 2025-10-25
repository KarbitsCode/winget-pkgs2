import os
import sys
import json
import yaml
import tempfile
import subprocess
from pathlib import Path

def has_two_arch(directory: str) -> bool:
    """Checks if installer.yml has x86 and x64 installers"""
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith((".installer.yml", ".installer.yaml")):
                with open(os.path.join(root, file), "r", encoding="utf-8") as f:
                    data = yaml.safe_load(f)
                installers = data.get("Installers", [])
                archs = {inst.get("Architecture") for inst in installers if isinstance(inst, dict)}
                if "x86" in archs and "x64" in archs:
                    return True
    return False

def run_powershell(script_path, *args):
    """Run a PowerShell script and pass args, streaming output to console."""
    cmd = ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(script_path), *map(str, args)]
    return subprocess.run(cmd, check=False)

def test_install(directory, args = ""):
    """Test install/uninstall of a package"""
    install_success = False
    uninstall_success = False
    
    # Temp file for ARP
    tmp_json = Path(tempfile.gettempdir()) / "arp.json"
    if tmp_json.exists():
        tmp_json.unlink()

    ps_script = Path(os.path.dirname(__file__)) / "Bootstrap.ps1"
    ps_args = []
    if os.getenv("GITHUB_ACTIONS"):
        args += " --silent"
        ps_args.append("-DisableSpinner")
    ps_args.append("-WinGetOptions")
    ps_args.append(f"--disable-interactivity {args}")
    ps_args.append("-AutoUninstall")
    # print(f"\nRunning {ps_script} with {ps_args}")
    install_proc = run_powershell(ps_script, directory, *ps_args)

    if install_proc.returncode != 0:
        print("PowerShell script failed.")
        return {"INST": install_success, "UNINST": uninstall_success}

    # Read JSON result from PowerShell
    if not tmp_json.exists():
        print("PowerShell did not write the JSON output.")
        return {"INST": install_success, "UNINST": uninstall_success}
    try:
        data = json.loads(tmp_json.read_text(encoding="utf-8-sig"))
    except Exception as e:
        print("Failed to parse JSON: ", e)
        return {"INST": install_success, "UNINST": uninstall_success}

    if data["InstallResult"]["ExitCode"] == 0:
        install_success = True
    for item in data["UninstallResult"]:
        if item["ExitCode"] == 0:
            uninstall_success = True

    return {"INST": install_success, "UNINST": uninstall_success}

def main(directories):
    seen = set()

    for directory in directories:
        for file_path in Path(directory).rglob("*.y*ml"):
            folder = file_path.parent
            if folder not in seen:
                seen.add(folder)
                for arch in ["x86", "x64"] if has_two_arch(folder) else [None]:
                    result = test_install(folder, f"-a {arch}" if arch else "")
                    print(f"\nFolder: {folder}" + (f" ({arch})" if arch else ""))
                    print(f"Install succeed: {result['INST']}")
                    print(f"Uninstall succeed: {result['UNINST']}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {Path(sys.executable).with_suffix('').name} {os.path.basename(sys.argv[0])} <directory>")
    else:
        main(sys.argv[1:])
