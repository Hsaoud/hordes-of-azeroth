import hashlib
import io
from pathlib import Path
import sys
import zipfile


root = Path(__file__).resolve().parent.parent
package = Path(sys.argv[1]).resolve()
prefix = "HordesOfAzeroth-Coop/"
with zipfile.ZipFile(package) as archive:
    names = archive.namelist()
    if len(names) != len(set(names)) or any(not name.startswith(prefix) for name in names):
        raise ValueError("Invalid package layout or duplicate files")
    for relative in (
        "WoW.exe", "HordesOfAzeroth.exe", "JOUER-ENSEMBLE.txt",
        "HordesOfAzeroth/coop-build.txt", "config/mariadb.ini",
        "server/mariadb/bin/mariadbd.exe", "server/mariadb-data/ibdata1",
        "server/mariadb-data/logs/system_fingerprint_usage.ibd",
        "server/data/5875/dbc/ChrClasses.dbc",
        "server/run/vcruntime140.dll", "server/run/msvcp140.dll",
        "tools/vcruntime140.dll", "tools/vcruntime140_1.dll",
        "HordesOfAzeroth-Coop-Sources.zip", "HordesOfAzeroth-Rust-Licenses.zip",
    ):
        if archive.getinfo(prefix + relative).file_size == 0:
            raise ValueError("Empty required file: " + relative)
    for relative, compiled in (
        ("HoALauncher.exe", "tools/launcher/bin/HoALauncher.exe"),
        ("HordesOfAzerothClientFix.dll", "tools/clientfix/build/Release/HordesOfAzerothClientFix.dll"),
        ("tools/hoa-coop.exe", "tools/coop/target/release/hoa-coop.exe"),
        ("server/run/mangosd.exe", "server/run/mangosd.exe"),
        ("server/run/realmd.exe", "server/run/realmd.exe"),
        ("Interface/AddOns/HordesOfAzeroth/VanillaBonkCoop.lua", "Interface/AddOns/HordesOfAzeroth/VanillaBonkCoop.lua"),
    ):
        if hashlib.sha256(archive.read(prefix + relative)).digest() != hashlib.sha256((root / compiled).read_bytes()).digest():
            raise ValueError("Outdated packaged file: " + relative)
    for relative in ("VanillaBonkNavigation.lua", "VanillaBonkMenu.lua", "VanillaBonkTracker.lua"):
        local = root / "Interface" / "AddOns" / "HordesOfAzeroth" / relative
        if archive.read(prefix + "Interface/AddOns/HordesOfAzeroth/" + relative) != local.read_bytes():
            raise ValueError("Outdated interface: " + relative)
    if prefix + "HordesOfAzeroth/coop-invitation.txt" in names:
        raise ValueError("A private invitation was included in the package")
    for name in ("GlueXML.toc", "BonkGlue.lua", "BonkGlue.xml", "BonkGluePad.lua", "BonkGluePad.xml"):
        if archive.read(prefix + "Interface/GlueXML/" + name) != (root / "Interface/GlueXML" / name).read_bytes():
            raise ValueError("Outdated login interface: " + name)
    fingerprint = archive.read(prefix + "HordesOfAzeroth/coop-build.txt").decode("ascii").strip()
    if fingerprint.lower() != hashlib.sha256(archive.read(prefix + "server/run/mangosd.exe")).hexdigest():
        raise ValueError("Incorrect compatibility fingerprint")
    with zipfile.ZipFile(io.BytesIO(archive.read(prefix + "HordesOfAzeroth-Coop-Sources.zip"))) as sources:
        source_names = sources.namelist()
        if "server/core/src/game/Bonk/BonkCoop.cpp" not in source_names:
            raise ValueError("Missing modified server source")
        if any("__pycache__" in name or name.endswith(".pyc") for name in source_names):
            raise ValueError("Generated Python caches in source archive")
    print("PASS complete game, database, native runtime, matching builds and source bundle", flush=True)
    print("Checking every archived file...", flush=True)
    corrupt = archive.testzip()
    if corrupt is not None:
        raise ValueError("Corrupt entry: " + corrupt)
    print(f"PASS CRC integrity of all {len(names)} entries", flush=True)
with package.open("rb") as stream:
    checksum = hashlib.file_digest(stream, "sha256").hexdigest()
package.with_suffix(package.suffix + ".sha256").write_text(checksum + "  " + package.name + "\n", encoding="ascii")
print(f"PASS SHA256 {checksum}", flush=True)
print(f"Complete archive: {package.stat().st_size} bytes", flush=True)
