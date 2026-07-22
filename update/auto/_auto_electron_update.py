def run():
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
    print(new_versions)
    
    for new_version in new_versions:
        updater = Path(__file__).stem.lstrip("_").removeprefix("auto_")
        package_folder = electron_dir / new_version.split(".", 1)[0]
        new_version_folder = package_folder / new_version
        update_package_local(
            updater,
            package_folder,
            f"{new_version}"
        )
        submit_package("komac", new_version_folder)


if __name__ == "__main__":
    from _update_all import inject_context
    inject_context(globals())
    run()
