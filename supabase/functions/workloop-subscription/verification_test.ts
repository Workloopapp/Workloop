import {
  subscriptionRecord,
  type VerifiedTransaction,
  verifyNotification,
  verifyTransaction,
} from "./verification.ts";

const user = "a2600000-0000-4000-8000-000000000001";
const signed = Date.parse("2026-09-07T00:00:00Z");
const expiry = Date.parse("2026-10-07T00:00:00Z");
const valid: VerifiedTransaction = {
  bundleId: "com.ismaeel.workloop",
  productId: "workloop_monthly",
  appAccountToken: user,
  originalTransactionId: "10000000000000001",
  transactionId: "10000000000000002",
  expiresDate: expiry,
  signedDate: signed,
  environment: "Production",
  type: "Auto-Renewable Subscription",
};
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
function rejects(action: () => unknown) {
  try {
    action();
  } catch {
    return;
  }
  throw new Error("Expected rejection");
}

Deno.test("verified transaction binds app, product, account and transaction period", () => {
  const record = subscriptionRecord(valid, user.toUpperCase());
  equal(record.user_id, user);
  equal(record.environment, "Production");
  equal(record.transaction_id, valid.transactionId);
  equal(record.original_transaction_id, valid.originalTransactionId);
  equal(record.expires_at, "2026-10-07T00:00:00.000Z");
  equal(record.status_signed_at, null);
  equal(record.grace_expires_at, null);
});

for (
  const [name, changes] of Object.entries({
    bundle: { bundleId: "another.app" },
    product: { productId: "unknown" },
    account: { appAccountToken: "invalid" },
    missingAccount: { appAccountToken: undefined },
    type: { type: "Consumable" },
    environment: { environment: "Xcode" },
    original: { originalTransactionId: "not-an-id" },
    transaction: { transactionId: "" },
    expiry: { expiresDate: NaN },
    zeroExpiry: { expiresDate: 0 },
    signed: { signedDate: 1.5 },
    missingSigned: { signedDate: undefined },
    invalidDate: { revocationDate: -1 },
    invalidUpgrade: { isUpgraded: "yes" },
  })
) {
  Deno.test(`reject invalid ${name} in verified policy input`, () => {
    rejects(() =>
      subscriptionRecord({ ...valid, ...changes } as VerifiedTransaction, user)
    );
  });
}
Deno.test("another authenticated account cannot attach the same signed purchase", () => {
  rejects(() =>
    subscriptionRecord(valid, "a2600000-0000-4000-8000-000000000002")
  );
});
Deno.test("sandbox remains sandbox and cannot be relabelled by the caller", () => {
  equal(
    subscriptionRecord({ ...valid, environment: "Sandbox" }, user).environment,
    "Sandbox",
  );
});
Deno.test("refund and upgrade facts survive verified conversion", () => {
  const record = subscriptionRecord({
    ...valid,
    revocationDate: signed + 1000,
    isUpgraded: true,
  }, user);
  equal(record.revoked_at, "2026-09-07T00:00:01.000Z");
  equal(record.is_upgraded, true);
});
Deno.test("grace status has an independent verified event timestamp", () => {
  const grace = expiry + 86400000;
  rejects(() => subscriptionRecord(valid, user, grace));
  const record = subscriptionRecord(valid, user, grace, signed + 1000);
  equal(record.grace_expires_at, "2026-10-08T00:00:00.000Z");
  equal(record.status_signed_at, "2026-09-07T00:00:01.000Z");
  equal(subscriptionRecord(valid, user).status_signed_at, null);
});
Deno.test("later notification preserves the inner transaction snapshot date", () => {
  const record = subscriptionRecord(valid, user, undefined, signed + 86400000);
  equal(record.signed_at, "2026-09-07T00:00:00.000Z");
  equal(record.status_signed_at, "2026-09-08T00:00:00.000Z");
  rejects(() =>
    subscriptionRecord(
      { ...valid, signedDate: undefined },
      user,
      undefined,
      signed,
    )
  );
});
for (
  const [name, value] of Object.entries({
    unsigned: "not-a-jws",
    noCertificate: `${btoa(JSON.stringify({ alg: "ES256" }))}.${
      btoa(JSON.stringify(valid))
    }.ZmFrZQ`,
    noneAlgorithm: `${btoa(JSON.stringify({ alg: "none" }))}.${
      btoa(JSON.stringify(valid))
    }.`,
    fakeCertificate: `${
      btoa(JSON.stringify({ alg: "ES256", x5c: ["ZmFrZQ"] }))
    }.${btoa(JSON.stringify(valid))}.ZmFrZQ`,
  })
) {
  Deno.test(`real Apple SDK rejects forged ${name} transaction and notification`, async () => {
    for (const verify of [verifyTransaction, verifyNotification]) {
      let rejected = false;
      try {
        await verify(value);
      } catch {
        rejected = true;
      }
      equal(rejected, true);
    }
  });
}

