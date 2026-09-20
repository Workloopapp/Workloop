// Run on macOS: xcrun swiftc ios/Runner/ReceiptTextBridge.swift
// test/native/receipt_text_recognizer_smoke.swift -o /tmp/workloop-receipt-test
import AppKit
import PDFKit
import CoreText

@main
struct ReceiptTextSmoke {
  static func main() throws {
    let image = NSImage(size: NSSize(width: 900, height: 1100))
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 900, height: 1100)).fill()
    let lines = ["WORKLOOP RECEIPT FIXTURE", "08/09/2026", "Materials 25.00", "VAT 5.00", "TOTAL GBP 30.00", "CARD PAYMENT", "Reference WL-1842"]
    for (index, text) in lines.enumerated() {
      (text as NSString).draw(at: NSPoint(x: 75, y: 970 - index * 90), withAttributes: [.font: NSFont.systemFont(ofSize: 35), .foregroundColor: NSColor.black])
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let png = bitmap.representation(using: .png, properties: [:])!
    let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
    for (data, mime) in [(png, "image/png"), (jpeg, "image/jpeg")] {
      let result = try ReceiptTextRecognizer.recognize(data: data, mimeType: mime)
      let text = result["text"] as! String
      precondition(text.contains("30.00") && text.contains("08/09/2026"), "Real Vision OCR must recognize fixture amount and date")
      precondition(result["pageCount"] as? Int == 1)
      print("PASS \(mime): native Vision amount/date")
    }
    let transparent = NSImage(size: NSSize(width: 900, height: 1100))
    transparent.lockFocus()
    for (index, text) in lines.enumerated() {
      (text as NSString).draw(at: NSPoint(x: 75, y: 970 - index * 90), withAttributes: [.font: NSFont.systemFont(ofSize: 35), .foregroundColor: NSColor.black])
    }
    transparent.unlockFocus()
    let transparentPNG = NSBitmapImageRep(data: transparent.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    let transparentResult = try ReceiptTextRecognizer.recognize(data: transparentPNG, mimeType: "image/png")
    precondition((transparentResult["text"] as! String).contains("30.00"))
    print("PASS transparent PNG: black text remains readable on paper background")
    let scanned = PDFDocument()
    for index in 0..<6 { scanned.insert(PDFPage(image: image)!, at: index) }
    let pdf = scanned.dataRepresentation()!
    let result = try ReceiptTextRecognizer.recognize(data: pdf, mimeType: "application/pdf")
    precondition(result["pageCount"] as? Int == 6 && result["processedPages"] as? Int == 5)
    precondition((result["text"] as! String).components(separatedBy: "30.00").count == 6)
    print("PASS scanned PDF: Vision reads 5 pages and reports 6 total")
    let hybridBytes = NSMutableData()
    var media = CGRect(x: 0, y: 0, width: 900, height: 1200)
    let consumer = CGDataConsumer(data: hybridBytes)!
    let context = CGContext(consumer: consumer, mediaBox: &media, nil)!
    context.beginPDFPage(nil)
    context.draw(bitmap.cgImage!, in: CGRect(x: 0, y: 100, width: 900, height: 1100))
    context.textPosition = CGPoint(x: 30, y: 30)
    let footer = NSAttributedString(string: "Searchable heading on an otherwise scanned receipt", attributes: [.font: NSFont.systemFont(ofSize: 22)])
    CTLineDraw(CTLineCreateWithAttributedString(footer), context)
    context.endPDFPage()
    context.closePDF()
    precondition((PDFDocument(data: hybridBytes as Data)!.page(at: 0)!.string ?? "").count > 20)
    let hybrid = try ReceiptTextRecognizer.recognize(data: hybridBytes as Data, mimeType: "application/pdf")
    precondition((hybrid["text"] as! String).contains("30.00"))
    print("PASS hybrid PDF: searchable footer cannot hide scanned receipt")
    let encrypted = scanned.dataRepresentation(options: [PDFDocumentWriteOption.ownerPasswordOption: "owner-test", PDFDocumentWriteOption.userPasswordOption: "fixture-test"])!
    do {
      _ = try ReceiptTextRecognizer.recognize(data: encrypted, mimeType: "application/pdf")
      preconditionFailure("Locked PDF must fail")
    } catch ReceiptTextError.locked { print("PASS locked PDF remains manual") }
    do {
      _ = try ReceiptTextRecognizer.recognize(data: Data(), mimeType: "image/png")
      preconditionFailure("Empty bytes must fail")
    } catch ReceiptTextError.invalid { print("PASS empty receipt rejected") }
    do {
      _ = try ReceiptTextRecognizer.recognize(data: Data("bad image".utf8), mimeType: "image/jpeg")
      preconditionFailure("Invalid image must fail")
    } catch ReceiptTextError.unreadable { print("PASS invalid image rejected") }
  }
}
