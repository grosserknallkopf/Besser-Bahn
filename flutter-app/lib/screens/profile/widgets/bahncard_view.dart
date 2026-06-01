import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../models/db_account.dart';
import '../../../providers/account_provider.dart';

/// True when the platform has a [WebViewWidget] implementation. Linux /
/// Windows / web don't — fall back to a native card there.
bool get _webViewSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Renders one BahnCard. The official `bildSicht` is an HTML document (a
/// `<div>` with the card art as `background-image` and CSS-positioned text
/// for the holder name, BC number, and validity dates) — rendered inside a
/// WebView so it matches DB Navigator pixel-for-pixel. Falls back to a
/// styled card on platforms without a WebView (or when the API doesn't
/// supply HTML).
class BahnCardView extends StatelessWidget {
  final DbBahnCard card;
  const BahnCardView({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    final hasControl = card.kontrollSichtHtml != null;
    final canRenderHtml = _webViewSupported && card.bildSichtHtml != null;
    final child = canRenderHtml
        ? ClipRRect(
            borderRadius: radius,
            child: AspectRatio(
              // DB's bildSicht is laid out at ~1.538:1 (the CSS uses
              // padding-top:65% of width = ~1.538 aspect). Match it so no
              // letterboxing appears around the card.
              aspectRatio: 1 / 0.65,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The WebView itself doesn't receive gestures — the parent
                  // InkWell owns the tap-to-open-Kontrollansicht.
                  IgnorePointer(
                    child: _BahnCardHtml(html: card.bildSichtHtml!),
                  ),
                  if (hasControl)
                    const Positioned(
                      right: 10,
                      bottom: 10,
                      child: _ControlChip(),
                    ),
                ],
              ),
            ),
          )
        : _fallback(context);
    return InkWell(
      borderRadius: radius,
      onTap: hasControl ? () => _openControlView(context) : null,
      child: child,
    );
  }

  void _openControlView(BuildContext context) =>
      openBahnCardControl(context, card);

  Widget _fallback(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.586,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEC0016), Color(0xFF9B0010)],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.produktBezeichnung.isNotEmpty
                  ? card.produktBezeichnung
                  : card.typ,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (card.karteninhaber != null)
              Text(
                card.karteninhaber!,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  card.firstClass ? '1. Klasse' : '2. Klasse',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13),
                ),
                if (card.gueltigBis != null)
                  Text(
                    'gültig bis ${_d(card.gueltigBis!)}',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _d(String iso) {
    final dt = DateTime.tryParse(iso);
    return dt != null ? DateFormat('dd.MM.yyyy').format(dt) : iso;
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user, color: Colors.white, size: 14),
          SizedBox(width: 4),
          Text('Kontrolle',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Open DB's BahnCard Kontrollansicht for [card] — same screen as tapping the
/// card in Profil, exposed so the Ticket view can jump to it (a conductor
/// usually checks both, so the user needs a fast switch).
void openBahnCardControl(BuildContext context, DbBahnCard card) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _BahnCardControlScreen(card: card),
    ),
  );
}

/// Open the first BahnCard's Kontrollansicht, or show a snackbar explaining
/// why nothing happened (still loading / endpoint failed / no BahnCard in the
/// account). Always-visible Ticket-AppBar action — never a silent no-op.
Future<void> openFirstBahnCardControl(
    BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final async = ref.read(bahncardsProvider);
  final cards = async.asData?.value;
  if (cards != null && cards.isNotEmpty) {
    openBahnCardControl(context, cards.first);
    return;
  }
  if (cards != null && cards.isEmpty) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Keine BahnCard im Konto.')));
    return;
  }
  // Loading or error — kick a fresh fetch and report.
  messenger.showSnackBar(
      const SnackBar(content: Text('BahnCard wird geladen …')));
  ref.invalidate(bahncardsProvider);
  try {
    final fresh = await ref.read(bahncardsProvider.future);
    if (!context.mounted) return;
    if (fresh.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Keine BahnCard im Konto.')));
      return;
    }
    openBahnCardControl(context, fresh.first);
  } catch (e) {
    if (!context.mounted) return;
    messenger
        .showSnackBar(SnackBar(content: Text('BahnCard nicht ladbar: $e')));
  }
}

/// Fullscreen Kontrollansicht — DB Navigator's exact control-view HTML
/// (PNG + CSS overlay) in a WebView so the conductor sees the same
/// `sichtpruefmerkmal` artwork the official app shows.
class _BahnCardControlScreen extends StatelessWidget {
  final DbBahnCard card;
  const _BahnCardControlScreen({required this.card});

  @override
  Widget build(BuildContext context) {
    final html = card.kontrollSichtHtml;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('BahnCard · Kontrolle'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                children: [
                  if (card.karteninhaber != null)
                    Text(card.karteninhaber!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(card.produktBezeichnung,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 14)),
                ],
              ),
            ),
            Expanded(
              child: (_webViewSupported && html != null)
                  ? _BahnCardHtml(html: html)
                  : const Center(
                      child: Text('Keine Kontrollansicht verfügbar.',
                          style: TextStyle(color: Colors.black54))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  Text('BahnCard-Nr ${card.nummer}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 12)),
                  if (card.gueltigBis != null)
                    Text(
                      'BahnCard gültig bis ${_fmt(card.gueltigBis!)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 12),
                    ),
                  if (card.kontrollSichtGueltigBis != null)
                    Text(
                      'Kontrollansicht gültig bis '
                      '${_fmt(card.kontrollSichtGueltigBis!)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.black38, fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(String iso) {
    final dt = DateTime.tryParse(iso);
    return dt != null ? DateFormat('dd.MM.yyyy').format(dt) : iso;
  }
}

/// Shared WebView wrapper for the BahnCard's `bildSicht` / `kontrollSicht`
/// HTML payloads. JS disabled (DB's HTML is static), white background, no
/// scrollbars.
class _BahnCardHtml extends StatefulWidget {
  final String html;
  const _BahnCardHtml({required this.html});

  @override
  State<_BahnCardHtml> createState() => _BahnCardHtmlState();
}

class _BahnCardHtmlState extends State<_BahnCardHtml> {
  late final WebViewController _controller;

  static const _injectedCss = '<style>'
      'html,body{margin:0;padding:0;background:#fff;'
      'scrollbar-width:none;-ms-overflow-style:none;}'
      'html::-webkit-scrollbar,body::-webkit-scrollbar{display:none;width:0;}'
      '</style>';

  @override
  void initState() {
    super.initState();
    final html = widget.html.contains('</head>')
        ? widget.html.replaceFirst('</head>', '$_injectedCss</head>')
        : '$_injectedCss${widget.html}';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.white)
      ..loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) =>
      WebViewWidget(controller: _controller);
}
