import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

/// Central gate for all haptic feedback.
///
/// **Every vibration in the app MUST go through this service** so the user's
/// "Haptics" setting (profile.hapticsEnabled) is honored. When the setting is
/// off, all methods are no-ops. Do not call [HapticFeedback] directly anywhere
/// else — see CLAUDE.md.
class HapticsService {
  HapticsService(this._ref);

  final Ref _ref;

  /// Latest persisted setting; defaults to on until the profile stream loads.
  bool get _enabled =>
      _ref.read(profileStreamProvider).asData?.value.hapticsEnabled ?? true;

  Future<void> light() async {
    if (_enabled) await HapticFeedback.lightImpact();
  }

  Future<void> medium() async {
    if (_enabled) await HapticFeedback.mediumImpact();
  }

  Future<void> heavy() async {
    if (_enabled) await HapticFeedback.heavyImpact();
  }

  Future<void> selection() async {
    if (_enabled) await HapticFeedback.selectionClick();
  }

  Future<void> vibrate() async {
    if (_enabled) await HapticFeedback.vibrate();
  }
}

/// Access point for haptics. Read it (`ref.read(hapticsProvider).light()`)
/// wherever feedback is needed instead of touching [HapticFeedback] directly.
final hapticsProvider = Provider<HapticsService>((ref) => HapticsService(ref));
