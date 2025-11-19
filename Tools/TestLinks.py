import re
import os
import sys
import uuid
import yaml
import hashlib
import platform
import requests
import tempfile
from pathlib import Path

def extract_urls_from_file(file_path):
    """Extract all URLs from a YAML file (raw text scan)"""
    text = Path(file_path).read_text(encoding="utf-8", errors="ignore")
    url_pattern = re.compile(r"https?://[^\s'\"<>]+")
    return url_pattern.findall(text)

def sha256sum(data):
    """Compute SHA256 hash of given bytes"""
    sha256 = hashlib.sha256()
    sha256.update(data)
    return sha256.hexdigest().upper()

def check_hash(file_path, url, response):
    """Checks in installer.yml has installers hash match"""
    if file_path.name.endswith((".installer.yml", ".installer.yaml")):
        with open(file_path.resolve(), "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
        installers = data.get("Installers", [])
        for installer in installers:
            if url != installer.get("InstallerUrl"):
                continue
            actual = sha256sum(response.content)
            expected = installer.get("InstallerSha256")
            print(f"Expected: {expected}")
            print(f"Actual:   {actual}")
            if actual == expected:
                print("Installer hash match!")
            else:
                print("Installer hash mismatch!")

def dump_response(prefix, response):
    """Dump response to %TEMP% with random filename"""
    # If NO_DUMP is false and we're not in CI and args being only "manifests"
    if os.getenv("NO_DUMP", "0").lower() not in ("true", "1") and not os.getenv("GITHUB_ACTIONS") and sys.argv[1] != "manifests":
        temp_dir = Path(tempfile.gettempdir())
        base_name = f"{prefix}_{uuid.uuid4().hex}"
        body_file = temp_dir / f"{base_name}.bin"
        meta_file = temp_dir / f"{base_name}.meta"
        
        # Write response body
        try:
            with open(body_file, "wb") as f:
                f.write(response.content)
        except Exception as e:
            print(f"Failed to write body file: {e}")
        
        # Write response metadata
        try:
            with open(meta_file, "w", encoding="utf-8") as f:
                f.write(f"URL: {response.url}\n")
                f.write(f"Status: {response.status_code}\n")
                f.write("Headers:\n")
                for k, v in response.headers.items():
                    f.write(f"  {k}: {v}\n")
        except Exception as e:
            print(f"Failed to write meta file: {e}")

def test_links(url, file_path):
    """Test a URL with HEAD and GET requests"""
    result = {"url": url}
    headers = {"User-Agent": f"Python/{platform.python_version()} (Windows NT 10.0; Win64; x64)"}
    timeout = 15
    try:
        resp = requests.head(url, timeout=timeout, headers=headers, allow_redirects=True)
        result["HEAD"] = str(resp.status_code)
        dump_response("HEAD", resp)
        result["HEAD"] += " (NOK)" if not resp.ok else ""
    except Exception as e:
        result["HEAD"] = f"Error: {e}"
    try:
        resp = requests.get(url, timeout=timeout, headers=headers, allow_redirects=True)
        result["GET"] = str(resp.status_code)
        if resp.ok:
            check_hash(file_path, url, resp)
        dump_response("GET", resp)
        result["GET"] += " (NOK)" if not resp.ok else ""
    except Exception as e:
        result["GET"] = f"Error: {e}"
    return result

def main(directories):
    seen = set()
    
    for directory in directories:
        if os.path.exists(directory):
            for file_path in sorted(Path(directory).rglob("*.y*ml")):
                urls = extract_urls_from_file(file_path)
                for url in urls:
                    if url not in seen:
                        seen.add(url)
                        print(f"\nFile: {file_path}")
                        print(f"URL:  {url}")
                        result = test_links(url, file_path)
                        print(f"HEAD: {result['HEAD']}")
                        print(f"GET:  {result['GET']}")
        else:
            print(f"Directory doesn't exist: {directory}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        if os.getenv("GITHUB_ACTIONS"):
            print("Nothing to do, exiting...")
        else:
            print(f"Usage: {Path(sys.executable).with_suffix('').name} {os.path.basename(sys.argv[0])} <directory>")
    else:
        if "--no-dump" in sys.argv:
            os.environ["NO_DUMP"] = "true"
            sys.argv.remove("--no-dump")
        main(sys.argv[1:])
