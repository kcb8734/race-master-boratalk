import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/race_models.dart';
import '../models/race_horse_data.dart';
import '../services/kra_mock_service.dart';
import '../services/kra_api_service.dart';
import '../services/race_stat_engine.dart';
import '../services/split_time_fetcher.dart';

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
// 배당률 변동 감지 이벤트
// ──────────────────────────────────────────────────────────────
class OddsChangeEvent {
  final int gateNo;
  final String horseName;
  final double previousOdds;
  final double currentOdds;
  final double changePct;   // 변동 비율 (양수 = 상승, 음수 = 하락)

  const OddsChangeEvent({
    required this.gateNo,
    required this.horseName,
    required this.previousOdds,
    required this.currentOdds,
    required this.changePct,
  });

  bool get isSignificant => changePct.abs() >= 10.0; // 10% 이상 변동
  bool get isRising => changePct > 0;
  String get directionEmoji => isRising ? '📈' : '📉';
  String get changeLabel =>
      '${isRising ? "+": ""}${changePct.toStringAsFixed(1)}%';
}

// ──────────────────────────────────────────────────────────────
// 실시간 갱신 상태
// ──────────────────────────────────────────────────────────────
enum RefreshStatus {
  idle,        // 대기 중
  refreshing,  // 갱신 중
  success,     // 마지막 갱신 성공
  error,       // 마지막 갱신 실패
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

  // ── Mock 데이터 여부 플래그 ──────────────────────────────────
  // true = API 실패 → Mock 예시 데이터 사용 중
  // false = KRA 실제 API 데이터 사용 중
  bool _isRacesMock = false;
  bool _isHorsesMock = false;

  bool get isRacesMock  => _isRacesMock;
  bool get isHorsesMock => _isHorsesMock;
  /// 레이스 목록 또는 출전마 중 하나라도 Mock이면 true
  bool get isAnyDataMock => _isRacesMock || _isHorsesMock;

  // AI 인사이트
  List<RaceInsight> _insights = [];
  List<RaceInsight> get insights => _insights;

  // ── 라이프사이클 상태 ────────────────────────────────────────
  DataStatus _dataStatus = DataStatus.loading;
  DataStatus get dataStatus => _dataStatus;

  // ── 실시간 갱신 상태 ─────────────────────────────────────────
  Timer? _refreshTimer;
  DateTime? _lastUpdated;
  RefreshStatus _refreshStatus = RefreshStatus.idle;
  bool _isAutoRefreshEnabled = false;
  List<OddsChangeEvent> _recentOddsChanges = [];

  // 이전 배당률 스냅샷 (변동 감지용)
  Map<int, double> _previousOddsSnapshot = {};

  // 자동 갱신 간격 (경주 시작 전 5분마다)
  static const Duration _refreshInterval = Duration(minutes: 5);

  // ── 실시간 갱신 게터 ─────────────────────────────────────────
  DateTime? get lastUpdated => _lastUpdated;
  RefreshStatus get refreshStatus => _refreshStatus;
  bool get isAutoRefreshEnabled => _isAutoRefreshEnabled;
  bool get isRefreshing => _refreshStatus == RefreshStatus.refreshing;
  List<OddsChangeEvent> get recentOddsChanges => _recentOddsChanges;

  /// 마지막 업데이트 시각 표시 문자열
  String get lastUpdatedLabel {
    if (_lastUpdated == null) return '업데이트 전';
    final now = DateTime.now();
    final diff = now.difference(_lastUpdated!);
    if (diff.inSeconds < 60) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    final h = _lastUpdated!.hour.toString().padLeft(2, '0');
    final m = _lastUpdated!.minute.toString().padLeft(2, '0');
    return '$h:$m 갱신';
  }

  /// 다음 자동 갱신까지 남은 시간 (초)
  int get secondsUntilNextRefresh {
    if (_lastUpdated == null || !_isAutoRefreshEnabled) return 0;
    final elapsed = DateTime.now().difference(_lastUpdated!).inSeconds;
    final intervalSec = _refreshInterval.inSeconds;
    return (intervalSec - elapsed).clamp(0, intervalSec);
  }

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
  // dispose: 타이머 정리
  // ─────────────────────────────────────────────────────────────
  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // 실시간 갱신 — 자동 폴링 시작
  // ─────────────────────────────────────────────────────────────

