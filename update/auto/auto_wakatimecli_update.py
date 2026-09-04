def run(*, is_main=(__name__ == "__main__")):
    selfname = Path(__file__).stem
    updater = selfname.lstrip("_").removeprefix("auto_")
    
    log("Checking releases...")
    versions = check_releases("https://api.github.com/repos/wakatime/wakatime-cli/releases")
    wakatime_dir = Path("manifests\\w\\Wakatime\\CLIWakatime")
    existing = {
        folder.name
        for folder in wakatime_dir.iterdir()
        if folder.is_dir()
    }
    new_versions = [
        version
        for version in versions
        if version not in existing
    ]
    new_versions = list(reversed(new_versions))
    log(f"Found {len(new_versions)} new WakaTime CLI release(s).")
    changes = []
    
    for new_version in new_versions:
        package_folder = wakatime_dir
        new_version_folder = package_folder / new_version
        update_package_local(
            updater,
            package_folder,
            f"{new_version}"
        )
        changes.append({"package": "Wakatime.CLIWakatime", "before": "—", "after": new_version, "submission_key": str(new_version_folder)})
        log(f"Queueing package submission for WakaTime CLI version: {new_version}")
        submit_package("komac", new_version_folder)
    
    if is_main:
        submit_flush()
    
    return changes


if __name__ == "__main__":
    from _update_all import inject_context
    inject_context(globals())
    run()
