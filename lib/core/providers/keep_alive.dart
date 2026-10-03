import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Default time an `autoDispose` entry survives after its last listener left.
const keepAliveTtl = Duration(minutes: 10);

/// Keeps an `autoDispose` provider entry alive for [ttl] after its last
/// listener unsubscribes, instead of disposing immediately: quick tab
/// switches or month swipes back and forth hit the cache, while entries no
/// longer looked at are still evicted eventually.
void keepAliveFor(Ref ref, [Duration ttl = keepAliveTtl]) {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onDispose(() => timer?.cancel());
  ref.onCancel(() => timer = Timer(ttl, link.close));
  ref.onResume(() => timer?.cancel());
}