Deno.test("only an explicit introductory FREE_TRIAL is a free trial", () => {
  const trial = {
    ...valid,
    offerType: 1,
    offerDiscountType: "FREE_TRIAL",
    purchaseDate: signed,
  };
  equal(subscriptionRecord(trial).is_free_trial, true);
  equal(subscriptionRecord(trial).purchased_at, "2026-09-07T00:00:00.000Z");
  equal(subscriptionRecord({ ...trial, offerType: 2 }).is_free_trial, false);
  equal(
    subscriptionRecord({ ...trial, offerDiscountType: "PAY_AS_YOU_GO" })
      .is_free_trial,
    false,
  );
  equal(subscriptionRecord(valid).is_free_trial, false);
  rejects(() => subscriptionRecord({ ...trial, purchaseDate: undefined }));
  rejects(() => subscriptionRecord({ ...trial, purchaseDate: expiry }));
});
const renewal = {
  originalTransactionId: valid.originalTransactionId,
  productId: valid.productId,
  autoRenewProductId: valid.productId,
  environment: "Production",
  signedDate: signed + 5000,
  autoRenewStatus: 1,
  renewalDate: expiry,
  isInBillingRetryPeriod: false,
};
Deno.test("signed renewal metadata retains its own timestamp and next charge", () => {
  const record = subscriptionRecord(
    valid,
    user,
    undefined,
    signed + 10000,
    renewal,
  );
  equal(record.signed_at, "2026-09-07T00:00:00.000Z");
  equal(record.status_signed_at, "2026-09-07T00:00:10.000Z");
  equal(record.renewal_signed_at, "2026-09-07T00:00:05.000Z");
  equal(record.auto_renews, true);
  equal(record.renews_at, "2026-10-07T00:00:00.000Z");
  equal(record.in_billing_retry, false);
  equal(subscriptionRecord(valid).auto_renews, null);
});
Deno.test("verified cancellation and billing retry are preserved", () => {
  const record = subscriptionRecord(valid, user, undefined, signed, {
    ...renewal,
    autoRenewStatus: 0,
    isInBillingRetryPeriod: true,
  });
  equal(record.auto_renews, false);
  equal(record.in_billing_retry, true);
});
Deno.test("renewal may name another allowed product in the same chain", () => {
  equal(
    subscriptionRecord(valid, user, undefined, signed, {
      ...renewal,
      productId: "workloop_yearly",
      autoRenewProductId: "workloop_yearly",
    }).auto_renews,
    true,
  );
});
for (
  const [name, changes] of Object.entries({
    chain: { originalTransactionId: "other" },
    environment: { environment: "Sandbox" },
    product: { productId: "unknown" },
    nextProduct: { autoRenewProductId: "unknown" },
    autoRenew: { autoRenewStatus: 2 },
    missingAutoRenew: { autoRenewStatus: undefined },
    signedDate: { signedDate: undefined },
    nextCharge: { renewalDate: -1 },
    retry: { isInBillingRetryPeriod: "true" },
  })
) {
  Deno.test(`reject invalid verified renewal ${name}`, () => {
    rejects(() =>
      subscriptionRecord(
        valid,
        user,
        undefined,
        signed,
        { ...renewal, ...changes } as typeof renewal,
      )
    );
  });
}
