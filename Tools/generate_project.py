#!/usr/bin/env python3
"""
Generates WatDash.xcodeproj from the files on disk.

Same approach as WatAlarm: an .xcodeproj is a large opaque blob that is painful
to review and easy to corrupt by hand, so this script walks the source tree and
emits a correct pbxproj every time. Adding a Swift file means creating the file
and re-running:

    python3 Tools/generate_project.py

Signing note
------------
macOS is kinder than iOS here. A free (personal) team can sign everything this
app needs, because none of it requires a provisioning profile:

  * App Sandbox (widget extension only; WidgetKit requires it)
  * An App Group whose identifier starts with the team id. On macOS that form
    needs no registration with Apple, so the app and the widget can share a
    snapshot file without a paid membership.
  * Calendar access, which only needs Info.plist usage strings plus the
    hardened-runtime entitlement.

So signing is manual with the "Apple Development" identity and no profile.
Pass a different team with --team if you fork this.

iOS and iPadOS
--------------
The app target is multiplatform (SDKROOT auto): the same sources build for
macOS, iPhone and iPad, with `#if os(macOS)` around what only a Mac has
(menu bar extra, hotkey, capture panel, launch at login). On iOS it has its
own Info.plist and no entitlements, and signs automatically, so a free team
works there too (with Apple's 7-day profiles on a device; the simulator needs
nothing).

The widget extension is macOS-only. Its data arrives through an App Group,
and on iOS a group must be registered in a provisioning profile, which a
personal team can't get (see WatAlarm's generator). The embed step and the
dependency carry a macOS platform filter, so iOS builds skip it.

Targets produced:
  * WatDash         — the app: macOS (not sandboxed: it reads your course
                      folders and runs local tools), iOS and iPadOS
  * WatDashWidgets  — WidgetKit extension (macOS), embedded in Contents/PlugIns
Sources under Shared/ are compiled into BOTH targets.
"""

import argparse
import hashlib
import os
import shutil
from pathlib import Path

_parser = argparse.ArgumentParser(description="Generate WatDash.xcodeproj")
_parser.add_argument(
    "--team",
    default=os.environ.get("WATDASH_TEAM_ID", "3AML23Y649"),
    help="DEVELOPMENT_TEAM id. Also prefixes the App Group identifier.",
)
ARGS = _parser.parse_args()

ROOT = Path(__file__).resolve().parent.parent
PROJECT_NAME = "WatDash"
APP_TARGET = "WatDash"
EXT_TARGET = "WatDashWidgets"
APP_BUNDLE_ID = "com.ashwinpaudel.WatDash"
EXT_BUNDLE_ID = "com.ashwinpaudel.WatDash.Widgets"
APP_GROUP = f"{ARGS.team}.com.ashwinpaudel.WatDash"
DEPLOYMENT_TARGET = "26.0"
SWIFT_VERSION = "5.0"

_ids_by_key: dict[str, str] = {}
_used_ids: set[str] = set()


def oid(*parts: str) -> str:
    """Stable 24-hex-char object id derived from a key (memoized, see WatAlarm)."""
    key = "::".join(parts)
    if key in _ids_by_key:
        return _ids_by_key[key]
    for salt in range(1000):
        candidate = hashlib.md5(f"{key}#{salt}".encode()).hexdigest()[:24].upper()
        if candidate not in _used_ids:
            _used_ids.add(candidate)
            _ids_by_key[key] = candidate
            return candidate
    raise RuntimeError("could not allocate object id")


def swift_files(*dirs: str) -> list[str]:
    found: list[str] = []
    for d in dirs:
        base = ROOT / d
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            found.append(str(path.relative_to(ROOT)))
    return sorted(found)


APP_SOURCES = swift_files("WatDash", "Shared")
EXT_SOURCES = swift_files("WatDashWidgets") + swift_files("Shared")


def resource_files(directory: str) -> list[str]:
    base = ROOT / directory
    if not base.exists():
        return []
    return sorted(str(p.relative_to(ROOT)) for p in base.iterdir() if p.is_file() and not p.name.startswith("."))


