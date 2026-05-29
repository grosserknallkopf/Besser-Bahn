import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/station.dart';
import 'service_providers.dart';

/// Debounced station search provider
class StationSearchNotifier extends AutoDisposeAsyncNotifier<List<Station>> {
  Timer? _debounce;

  @override
  Future<List<Station>> build() async => [];

  void search(String query) {
    _debounce?.cancel();
    if (query.length < 2) {
      state = const AsyncData([]);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      state = const AsyncLoading();
      try {
        final results = await ref.read(hafasServiceProvider).searchStations(query);
        state = AsyncData(results);
      } catch (e) {
        state = AsyncError(e, StackTrace.current);
      }
    });
  }

  void clear() {
    _debounce?.cancel();
    state = const AsyncData([]);
  }
}

final stationSearchProvider =
    AsyncNotifierProvider.autoDispose<StationSearchNotifier, List<Station>>(
        StationSearchNotifier.new);
