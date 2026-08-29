def run(*, is_main=(__name__ == "__main__")):
    selfname = Path(__file__).stem
    log("Checking releases...")
    versions = check_releases("https://api.github.com/repos/electron/electron/releases")
    electron_dir = Path("manifests\\o\\OpenJS\\Electron")
    tracked_majors = {
        folder.name
        for folder in electron_dir.iterdir()
        if folder.is_dir()
    }
    existing = {
        folder.name
        for major in electron_dir.iterdir()
        if major.is_dir()
        for folder in major.iterdir()
        if folder.is_dir()
    }
    new_versions = [
        version
        for version in versions
        if version not in existing
        and version.split(".", 1)[0] in tracked_majors
    ]
    log(f"Found {len(new_versions)} new Electron release(s).")
    changes = []
    
    for new_version in new_versions:
        updater = selfname.lstrip("_").removeprefix("auto_")
        package_folder = electron_dir / new_version.split(".", 1)[0]
        new_version_folder = package_folder / new_version
        update_package_local(
            updater,
            package_folder,
            f"{new_version}"
        )
        previous_version = max(
            (version for version in existing if version.split(".", 1)[0] == new_version.split(".", 1)[0]),
            key=version_key,
            default="—",
        )
        changes.append({"package": "OpenJS.Electron", "before": previous_version, "after": new_version, "updater": selfname})
        log(f"Queueing package submission for Electron version: {new_version}")
        submit_package("komac", new_version_folder)
    
    if is_main:
        submit_flush()
    
    return changes


if __name__ == "__main__":
    from _update_all import inject_context
    inject_context(globals())
    run()
