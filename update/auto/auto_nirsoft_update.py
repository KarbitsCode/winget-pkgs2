def run(*, is_main=(__name__ == "__main__")):
    selfname = Path(__file__).stem.lstrip("_").removeprefix("auto_")
    log("Checking installer mismatches...")
    files, urls, packages = check_mismatches("manifests\\n\\NirSoft")
    
    for i in range(len(urls) - 1, -1, -1):
        if not urls[i].endswith(".zip"):
            del files[i]
            del urls[i]
            del packages[i]
    
    log(f"Found {len(packages)} NirSoft installer hash mismatch(es) to inspect.")
    
    new_versions = []
    for file in files:
        folder = Path(file).parent
        check_output = run_with_stream(
            f"\"{sys.executable}\" update\\releasenotes\\releasenotes_{selfname}.py {folder} --latest-version"
        )
        new_version = re.search(r"^Latest version:\s+(\S+)$", check_output, re.MULTILINE).group(1)
        log(f"{folder}: latest version {new_version}")
        if folder.name == new_version:
            log("Already current.")
            new_versions.append(None)
            continue
        new_versions.append(new_version)
    
    for package_name, new_version, file in zip(packages, new_versions, files):
        if new_version is None:
            continue
        updater = selfname
        old_version_folder = Path(file).parent
        package_folder = old_version_folder.parent
        new_version_folder = package_folder / new_version
        update_and_replace(
            updater,
            package_folder,
            f"{package_name.split(".")[1]} {new_version}",
            replace=old_version_folder
        )
        run_with_stream(
            f"\"{sys.executable}\" update\\releasenotes\\releasenotes_{selfname}.py {new_version_folder} --no-backup"
        )
        log(f"Queueing package submission for NirSoft version: {new_version}")
        submit_package("wingetcreate", new_version_folder, "--replace")
    
    if is_main:
        submit_flush()
    
    return sum(version is not None for version in new_versions)


if __name__ == "__main__":
    from _update_all import inject_context
    inject_context(globals())
    run()
