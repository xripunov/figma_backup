# figma_bckp

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

---

## Building a DMG for macOS

Follow these steps to create a DMG installer for distributing the application.

### 1. Install dependencies

Make sure [Homebrew](https://brew.sh/) is installed, then install the `create-dmg` utility:

```bash
brew install create-dmg
```

### 2. Build the Flutter application

Build the release version of the macOS application:

```bash
flutter build macos
```

### 3. Create the DMG image

Run the following command from the project root to create a customized DMG image with the application icon and a shortcut to the Applications folder:

```bash
create-dmg \
  --volname "Figma Bckp" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "figma_bckp.app" 150 180 \
  --hide-extension "figma_bckp.app" \
  --app-drop-link 450 180 \
  --add-file "Инструкция.txt" "assets/dmg/Инструкция.txt" 650 180 \
  "build/Figma_Bckp.dmg" \
  "build/macos/Build/Products/Release/figma_bckp.app"
```

The generated `Figma_Bckp.dmg` file will be in the `build` folder.

---

## Installation and First Launch

Once the DMG image has been created, use it to install the application.

1. Open `Figma_Bckp.dmg`.
2. Drag `figma_bckp.app` into the `Applications` folder.
3. **Important:** macOS may block applications from unidentified developers. To remove the quarantine attributes, open Terminal and run:

    ```bash
    xattr -cr /Applications/figma_bckp.app
    ```

This removes the quarantine attributes that can trigger macOS security warnings when launching the application.

---

## macOS Build Details

This section describes the key technical decisions made to ensure the application works correctly on macOS.

### 1. Launching Chromium

The application does not use the system installation of Google Chrome. Instead, it launches its own isolated copy of **Chromium**, bundled inside the `.app` package. Chromium is launched from Dart code (`puppeteer_service.dart`) using the `puppeteer` library. Its executable is located inside the application bundle to provide a predictable runtime environment.

### 2. Permissions and Sandboxing

To support file downloads and browser control, sandboxing is disabled at both the application and browser levels:

- **Application level (macOS Sandbox):** In `Release.entitlements`, the `com.apple.security.app-sandbox` key is set to `false`, disabling the macOS App Sandbox restrictions.
- **Browser level (Chromium Sandbox):** Chromium is launched with the `--no-sandbox` and `--disable-setuid-sandbox` arguments, disabling its internal sandbox.
- **Permission inheritance:** The `com.apple.security.inherit: true` flag in the `.entitlements` file is intended to let the child process (Chromium) inherit the main application's sandbox configuration.

### 3. Building the Project in Xcode

The Xcode build settings (`project.pbxproj`) include a custom **"Copy Chromium"** script. It recursively copies `Chromium.app` from the project's `assets` folder into the final application bundle (`.app/Contents/Frameworks/App.framework/Resources/flutter_assets/assets/chromium/`), making it available to the Dart code.

### 4. Removing Quarantine Attributes

The build process also runs a **"Remove Quarantine Attribute"** script (`xattr -cr ...`). It removes the `com.apple.quarantine` attribute from the final `.app` bundle. macOS Gatekeeper uses this attribute for files downloaded from the internet. Removing it is intended to prevent the "Are you sure you want to open this application?" dialog on first launch.
