import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_log.dart';
import '../models/db_account.dart';
import '../models/db_ticket.dart';
import '../models/journey.dart';
import '../models/split_ticket.dart' show BahnCardType;
import '../models/station.dart';
import '../services/db_account_service.dart';
import 'library_provider.dart';
import 'service_providers.dart';
import 'settings_provider.dart';

/// Auth state for the DB account login.
class DbAuthState {
  /// false until storage has been checked (initial splash).
  final bool initialized;
  final DbProfile? profile;
  final bool isLoading;
  final String? error;

  const DbAuthState({
    this.initialized = false,
    this.profile,
    this.isLoading = false,
    this.error,
  });

  bool get isLoggedIn => profile != null;

  DbAuthState copyWith({
    bool? initialized,
    DbProfile? profile,
    bool? isLoading,
    String? error,
    bool clearProfile = false,
    bool clearError = false,
  }) {
    return DbAuthState(
      initialized: initialized ?? this.initialized,
      profile: clearProfile ? null : (profile ?? this.profile),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DbAuthNotifier extends Notifier<DbAuthState> {
  DbAccountService get _service => ref.read(dbAccountServiceProvider);

  @override
  DbAuthState build() {
    _restore();
    return const DbAuthState();
  }

  /// On startup: if a token exists, load the profile to validate the session.
  Future<void> _restore() async {
    try {
      final has = await _service.hasSession();
      AppLog.log('restore start · session=$has', tag: 'db-account');
      if (has) {
        final profile = await _service.profile();
        state = state.copyWith(initialized: true, profile: profile);
        _seedSearchDefaults(profile);
        AppLog.log('restore ok · ${profile.kundennummer}', tag: 'db-account');
        return;
      }
    } on DbAccountException catch (e) {
      // Only a genuine auth failure (401) means the stored session is dead —
      // then drop the tokens. The service has already cleared them on a failed
      // refresh, but be explicit. A transient error (offline, timeout, missing
      // platform keyring) must NOT wipe a valid refresh token, or the user is
      // forced to log in again on every cold start.
      AppLog.log(
          'restore DbAccountException status=${e.status} msg=${e.message}',
          tag: 'db-account');
      if (e.status == 401) await _service.logout();
    } catch (e) {
      // Network/platform hiccup — keep the tokens, just show logged-out for
      // now; the next launch (or a manual retry) re-validates the session.
      AppLog.log('restore non-auth error: $e', tag: 'db-account');
    }
    state = state.copyWith(initialized: true, clearProfile: true);
  }

  /// Runs the DB browser login.
  Future<void> login() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final profile = await _service.login();
      state = state.copyWith(isLoading: false, profile: profile);
      _invalidateData();
      _seedSearchDefaults(profile);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: _message(e), clearProfile: true);
    }
  }

  /// Seed the journey-search defaults (age, BahnCard) from what the DB account
  /// already knows, so the user doesn't have to re-enter it. Best-effort and
  /// runs at most once per login — manual changes after this stick.
  Future<void> _seedSearchDefaults(DbProfile profile) async {
    int? age;
    final geb = profile.geburtsdatum;
    if (geb != null) {
      final dt = DateTime.tryParse(geb);
      if (dt != null) {
        final now = DateTime.now();
        age = now.year - dt.year -
            ((now.month < dt.month ||
                    (now.month == dt.month && now.day < dt.day))
                ? 1
                : 0);
      }
    }
    BahnCardType? card;
    try {
      // Go through the provider's future so the cached result is shared with
      // the Profile / Ticket / search-prefill paths — calling the service
      // directly here was firing a SECOND concurrent GET that DB 429'd, and
      // the user saw "BahnCard nicht ladbar · 429".
      final cards = await ref.read(bahncardsProvider.future);
      if (cards.isNotEmpty) card = _toBahnCardType(cards.first);
    } catch (_) {/* no cards / network — leave settings untouched */}
    ref.read(settingsProvider.notifier).applyFromDbAccount(
          age: age,
          card: card,
        );
    // Pull the DB account's Bahnhof-Favoriten into the local library so
    // they show up in the search Schnellauswahl without re-entering them.
    try {
      // Same shared-cache reasoning as bahncards above.
      final favs = await ref.read(dbStationFavoritesProvider.future);
      if (favs.isNotEmpty) {
        final stations = favs.map(_stationFromFavorite).toList();
        ref.read(libraryProvider.notifier).mergeServerFavorites(stations);
      }
    } catch (_) {/* offline / endpoint changed — local library untouched */}
  }

  Station _stationFromFavorite(DbStationFavorite f) => Station(
        id: f.evaNr ?? '',
        name: f.displayName,
        locationId:
            f.locationId.contains('@') ? f.locationId : null,
        latitude: f.lat,
        longitude: f.lng,
      );

  /// Maps a DB-account BahnCard (BC25/BC50/BC100 × KLASSE_1/2) to the local
  /// [BahnCardType] enum the search uses. BC100 isn't an enum value yet — it
  /// behaves like BC50 for discount-bound searches, so map it there.
  BahnCardType? _toBahnCardType(DbBahnCard c) {
    final t = c.typ.toUpperCase();
    final firstClass = c.firstClass;
    if (t.contains('25')) {
      return firstClass ? BahnCardType.bc25_1 : BahnCardType.bc25_2;
    }
    if (t.contains('50') || t.contains('100')) {
      return firstClass ? BahnCardType.bc50_1 : BahnCardType.bc50_2;
    }
    return null;
  }

