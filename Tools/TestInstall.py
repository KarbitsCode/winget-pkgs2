import os
import sys
import json
import tempfile
import subprocess
from pathlib import Path

def run_powershell(script_path, *args):
    """Run a PowerShell script and pass args, streaming output to console."""
    cmd = ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(script_path), *map(str, args)]
    return subprocess.run(cmd, check=False)

def test_install(directory):
    """Test install/uninstall of a package"""
    install_success = False
    uninstall_success = False
    
    # Temp file for ARP
    tmp_json = Path(tempfile.gettempdir()) / "arp.json"
    if tmp_json.exists():
        tmp_json.unlink()

    ps_script = Path(os.path.dirname(__file__)) / "Bootstrap.ps1"
    ps_args = []
    ps_args.append("-WinGetOptions")
    ps_args.append("--accept-package-agreements --accept-source-agreements --disable-interactivity")
    if os.getenv("GITHUB_ACTIONS"):
        ps_args.append("-DisableSpinner")
    print(f"\n[INSTALL] Running {ps_script} with {ps_args}")
    install_proc = run_powershell(ps_script, directory, *ps_args)

    if install_proc.returncode != 0:
        print("PowerShell script failed.")
        return {"INST": install_success, "UNINST": uninstall_success}

    # If we got to this point, the install should be a success
    install_success = True

    # Read JSON diff result from PowerShell
    if not tmp_json.exists():
        print("PowerShell did not write the JSON output.")
        return {"INST": install_success, "UNINST": uninstall_success}
    try:
        data = json.loads(tmp_json.read_text(encoding="utf-8-sig"))
    except Exception as e:
        print("Failed to parse JSON: ", e)
        return {"INST": install_success, "UNINST": uninstall_success}

    # Ensure data is always a list
    if isinstance(data, dict):
        data = [data]
    elif not isinstance(data, list):
        print("Unexpected JSON format from PowerShell.")
        return {"INST": True, "UNINST": False}

    # Extract unique product codes from json
    product_codes = sorted(set(d["ProductCode"] for d in data if d.get("ProductCode")))

    if not product_codes:
        print("No ProductCode found in PowerShell output.")
        return {"INST": True, "UNINST": False}

    print(f"Installation completed. Found ProductCode(s): {product_codes}")

    uninstall_success = True
    for product_code in product_codes:
        print(f"[UNINSTALL] Running: winget uninstall {product_code}")
        proc = subprocess.run(["winget", "uninstall", product_code])
        if proc.returncode == 0:
            print(f"Uninstall succeeded for {product_code}")
        else:
            print(f"Uninstall failed for {product_code}")
            uninstall_success = False

    return {"INST": install_success, "UNINST": uninstall_success}

def main(directories):
    seen = set()

    for directory in directories:
        for file_path in Path(directory).rglob("*.y*ml"):
            folder = file_path.parent
            if folder not in seen:
                seen.add(folder)
                result = test_install(folder)
                print(f"\nFolder: {folder}")
                print(f"Install succeed: {result['INST']}")
                print(f"Uninstall succeed: {result['UNINST']}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {Path(sys.executable).with_suffix('').name} {os.path.basename(sys.argv[0])} <directory>")
    else:
        main(sys.argv[1:])
