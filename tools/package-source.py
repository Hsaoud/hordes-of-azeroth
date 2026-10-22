import csv
import io
import json
import os
from pathlib import Path
import subprocess
import zipfile


root = Path(__file__).resolve().parent.parent
output = root / "release" / "coop"
output.mkdir(parents=True, exist_ok=True)
source = output / "HordesOfAzeroth-Coop-Sources.zip"
with zipfile.ZipFile(source, "w", zipfile.ZIP_DEFLATED, strict_timestamps=False) as archive:
    for checkout, prefix in ((root, ""), (root / "server" / "core", "server/core/")):
        listed = subprocess.check_output(["git", "-C", str(checkout), "ls-files", "-c", "-o", "--exclude-standard", "-z"])
        for relative in sorted(set(listed.decode("utf-8").split("\0"))):
            path = checkout / relative
            if relative and path.is_file():
                archive.write(path, prefix + relative.replace("\\", "/"))
    archive.writestr("SOURCE-SNAPSHOT.txt", "Complete working source snapshot for this co-op edition. See COOP.md and BUILDING.md. The client and generated game data are excluded.\n")

cargo = root / "tools" / "coop" / ".cargo" / "bin" / "cargo.exe"
if not cargo.exists():
    cargo = "cargo"
metadata = json.loads(subprocess.check_output([str(cargo), "metadata", "--locked", "--offline", "--filter-platform", "x86_64-pc-windows-msvc", "--format-version", "1", "--manifest-path", str(root / "tools" / "coop" / "Cargo.toml")]))
notices = output / "HordesOfAzeroth-Rust-Licenses.zip"
with zipfile.ZipFile(notices, "w", zipfile.ZIP_DEFLATED, strict_timestamps=False) as archive:
    inventory = io.StringIO()
    writer = csv.writer(inventory)
    writer.writerow(["Package", "Version", "License", "Source"])
    for package in metadata["packages"]:
        if package["name"] == "hoa-coop":
            continue
        writer.writerow([package["name"], package["version"], package.get("license", ""), package.get("repository", "")])
        directory = Path(package["manifest_path"]).parent
        candidates = {path for path in directory.iterdir() if path.is_file() and path.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE", "COPYRIGHT"))}
        if package.get("license_file"):
            license_file = directory / package["license_file"]
            if license_file.is_file():
                candidates.add(license_file)
        for path in sorted(candidates):
            archive.write(path, f"{package['name']}-{package['version']}/{path.name}")
    archive.writestr("DEPENDENCIES.csv", inventory.getvalue())
print("Source snapshot: " + str(source))
print("Rust notices: " + str(notices))
