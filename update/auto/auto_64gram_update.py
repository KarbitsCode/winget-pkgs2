def run(*, is_main=(__name__ == "__main__")):
    selfname = Path(__file__).stem
    updater = selfname.lstrip("_").removeprefix("auto_")
    
    log("Checking releases...")
    versions = check_releases("https://api.github.com/repos/TDesktop-x64/tdesktop/releases")[:10]
    sixtyfourgram_dir = Path("manifests\\6\\64Gram\\64Gram")
    existing = {
        folder.name
        for folder in sixtyfourgram_dir.iterdir()
        if folder.is_dir()
    }
    new_versions = [
        version
        for version in versions
        if version not in existing
    ]
    log(f"Found {len(new_versions)} new 64Gram release(s).")
    changes = []
    
    for new_version in new_versions:
        package_folder = sixtyfourgram_dir
        new_version_folder = package_folder / new_version
        update_package_local(
            updater,
            package_folder,
            f"{new_version}"
        )
        run_with_stream(
            f"\"{sys.executable}\" update\\releasenotes\\releasenotes_{updater}.py {new_version_folder} --no-backup"
        )
        changes.append({"package": "64Gram.64Gram", "before": "—", "after": new_version, "submission_key": str(new_version_folder)})
        log(f"Queueing package submission for 64Gram version: {new_version}")
        submit_package("wingetcreate", new_version_folder)
    
    if is_main:
        submit_flush()
    
    return changes


if __name__ == "__main__":
    from _update_all import inject_context
    inject_context(globals())
    run()
