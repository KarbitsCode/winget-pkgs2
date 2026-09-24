if __name__ == "__main__":
    from _common import *

    output, data = load_manifest()
    version = data.get("PackageVersion")

    url = f"https://api.github.com/repos/TDesktop-x64/tdesktop/releases"
    response = fetch(url, timeout=30)
    releases = response.json()

    if asked_latest_version():
        if not releases:
            raise RuntimeError("No releases found.")
        latest_release = releases[0]
        new_version = re.sub(r"^v", "", latest_release["tag_name"])
        log(f"Latest version: {new_version}")
        raise SystemExit

    create_backup(output)

    target_version = f"v{version}"
    for release in releases:
        if release.get("tag_name") != target_version:
            continue
        
        notes = release.get("body")
        if notes is None:
            raise RuntimeError(f"No release notes found for {target_version}")
        
        log(f"Found release notes for version {version}:\n'{notes}'")
        log(f"Writing new release notes...")
        release_notes = []
        first_line = next((line.strip() for line in notes.splitlines() if line.strip()), "")
        release_notes.append(first_line)
        for note in notes.splitlines():
            note = note.strip()
            if not note or note == first_line:
                continue
            note = re.sub(r"^\d+\.\s+", "", note)
            release_notes.append(f"- {note}")
        write_release_notes(output, data, release_notes)
        
        log("Done.")
        break
    else:
        raise RuntimeError(f"{target_version} was not found.")
