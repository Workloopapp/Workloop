# In-app document viewing — 8 September 2026

## Behavior

Invoice and quote details now offer **View PDF** (or **View draft PDF**). The
viewer reloads the document through its existing repository before generating
the PDF, so the current collected amount and cancellation state are included.
Saved expense receipts open their original PDF or image when tapped. The tax
estimate opens its existing text report in the same viewer.

The Workloop viewer provides scrolling PDF pages, pinch zoom, labelled zoom
buttons and a fit control. Receipt images have the same zoom controls; text
reports are scrollable and selectable. **Share** is secondary and exports the
exact loaded document bytes. Opening a document does not mark it sent, issue
it, record income, upload another copy, or contact a customer.

CSV mileage, privacy JSON and calendar ICS remain structured-data exports.
Their records already have in-app views and are outside this document-preview
change.

## Implementation

- `lib/shared/documents/workloop_document_viewer.dart` owns one in-memory
  viewer for PDF, JPEG, PNG and UTF-8 text. Existing repositories and generators
  remain responsible for retrieving or creating bytes.
- The approved `printing` 5.15.0 renderer works with the existing `pdf` package.
  Its print, share, page-format, orientation and debug actions are disabled;
  Workloop supplies navigation, presentation and sharing controls.
- The viewer pins both account and workspace. In-flight loads cannot expose
  content after either changes. Workspace loading/error states hide content
  and block retained share callbacks until scope is confirmed. Signing out or
  changing workspace revokes that viewer permanently. Closing clears its
  byte references and evicts rendered image cache entries.
- The renderer callback remains stable during share-button updates, avoiding
  unnecessary rerendering. Empty files, unsupported formats and files above
  20 MiB are rejected; receipt upload limits remain the existing 10 MiB.
- Existing invoice form controls now use the shared `WorkloopFormField`
  wrapper, retaining outlines while allowing long labels to wrap above them.
  This includes client/service selection, VAT, deposits and manual receipts.

The package choice was checked against the maintained
[printing package](https://pub.dev/packages/printing) and its
[PdfPreview API](https://pub.dev/documentation/printing/latest/printing/PdfPreview-class.html).
The current pdfrx release requires a newer Flutter SDK than this checkout, so
it was not introduced alongside a framework upgrade.

## Verification

Focused widget coverage uses a mocked native raster channel while exercising
the real invoice/quote generators, navigation and saved-receipt loader. It
covers two-page scrolling, zoom at 320 px with 2× text, receipt images, retry,
malformed PDF handling, workspace refresh, workspace switch, sign-out and a
retained share callback. The accompanying invoice editor/settings/client
workflow suite checks the external labels and existing save/payment retries.

Ten viewer tests pass, alongside the 30 invoice editor/settings/client workflow
tests. Scoped analysis reports no issues and `git diff --check` passes. Evidence:
`/private/tmp/workloop-document-viewer-scope-tests.log`,
`/private/tmp/workloop-document-viewer-final-tests.log` (the 30 surrounding tests
passed; its initial workspace-refresh test timing was corrected in the later
viewer run), and `/private/tmp/workloop-document-viewer-final-analyze.log`.

Native PDF rendering, native sharing and the integrated release build are
separate device verification steps owned by the release run. No schema,
backend deployment, owner-account mutation or device action was performed by
this viewer implementation.

The integrated build 18 run subsequently verified actual iOS PDF rendering and
installed the normal app on the owner's phone. See
[final native/build/device evidence and limits](2026-09-08-build18-refinement.md).
