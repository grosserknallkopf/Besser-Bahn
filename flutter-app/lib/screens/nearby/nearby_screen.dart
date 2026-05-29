import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/nearby_tab_provider.dart';
import '../../widgets/app_menu_button.dart';
import '../departure_board/departure_board_screen.dart';
import '../station_map/station_map_screen.dart';
import '../train_lookup/train_lookup_screen.dart';

/// Combines the former Zug / Abfahrten / Karte tabs into a single screen with
/// an internal, swipeable tab bar — fewer bottom-bar destinations, one place
/// for everything about a station.
class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: ref.read(nearbyTabProvider),
    );
    // Mirror manual swipes/taps back into the provider so external jumps stay
    // in sync. Only write once the swipe settles.
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging &&
          _tabs.index != ref.read(nearbyTabProvider)) {
        ref.read(nearbyTabProvider.notifier).select(_tabs.index);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // External jumps (e.g. tapping a departure → open its train) drive the tab.
    ref.listen<int>(nearbyTabProvider, (_, next) {
      if (_tabs.index != next) _tabs.animateTo(next);
    });

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Bahnhof'),
        actions: const [AppMenuButton()],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.train), text: 'Zug'),
            Tab(icon: Icon(Icons.departure_board), text: 'Abfahrten'),
            Tab(icon: Icon(Icons.map), text: 'Karte'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          TrainLookupScreen(embedded: true),
          DepartureBoardScreen(embedded: true),
          StationMapScreen(embedded: true),
        ],
      ),
    );
  }
}
