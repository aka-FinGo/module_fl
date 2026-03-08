#!/usr/bin/env python3
import subprocess

# 1. Kotlin duplikat xatosini tuzatish
gradle = "android/build.gradle"
with open(gradle, "r") as f:
    content = f.read()

if "resolutionStrategy" not in content:
    fix = (
        "\nallprojects {\n"
        "    configurations.all {\n"
        "        resolutionStrategy {\n"
        '            force "org.jetbrains.kotlin:kotlin-stdlib:1.8.22"\n'
        '            force "org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.8.22"\n'
        '            force "org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.8.22"\n'
        "        }\n"
        "    }\n"
        "}\n"
    )
    with open(gradle, "a") as f:
        f.write(fix)
    print("Kotlin fix qoshildi")
else:
    print("resolutionStrategy allaqachon bor")

# 2. MainActivity.java - FLAG_SECURE
result = subprocess.run(["find", "android", "-name", "MainActivity.java"], capture_output=True, text=True)
filepath = result.stdout.strip().split("\n")[0]
java_code = (
    "package uz.aristokrat.yigish;\n\n"
    "import com.getcapacitor.BridgeActivity;\n"
    "import android.os.Bundle;\n"
    "import android.view.WindowManager;\n\n"
    "public class MainActivity extends BridgeActivity {\n"
    "    @Override\n"
    "    public void onCreate(Bundle savedInstanceState) {\n"
    "        super.onCreate(savedInstanceState);\n"
    "        getWindow().setFlags(\n"
    "            WindowManager.LayoutParams.FLAG_SECURE,\n"
    "            WindowManager.LayoutParams.FLAG_SECURE\n"
    "        );\n"
    "    }\n"
    "}\n"
)
with open(filepath, "w") as f:
    f.write(java_code)
print(f"MainActivity yazildi: {filepath}")

# 3. CAMERA ruxsati
manifest = "android/app/src/main/AndroidManifest.xml"
with open(manifest, "r") as f:
    mc = f.read()
if "CAMERA" not in mc:
    mc = mc.replace("</manifest>", '    <uses-permission android:name="android.permission.CAMERA" />\n</manifest>')
    with open(manifest, "w") as f:
        f.write(mc)
    print("CAMERA qoshildi")
else:
    print("CAMERA allaqachon bor")

print("Hammasi tayyor!")
