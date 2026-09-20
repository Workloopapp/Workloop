import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import Vision
#if canImport(Flutter)
import Flutter
#endif

enum ReceiptTextError: Error {
  case invalid, locked, unreadable
}

/// No files, network requests, or account data are retained by recognition.
/// Kept separate from Flutter so native fixtures can exercise the real engine.
enum ReceiptTextRecognizer {
  static let maximumPages = 5

  static func recognize(data: Data, mimeType: String) throws -> [String: Any] {
    guard !data.isEmpty, data.count <= 10 * 1024 * 1024 else {
      throw ReceiptTextError.invalid
    }
    if mimeType == "application/pdf" {
      guard let document = PDFDocument(data: data) else { throw ReceiptTextError.unreadable }
      guard !document.isLocked else { throw ReceiptTextError.locked }
      guard document.pageCount > 0 else { throw ReceiptTextError.unreadable }
      var pages: [String] = []
      var truncated = false
      let count = min(document.pageCount, maximumPages)
      for index in 0..<count {
        let text: String = try autoreleasepool {
          guard let page = document.page(at: index) else { throw ReceiptTextError.unreadable }
          let embedded = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          // Even a searchable page can contain a scanned receipt beside a
          // selectable heading/footer. Always inspect the rendered page too.
          guard let pdfPage = page.pageRef else { throw ReceiptTextError.unreadable }
          let bounds = pdfPage.getBoxRect(.cropBox)
          guard bounds.width > 0, bounds.height > 0 else { throw ReceiptTextError.unreadable }
          let scale = 2048 / max(bounds.width, bounds.height)
          let rotated = abs(pdfPage.rotationAngle) % 180 == 90
          let width = max(1, Int((rotated ? bounds.height : bounds.width) * scale))
          let height = max(1, Int((rotated ? bounds.width : bounds.height) * scale))
          guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          ) else { throw ReceiptTextError.unreadable }
          let destination = CGRect(x: 0, y: 0, width: width, height: height)
          context.setFillColor(CGColor(gray: 1, alpha: 1))
          context.fill(destination)
          context.concatenate(pdfPage.getDrawingTransform(.cropBox, rect: destination, rotate: 0, preserveAspectRatio: true))
          context.drawPDFPage(pdfPage)
          guard let image = context.makeImage() else { throw ReceiptTextError.unreadable }
          let recognized = try recognize(image: image)
          return embedded.isEmpty ? recognized : embedded + "\n" + recognized
        }
        truncated = truncated || text.count > 12000
        pages.append(String(text.prefix(12000)))
      }
      return ["text": pages.joined(separator: "\n\n"), "pageCount": document.pageCount, "processedPages": count, "textTruncated": truncated]
    }
    guard ["image/jpeg", "image/png"].contains(mimeType),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
            kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary) else { throw ReceiptTextError.unreadable }
    let text = try recognize(image: image)
    return ["text": String(text.prefix(12000)), "pageCount": 1, "processedPages": 1, "textTruncated": text.count > 12000]
  }

  private static func recognize(image: CGImage) throws -> String {
    let opaque: CGImage
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast:
      opaque = image
    default:
      // Exported PNG receipts can have black text on transparent pixels.
      // Vision treats that background as black unless composited onto paper.
      guard let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      ) else { throw ReceiptTextError.unreadable }
      let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(bounds)
      context.draw(image, in: bounds)
      guard let flattened = context.makeImage() else { throw ReceiptTextError.unreadable }
      opaque = flattened
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-GB", "en-US"]
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(cgImage: opaque, options: [:])
    try handler.perform([request])
    // Vision supplies observations in reading order. Keep line boundaries for
    // labels such as TOTAL rather than inferring amounts in native code.
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    return lines.joined(separator: "\n")
  }
}

#if canImport(Flutter)
final class WorkloopReceiptTextBridge {
  private let channel: FlutterMethodChannel
  private var busy = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "workloop/receipt_text", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "recognize" else { result(FlutterMethodNotImplemented); return }
      guard let self = self else { result(FlutterError(code: "recognition_failed", message: "Receipt reader closed.", details: nil)); return }
      guard !self.busy else { result(FlutterError(code: "recognition_failed", message: "Another receipt is being read.", details: nil)); return }
      guard let arguments = call.arguments as? [String: Any],
            let bytes = arguments["bytes"] as? FlutterStandardTypedData,
            let mimeType = arguments["mimeType"] as? String else {
        result(FlutterError(code: "invalid_receipt", message: "Choose a JPEG, PNG or PDF receipt.", details: nil)); return
      }
      self.busy = true
      DispatchQueue.global(qos: .userInitiated).async {
        let response: Any
        do {
          response = try ReceiptTextRecognizer.recognize(data: bytes.data, mimeType: mimeType)
        } catch ReceiptTextError.locked {
          response = FlutterError(code: "receipt_locked", message: "Choose an unlocked PDF or enter the details yourself.", details: nil)
        } catch ReceiptTextError.invalid {
          response = FlutterError(code: "invalid_receipt", message: "Choose a receipt up to 10 MB.", details: nil)
        } catch {
          response = FlutterError(code: "receipt_unreadable", message: "This receipt could not be read. You can enter the details yourself.", details: nil)
        }
        DispatchQueue.main.async {
          self.busy = false
          result(response)
        }
      }
    }
  }
}
#endif
