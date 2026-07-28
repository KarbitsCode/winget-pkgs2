def run():
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
    print(new_versions)
    
    for new_version in new_versions:
        updater = Path(__file__).stem.lstrip("_").removeprefix("auto_")
        package_folder = wakatime_dir
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
