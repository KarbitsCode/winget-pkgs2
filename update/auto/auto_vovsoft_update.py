def run():
    check_output = run_with_stream(
        f"\"{sys.executable}\" Tools\\TestLinks.py manifests\\v\\VovSoft\\*.installer.*",
    )

    files = []
    urls = []
    packages = []
    seen = set()

    blocks = check_output.strip().split("\n\n")

    for block in blocks:
        if "Installer hash mismatch!" not in block:
            continue

        file = re.search(r"^File:\s+(.+)$", block, re.MULTILINE).group(1)
        url = re.search(r"^URL:\s+(\S+)$", block, re.MULTILINE).group(1)

        if not url.endswith(".exe"):
            continue

        package = file.rsplit("\\", 1)[1].replace(".installer.yaml", "")

        key = (file, url, package)
        if key in seen:
            continue

        seen.add(key)
        files.append(file)
        urls.append(url)
        packages.append(package)

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

    for package, version, file in zip(packages, new_versions, files):
        old_version_folder = Path(file).parent
        package_folder = old_version_folder.parent
        new_version_folder = package_folder / version
        run_with_stream(
            f"update\\{Path(__file__).stem.removeprefix("auto_")}.bat {package.split(".")[1]} {version}"
        )
        shutil.rmtree(old_version_folder)
        run_with_stream(
            f"git add {package_folder} && git --no-pager diff HEAD"
        )
        submit_output = run_with_stream(
            f"wingetcreate submit {new_version_folder} --no-open"
        )
        pr_url = re.search(r"^Pull request can be found here:\s*(.+)$", submit_output, re.MULTILINE).group(1).strip()
        run_with_stream(
            f"powershell -ExecutionPolicy Bypass -File Tools\\UpdatePRBody.ps1 Tools\\PRBodyTemplate\\PRBodyModify.md -pr {pr_url.split('/')[-1]}"
        )

if __name__ == "__main__":
    from auto_update_all import inject_context
    inject_context(globals())
    run()
