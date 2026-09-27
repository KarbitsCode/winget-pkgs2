def run(*, is_main=(__name__ == "__main__")):
    manifests = load_manifest()
    _, data = get_manifest(manifests, "installer")
    installer_url = data.get("Installers")[0].get("InstallerUrl")
    release_date = data.get("ReleaseDate")
    output, data = get_manifest(manifests, "locale.en-US")
    version = data.get("PackageVersion")
    
    with tempfile.TemporaryDirectory(prefix="innounp_") as extract_dir_str:
        extract_dir = Path(extract_dir_str)
        
        installer = extract_dir / "installer.bin"
        installer.write_bytes(fetch(installer_url, timeout=30).content)
        run_with_stream(
            f"innounp -x -y -b -d{extract_dir} {str(installer)} *.txt *.ini *.log"
        )
        
        header_re = re.compile(
            r'^\s*(?:Release\s+)?[Vv](\d+(?:\.\d+)*)\s*'
            r'(?:-\s*)?'
            r'\(?\s*(\d{4}[-.]\d{2}[-.]\d{2}|[A-Za-z]+\.?\s+\d{1,2},\s*\d{4})?\s*\)?\s*$'
        )
        
        results = []
        for f in sorted(extract_dir.rglob("*")):
            if not f.is_file() or f == installer:
                continue
            
            # Detect encoding
            raw = f.read_bytes()
            if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
                text = raw.decode("utf-16", errors="ignore")
            elif raw.startswith(b"\xef\xbb\xbf"):
                text = raw.decode("utf-8-sig", errors="ignore")
            else:
                text = raw.decode("utf-8", errors="ignore")
            
            # Count how many lines look like release-note version headers
            score = sum(
                1 for line in text.splitlines()
                # Release v3.2 - November 23, 2022
                # Release v1.2 - Jun 10, 2021
                # v6.4
                # Release v1.4
                # v8.0 (2026-09-21)
                if header_re.match(line.strip())
            )
            results.append((f, score, text))
        
        results.sort(key=lambda r: (
            len(r[0].relative_to(extract_dir).parts), # shallower folders first
            0 if (r[0].stem.lower() == "english" or r[0].stem.lower() == r[0].parent.name.lower()) else 1, # "english" or parent filename first
            -r[1] # highest score first
        ))
        
        log(f"Checked {len(results)} .txt/.ini/.log file(s):\n")
        for f, score, _ in results:
            marker = "  <-- likely release notes" if score > 0 else ""
            log(f"  {score:>2} match(es)  {f.relative_to(extract_dir)}{marker}")
        
        candidates = [r for r in results if r[1] > 0]
        if not candidates:
            log("\nNothing matched the release-notes shape.")
            sys.exit(2)
        
        winner, _, winner_text = candidates[0] # the first
        log(f"\nBest candidate: {winner.relative_to(extract_dir)}")
        # log(f"Found raw release notes:\n{winner_text}")
        
        # Now for the release notes
        output_lines = []
        in_block = False
        
        for line in winner_text.splitlines():
            line = line.strip()
            if not line:
                continue
            
            header = header_re.match(line.strip())
            if header:
                raw_version, raw_date = header.groups()
                if raw_date is None:
                    date = release_date
                else:
                    date = raw_date
                    for fmt in ["%Y-%m-%d", "%Y.%m.%d", "%B %d, %Y", "%b %d, %Y"]:
                        try:
                            date = datetime.strptime(raw_date, fmt).strftime("%Y-%m-%d")
                            break
                        except ValueError:
                            pass
                
                if output_lines:
                    break # done
                
                output_lines.append(f"v{raw_version} ({date})")
                in_block = True
                continue
            
            if not in_block:
                continue
            
            # bullet lines: "+ text", "* text
            if line.startswith("+") or line.startswith("*"):
                text_part = line[1:].strip()
            else:
                continue
            
            if text_part:
                output_lines.append(f"- {text_part}")
        
        release_notes = output_lines
        log(f"Release notes for version {version}:\n{"\n".join(release_notes)}")
        create_backup(output)
        log(f"Writing new release notes...")
        write_release_notes(output, data, output_lines)
        log("Done.")


if __name__ == "__main__":
    from _common import inject_context
    inject_context(globals())
    run()
