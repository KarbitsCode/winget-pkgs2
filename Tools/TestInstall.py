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
    print(f"\n[INSTALL] Running {ps_script} ...")
    install_proc = run_powershell(ps_script, directory, "-WinGetOptions \"--accept-package-agreements --accept-source-agreements --disable-interactivity\"")

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
        data = json.loads(tmp_json.read_text(encoding="utf-8"))
    except Exception as e:
        print("Failed to parse JSON: ", e)
        return {"INST": install_success, "UNINST": uninstall_success}

    product_code = data.get("ProductCode")
    if not product_code:
        print("No ProductCode found in PowerShell output.")
        return {"INST": install_success, "UNINST": uninstall_success}

    print(f"Installation completed. Found ProductCode: {product_code}")

    # Try uninstalling the package via winget
    print(f"[UNINSTALL] Running: winget uninstall {product_code}")
    proc = subprocess.run(["winget", "uninstall", product_code])
    uninstall_success = proc.returncode == 0

    if uninstall_success:
        print(f"Uninstall succeeded for {product_code}")
    else:
        print(f"Uninstall failed for {product_code}")

    return {"INST": install_success, "UNINST": uninstall_success}

def main(directories):
    seen = set()

    for directory in directories:
        for file_path in Path(directory).rglob("*.y*ml"):
            folder = file_path.parent
            if folder not in seen:
                seen.add(folder)
                print(f"\nFolder: {folder}")
                result = test_install(folder)
                print(f"Install succeed: {result['INST']}")
                print(f"Uninstall succeed: {result['UNINST']}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {Path(sys.executable).with_suffix('').name} {os.path.basename(sys.argv[0])} <directory>")
    else:
        main(sys.argv[1:])
