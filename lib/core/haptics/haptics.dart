import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';

import '../../data/database.dart';
import '../providers/app_providers.dart';

/// Central gate for all haptic feedback.
///
/// **Every vibration in the app MUST go through this service** so the user's
/// "Haptics" setting (profile.hapticsEnabled) is honored. When the setting is
/// off, all methods are no-ops. Do not call [HapticFeedback] or [Vibration]
/// directly anywhere else — see CLAUDE.md.
///
/// Flutter's [HapticFeedback] impacts are weak and barely distinguishable on
/// most Android devices, so we drive the OS vibrator directly via the
/// `vibration` package with explicit duration + amplitude. Each semantic method
/// has a base rung; the user's strength setting (profile.hapticsStrength:
/// 0 soft, 1 medium, 2 strong) scales both duration and amplitude so the levels
/// feel clearly different. Devices without a custom vibrator (or amplitude
/// control) degrade gracefully to duration-only / [HapticFeedback].
class HapticsService {
  HapticsService(this._ref);

  final Ref _ref;

  /// Base vibration length per semantic rung (ms), before the strength scale.
  static const _baseDurationMs = <int>[18, 30, 55, 90, 180];

  /// Per-strength multiplier applied to the base duration.
  static const _durationScale = <double>[0.7, 1.0, 1.8];

  /// Per-strength amplitude (1–255) on devices with amplitude control.
  static const _amplitude = <int>[130, 200, 255];

  /// Fallback ladder for devices without a controllable vibrator.
  static const _ladder = <Future<void> Function()>[
    HapticFeedback.selectionClick,
    HapticFeedback.lightImpact,
    HapticFeedback.mediumImpact,
    HapticFeedback.heavyImpact,
    HapticFeedback.vibrate,
  ];

  bool? _hasVibrator;
  bool? _hasAmplitude;

  ProfileData? get _profile => _ref.read(profileStreamProvider).asData?.value;

  /// Latest persisted setting; defaults to on until the profile stream loads.
  bool get _enabled => _profile?.hapticsEnabled ?? true;

  /// 0 soft, 1 medium (default), 2 strong.
  int get _strength => (_profile?.hapticsStrength ?? 1).clamp(0, 2);

  /// Detects vibrator capabilities once and caches them.
  Future<void> _ensureCaps() async {
    if (_hasVibrator != null) return;
    try {
      _hasVibrator = await Vibration.hasVibrator();
      _hasAmplitude = _hasVibrator! && await Vibration.hasAmplitudeControl();
    } catch (_) {
      _hasVibrator = false;
      _hasAmplitude = false;
    }
  }

  /// Fires semantic rung [base] (0..4), scaled by the strength setting.
  Future<void> _fire(int base) async {
    if (!_enabled) return;
    final strength = _strength;
    await _ensureCaps();
    if (_hasVibrator == true) {
      final duration = (_baseDurationMs[base] * _durationScale[strength]).round();
      await Vibration.vibrate(
        duration: duration,
        amplitude: _hasAmplitude == true ? _amplitude[strength] : -1,
      );
      return;
    }
    // No controllable vibrator: fall back to the platform impact ladder.
    final index = (base + strength).clamp(0, _ladder.length - 1);
    await _ladder[index]();
  }

  Future<void> selection() => _fire(0);

  Future<void> light() => _fire(1);

  Future<void> medium() => _fire(2);

  Future<void> heavy() => _fire(3);

  Future<void> vibrate() => _fire(4);
}

/// Access point for haptics. Read it (`ref.read(hapticsProvider).light()`)
/// wherever feedback is needed instead of touching [HapticFeedback] directly.
final hapticsProvider = Provider<HapticsService>((ref) => HapticsService(ref));
