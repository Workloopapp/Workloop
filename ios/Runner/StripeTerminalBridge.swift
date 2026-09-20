import Flutter
import StripeTerminal
import UIKit

final class WorkloopStripeTerminalBridge: NSObject {
  private let channel: FlutterMethodChannel
  private var activeResult: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.ismaeel.workloop/payments",
      binaryMessenger: messenger
    )
    super.init()
    Terminal.initWithTokenProvider(self)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "availability":
      #if targetEnvironment(simulator)
      result(["supported": true, "reason": "Stripe simulated reader"])
      #else
      switch Terminal.shared.supportsReaders(
        of: .tapToPay,
        discoveryMethod: .tapToPay,
        simulated: false
      ) {
      case .success:
        result(["supported": true])
      case .failure(let error):
        result(["supported": false, "reason": error.localizedDescription])
      }
      #endif
    case "collectPayment":
      guard activeResult == nil else {
        result(FlutterError(
          code: "reader_busy",
          message: "A payment is already in progress.",
          details: nil
        ))
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let clientSecret = arguments["clientSecret"] as? String,
        let locationId = arguments["locationId"] as? String,
        !clientSecret.isEmpty,
        locationId.hasPrefix("tml_")
      else {
        result(FlutterError(
          code: "invalid_payment",
          message: "The payment reader request was incomplete.",
          details: nil
        ))
        return
      }
      activeResult = result
      Task { @MainActor [weak self] in
        await self?.collectPayment(clientSecret: clientSecret, locationId: locationId)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @MainActor
  private func collectPayment(clientSecret: String, locationId: String) async {
    do {
      #if targetEnvironment(simulator)
      let simulated = true
      #else
      let simulated = false
      #endif

      let discovery = try TapToPayDiscoveryConfigurationBuilder()
        .setSimulated(simulated)
        .build()
      let connection = try TapToPayConnectionConfigurationBuilder(
        delegate: self,
        locationId: locationId
      )
      .setAutoReconnectOnUnexpectedDisconnect(true)
      .build()
      let easyConnect = TapToPayEasyConnectConfiguration(
        discoveryConfiguration: discovery,
        connectionConfiguration: connection
      )
      _ = try await Terminal.shared.easyConnect(easyConnect)
      let paymentIntent = try await retrievePaymentIntent(clientSecret: clientSecret)
      let processed = try await Terminal.shared.processPaymentIntent(paymentIntent)
      complete([
        "paymentIntentId": processed.stripeId ?? "",
        "status": String(describing: processed.status),
      ])
    } catch {
      complete(FlutterError(
        code: "tap_to_pay_failed",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private func retrievePaymentIntent(clientSecret: String) async throws -> PaymentIntent {
    try await withCheckedThrowingContinuation { continuation in
      Terminal.shared.retrievePaymentIntent(clientSecret: clientSecret) { intent, error in
        if let intent {
          continuation.resume(returning: intent)
        } else {
          continuation.resume(throwing: error ?? NSError(
            domain: "com.ismaeel.workloop.payments",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not load the payment."]
          ))
        }
      }
    }
  }

  private func complete(_ value: Any) {
    let result = activeResult
    activeResult = nil
    result?(value)
  }
}

extension WorkloopStripeTerminalBridge: ConnectionTokenProvider {
  func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
    channel.invokeMethod("fetchConnectionToken", arguments: nil) { value in
      if let token = value as? String, token.hasPrefix("pst_") {
        completion(token, nil)
        return
      }
      let message: String
      if let flutterError = value as? FlutterError {
        message = flutterError.message ?? "Could not authenticate the payment reader."
      } else {
        message = "Could not authenticate the payment reader."
      }
      completion(nil, NSError(
        domain: "com.ismaeel.workloop.payments",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: message]
      ))
    }
  }
}

extension WorkloopStripeTerminalBridge: TapToPayReaderDelegate {
  func tapToPayReader(
    _ reader: Reader,
    didStartInstallingUpdate update: ReaderSoftwareUpdate,
    cancelable: Cancelable?
  ) {}

  func tapToPayReader(
    _ reader: Reader,
    didReportReaderSoftwareUpdateProgress progress: Float
  ) {}

  func tapToPayReader(
    _ reader: Reader,
    didFinishInstallingUpdate update: ReaderSoftwareUpdate?,
    error: Error?
  ) {}

  func tapToPayReader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions) {}

  func tapToPayReader(
    _ reader: Reader,
    didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage
  ) {}
}
