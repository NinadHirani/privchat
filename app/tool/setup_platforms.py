#!/usr/bin/env python3
"""
One-time platform setup. Run from the app/ directory AFTER:

    flutter create --org app.privchat --project-name privchat --platforms android,ios .

It overlays PrivChat's native code (Wi-Fi Direct, Multipeer, foreground service,
privacy hardening) and patches the generated Gradle / Xcode / plist files.
Safe to re-run.
"""
import os, plistlib, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OVL = os.path.join(ROOT, "native_overlay")

def p(*a): return os.path.join(ROOT, *a)
def say(m): print("  •", m)

def copy_tree(src, dst):
    for base, _, files in os.walk(src):
        rel = os.path.relpath(base, src)
        os.makedirs(os.path.join(dst, rel), exist_ok=True)
        for f in files:
            shutil.copy2(os.path.join(base, f), os.path.join(dst, rel, f))
            say(f"overlay {os.path.join(rel, f)}")

def android():
    if not os.path.isdir(p("android", "app")):
        sys.exit("android/app missing — run `flutter create ...` first (see header).")
    print("Android:")
    # remove the template MainActivity flutter create generated under another package path
    kroot = p("android", "app", "src", "main", "kotlin")
    for base, _, files in os.walk(kroot):
        for f in files:
            if f == "MainActivity.kt" and not base.endswith(os.path.join("app", "privchat")):
                os.remove(os.path.join(base, f)); say(f"removed template {os.path.join(base, f)}")
    copy_tree(os.path.join(OVL, "android"), p("android"))

    kts = p("android", "app", "build.gradle.kts")
    groovy = p("android", "app", "build.gradle")
    if os.path.exists(kts):
        s = open(kts).read()
        s = re.sub(r"compileSdk\s*=\s*[^\n]+", "compileSdk = 36", s)
        s = re.sub(r"targetSdk\s*=\s*[^\n]+", "targetSdk = 34", s)
        s = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 24", s)
        s = re.sub(r'namespace\s*=\s*"[^"]+"', 'namespace = "app.privchat"', s)
        s = re.sub(r'applicationId\s*=\s*"[^"]+"', 'applicationId = "app.privchat"', s)
        if "isCoreLibraryDesugaringEnabled" not in s:
            s = s.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
        if "desugar_jdk_libs" not in s:
            s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        open(kts, "w").write(s); say("patched build.gradle.kts (compileSdk 36, minSdk 24, desugaring, app id)")
    elif os.path.exists(groovy):
        s = open(groovy).read()
        s = re.sub(r"compileSdk(Version)?\s*=?\s*[^\n]+", "compileSdkVersion 36", s, count=1)
        s = re.sub(r"targetSdk(Version)?\s*=?\s*[^\n]+", "targetSdkVersion 34", s, count=1)
        s = re.sub(r"minSdk(Version)?\s*=?\s*[^\n]+", "minSdkVersion 24", s, count=1)
        s = re.sub(r'namespace\s*=?\s*"[^"]+"', 'namespace "app.privchat"', s)
        s = re.sub(r'applicationId\s*=?\s*"[^"]+"', 'applicationId "app.privchat"', s)
        if "coreLibraryDesugaringEnabled" not in s:
            s = s.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
        if "desugar_jdk_libs" not in s:
            s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
        open(groovy, "w").write(s); say("patched build.gradle (compileSdk 36, minSdk 24, desugaring, app id)")
    else:
        say("WARNING: no app build.gradle found")

    # Enforce compileSdk 36 on plugins/subprojects (e.g. bonsoir_android)
    root_kts = p("android", "build.gradle.kts")
    root_groovy = p("android", "build.gradle")
    subproj_kts = """
subprojects {
    val project = this
    val applySdk = {
        val extension = project.extensions.findByName("android")
        if (extension != null) {
            try {
                val method = extension.javaClass.getMethod("setCompileSdkVersion", Int::class.java)
                method.invoke(extension, 36)
            } catch (e: Exception) {
                try {
                    val property = extension.javaClass.getMethod("setCompileSdk", Int::class.java)
                    property.invoke(extension, 36)
                } catch (ignored: Exception) {}
            }
        }
    }
    project.plugins.withId("com.android.library") { applySdk() }
    project.plugins.withId("com.android.application") { applySdk() }
    if (project.state.executed) {
        applySdk()
    } else {
        project.afterEvaluate { applySdk() }
    }
}
"""
    subproj_groovy = """
subprojects { project ->
    def applySdk = {
        if (project.hasProperty("android")) {
            try {
                project.android.compileSdkVersion 36
            } catch (Exception ignored) {}
        }
    }
    project.plugins.withId("com.android.library") { applySdk() }
    project.plugins.withId("com.android.application") { applySdk() }
    if (project.state.executed) {
        applySdk()
    } else {
        project.afterEvaluate { applySdk() }
    }
}
"""
    if os.path.exists(root_kts):
        rk = open(root_kts).read()
        if "setCompileSdkVersion" not in rk:
            open(root_kts, "a").write(subproj_kts)
            say("enforced compileSdk 36 on subprojects in android/build.gradle.kts")
    elif os.path.exists(root_groovy):
        rg = open(root_groovy).read()
        if "compileSdkVersion" not in rg:
            open(root_groovy, "a").write(subproj_groovy)
            say("enforced compileSdk 36 on subprojects in android/build.gradle")

