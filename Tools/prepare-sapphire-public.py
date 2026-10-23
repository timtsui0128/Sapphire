#!/usr/bin/env python3
"""Prepare an isolated Xcode 26.3 project for Sapphire's public source checkout."""

import argparse
import json
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path


def write_if_changed(path, content):
    """Keep generated project mtimes stable when their contents are unchanged."""
    if isinstance(content, str):
        content = content.encode("utf-8")
    if path.exists() and path.read_bytes() == content:
        return
    path.write_bytes(content)


def openstep(value, depth=0):
    indentation = "\t" * depth
    child_indent = "\t" * (depth + 1)
    if isinstance(value, dict):
        entries = (
            f"{child_indent}{json.dumps(str(key), ensure_ascii=False)} = "
            f"{openstep(item, depth + 1)};"
            for key, item in value.items()
        )
        return "{\n" + "\n".join(entries) + f"\n{indentation}}}"
    if isinstance(value, list):
        entries = (f"{child_indent}{openstep(item, depth + 1)}," for item in value)
        return "(\n" + "\n".join(entries) + f"\n{indentation})"
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, (int, float)):
        return str(value)
    return json.dumps(value, ensure_ascii=False)


def prepare(repo, destination):
    source_project = repo / "Sapphire.xcodeproj"
    destination = destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    raw = subprocess.check_output(
        ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(source_project / "project.pbxproj")]
    )
    project = json.loads(raw)
    objects = project["objects"]
    project["objectVersion"] = 77
    root = objects[project["rootObject"]]
    root["preferredProjectObjectVersion"] = 77
    root["projectDirPath"] = str(repo)
    root.pop("projectReferences", None)
    root.pop("minimizedProjectReferenceProxies", None)
    root["attributes"]["LastUpgradeCheck"] = "2630"

    # This upstream self-reference otherwise opens the original format-100 project.
    self_reference = "DA262AE22EA484A70027CA69"
    for obj in objects.values():
        if "children" in obj:
            obj["children"] = [item for item in obj["children"] if item != self_reference]
    objects.pop(self_reference, None)

    # Xcode 26.5 stores these properties differently from Xcode 26.3.
    destinations = {
        "None": 0, "Wrapper": 1, "Executables": 6, "Resources": 7,
        "Frameworks": 10, "SharedFrameworks": 11, "SharedSupport": 12, "PlugIns": 13,
    }
    for obj in objects.values():
        if obj["isa"].endswith("BuildPhase"):
            obj.setdefault("buildActionMask", 2147483647)
            obj.setdefault("runOnlyForDeploymentPostprocessing", 0)
        if obj["isa"] == "PBXCopyFilesBuildPhase" and "dstSubfolder" in obj:
            obj["dstSubfolderSpec"] = destinations[obj.pop("dstSubfolder")]
        if obj["isa"] == "PBXShellScriptBuildPhase" and isinstance(obj.get("shellScript"), list):
            obj["shellScript"] = "\n".join(obj["shellScript"])
        # Upstream system references assume the author's checkout directory depth.
        path = obj.get("path", "")
        if re.match(r"^(?:\.\./)+System/", path):
            system_path = path[path.index("System/"):]
            if obj.get("lastKnownFileType") == "wrapper.framework":
                obj["path"] = system_path
                obj["sourceTree"] = "SDKROOT"
            else:
                obj["path"] = "/" + system_path
                obj["sourceTree"] = "<absolute>"
        if obj.get("name") == "IOKit.framework" and obj.get("sourceTree") == "DEVELOPER_DIR":
            obj["path"] = "System/Library/Frameworks/IOKit.framework"
            obj["sourceTree"] = "SDKROOT"

    def settings_for(target_id):
        target = objects[target_id]
        configuration_list = objects[target["buildConfigurationList"]]
        return [
            objects[identifier]["buildSettings"]
            for identifier in configuration_list["buildConfigurations"]
        ]

    sapphire = objects["DA46CF752DCBCA0000F00EC5"]
    # The repository supplies fallback implementations for omitted premium sources.
    for settings in settings_for("DA46CF752DCBCA0000F00EC5"):
        exclusions = []
        if (repo / "Sapphire/Services/Gemini/GeminiLiveManager.swift").exists():
            exclusions.append("*/Sapphire/Stubs/GeminiLiveManagerStub.swift")
        settings["EXCLUDED_SOURCE_FILE_NAMES"] = " ".join(exclusions)
        # Diagnose missing public fallback APIs across all frontend batches in one
        # build. Keep this on Sapphire only, including its architecture override.
        for key in ("OTHER_SWIFT_FLAGS", "OTHER_SWIFT_FLAGS[arch=*]"):
            flags = settings.get(key, "")
            if isinstance(flags, list):
                flags = " ".join(flags)
            option = "-continue-building-after-errors"
            if option not in flags.split():
                settings[key] = " ".join(part for part in (flags, option) if part)
    # Local builds should never run the publisher's symbol-upload task.
    sapphire["buildPhases"] = [
        identifier for identifier in sapphire["buildPhases"]
        if objects[identifier].get("name") != "Upload Crashlytics Symbols"
    ]

    # Keep public placeholder targets, while removing unavailable private source inputs.
    objects["CAFE10000000000000000BAA"]["files"] = ["CAFE100000000000000007AA"]
    objects["CAFE200000000000000007BB"]["files"] = ["CAFE200000000000000006BB"]
    file_provider_source = objects["F2DE000000000000000002BB"]
    file_provider_source["path"] = "PublicExtensionStubs/FileProvider/FileProviderExtension.swift"
    file_provider_source["sourceTree"] = "SOURCE_ROOT"
    objects["F2DE00000000000000000EBB"]["files"] = ["F2DE000000000000000013BB"]
    for settings in settings_for("F2DE00000000000000000ABB"):
        settings["INFOPLIST_FILE"] = "PublicExtensionStubs/FileProvider/Info.plist"
        settings["CODE_SIGN_ENTITLEMENTS"] = ""

    prepared = destination / "project.pbxproj"
    write_if_changed(prepared, "// !$*UTF8*$!\n" + openstep(project) + "\n")
    subprocess.run(["/usr/bin/plutil", "-lint", str(prepared)], check=True)

    # Copy exact upstream pins; package resolution never edits the original project.
    relative_pins = Path("project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    pins = destination / relative_pins
    pins.parent.mkdir(parents=True, exist_ok=True)
    write_if_changed(pins, (source_project / relative_pins).read_bytes())
    workspace = destination / "project.xcworkspace/contents.xcworkspacedata"
    write_if_changed(
        workspace,
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Workspace version="1.0"><FileRef location="self:"/></Workspace>\n'
    )
    schemes = destination / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    tree = ET.parse(source_project / "xcshareddata/xcschemes/Sapphire.xcscheme")
    for reference in tree.iter("BuildableReference"):
        reference.set("ReferencedContainer", "container:" + str(destination))
    tree.getroot().set("LastUpgradeVersion", "2630")
    write_if_changed(
        schemes / "Sapphire.xcscheme",
        ET.tostring(tree.getroot(), encoding="utf-8", xml_declaration=True),
    )
    print(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    repository = arguments.repo.resolve()
    output = arguments.output or repository / "output/public-build/Sapphire.xcodeproj"
    if output.resolve() == (repository / "Sapphire.xcodeproj").resolve():
        parser.error("Output must be separate from the checked-in Xcode project")
    prepare(repository, output)