  /// 자동 갱신 시작 (경주 선택 시 호출)
  /// [race]가 종료됐거나 시즌오프 중이면 폴링하지 않음
  void startAutoRefresh(RaceInfo race) {
    // 이미 실행 중이면 중지 후 재시작
    stopAutoRefresh();

    // 종료된 경주 또는 시즌오프면 폴링 안 함
    if (race.isFinished || globalLockState == RaceLockState.seasonOff) return;

    _isAutoRefreshEnabled = true;
    _refreshTimer = Timer.periodic(_refreshInterval, (_) async {
      await _autoRefreshHorses();
    });
    notifyListeners();
  }

  /// 자동 갱신 중지
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _isAutoRefreshEnabled = false;
  }

  /// 수동 새로고침 (버튼 탭)
  Future<void> manualRefresh() async {
    if (_selectedRace == null) return;
    await _autoRefreshHorses(isManual: true);
  }

  /// 내부 갱신 로직 (자동/수동 공통)
  Future<void> _autoRefreshHorses({bool isManual = false}) async {
    if (_selectedRace == null || _isLoadingHorses) return;

    _refreshStatus = RefreshStatus.refreshing;
    notifyListeners();

    try {
      final race = _selectedRace!;
      final day  = _weekDays[_selectedDayIndex];

      // 이전 배당률 스냅샷 저장
      _previousOddsSnapshot = {
        for (final h in _horses) h.gateNo: h.odds
      };

      final rawEntries = await KraApiService.fetchHorseEntries(
          _selectedVenue.code, day.date, race.raceNo);
      final enriched = await RaceStatEngine.enrichHorseStats(
        entries: rawEntries,
        race: race,
      );

      // 배당률 변동 감지
      _detectOddsChanges(enriched);

      _horses = enriched;
      if (_selectedRace != null) {
        _insights = RaceStatEngine.generateInsights(_horses, _selectedRace!);
      }

      _lastUpdated = DateTime.now();
      _refreshStatus = RefreshStatus.success;
    } catch (_) {
      // API 실패 시 기존 데이터 유지
      _refreshStatus = RefreshStatus.error;
      _lastUpdated = DateTime.now();
    }

    notifyListeners();
  }

  /// 배당률 변동 감지 (10% 이상 변동을 이벤트로 기록)
  void _detectOddsChanges(List<HorseEntry> newHorses) {
    final changes = <OddsChangeEvent>[];

    for (final h in newHorses) {
      final prev = _previousOddsSnapshot[h.gateNo];
      if (prev == null || prev <= 0 || h.odds <= 0) continue;

      final changePct = ((h.odds - prev) / prev) * 100.0;
      if (changePct.abs() >= 10.0) {
        changes.add(OddsChangeEvent(
          gateNo: h.gateNo,
          horseName: h.horseName,
          previousOdds: prev,
          currentOdds: h.odds,
          changePct: changePct,
        ));
      }
    }

    if (changes.isNotEmpty) {
      // 최신 5건만 유지
      _recentOddsChanges = [...changes, ..._recentOddsChanges].take(5).toList();
    }
  }

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

    // 날짜 전환 시 폴링 중지
    stopAutoRefresh();

    // ── Jockey Engine: 날짜 변경 시 당일 기수 성적 초기화 ─────────────
    // 새 날짜 선택 → 전일 safeMode/mentalBuff 상태 리셋
    final currentDay = _weekDays.isNotEmpty ? _weekDays[_selectedDayIndex] : null;
    final newDayData = _weekDays[index];
    if (currentDay == null || currentDay.date != newDayData.date) {
      JockeyDailyTracker.instance.resetDay();
      HighOddsWindowDetector.instance.reset();
    }

    _selectedDayIndex = index;
    _selectedRace = null;
    _horses = [];
    _insights = [];
    _recentOddsChanges = [];
    _previousOddsSnapshot = {};

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
    stopAutoRefresh();
    _selectedVenue = venue;
    _selectedRace = null;
    _horses = [];
    _insights = [];
    _recentOddsChanges = [];
    _previousOddsSnapshot = {};
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

    // Mock 여부 기록 (UI 배지 표시용)
    _isRacesMock = !apiSuccess;

    _isLoadingRaces = false;
    _evaluateDataStatus();
    notifyListeners();
  }

  Future<void> selectRace(RaceInfo race) async {
    // 경주 변경 시 기존 폴링 중지
    stopAutoRefresh();
    _recentOddsChanges = [];
    _previousOddsSnapshot = {};

    _selectedRace = race;
    _isLoadingHorses = true;
    _horses = [];
    _insights = [];
    notifyListeners();

    bool apiSuccess = false;
    try {
      final day = _weekDays[_selectedDayIndex];
      final rawEntries = await KraApiService.fetchHorseEntries(
          _selectedVenue.code, day.date, race.raceNo);
      _horses = await RaceStatEngine.enrichHorseStats(
        entries: rawEntries,
        race: race,
      );
      // gateNo(마번) 기준 오름차순 정렬 — API 응답 순서 불일치 방지
      _horses.sort((a, b) => a.gateNo.compareTo(b.gateNo));
      apiSuccess = true;
    } catch (_) {
      _horses = KraMockService.getHorseEntries(race);
      // Mock도 정렬 보장
      _horses.sort((a, b) => a.gateNo.compareTo(b.gateNo));
    }

    // Mock 여부 기록 (UI 배지 표시용)
    _isHorsesMock = !apiSuccess;

    if (_selectedRace != null) {
      _insights = RaceStatEngine.generateInsights(_horses, _selectedRace!);
    }

    _lastUpdated = DateTime.now();
    _refreshStatus = apiSuccess ? RefreshStatus.success : RefreshStatus.error;
    _isLoadingHorses = false;
    notifyListeners();

    // ── [API4_3] 물리 프로필 백그라운드 사전 로딩 ──────────────────────────────────────
    // 경주 선택 시점에 즉시 백그라운드 실행
    // → race_animation_screen.dart 게이트빰 진입 전에 미리 프로필 주입→ 대기시간 활용
    // → 로딩 완료 시 notifyListeners()로 UI 자동 갱신 (AI✓ 인디케이터)
    SplitTimeFetcher.clearCache(); // 새 경주 선택 시 캐시 초기화
    _prefetchPhysicsProfiles(race);

    // 경주 미종료 시 자동 갱신 시작
    if (!race.isFinished) {
      startAutoRefresh(race);
    }
  }

  // ───────────────────────────────────────────────────────────────
  // [API4_3] 물리 프로필 백그라운드 사전 로딩
  //
  // 연산:
  //   경주 선택 시점에 selectRace() 끝에서 호출
  //   → 물리 프로필이 없는 말들만 SplitTimeFetcher.fetchAllProfiles()
  //   → 로딩 완료 시 _horses[] 각 HorseEntry에 physicsProfile 주입
  //   → notifyListeners() 호출 → UI(AI✓/AI?) 인디케이터 자동 갱신
  //
  // 예외 처리:
  //   • API 실패 → neutral 프로필 적용 (시미실 중단 없음)
  //   • mounted 검사 없음 — ChangeNotifier는 dispose 후 notifyListeners() 내부 안전한 처리
  // ───────────────────────────────────────────────────────────────
  void _prefetchPhysicsProfiles(RaceInfo race) {
    // 이미 physicsProfile이 주입된 말은 제외 (새로 불러올 필요 없음)
    final needFetch = _horses.where((h) => h.physicsProfile == null).toList();
    if (needFetch.isEmpty) return;

    SplitTimeFetcher.fetchAllProfiles(
      entries: needFetch,
      race:    race,
    ).then((profileMap) {
      // 프로파이더가 dispose된 여부는 ChangeNotifier가 내부 처리
      if (_horses.isEmpty) return;

      bool updated = false;
      final updatedHorses = _horses.map((h) {
        final profile = profileMap[h.gateNo];
        if (profile != null && h.physicsProfile == null) {
          updated = true;
          return h.copyWith(physicsProfile: profile);
        }
        return h;
      }).toList();

      if (updated) {
        _horses = updatedHorses;
        notifyListeners(); // AI✓ 인디케이터 즈시 업데이트
        if (kDebugMode) {
          debugPrint('[RaceProvider] 피직스 프로파일 주입 완료: '
              '${profileMap.length}마 / ${_horses.length}마');
        }
      }
    }).catchError((e) {
      if (kDebugMode) {
        debugPrint('[RaceProvider] 피직스 프로파일 사전로딩 실패: $e');
      }
    });
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

  // ─────────────────────────────────────────────────────────────────
  // 샌드박스 모드: 외부에서 경주/말 데이터 직접 주입
  // racedetailresult 기반 과거 경주 재현 시 사용
  // ─────────────────────────────────────────────────────────────────
  Future<void> injectSandboxData(
      RaceInfo race, List<HorseEntry> entries) async {
    stopAutoRefresh();
    _selectedRace    = race;
    _horses          = entries;
    _insights        = RaceStatEngine.generateInsights(entries, race);
    _lastUpdated     = DateTime.now();
    _refreshStatus   = RefreshStatus.success;
    _isLoadingHorses = false;
    _recentOddsChanges   = [];
    _previousOddsSnapshot = {};
    notifyListeners();
  }
}
