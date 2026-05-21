import 'package:flutter/material.dart';
import '../models/race_models.dart';
import '../services/kra_mock_service.dart';
import '../services/kra_api_service.dart';
import '../services/race_stat_engine.dart';

// ──────────────────────────────────────────────────────────────
// 데이터 상태 열거 (Null Fallback 파이프라인용)
// ──────────────────────────────────────────────────────────────
enum DataStatus {
  loading,      // 로딩 중
  available,    // 데이터 정상 수신
  nullPending,  // 데이터 미확정 (목요일 5시 이전 또는 API 빈 응답)
}

// ──────────────────────────────────────────────────────────────
// 모의레이서 잠금 상태 (Lifecycle Lock)
// ──────────────────────────────────────────────────────────────
enum RaceLockState {
  active,       // 정상 활성 — 레이스 진입 가능
  raceLocked,   // 해당 경주 종료 — 당일 해당 경주 비활성
  seasonOff,    // 일요일 최종 종료 후 ~ 다음 목요일 5시 전 전체 잠금
  dataPending,  // API 데이터 미확정 — 진입 잠금
}

// ──────────────────────────────────────────────────────────────
// RaceProvider
// ──────────────────────────────────────────────────────────────
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

  // ── 라이프사이클 상태 ────────────────────────────────────────
  DataStatus _dataStatus = DataStatus.loading;
  DataStatus get dataStatus => _dataStatus;

  // ── 게터 ────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────
  // 시즌오프 데모 모드
  // ─────────────────────────────────────────────────────────────

  /// 시즌오프 중 체험 모드 시작 — 가상 경주 데이터 1개 로드
  Future<void> loadDemoRaceForSeasonOff() async {
    _selectedRace = KraMockService.getDemoRace();
    _isLoadingHorses = true;
    _horses = [];
    _insights = [];
    notifyListeners();

    // 고정 시드 가상 말 데이터 로드
    await Future.delayed(const Duration(milliseconds: 300)); // 로딩 연출
    _horses = KraMockService.getDemoHorseEntries();

    if (_selectedRace != null) {
      _insights = RaceStatEngine.generateInsights(_horses, _selectedRace!);
    }
    _isLoadingHorses = false;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // 요일별 경주장 스케줄 — VenueScheduleRule 위임
  // ─────────────────────────────────────────────────────────────

  /// 현재 선택된 날짜·경주장 조합이 운영 가능한지 여부
  bool get isSelectedVenueAvailable {
    final day = selectedDay;
    if (day == null) return true;
    return VenueScheduleRule.isVenueActiveOnDate(day.date, _selectedVenue);
  }

  /// 선택된 날짜의 비활성화 이유 설명 (UI 안내문)
  String get venueUnavailableReason {
    final day = selectedDay;
    if (day == null) return '';
    return VenueScheduleRule.inactiveReason(day.date.weekday, _selectedVenue);
  }

  /// 현재 날짜에 활성화된 경주장 목록
  List<VenueCode> get activeVenuesForSelectedDay {
    final day = selectedDay;
    if (day == null) return VenueCode.values;
    final codes = VenueScheduleRule.activeVenueCodes(day.date.weekday);
    return VenueCode.values.where((v) => codes.contains(v.code)).toList();
  }

  // ─────────────────────────────────────────────────────────────
  // 라이프사이클 상태 판단
  // ─────────────────────────────────────────────────────────────

  /// 현재 앱 전역 잠금 상태 계산
  RaceLockState get globalLockState {
    // 1. 데이터 미확정 → dataPending
    if (_dataStatus == DataStatus.nullPending) return RaceLockState.dataPending;

    final now = DateTime.now();

    // 2. 시즌오프 판정:
    //    일요일 경주가 모두 끝났고 (일 23:59 이후 또는 일요일 마지막 경주 종료)
    //    아직 다음 목요일 17:00 이전
    if (_isSeasonOff(now)) return RaceLockState.seasonOff;

    return RaceLockState.active;
  }

  /// 특정 경주에 대한 잠금 상태 계산
  RaceLockState raceLockFor(RaceInfo race) {
    // 전역 잠금이 우선
    final global = globalLockState;
    if (global != RaceLockState.active) return global;

    // 해당 경주가 종료됐는지
    if (race.isFinished) return RaceLockState.raceLocked;

    return RaceLockState.active;
  }

  /// 시즌오프 판정:
  ///   일요일 전체 경주 종료(일 23:00 이후) ~ 목요일 17:00 미만
  bool _isSeasonOff(DateTime now) {
    final wd = now.weekday; // 1=월 … 7=일
    final h = now.hour;

    // 일요일 23:00 이후 → 시즌오프 시작
    if (wd == 7 && h >= 23) return true;

    // 월~목 17:00 미만 → 시즌오프 지속
    if (wd == 1 && h < 17) return true; // 월요일
    if (wd == 2) return true;           // 화요일
    if (wd == 3) return true;           // 수요일
    if (wd == 4 && h < 17) return true; // 목요일 17시 이전

    return false;
  }

  /// 목요일 17시 이후 ~ 금요일 첫 경주 전 → 데이터 아직 없으면 nullPending
  bool get isDataUpdateWindow {
    final now = DateTime.now();
    final wd = now.weekday;
    final h = now.hour;
    // 목요일 17시 이후면 데이터 업데이트 타임
    return (wd == 4 && h >= 17) || wd == 5 || wd == 6 || wd == 7;
  }

  // ─────────────────────────────────────────────────────────────
  // 초기화
  // ─────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    _isLoadingDays = true;
    _dataStatus = DataStatus.loading;
    notifyListeners();

    bool apiSuccess = false;
    try {
      final days = await KraApiService.scanWeeklyRaceDays();
      if (days.isNotEmpty) {
        _weekDays = days;
        apiSuccess = true;
      }
    } catch (_) {}

    if (!apiSuccess) {
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

    // 데이터 상태 판정
    _evaluateDataStatus();
    notifyListeners();
  }

  /// 경주 데이터를 바탕으로 DataStatus 결정
  void _evaluateDataStatus() {
    // 시즌오프 중에는 dataPending이 아닌 seasonOff 처리 → active 유지
    if (_races.isEmpty && isDataUpdateWindow) {
      _dataStatus = DataStatus.nullPending;
    } else {
      _dataStatus = DataStatus.available;
    }
  }

  void selectDay(int index) {
    if (index < 0 || index >= _weekDays.length) return;
    _selectedDayIndex = index;
    _selectedRace = null;
    _horses = [];
    _insights = [];

    // 새 날짜에서 현재 선택된 경주장이 비활성이면 활성 경주장 중 첫 번째로 자동 전환
    final newDay = _weekDays[index];
    if (!VenueScheduleRule.isVenueActiveOnDate(newDay.date, _selectedVenue)) {
      final activeCodes = VenueScheduleRule.activeVenueCodes(newDay.date.weekday);
      final fallback = VenueCode.values.firstWhere(
        (v) => activeCodes.contains(v.code),
        orElse: () => _selectedVenue,
      );
      _selectedVenue = fallback;
    }

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

    bool apiSuccess = false;
    try {
      final day = _weekDays[_selectedDayIndex];
      final result = await KraApiService.fetchRaces(_selectedVenue.code, day.date);
      if (result.isNotEmpty) {
        _races = result;
        apiSuccess = true;
      }
    } catch (_) {}

    if (!apiSuccess) {
      final day = _weekDays[_selectedDayIndex];
      _races = KraMockService.getRaces(_selectedVenue.code, day.date);
    }

    _isLoadingRaces = false;
    _evaluateDataStatus();
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
      _horses = await RaceStatEngine.enrichHorseStats(
        entries: rawEntries,
        race: race,
      );
    } catch (_) {
      _horses = KraMockService.getHorseEntries(race);
    }

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

  Future<void> refreshRaces() async {
    await _loadRaces();
  }
}
