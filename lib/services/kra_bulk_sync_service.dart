import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'race_schedule_cache.dart';
import 'race_snapshot_cache.dart';
import 'kra_api_service.dart';
import 'race_stat_engine.dart';
import '../models/race_models.dart';

// ══════════════════════════════════════════════════════════════════════════
//  KraBulkSyncService — 새벽 시간대 KRA 공공데이터 API 벌크 수집 스케줄러
//
//  ▸ 목적: 트래픽이 적은 새벽 02:00~05:00 사이에 23개 공공데이터 API를
//          순차적으로 호출(3~5초 딜레이)하여 마필/기수/조교사 뼈대 데이터를
//          로컬 SharedPreferences에 영구 적재 (Cold Storage)
//
//  ▸ 대상 API 목록 (공공데이터포털 KRA 공개 API 전체):
//    01. API187     — 경마경주정보 (레이스 스케줄)
//    02. API26_2    — 출전표 상세정보
//    03. API4_3     — 경주기록 (착순 결과)
//    04. API8_2     — 경주마 상세정보 & 레이팅
//    05. API12_1    — 기수 면허 및 통산 전적
//    06. API10_1    — 조교사 통산 성적
//    07. API11      — 마주 정보
//    08. trnweekentry  — 조교사 차주 출전 예정마 조교 정보
//    09. trtrdate      — 조교사 일일 조교두수
//    10. API3_1     — 경마 일정 (레이스 캘린더)
//    11. API6_1     — 배당률 현황 (단승/복승/쌍승)
//    12. API5_1     — 경마 통계 (주로별 기록)
//    13. API14      — 경주마 혈통 정보
//    14. API15      — 경주마 과거성적 (히스토리)
//    15. API16      — 기수 과거 성적
//    16. API17      — 조교사 과거 성적
//    17. API18      — 마주 과거 성적
//    18. API19      — 생산자 정보
//    19. API20      — 경주마 조교 기록
//    20. API21      — 경주 날씨 / 주로 상태 이력
//    21. API22      — 경주장별 기록 통계
//    22. API23      — 연간 경마 통계
//    23. racedetailresult — 경주별 상세 성적표
//
//  ▸ 새벽 시간대 판단: KST 02:00 ~ 05:00 (UTC+9)
//  ▸ 딜레이: 호출 간 3~5초 랜덤 (방화벽 탐지 임계치 분산)
//  ▸ 저장 키: bulk_sync_{apiId}_{YYYYMMDD}
//  ▸ TTL: 7일
// ══════════════════════════════════════════════════════════════════════════
class KraBulkSyncService {
  // ── 싱글톤 ────────────────────────────────────────────────────────────
  static final KraBulkSyncService _instance = KraBulkSyncService._internal();
  factory KraBulkSyncService() => _instance;
  KraBulkSyncService._internal();

  // ── KRA 공공데이터 상수 ───────────────────────────────────────────────
  static const String _serviceKey =
      'ef117e7bebbcea7586234f85acd8292dba6a6d95230131aec62a10b5b2610885';
  static const String _baseUrl = 'https://apis.data.go.kr/B551015';

  // ── 스케줄러 상수 ─────────────────────────────────────────────────────
  static const String _prefixBulk  = 'bulk_sync_';
  static const String _keyLastSync = 'bulk_sync_last_run';
  static const String _keyProgress = 'bulk_sync_progress';
  static const Duration _cacheTtl  = Duration(days: 7);
  static const Duration _checkInterval = Duration(minutes: 10);

  // ── 상태 ──────────────────────────────────────────────────────────────
  bool _isRunning = false;
  int  _completedApis = 0;
  int  _totalApis = 0;
  String _currentApi = '';
  DateTime? _lastRunAt;
  Timer? _scheduleTimer;

  // ── Getters ───────────────────────────────────────────────────────────
  bool get isRunning      => _isRunning;
  int  get completedApis  => _completedApis;
  int  get totalApis      => _totalApis;
  String get currentApi   => _currentApi;
  DateTime? get lastRunAt => _lastRunAt;
  double get progress =>
      _totalApis > 0 ? _completedApis / _totalApis : 0.0;

