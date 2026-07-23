<div align="center">

<img src="assets/icon/icon.png" width="96" alt="FileMill icon" />

# FileMill

### Offline PDF & file toolkit — your files never leave your device, *provably*

24 document tools that run **100% on-device**. No upload. No account. No ads. No watermark.
FileMill ships with **zero network permission** — the app literally *cannot* touch the internet.

<br/>

<img src="docs/screenshots/home.png" width="260" alt="FileMill home" />
&nbsp;&nbsp;
<img src="docs/screenshots/about.png" width="260" alt="FileMill about" />

</div>

---

## The privacy claim, proven

Most "private" PDF apps still upload your files to a server. FileMill can't — it declares **no `INTERNET` permission** in its release manifest. You can verify it yourself:

```console
$ aapt dump permissions app-release.apk
package: com.filemill.filemill
uses-permission: ...DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION   # AndroidX internal only
# no INTERNET, no ACCESS_NETWORK_STATE — nothing
```

On the phone: **Settings → Apps → FileMill → Permissions** — the list is empty. Even the on-device OCR model and the bundled fonts mean nothing ever phones home.

## What it does

**PDF tools**

| | | |
|---|---|---|
| 📖 **Read** — fast pinch-zoom viewer, "Open with" integration | ✍️ **Sign** — draw & place your signature | ⌨️ **Add Text** — fill flat forms, styled vector text |
| 🔀 **Merge** — combine PDFs, drag to order | ✂️ **Split** — extract any pages | 🎛 **Organize** — reorder, rotate, delete pages |
| 🖼 **Crop** — trim margins, auto-detect content | 🗜 **Compress** — quality presets or "fit under X MB" | 🔒 **Protect** — AES-256 lock / unlock |
| 🖊 **Highlight** — color markup, find-to-highlight | ⬛ **Redact** — *truly* destroys content, not just covers it | 💧 **Watermark** — diagonal stamps + page numbers |
| 🌄 **PDF → Images** — export pages as PNG/JPG | | |

**Create & capture**

| | | |
|---|---|---|
| 📷 **Scan → PDF** — auto edge-detect, deskew, enhance | 🏞 **Images → PDF** — photos into a clean PDF | 🪪 **ID Card → PDF** — front & back at true size on one A4 |
| 🔤 **Extract Text** — on-device OCR | 🔎 **Searchable PDF** — invisible OCR text layer over scans | 🔄 **Convert Images** — JPG/PNG, resize, shrink |

**Convert & compare**

| | | |
|---|---|---|
| 📝 **PDF → Word** — editable `.docx`, geometry-faithful | 🔀 **Compare PDFs** — exact word-level diff of two versions | 🕵️ **Metadata Cleaner** — see & scrub hidden file data |
| 🌄 **PDF → Images** — export pages as PNG/JPG | | |

## Highlights worth a closer look

- **PDF → Word** rebuilds document structure from glyph geometry — same-row cells become table rows with real tab stops, headings by font ratio, soft-hyphen repair, exact indents and page breaks. Validated line-by-line against real bank statements, forms and resumes.
- **Compare PDFs** runs a patience diff (git's algorithm) over both documents' words with glyph-accurate bounds, so an insertion on page 1 never false-flags the pages after it. Every change is highlighted on the page and listed with context — an Acrobat-Pro-only feature, free and offline.
- **Metadata Cleaner** shows the location, device, author and history hidden in a file, then scrubs it — JPEG stripped losslessly (pixels byte-identical), PDF rebuilt so old strings aren't recoverable, verified at the raw-byte level.
- **ID Card → PDF** lays an Aadhaar/PAN/DL front and back at true ISO card size on one A4, auto-orients by reading the card, and can mask the ID number (burned into the pixels) — the KYC copy people usually pay or upload for.
- **Redact** flattens affected pages to images so the hidden text is *destroyed*, not painted over — a text-extractor over the output finds nothing (there's a unit test that proves it).
- **Scan** does real perspective correction (4-point homography) + auto-enhance, entirely in pure Dart.
- **Share-sheet & "Open with"** — FileMill appears wherever you share or open a PDF/image.

## Built with

Flutter · Google ML Kit (on-device OCR) · Syncfusion & pure-Dart `pdf` engines · `pdfx` rendering · isolate-based processing for a smooth UI · Storage Access Framework (no storage permissions) · bundled Manrope + Space Grotesk fonts.

## Build

```console
flutter pub get
flutter build apk --release          # universal APK (sideload / direct install)
flutter build appbundle --release    # AAB for Play Store upload
```

Requires Flutter 3.41+, Android minSdk 24, targetSdk 36.

### Release signing

Release builds read their signing key from `android/key.properties` (git-ignored).
See `android/key.properties.example` for the one-time keystore setup. Without that
file, release builds fall back to the debug key so the app still builds locally.

## Privacy

See [PRIVACY.md](PRIVACY.md). FileMill collects nothing and has no network
permission — the privacy claim is verifiable, not a promise.

---

<div align="center">
<em>Milled locally. Nothing ever uploaded.</em>
</div>
