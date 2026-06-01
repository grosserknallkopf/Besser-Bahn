import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/extensions.dart';
import '../../models/db_ticket.dart';
import '../../models/journey.dart';
import '../../providers/account_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/delay_badge.dart';
import '../../widgets/product_badge.dart';

/// A single booked ticket. Two tabs (like the official DB Navigator):
///
/// - **Reiseplan** — the route/legs of this booked connection, parsed from the
///   ticket's `verbindung` via [VendoService.parseConnection] so the same UI
///   that renders search results renders the bought trip too.
/// - **Ticket** — DB's own self-contained Handyticket HTML rendered offline in
///   a WebView (Aztec barcode, Sichtprüfmerkmal, all fields and conditions),
///   so the in-app ticket is inspection-valid. A moving marquee above the
///   ticket shows status/route/Auftrag — the anti-fraud strip the official
///   app draws over the ticket.
///
/// On platforms without a WebView (desktop/web) the Ticket tab falls back to
/// the native card (barcode + parsed facts).
class TicketDetailScreen extends ConsumerWidget {
  final String auftragsnummer;
  final String kundenwunschId;

  const TicketDetailScreen({
    super.key,
    required this.auftragsnummer,
    required this.kundenwunschId,
  });

  static bool get _webViewSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '$auftragsnummer/$kundenwunschId';
    final ticket = ref.watch(ticketProvider(key));
    final reservations = ticket.asData?.value.reservierungen ?? const [];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ticket'),
          actions: [
            if (reservations.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.event_seat_outlined),
                tooltip: 'Reservierte Sitzplätze',
                onPressed: () => _showReservations(context, reservations),
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Reiseplan', icon: Icon(Icons.alt_route)),
              Tab(text: 'Ticket', icon: Icon(Icons.qr_code_2)),
            ],
          ),
        ),
        body: ticket.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 12),
                  Text('Ticket konnte nicht geladen werden.\n$e',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(ticketProvider(key)),
                    child: const Text('Erneut versuchen'),
                  ),
                ],
              ),
            ),
          ),
          data: (t) => TabBarView(
            children: [
              _ReiseplanTab(ticket: t),
              _TicketTab(ticket: t),
            ],
          ),
        ),
      ),
    );
  }

  void _showReservations(
      BuildContext context, List<DbReservierung> reservations) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Deine Reservierung', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                for (final r in reservations)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.train,
                                  size: 20, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(r.trainLabel,
                                  style: theme.textTheme.titleMedium),
                            ],
                          ),
                          if (r.vonName != null || r.nachName != null) ...[
                            const SizedBox(height: 4),
                            Text('${r.vonName ?? ''} → ${r.nachName ?? ''}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.outline)),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.event_seat,
                                  size: 20, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                    r.plaetze.isEmpty
                                        ? '${r.anzahlPlaetze} Platz reserviert'
                                        : r.seatLabel,
                                    style: theme.textTheme.bodyLarge),
                              ),
                            ],
                          ),
                          if (r.firstWagon != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Wagen ${r.firstWagon} — am Bahnsteig findest du '
                              'die Wagenreihung in der Bahnhofskarte.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ===========================================================================
// Reiseplan tab — the booked connection's route/legs.
// ===========================================================================

class _ReiseplanTab extends ConsumerWidget {
  final DbTicket ticket;
  const _ReiseplanTab({required this.ticket});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Journey? journey;
    final v = ticket.verbindungJson;
    if (v != null) {
      try {
        journey = ref.read(vendoServiceProvider).parseConnection(v);
      } catch (_) {/* fall through to summary-only */}
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Header summary (works even when verbindung can't be parsed).
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ticket.vonName ?? journey?.origin?.name ?? '—'}  →  '
                  '${ticket.nachName ?? journey?.destination?.name ?? '—'}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (ticket.gueltigAb != null)
                      DateFormat('EEEE, d. MMMM yyyy', 'de')
                          .format(ticket.gueltigAb!),
                    if (journey?.durationString.isNotEmpty == true)
                      'Dauer ${journey!.durationString}',
                    if (journey != null)
                      journey.transfers <= 0
                          ? 'direkt'
                          : '${journey.transfers} Umstieg${journey.transfers == 1 ? '' : 'e'}',
                    if (ticket.angebotsname != null) ticket.angebotsname!,
                    ticket.firstClass ? '1. Klasse' : '2. Klasse',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (journey == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Kein Reiseplan in diesem Ticket.',
                style: TextStyle(color: theme.colorScheme.outline),
              ),
            ),
          )
        else
          ...journey.legs
              .where((l) => !l.isWalking)
              .map((l) => _legCard(context, l)),
      ],
    );
  }

  Widget _legCard(BuildContext context, JourneyLeg leg) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (leg.line != null)
                  ProductBadge(label: leg.line!.name),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    leg.direction != null
                        ? 'Richtung ${leg.direction}'
                        : (leg.line?.name ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _stopRow(context, leg.origin.name,
                planned: leg.plannedDeparture,
                actual: leg.departure,
                delay: leg.departureDelay,
                gleis: leg.departurePlatform),
            const SizedBox(height: 6),
            _stopRow(context, leg.destination.name,
                planned: leg.plannedArrival,
                actual: leg.arrival,
                delay: leg.arrivalDelay,
                gleis: leg.arrivalPlatform),
          ],
        ),
      ),
    );
  }

  Widget _stopRow(BuildContext context, String name,
      {DateTime? planned,
      DateTime? actual,
      int? delay,
      String? gleis}) {
    final theme = Theme.of(context);
    final time = (actual ?? planned)?.hhmm ?? '—:—';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(time,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              if (gleis != null)
                Text('Gleis $gleis',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
        if (delay != null && delay > 60)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: DelayBadge(delaySeconds: delay),
          ),
      ],
    );
  }
}