  // ── 진행 상태 콜백 ────────────────────────────────────────────────────
  Function(BulkSyncProgress)? onProgress;

  // ══════════════════════════════════════════════════════════════════════
  //  23개 API 정의
  // ══════════════════════════════════════════════════════════════════════
  static List<BulkApiTarget> get apiTargets => [
    BulkApiTarget(
      id: 'API187',
      name: '경마경주정보',
      path: '/API187',
      params: {'numOfRows': '20', 'pageNo': '1', 'meet': '1', '_type': 'json'},
      needsDate: true,
    ),
    BulkApiTarget(
      id: 'API26_2',
      name: '출전표 상세정보',
      path: '/API26_2/entrySheet_2',
      params: {'numOfRows': '20', 'pageNo': '1', 'meet': '1', 'rc_no': '1'},
      needsDate: true,
    ),
    BulkApiTarget(
      id: 'API4_3',
      name: '경주기록(착순결과)',
      path: '/API4_3',
      params: {'numOfRows': '20', 'pageNo': '1', 'meet': '1', '_type': 'json'},
      needsDate: true,
    ),
    BulkApiTarget(
      id: 'API8_2',
      name: '경주마 상세정보',
      path: '/API8_2/raceHorseInfo_2',
      params: {'numOfRows': '100', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API12_1',
      name: '기수 면허 및 통산전적',
      path: '/API12_1/jockeyInfo_1',
      params: {'numOfRows': '100', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API10_1',
      name: '조교사 통산성적',
      path: '/API10_1/trainerInfo_1',
      params: {'numOfRows': '100', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API11',
      name: '마주 정보',
      path: '/API11/ownerInfo',
      params: {'numOfRows': '100', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'trnweekentry',
      name: '조교사 차주 출전 예정마',
      path: '/trnweekentry/gettrnweekentry',
      params: {'numOfRows': '500', 'pageNo': '1', 'meet': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'trtrdate',
      name: '조교사 일일 조교두수',
      path: '/trtrdate/gettrtrdate',
      params: {'numOfRows': '100', 'pageNo': '1', 'meet': '1'},
      needsDate: true,
    ),
    BulkApiTarget(
      id: 'API3_1',
      name: '경마 일정(캘린더)',
      path: '/API3_1/raceSchedule_1',
      params: {'numOfRows': '30', 'pageNo': '1', '_type': 'json'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API6_1',
      name: '배당률 현황',
      path: '/API6_1/oddsInfo_1',
      params: {'numOfRows': '20', 'pageNo': '1', 'meet': '1', 'rc_no': '1'},
      needsDate: true,
    ),
    BulkApiTarget(
      id: 'API5_1',
      name: '경마통계(주로별기록)',
      path: '/API5_1/raceStatistics_1',
      params: {'numOfRows': '50', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API14',
      name: '경주마 혈통정보',
      path: '/API14/pedigreeInfo',
      params: {'numOfRows': '100', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API15',
      name: '경주마 과거성적',
      path: '/API15/horseHistoryInfo',
      params: {'numOfRows': '50', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API16',
      name: '기수 과거성적',
      path: '/API16/jockeyHistoryInfo',
      params: {'numOfRows': '50', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API17',
      name: '조교사 과거성적',
      path: '/API17/trainerHistoryInfo',
      params: {'numOfRows': '50', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API18',
      name: '마주 과거성적',
      path: '/API18/ownerHistoryInfo',
      params: {'numOfRows': '50', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API19',
      name: '생산자 정보',
      path: '/API19/breederInfo',
      params: {'numOfRows': '100', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API20',
      name: '경주마 조교기록',
      path: '/API20/horseTrainingRecord',
      params: {'numOfRows': '50', 'pageNo': '1', 'meet': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API21',
      name: '경주 날씨/주로상태 이력',
      path: '/API21/weatherTrackHistory',
      params: {'numOfRows': '30', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API22',
      name: '경주장별 기록통계',
      path: '/API22/venueStatistics',
      params: {'numOfRows': '50', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'API23',
      name: '연간 경마통계',
      path: '/API23/annualStatistics',
      params: {'numOfRows': '50', 'pageNo': '1'},
      needsDate: false,
    ),
    BulkApiTarget(
      id: 'racedetailresult',
      name: '경주별 상세성적표',
      path: '/racedetailresult/getracedetailresult',
      params: {'numOfRows': '16', 'pageNo': '1', 'meet': '1', 'rc_no': '1'},
      needsDate: true,
    ),
  ];

  // ══════════════════════════════════════════════════════════════════════
  //  자동 스케줄러 시작 (앱 초기화 시 1회 호출)
  //  10분 주기로 현재 시각이 새벽 02:00~05:00인지 체크
  // ══════════════════════════════════════════════════════════════════════
  void startScheduler() {
    _scheduleTimer?.cancel();
    _checkAndRunIfDawn(); // 즉시 1회 체크
    _scheduleTimer = Timer.periodic(_checkInterval, (_) => _checkAndRunIfDawn());
    if (kDebugMode) {
      debugPrint('[BulkSync] 스케줄러 시작 (10분 주기 새벽 체크)');
    }
  }

  void stopScheduler() {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
  }

  Future<void> _checkAndRunIfDawn() async {
    if (_isRunning) return;
    final now = DateTime.now().toLocal();
    if (!_isDawnWindow(now)) return;

    // 오늘 이미 실행했으면 스킵
    final prefs = await SharedPreferences.getInstance();
    final lastRunStr = prefs.getString(_keyLastSync);
    if (lastRunStr != null) {
      final lastRun = DateTime.tryParse(lastRunStr);
      if (lastRun != null) {
        final today = DateTime(now.year, now.month, now.day);
        if (!lastRun.isBefore(today)) {
          if (kDebugMode) {
            debugPrint('[BulkSync] 오늘 이미 실행됨 (${lastRun.toLocal()}) — 스킵');
          }
          return;
        }
      }
    }

    if (kDebugMode) {
      debugPrint('[BulkSync] 새벽 시간대 감지 — 벌크 싱크 시작');
    }
    await runBulkSync();
  }

  // KST 기준 02:00~05:00
  static bool _isDawnWindow(DateTime localTime) {
    final h = localTime.hour;
    return h >= 2 && h < 5;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  수동 즉시 실행 (관리자 어드민 패널 "지금 수집" 버튼)
  // ══════════════════════════════════════════════════════════════════════
  Future<BulkSyncResult> runBulkSyncNow() async {
    return await runBulkSync(forceRun: true);
  }

  // ══════════════════════════════════════════════════════════════════════
  //  벌크 싱크 본체 (v2.0 — RaceSnapshotCache 파이프라인 통합)
  //
  //  Phase 1: 23개 공공데이터 API 벌크 호출 → raw JSON 저장 (기존)
  //  Phase 2: API26_2 출전표 수집 완료된 경주별 → enrichHorseStats() 실행
  //           → RaceSnapshotCache.saveRaceSnapshot() 저장 (신규)
  //  → 이후 selectRace()는 외부 API 없이 캐시만 조회 (200ms 이내 반환)
  // ══════════════════════════════════════════════════════════════════════
  Future<BulkSyncResult> runBulkSync({bool forceRun = false}) async {
    if (_isRunning) {
      return BulkSyncResult(
        success: false,
        message: '이미 실행 중입니다',
        completedCount: 0,
        failedCount: 0,
        details: [],
        snapshotSavedCount: 0,
      );
    }

    _isRunning = true;
    _completedApis = 0;
    // Phase 1 (API 수집) + Phase 2 (스냅샷 인젝션) 합산
    _totalApis = apiTargets.length;
    final prefs = await SharedPreferences.getInstance();
    final today = _todayStr();
    final results = <BulkApiResult>[];
    final cache = RaceScheduleCache();
    final snapCache = RaceSnapshotCache();
    int snapshotSavedCount = 0;

    if (kDebugMode) {
      debugPrint('[BulkSync] ▶ 벌크 싱크 시작 v2.0 — ${apiTargets.length}개 API (날짜: $today)');
      debugPrint('[BulkSync] Phase 1: API 수집 | Phase 2: 스냅샷 DB 인젝션');
    }

    // ── Phase 1: 23개 API 순차 수집 ─────────────────────────────────────
    for (int i = 0; i < apiTargets.length; i++) {
      final target = apiTargets[i];
      _currentApi = target.name;
      _completedApis = i;
      onProgress?.call(BulkSyncProgress(
        current: i + 1,
        total: apiTargets.length,
        apiName: target.name,
        apiId: target.id,
        phase: 'API수집',
      ));

      // 이미 오늘 수집된 API는 스킵 (forceRun이면 재수집)
      if (!forceRun) {
        final existing = prefs.getString('$_prefixBulk${target.id}_$today');
        if (existing != null) {
          if (kDebugMode) {
            debugPrint('[BulkSync] #${i+1}/${apiTargets.length} ${target.id} — 오늘 수집됨, 스킵');
          }
          results.add(BulkApiResult(
            apiId: target.id, apiName: target.name,
            success: true, statusCode: 200,
            message: '기존 캐시 사용', recordCount: 0, skipped: true,
          ));
          _completedApis = i + 1;
          continue;
        }
      }

      // API 호출
      final result = await _callSingleApi(target, today, prefs, cache);
      results.add(result);
      _completedApis = i + 1;

      if (kDebugMode) {
        final icon = result.success ? '✅' : '❌';
        debugPrint(
          '[BulkSync] #${i+1}/${apiTargets.length} $icon ${target.id}: '
          '${result.message} (${result.recordCount}건)',
        );
      }

      // 3~5초 랜덤 딜레이 (방화벽 분산)
      if (i < apiTargets.length - 1) {
        final delayMs = 3000 + (DateTime.now().millisecond % 2000); // 3000~5000ms
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    // ── Phase 2: 출전표(API26_2) 기반 경주별 스냅샷 인젝션 ──────────────
    // API26_2 raw JSON → 경주별 HorseEntry enrichment → RaceSnapshotCache 저장
    if (kDebugMode) {
      debugPrint('[BulkSync] Phase 2 시작: 출전표 → RaceSnapshotCache 인젝션');
    }
    _currentApi = '스냅샷 인젝션 중...';
    snapshotSavedCount = await _injectSnapshotsFromBulkData(
      today: today,
      prefs: prefs,
      snapCache: snapCache,
      forceRun: forceRun,
    );
    if (kDebugMode) {
      debugPrint('[BulkSync] Phase 2 완료: $snapshotSavedCount개 경주 스냅샷 저장');
    }

    // ── 완료 기록 ─────────────────────────────────────────────────────
    _lastRunAt = DateTime.now();
    await prefs.setString(_keyLastSync, _lastRunAt!.toIso8601String());
    await prefs.setString(_keyProgress, jsonEncode({
      'lastRun': _lastRunAt!.toIso8601String(),
      'completed': results.where((r) => r.success && !r.skipped).length,
      'failed': results.where((r) => !r.success).length,
      'skipped': results.where((r) => r.skipped).length,
      'total': apiTargets.length,
      'snapshotSaved': snapshotSavedCount,
    }));

    _isRunning = false;
    _currentApi = '';

    final successCount = results.where((r) => r.success && !r.skipped).length;
    final failCount    = results.where((r) => !r.success).length;
    final skipCount    = results.where((r) => r.skipped).length;

    if (kDebugMode) {
      debugPrint(
        '[BulkSync] ■ 완료 — 성공: $successCount, 실패: $failCount, 스킵: $skipCount\n'
        '[BulkSync] ■ 스냅샷 DB 인젝션: $snapshotSavedCount개 경주',
      );
    }

    return BulkSyncResult(
      success: failCount < apiTargets.length,
      message: '성공 $successCount / 실패 $failCount / 스킵 $skipCount | 스냅샷 $snapshotSavedCount개',
      completedCount: successCount,
      failedCount: failCount,
      details: results,
      snapshotSavedCount: snapshotSavedCount,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  Phase 2 핵심: 벌크 수집 완료 후 경주별 스냅샷 인젝션
  //
  //  ▸ 서울/부산/제주 전체 경주번호 순회
  //  ▸ API26_2 raw JSON → KraApiService.parseEntrySheet() → HorseEntry 목록
  //  ▸ RaceStatEngine.enrichHorseStats() → 통계 풍부화
  //  ▸ RaceSnapshotCache.saveRaceSnapshot() → SharedPreferences 저장
  //
  //  ▸ 실패 허용 (경주별 try-catch): 일부 경주 실패해도 전체 중단 없음
  // ══════════════════════════════════════════════════════════════════════
  Future<int> _injectSnapshotsFromBulkData({
    required String today,
    required SharedPreferences prefs,
    required RaceSnapshotCache snapCache,
    required bool forceRun,
  }) async {
    int savedCount = 0;

    // today(YYYYMMDD) → DateTime 변환 (캐시 API용)
    final todayDate = DateTime(
      int.parse(today.substring(0, 4)),
      int.parse(today.substring(4, 6)),
      int.parse(today.substring(6, 8)),
    );

    // 수집된 경주 목록 조회 (API187 — 경마경주정보에서 파싱)
    final raceListJson = prefs.getString('${_prefixBulk}API187_$today');
    List<Map<String, dynamic>> raceTargets = [];

    if (raceListJson != null) {
      try {
        raceTargets = _parseRaceListFromApi187(raceListJson);
      } catch (e) {
        if (kDebugMode) debugPrint('[BulkSync] API187 파싱 실패: $e');
      }
    }

    // API187 파싱 실패 시 기본 경주 범위로 폴백
    if (raceTargets.isEmpty) {
      // 서울(1), 부산(2), 제주(3) × 경주번호 1~11
      for (final meet in ['1', '2', '3']) {
        for (int rcNo = 1; rcNo <= 11; rcNo++) {
          raceTargets.add({'meet': meet, 'rcNo': '$rcNo'});
        }
      }
    }

    for (final target in raceTargets) {
      final meet  = target['meet']  as String? ?? '1';
      final rcNo  = target['rcNo']  as String? ?? '1';
      final vCode = _meetToVenueCode(meet);

      // forceRun=false면 이미 유효한 스냅샷이 있으면 스킵
      if (!forceRun) {
        final hasSnap = await snapCache.hasValidSnapshot(
          venueCode: vCode, date: todayDate, raceNo: rcNo);
        if (hasSnap) {
          if (kDebugMode) {
            debugPrint('[BulkSync] 스냅샷 스킵: $vCode R$rcNo (이미 유효)');
          }
          continue;
        }
      }

      try {
        final sw = Stopwatch()..start();

        // API26_2 출전표 직접 호출 (스냅샷 인젝션용 — 배치 내에서 경주별 1회)
        final meta = await KraApiService.fetchHorseEntriesWithMeta(
          vCode, todayDate, rcNo);

        if (meta.entries.isEmpty) {
          if (kDebugMode) {
            debugPrint('[BulkSync] 출전마 없음: $vCode R$rcNo — 스킵');
          }
          continue;
        }

        // 경주 메타 구성 (distance는 EntrySheetResult에 없어 기본값 사용)
        final raceInfo = RaceInfo(
          raceNo:         rcNo,
          raceName:       '${rcNo}경주',
          distance:       1200, // 배치 단계 기본거리
          startTime:      meta.startTime ?? '',
          totalHorses:    meta.entries.length,
          venueCode:      vCode,
          venueName:      _meetToVenueName(meet),
          raceDate:       today,
          condition:      '',
          grade:          '',
          trackCondition: '',
          isFinished:     false,
        );

        // enrichHorseStats: API4_3, API8_2, API5_1, API6_1, API16 등 내부 처리
        final enriched = await RaceStatEngine.enrichHorseStats(
          entries: meta.entries,
          race:    raceInfo,
        );
        enriched.sort((a, b) => a.gateNo.compareTo(b.gateNo));

        sw.stop();

        // RaceSnapshotCache에 저장
        await snapCache.saveRaceSnapshot(
          venueCode:       vCode,
          date:            todayDate,
          raceNo:          rcNo,
          horses:          enriched,
          source:          'batch',
          fetchDurationMs: sw.elapsedMilliseconds,
        );

        savedCount++;
        if (kDebugMode) {
          debugPrint(
            '[BulkSync] ✅ 스냅샷 저장: $vCode R$rcNo — '
            '${enriched.length}마 / ${sw.elapsedMilliseconds}ms',
          );
        }

        // 인젝션 간 1~2초 딜레이 (API 부하 분산)
        await Future.delayed(const Duration(milliseconds: 1200));

      } catch (e) {
        if (kDebugMode) {
          debugPrint('[BulkSync] ❌ 스냅샷 실패: $vCode R$rcNo — $e');
        }
        // 경주별 실패는 무시하고 다음 경주 계속
      }
    }

    return savedCount;
  }

  /// API187 응답 JSON 파싱 → (meet, rcNo) 목록
  List<Map<String, dynamic>> _parseRaceListFromApi187(String rawJson) {
    final result = <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(rawJson);
      List items = [];
      if (decoded is Map) {
        items = decoded['response']?['body']?['items']?['item'] ?? [];
        if (items is! List) items = [items];
      } else if (decoded is List) {
        items = decoded;
      }
      final seen = <String>{};
      for (final item in items) {
        if (item is! Map) continue;
        final meet  = (item['meet']  ?? item['meetCd'] ?? '').toString();
        final rcNo  = (item['rcNo']  ?? item['raceNo'] ?? '').toString();
        if (meet.isEmpty || rcNo.isEmpty) continue;
        final key = '$meet:$rcNo';
        if (!seen.contains(key)) {
          seen.add(key);
          result.add({'meet': meet, 'rcNo': rcNo});
        }
      }
    } catch (_) {}
    return result;
  }

  /// meet 코드 → venueCode 문자열 변환
  static String _meetToVenueCode(String meet) {
    switch (meet) {
      case '1': return 'SEO';
      case '2': return 'PUS';
      case '3': return 'JEJ';
      default:  return 'SEO';
    }
  }

  /// meet 코드 → 경주장명 변환
  static String _meetToVenueName(String meet) {
    switch (meet) {
      case '1': return '서울';
      case '2': return '부산경남';
      case '3': return '제주';
      default:  return '서울';
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  단일 API 호출 + 저장
  // ─────────────────────────────────────────────────────────────────────
  Future<BulkApiResult> _callSingleApi(
    BulkApiTarget target,
    String today,
    SharedPreferences prefs,
    RaceScheduleCache cache,
  ) async {
    try {
      // URL 조립
      final params = Map<String, String>.from(target.params);
      params['serviceKey'] = _serviceKey;
      if (target.needsDate) params['rc_date'] = today;

      final queryStr = params.entries
          .map((e) => '${e.key}=${e.value}')
          .join('&');
      final url = '$_baseUrl${target.path}?$queryStr';

      final resp = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));

      // 에러 로그 적재 (투명성)
      if (resp.statusCode != 200 || resp.body.contains('Unexpected errors')) {
        await cache.logApiError(
          apiName: 'BulkSync-${target.id}',
          statusCode: resp.statusCode,
          errorBody: resp.body.length > 200
              ? resp.body.substring(0, 200) : resp.body,
          requestUrl: url,
          encodingNote: 'bulk_sync 새벽 수집',
        );
        return BulkApiResult(
          apiId: target.id, apiName: target.name,
          success: false,
          statusCode: resp.statusCode,
          message: 'HTTP ${resp.statusCode}: ${resp.body.substring(0, resp.body.length.clamp(0, 80))}',
          recordCount: 0,
        );
      }

      // 데이터 저장 (Raw JSON/XML 전체)
      final bodyToStore = resp.body.length > 50000
          ? resp.body.substring(0, 50000) : resp.body;
      await prefs.setString(
        '$_prefixBulk${target.id}_$today',
        bodyToStore,
      );
      await prefs.setInt(
        '${_prefixBulk}ts_${target.id}_$today',
        DateTime.now().millisecondsSinceEpoch,
      );

      // 레코드 수 추정 (JSON의 경우 items 파싱, XML은 <item> 카운트)
      final recordCount = _estimateRecordCount(resp.body);

      return BulkApiResult(
        apiId: target.id, apiName: target.name,
        success: true, statusCode: 200,
        message: '수집 완료', recordCount: recordCount,
      );

    } catch (e) {
      await RaceScheduleCache().logApiError(
        apiName: 'BulkSync-${target.id}',
        statusCode: 0,
        errorBody: e.toString(),
        requestUrl: '$_baseUrl${target.path}',
        encodingNote: 'Timeout/Exception',
      );
      return BulkApiResult(
        apiId: target.id, apiName: target.name,
        success: false, statusCode: 0,
        message: e.toString().substring(0, e.toString().length.clamp(0, 100)),
        recordCount: 0,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  저장된 Raw JSON 데이터 조회 (물리 엔진 바인딩용)
  // ─────────────────────────────────────────────────────────────────────
  Future<String?> getCachedData(String apiId) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayStr();

    // 오늘 데이터 우선
    String? data = prefs.getString('$_prefixBulk${apiId}_$today');
    if (data != null) return data;

    // 최근 7일 이내 탐색 (TTL)
    for (int i = 1; i <= 7; i++) {
      final d = DateTime.now().subtract(Duration(days: i));
      final dateStr = '${d.year}${d.month.toString().padLeft(2,'0')}${d.day.toString().padLeft(2,'0')}';
      data = prefs.getString('$_prefixBulk${apiId}_$dateStr');
      if (data != null) {
        if (kDebugMode) {
          debugPrint('[BulkSync] $apiId — 오늘 데이터 없음, ${i}일 전 캐시 반환');
        }
        return data;
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────
  //  수집 현황 요약 조회 (관리자 UI용)
  // ─────────────────────────────────────────────────────────────────────
  Future<BulkSyncStatus> getStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRunStr = prefs.getString(_keyLastSync);
    final progressStr = prefs.getString(_keyProgress);
    final today = _todayStr();

    int cachedToday = 0;
    for (final target in apiTargets) {
      if (prefs.containsKey('$_prefixBulk${target.id}_$today')) {
        cachedToday++;
      }
    }

    Map<String, dynamic>? lastProgress;
    if (progressStr != null) {
      try { lastProgress = jsonDecode(progressStr); } catch (_) {}
    }

    return BulkSyncStatus(
      lastRunAt: lastRunStr != null ? DateTime.tryParse(lastRunStr) : null,
      cachedApiCount: cachedToday,
      totalApiCount: apiTargets.length,
      isRunning: _isRunning,
      currentApi: _currentApi,
      progress: progress,
      lastCompletedCount: (lastProgress?['completed'] as num?)?.toInt() ?? 0,
      lastFailedCount: (lastProgress?['failed'] as num?)?.toInt() ?? 0,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  만료 캐시 정리 (TTL=7일)
  // ─────────────────────────────────────────────────────────────────────
  Future<void> purgeExpiredCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys()
        .where((k) => k.startsWith(_prefixBulk))
        .toList();
    int removed = 0;
    final now = DateTime.now();
    for (final key in keys) {
      // 키 형식: bulk_sync_{apiId}_{YYYYMMDD} 또는 bulk_sync_ts_...
      final parts = key.split('_');
      if (parts.length < 2) continue;
      final dateStr = parts.last;
      if (dateStr.length != 8) continue;
      final y  = int.tryParse(dateStr.substring(0, 4));
      final mo = int.tryParse(dateStr.substring(4, 6));
      final d  = int.tryParse(dateStr.substring(6, 8));
      if (y == null || mo == null || d == null) continue;
      final cacheDate = DateTime(y, mo, d);
      if (now.difference(cacheDate) > _cacheTtl) {
        await prefs.remove(key);
        removed++;
      }
    }
    if (kDebugMode && removed > 0) {
      debugPrint('[BulkSync] 🧹 만료 캐시 $removed건 정리');
    }
  }

  // ── 유틸 ──────────────────────────────────────────────────────────────
  static String _todayStr() {
    final now = DateTime.now().toLocal();
    return '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}';
  }

  static int _estimateRecordCount(String body) {
    if (body.startsWith('{') || body.startsWith('[')) {
      // JSON: item 배열 카운트 근사
      return '<item>'.allMatches(body).length.clamp(0, 9999);
    }
    // XML: <item> 태그 카운트
    return '<item>'.allMatches(body).length;
  }

  void dispose() {
    _scheduleTimer?.cancel();
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  BulkApiTarget — API 호출 대상 정의
// ══════════════════════════════════════════════════════════════════════════
class BulkApiTarget {
  final String id;
  final String name;
  final String path;

  final Map<String, String> params;
  final bool needsDate; // rc_date 파라미터 자동 주입 여부

  const BulkApiTarget({
    required this.id,
    required this.name,
    required this.path,
    required this.params,
    required this.needsDate,
  });
}

// ══════════════════════════════════════════════════════════════════════════
//  BulkApiResult — 단일 API 호출 결과
// ══════════════════════════════════════════════════════════════════════════
class BulkApiResult {
  final String apiId;
  final String apiName;
  final bool   success;
  final int    statusCode;
  final String message;
  final int    recordCount;
  final bool   skipped;

  const BulkApiResult({
    required this.apiId,
    required this.apiName,
    required this.success,
    required this.statusCode,
    required this.message,
    required this.recordCount,
    this.skipped = false,
  });

  String get statusIcon => skipped ? '⏭️' : (success ? '✅' : '❌');
  String get statusLabel => skipped ? '스킵' : (success ? '성공' : '실패');
}

// ══════════════════════════════════════════════════════════════════════════
//  BulkSyncResult — 전체 실행 결과 요약
// ══════════════════════════════════════════════════════════════════════════
class BulkSyncResult {
  final bool   success;
  final String message;
  final int    completedCount;
  final int    failedCount;
  final List<BulkApiResult> details;
  final int    snapshotSavedCount; // Phase 2: 스냅샷 저장 성공 경주 수

  const BulkSyncResult({
    required this.success,
    required this.message,
    required this.completedCount,
    required this.failedCount,
    required this.details,
    this.snapshotSavedCount = 0,
  });
}

// ══════════════════════════════════════════════════════════════════════════
//  BulkSyncProgress — 진행 상황 (스트리밍 콜백용)
// ══════════════════════════════════════════════════════════════════════════
class BulkSyncProgress {
  final int    current;
  final int    total;
  final String apiName;
  final String apiId;
  final String phase; // 'API수집' | '스냅샷인젝션'

  const BulkSyncProgress({
    required this.current,
    required this.total,
    required this.apiName,
    required this.apiId,
    this.phase = 'API수집',
  });

  double get ratio => total > 0 ? current / total : 0.0;
}

// ══════════════════════════════════════════════════════════════════════════
//  BulkSyncStatus — 관리자 UI 표시용 현황
// ══════════════════════════════════════════════════════════════════════════
class BulkSyncStatus {
  final DateTime? lastRunAt;
  final int    cachedApiCount;
  final int    totalApiCount;
  final bool   isRunning;
  final String currentApi;
  final double progress;
  final int    lastCompletedCount;
  final int    lastFailedCount;

  const BulkSyncStatus({
    required this.lastRunAt,
    required this.cachedApiCount,
    required this.totalApiCount,
    required this.isRunning,
    required this.currentApi,
    required this.progress,
    required this.lastCompletedCount,
    required this.lastFailedCount,
  });

  String get lastRunLabel {
    if (lastRunAt == null) return '미실행';
    final t = lastRunAt!.toLocal();
    return '${t.month}/${t.day} ${t.hour.toString().padLeft(2,'0')}:'
        '${t.minute.toString().padLeft(2,'0')}';
  }

  String get nextWindowLabel {
    final now = DateTime.now().toLocal();
    DateTime next = DateTime(now.year, now.month, now.day, 2, 0); // 오늘 02:00
    if (now.hour >= 5) {
      next = next.add(const Duration(days: 1)); // 내일 02:00
    } else if (now.hour >= 2) {
      return '수집 창 진행 중 (02:00~05:00)';
    }
    final diff = next.difference(now);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return '${h}시간 ${m}분 후 (익일 02:00)';
  }
}
