import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/hafas_service.dart';
import '../services/coach_sequence_service.dart';
import '../services/db_api_service.dart';
import '../services/station_map_service.dart';
import '../services/vendo_service.dart';

final hafasServiceProvider = Provider<HafasService>((ref) => HafasService());

final coachSequenceServiceProvider =
    Provider<CoachSequenceService>((ref) => CoachSequenceService());

final dbApiServiceProvider =
    Provider<DbApiService>((ref) => DbApiService());

final stationMapServiceProvider =
    Provider<StationMapService>((ref) => StationMapService());

final vendoServiceProvider = Provider<VendoService>((ref) => VendoService());