// ===========================================================================
// Ticket tab — DB's official Handyticket HTML in a WebView + anti-fraud
// marquee strip; native fallback off WebView platforms.
// ===========================================================================

class _TicketTab extends StatelessWidget {
  final DbTicket ticket;
  const _TicketTab({required this.ticket});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          _TicketMarquee(ticket: ticket),
          Expanded(
            child: Padding(
              // Half-cm-ish border around the ticket like the official app
              // (so the rounded-card hint reads clearly against the bg).
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ColoredBox(
                  color: Colors.white,
                  child: (TicketDetailScreen._webViewSupported &&
                          ticket.ticketHtml != null)
                      ? _OfficialTicketWebView(html: ticket.ticketHtml!)
                      : _FallbackTicket(ticket: ticket),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Anti-fraud marquee strip ----------------------------------------------

/// Right-to-left scrolling status strip above the ticket — exactly like the
/// official app's anti-fraud ribbon: text actually moves, so a static
/// screenshot can't replicate it at inspection.
class _TicketMarquee extends StatefulWidget {
  final DbTicket ticket;
  const _TicketMarquee({required this.ticket});

  @override
  State<_TicketMarquee> createState() => _TicketMarqueeState();
}

class _TicketMarqueeState extends State<_TicketMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    final now = DateTime.now();
    final expired = ticket.gueltigBis != null && now.isAfter(ticket.gueltigBis!);
    final stornoed = ticket.status.toUpperCase() == 'STORNIERT';

    final bg = stornoed
        ? const Color(0xFFB00020)
        : expired
            ? const Color(0xFF616161)
            : const Color(0xFF0E7A2C); // DB-ish green
    const fg = Colors.white;

    final statusText = stornoed
        ? 'Ticket storniert'
        : expired
            ? 'Ticket nicht mehr gültig'
            : 'Ticket gültig';

    final dateText = ticket.gueltigAb != null
        ? DateFormat('dd.MM.yyyy').format(ticket.gueltigAb!)
        : '';
    final parts = <String>[
      if (dateText.isNotEmpty) dateText,
      'Auftrag ${ticket.auftragsnummer}',
      if (ticket.angebotsname != null) ticket.angebotsname!,
      ticket.firstClass ? '1. Klasse' : '2. Klasse',
      if (ticket.vonName != null || ticket.nachName != null)
        '${ticket.vonName ?? '—'} → ${ticket.nachName ?? '—'}',
      statusText,
    ];
    final text = parts.join('   ·   ');
    final style = const TextStyle(
        color: fg, fontSize: 13, fontWeight: FontWeight.w600);

    return Container(
      color: bg,
      height: 32,
      child: ClipRect(
        child: LayoutBuilder(builder: (ctx, c) {
          // Measure the text once per build (cheap).
          final tp = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          final segmentWidth = tp.width + 80; // text + gap before repeat
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (ctx, _) {
              // Slide from 0 to -segmentWidth, then loop seamlessly.
              final dx = -_ctrl.value * segmentWidth;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: dx,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      children: [
                        SizedBox(
                            width: segmentWidth,
                            child: Center(child: Text(text, style: style))),
                        SizedBox(
                            width: segmentWidth,
                            child: Center(child: Text(text, style: style))),
                        // Extra copy so the right edge is filled even when
                        // the viewport is wider than one segment.
                        SizedBox(
                            width: segmentWidth,
                            child: Center(child: Text(text, style: style))),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        }),
      ),
    );
  }
}

// --- WebView ----------------------------------------------------------------

class _OfficialTicketWebView extends StatefulWidget {
  final String html;
  const _OfficialTicketWebView({required this.html});

  @override
  State<_OfficialTicketWebView> createState() => _OfficialTicketWebViewState();
}

class _OfficialTicketWebViewState extends State<_OfficialTicketWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    // The ticket carries an empty <script>; no JS is needed to render it, so
    // keep JS disabled (defence in depth for arbitrary embedded content).
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.white)
      ..loadHtmlString(widget.html);
  }

  @override
  Widget build(BuildContext context) =>
      WebViewWidget(controller: _controller);
}

// --- Native fallback (desktop/web) -----------------------------------------

class _FallbackTicket extends StatelessWidget {
  final DbTicket ticket;
  const _FallbackTicket({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (t.barcode != null)
                  Image.memory(t.barcode!,
                      width: 220,
                      height: 220,
                      fit: BoxFit.contain,
                      gaplessPlayback: true)
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text('Kein Barcode in diesem Ticket.',
                        style: TextStyle(color: Colors.black54)),
                  ),
                const SizedBox(height: 8),
                Text('Auftrag ${t.auftragsnummer}',
                    style: const TextStyle(color: Colors.black87)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              if (t.angebotsname != null)
                _row(theme, Icons.local_offer_outlined, 'Tarif', t.angebotsname!),
              _row(theme, Icons.event_seat_outlined, 'Klasse',
                  t.firstClass ? '1. Klasse' : '2. Klasse'),
              _row(theme, Icons.group_outlined, 'Reisende', t.reisendeText),
              if (t.gueltigAb != null)
                _row(theme, Icons.schedule, 'Gültig ab',
                    DateFormat('dd.MM.yyyy, HH:mm').format(t.gueltigAb!)),
              if (t.gueltigBis != null)
                _row(theme, Icons.event_busy_outlined, 'Gültig bis',
                    DateFormat('dd.MM.yyyy, HH:mm').format(t.gueltigBis!)),
              _row(theme, Icons.verified_outlined, 'Status', t.status),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(ThemeData theme, IconData icon, String label, String value) =>
      ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(label, style: theme.textTheme.bodySmall),
        subtitle: Text(value, style: theme.textTheme.bodyLarge),
      );
}
