def run(*, is_main=(__name__ == "__main__")):
    selfname = Path(__file__).stem
    updater = selfname.lstrip("_").removeprefix("auto_")
    
    log("Checking installer mismatches...")
    itop_dir = Path("manifests\\i\\iTop")
    files, urls, packages = check_mismatches(itop_dir)
    for i in range(len(urls) - 1, -1, -1):
        if not urls[i].endswith(".exe"):
            del files[i]
            del urls[i]
            del packages[i]
    log(f"Found {len(packages)} iTop installer hash mismatches to inspect.")
    changes = []
    
    new_versions = []
    for url in urls:
        new_version_check_output = run_with_stream(
            f"powershell -ExecutionPolicy Bypass -File Tools\\InstallerUrlChecker.ps1 {url}"
        )
        new_product_version = re.search(r"^FileVersion:\s*(\S+)\s*$", new_version_check_output, re.MULTILINE).group(1)
        new_versions.append(new_product_version)
    log(f"Resolved {len(new_versions)} iTop version(s).")
    
    for package_name, new_version, file in zip(packages, new_versions, files):
        old_version_folder = Path(file).parent
        package_folder = old_version_folder.parent
        new_version_folder = package_folder / new_version
        update_package(
            updater,
            f"{package_name.split(".")[-1]} {new_version}",
            replace=old_version_folder
        )
        try:
            run_with_stream(
                f"\"{sys.executable}\" update\\releasenotes\\releasenotes_{updater}.py {new_version_folder} --no-backup"
            )
        except Exception as e:
            log(f"{"::warning title=Release Notes::" if os.getenv("GITHUB_ACTIONS") else ""}Failed to generate release notes for {package_name} version: {new_version}. Error: {e}")
        log(f"Queueing package submission for {package_name} version: {new_version}")
        submit_package("wingetcreate", new_version_folder)
        changes.append({"package": package_name, "before": old_version_folder.name, "after": new_version, "submission_key": str(new_version_folder)})
    
    # remote_versions = get_current_versions(itop_dir)
    # for package_name, versions in remote_versions.items():
        # if len(versions) > 1: # might have the older version present
            # older_than_latest = sorted(versions, key=version_key)[:-1]
            # log(f"Found older versions for {package_name}: {older_than_latest}")
            # for version in older_than_latest:
                # log(f"Queueing package removal for {package_name} version: {version}")
                # remove_package(package_name, version, "Old version")
                # changes.append({"package": package_name, "before": version, "after": "—", "submission_key": f"{package_name}@{version}"})
    
    if is_main:
        submit_flush()
    
    return changes

if __name__ == "__main__":
    from _update_all import inject_context
    inject_context(globals())
    run()
