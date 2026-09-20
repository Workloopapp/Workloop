import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String path) => File(path).readAsStringSync().toLowerCase();

void _expectBefore(String source, String first, String second) {
  final firstIndex = source.indexOf(first);
  final secondIndex = source.indexOf(second);
  expect(firstIndex, greaterThanOrEqualTo(0), reason: 'Missing "$first"');
  expect(secondIndex, greaterThanOrEqualTo(0), reason: 'Missing "$second"');
  expect(
    firstIndex,
    lessThan(secondIndex),
    reason: 'Expected "$first" before "$second"',
  );
}

String _phoneDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

void main() {
  group('target-date public availability boundary', () {
    late String migration;
    late String edgeHandler;
    late String edgeContract;

    setUpAll(() {
      migration = _source(
        'supabase/migrations/'
        '20260902183040_public_booking_target_date_availability.sql',
      );
      edgeHandler = _source(
        'supabase/functions/get-public-booking-availability/index.ts',
      );
      edgeContract = _source(
        'supabase/functions/get-public-booking-availability/'
        'availability_contract.ts',
      );
    });

    test('keeps the old RPC and adds a service-role-only dated version', () {
      expect(
        migration,
        contains(
          'create or replace function public.get_public_booking_slot_suggestions(',
        ),
      );
      expect(
        migration,
        contains(
          'create function public.get_public_booking_slot_suggestions_v3',
        ),
      );
      expect(migration, contains('p_target_date date default null'));
      expect(migration, contains('from public, anon, authenticated'));
      expect(migration, contains('to service_role'));
      expect(migration, isNot(contains('security definer')));
    });

    test('edge validates and forwards one optional target date', () {
      expect(edgeContract, contains('targetdate: string | null'));
      expect(edgeContract, contains('safeisodate'));
      expect(edgeHandler, contains('get_public_booking_slot_suggestions_v3'));
      expect(edgeHandler, contains('p_target_date: input.targetdate'));
    });
  });

  group('service add-on and snapshot boundary', () {
    late String migration;

    setUpAll(() {
      migration = _source(
        'supabase/migrations/'
        '20260902172046_service_add_ons_and_booking_item_snapshots.sql',
      );
    });

    test('new public tables enable RLS and use explicit least privilege', () {
      for (final table in const [
        'service_add_ons',
        'booking_request_items',
        'appointment_items',
      ]) {
        expect(
          migration,
          contains('alter table public.$table enable row level security'),
        );
        expect(migration, contains('revoke all on table public.$table'));
      }
      expect(
        migration,
        contains(
          'grant select on table public.booking_request_items, public.appointment_items',
        ),
      );
      expect(
        migration,
        isNot(
          contains(
            'grant select, insert, update, delete on table public.booking_request_items',
          ),
        ),
      );
    });

    test(
      'tenant-safe foreign keys and immutable snapshot sources are explicit',
      () {
        expect(migration, contains('service_add_ons_workspace_service_fk'));
        expect(
          migration,
          contains('booking_request_items_workspace_request_fk'),
        );
        expect(
          migration,
          contains('appointment_items_workspace_appointment_fk'),
        );
        expect(migration, contains('on delete set null (source_add_on_id)'));
        expect(migration, contains('booking_request_items_one_base_uidx'));
        expect(migration, contains('appointment_items_one_base_uidx'));
        for (final index in const [
          'booking_request_items_workspace_source_service_idx',
          'booking_request_items_workspace_source_add_on_idx',
          'appointment_items_workspace_source_service_idx',
          'appointment_items_workspace_source_add_on_idx',
        ]) {
          expect(migration, contains('create index $index'));
        }
      },
    );

    test('v3 trusts catalog IDs and preserves older intake RPCs', () {
      expect(
        migration,
        contains(
          'create function app_private.snapshot_booking_request_base_service()',
        ),
      );
      expect(migration, contains('after insert on public.booking_requests'));
      expect(
        migration,
        contains(
          'on conflict on constraint '
          'booking_request_items_booking_request_id_position_key',
        ),
      );
      expect(
        migration,
        isNot(contains('on conflict (booking_request_id, position)')),
      );
      expect(
        migration,
        contains('create function public.create_public_booking_request_v3'),
      );
      final v3Function = migration.substring(
        migration.indexOf(
          'create function public.create_public_booking_request_v3',
        ),
        migration.indexOf(
          'comment on function public.create_public_booking_request_v3',
        ),
      );
      expect(
        v3Function,
        isNot(contains("current_setting('request.jwt.claim.role'")),
      );
      expect(v3Function, contains('from public, anon, authenticated'));
      expect(v3Function, contains('to service_role'));
      expect(migration, contains("'invalid_add_on'::text"));
      expect(migration, contains('add_on.id = any(p_add_on_ids)'));
      expect(
        migration,
        contains(
          'create function public.get_public_booking_slot_suggestions_v2',
        ),
      );
      expect(migration, contains('sum(add_on.duration_mins)'));
      expect(
        migration,
        contains('return public.get_public_booking_slot_suggestions'),
      );
      expect(
        migration,
        contains('from public.create_public_booking_request_v2'),
      );
      expect(
        migration,
        isNot(
          contains('drop function public.create_public_booking_request_v2'),
        ),
      );
    });

    test('booking workflow copies request snapshots atomically', () {
      final workflowWrapper = migration.substring(
        migration.indexOf(
          'create function app_private.create_booking_workflow(p_payload jsonb)',
        ),
      );
      _expectBefore(
        workflowWrapper,
        'v_result := app_private.create_booking_workflow_without_item_snapshots',
        'insert into public.appointment_items',
      );
      expect(
        workflowWrapper,
        contains('from public.booking_request_items request_item'),
      );
      expect(
        workflowWrapper,
        contains(
          'on conflict on constraint '
          'appointment_items_appointment_id_position_key',
        ),
      );
      expect(
        workflowWrapper,
        isNot(contains('on conflict (appointment_id, position)')),
      );
      _expectBefore(
        workflowWrapper,
        'request.result is not null',
        "if p_payload ? 'add_on_ids'",
      );
    });

    test(
      'snapshot wrapper remains outside confirmation email and overlap core',
      () {
        final confirmationMigration = _source(
          'supabase/migrations/'
          '20260813205930_booking_request_confirmation_email_outbox.sql',
        );
        final overlapMigration = _source(
          'supabase/migrations/'
          '20260902172036_allow_booking_schedule_exceptions.sql',
        );

        expect(
          confirmationMigration,
          contains(
            'rename to create_booking_workflow_without_confirmation_email',
          ),
        );
        expect(
          confirmationMigration,
          contains('insert into app_private.transactional_email_outbox'),
        );
        expect(
          overlapMigration,
          contains(
            'create or replace function app_private.create_booking_workflow_without_confirmation_email',
          ),
        );
        expect(
          migration,
          contains('rename to create_booking_workflow_without_item_snapshots'),
        );
        expect(
          migration,
          contains(
            'v_result := app_private.create_booking_workflow_without_item_snapshots',
          ),
        );
      },
    );

    test('database regression covers legacy conversion and email intent', () {
      final pgTap = _source(
        'supabase/tests/database/012_service_add_ons_and_snapshots.test.sql',
      );
      expect(pgTap, contains('public.create_public_booking_request_v2'));
      expect(pgTap, contains('public.create_booking_workflow(payload)'));
      expect(pgTap, contains('from public.appointment_items item'));
      expect(pgTap, contains('app_private.transactional_email_outbox'));
    });
  });

  group('public booking request database boundary', () {
    late String rateLimitMigration;

    setUpAll(() {
      rateLimitMigration = _source(
        'supabase/migrations/20260726000057_edge_rate_limits.sql',
      );
    });

    test('duplicate tokens are unique and short-circuit side effects', () {
      expect(
        rateLimitMigration,
        contains('booking_requests_workspace_request_token_idx'),
      );
      expect(
        rateLimitMigration,
        contains('on public.booking_requests(workspace_id, request_token)'),
      );
      _expectBefore(
        rateLimitMigration,
        'select request.id',
        'delete from app_private.edge_rate_limit_events',
      );
      _expectBefore(
        rateLimitMigration,
        "return query select v_existing_id, 'duplicate'::text",
        'insert into public.notifications',
      );
    });

    test('service ownership, visibility, and booking mode are enforced', () {
      expect(rateLimitMigration, contains("profile.booking_mode = 'manual'"));
      expect(
        rateLimitMigration,
        contains('service.workspace_id = p_workspace_id'),
      );
      expect(rateLimitMigration, contains('service.show_on_profile = true'));
      expect(rateLimitMigration, contains('service.active = true'));
      _expectBefore(
        rateLimitMigration,
        "return query select null::uuid, 'invalid_service'::text",
        'insert into public.booking_requests',
      );
    });

    test('rate limits serialize and normalize both abuse dimensions', () {
      expect(rateLimitMigration, contains('pg_advisory_xact_lock'));
      expect(rateLimitMigration, contains("scope = 'booking_source'"));
      expect(rateLimitMigration, contains('if v_source_count >= 5'));
      expect(rateLimitMigration, contains("scope = 'booking_phone'"));
      expect(rateLimitMigration, contains('if v_phone_count >= 3'));
      expect(rateLimitMigration, contains("interval '15 minutes'"));
      expect(
        rateLimitMigration,
        contains("regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')"),
      );
    });

    test('ledger and intake RPC are closed to mobile roles', () {
      final denyMigration = _source(
        'supabase/migrations/'
        '20260726000520_deny_client_edge_rate_limit_access.sql',
      );
      expect(rateLimitMigration, contains('enable row level security'));
      expect(
        rateLimitMigration,
        contains(
          'revoke all on table app_private.edge_rate_limit_events from anon',
        ),
      );
      expect(
        rateLimitMigration,
        contains(
          'revoke all on table app_private.edge_rate_limit_events from authenticated',
        ),
      );
      expect(rateLimitMigration, contains(') to service_role'));
      expect(denyMigration, contains('to anon, authenticated'));
      expect(denyMigration, contains('using (false)'));
      expect(denyMigration, contains('with check (false)'));
    });
  });

  test('public profile publishes only active extras below public services', () {
    final handler = _source('supabase/functions/get-public-profile/index.ts');
    expect(handler, contains('service_add_ons('));
    expect(handler, contains('.eq("service_add_ons.active", true)'));
    expect(handler, contains('.eq("show_on_profile", true)'));
    expect(handler, contains('.eq("active", true)'));
    expect(handler, contains('.gte("duration_mins", 5)'));
    expect(handler, contains('.lte("duration_mins", 1440)'));
  });

  test(
    'service duration migration quarantines legacy values before bounding writes',
    () {
      final migration = _source(
        'supabase/migrations/'
        '20260902174021_bound_public_service_durations.sql',
      );
      expect(migration, contains('set duration_mins = 60'));
      expect(migration, contains('active = false'));
      expect(migration, contains('show_on_profile = false'));
      expect(migration, contains('where duration_mins not between 5 and 1440'));
      expect(migration, contains('services_duration_mins_check'));
      _expectBefore(
        migration,
        'update public.services',
        'add constraint services_duration_mins_check',
      );
    },
  );

  test('owner booking request queries load immutable item snapshots', () {
    final repository = _source(
      'lib/shared/repositories/profile_repository.dart',
    );
    expect(repository, contains('booking_request_items(id, workspace_id'));
    expect(repository, contains('source_add_on_id'));
  });

  group('member booking conversion boundary', () {
    late String workflowMigration;

    setUpAll(() {
      workflowMigration = _source(
        'supabase/migrations/'
        '20260726000118_transactional_booking_workflows.sql',
      );
    });

    test('auth, workspace ownership, and linked records are validated', () {
      expect(workflowMigration, contains('v_caller_id uuid := auth.uid()'));
      expect(workflowMigration, contains('workspace access denied'));
      expect(
        workflowMigration,
        contains('member.workspace_id = v_workspace_id'),
      );
      expect(workflowMigration, contains('member.user_id = v_caller_id'));
      expect(
        workflowMigration,
        contains('service.workspace_id = v_workspace_id'),
      );
      expect(
        workflowMigration,
        contains('contact.workspace_id = v_workspace_id'),
      );
    });

    test('request conversion is locked, active-only, and atomic', () {
      expect(workflowMigration, contains('pg_advisory_xact_lock'));
      expect(
        workflowMigration,
        contains('request.workspace_id = v_workspace_id'),
      );
      expect(workflowMigration, contains('for update;'));
      expect(
        workflowMigration,
        contains("v_request_status not in ('pending', 'contacted')"),
      );
      _expectBefore(
        workflowMigration,
        'appointment overlaps an existing booking',
        'insert into public.appointments',
      );
      _expectBefore(
        workflowMigration,
        "set status = 'confirmed'",
        'insert into public.notifications',
      );
      _expectBefore(
        workflowMigration,
        'insert into public.notifications',
        'set result = v_existing_result',
      );
    });

    test('idempotency and callable privileges are explicit', () {
      expect(
        workflowMigration,
        contains(
          'primary key (workspace_id, user_id, operation, idempotency_key)',
        ),
      );
      expect(workflowMigration, contains('security definer'));
      expect(workflowMigration, contains("set search_path = ''"));
      expect(workflowMigration, contains('security invoker'));
      expect(
        workflowMigration,
        contains(
          'revoke execute on function public.create_booking_workflow(jsonb)',
        ),
      );
      expect(workflowMigration, contains('from public, anon'));
      expect(
        workflowMigration,
        contains(
          'grant execute on function public.create_booking_workflow(jsonb)',
        ),
      );
      expect(workflowMigration, contains('to authenticated'));
    });
  });

  group('launch booking hardening migration', () {
    late String hardeningMigration;

    setUpAll(() {
      hardeningMigration = _source(
        'supabase/migrations/'
        '20260726005736_harden_booking_notification_and_contact_reuse.sql',
      );
    });

    test('public request notifications respect both preference switches', () {
      final triggerFunction = hardeningMigration.substring(
        0,
        hardeningMigration.indexOf(
          'create or replace function app_private.create_booking_workflow',
        ),
      );

      expect(hardeningMigration, contains('new.type = \'booking_request\''));
      expect(
        hardeningMigration,
        contains('preference.workspace_id = new.workspace_id'),
      );
      expect(hardeningMigration, contains('not preference.all_notifications'));
      expect(hardeningMigration, contains('not preference.booking_request'));
      expect(hardeningMigration, contains('return null'));
      expect(
        hardeningMigration,
        contains('before insert on public.notifications'),
      );
      expect(hardeningMigration, contains("set search_path = ''"));
      expect(hardeningMigration, contains('from public, anon, authenticated'));
      expect(triggerFunction, contains('security invoker'));
      expect(triggerFunction, isNot(contains('security definer')));
    });

    test('contact reuse compares workspace-scoped canonical digits', () {
      expect(
        hardeningMigration,
        contains(
          'create or replace function '
          'app_private.create_booking_workflow',
        ),
      );
      expect(hardeningMigration, contains('member.user_id = v_caller_id'));
      expect(
        hardeningMigration,
        contains('contact.workspace_id = v_workspace_id'),
      );
      expect(
        hardeningMigration,
        contains("contact.phone = btrim(v_new_contact ->> 'phone')"),
      );
      expect(hardeningMigration, contains("coalesce(contact.phone, '')"));
      expect(
        hardeningMigration,
        contains("coalesce(v_new_contact ->> 'phone', '')"),
      );
      expect(hardeningMigration, contains("'[^0-9]'"));
      expect(hardeningMigration, contains(')) >= 7'));
      expect(hardeningMigration, contains('for update;'));
      expect(hardeningMigration, contains('pg_advisory_xact_lock'));
      _expectBefore(
        hardeningMigration,
        'insert into app_private.workflow_idempotency',
        'perform pg_advisory_xact_lock',
      );
      _expectBefore(
        hardeningMigration,
        'perform pg_advisory_xact_lock',
        'select contact.id',
      );
      expect(
        hardeningMigration,
        contains('select app_private.create_booking_workflow(p_payload)'),
      );
      expect(hardeningMigration, isNot(contains("'+44'")));
      expect(hardeningMigration, isNot(contains('united kingdom')));
    });

    test(
      'digit matching removes formatting but invents no country mapping',
      () {
        expect(
          _phoneDigits('+44 (0) 7123-456-789'),
          _phoneDigits('44 0 7123 456 789'),
        );
        expect(
          _phoneDigits('07123 456789'),
          isNot(_phoneDigits('+44 7123 456789')),
        );
      },
    );
  });

  test('schema contract records current booking backend shape', () {
    final schemaContract = _source('supabase/schema_contract.sql');

    expect(schemaContract, contains('phone_normalized text'));
    expect(
      schemaContract,
      contains(
        "generated always as (regexp_replace(phone, '[^0-9]', '', 'g')) stored",
      ),
    );
    expect(schemaContract, contains('request_token uuid'));
    expect(
      schemaContract,
      contains('booking_requests_workspace_request_token_idx'),
    );
    expect(
      schemaContract,
      contains('create table if not exists app_private.edge_rate_limit_events'),
    );
    expect(schemaContract, contains('enable row level security'));
    expect(schemaContract, contains('edge_rate_limit_events_deny_clients'));
    expect(schemaContract, contains('using (false)'));
    expect(schemaContract, contains('with check (false)'));
    expect(schemaContract, contains('from public, anon, authenticated'));
    expect(schemaContract, contains('to service_role'));
    expect(schemaContract, contains('dedupe_key text'));
    expect(schemaContract, contains('notifications_workspace_dedupe_uidx'));
    expect(schemaContract, contains('public.create_public_booking_request('));
    expect(
      schemaContract,
      contains('public.create_booking_workflow(jsonb) returns jsonb'),
    );
    expect(
      schemaContract,
      contains('public.complete_booking_workflow(jsonb) returns jsonb'),
    );
    expect(schemaContract, contains('no country-code'));
    expect(schemaContract, contains('inference is performed'));
  });

  test('booking request rows retain member-only RLS and explicit grants', () {
    final policies = _source('supabase/rls_policies.sql');
    final grants = _source(
      'supabase/migrations/'
      '20260725212223_harden_data_api_table_grants.sql',
    );

    expect(
      policies,
      contains(
        'alter table if exists booking_requests enable row level security',
      ),
    );
    expect(policies, contains('on booking_requests for all'));
    expect(policies, contains('to authenticated'));
    expect(
      policies,
      contains('using (app_private.is_workspace_member(workspace_id))'),
    );
    expect(
      policies,
      contains(
        'drop policy if exists "public can create booking requests" '
        'on booking_requests',
      ),
    );
    expect(
      grants,
      contains(
        'revoke all privileges on all tables in schema public from anon',
      ),
    );
    expect(grants, contains('public.booking_requests'));
    expect(grants, contains('to authenticated'));
  });

  test('Edge handler delegates atomic writes and never inserts directly', () {
    final edgeHandler = File(
      'supabase/functions/create-booking-request/index.ts',
    ).readAsStringSync();
    final profileHandler = File(
      'supabase/functions/get-public-profile/index.ts',
    ).readAsStringSync();

    expect(edgeHandler, contains('"create_public_booking_request_v2"'));
    expect(edgeHandler, contains('p_request_token: requestToken'));
    expect(edgeHandler, contains('p_email: email'));
    expect(edgeHandler, contains('bookingRequestOutcomeResponse(outcome)'));
    for (final handler in [edgeHandler, profileHandler]) {
      expect(handler, contains('"is_public_workspace_active"'));
      expect(handler, contains('p_workspace_id: profile.workspace_id'));
      expect(handler, contains('if (member !== true)'));
    }
    _expectBefore(
      edgeHandler,
      'if (member !== true)',
      '"create_public_booking_request_v2"',
    );
    _expectBefore(
      profileHandler,
      'if (member !== true)',
      '.from("workspaces")',
    );
    expect(edgeHandler, isNot(contains('.from("booking_requests").insert')));
    expect(edgeHandler, isNot(contains('.from("notifications").insert')));
  });

  test('availability verifies an active public owner before reading slots', () {
    final handler = File(
      'supabase/functions/get-public-booking-availability/index.ts',
    ).readAsStringSync();
    expect(handler, contains('"is_public_profile_active"'));
    expect(handler, contains('p_handle: input.handle'));
    _expectBefore(
      handler,
      'if (active !== true)',
      '"get_public_booking_slot_suggestions_v4"',
    );
  });

  test('Flutter retry and triage paths preserve lifecycle guards', () {
    final publicForm = File(
      'lib/features/public_profile/public_profile_screen.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/shared/repositories/profile_repository.dart',
    ).readAsStringSync();

    expect(
      publicForm,
      contains('final String _requestToken = createPublicRequestToken();'),
    );
    expect(publicForm, contains('requestToken: _requestToken'));
    expect(repository, contains(".eq('workspace_id', workspaceId)"));
    expect(repository, contains(".inFilter('status', sourceStatuses)"));
    expect(repository, contains(".select('id')"));
    expect(repository, contains('.maybeSingle()'));
    expect(repository, contains('if (updated == null)'));
  });

  test('booking repository reads page full datasets deterministically', () {
    final appointments = File(
      'lib/shared/repositories/appointments_repository.dart',
    ).readAsStringSync();
    final profiles = File(
      'lib/shared/repositories/profile_repository.dart',
    ).readAsStringSync();

    expect(
      RegExp(
        'fetchAllRepositoryPages<Map<String, dynamic>>',
      ).allMatches(appointments),
      // Four current-schema reads plus four legacy projections used only when
      // appointment_items has not reached the backend yet.
      hasLength(8),
    );
    expect(appointments, contains(".order('start_time', ascending: true)"));
    expect(appointments, contains(".order('id', ascending: true)"));
    expect(appointments, contains('.range(from, to)'));
    expect(appointments, contains('.limit(limit)'));
    expect(profiles, contains('fetchAllRepositoryPages<Map<String, dynamic>>'));
    expect(profiles, contains(".order('created_at', ascending: false)"));
    expect(profiles, contains(".order('id', ascending: true)"));
    expect(profiles, contains('.range(from, to)'));
  });
}