APP_RESOURCES = [p for p in ["WatDash/Assets.xcassets"] if (ROOT / p).exists()]
APP_RESOURCES += resource_files("WatDash/Resources")
EXT_RESOURCES = [p for p in ["WatDashWidgets/Assets.xcassets"] if (ROOT / p).exists()]

APP_PLIST = "WatDash/Info.plist"
APP_IOS_PLIST = "WatDash/Info-iOS.plist"
EXT_PLIST = "WatDashWidgets/Info.plist"
APP_ENTITLEMENTS = "WatDash/WatDash.entitlements"
EXT_ENTITLEMENTS = "WatDashWidgets/WatDashWidgets.entitlements"

LOOSE_FILES = [p for p in [APP_PLIST, APP_IOS_PLIST, EXT_PLIST, APP_ENTITLEMENTS, EXT_ENTITLEMENTS] if (ROOT / p).exists()]

ALL_PATHS = sorted(set(APP_SOURCES + EXT_SOURCES + APP_RESOURCES + EXT_RESOURCES + LOOSE_FILES))


def file_type(path: str) -> str:
    if path.endswith(".swift"):
        return "sourcecode.swift"
    if path.endswith(".xcassets"):
        return "folder.assetcatalog"
    if path.endswith(".plist"):
        return "text.plist.xml"
    if path.endswith(".entitlements"):
        return "text.plist.entitlements"
    if path.endswith(".html"):
        return "text.html"
    if path.endswith(".js"):
        return "sourcecode.javascript"
    if path.endswith(".css"):
        return "text.css"
    return "file"


file_refs = {path: oid("fileref", path) for path in ALL_PATHS}

PRODUCT_APP = oid("product", "app")
PRODUCT_EXT = oid("product", "ext")


def build_file_ids(target: str, paths: list[str]) -> dict[str, str]:
    return {path: oid("buildfile", target, path) for path in paths}


app_source_bf = build_file_ids(APP_TARGET, APP_SOURCES)
app_resource_bf = build_file_ids(APP_TARGET, APP_RESOURCES)
ext_source_bf = build_file_ids(EXT_TARGET, EXT_SOURCES)
ext_resource_bf = build_file_ids(EXT_TARGET, EXT_RESOURCES)
embed_ext_bf = oid("buildfile", "embed", EXT_TARGET)

# ---------------------------------------------------------------- group tree


class Group:
    def __init__(self, name: str, path_component: str | None = None):
        self.name = name
        self.path_component = path_component
        self.children: dict[str, "Group"] = {}
        self.files: list[str] = []
        self.id = ""


def build_groups() -> Group:
    root = Group(PROJECT_NAME)
    for path in ALL_PATHS:
        parts = Path(path).parts
        node = root
        for part in parts[:-1]:
            if part not in node.children:
                node.children[part] = Group(part, part)
            node = node.children[part]
        node.files.append(path)
    return root


def assign_group_ids(group: Group, prefix: str = "root") -> None:
    group.id = oid("group", prefix, group.name)
    for child in group.children.values():
        assign_group_ids(child, f"{prefix}/{group.name}")


root_group = build_groups()
assign_group_ids(root_group)
PRODUCTS_GROUP = oid("group", "Products")

# ---------------------------------------------------------------- emit

lines: list[str] = []
w = lines.append

w("// !$*UTF8*$!")
w("{")
w("\tarchiveVersion = 1;")
w("\tclasses = {")
w("\t};")
w("\tobjectVersion = 56;")
w("\tobjects = {")

w("")
w("/* Begin PBXBuildFile section */")
for mapping, phase in ((app_source_bf, "Sources"), (app_resource_bf, "Resources"),
                       (ext_source_bf, "Sources"), (ext_resource_bf, "Resources")):
    for path, bid in sorted(mapping.items()):
        w(f"\t\t{bid} /* {Path(path).name} in {phase} */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {Path(path).name} */; }};")
