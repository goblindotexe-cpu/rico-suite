"""Build the installable WoW Forever bundle from the reviewed addon trees."""

import argparse
import os
import re
import stat
from pathlib import Path, PurePosixPath
from tempfile import NamedTemporaryFile
from xml.etree import ElementTree
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parent
ADDONS = ("RicoFishing", "RicoLoot", "RicoPlates")
OUTPUT = ROOT / "dist" / "RicoSuite-forever.zip"
REQUIRED_FILES = {
    "RicoFishing": (
        "LICENSE.txt", "LICENSE_GatherLite.txt", "LICENSE-RICO-SHARED.txt", "SOURCES_NL.txt",
        "Media/PromptSmoke.tga", "Media/CatchStripSmoke.tga",
    ),
    "RicoLoot": (
        "COPYING.txt", "SOURCES_NL.txt", "Licenses/GPL-3.0.txt", "Licenses/RicoShared-MIT.txt",
        "Licenses/Lootified-THIRD_PARTY_NOTICES.md", "Source/build_ricoloot_data.py",
        "Source/input-manifest.json", "Source/lootified-data.json", "Source/lootinsight-data.json",
        "Source/cmangos/build_reference.py", "Source/cmangos/classic_reference.json",
    ),
    "RicoPlates": (
        "LICENSE.txt", "MiningReference-LICENSE.txt", "MiningReference-SOURCE.json", "Vendor/SPF/LICENSE",
        "Vendor/SPF/THIRD_PARTY.md", "Vendor/SPF/media/Dot.tga",
        "Vendor/SPF/media/Icon.tga", "Vendor/SPF/media/Zeppelin.tga",
        *(f"Media/{name}.tga" for name in ("Arrow", "Bar", "Bubble", "Icon", "Quest", "QuestKill", "QuestLoot")),
    ),
}
PUBLIC_SUFFIXES = {".blp", ".dds", ".json", ".lua", ".md", ".ogg", ".py", ".tga", ".toc", ".txt", ".wav", ".xml"}
PUBLIC_BASENAMES = {"authors", "cmangos-authors", "license", "copying", "notice"}
PRIVATE_NAMES = {
    "backup", "backups", "cache", "credentials", "databasestate", "logs",
    "private", "savedvariables", "screenshots", "secrets", "tokens", "wtf", "__pycache__",
}
INVALID_MEMBER = re.compile(r'[<>:"\\|?*\x00-\x1f]')
LOOT_CACHE_LOADERS = {
    "DataObserved.lua": (
        "local _, R = ...",
        "local cache = RicoLootEverloot",
        "if cache and cache.ApplyObserved then cache.ApplyObserved(R) end",
    ),
    "DataSyncStatus.lua": (
        "local _, R = ...",
        'R.Data.syncStatus = { schema = 1, state = "idle" }',
        "local cache = RicoLootEverloot",
        "if cache and cache.ApplyStatus then cache.ApplyStatus(R) end",
    ),
}


