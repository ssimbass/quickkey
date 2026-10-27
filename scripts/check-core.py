#!/usr/bin/env python3
"""Run the core checks with the Swift compiler, including Command Line Tools-only Macs."""

import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def main():
    project = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="quickkey-core-") as temporary:
        work = Path(temporary)
        bundle = work / "QuickKey_ShortcutCore.bundle"
        resources = bundle / "Contents" / "Resources"
        resources.mkdir(parents=True)
        with (bundle / "Contents" / "Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleIdentifier": "local.quickkey.corechecks", "CFBundlePackageType": "BNDL"}, file)
        for resource in (project / "Sources/ShortcutCore/Resources").glob("*.json"):
            shutil.copyfile(resource, resources / resource.name)
        shim = work / "ResourceBundle.swift"
        shim.write_text('''import Foundation
extension Bundle {
    static let module: Bundle = {
        guard let path = ProcessInfo.processInfo.environment["QUICKKEY_CORE_TEST_BUNDLE"],
              let bundle = Bundle(path: path) else {
            fatalError("核心测试缺少临时资源包")
        }
        return bundle
    }()
}
''')
        executable = work / "core-checks"
        sources = sorted((project / "Sources/ShortcutCore").glob("*.swift"))
        subprocess.run(["swiftc", "-swift-version", "6", "-parse-as-library", *map(str, sources),
                        str(shim), str(project / "scripts/CoreChecks.swift"), "-o", str(executable)],
                       check=True, cwd=project)
        environment = os.environ.copy()
        environment["QUICKKEY_CORE_TEST_BUNDLE"] = str(bundle)
        subprocess.run([str(executable)], check=True, cwd=project, env=environment)


if __name__ == "__main__":
    main()
