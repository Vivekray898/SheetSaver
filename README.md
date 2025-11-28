
# SheetSaver

A small Flutter app that combines two PDF pages into one A4 landscape sheet to save paper when printing. The app supports Web, Android and iOS (mobile) with platform-specific download/share handling.

**Key Features**
- **Two-into-One PDF**: Combines every 2 pages from an input PDF into one A4 landscape page (left+right).
- **Even/Odd Handling**: If the original PDF has an odd number of pages, the last page is placed on the left side of the final sheet.
- **Cross-platform**: Web, Android and iOS handling for file picking and downloads/sharing.
- **User-friendly UI**: Simple home screen with file picker, filename preview, processing indicator and success dialog.
- **Error handling**: Friendly messages for common failure modes (file read errors, empty/corrupt PDFs, permission denials).

**Files I added / updated**
- `lib/services/pdf_service.dart` — Core logic to read input PDF, render pages to images and create the combined PDF using `syncfusion_flutter_pdf` (for reading) and `pdf` (for creating).
- `lib/screens/home_screen.dart` — UI: file picker, processing flow, progress indicator, success dialog and download/share logic.
- `lib/main.dart` — App entry wired to `HomeScreen`.
- `lib/utils/web_download.dart` — Web-only helper to trigger browser download (uses `dart:html`).
- `lib/utils/web_download_stub.dart` and `lib/utils/downloader.dart` — Conditional exports to keep cross-platform imports clean.
- `pubspec.yaml` — Added required dependencies (see Dependencies section).
- `android/app/src/main/AndroidManifest.xml` — Added runtime permissions for Android.
- `android/app/build.gradle` — Updated `minSdkVersion` to 21.
- `ios/Runner/Info.plist` — Added `NSPhotoLibraryUsageDescription` and `NSCameraUsageDescription` entries and updated app display name.

**Dependencies (added in `pubspec.yaml`)**
- `file_picker: ^6.1.1`
- `pdf: ^3.10.7`
- `printing: ^5.12.0`
- `path_provider: ^2.1.2`
- `syncfusion_flutter_pdf: ^24.2.9`
- `share_plus: ^7.2.2`
- `permission_handler: ^11.3.0`

Dev dependencies:
- `flutter_test` (SDK)
- `flutter_lints: ^3.0.0`

**How it works (overview)**
1. User picks a PDF via the UI (`Upload PDF`).
2. The app reads the PDF bytes and uses `syncfusion_flutter_pdf` to determine page count.
3. Each source page is rasterized to an image using the `printing` package.
4. The `pdf` package creates a new document using `PdfPageFormat.a4.landscape`. For every two source pages it places the two images side-by-side using equal widths. If a single page remains, it is placed on the left.
5. The final combined PDF is returned as bytes. On mobile it is written to a temporary file; the user can download/share it. On web a browser download is triggered.

**Build & Run**
- Ensure Flutter and Android SDK are installed and available in your PATH.
- Fetch packages:

```powershell
flutter pub get
```

- Build debug APK (already done during recent run):

```powershell
flutter build apk --debug
```

- Resulting debug APK (example path):

```
build\\app\\outputs\\flutter-apk\\app-debug.apk
```

- Install to connected Android device or emulator:

```powershell
adb install -r "build\app\outputs\flutter-apk\app-debug.apk"
# or use
flutter install
```

- Build Web release:

```powershell
flutter build web --release
```

**Platform-specific notes**
- Android:
	- Permissions added to `AndroidManifest.xml` for reading/writing external storage and Internet.
	- `minSdkVersion` set to 21.
	- Build produced a debug APK successfully; a warning recommended `compileSdk = 35` because some plugins target SDK 35 — consider updating `android/app/build.gradle` to set `compileSdk = 35` to remove warnings.
- iOS:
	- `Info.plist` updated with usage descriptions for saving files.
	- Sharing uses `share_plus` on mobile so iOS users can choose where to save.
- Web:
	- `lib/utils/web_download.dart` triggers a browser download using `dart:html`.
	- File picker uses web-capable file picking logic (bytes are passed directly for processing).

**Error handling implemented**
- Detect and inform user if PDF cannot be read: "Failed to read PDF file. Please try another file." 
- If the PDF is empty or page count is zero: "This PDF is empty or corrupted." 
- Permission denied flows show: "Storage permission denied. Please enable it in settings." 
- Any other unexpected errors show: "Something went wrong. Please try again." 

**UX and feedback**
- Processing state: `_isProcessing` shows a `CircularProgressIndicator` and the message: "Combining pages... This may take a moment".
- Buttons are disabled while processing and their text indicates the operation.
- On success: a dialog shows with a `Download / Share` button.

**Testing checklist**
- [ ] Upload PDF opens file picker and allows only PDF files.
- [ ] Selected filename displays correctly in the UI.
- [ ] Combine button processes the PDF and shows progress indicator.
- [ ] Success dialog appears and download/share works on the target platform.
- [ ] Error messages display correctly for invalid/corrupt files.
- [ ] App handles large PDFs (50+ pages) without crashing (test on device/emulator).
- [ ] UI remains responsive on different screen sizes.

**Known limitations & notes**
- The PDF page rasterization uses memory; very large PDFs may be slow or memory-intensive — test on production devices.
- `dart:html` usage is web-only; `web_download.dart` is guarded by conditional imports, but static analysis will still flag web-library usage in Flutter projects unless built for web.
- Syncfusion PDF package is used only for reading page count and safe extraction; ensure license compliance if used in production.

**Next steps & suggestions**
- Update `android/app/build.gradle` to `compileSdk = 35` to match some plugin requirements (recommended).
- Add signed release build configuration for Play Store distribution.
- Improve memory usage by downscaling very large pages or using streaming approaches.
- Add unit/integration tests around `PdfService` using a few sample PDFs.

If you want, I can:
- Update `android/app/build.gradle` to set `compileSdk = 35` now and rebuild.
- Create a small sample PDF for quick end-to-end testing.
- Add more robust progress reporting during long runs.

---

Generated by development work in this workspace. For implementation details look at the key files listed above (`lib/services/pdf_service.dart`, `lib/screens/home_screen.dart`, etc.).
