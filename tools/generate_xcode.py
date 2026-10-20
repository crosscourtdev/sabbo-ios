"""Generate a small dependency-free native Xcode project, reproducibly."""

import hashlib, json, plistlib
from urllib.parse import urlparse
from pathlib import Path

root = Path(__file__).resolve().parents[1]
native_config = json.loads((root / "config/native.json").read_text())
assert set(native_config) == {"bundle_id", "team_id", "api_url", "profile"}
assert urlparse(native_config["api_url"]).scheme == "https" and urlparse(native_config["api_url"]).hostname
assert set(native_config["profile"]) == {"ownerID", "learnerID", "ownerName", "learnerName", "ownerAvatar", "learnerAvatar", "rewardAsset", "rewardAccessibilityLabel", "rewardMessages"}
assert native_config["profile"]["ownerID"] != native_config["profile"]["learnerID"]
ios = root / "ios"
project = ios / "Sabbo.xcodeproj"
project.mkdir(exist_ok=True)


def ID(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


objects = {}


def add(key, **fields):
    objects[ID(key)] = fields
    return ID(key)


sources = sorted((ios / "Sabbo").glob("*.swift"))
refs = []
builds = []
resources = []
for p in sources:
    r = add(
        str(p.name),
        isa="PBXFileReference",
        lastKnownFileType="sourcecode.swift",
        path="Sabbo/" + p.name,
        sourceTree="<group>",
    )
    refs.append(r)
    builds.append(add("build" + p.name, isa="PBXBuildFile", fileRef=r))
for name, kind in [
    ("Assets.xcassets", "folder.assetcatalog"),
    ("questions.v1.json", "text.json"),
    ("profile.json", "text.json"),
    ("PrivacyInfo.xcprivacy", "text.xml"),
]:
    r = add(
        name,
        isa="PBXFileReference",
        lastKnownFileType=kind,
        path="Sabbo/" + name,
        sourceTree="<group>",
    )
    refs.append(r)
    resources.append(add("build" + name, isa="PBXBuildFile", fileRef=r))
product = add(
    "product",
    isa="PBXFileReference",
    explicitFileType="wrapper.application",
    path="Sabbo.app",
    sourceTree="BUILT_PRODUCTS_DIR",
)
pg = add(
    "products",
    isa="PBXGroup",
    children=[product],
    name="Products",
    sourceTree="<group>",
)
group = add("root", isa="PBXGroup", children=refs + [pg], sourceTree="<group>")
sphase = add(
    "sources",
    isa="PBXSourcesBuildPhase",
    buildActionMask=2147483647,
    files=builds,
    runOnlyForDeploymentPostprocessing=0,
)
rphase = add(
    "resources",
    isa="PBXResourcesBuildPhase",
    buildActionMask=2147483647,
    files=resources,
    runOnlyForDeploymentPostprocessing=0,
)
fphase = add(
    "frameworks",
    isa="PBXFrameworksBuildPhase",
    buildActionMask=2147483647,
    files=[],
    runOnlyForDeploymentPostprocessing=0,
)
for scope in ["project", "target"]:
    configs = []
    for mode in ["Debug", "Release"]:
        settings = {
            "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
            "SDKROOT": "iphoneos",
            "SWIFT_VERSION": "5.0",
            "CLANG_ENABLE_MODULES": "YES",
        }
        if scope == "target":
            settings.update(
                {
                    "PRODUCT_BUNDLE_IDENTIFIER": native_config["bundle_id"],
                    "PRODUCT_NAME": "Sabbo",
                    "INFOPLIST_FILE": "Sabbo/Info.plist",
                    "GENERATE_INFOPLIST_FILE": "NO",
                    "CODE_SIGN_ENTITLEMENTS": "Sabbo/Sabbo.entitlements",
                    "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "Sabbo/SabboMac.entitlements",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                    "CODE_SIGN_STYLE": "Manual",
                    "DEVELOPMENT_TEAM": native_config["team_id"],
                    "SABBO_API_URL": native_config["api_url"],
                    "SABBO_APNS_ENVIRONMENT": "sandbox"
                    if mode == "Debug"
                    else "production",
                    "SABBO_APNS_ENTITLEMENT": "development"
                    if mode == "Debug"
                    else "production",
                    "TARGETED_DEVICE_FAMILY": "1,2",
                    "SUPPORTS_MACCATALYST": "YES",
                    "DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER": "NO",
                    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
                    "MACOSX_DEPLOYMENT_TARGET": "15.0",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "CURRENT_PROJECT_VERSION": "1",
                    "MARKETING_VERSION": "0.5.1",
                    "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O",
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"
                    if mode == "Debug"
                    else "",
                }
            )
        configs.append(
            add(
                scope + mode,
                isa="XCBuildConfiguration",
                buildSettings=settings,
                name=mode,
            )
        )
    add(
        scope + "config",
        isa="XCConfigurationList",
        buildConfigurations=configs,
        defaultConfigurationIsVisible=0,
        defaultConfigurationName="Release",
    )
target = add(
    "target",
    isa="PBXNativeTarget",
    buildConfigurationList=ID("targetconfig"),
    buildPhases=[sphase, fphase, rphase],
    buildRules=[],
    dependencies=[],
    name="Sabbo",
    productName="Sabbo",
    productReference=product,
    productType="com.apple.product-type.application",
)
test_targets = []
for name, folder, product_type in [
    ("SabboTests", "SabboTests", "com.apple.product-type.bundle.unit-test"),
    ("SabboUITests", "SabboUITests", "com.apple.product-type.bundle.ui-testing"),
]:
    test_refs = []
    test_builds = []
    for path in sorted((ios / folder).glob("*.swift")):
        ref = add(
            name + path.name,
            isa="PBXFileReference",
            lastKnownFileType="sourcecode.swift",
            path=folder + "/" + path.name,
            sourceTree="<group>",
        )
        test_refs.append(ref)
        test_builds.append(
            add("build" + name + path.name, isa="PBXBuildFile", fileRef=ref)
        )
    objects[group]["children"].extend(test_refs)
    prod = add(
        name + "product",
        isa="PBXFileReference",
        explicitFileType="wrapper.cfbundle",
        path=name + ".xctest",
        sourceTree="BUILT_PRODUCTS_DIR",
    )
    objects[pg]["children"].append(prod)
    phase = add(
        name + "sources",
        isa="PBXSourcesBuildPhase",
        buildActionMask=2147483647,
        files=test_builds,
        runOnlyForDeploymentPostprocessing=0,
    )
    conf = []
    for mode in ["Debug", "Release"]:
        settings = {
            "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
            "SWIFT_VERSION": "5.0",
            "SDKROOT": "iphoneos",
            "GENERATE_INFOPLIST_FILE": "YES",
            "PRODUCT_BUNDLE_IDENTIFIER": native_config["bundle_id"] + "." + name.lower(),
            "PRODUCT_NAME": name,
            "TARGETED_DEVICE_FAMILY": "1,2",
                    "SUPPORTS_MACCATALYST": "YES",
                    "DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER": "NO",
                    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
                    "MACOSX_DEPLOYMENT_TARGET": "15.0",
            "CODE_SIGN_STYLE": "Manual",
            "DEVELOPMENT_TEAM": native_config["team_id"],
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if mode == "Debug" else "",
        }
        if name == "SabboTests":
            settings.update(
                {
                    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Sabbo.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Sabbo",
                    "BUNDLE_LOADER": "$(TEST_HOST)",
                }
            )
        else:
            settings["TEST_TARGET_NAME"] = "Sabbo"
        conf.append(
            add(
                name + mode,
                isa="XCBuildConfiguration",
                name=mode,
                buildSettings=settings,
            )
        )
    config = add(
        name + "config",
        isa="XCConfigurationList",
        buildConfigurations=conf,
        defaultConfigurationIsVisible=0,
        defaultConfigurationName="Debug",
    )
    proxy = add(
        name + "proxy",
        isa="PBXContainerItemProxy",
        containerPortal=ID("project"),
        proxyType=1,
        remoteGlobalIDString=target,
        remoteInfo="Sabbo",
    )
    dep = add(name + "dep", isa="PBXTargetDependency", target=target, targetProxy=proxy)
    test_targets.append(
        add(
            name,
            isa="PBXNativeTarget",
            buildConfigurationList=config,
            buildPhases=[phase],
            buildRules=[],
            dependencies=[dep],
            name=name,
            productName=name,
            productReference=prod,
            productType=product_type,
        )
    )
# Tests import the app module and remain absent from Release app artifacts.
objects[ID("targetDebug")]["buildSettings"]["ENABLE_TESTABILITY"] = "YES"
proj = add(
    "project",
    isa="PBXProject",
    attributes={"LastUpgradeCheck": "2630"},
    buildConfigurationList=ID("projectconfig"),
    compatibilityVersion="Xcode 14.0",
    developmentRegion="nb",
    knownRegions=["nb", "en", "Base"],
    mainGroup=group,
    productRefGroup=pg,
    projectDirPath="",
    projectRoot="",
    targets=[target] + test_targets,
)


def val(v):
    if isinstance(v, dict):
        return (
            "{ "
            + " ".join(json.dumps(k) + " = " + val(x) + ";" for k, x in v.items())
            + " }"
        )
    if isinstance(v, list):
        return "(" + ",".join(val(x) for x in v) + ")"
    if isinstance(v, int):
        return str(v)
    return json.dumps(v)


(project / "project.pbxproj").write_text(
    "// !$*UTF8*$!\n"
    + val(
        dict(
            archiveVersion=1,
            classes={},
            objectVersion=56,
            objects=objects,
            rootObject=proj,
        )
    )
    + "\n"
)
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
(schemes / "Sabbo.xcscheme").write_text(
    f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2630" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Sabbo.app" BlueprintName="Sabbo" ReferencedContainer="container:Sabbo.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Sabbo.app" BlueprintName="Sabbo" ReferencedContainer="container:Sabbo.xcodeproj"/></BuildableProductRunnable></LaunchAction><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
)
scheme_file = schemes / "Sabbo.xcscheme"
xml = scheme_file.read_text()
testxml = (
    '<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables>'
    + "".join(
        f'<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ID(n)}" BuildableName="{n}.xctest" BlueprintName="{n}" ReferencedContainer="container:Sabbo.xcodeproj"/></TestableReference>'
        for n in ["SabboTests", "SabboUITests"]
    )
    + "</Testables></TestAction>"
)
scheme_file.write_text(xml.replace("<LaunchAction", testxml + "<LaunchAction", 1))
info = {
    "CFBundleDisplayName": "Sabbo",
    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleExecutable": "$(EXECUTABLE_NAME)",
    "CFBundleName": "$(PRODUCT_NAME)",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "LSRequiresIPhoneOS": True,
    "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False},
    "UILaunchScreen": {},
    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
    "UISupportedInterfaceOrientations~ipad": [
        "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
        "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
    ],
    "LSApplicationCategoryType": "public.app-category.education",
    "CFBundleURLTypes": [{"CFBundleURLSchemes": [native_config["bundle_id"]]}],
    "SabboAPIURL": "$(SABBO_API_URL)",
    "APNsEnvironment": "$(SABBO_APNS_ENVIRONMENT)",
    "ITSAppUsesNonExemptEncryption": False,
}
(ios / "Sabbo/Info.plist").write_bytes(plistlib.dumps(info))
(ios / "Sabbo/Sabbo.entitlements").write_bytes(
    plistlib.dumps({"aps-environment": "$(SABBO_APNS_ENTITLEMENT)"})
)
# Preserve all released generations for offline review and bonus-round replay.
all_questions = []
for filename, key in [
    ("questions.v1.json", "questions"), ("questions.v2.json", "questions"),
    ("sessions.v1.json", "sessions"), ("questions.v3.json", "questions"),
    ("sessions.v2.json", "sessions"),
]:
    all_questions.extend(json.loads((root / "content" / filename).read_text())[key])
(ios / "Sabbo/questions.v1.json").write_text(json.dumps({"version": 3, "questions": all_questions}, ensure_ascii=False, indent=2) + "\n")

(ios / "Sabbo/profile.json").write_text(json.dumps(native_config["profile"], ensure_ascii=False, indent=2) + "\n")
