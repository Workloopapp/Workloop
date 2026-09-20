import { drainCustomerEventEmails } from "../_shared/customer_event_email.ts";
import {
  bookingSmsConfig,
  drainBookingReminderSms,
} from "../_shared/booking_sms.ts";
import { drainBookingReminderEmails } from "../_shared/booking_reminder_email.ts";
import { createClient } from "@supabase/supabase-js";
import {
  bookingConfirmationEmailConfig,
  BookingConfirmationRpcClient,
  drainBookingConfirmationEmails,
  validBookingConfirmationDrainToken,
} from "../_shared/booking_confirmation_email.ts";
import {
  drainWaitlistWelcomeEmails,
  waitlistWelcomeEmailConfig,
} from "../_shared/waitlist_welcome_email.ts";
import {
  accountWelcomeEmailConfig,
  drainAccountWelcomeEmails,
} from "../_shared/account_welcome_email.ts";
import {
  accountDeletionEmailConfig,
  drainAccountDeletionEmails,
} from "../_shared/account_deletion_email.ts";
import {
  automationAlertConfig,
  type AutomationClient,
  deliverOperationalAlerts,
  processAccountDeletions,
  runDatabaseAutomations,
} from "../_shared/workloop_automations.ts";
import {
  apnsPushConfig,
  drainPushNotifications,
  type PushDeliveryRpcClient,
} from "../_shared/push_delivery.ts";
import { fcmPushConfig } from "../_shared/push_delivery_fcm.ts";
import { drainSubscriptionTrialEmails } from "../_shared/subscription_trial_email.ts";

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return response(405, { error: "Method not allowed" });
  }

  const configuredToken = Deno.env.get("BOOKING_CONFIRMATION_DRAIN_TOKEN") ??
    "";
  const suppliedToken = req.headers.get("x-workloop-drain-token") ?? "";
  if (!validBookingConfirmationDrainToken(configuredToken, suppliedToken)) {
    return response(401, { error: "Unauthorized" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const emailConfig = bookingConfirmationEmailConfig();
  const waitlistConfig = waitlistWelcomeEmailConfig();
  const accountConfig = accountWelcomeEmailConfig();
  const deletionConfig = accountDeletionEmailConfig();
  const pushConfig = apnsPushConfig();
  const fcmConfig = fcmPushConfig();
  if (!supabaseUrl || serviceRoleKey.length < 32) {
    return response(503, { error: "Scheduled worker is not configured" });
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const results: Record<string, unknown> = {};
  const failures: string[] = [];
  const runJob = async (name: string, job: () => Promise<unknown>) => {
    try {
      results[name] = await job();
    } catch (_) {
      failures.push(name);
      console.error(`scheduled_worker_job_failed:${name}`);
    }
  };

  // Account deletion is the primary lifecycle guarantee. Run it before email
  // delivery so a provider outage cannot leave a requested account active.
  await runJob("deletions", () =>
    processAccountDeletions({
      client: serviceClient as unknown as AutomationClient,
      supabaseUrl,
      serviceRoleKey,
      adminToken: Deno.env.get("ACCOUNT_DELETION_ADMIN_TOKEN") ?? "",
      // Completion can include Stripe offboarding; keep the serial batch inside
      // the Edge execution window and let the minute schedule drain the rest.
      limit: 3,
    }));
  await runJob(
    "business",
    () => runDatabaseAutomations(serviceClient as unknown as AutomationClient),
  );
  if (pushConfig === null && fcmConfig === null) {
    failures.push("push");
  } else {
    await runJob("push", () =>
      drainPushNotifications({
        client: serviceClient as unknown as PushDeliveryRpcClient,
        config: pushConfig,
        fcmConfig,
        limit: 5,
      }));
  }

  const emailClient = serviceClient as unknown as BookingConfirmationRpcClient;
  // Billing reminders are service messages to the verified account owner.
  // Their private SQL outbox is disabled until the rollout flag is enabled.
  if (accountConfig !== null) {
    await runJob("subscription_trials", async () => {
      const result = await drainSubscriptionTrialEmails({
        client: emailClient,
        config: accountConfig,
        limit: 5,
      });
      if (result.failed > 0) failures.push("subscription_trials_delivery");
      return result;
    });
  }
  if (emailConfig === null) {
    failures.push("booking");
  } else {
    await runJob("booking", () =>
      drainBookingConfirmationEmails({
        client: emailClient,
        config: emailConfig,
        limit: 20,
      }));
  }
  if (emailConfig !== null) {
    await runJob("booking_reminders", async () => {
      const reminders = await drainBookingReminderEmails({
        client: emailClient,
        config: emailConfig,
        supabaseUrl,
        limit: 5,
      });
      if (reminders.failed > 0) failures.push("booking_reminders_delivery");
      return reminders;
    });
  }
  if (emailConfig !== null) {
    await runJob("customer_events", async () => {
      const result = await drainCustomerEventEmails({
        client: emailClient,
        config: emailConfig,
      });
      if (result.failed) failures.push("customer_events_delivery");
      return result;
    });
  }
  if (waitlistConfig === null) failures.push("waitlist");
  else {
    await runJob("waitlist", () =>
      drainWaitlistWelcomeEmails({
        client: emailClient,
        config: waitlistConfig,
        limit: 20,
      }));
  }
  if (accountConfig === null) failures.push("account");
  else {
    await runJob("account", () =>
      drainAccountWelcomeEmails({
        client: emailClient,
        config: accountConfig,
        limit: 20,
      }));
  }
  if (deletionConfig === null) failures.push("deletion");
  else {
    await runJob("deletion", () =>
      drainAccountDeletionEmails({
        client: emailClient,
        config: deletionConfig,
        limit: 20,
      }));
  }
  await runJob("alerts", () =>
    deliverOperationalAlerts({
      client: serviceClient as unknown as AutomationClient,
      config: automationAlertConfig(),
      limit: 20,
    }));

  // Optional SMS runs last so Twilio latency cannot delay existing email jobs.
  await runJob("booking_sms", async () => {
    const result = await drainBookingReminderSms({
      client: emailClient,
      config: bookingSmsConfig((name) => Deno.env.get(name)),
      limit: 5,
    });
    if (result.failed || result.uncertain) {
      failures.push("booking_sms_delivery");
    }
    return result;
  });

  // Counts provide operational evidence without logging recipient/body data.
  return response(failures.length === 0 ? 200 : 503, {
    ok: failures.length === 0,
    failures,
    ...results,
  });
});
