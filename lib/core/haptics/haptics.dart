import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../providers/app_providers.dart';

/// Central gate for all haptic feedback.
///
/// **Every vibration in the app MUST go through this service** so the user's
/// "Haptics" setting (profile.hapticsEnabled) is honored. When the setting is
/// off, all methods are no-ops. Do not call [HapticFeedback] directly anywhere
/// else — see CLAUDE.md.
///
/// Feedback is driven by Flutter's [HapticFeedback], which routes to the OS
/// haptic actuator. This is deliberately chosen over the `vibration` package's
/// motor duration/amplitude control: the actuator fires immediately (no motor
/// ramp-up) and feels crisp, exactly like the native keyboard. The trade-off is
/// that intensity is fixed by the OEM and not adjustable — see the DB column
/// `profile.hapticsStrength` (still persisted, currently unused) for the
/// abandoned strength setting, kept in case a future API makes it useful.
class HapticsService {
  HapticsService(this._ref);

  final Ref _ref;

  ProfileData? get _profile => _ref.read(profileStreamProvider).asData?.value;

  /// Latest persisted setting; defaults to on until the profile stream loads.
  bool get _enabled => _profile?.hapticsEnabled ?? true;

  /// Runs [action] only when haptics are enabled.
  Future<void> _gate(Future<void> Function() action) async {
    if (!_enabled) return;
    await action();
  }

  /// Light, crisp tick — key taps, item selection.
  Future<void> selection() => _gate(HapticFeedback.selectionClick);

  Future<void> light() => _gate(HapticFeedback.lightImpact);

  Future<void> medium() => _gate(HapticFeedback.mediumImpact);

  Future<void> heavy() => _gate(HapticFeedback.heavyImpact);

  /// Strongest alert. Uses [HapticFeedback.heavyImpact] rather than
  /// [HapticFeedback.vibrate] so it stays on the immediate actuator path.
  Future<void> vibrate() => _gate(HapticFeedback.heavyImpact);
}

/// Access point for haptics. Read it (`ref.read(hapticsProvider).light()`)
/// wherever feedback is needed instead of touching [HapticFeedback] directly.
final hapticsProvider = Provider<HapticsService>((ref) => HapticsService(ref));
