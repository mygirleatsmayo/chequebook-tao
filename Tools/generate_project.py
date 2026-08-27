#!/usr/bin/env python3
"""Generate ChequebookTao.xcodeproj/project.pbxproj.

The project file is deterministic: object IDs are derived from stable strings,
so regenerating produces the same file unless sources were added or removed.

Run from the repo root after adding/removing Swift files:

    python3 Tools/generate_project.py
"""

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "ChequebookTao"
BUNDLE_ID = "com.mygirleatsmayo.ChequebookTao"
DEPLOYMENT_TARGET = "14.0"


def read_version():
    """Marketing version and build number from the VERSION file.

    Line 1 is CFBundleShortVersionString (0.2.0). Line 2 is CFBundleVersion,
    a monotonically increasing integer. Blank lines and # comments are ignored.
    """
    path = os.path.join(ROOT, "VERSION")
    with open(path) as handle:
        lines = [line.strip() for line in handle if line.strip() and not line.startswith("#")]
    if len(lines) < 2:
        sys.exit(f"VERSION must contain a marketing version and a build number, got {lines!r}")
    return lines[0], lines[1]


MARKETING_VERSION, PROJECT_VERSION = read_version()


def uid(key: str) -> str:
    """A stable 24-hex-char object ID."""
    return hashlib.md5(key.encode()).hexdigest()[:24].upper()


def quote(s: str) -> str:
    """Quote a pbxproj string when required."""
    safe = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./")
    if s and all(c in safe for c in s):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def swift_sources():
    files = []
    for group in ("Sources/Core", "Sources/App"):
        directory = os.path.join(ROOT, group)
        for name in sorted(os.listdir(directory)):
            if name.endswith(".swift"):
                files.append(f"{group}/{name}")
    return files


