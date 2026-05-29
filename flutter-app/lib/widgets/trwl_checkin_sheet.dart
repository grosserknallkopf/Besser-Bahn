import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/traewelling_models.dart';
import '../models/trip.dart';
import '../providers/service_providers.dart';
import '../providers/settings_provider.dart';
import '../providers/traewelling_provider.dart';
import '../services/traewelling_service.dart';
import '../theme/app_colors.dart';
import 'traewelling_logo.dart';

/// Entry point for checking the *current* train into Träwelling — used by the
/// in-train check-in button so there's no separate manual station search.
///
/// Behaviour follows the user's settings:
/// - not logged in → a hint that links to the Träwelling connect screen;
/// - `trwlAutoCheckin` on → checks in immediately (origin → destination, at the
///   configured default visibility), no sheet;
/// - off → opens a confirm sheet to pick the destination + visibility first.
Future<void> startTrwlCheckin(
    BuildContext context, WidgetRef ref, Trip trip) async {
  final auth = ref.read(traewellingAuthProvider);
  if (!auth.isLoggedIn) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: const Text('Mit Träwelling verbinden, um einzuchecken.'),
      action: SnackBarAction(
        label: 'Anmelden',
        onPressed: () => context.push('/trawelling'),
      ),
    ));
    return;
  }

  final settings = ref.read(settingsProvider);
  if (settings.trwlAutoCheckin) {
    final stops = trip.stopovers;
    final boarding = stops.isNotEmpty ? stops.first : null;
    final alighting = stops.length > 1 ? stops.last : null;
    final boardName = boarding?.stop.name ?? trip.origin.name;
    final alightName = alighting?.stop.name ?? trip.destination.name;
    final boardDep = boarding?.departure ??
        boarding?.plannedDeparture ??
        DateTime.now();
    await runTrwlCheckin(
      context,
      ref,
      lineName: trip.line.displayName,
      boardingName: boardName,
      boardingDeparture: boardDep,
      alightingName: alightName,
      visibility: settings.trwlVisibility,
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CheckinSheet(trip: trip),
  );
}

/// Runs the actual check-in and reports the outcome via SnackBars. Handles the
/// 409 collision by offering a "trotzdem einchecken" (force) retry. Returns
/// true on success.
Future<bool> runTrwlCheckin(
  BuildContext context,
  WidgetRef ref, {
  required String lineName,
  required String boardingName,
  required DateTime boardingDeparture,
  required String alightingName,
  required int visibility,
  String body = '',
  bool force = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(traewellingServiceProvider);
  try {
    await service.checkinFromTrip(
      lineName: lineName,
      boardingName: boardingName,
      boardingDeparture: boardingDeparture,
      alightingName: alightingName,
      visibility: visibility,
      body: body,
      force: force,
    );
    ref.invalidate(trwlDashboardProvider);
    await ref.read(traewellingAuthProvider.notifier).refreshUser();
    messenger.showSnackBar(
      const SnackBar(content: Text('Eingecheckt! 🎉')),
    );
    return true;
  } on CheckinCollisionException {
    if (!context.mounted) return false;
    final retry = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Überschneidung'),
        content: const Text(
            'Du bist bereits für eine überlappende Fahrt eingecheckt. '
            'Trotzdem einchecken?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Trotzdem')),
        ],
      ),
    );
    if (retry == true && context.mounted) {
      return runTrwlCheckin(
        context,
        ref,
        lineName: lineName,
        boardingName: boardingName,
        boardingDeparture: boardingDeparture,
        alightingName: alightingName,
        visibility: visibility,
        body: body,
        force: true,
      );
    }
    return false;
  } on TraewellingException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text('Check-in fehlgeschlagen: $e')));
    return false;
  }
}

class _CheckinSheet extends ConsumerStatefulWidget {
  final Trip trip;
  const _CheckinSheet({required this.trip});

  @override
  ConsumerState<_CheckinSheet> createState() => _CheckinSheetState();
}

class _CheckinSheetState extends ConsumerState<_CheckinSheet> {
  final _timeFmt = DateFormat('HH:mm');
  final _bodyCtrl = TextEditingController();
  late Stopover _destination;
  late TrwlVisibility _visibility;
  bool _submitting = false;

  /// Boarding stop (the run's first stop) and the valid destinations after it.
  Stopover get _boarding => widget.trip.stopovers.first;
  List<Stopover> get _destOptions =>
      widget.trip.stopovers.length > 1 ? widget.trip.stopovers.sublist(1) : [];

  @override
  void initState() {
    super.initState();
    _destination = _destOptions.isNotEmpty
        ? _destOptions.last
        : widget.trip.stopovers.first;
    final v = ref.read(settingsProvider).trwlVisibility;
    _visibility = TrwlVisibility.values.firstWhere((e) => e.value == v,
        orElse: () => TrwlVisibility.public);
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final boardDep =
        _boarding.departure ?? _boarding.plannedDeparture ?? DateTime.now();
    final ok = await runTrwlCheckin(
      context,
      ref,
      lineName: widget.trip.line.displayName,
      boardingName: _boarding.stop.name,
      boardingDeparture: boardDep,
      alightingName: _destination.stop.name,
      visibility: _visibility.value,
      body: _bodyCtrl.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = widget.trip;
    final boardDep = _boarding.departure ?? _boarding.plannedDeparture;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TraewellingLogo(size: 28),
              const SizedBox(width: 10),
              Text('In Träwelling einchecken',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Text('${trip.line.displayName} · ab ${_boarding.stop.name}'
              '${boardDep != null ? ' ${_timeFmt.format(boardDep.toLocal())}' : ''}',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          DropdownButtonFormField<Stopover>(
            initialValue: _destination,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Ausstieg',
              border: OutlineInputBorder(),
            ),
            items: _destOptions
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(
                        '${s.stop.name}'
                        '${(s.arrival ?? s.plannedArrival) != null ? '  ${_timeFmt.format((s.arrival ?? s.plannedArrival)!.toLocal())}' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _destination = v ?? _destination),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TrwlVisibility>(
            initialValue: _visibility,
            decoration: const InputDecoration(
              labelText: 'Sichtbarkeit',
              border: OutlineInputBorder(),
            ),
            items: TrwlVisibility.values
                .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
                .toList(),
            onChanged: (v) => setState(() => _visibility = v ?? _visibility),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            maxLength: 280,
            decoration: const InputDecoration(
              labelText: 'Statustext (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dbRed,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(_submitting ? 'Checke ein…' : 'Einchecken'),
            ),
          ),
        ],
      ),
    );
  }
}
