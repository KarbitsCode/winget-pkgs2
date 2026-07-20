def run():
    files, urls, packages = check_mismatches("manifests\\v\\VovSoft")
    
    print(files)
    print(urls)
    print(packages)
    
    new_versions = []
    
    for url in urls:
        new_version_check_output = run_with_stream(
            f"powershell -ExecutionPolicy Bypass -File Tools\\InstallerUrlChecker.ps1 {url}"
        )
        new_product_version = re.search(r"^ProductVersion:\s*(.+)$", new_version_check_output, re.MULTILINE).group(1).strip()
        new_versions.append(new_product_version)
    
    print(new_versions)
    
    for package_name, new_version, file in zip(packages, new_versions, files):
        updater = Path(__file__).stem.removeprefix("auto_")
        old_package_folder = Path(file).parent
        new_version_folder = update_and_replace(
            updater,
            old_package_folder,
            package_name,
            new_version
        )
        # submit_package("wingetcreate", new_version_folder, "--replace --no-open")


if __name__ == "__main__":
    from auto_update_all import inject_context
    inject_context(globals())
    run()
