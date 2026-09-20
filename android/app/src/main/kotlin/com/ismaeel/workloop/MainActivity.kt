package com.ismaeel.workloop

import android.Manifest
import android.content.pm.PackageManager
import android.content.pm.ApplicationInfo
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.nfc.NfcAdapter
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.stripe.stripeterminal.Terminal
import com.stripe.stripeterminal.external.callable.Cancelable
import com.stripe.stripeterminal.external.callable.ConnectionTokenCallback
import com.stripe.stripeterminal.external.callable.ConnectionTokenProvider
import com.stripe.stripeterminal.external.callable.TapToPayReaderListener
import com.stripe.stripeterminal.external.callable.TerminalListener
import com.stripe.stripeterminal.external.models.ConnectionConfiguration
import com.stripe.stripeterminal.external.models.ConnectionStatus
import com.stripe.stripeterminal.external.models.DisconnectReason
import com.stripe.stripeterminal.external.models.DiscoveryConfiguration
import com.stripe.stripeterminal.external.models.LocaleConfig
import com.stripe.stripeterminal.external.models.PaymentStatus
import com.stripe.stripeterminal.external.models.Reader
import com.stripe.stripeterminal.external.models.TapUseCase
import com.stripe.stripeterminal.external.models.TerminalException
import com.stripe.stripeterminal.external.models.ConnectionTokenException
import com.stripe.stripeterminal.ktx.connectReader
import com.stripe.stripeterminal.ktx.discoverReaders
import com.stripe.stripeterminal.ktx.processPaymentIntent
import com.stripe.stripeterminal.ktx.retrievePaymentIntent
import com.stripe.stripeterminal.log.LogLevel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity(), TapToPayReaderListener {
    private val paymentScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var paymentChannel: MethodChannel
    private var activeResult: MethodChannel.Result? = null
    private var receiptTextBridge: ReceiptTextBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        receiptTextBridge = ReceiptTextBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "workloop/notifications",
        ).setMethodCallHandler { call, result ->
            if (call.method != "openSettings") {
                result.notImplemented()
            } else {
                try {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"))
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            }
        }
        paymentChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ismaeel.workloop/payments",
        )
        paymentChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "availability" -> result.success(availability())
                "collectPayment" -> {
                    val clientSecret = call.argument<String>("clientSecret").orEmpty()
                    val locationId = call.argument<String>("locationId").orEmpty()
                    if (activeResult != null) {
                        result.error("reader_busy", "A payment is already in progress.", null)
                    } else if (clientSecret.isBlank() || !locationId.startsWith("tml_")) {
                        result.error("invalid_payment", "The payment reader request was incomplete.", null)
                    } else if (!hasLocationPermission()) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                            LOCATION_PERMISSION_REQUEST,
                        )
                        result.error(
                            "location_permission_required",
                            "Allow location access, then try the payment again.",
                            null,
                        )
                    } else {
                        activeResult = result
                        collectPayment(clientSecret, locationId)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun initializeTerminal() {
        if (Terminal.isInitialized()) return
        Terminal.init(
            applicationContext,
            if (isDebuggable()) LogLevel.VERBOSE else LogLevel.ERROR,
            FlutterConnectionTokenProvider(),
            object : TerminalListener {
                override fun onConnectionStatusChange(status: ConnectionStatus) = Unit
                override fun onPaymentStatusChange(status: PaymentStatus) = Unit
            },
            null,
            LocaleConfig.CardLanguagePreferenceIfAvailable,
        )
    }

    private fun availability(): Map<String, Any> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return mapOf(
                "supported" to false,
                "reason" to "Tap to Pay requires Android 13 or newer.",
            )
        }
        val adapter = NfcAdapter.getDefaultAdapter(this)
        if (adapter == null) {
            return mapOf("supported" to false, "reason" to "This phone does not have NFC.")
        }
        if (!adapter.isEnabled) {
            return mapOf("supported" to false, "reason" to "Turn on NFC to take a payment.")
        }
        return mapOf("supported" to true)
    }

    private fun collectPayment(clientSecret: String, locationId: String) {
        paymentScope.launch {
            try {
                initializeTerminal()
                val terminal = Terminal.getInstance()
                if (terminal.connectionStatus != ConnectionStatus.CONNECTED) {
                    val reader = terminal.discoverReaders(
                        DiscoveryConfiguration.TapToPayDiscoveryConfiguration(
                            isSimulated = isDebuggable(),
                        ),
                    ).first { it.isNotEmpty() }.first()
                    terminal.connectReader(
                        reader,
                        ConnectionConfiguration.TapToPayConnectionConfiguration(
                            useCase = TapUseCase.Pay(locationId),
                            autoReconnectOnUnexpectedDisconnect = true,
                            tapToPayReaderListener = this@MainActivity,
                        ),
                    )
                }
                val intent = withContext(Dispatchers.IO) {
                    terminal.retrievePaymentIntent(clientSecret)
                }
                val processed = terminal.processPaymentIntent(intent)
                complete(
                    mapOf(
                        "paymentIntentId" to processed.id.orEmpty(),
                        "status" to processed.status.toString().lowercase(),
                    ),
                )
            } catch (error: CancellationException) {
                completeError("payment_cancelled", "The payment was cancelled.")
            } catch (error: TerminalException) {
                completeError(error.errorCode.toString(), error.errorMessage)
            } catch (error: Throwable) {
                completeError("tap_to_pay_failed", error.localizedMessage ?: "Tap to Pay failed.")
            }
        }
    }

    private fun complete(value: Any) {
        val result = activeResult
        activeResult = null
        result?.success(value)
    }

    private fun completeError(code: String, message: String) {
        val result = activeResult
        activeResult = null
        result?.error(code, message, null)
    }

    private fun hasLocationPermission() =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun isDebuggable() =
        applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

    private inner class FlutterConnectionTokenProvider : ConnectionTokenProvider {
        override fun fetchConnectionToken(callback: ConnectionTokenCallback) {
            runOnUiThread {
                paymentChannel.invokeMethod(
                    "fetchConnectionToken",
                    null,
                    object : MethodChannel.Result {
                        override fun success(value: Any?) {
                            val token = value as? String
                            if (token?.startsWith("pst_") == true) {
                                callback.onSuccess(token)
                            } else {
                                fail()
                            }
                        }

                        override fun error(code: String, message: String?, details: Any?) = fail()
                        override fun notImplemented() = fail()

                        private fun fail() {
                            callback.onFailure(
                                ConnectionTokenException(
                                    "Could not authenticate the payment reader.",
                                    IllegalStateException("Missing connection token"),
                                ),
                            )
                        }
                    },
                )
            }
        }
    }

    override fun onDisconnect(reason: DisconnectReason) = Unit
    override fun onReaderReconnectStarted(
        reader: Reader,
        cancelReconnect: Cancelable,
        reason: DisconnectReason,
    ) = Unit
    override fun onReaderReconnectSucceeded(reader: Reader) = Unit
    override fun onReaderReconnectFailed(reader: Reader) = Unit

    override fun onDestroy() {
        receiptTextBridge?.close()
        paymentScope.cancel()
        super.onDestroy()
    }

    companion object {
        private const val LOCATION_PERMISSION_REQUEST = 9104
    }
}
