if __name__ == "__main__":
    from _common import *

    output, data = load_manifest()
    url = data.get("PackageUrl")
    version = data.get("PackageVersion")

    response = fetch(url, timeout=30)

    log(f"Parsing page...")
    soup = BeautifulSoup(response.text, "lxml")
    history_heading = soup.find(
        "h4",
        class_="utilsubject",
        string=re.compile(r"^Versions? History$")
    )
    if history_heading is None:
        raise RuntimeError("Version history section was not found.")

    history = history_heading.find_next("ul")
    if history is None:
        raise RuntimeError("Version history list was not found.")

    if asked_latest_version():
        latest_entry = history.find("li", recursive=False)
        if latest_entry is None:
            raise RuntimeError("No versions found.")
        latest_label = next((text.strip() for text in latest_entry.find_all(string=True, recursive=False)), "")
        new_version = re.sub(r"^Version\s+", "", latest_label).rstrip(":")
        log(f"Latest version: {new_version}")
        raise SystemExit

    create_backup(output)

    target_version = f"Version {version}"
    for entry in history.find_all("li", recursive=False):
        # The text directly inside the outer <li> is the version label.
        label = next((text.strip() for text in entry.find_all(string=True, recursive=False)), "")
        match = re.fullmatch(rf"{re.escape(target_version)}:?", label)
        if not match:
            continue
        
        notes = entry.find("ul", recursive=False)
        if notes is None:
            raise RuntimeError(f"No release notes found for {target_version}")
        
        log(f"Found release notes for version {version}:\n'{' '.join(str(notes or '').split())}'")
        log(f"Writing new release notes...")
        release_notes = []
        release_notes.append(f"- {target_version}:")
        for note in notes.find_all("li", recursive=False):
            text = re.sub(r"\s+", " ", note.get_text(" ", strip=True))
            release_notes.append(f"  - {text}")
        write_release_notes(output, data, release_notes)
        
        log("Done.")
        break
    else:
        raise RuntimeError(f"{target_version} was not found.")