# The widget is macOS-only: iOS builds of the app skip embedding it.
w(f"\t\t{embed_ext_bf} /* {EXT_TARGET}.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {PRODUCT_EXT} /* {EXT_TARGET}.appex */; platformFilters = (macos, ); settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
w("/* End PBXBuildFile section */")

PROJECT_ID = oid("project", PROJECT_NAME)
CONTAINER_PROXY = oid("containerproxy", EXT_TARGET)
TARGET_APP = oid("target", APP_TARGET)
TARGET_EXT = oid("target", EXT_TARGET)
DEPENDENCY = oid("dependency", EXT_TARGET)

w("")
w("/* Begin PBXContainerItemProxy section */")
w(f"\t\t{CONTAINER_PROXY} /* PBXContainerItemProxy */ = {{")
w("\t\t\tisa = PBXContainerItemProxy;")
w(f"\t\t\tcontainerPortal = {PROJECT_ID} /* Project object */;")
w("\t\t\tproxyType = 1;")
w(f"\t\t\tremoteGlobalIDString = {TARGET_EXT};")
w(f"\t\t\tremoteInfo = {EXT_TARGET};")
w("\t\t};")
w("/* End PBXContainerItemProxy section */")

EMBED_PHASE = oid("phase", "embed")
w("")
w("/* Begin PBXCopyFilesBuildPhase section */")
w(f"\t\t{EMBED_PHASE} /* Embed Foundation Extensions */ = {{")
w("\t\t\tisa = PBXCopyFilesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tdstPath = \"\";")
w("\t\t\tdstSubfolderSpec = 13;")
w("\t\t\tfiles = (")
w(f"\t\t\t\t{embed_ext_bf} /* {EXT_TARGET}.appex in Embed Foundation Extensions */,")
w("\t\t\t);")
w("\t\t\tname = \"Embed Foundation Extensions\";")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXCopyFilesBuildPhase section */")

w("")
w("/* Begin PBXFileReference section */")
for path in ALL_PATHS:
    name = Path(path).name
    w(f"\t\t{file_refs[path]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type(path)}; path = \"{name}\"; sourceTree = \"<group>\"; }};")
w(f"\t\t{PRODUCT_APP} /* {APP_TARGET}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP_TARGET}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
w(f"\t\t{PRODUCT_EXT} /* {EXT_TARGET}.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = {EXT_TARGET}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
w("/* End PBXFileReference section */")

FRAMEWORKS_APP = oid("phase", "frameworks", APP_TARGET)
FRAMEWORKS_EXT = oid("phase", "frameworks", EXT_TARGET)
w("")
w("/* Begin PBXFrameworksBuildPhase section */")
for pid in (FRAMEWORKS_APP, FRAMEWORKS_EXT):
    w(f"\t\t{pid} /* Frameworks */ = {{")
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
w("/* End PBXFrameworksBuildPhase section */")

w("")
w("/* Begin PBXGroup section */")


def emit_group(group: Group, is_root: bool) -> None:
    w(f"\t\t{group.id} /* {group.name} */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for name in sorted(group.children):
        child = group.children[name]
        w(f"\t\t\t\t{child.id} /* {child.name} */,")
    for path in sorted(group.files):
        w(f"\t\t\t\t{file_refs[path]} /* {Path(path).name} */,")
    if is_root:
        w(f"\t\t\t\t{PRODUCTS_GROUP} /* Products */,")
    w("\t\t\t);")
    if not is_root:
        w(f"\t\t\tpath = \"{group.path_component}\";")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    for name in sorted(group.children):
        emit_group(group.children[name], False)


emit_group(root_group, True)

w(f"\t\t{PRODUCTS_GROUP} /* Products */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{PRODUCT_APP} /* {APP_TARGET}.app */,")
w(f"\t\t\t\t{PRODUCT_EXT} /* {EXT_TARGET}.appex */,")
w("\t\t\t);")
w("\t\t\tname = Products;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w("/* End PBXGroup section */")

SOURCES_APP = oid("phase", "sources", APP_TARGET)
SOURCES_EXT = oid("phase", "sources", EXT_TARGET)
RESOURCES_APP = oid("phase", "resources", APP_TARGET)
RESOURCES_EXT = oid("phase", "resources", EXT_TARGET)
CONFLIST_APP = oid("conflist", APP_TARGET)
CONFLIST_EXT = oid("conflist", EXT_TARGET)
CONFLIST_PROJECT = oid("conflist", "project")

w("")
w("/* Begin PBXNativeTarget section */")
for target_id, name, conflist, phases, deps, product, ptype in (
    (TARGET_APP, APP_TARGET, CONFLIST_APP,
     [(SOURCES_APP, "Sources"), (FRAMEWORKS_APP, "Frameworks"), (RESOURCES_APP, "Resources"), (EMBED_PHASE, "Embed Foundation Extensions")],
     [DEPENDENCY], f"{PRODUCT_APP} /* {APP_TARGET}.app */", "com.apple.product-type.application"),
    (TARGET_EXT, EXT_TARGET, CONFLIST_EXT,
     [(SOURCES_EXT, "Sources"), (FRAMEWORKS_EXT, "Frameworks"), (RESOURCES_EXT, "Resources")],
     [], f"{PRODUCT_EXT} /* {EXT_TARGET}.appex */", "com.apple.product-type.app-extension"),
):
    w(f"\t\t{target_id} /* {name} */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {conflist} /* Build configuration list for PBXNativeTarget \"{name}\" */;")
    w("\t\t\tbuildPhases = (")
    for pid, label in phases:
        w(f"\t\t\t\t{pid} /* {label} */,")
    w("\t\t\t);")
    w("\t\t\tbuildRules = (")
    w("\t\t\t);")
    w("\t\t\tdependencies = (")
    for dep in deps:
        w(f"\t\t\t\t{dep} /* PBXTargetDependency */,")
    w("\t\t\t);")
    w(f"\t\t\tname = {name};")
    w(f"\t\t\tproductName = {name};")
    w(f"\t\t\tproductReference = {product};")
    w(f"\t\t\tproductType = \"{ptype}\";")
    w("\t\t};")
w("/* End PBXNativeTarget section */")

w("")
w("/* Begin PBXProject section */")
w(f"\t\t{PROJECT_ID} /* Project object */ = {{")
w("\t\t\tisa = PBXProject;")
w("\t\t\tattributes = {")
w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
w("\t\t\t\tLastSwiftUpdateCheck = 2700;")
w("\t\t\t\tLastUpgradeCheck = 2700;")
w("\t\t\t\tTargetAttributes = {")
for tid in (TARGET_APP, TARGET_EXT):
    w(f"\t\t\t\t\t{tid} = {{")
    w("\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;")
    w("\t\t\t\t\t};")
w("\t\t\t\t};")
w("\t\t\t};")
w(f"\t\t\tbuildConfigurationList = {CONFLIST_PROJECT} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */;")
w("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
w("\t\t\tdevelopmentRegion = en;")
w("\t\t\thasScannedForEncodings = 0;")
w("\t\t\tknownRegions = (")
w("\t\t\t\ten,")
w("\t\t\t\tBase,")
w("\t\t\t);")
w(f"\t\t\tmainGroup = {root_group.id};")
w(f"\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;")
w("\t\t\tprojectDirPath = \"\";")
w("\t\t\tprojectRoot = \"\";")
w("\t\t\ttargets = (")
w(f"\t\t\t\t{TARGET_APP} /* {APP_TARGET} */,")
w(f"\t\t\t\t{TARGET_EXT} /* {EXT_TARGET} */,")
w("\t\t\t);")
w("\t\t};")
w("/* End PBXProject section */")

w("")
w("/* Begin PBXResourcesBuildPhase section */")
for pid, mapping in ((RESOURCES_APP, app_resource_bf), (RESOURCES_EXT, ext_resource_bf)):
    w(f"\t\t{pid} /* Resources */ = {{")
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for path, bid in sorted(mapping.items()):
        w(f"\t\t\t\t{bid} /* {Path(path).name} in Resources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
w("/* End PBXResourcesBuildPhase section */")

w("")
w("/* Begin PBXSourcesBuildPhase section */")
for pid, mapping in ((SOURCES_APP, app_source_bf), (SOURCES_EXT, ext_source_bf)):
    w(f"\t\t{pid} /* Sources */ = {{")
    w("\t\t\tisa = PBXSourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for path, bid in sorted(mapping.items()):
        w(f"\t\t\t\t{bid} /* {Path(path).name} in Sources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
w("/* End PBXSourcesBuildPhase section */")

w("")
w("/* Begin PBXTargetDependency section */")
w(f"\t\t{DEPENDENCY} /* PBXTargetDependency */ = {{")
w("\t\t\tisa = PBXTargetDependency;")
w("\t\t\tplatformFilters = (")
w("\t\t\t\tmacos,")
w("\t\t\t);")
w(f"\t\t\ttarget = {TARGET_EXT} /* {EXT_TARGET} */;")
w(f"\t\t\ttargetProxy = {CONTAINER_PROXY} /* PBXContainerItemProxy */;")
w("\t\t};")
w("/* End PBXTargetDependency section */")

PROJECT_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "MACOSX_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    # One target for Mac, iPhone and iPad (see "iOS and iPadOS" above).
    "SDKROOT": "auto",
    "SUPPORTED_PLATFORMS": "\"iphoneos iphonesimulator macosx\"",
    "TARGETED_DEVICE_FAMILY": "\"1,2\"",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_VERSION": SWIFT_VERSION,
    # Same call as WatAlarm: one @MainActor store, value types across every
    # boundary. Full strict checking would add noise without changing behaviour.
    "SWIFT_STRICT_CONCURRENCY": "minimal",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "DEVELOPMENT_TEAM": ARGS.team,
    "CODE_SIGN_STYLE": "Manual",
    "CODE_SIGN_IDENTITY": "\"Apple Development\"",
    "PROVISIONING_PROFILE_SPECIFIER": "\"\"",
    # A device needs a profile, which Xcode manages; the simulator signs ad hoc.
    "\"CODE_SIGN_STYLE[sdk=iphoneos*]\"": "Automatic",
    "\"CODE_SIGN_IDENTITY[sdk=iphonesimulator*]\"": "\"-\"",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "\"$(inherited)\"",
    "WATDASH_APP_GROUP": APP_GROUP,
}

PROJECT_DEBUG = {
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "\"DEBUG $(inherited)\"",
    "SWIFT_OPTIMIZATION_LEVEL": "\"-Onone\"",
}

PROJECT_RELEASE = {
    "DEBUG_INFORMATION_FORMAT": "\"dwarf-with-dsym\"",
    "ENABLE_NS_ASSERTIONS": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
}

APP_COMMON = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CURRENT_PROJECT_VERSION": "1",
    "MARKETING_VERSION": "1.0",
    "ENABLE_PREVIEWS": "YES",
    "INFOPLIST_FILE": APP_PLIST,
    "\"INFOPLIST_FILE[sdk=iphoneos*]\"": APP_IOS_PLIST,
    "\"INFOPLIST_FILE[sdk=iphonesimulator*]\"": APP_IOS_PLIST,
    # The App Group and calendar entitlements are the Mac's; iOS needs none.
    "\"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]\"": APP_ENTITLEMENTS,
    "LD_RUNPATH_SEARCH_PATHS": "\"$(inherited) @executable_path/../Frameworks\"",
    "\"LD_RUNPATH_SEARCH_PATHS[sdk=iphoneos*]\"": "\"$(inherited) @executable_path/Frameworks\"",
    "\"LD_RUNPATH_SEARCH_PATHS[sdk=iphonesimulator*]\"": "\"$(inherited) @executable_path/Frameworks\"",
    "PRODUCT_BUNDLE_IDENTIFIER": APP_BUNDLE_ID,
    "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
    "COMBINE_HIDPI_IMAGES": "YES",
}

EXT_COMMON = {
    "SDKROOT": "macosx",
    "SUPPORTED_PLATFORMS": "macosx",
    "CURRENT_PROJECT_VERSION": "1",
    "MARKETING_VERSION": "1.0",
    "ENABLE_PREVIEWS": "YES",
    "INFOPLIST_FILE": EXT_PLIST,
    "CODE_SIGN_ENTITLEMENTS": EXT_ENTITLEMENTS,
    "LD_RUNPATH_SEARCH_PATHS": "\"$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks\"",
    "PRODUCT_BUNDLE_IDENTIFIER": EXT_BUNDLE_ID,
    "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
    "SKIP_INSTALL": "YES",
}

configs: list[tuple[str, str, dict]] = []
for name in ("Debug", "Release"):
    base = dict(PROJECT_COMMON)
    base.update(PROJECT_DEBUG if name == "Debug" else PROJECT_RELEASE)
    configs.append((oid("buildconfig", "project", name), name, base))
    configs.append((oid("buildconfig", APP_TARGET, name), name, APP_COMMON))
    configs.append((oid("buildconfig", EXT_TARGET, name), name, EXT_COMMON))

w("")
w("/* Begin XCBuildConfiguration section */")
for cid, name, settings in configs:
    w(f"\t\t{cid} /* {name} */ = {{")
    w("\t\t\tisa = XCBuildConfiguration;")
    w("\t\t\tbuildSettings = {")
    for key in sorted(settings):
        w(f"\t\t\t\t{key} = {settings[key]};")
    w("\t\t\t};")
    w(f"\t\t\tname = {name};")
    w("\t\t};")
w("/* End XCBuildConfiguration section */")

w("")
w("/* Begin XCConfigurationList section */")
for list_id, label, owner in (
    (CONFLIST_PROJECT, f"PBXProject \"{PROJECT_NAME}\"", "project"),
    (CONFLIST_APP, f"PBXNativeTarget \"{APP_TARGET}\"", APP_TARGET),
    (CONFLIST_EXT, f"PBXNativeTarget \"{EXT_TARGET}\"", EXT_TARGET),
):
    w(f"\t\t{list_id} /* Build configuration list for {label} */ = {{")
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    for name in ("Debug", "Release"):
        w(f"\t\t\t\t{oid('buildconfig', owner, name)} /* {name} */,")
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
w("/* End XCConfigurationList section */")

w("\t};")
w(f"\trootObject = {PROJECT_ID} /* Project object */;")
w("}")

# ---------------------------------------------------------------- write out

project_dir = ROOT / f"{PROJECT_NAME}.xcodeproj"
if project_dir.exists():
    shutil.rmtree(project_dir)
project_dir.mkdir(parents=True)
(project_dir / "project.pbxproj").write_text("\n".join(lines) + "\n")

# Entitlements carry the team-prefixed group, so regenerate them with the team.
group_plist = f"""\t<key>com.apple.security.application-groups</key>
\t<array>
\t\t<string>{APP_GROUP}</string>
\t</array>"""
(ROOT / APP_ENTITLEMENTS).write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
{group_plist}
\t<key>com.apple.security.personal-information.calendars</key>
\t<true/>
\t<key>com.apple.security.network.client</key>
\t<true/>
</dict>
</plist>
""")
(ROOT / EXT_ENTITLEMENTS).write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.security.app-sandbox</key>
\t<true/>
{group_plist}
</dict>
</plist>
""")

scheme_dir = project_dir / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True)
(scheme_dir / f"{APP_TARGET}.xcscheme").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2700" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{TARGET_APP}"
               BuildableName = "{APP_TARGET}.app"
               BlueprintName = "{APP_TARGET}"
               ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{TARGET_APP}"
            BuildableName = "{APP_TARGET}.app"
            BlueprintName = "{APP_TARGET}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{TARGET_APP}"
            BuildableName = "{APP_TARGET}.app"
            BlueprintName = "{APP_TARGET}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
""")

print(f"Generated {project_dir.relative_to(ROOT)}")
print(f"  app sources:    {len(APP_SOURCES)}")
print(f"  widget sources: {len(EXT_SOURCES)}")
print(f"  app group:      {APP_GROUP}")