  Future<void> logout() async {
    await _service.logout();
    state = const DbAuthState(initialized: true);
    _invalidateData();
    // Privacy: strip any Bahnhof-Favoriten that came from the server-side
    // sync and were never used locally — leftover would otherwise leak the
    // signed-out account's data into the Schnellauswahl.
    ref.read(libraryProvider.notifier).dropServerFavorites();
  }

  /// Re-pull the profile (e.g. pull-to-refresh on the Profile tab).
  Future<void> reload() async {
    if (!state.isLoggedIn) return;
    try {
      final profile = await _service.profile();
      state = state.copyWith(profile: profile, clearError: true);
    } catch (e) {
      state = state.copyWith(error: _message(e));
    }
    _invalidateData();
  }

  void _invalidateData() {
    ref.invalidate(bahnbonusProvider);
    ref.invalidate(bahncardsProvider);
    ref.invalidate(reisenuebersichtProvider);
    ref.invalidate(dbStationFavoritesProvider);
  }

  String _message(Object e) {
    final s = e.toString();
    if (s.contains('CANCELED') || s.contains('cancel')) {
      return 'Anmeldung abgebrochen';
    }
    return e is DbAccountException ? e.message : 'Anmeldung fehlgeschlagen';
  }
}

final dbAuthProvider =
    NotifierProvider<DbAuthNotifier, DbAuthState>(DbAuthNotifier.new);

/// BahnBonus status — only fetched while logged in.
final bahnbonusProvider = FutureProvider<DbBahnBonus?>((ref) async {
  final auth = ref.watch(dbAuthProvider);
  if (!auth.isLoggedIn) return null;
  return ref.read(dbAccountServiceProvider).bahnbonus();
});

/// The user's BahnCards.
final bahncardsProvider = FutureProvider<List<DbBahnCard>>((ref) async {
  final auth = ref.watch(dbAuthProvider);
  if (!auth.isLoggedIn) return const [];
  return ref.read(dbAccountServiceProvider).bahncards();
});

/// Full "Meine Reisen" overview from DB (orders + tracked-but-unpaid trips).
/// Cached for the session; both [ticketIndicesProvider] and
/// [savedReisenProvider] derive from this one network call.
final reisenuebersichtProvider =
    FutureProvider<DbReisenUebersicht>((ref) async {
  final auth = ref.watch(dbAuthProvider);
  if (!auth.isLoggedIn) return const DbReisenUebersicht();
  return ref
      .read(dbAccountServiceProvider)
      .reisenuebersicht(onlyCurrent: false);
});

/// Bought tickets only (auftragsIndizes), newest first.
final ticketIndicesProvider = FutureProvider<List<DbReiseIndex>>((ref) async {
  final uebersicht = await ref.watch(reisenuebersichtProvider.future);
  return uebersicht.orders;
});

/// Tracked-but-unpaid trips (reiseIndizes, "Reise merken"), newest start first.
final savedReisenProvider =
    FutureProvider<List<DbSavedReiseIndex>>((ref) async {
  final uebersicht = await ref.watch(reisenuebersichtProvider.future);
  return uebersicht.saved;
});

/// The Journey parsed from one saved DB Reise (`/mob/reisen/{rkUuid}`), cached
/// per rkUuid. Feeds the Reisen tile's JourneyCard.
final savedReiseJourneyProvider =
    FutureProvider.family<Journey?, String>((ref, rkUuid) async {
  final wrap = await ref
      .read(dbAccountServiceProvider)
      .savedReiseVerbindung(rkUuid);
  if (wrap == null) return null;
  try {
    return ref.read(vendoServiceProvider).parseConnection(wrap);
  } catch (_) {
    return null;
  }
});

/// Server-side Bahnhof favorites — read-only sync on login.
final dbStationFavoritesProvider =
    FutureProvider<List<DbStationFavorite>>((ref) async {
  final auth = ref.watch(dbAuthProvider);
  if (!auth.isLoggedIn) return const [];
  return ref.read(dbAccountServiceProvider).stationFavorites();
});

/// A single booked ticket, keyed by "auftragsnummer/kundenwunschId".
final ticketProvider =
    FutureProvider.family<DbTicket, String>((ref, key) async {
  final parts = key.split('/');
  return ref.read(dbAccountServiceProvider).ticket(parts[0], parts[1]);
});

/// Maps a locally-saved journey key → the `rkUuid` of the matching DB "Meine
/// Reisen" trip created when the user bookmarked it while logged in, so the
/// same bookmark can remove it from the DB account again. In-memory for the
/// session (cross-session removal reconciles via the trip overview).
class DbSavedReiseIds extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => {};

  void put(String key, String rkUuid) => state = {...state, key: rkUuid};

  /// Removes and returns the stored id for [key] (null if none).
  String? take(String key) {
    final id = state[key];
    if (id != null) state = {...state}..remove(key);
    return id;
  }
}

final dbSavedReiseIdsProvider =
    NotifierProvider<DbSavedReiseIds, Map<String, String>>(
        DbSavedReiseIds.new);
