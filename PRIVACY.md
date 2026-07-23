# Privacy Policy — FileMill

**Last updated: 11 July 2026**

FileMill is an offline PDF & file toolkit. This policy explains, plainly, what
happens to your data when you use it. The short version: **nothing leaves your
device, because the app cannot send it anywhere.**

## The one-sentence summary

FileMill collects no data, contains no analytics or advertising, and ships with
**no network permission at all** — so your files, and everything in them,
physically never leave your phone.

## What we collect

**Nothing.** FileMill has no account system, no sign-in, no telemetry, no
analytics, and no crash reporting. We never see your files, their contents, or
any information about how you use the app.

## How your files are handled

- Every operation — merging, converting, OCR, comparing, metadata cleaning,
  ID-card layout, and all other tools — runs **entirely on your device**.
- Files are only accessed when **you** pick them through Android's system file
  picker (Storage Access Framework). The app does not scan, index, or browse
  your storage on its own.
- Outputs are saved only where **you** choose to save them, or shared only when
  **you** tap share.
- On-device text recognition (OCR) uses a bundled Google ML Kit model that runs
  offline; no image or text is ever uploaded for recognition.

## Network access

FileMill's release build declares **no `INTERNET` permission** (and no
network-state permissions). You can verify this yourself:

- On your phone: **Settings → Apps → FileMill → Permissions** — the list
  contains no network, storage, camera, or location permission.
- The app therefore cannot transmit your data even in principle.

## Permissions

FileMill requests **no runtime permissions**. Camera capture (for scanning and
ID cards) is performed through Android's own camera app, so the app itself never
holds a camera permission. File access is handled entirely by the system file
picker.

## Data sharing

We share nothing, because we collect nothing. There are no third-party
advertising, analytics, or tracking SDKs in the app.

## Children's privacy

FileMill collects no personal data from anyone, including children.

## Changes to this policy

If this policy changes, the updated version will be posted at this same
location with a new "Last updated" date.

## Contact

Questions about this policy? Contact the developer:

- **Developer:** Harsh Tank
- **Email:** tankharsh9510@gmail.com

<!--
  BEFORE PUBLISHING: confirm the developer name and the public contact email
  above are the ones you want shown on the Play Store and in this policy, then
  host this file at a public URL (e.g. GitHub Pages) and paste that URL into the
  Play Console listing + Data Safety form.
-->
