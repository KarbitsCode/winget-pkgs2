import os
import sys
import mss
import json
import yaml
import time
import ctypes
import tempfile
import platform
import traceback
import threading
import subprocess
from pathlib import Path
from ctypes import wintypes
from datetime import datetime

def auto_popups(stop_event):
    """Scan for installer popups and auto-close them if exists"""
    user32 = ctypes.windll.user32
    WM_GETTEXT = 0x000D
    WM_GETTEXTLENGTH = 0x000E
    BM_CLICK = 0x00F5
    WM_CLOSE = 0x0010
    BM_CLICK = 0x00F5
    VK_ENTER = 0x0D
    VK_TAB = 0x09
    EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
    
    def callback(hwnd, lParam):
        # Get class name of the window
        class_name = ctypes.create_unicode_buffer(256)
        user32.GetClassNameW(hwnd, class_name, 256)
        # print(f"Class name value: {class_name.value}")
        if class_name.value == "#32770":  # Common window popup
            def get_dialog_text(hwnd):
                text_parts = []
                buf = ctypes.create_unicode_buffer(512)
                @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
                def enum_child_callback(child_hwnd, _):
                    user32.GetClassNameW(child_hwnd, buf, 512)
                    cls = buf.value
                    if cls == "Static":  # only read Static controls
                        user32.SendMessageW(child_hwnd, WM_GETTEXT, 512, buf)
                        txt = buf.value.strip()
                        if txt:
                            text_parts.append(txt)
                    return True
                user32.EnumChildWindows(hwnd, enum_child_callback, 0)
                return " ".join(text_parts)
            
            # Inside dialog, find buttons
            def click_buttons(child_hwnd, _):
                btn_class = ctypes.create_unicode_buffer(256)
                user32.GetClassNameW(child_hwnd, btn_class, 256)
                # print(f"Button class value: {btn_class.value}")
                if btn_class.value == "Button":
                    msg_text = get_dialog_text(hwnd).lower()
                    text_buf = ctypes.create_unicode_buffer(1024)
                    user32.GetWindowTextW(child_hwnd, text_buf, 1024)
                    caption = text_buf.value.translate(str.maketrans("", "", "&<>")).strip()
                    # print(f"Button text: {caption}")
                    
                    # Avoid restarting/rebooting while install/uninstall
                    if any(word in msg_text for word in ("restart", "reboot")):
                        if caption in ("No", "Cancel", "Abort"):
                            user32.SendMessageW(child_hwnd, BM_CLICK, 0, 0)
                    elif caption in ("OK", "Yes", "Next", "Run", "Continue", "Uninstall", "Close", "Finish"):
                        user32.SendMessageW(child_hwnd, BM_CLICK, 0, 0)
                return True
            
            user32.EnumChildWindows(hwnd, EnumWindowsProc(click_buttons), 0)
        elif "SunAwtFrame" in class_name.value: # Handle Java AWT
            user32.SetForegroundWindow(hwnd)
            # Simulate Enter key
            user32.keybd_event(VK_ENTER, 0, 0, 0) # down
            time.sleep(0.05)
            user32.keybd_event(VK_ENTER, 0, 2, 0) # up
            time.sleep(2)
            user32.SetForegroundWindow(hwnd)
            # Simulate Tab key
            user32.keybd_event(VK_TAB, 0, 0, 0)  # down
            time.sleep(0.05)
            user32.keybd_event(VK_TAB, 0, 2, 0)  # up
        return True
    
    while not stop_event.is_set():
        user32.EnumWindows(EnumWindowsProc(callback), 0)
        time.sleep(1)

def get_screenshots(stop_event, folder, interval=10):
    """Takes desktop screenshots every [interval] seconds until stop_event is triggered"""
    folder.mkdir(parents=True, exist_ok=True)
    with mss.mss() as sct:
        monitor_index = 1  # 1 = primary monitor
        while not stop_event.is_set():
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            img_path = folder / f"screenshot_{timestamp}.png"
            sct.shot(mon=monitor_index, output=str(img_path))
            time.sleep(interval)

def get_installer_arch(directory):
    """Get installer architectures from package's installer.yml"""
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith((".installer.yml", ".installer.yaml")):
                with open(os.path.join(root, file), "r", encoding="utf-8") as f:
                    data = yaml.safe_load(f)
                installers = data.get("Installers", [])
                archs = {inst.get("Architecture") for inst in installers if isinstance(inst, dict)}
    return list(sorted(archs))

def run_powershell(script_path, *args, timeout=600):
    """Run a PowerShell script with timeout, streaming output to console"""
    cmd = ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(script_path), *map(str, args)]
    try:
        return subprocess.run(cmd, check=False, shell=False, timeout=timeout)
    except subprocess.TimeoutExpired as e:
        print(f"PowerShell script timed out after {timeout} seconds.")
        return subprocess.CompletedProcess(cmd, returncode=-999)

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
        ps_args.append("-StripProgress")
        ps_args.append("-DisableSpinner")
    ps_args.append("-WinGetOptions")
    ps_args.append(f"--disable-interactivity {args}")
    ps_args.append("-AutoUninstall")
    
    # Start screenshoting
    ss_dir = Path(__file__).parent / "ss"
    ss_stop = threading.Event()
    ss_thread = threading.Thread(target=get_screenshots, args=[ss_stop, ss_dir])
    ss_thread.start()
    
    try:
        # print(f"\nRunning {ps_script} with {ps_args}")
        install_proc = run_powershell(ps_script, directory, *ps_args)
    except KeyboardInterrupt:
        traceback.print_exc()
    finally:
        # Stop screenshoting
        ss_stop.set()
    ss_thread.join()
    
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
    
    # Start handling popups
    pp_stop = threading.Event()
    pp_thread = threading.Thread(target=auto_popups, args=[pp_stop])
    pp_thread.start()
    
    try:
        for directory in directories:
            if os.path.exists(directory):
                for file_path in sorted(Path(directory).rglob("*.y*ml")):
                    folder = file_path.parent
                    if folder not in seen:
                        seen.add(folder)
                        for arch in get_installer_arch(folder):
                            if platform.machine().lower() != arch == "arm64":
                                continue
                            result = test_install(folder, f"-a {arch}" if arch else "")
                            print(f"\nFolder: {folder}" + (f" ({arch})" if arch else ""))
                            print(f"Install succeed: {result['INST']}")
                            print(f"Uninstall succeed: {result['UNINST']}")
            else:
                print(f"Direcory doesn't exist: {directory}")
    except KeyboardInterrupt:
        traceback.print_exc()
    finally:
        # Stop handling popups
        pp_stop.set()
    pp_thread.join()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        if os.getenv("GITHUB_ACTIONS"):
            print("Nothing to do, exiting...")
        else:
            print(f"Usage: {Path(sys.executable).with_suffix('').name} {os.path.basename(sys.argv[0])} <directory>")
    else:
        main(sys.argv[1:])