def main():
    sources = swift_sources()
    info_plist = "Sources/App/Info.plist"

    lines = []
    add = lines.append

    add("// !$*UTF8*$!")
    add("{")
    add("\tarchiveVersion = 1;")
    add("\tclasses = {")
    add("\t};")
    add("\tobjectVersion = 56;")
    add("\tobjects = {")

    # ---- PBXBuildFile
    add("")
    add("/* Begin PBXBuildFile section */")
    for path in sources:
        name = os.path.basename(path)
        add(
            f"\t\t{uid('build:' + path)} /* {name} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {uid('ref:' + path)} /* {name} */; }};"
        )
    add("/* End PBXBuildFile section */")

    # ---- PBXFileReference
    add("")
    add("/* Begin PBXFileReference section */")
    for path in sources:
        name = os.path.basename(path)
        add(
            f"\t\t{uid('ref:' + path)} /* {name} */ = "
            f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            f"path = {quote(name)}; sourceTree = \"<group>\"; }};"
        )
    add(
        f"\t\t{uid('ref:' + info_plist)} /* Info.plist */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = text.plist.xml; "
        f"path = Info.plist; sourceTree = \"<group>\"; }};"
    )
    add(
        f"\t\t{uid('ref:product')} /* {PROJECT_NAME}.app */ = "
        f"{{isa = PBXFileReference; explicitFileType = wrapper.application; "
        f"includeInIndex = 0; path = {quote(PROJECT_NAME + '.app')}; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    add("/* End PBXFileReference section */")

    # ---- PBXGroup
    core_files = [p for p in sources if p.startswith("Sources/Core/")]
    app_files = [p for p in sources if p.startswith("Sources/App/")]

    def child_line(path):
        return f"\t\t\t\t{uid('ref:' + path)} /* {os.path.basename(path)} */,"

    add("")
    add("/* Begin PBXGroup section */")

    add(f"\t\t{uid('group:main')} = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{uid('group:sources')} /* Sources */,")
    add(f"\t\t\t\t{uid('group:products')} /* Products */,")
    add("\t\t\t);")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    add(f"\t\t{uid('group:sources')} /* Sources */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{uid('group:core')} /* Core */,")
    add(f"\t\t\t\t{uid('group:app')} /* App */,")
    add("\t\t\t);")
    add("\t\t\tpath = Sources;")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    add(f"\t\t{uid('group:core')} /* Core */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    for path in core_files:
        add(child_line(path))
    add("\t\t\t);")
    add("\t\t\tpath = Core;")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    add(f"\t\t{uid('group:app')} /* App */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    for path in app_files:
        add(child_line(path))
    add(f"\t\t\t\t{uid('ref:' + info_plist)} /* Info.plist */,")
    add("\t\t\t);")
    add("\t\t\tpath = App;")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    add(f"\t\t{uid('group:products')} /* Products */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{uid('ref:product')} /* {PROJECT_NAME}.app */,")
    add("\t\t\t);")
    add("\t\t\tname = Products;")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")
    add("/* End PBXGroup section */")

    # ---- PBXNativeTarget
    add("")
    add("/* Begin PBXNativeTarget section */")
    add(f"\t\t{uid('target:app')} /* {PROJECT_NAME} */ = {{")
    add("\t\t\tisa = PBXNativeTarget;")
    add(f"\t\t\tbuildConfigurationList = {uid('cfglist:target')} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */;")
    add("\t\t\tbuildPhases = (")
    add(f"\t\t\t\t{uid('phase:sources')} /* Sources */,")
    add(f"\t\t\t\t{uid('phase:frameworks')} /* Frameworks */,")
    add(f"\t\t\t\t{uid('phase:resources')} /* Resources */,")
    add("\t\t\t);")
    add("\t\t\tbuildRules = (")
    add("\t\t\t);")
    add("\t\t\tdependencies = (")
    add("\t\t\t);")
    add(f"\t\t\tname = {quote(PROJECT_NAME)};")
    add(f"\t\t\tproductName = {quote(PROJECT_NAME)};")
    add(f"\t\t\tproductReference = {uid('ref:product')} /* {PROJECT_NAME}.app */;")
    add("\t\t\tproductType = \"com.apple.product-type.application\";")
    add("\t\t};")
    add("/* End PBXNativeTarget section */")

    # ---- PBXProject
    add("")
    add("/* Begin PBXProject section */")
    add(f"\t\t{uid('project')} /* Project object */ = {{")
    add("\t\t\tisa = PBXProject;")
    add("\t\t\tattributes = {")
    add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    add("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    add("\t\t\t\tLastUpgradeCheck = 1500;")
    add("\t\t\t};")
    add(f"\t\t\tbuildConfigurationList = {uid('cfglist:project')} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */;")
    add("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    add("\t\t\tdevelopmentRegion = en;")
    add("\t\t\thasScannedForEncodings = 0;")
    add("\t\t\tknownRegions = (")
    add("\t\t\t\ten,")
    add("\t\t\t\tBase,")
    add("\t\t\t);")
    add(f"\t\t\tmainGroup = {uid('group:main')};")
    add(f"\t\t\tproductRefGroup = {uid('group:products')} /* Products */;")
    add("\t\t\tprojectDirPath = \"\";")
    add("\t\t\tprojectRoot = \"\";")
    add("\t\t\ttargets = (")
    add(f"\t\t\t\t{uid('target:app')} /* {PROJECT_NAME} */,")
    add("\t\t\t);")
    add("\t\t};")
    add("/* End PBXProject section */")

    # ---- Build phases
    add("")
    add("/* Begin PBXSourcesBuildPhase section */")
    add(f"\t\t{uid('phase:sources')} /* Sources */ = {{")
    add("\t\t\tisa = PBXSourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for path in sources:
        add(f"\t\t\t\t{uid('build:' + path)} /* {os.path.basename(path)} in Sources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXSourcesBuildPhase section */")

    add("")
    add("/* Begin PBXFrameworksBuildPhase section */")
    add(f"\t\t{uid('phase:frameworks')} /* Frameworks */ = {{")
    add("\t\t\tisa = PBXFrameworksBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXFrameworksBuildPhase section */")

    add("")
    add("/* Begin PBXResourcesBuildPhase section */")
    add(f"\t\t{uid('phase:resources')} /* Resources */ = {{")
    add("\t\t\tisa = PBXResourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXResourcesBuildPhase section */")

    # ---- XCBuildConfiguration
    common_project = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "MACOSX_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "SDKROOT": "macosx",
        "SWIFT_VERSION": "5.0",
    }
    debug_project = {
        **common_project,
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    }
    release_project = {
        **common_project,
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
    }
    common_target = {
        "ARCHS": "$(ARCHS_STANDARD)",
        "CODE_SIGN_IDENTITY": "-",
        "CODE_SIGN_STYLE": "Automatic",
        "COMBINE_HIDPI_IMAGES": "YES",
        "CURRENT_PROJECT_VERSION": PROJECT_VERSION,
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "Sources/App/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
        "MARKETING_VERSION": MARKETING_VERSION,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
    }
    debug_target = dict(common_target)
    release_target = dict(common_target)

    def emit_config(name, config_uid, settings):
        add(f"\t\t{config_uid} /* {name} */ = {{")
        add("\t\t\tisa = XCBuildConfiguration;")
        add("\t\t\tbuildSettings = {")
        for key in sorted(settings):
            add(f"\t\t\t\t{key} = {quote(settings[key])};")
        add("\t\t\t};")
        add(f"\t\t\tname = {name};")
        add("\t\t};")

    add("")
    add("/* Begin XCBuildConfiguration section */")
    emit_config("Debug", uid("cfg:project:debug"), debug_project)
    emit_config("Release", uid("cfg:project:release"), release_project)
    emit_config("Debug", uid("cfg:target:debug"), debug_target)
    emit_config("Release", uid("cfg:target:release"), release_target)
    add("/* End XCBuildConfiguration section */")

    # ---- XCConfigurationList
    add("")
    add("/* Begin XCConfigurationList section */")
    add(f"\t\t{uid('cfglist:project')} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */ = {{")
    add("\t\t\tisa = XCConfigurationList;")
    add("\t\t\tbuildConfigurations = (")
    add(f"\t\t\t\t{uid('cfg:project:debug')} /* Debug */,")
    add(f"\t\t\t\t{uid('cfg:project:release')} /* Release */,")
    add("\t\t\t);")
    add("\t\t\tdefaultConfigurationIsVisible = 0;")
    add("\t\t\tdefaultConfigurationName = Release;")
    add("\t\t};")
    add(f"\t\t{uid('cfglist:target')} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */ = {{")
    add("\t\t\tisa = XCConfigurationList;")
    add("\t\t\tbuildConfigurations = (")
    add(f"\t\t\t\t{uid('cfg:target:debug')} /* Debug */,")
    add(f"\t\t\t\t{uid('cfg:target:release')} /* Release */,")
    add("\t\t\t);")
    add("\t\t\tdefaultConfigurationIsVisible = 0;")
    add("\t\t\tdefaultConfigurationName = Release;")
    add("\t\t};")
    add("/* End XCConfigurationList section */")

    add("\t};")
    add(f"\trootObject = {uid('project')} /* Project object */;")
    add("}")

    out_dir = os.path.join(ROOT, f"{PROJECT_NAME}.xcodeproj")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "project.pbxproj")
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {out_path} ({len(sources)} sources)")


if __name__ == "__main__":
    sys.exit(main())
