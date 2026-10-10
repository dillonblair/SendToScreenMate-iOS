#!/usr/bin/env python3
"""Generates SendToScreenMate.xcodeproj (Xcode 16+ folder-synchronized format).

Source folders (App, Shared, ShareExtension, Tests) are synchronized groups, so adding a
.swift file to a folder needs no project change. Re-run this script only when targets or
build settings change:  python3 Scripts/generate_project.py
"""
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "SendToScreenMate.xcodeproj"
objects: dict[str, dict] = {}


def oid(name: str) -> str:
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def obj(_id: str, **fields) -> str:
    key = oid(_id)
    objects[key] = fields
    return key


# --- Groups -----------------------------------------------------------------
sync = {folder: obj(f"sync:{folder}", isa="PBXFileSystemSynchronizedRootGroup", path=folder, sourceTree="<group>")
        for folder in ("App", "Shared", "ShareExtension", "Tests")}

config_files = ["Base.xcconfig", "Local.example.xcconfig", "App-Info.plist", "Share-Info.plist",
                "App.entitlements", "Share.entitlements"]
file_types = {".xcconfig": "text.xcconfig", ".plist": "text.plist.xml", ".entitlements": "text.plist.entitlements"}
config_refs = {name: obj(f"file:{name}", isa="PBXFileReference", lastKnownFileType=file_types[Path(name).suffix],
                         path=name, sourceTree="<group>") for name in config_files}
config_group = obj("group:Config", isa="PBXGroup", children=list(config_refs.values()), path="Config", sourceTree="<group>")

products = {
    "App": obj("product:App", isa="PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0,
               path="SendToScreenMate.app", sourceTree="BUILT_PRODUCTS_DIR"),
    "Share": obj("product:Share", isa="PBXFileReference", explicitFileType="wrapper.app-extension", includeInIndex=0,
                 path="ShareExtension.appex", sourceTree="BUILT_PRODUCTS_DIR"),
    "Tests": obj("product:Tests", isa="PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0,
                 path="Tests.xctest", sourceTree="BUILT_PRODUCTS_DIR"),
}
products_group = obj("group:Products", isa="PBXGroup", children=list(products.values()), name="Products", sourceTree="<group>")
main_group = obj("group:main", isa="PBXGroup",
                 children=[sync["App"], sync["Shared"], sync["ShareExtension"], sync["Tests"], config_group, products_group],
                 sourceTree="<group>")


# --- Build settings ---------------------------------------------------------
def configs(name: str, common: dict, base_ref: str | None = None) -> str:
    refs = []
    for variant in ("Debug", "Release"):
        settings = dict(common)
        if variant == "Debug":
            settings.update(DEBUG_INFORMATION_FORMAT="dwarf", ENABLE_TESTABILITY="YES", ONLY_ACTIVE_ARCH="YES",
                            SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG $(inherited)", SWIFT_OPTIMIZATION_LEVEL="-Onone",
                            GCC_OPTIMIZATION_LEVEL="0")
        else:
            settings.update(DEBUG_INFORMATION_FORMAT="dwarf-with-dsym", SWIFT_COMPILATION_MODE="wholemodule",
                            VALIDATE_PRODUCT="YES")
        fields = dict(isa="XCBuildConfiguration", buildSettings=settings, name=variant)
        if base_ref:
            fields["baseConfigurationReference"] = base_ref
        refs.append(obj(f"config:{name}:{variant}", **fields))
    return obj(f"configlist:{name}", isa="XCConfigurationList", buildConfigurations=refs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


project_settings = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "MARKETING_VERSION": "1.0",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1,2",
}

app_settings = {
    "PRODUCT_NAME": "SendToScreenMate",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(APP_BUNDLE_ID)",
    "INFOPLIST_FILE": "Config/App-Info.plist",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "SendTo ScreenMate",
    "INFOPLIST_KEY_NSCameraUsageDescription": "Scan the pairing QR code shown on your ScreenMate Receiver.",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad":
        "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown "
        "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "CODE_SIGN_ENTITLEMENTS": "Config/App.entitlements",
    "ENABLE_PREVIEWS": "YES",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
}

share_settings = {
    "PRODUCT_NAME": "ShareExtension",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(APP_BUNDLE_ID).share",
    "INFOPLIST_FILE": "Config/Share-Info.plist",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "SendTo ScreenMate",
    "CODE_SIGN_ENTITLEMENTS": "Config/Share.entitlements",
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "SKIP_INSTALL": "YES",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
}

test_settings = {
    "PRODUCT_NAME": "Tests",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(APP_BUNDLE_ID).tests",
    "GENERATE_INFOPLIST_FILE": "YES",
}


# --- Targets ----------------------------------------------------------------
def phase(kind: str, target: str, files=(), **extra) -> str:
    return obj(f"phase:{kind}:{target}", isa=kind, buildActionMask=2147483647, files=list(files),
               runOnlyForDeploymentPostprocessing=0, **extra)


project_key = oid("project")

embed_file = obj("buildfile:embed-share", isa="PBXBuildFile", fileRef=products["Share"],
                 settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})


