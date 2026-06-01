import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform, Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/db_ticket.dart';
import '../../models/journey.dart';
import '../../providers/account_provider.dart';
import '../../providers/service_providers.dart';
import '../connection_search/connection_detail_screen.dart';

/// Entry point for a booked ticket from the Reisen tab. Loads the ticket,
/// parses its `verbindung` into a [Journey], then defers to
/// [ConnectionDetailScreen] — so a bought ticket reads the *same* Reiseplan
/// view as a search result. From there, the AppBar's Ticket icon opens
/// [TicketViewScreen] (the official Handyticket WebView).
class TicketDetailScreen extends ConsumerWidget {
  final String auftragsnummer;
  final String kundenwunschId;

  const TicketDetailScreen({
    super.key,
    required this.auftragsnummer,
    required this.kundenwunschId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '$auftragsnummer/$kundenwunschId';
    final ticket = ref.watch(ticketProvider(key));
    return ticket.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Reiseplan')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Reiseplan')),
        body: Center(
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
      ),
      data: (t) {
        Journey? j;
        final v = t.verbindungJson;
        if (v != null) {
          try {
            j = ref.read(vendoServiceProvider).parseConnection(v);
          } catch (_) {/* fall through */}
        }
        if (j == null) {
          // No usable Reiseplan in this ticket — go straight to the official
          // Handyticket view so the user can at least show it.
          return TicketViewScreen(
            ticketRef: (
              auftragsnummer: auftragsnummer,
              kundenwunschId: kundenwunschId,
            ),
          );
        }
        return ConnectionDetailScreen(
          journey: j,
          ticketRef: (
            auftragsnummer: auftragsnummer,
            kundenwunschId: kundenwunschId,
          ),
        );
      },
    );
  }
}

// ===========================================================================
// TicketViewScreen — the official Handyticket WebView, opened from the
// AppBar "Ticket" action on a booked Reiseplan.
// ===========================================================================

class TicketViewScreen extends ConsumerWidget {
  final TicketRef ticketRef;
  const TicketViewScreen({super.key, required this.ticketRef});

  static bool get _webViewSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '${ticketRef.auftragsnummer}/${ticketRef.kundenwunschId}';
    final ticket = ref.watch(ticketProvider(key));
    final reservations = ticket.asData?.value.reservierungen ?? const [];

    return Scaffold(
      // White all the way through, like the official app.
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('Ticket'),
        actions: [
          if (reservations.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.event_seat_outlined),
              tooltip: 'Reservierte Sitzplätze',
              onPressed: () => _showReservations(context, reservations),
            ),
        ],
      ),
      body: ticket.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Ticket konnte nicht geladen werden.\n$e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (t) => _body(context, t),
      ),
    );
  }

  Widget _body(BuildContext context, DbTicket t) {
    return Column(
      children: [
        _TicketMarquee(ticket: t),
        Expanded(
          child: Padding(
            // The half-cm white border around the ticket itself, matching the
            // official app's framing.
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: Colors.white,
                child: (_webViewSupported && t.ticketHtml != null)
                    ? _OfficialTicketWebView(html: t.ticketHtml!)
                    : _FallbackTicket(ticket: t),
              ),
            ),
          ),
        ),
      ],
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
            : const Color(0xFF0E7A2C);
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
    const style = TextStyle(
        color: fg, fontSize: 13, fontWeight: FontWeight.w600);

    return Container(
      color: bg,
      height: 32,
      child: ClipRect(
        child: LayoutBuilder(builder: (ctx, c) {
          final tp = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          final segmentWidth = tp.width + 80;
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (ctx, _) {
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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.white)
      ..loadHtmlString(widget.html);
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(
        controller: _controller,
        // Claim vertical drag so the WebView's internal scroll always wins —
        // without this any ancestor scrollable could steal the gesture and the
        // ticket appears stuck (the bug the user reported).
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<VerticalDragGestureRecognizer>(
              () => VerticalDragGestureRecognizer()),
        },
      );
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
                _row(theme, Icons.local_offer_outlined, 'Tarif',
                    t.angebotsname!),
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
