import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/public_booking_availability.dart';
import '../../shared/repositories/profile_repository.dart';

typedef PublicBookingAvailabilityQuery = ({
  String handle,
  String serviceId,
  String serviceIdsKey,
  String addOnIdsKey,
});

final publicBookingAvailabilityProvider = FutureProvider.autoDispose
    .family<PublicBookingAvailability, PublicBookingAvailabilityQuery>((
      ref,
      query,
    ) {
      return ref
          .watch(profileRepositoryProvider)
          .getPublicBookingAvailability(
            handle: query.handle,
            serviceId: query.serviceId,
            serviceIds: query.serviceIdsKey.split(','),
            addOnIds: query.addOnIdsKey.isEmpty
                ? const []
                : query.addOnIdsKey.split(','),
          );
    });
