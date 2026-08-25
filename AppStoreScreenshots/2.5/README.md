# Pace & Plates 2.5 App Store screenshots

This folder contains the App Store screenshot package for version 2.5, build 4.

## Ready-to-upload sets

- `final/`: 6.9-inch iPhone, 1320 x 2868 pixels
- `final-6.5/`: 6.5-inch iPhone compatibility set, 1284 x 2778 pixels
- `final-ipad-13/`: 13-inch iPad, 2064 x 2752 pixels

Every final image is an RGB PNG without transparency. `manifest.json` records the
source screen, headline, dimensions, version, and build for each image.

## Capture environment

- Xcode 26.6 (`/Applications/Xcode.app`)
- iOS 26.5 Simulator runtime
- iPhone 17 Pro, portrait
- iPad Pro 13-inch (M5), portrait
- iPad Multitasking & Gestures set to **Full Screen Apps**
- Status bar normalized to 9:41, Wi-Fi, full cellular signal, and 100% battery
- Deterministic `core_tabs` fixture data

The UI test `WorkingOutUITests.testAppStoreScreenshotSet()` captures all six
screens as named test attachments. The result bundles used for this release are
ignored build artifacts under `build/AppStore/2.5/`.

## Regenerate

Set the two Simulator identifiers for the local machine. On the iPad Simulator,
select **Settings > Multitasking & Gestures > Full Screen Apps** and return to the
Home Screen before capture so iPadOS does not add windowing chrome or a Settings
breadcrumb. Then normalize both status bars and run the screenshot test once per
device:

```sh
IPHONE_SCREENSHOT_UDID="38E2099C-8F4C-4339-9FA4-0CB167976F97"
IPAD_SCREENSHOT_UDID="16CF7ACE-D7A4-458A-869E-6295407DBF64"
XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcrun simctl status_bar "$IPHONE_SCREENSHOT_UDID" override \
  --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcodebuild \
  -project "Pace & Plates.xcodeproj" \
  -scheme WorkingOut \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$IPHONE_SCREENSHOT_UDID" \
  -only-testing:WorkingOutUITests/WorkingOutUITests/testAppStoreScreenshotSet \
  -resultBundlePath build/AppStore/2.5/iphone.xcresult \
  test

DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcrun simctl status_bar "$IPAD_SCREENSHOT_UDID" override \
  --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcodebuild \
  -project "Pace & Plates.xcodeproj" \
  -scheme WorkingOut \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$IPAD_SCREENSHOT_UDID" \
  -only-testing:WorkingOutUITests/WorkingOutUITests/testAppStoreScreenshotSet \
  -resultBundlePath build/AppStore/2.5/ipad.xcresult \
  test
```

Export each result bundle's attachments with `xcresulttool`. Use the suggested
human-readable attachment names to populate `raw/` and `raw-ipad-13/` as:

```text
01-home.png
02-workouts.png
03-coach.png
04-runs.png
05-weight.png
06-running-assistant.png
```

Then render and validate the upload sets:

```sh
/Users/joshua/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 \
  AppStoreScreenshots/2.5/create_screenshots.py

sips -g pixelWidth -g pixelHeight -g format -g hasAlpha \
  AppStoreScreenshots/2.5/final/*.png \
  AppStoreScreenshots/2.5/final-6.5/*.png \
  AppStoreScreenshots/2.5/final-ipad-13/*.png
```

Use `contact-sheet.jpg` and `contact-sheet-ipad.jpg` for a quick visual review
before uploading.
