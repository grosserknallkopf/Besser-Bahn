import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Forwards app lifecycle changes to a callback without the host having to
/// mix in [WidgetsBindingObserver] itself.
class _LifecycleProxy with WidgetsBindingObserver {
  final void Function(AppLifecycleState) onChange;
  _LifecycleProxy(this.onChange);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChange(state);
}

/// Drop-in silent auto-refresh for a screen's [ConsumerState].
///
/// While the screen is mounted (and the app is in the foreground) it calls
/// [onAutoRefresh] every [autoRefreshInterval]. It also fires once on mount and
/// again whenever the app returns to the foreground — so coming back to the
/// screen shows fresh data without a manual pull.
///
/// The implementation of [onAutoRefresh] is expected to fetch *silently*: no
/// loading spinner, and on failure (offline etc.) keep the previously shown
/// data instead of wiping it. The timer is paused while the app is backgrounded
/// so a hidden process never fetches.
///
/// Because the tab shell builds only the active screen ([ShellRoute] with a
/// single `child`, no IndexedStack), the host State is disposed when the user
/// leaves the tab — which cancels the timer automatically.
mixin AutoRefreshMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Timer? _timer;
  _LifecycleProxy? _lifecycle;

  /// How often to refresh while the screen is visible. 60s suits live delay
  /// data without hammering the upstream API.
  Duration get autoRefreshInterval => const Duration(seconds: 60);

  /// Whether to fire one refresh immediately on mount.
  bool get refreshOnStart => true;

  /// Fetch fresh data silently. Must keep old data on error.
  Future<void> onAutoRefresh();

  @override
  void initState() {
    super.initState();
    _lifecycle = _LifecycleProxy(_onLifecycle);
    WidgetsBinding.instance.addObserver(_lifecycle!);
    if (refreshOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) onAutoRefresh();
      });
    }
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(autoRefreshInterval, (_) {
      if (mounted) onAutoRefresh();
    });
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) onAutoRefresh();
      _startTimer(); // restart cadence from the moment of return
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_lifecycle != null) {
      WidgetsBinding.instance.removeObserver(_lifecycle!);
    }
    super.dispose();
  }
}