INFO_KEYS = {
    "NSMicrophoneUsageDescription": "PrivChat uses the microphone for encrypted voice calls and voice messages.",
    "NSCameraUsageDescription": "PrivChat uses the camera for photos, videos, video calls and scanning contact QR codes.",
    "NSPhotoLibraryUsageDescription": "PrivChat lets you share photos and videos from your library.",
    "NSPhotoLibraryAddUsageDescription": "PrivChat can save received photos and videos to your library.",
    "NSLocationWhenInUseUsageDescription": "PrivChat shares your location only when you choose to send it.",
    "NSContactsUsageDescription": "PrivChat lets you pick a contact card to share. Your address book is never uploaded.",
    "NSFaceIDUsageDescription": "PrivChat uses Face ID to unlock the app.",
    "NSLocalNetworkUsageDescription": "PrivChat talks directly to nearby devices on your Wi-Fi or hotspot — no internet or servers.",
    "NSBluetoothAlwaysUsageDescription": "PrivChat connects directly to nearby iPhones when there is no Wi-Fi.",
    "NSBonjourServices": ["_privchat._tcp", "_privchat-mp._tcp", "_privchat-mp._udp"],
    "UIBackgroundModes": ["audio", "voip"],
    "ITSAppUsesNonExemptEncryption": True,
    "UIFileSharingEnabled": False,
    "LSSupportsOpeningDocumentsInPlace": False,
    "CFBundleDisplayName": "PrivChat",
}

def ios():
    if not os.path.isdir(p("ios", "Runner")):
        say("ios/Runner missing — skipping iOS setup. Run `flutter create ...` if needed.")
        return
    print("iOS:")
    if os.path.exists(os.path.join(OVL, "ios", "Runner", "AppDelegate.swift")):
        shutil.copy2(os.path.join(OVL, "ios", "Runner", "AppDelegate.swift"), p("ios", "Runner", "AppDelegate.swift"))
        say("overlay AppDelegate.swift (+ Multipeer)")
    if os.path.exists(os.path.join(OVL, "ios", "Podfile")):
        shutil.copy2(os.path.join(OVL, "ios", "Podfile"), p("ios", "Podfile"))
        say("overlay Podfile (iOS 15, permission macros)")
    plist = p("ios", "Runner", "Info.plist")
    if os.path.exists(plist):
        with open(plist, "rb") as f: d = plistlib.load(f)
        d.update(INFO_KEYS)
        with open(plist, "wb") as f: plistlib.dump(d, f)
        say("merged Info.plist permissions / Bonjour services / background modes")
    else:
        say("WARNING: ios/Runner/Info.plist not found, skipping plist patch")
    pbx = p("ios", "Runner.xcodeproj", "project.pbxproj")
    if os.path.exists(pbx):
        s = open(pbx).read()
        s = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.0;", s)
        s = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER = [^;]*RunnerTests;", "PRODUCT_BUNDLE_IDENTIFIER = app.privchat.RunnerTests;", s)
        s = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER = (?![^;]*RunnerTests)[^;]+;", "PRODUCT_BUNDLE_IDENTIFIER = app.privchat;", s)
        open(pbx, "w").write(s); say("deployment target 15.0, bundle id app.privchat")

def cleanup():
    wt = p("test", "widget_test.dart")
    if os.path.exists(wt): os.remove(wt); say("removed template test/widget_test.dart")

if __name__ == "__main__":
    args = sys.argv[1:]
    if "--android-only" in args:
        android(); cleanup()
    elif "--ios-only" in args:
        ios(); cleanup()
    else:
        android(); ios(); cleanup()
    print("\nDone. Next:  flutter pub get  &&  flutter test  &&  flutter run")