def dependency(owner: str, target: str, name: str) -> str:
    proxy = obj(f"proxy:{owner}:{name}", isa="PBXContainerItemProxy", containerPortal=project_key, proxyType=1,
                remoteGlobalIDString=oid(f"target:{name}"), remoteInfo=name)
    return obj(f"dependency:{owner}:{name}", isa="PBXTargetDependency", target=oid(f"target:{name}"), targetProxy=proxy)


targets = {
    "SendToScreenMate": obj(
        "target:SendToScreenMate", isa="PBXNativeTarget",
        buildConfigurationList=configs("SendToScreenMate", app_settings),
        buildPhases=[
            phase("PBXSourcesBuildPhase", "app"),
            phase("PBXFrameworksBuildPhase", "app"),
            phase("PBXResourcesBuildPhase", "app"),
            phase("PBXCopyFilesBuildPhase", "app", [embed_file], dstPath="", dstSubfolderSpec=13,
                  name="Embed Foundation Extensions"),
        ],
        buildRules=[], dependencies=[dependency("app", "SendToScreenMate", "ShareExtension")],
        fileSystemSynchronizedGroups=[sync["App"], sync["Shared"]],
        name="SendToScreenMate", packageProductDependencies=[], productName="SendToScreenMate",
        productReference=products["App"], productType="com.apple.product-type.application"),
    "ShareExtension": obj(
        "target:ShareExtension", isa="PBXNativeTarget",
        buildConfigurationList=configs("ShareExtension", share_settings),
        buildPhases=[phase("PBXSourcesBuildPhase", "share"), phase("PBXFrameworksBuildPhase", "share"),
                     phase("PBXResourcesBuildPhase", "share")],
        buildRules=[], dependencies=[],
        fileSystemSynchronizedGroups=[sync["ShareExtension"], sync["Shared"]],
        name="ShareExtension", packageProductDependencies=[], productName="ShareExtension",
        productReference=products["Share"], productType="com.apple.product-type.app-extension"),
    "Tests": obj(
        "target:Tests", isa="PBXNativeTarget",
        buildConfigurationList=configs("Tests", test_settings),
        buildPhases=[phase("PBXSourcesBuildPhase", "tests"), phase("PBXFrameworksBuildPhase", "tests"),
                     phase("PBXResourcesBuildPhase", "tests")],
        buildRules=[], dependencies=[],
        fileSystemSynchronizedGroups=[sync["Tests"], sync["Shared"]],
        name="Tests", packageProductDependencies=[], productName="Tests",
        productReference=products["Tests"], productType="com.apple.product-type.bundle.unit-test"),
}

objects[project_key] = dict(
    isa="PBXProject",
    attributes={"BuildIndependentTargetsInParallel": 1, "LastSwiftUpdateCheck": "1600", "LastUpgradeCheck": "1600",
                "TargetAttributes": {targets[t]: {"CreatedOnToolsVersion": "16.0"} for t in targets}},
    buildConfigurationList=configs("project", project_settings, base_ref=config_refs["Base.xcconfig"]),
    developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main_group,
    minimizedProjectReferenceProxies=1, preferredProjectObjectVersion=77, productRefGroup=products_group,
    projectDirPath="", projectRoot="", targets=list(targets.values()),
)


# --- Serialization (OpenStep plist) ----------------------------------------
def quote(value) -> str:
    if isinstance(value, int):
        return str(value)
    text = str(value)
    if text and re.fullmatch(r"[A-Za-z0-9_$/.]+", text) and not text.startswith("$("):
        return text
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def dump(value, indent: int) -> str:
    pad = "\t" * indent
    if isinstance(value, dict):
        body = "".join(f"{pad}\t{quote(k)} = {dump(v, indent + 1)};\n" for k, v in value.items())
        return "{\n" + body + pad + "}"
    if isinstance(value, list):
        body = "".join(f"{pad}\t{dump(v, indent + 1)},\n" for v in value)
        return "(\n" + body + pad + ")"
    return quote(value)


def ordered(fields: dict) -> dict:
    return {"isa": fields["isa"], **{k: v for k, v in sorted(fields.items()) if k != "isa"}}


lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 77;", "\tobjects = {"]
for isa in sorted({o["isa"] for o in objects.values()}):
    lines.append(f"\n/* Begin {isa} section */")
    for key in sorted(k for k, o in objects.items() if o["isa"] == isa):
        lines.append(f"\t\t{key} = {dump(ordered(objects[key]), 2)};")
    lines.append(f"/* End {isa} section */")
lines += ["\t};", f"\trootObject = {project_key};", "}", ""]

PROJECT.mkdir(exist_ok=True)
(PROJECT / "project.pbxproj").write_text("\n".join(lines))

# Shared scheme so the app (not the extension) is selected by default.
schemes = PROJECT / "xcshareddata" / "xcschemes"
schemes.mkdir(parents=True, exist_ok=True)


def ref(name: str, product: str) -> str:
    return (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{oid("target:" + name)}" '
            f'BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "container:SendToScreenMate.xcodeproj"/>')


app_ref = ref("SendToScreenMate", "SendToScreenMate.app")
(schemes / "SendToScreenMate.xcscheme").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {app_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            {ref("Tests", "Tests.xctest")}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"/>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
""")
print(f"Wrote {PROJECT.relative_to(ROOT)} ({len(objects)} objects)")
