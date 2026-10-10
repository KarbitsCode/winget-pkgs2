def run(*, is_main=(__name__ == "__main__")):
    selfname = Path(__file__).stem
    updater = selfname.lstrip("_").removeprefix("auto_")

    log("Checking installer mismatches...")
    files, urls, packages = check_mismatches("manifests\\i\\IObit")
    for i in range(len(urls) - 1, -1, -1):
        if not urls[i].endswith(".exe"):
            del files[i]
            del urls[i]
            del packages[i]
    log(f"Found {len(packages)} IObit installer hash mismatches to inspect.")
    changes = []
    
    new_versions = []
    for url in urls:
        new_version_check_output = run_with_stream(
            f"powershell -ExecutionPolicy Bypass -File Tools\\InstallerUrlChecker.ps1 {url}"
        )
        new_product_version = re.search(r"^ProductVersion:\s*(\S+)\s*$", new_version_check_output, re.MULTILINE).group(1)
        new_versions.append(new_product_version)
    log(f"Resolved {len(new_versions)} IObit version(s).")
    
    for package_name, new_version, file in zip(packages, new_versions, files):
        old_version_folder = Path(file).parent
        package_folder = old_version_folder.parent
        new_version_folder = package_folder / new_version
        update_package(
            updater,
            f"{package_name.split(".")[-1]} {new_version}",
            replace=old_version_folder
        )
        run_with_stream(
            f"\"{sys.executable}\" update\\releasenotes\\releasenotes_{updater}.py {new_version_folder} --no-backup"
        )
        log(f"Queueing package submission for IObit version: {new_version}")
        submit_package("wingetcreate", new_version_folder)
        changes.append({"package": package_name, "before": old_version_folder.name, "after": new_version, "submission_key": str(new_version_folder)})
    
    if is_main:
        submit_flush()
    
    return changes

if __name__ == "__main__":
    from _update_all import inject_context
    inject_context(globals())
    run()