def validate_member(path, relative):
    mode = path.lstat()
    if stat.S_ISLNK(mode.st_mode) or getattr(mode, "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT:
        raise ValueError(f"Links are not allowed in the release: {relative}")
    name = path.name.lower()
    if (name.startswith(".") or name.endswith((" ", ".", "~")) or INVALID_MEMBER.search(name)
            or name.split(".", 1)[0] in PRIVATE_NAMES or re.search(r"[._-](bak|backup|old|previous)([._-]|$)", name)):
        raise ValueError(f"Local or invalid file in the release: {relative}")
    return mode.st_mode


def collect_files(addons):
    if not stat.S_ISDIR(validate_member(addons, addons)):
        raise ValueError(f"Expected an addon source directory: {addons}")
    files = {}
    names = set()
    for addon in ADDONS:
        directory = addons / addon
        if not stat.S_ISDIR(validate_member(directory, addon)):
            raise ValueError(f"Expected an addon directory: {addon}")
        for path in directory.rglob("*"):
            relative = path.relative_to(addons).as_posix()
            mode = validate_member(path, relative)
            folded = relative.casefold()
            if folded in names:
                raise ValueError(f"Case-insensitive path collision: {relative}")
            names.add(folded)
            if stat.S_ISDIR(mode):
                continue
            if not stat.S_ISREG(mode) or (path.suffix.lower() not in PUBLIC_SUFFIXES and path.name.lower() not in PUBLIC_BASENAMES):
                raise ValueError(f"Unexpected release file: {relative}")
            files[relative] = path
    return files


def validate_addon(files, addon):
    toc = f"{addon}/{addon}.toc"
    for relative in (toc, *(f"{addon}/{name}" for name in REQUIRED_FILES[addon])):
        if relative not in files or not files[relative].stat().st_size:
            raise ValueError(f"Required release file is missing or empty: {relative}")

    checked_xml = set()

    def validate_reference(source, reference):
        target = PurePosixPath(reference.replace("\\", "/"))
        relative = (PurePosixPath(source).parent / target).as_posix()
        if target.is_absolute() or ".." in target.parts or relative not in files:
            raise ValueError(f"{source} references a missing or invalid file: {reference}")
        if target.suffix.lower() == ".xml" and relative not in checked_xml:
            checked_xml.add(relative)
            for element in ElementTree.parse(files[relative]).iter():
                if element.tag.rsplit("}", 1)[-1] in {"Include", "Script"} and "file" in element.attrib:
                    validate_reference(relative, element.attrib["file"])

    toc_lines = files[toc].read_text(encoding="utf-8-sig").splitlines()
    if not any(re.fullmatch(r"##\s*Interface\s*:\s*16\d{3}(?:\s*,\s*16\d{3})*\s*", line) for line in toc_lines):
        raise ValueError(f"{toc} is missing a WoW Forever interface version")
    entries = [line.strip() for line in toc_lines if line.strip() and not line.lstrip().startswith("#")]
    if not entries:
        raise ValueError(f"{toc} does not load any files")
    for entry in entries:
        validate_reference(toc, entry)

    if addon == "RicoLoot":
        for name, expected in LOOT_CACHE_LOADERS.items():
            relative = f"{addon}/{name}"
            if relative not in files:
                raise ValueError(f"Required cache loader is missing: {relative}")
            lines = files[relative].read_text(encoding="utf-8-sig").splitlines()
            code = tuple(line.strip() for line in lines if line.strip() and not line.lstrip().startswith("--"))
            if code != expected:
                raise ValueError(f"Expected a clean public cache loader, not generated loot or local status: {relative}")


def package(addons, output):
    if output.resolve().is_relative_to(addons.resolve()):
        raise ValueError("The release archive must be outside the addon source tree")
    files = collect_files(addons)
    for addon in ADDONS:
        validate_addon(files, addon)

    output.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(dir=output.parent, prefix=f".{output.name}.", delete=False) as temp:
        temporary_path = Path(temp.name)
    try:
        with ZipFile(temporary_path, "w") as archive:
            for name, path in sorted(files.items()):
                entry = ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = (stat.S_IFREG | 0o644) << 16
                archive.writestr(entry, path.read_bytes(), compress_type=ZIP_DEFLATED, compresslevel=9)
        os.replace(temporary_path, output)
    finally:
        temporary_path.unlink(missing_ok=True)
    return len(files)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--addons", type=Path, default=ROOT / "addons", help="reviewed addon source directory")
    parser.add_argument("--output", type=Path, default=OUTPUT, help="destination ZIP file")
    args = parser.parse_args()
    try:
        file_count = package(args.addons, args.output)
    except (OSError, ValueError, ElementTree.ParseError) as error:
        parser.exit(1, f"Packaging failed: {error}\n")
    print(f"Packaged {file_count} files in {args.output}")


if __name__ == "__main__":
    main()
