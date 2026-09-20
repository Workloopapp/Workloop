import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workloop/features/subscription/subscription_access.dart';

const subscriptionUser = '11000000-0000-4000-8000-000000000001';
const otherSubscriptionUser = '11000000-0000-4000-8000-000000000002';

ProductDetails subscriptionProduct([String id = WorkloopPlans.monthlyId]) =>
    ProductDetails(
      id: id,
      title: 'Workloop',
      description: 'All features',
      price: id == WorkloopPlans.yearlyId ? '£149.99' : '£14.99',
      rawPrice: id == WorkloopPlans.yearlyId ? 149.99 : 14.99,
      currencyCode: 'GBP',
    );

PurchaseDetails subscriptionPurchase({
  PurchaseStatus status = PurchaseStatus.purchased,
  String id = 'transaction-1',
  String receipt = 'signed-test-receipt',
  String product = WorkloopPlans.monthlyId,
  bool needsCompletion = true,
}) => PurchaseDetails(
  purchaseID: id,
  productID: product,
  verificationData: PurchaseVerificationData(
    localVerificationData: '',
    serverVerificationData: receipt,
    source: 'app_store',
  ),
  transactionDate: '1788739200000',
  status: status,
)..pendingCompletePurchase = needsCompletion;

class FakeSubscriptionStore implements InAppPurchase {
  final events = StreamController<List<PurchaseDetails>>.broadcast(sync: true);
  bool available = true, startsPurchase = true, failsLoad = false;
  int completeFailures = 0, restoreFailures = 0, queries = 0;
  List<ProductDetails> products = [
    subscriptionProduct(),
    subscriptionProduct(WorkloopPlans.yearlyId),
  ];
  final buys = <PurchaseParam>[];
  final completions = <PurchaseDetails>[];
  final restores = <String?>[];
  List<PurchaseDetails> restored = [];
  Completer<void>? queryPending;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    queries++;
    await queryPending?.future;
    if (failsLoad) throw StateError('store offline');
    return ProductDetailsResponse(productDetails: products, notFoundIDs: []);
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buys.add(purchaseParam);
    return startsPurchase;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completions.add(purchase);
    if (completeFailures-- > 0) {
      throw StateError('store acknowledgement offline');
    }
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restores.add(applicationUserName);
    if (restoreFailures-- > 0) throw StateError('restore unavailable');
    events.add(restored);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SubscriptionBackend {
  final requests = <http.Request>[];
  FutureOr<http.Response> Function(http.Request)? respond;
  late final client = SupabaseClient(
    'https://example.supabase.co',
    'public-fixture',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      requests.add(request);
      final response = respond == null
          ? jsonResponse({'verified': true, 'environment': 'Sandbox'})
          : await respond!(request);
      return http.Response(
        response.body,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }),
  );
  Future<void> account([String id = subscriptionUser]) async {
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'exp': 4102444800, 'sub': id, 'aal': 'aal1'})}.fixture';
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': token,
        'refresh_token': 'fixture-refresh',
        'token_type': 'bearer',
        'user': {
          'id': id,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': '$id@example.test',
          'email_confirmed_at': '2026-01-01T00:00:00Z',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  }
}

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Future<void> flushStoreEvents() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
