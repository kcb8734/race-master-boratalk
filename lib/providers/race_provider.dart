import 'package:flutter/material.dart';
import '../models/race_models.dart';
import '../services/kra_mock_service.dart';
import '../services/kra_api_service.dart';
import '../services/race_stat_engine.dart';

class RaceProvider extends ChangeNotifier {
  List<DayTab> _weekDays = [];
  int _selectedDayIndex = 0;
  VenueCode _selectedVenue = VenueCode.seoul;
  List<RaceInfo> _races = [];
  bool _isLoadingRaces = false;
  bool _isLoadingDays = true;
  RaceInfo? _selectedRace;
  List<HorseEntry> _horses = [];
  bool _isLoadingHorses = false;
  int _simCount = 0;
  bool _isPremium = false;
  static const int _freeLimitPerDay = 3;

  // AI 인사이트
  List<RaceInsight> _insights = [];
  List<RaceInsight> get insights => _insights;

  List<DayTab> get weekDays => _weekDays;
  int get selectedDayIndex => _selectedDayIndex;
  DayTab? get selectedDay =>
      _weekDays.isNotEmpty ? _weekDays[_selectedDayIndex] : null;
  VenueCode get selectedVenue => _selectedVenue;
  List<RaceInfo> get races => _races;
  bool get isLoadingRaces => _isLoadingRaces;
  bool get isLoadingDays => _isLoadingDays;
  RaceInfo? get selectedRace => _selectedRace;
  List<HorseEntry> get horses => _horses;
  bool get isLoadingHorses => _isLoadingHorses;
  int get simCount => _simCount;
  bool get isPremium => _isPremium;
  bool get canSimulate => _isPremium || _simCount < _freeLimitPerDay;
  int get remainingFree =>
      (_freeLimitPerDay - _simCount).clamp(0, _freeLimitPerDay);

  Future<void> initialize() async {
    _isLoadingDays = true;
    notifyListeners();

    try {
      _weekDays = await KraApiService.scanWeeklyRaceDays();
    } catch (_) {
      _weekDays = KraMockService.scanWeeklyRaceDays();
    }

    final now = DateTime.now();
    final todayIdx = _weekDays.indexWhere((d) =>
        d.date.year == now.year &&
        d.date.month == now.month &&
        d.date.day == now.day);
    _selectedDayIndex = todayIdx >= 0 ? todayIdx : 0;
    _isLoadingDays = false;

    await _loadRaces();
    notifyListeners();
  }

  void selectDay(int index) {
    if (index < 0 || index >= _weekDays.length) return;
    _selectedDayIndex = index;
    _selectedRace = null;
    _horses = [];
    _insights = [];
    _loadRaces();
    notifyListeners();
  }

  void selectVenue(VenueCode venue) {
    _selectedVenue = venue;
    _selectedRace = null;
    _horses = [];
    _insights = [];
    _loadRaces();
    notifyListeners();
  }

  Future<void> _loadRaces() async {
    if (_weekDays.isEmpty) return;
    _isLoadingRaces = true;
    notifyListeners();

    try {
      final day = _weekDays[_selectedDayIndex];
      _races = await KraApiService.fetchRaces(_selectedVenue.code, day.date);
    } catch (_) {
      final day = _weekDays[_selectedDayIndex];
      _races = KraMockService.getRaces(_selectedVenue.code, day.date);
    }

    _isLoadingRaces = false;
    notifyListeners();
  }

  Future<void> selectRace(RaceInfo race) async {
    _selectedRace = race;
    _isLoadingHorses = true;
    _horses = [];
    _insights = [];
    notifyListeners();

    try {
      final day = _weekDays[_selectedDayIndex];
      final rawEntries = await KraApiService.fetchHorseEntries(
          _selectedVenue.code, day.date, race.raceNo);

      // RaceStatEngine: API 기반 스탯 정교화
      _horses = await RaceStatEngine.enrichHorseStats(
        entries: rawEntries,
        race: race,
      );
    } catch (_) {
      _horses = KraMockService.getHorseEntries(race);
    }

    // AI 인사이트 생성
    if (_selectedRace != null) {
      _insights = RaceStatEngine.generateInsights(_horses, _selectedRace!);
    }

    _isLoadingHorses = false;
    notifyListeners();
  }

  void updateUserBonus(int gateNo, double bonus) {
    final idx = _horses.indexWhere((h) => h.gateNo == gateNo);
    if (idx >= 0) {
      _horses[idx] = _horses[idx].copyWith(userBonus: bonus);
      // 인사이트 재계산
      if (_selectedRace != null) {
        _insights = RaceStatEngine.generateInsights(_horses, _selectedRace!);
      }
      notifyListeners();
    }
  }

  void incrementSimCount() {
    _simCount++;
    notifyListeners();
  }

  void setPremium(bool value) {
    _isPremium = value;
    notifyListeners();
  }

  Future<void> refreshRaces() => _loadRaces();
}
