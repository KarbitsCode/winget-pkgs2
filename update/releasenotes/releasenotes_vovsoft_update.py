def run(*, is_main=(__name__ == "__main__")):
    output, data = get_manifest(load_manifest(), "locale.en-US")
    version = data.get("PackageVersion")
    url = data.get("ReleaseNotesUrl")
    
    response = fetch(url, timeout=30)
    
    log(f"Parsing page...")
    soup = BeautifulSoup(response.text, "lxml")
    entries = [
        row for row in soup.find_all("div", class_="w3-row")
        if row.find("div", class_="w3-third", recursive=False) and row.find("ul")
    ]
    if not entries:
        raise RuntimeError("Version history section was not found.")
    
    if asked_latest_version():
        latest_label = entries[0].find("span", class_="notranslate").get_text(strip=True)
        log(f"Latest version: {latest_label.rsplit(' ', 1)[-1]}")
        raise SystemExit
    
    for entry in entries:
        # The label is like "Vov Screen Recorder 5.2"
        label = entry.find("span", class_="notranslate").get_text(strip=True)
        entry_version = label.rsplit(" ", 1)[-1]
        if re.sub(r"(?:\.0)+$", "", entry_version) != re.sub(r"(?:\.0)+$", "", str(version)):
            continue
        
        notes = entry.find("ul")
        
        title = f"{label}"
        date = re.search(r"[A-Z][a-z]+ \d{1,2}, \d{4}", entry.find("div", class_="w3-third").get_text(" ", strip=True))
        if date:
            title += f" ({datetime.strptime(date.group(), '%B %d, %Y').strftime('%Y-%m-%d')})"
        
        release_notes = [title]
        for note in notes.find_all("li", recursive=False):
            text = re.sub(r"\s+", " ", note.get_text(" ", strip=True))
            release_notes.append(f"- {text}")
        
        log("Release notes for version " + str(version) + ":\n" + "\n".join(release_notes))
        create_backup(output)
        log("Writing new release notes...")
        write_release_notes(output, data, release_notes)
        log("Done.")
        break
    else:
        raise RuntimeError(f"Version {version} was not found.")


if __name__ == "__main__":
    from _common import inject_context
    inject_context(globals())
    run()
