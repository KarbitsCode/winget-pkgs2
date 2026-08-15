def run(*, is_main=(__name__ == "__main__")):
    selfname = Path(__file__).stem.lstrip("_").removeprefix("auto_")
    files, urls, packages = check_mismatches("manifests\\r\\RootsMagic\\RootsMagic")
    
    for i in range(len(urls) - 1, -1, -1):
        if not urls[i].endswith(".exe"):
            del files[i]
            del urls[i]
            del packages[i]
    
    print(files)
    print(urls)
    print(packages)
    
    new_versions = []
    for url in urls:
        new_version_check_output = run_with_stream(
            f"powershell -ExecutionPolicy Bypass -File Tools\\InstallerUrlChecker.ps1 {url}"
        )
        new_product_version = re.search(r"^ProductVersion:\s*(\S+)\s*$", new_version_check_output, re.MULTILINE).group(1)
        new_versions.append(new_product_version)
    print(new_versions)
    
    for package_name, new_version, file in zip(packages, new_versions, files):
        updater = selfname
        old_version_folder = Path(file).parent
        package_folder = old_version_folder.parent
        new_version_folder = package_folder / new_version
        update_and_replace(
            updater,
            package_folder,
            f"{new_version}",
            replace=old_version_folder
        )
        submit_package("wingetcreate", new_version_folder, "--replace")
    
    if is_main:
        submit_flush()

if __name__ == "__main__":
    from _update_all import inject_context
    inject_context(globals())
    run()
