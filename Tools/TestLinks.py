import re
import os
import sys
import uuid
import requests
import tempfile
from pathlib import Path

def extract_urls_from_file(file_path):
    """Extract all URLs from a YAML file (raw text scan)."""
    text = Path(file_path).read_text(encoding="utf-8", errors="ignore")
    url_pattern = re.compile(r"https?://[^\s'\"<>]+")
    return url_pattern.findall(text)

def dump_response(prefix, response):
    """Dump response to %TEMP% with random filename."""
    if os.getenv("NO_DUMP", "0").lower() not in ("true", "1") and not os.getenv("GITHUB_ACTIONS"):
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

def check_url(url):
    """Check a URL with HEAD and GET requests."""
    result = {"url": url}
    try:
        resp = requests.head(url, timeout=10, allow_redirects=True)
        result["HEAD"] = resp.status_code
        if resp.ok:
            dump_response("HEAD", resp)
    except Exception as e:
        result["HEAD"] = f"Error: {e}"
    try:
        resp = requests.get(url, timeout=10, allow_redirects=True)
        result["GET"] = resp.status_code
        if resp.ok:
            dump_response("GET", resp)
    except Exception as e:
        result["GET"] = f"Error: {e}"
    return result

def main(directories):
    seen = set()

    for directory in directories:
        for file_path in Path(directory).rglob("*.y*ml"):
            urls = extract_urls_from_file(file_path)
            for url in urls:
                if url not in seen:
                    seen.add(url)
                    print(f"\nFile: {file_path}")
                    print(f"URL:  {url}")
                    result = check_url(url)
                    print(f"HEAD: {result['HEAD']}")
                    print(f"GET:  {result['GET']}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {Path(sys.executable).with_suffix('').name} {os.path.basename(sys.argv[0])} <directory>")
    else:
        if "--no-dump" in sys.argv:
            os.environ["NO_DUMP"] = "true"
            sys.argv.remove("--no-dump")
        main(sys.argv[1:])
