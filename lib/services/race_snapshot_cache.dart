import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/race_models.dart';

// ══════════════════════════════════════════════════════════════════════════
//  RaceSnapshotCache  — 심야 배치 스냅샷 캐싱 레이어 (배치 아키텍처 v2.0)
//
//  ▸ 목적:
//    경주별 출전표·배당·AI 스코어 전체를 당일 심야 배치로 사전 수집하여
//    SharedPreferences 기반 로컬 DB에 JSON 직렬화 형태로 저장.
//    유저가 경주 탭 진입 시 외부 API 호출 없이 0.1초 이내 즉시 반환.
//
//  ▸ 데이터 계층 (우선순위):
//    [1] 심야 배치 스냅샷 (batch_snap:) → TTL 36시간
//    [2] 수동 강제 싱크 스냅샷 (manual_snap:) → TTL 24시간
//    [3] 온라인 fallback (기존 API 호출) → Cache Miss 시만 허용
//
//  ▸ 키 네이밍:
//    batch_snap:{venueCode}:{date}:{raceNo}         → HorseEntrySnapshot JSON
//    batch_snap_ts:{venueCode}:{date}:{raceNo}       → 저장 Unix ms
//    batch_snap_meta:{venueCode}:{date}              → 경주 메타 목록
//    batch_sync_log:{date}                           → 배치 실행 로그
//    batch_sync_last:{venueCode}                     → 마지막 성공 싱크 시각
//    batch_perf:{venueCode}:{date}:{raceNo}          → 성능 측정 로그
//
//  ▸ TTL: 스냅샷 36시간 (경주 당일 + 다음 날 새벽까지 보존)
// ══════════════════════════════════════════════════════════════════════════

/// 단일 경주 출전마 스냅샷 DTO
class HorseEntrySnapshot {
  final int gateNo;
  final String horseName;
  final String jockeyName;
  final String trainerName;
  final double wgBudam;
  final int weight;
  final int weightChange;
  final double odds;
  final double plcOdds;
  final double speedStat;
  final double staminaStat;
  final double formStat;
  final double trackFitStat;
  final double baseScore;
  final double finalScore;
  final String recentRecord;
  final double rcWins;
  final double jockeyRcWins;
  final double g1fRating;
  final double rating;
  final int prizeTotal6Month;
  final int prizeTotal1Year;
  final String horseRegNo;
  final int prizeWin;
  final int prize2nd;
  final int prize3rd;

  const HorseEntrySnapshot({
    required this.gateNo,
    required this.horseName,
    required this.jockeyName,
    required this.trainerName,
    this.wgBudam = 55.0,
    this.weight = 0,
    this.weightChange = 0,
    this.odds = 0.0,
    this.plcOdds = 0.0,
    this.speedStat = 50.0,
    this.staminaStat = 50.0,
    this.formStat = 50.0,
    this.trackFitStat = 50.0,
    this.baseScore = 50.0,
    this.finalScore = 50.0,
    this.recentRecord = '',
    this.rcWins = 0.0,
    this.jockeyRcWins = 0.0,
    this.g1fRating = 0.0,
    this.rating = 0.0,
    this.prizeTotal6Month = 0,
    this.prizeTotal1Year = 0,
    this.horseRegNo = '',
    this.prizeWin = 0,
    this.prize2nd = 0,
    this.prize3rd = 0,
  });

  Map<String, dynamic> toJson() => {
    'gateNo':          gateNo,
    'horseName':       horseName,
    'jockeyName':      jockeyName,
    'trainerName':     trainerName,
    'wgBudam':         wgBudam,
    'weight':          weight,
    'weightChange':    weightChange,
    'odds':            odds,
    'plcOdds':         plcOdds,
    'speedStat':       speedStat,
    'staminaStat':     staminaStat,
    'formStat':        formStat,
    'trackFitStat':    trackFitStat,
    'baseScore':       baseScore,
    'finalScore':      finalScore,
    'recentRecord':    recentRecord,
    'rcWins':          rcWins,
    'jockeyRcWins':    jockeyRcWins,
    'g1fRating':       g1fRating,
    'rating':          rating,
    'prizeTotal6Month': prizeTotal6Month,
    'prizeTotal1Year': prizeTotal1Year,
    'horseRegNo':      horseRegNo,
    'prizeWin':        prizeWin,
    'prize2nd':        prize2nd,
    'prize3rd':        prize3rd,
  };

  factory HorseEntrySnapshot.fromJson(Map<String, dynamic> j) =>
      HorseEntrySnapshot(
        gateNo:          (j['gateNo']          as int?)    ?? 0,
        horseName:       (j['horseName']        as String?) ?? '',
        jockeyName:      (j['jockeyName']       as String?) ?? '',
        trainerName:     (j['trainerName']      as String?) ?? '',
        wgBudam:         (j['wgBudam']          as num?)?.toDouble()  ?? 55.0,
        weight:          (j['weight']           as int?)    ?? 0,
        weightChange:    (j['weightChange']     as int?)    ?? 0,
        odds:            (j['odds']             as num?)?.toDouble()  ?? 0.0,
        plcOdds:         (j['plcOdds']          as num?)?.toDouble()  ?? 0.0,
        speedStat:       (j['speedStat']        as num?)?.toDouble()  ?? 50.0,
        staminaStat:     (j['staminaStat']      as num?)?.toDouble()  ?? 50.0,
        formStat:        (j['formStat']         as num?)?.toDouble()  ?? 50.0,
        trackFitStat:    (j['trackFitStat']     as num?)?.toDouble()  ?? 50.0,
        baseScore:       (j['baseScore']        as num?)?.toDouble()  ?? 50.0,
        finalScore:      (j['finalScore']       as num?)?.toDouble()  ?? 50.0,
        recentRecord:    (j['recentRecord']     as String?) ?? '',
        rcWins:          (j['rcWins']           as num?)?.toDouble()  ?? 0.0,
        jockeyRcWins:    (j['jockeyRcWins']     as num?)?.toDouble()  ?? 0.0,
        g1fRating:       (j['g1fRating']        as num?)?.toDouble()  ?? 0.0,
        rating:          (j['rating']           as num?)?.toDouble()  ?? 0.0,
        prizeTotal6Month:(j['prizeTotal6Month'] as int?)    ?? 0,
        prizeTotal1Year: (j['prizeTotal1Year']  as int?)    ?? 0,
        horseRegNo:      (j['horseRegNo']       as String?) ?? '',
        prizeWin:        (j['prizeWin']         as int?)    ?? 0,
        prize2nd:        (j['prize2nd']         as int?)    ?? 0,
        prize3rd:        (j['prize3rd']         as int?)    ?? 0,
      );

  /// HorseEntrySnapshot → HorseEntry 변환
  HorseEntry toHorseEntry() => HorseEntry(
    gateNo:         gateNo,
    horseName:      horseName,
    jockeyName:     jockeyName,
    trainerName:    trainerName,
    weight:         weight,
    weightChange:   weightChange,
    rating:         rating,
    speedStat:      speedStat,
    staminaStat:    staminaStat,
    formStat:       formStat,
    trackFitStat:   trackFitStat,
    baseScore:      baseScore,
    userBonus:      0.0,
    recentRecord:   recentRecord,
    odds:           odds,
    plcOdds:        plcOdds,
    isCancelled:    false,
    horseRegNo:     horseRegNo,
    rcWins:         rcWins,
    jockeyRcWins:   jockeyRcWins,
    wgBudam:        wgBudam,
    g1fRating:      g1fRating,
    prizeWin:       prizeWin,
    prize2nd:       prize2nd,
    prize3rd:       prize3rd,
    prize4th:       0,
    prize5th:       0,
    prizeTotalCareer: 0,
    prizeTotal1Year: prizeTotal1Year,
    prizeTotal6Month: prizeTotal6Month,
  );

  /// HorseEntry → HorseEntrySnapshot 변환
  static HorseEntrySnapshot fromHorseEntry(HorseEntry h) =>
      HorseEntrySnapshot(
        gateNo:          h.gateNo,
        horseName:       h.horseName,
        jockeyName:      h.jockeyName,
        trainerName:     h.trainerName,
        wgBudam:         h.wgBudam,
        weight:          h.weight,
        weightChange:    h.weightChange,
        odds:            h.odds,
        plcOdds:         h.plcOdds,
        speedStat:       h.speedStat,
        staminaStat:     h.staminaStat,
        formStat:        h.formStat,
        trackFitStat:    h.trackFitStat,
        baseScore:       h.baseScore,
        finalScore:      h.finalScore,
        recentRecord:    h.recentRecord,
        rcWins:          h.rcWins,
        jockeyRcWins:    h.jockeyRcWins,
        g1fRating:       h.g1fRating,
        rating:          h.rating,
        prizeTotal6Month: h.prizeTotal6Month,
        prizeTotal1Year: h.prizeTotal1Year,
        horseRegNo:      h.horseRegNo,
        prizeWin:        h.prizeWin,
        prize2nd:        h.prize2nd,
        prize3rd:        h.prize3rd,
      );
}

/// 단일 경주 배치 스냅샷 전체 컨테이너
class RaceBatchSnapshot {
  final String venueCode;
  final String date;             // 'YYYYMMDD'
  final String raceNo;
  final List<HorseEntrySnapshot> horses;
  final DateTime savedAt;
  final String source;           // 'batch' | 'manual' | 'online_fallback'
  final int fetchDurationMs;     // API 호출 소요 시간 (ms)

  const RaceBatchSnapshot({
    required this.venueCode,
    required this.date,
    required this.raceNo,
    required this.horses,
    required this.savedAt,
    required this.source,
    this.fetchDurationMs = 0,
  });

  Map<String, dynamic> toJson() => {
    'venueCode':       venueCode,
    'date':            date,
    'raceNo':          raceNo,
    'horses':          horses.map((h) => h.toJson()).toList(),
    'savedAt':         savedAt.toIso8601String(),
    'source':          source,
    'fetchDurationMs': fetchDurationMs,
  };

  factory RaceBatchSnapshot.fromJson(Map<String, dynamic> j) =>
      RaceBatchSnapshot(
        venueCode: (j['venueCode'] as String?) ?? '',
        date:      (j['date']      as String?) ?? '',
        raceNo:    (j['raceNo']    as String?) ?? '',
        horses:    ((j['horses'] as List<dynamic>?) ?? [])
            .map((e) => HorseEntrySnapshot.fromJson(
                e as Map<String, dynamic>))
            .toList(),
        savedAt:   DateTime.tryParse((j['savedAt'] as String?) ?? '') ??
                   DateTime.now(),
        source:    (j['source']          as String?) ?? 'unknown',
        fetchDurationMs: (j['fetchDurationMs'] as int?) ?? 0,
      );
}

/// 배치 싱크 실행 결과 로그
class BatchSyncLog {
  final DateTime runAt;
  final int totalRaces;
  final int successRaces;
  final int failedRaces;
  final int totalFetchMs;       // 전체 API 호출 소요 시간
  final bool isForced;          // 관리자 수동 강제 실행 여부
  final String triggerSource;   // 'cron' | 'admin_manual' | 'admin_text'

  const BatchSyncLog({
    required this.runAt,
    required this.totalRaces,
    required this.successRaces,
    required this.failedRaces,
    required this.totalFetchMs,
    this.isForced = false,
    this.triggerSource = 'cron',
  });

  Map<String, dynamic> toJson() => {
    'runAt':         runAt.toIso8601String(),
    'totalRaces':    totalRaces,
    'successRaces':  successRaces,
    'failedRaces':   failedRaces,
    'totalFetchMs':  totalFetchMs,
    'isForced':      isForced,
    'triggerSource': triggerSource,
  };

  factory BatchSyncLog.fromJson(Map<String, dynamic> j) => BatchSyncLog(
    runAt: DateTime.tryParse((j['runAt'] as String?) ?? '') ?? DateTime.now(),
    totalRaces:   (j['totalRaces']   as int?) ?? 0,
    successRaces: (j['successRaces'] as int?) ?? 0,
    failedRaces:  (j['failedRaces']  as int?) ?? 0,
    totalFetchMs: (j['totalFetchMs'] as int?) ?? 0,
    isForced:     (j['isForced']     as bool?) ?? false,
    triggerSource:(j['triggerSource'] as String?) ?? 'cron',
  );

  String get summary =>
    '${runAt.month}/${runAt.day} ${runAt.hour.toString().padLeft(2,'0')}:${runAt.minute.toString().padLeft(2,'0')} | '
    '$successRaces/$totalRaces 성공 | ${(totalFetchMs / 1000).toStringAsFixed(1)}s | $triggerSource';
}

// ══════════════════════════════════════════════════════════════════════════
//  RaceSnapshotCache 싱글톤 — 핵심 캐싱 레이어
// ══════════════════════════════════════════════════════════════════════════
class RaceSnapshotCache {
  static final RaceSnapshotCache _instance = RaceSnapshotCache._internal();
  factory RaceSnapshotCache() => _instance;
  RaceSnapshotCache._internal();

  SharedPreferences? _prefs;

  // ── 캐시 키 접두어 ──────────────────────────────────────────────────────
  static const String _kSnap      = 'batch_snap:';       // 경주별 스냅샷
  static const String _kSnapTs    = 'batch_snap_ts:';    // 저장 타임스탬프
  static const String _kMeta      = 'batch_snap_meta:';  // 날짜별 경주 메타
  static const String _kSyncLog   = 'batch_sync_log:';   // 배치 실행 로그
  static const String _kSyncLast  = 'batch_sync_last:';  // 마지막 싱크 시각
  static const String _kOddsSnap  = 'odds_snap:';        // 배당 실시간 스냅샷
  static const String _kOddsTs    = 'odds_snap_ts:';     // 배당 스냅샷 타임스탬프

  // ── TTL 설정 ────────────────────────────────────────────────────────────
  // 스냅샷: 36시간 (경주 당일 + 다음날 새벽)
  static const Duration _snapTtl  = Duration(hours: 36);
  // 배당: 5분 (실시간 폴링 캐시)
  static const Duration _oddsTtl  = Duration(minutes: 5);

  // ── 초기화 ──────────────────────────────────────────────────────────────
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ══════════════════════════════════════════════════════════════════════
  //  [WRITE] 심야 배치 스냅샷 저장
  //
  //  파이프라인: API → enrichHorseStats() → saveRaceSnapshot()
  //  호출: KraBulkSyncService.runBulkSync() 완료 후
  // ══════════════════════════════════════════════════════════════════════
  Future<void> saveRaceSnapshot({
    required String venueCode,
    required DateTime date,
    required String raceNo,
    required List<HorseEntry> horses,
    required String source,
    int fetchDurationMs = 0,
  }) async {
    await init();
    final dateStr = _fmtDate(date);
    final snapKey = '$_kSnap$venueCode:$dateStr:$raceNo';
    final tsKey   = '$_kSnapTs$venueCode:$dateStr:$raceNo';

    final snap = RaceBatchSnapshot(
      venueCode: venueCode,
      date:      dateStr,
      raceNo:    raceNo,
      horses:    horses.map(HorseEntrySnapshot.fromHorseEntry).toList(),
      savedAt:   DateTime.now(),
      source:    source,
      fetchDurationMs: fetchDurationMs,
    );

    await _prefs!.setString(snapKey, jsonEncode(snap.toJson()));
    await _prefs!.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);

    // 메타 인덱스 업데이트
    await _updateMetaIndex(venueCode: venueCode, dateStr: dateStr, raceNo: raceNo);

    if (kDebugMode) {
      debugPrint('[SnapCache] 저장: $venueCode/$dateStr/$raceNo '
          '(${horses.length}두, ${fetchDurationMs}ms, src=$source)');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  [READ] 경주 스냅샷 로드 (메인 캐시 조회)
  //
  //  반환:
  //    - List<HorseEntry> : 캐시 히트 → 즉시 반환 (목표: <100ms)
  //    - null             : 캐시 미스 → 온라인 fallback 허용
  // ══════════════════════════════════════════════════════════════════════
  Future<List<HorseEntry>?> loadRaceSnapshot({
    required String venueCode,
    required DateTime date,
    required String raceNo,
  }) async {
    final sw = Stopwatch()..start();
    await init();

    final dateStr = _fmtDate(date);
    final snapKey = '$_kSnap$venueCode:$dateStr:$raceNo';
    final tsKey   = '$_kSnapTs$venueCode:$dateStr:$raceNo';

    final raw = _prefs!.getString(snapKey);
    if (raw == null) {
      if (kDebugMode) {
        debugPrint('[SnapCache] MISS: $venueCode/$dateStr/$raceNo');
      }
      return null;  // → 온라인 fallback
    }

    // TTL 체크
    final ts = _prefs!.getInt(tsKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age > _snapTtl.inMilliseconds) {
      if (kDebugMode) {
        debugPrint('[SnapCache] EXPIRED: $venueCode/$dateStr/$raceNo '
            '(age=${(age / 3600000).toStringAsFixed(1)}h > 36h)');
      }
      return null;  // → 온라인 fallback
    }

    try {
      final snap = RaceBatchSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      final horses = snap.horses.map((s) => s.toHorseEntry()).toList();
      sw.stop();

      if (kDebugMode) {
        debugPrint('[SnapCache] HIT: $venueCode/$dateStr/$raceNo '
            '→ ${horses.length}두 (${sw.elapsedMilliseconds}ms) '
            '[src=${snap.source}]');
      }

      // 성능 로그 기록
      await _recordPerfLog(
        venueCode: venueCode, dateStr: dateStr, raceNo: raceNo,
        hitMs: sw.elapsedMilliseconds, source: snap.source,
      );

      return horses;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SnapCache] PARSE ERROR: $e');
      }
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  [READ] 배당 스냅샷 로드/저장 (5분 TTL 실시간 캐시)
  // ══════════════════════════════════════════════════════════════════════
  Future<List<HorseEntry>?> loadOddsSnapshot({
    required String venueCode,
    required DateTime date,
    required String raceNo,
  }) async {
    await init();
    final key   = '$_kOddsSnap$venueCode:${_fmtDate(date)}:$raceNo';
    final tsKey = '$_kOddsTs$venueCode:${_fmtDate(date)}:$raceNo';
    final raw = _prefs!.getString(key);
    if (raw == null) return null;
    final ts  = _prefs!.getInt(tsKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age > _oddsTtl.inMilliseconds) return null;
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => HorseEntrySnapshot.fromJson(e as Map<String, dynamic>)
              .toHorseEntry())
          .toList();
      return list;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveOddsSnapshot({
    required String venueCode,
    required DateTime date,
    required String raceNo,
    required List<HorseEntry> horses,
  }) async {
    await init();
    final key   = '$_kOddsSnap$venueCode:${_fmtDate(date)}:$raceNo';
    final tsKey = '$_kOddsTs$venueCode:${_fmtDate(date)}:$raceNo';
    final snapList = horses.map(HorseEntrySnapshot.fromHorseEntry).toList();
    await _prefs!.setString(key, jsonEncode(snapList.map((s) => s.toJson()).toList()));
    await _prefs!.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
  }

  // ══════════════════════════════════════════════════════════════════════
  //  [STATUS] 캐시 상태 조회 (관리자 패널용)
  // ══════════════════════════════════════════════════════════════════════

  /// 특정 경주의 캐시 유효 여부
  Future<bool> hasValidSnapshot({
    required String venueCode,
    required DateTime date,
    required String raceNo,
  }) async {
    await init();
    final dateStr = _fmtDate(date);
    final tsKey   = '$_kSnapTs$venueCode:$dateStr:$raceNo';
    final snapKey = '$_kSnap$venueCode:$dateStr:$raceNo';
    if (_prefs!.getString(snapKey) == null) return false;
    final ts  = _prefs!.getInt(tsKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    return age < _snapTtl.inMilliseconds;
  }

  /// 날짜별 캐시된 경주 목록 (마지막 배치 결과 확인용)
  Future<List<String>> getCachedRaceNos({
    required String venueCode,
    required DateTime date,
  }) async {
    await init();
    final dateStr = _fmtDate(date);
    final metaKey = '$_kMeta$venueCode:$dateStr';
    final raw = _prefs!.getString(metaKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// 마지막 성공 배치 시각 반환
  Future<DateTime?> getLastSyncAt(String venueCode) async {
    await init();
    final raw = _prefs!.getString('$_kSyncLast$venueCode');
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// 배치 실행 로그 목록 (최근 10건)
  Future<List<BatchSyncLog>> getSyncLogs() async {
    await init();
    final today = _fmtDate(DateTime.now());
    final raw = _prefs!.getString('$_kSyncLog$today');
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => BatchSyncLog.fromJson(e as Map<String, dynamic>))
          .toList();
      return list.reversed.take(10).toList();
    } catch (_) {
      return [];
    }
  }

  /// 전체 캐시 통계 (관리자 대시보드용)
  Future<Map<String, dynamic>> getCacheStats() async {
    await init();
    final allKeys = _prefs!.getKeys();
    final snapKeys = allKeys.where((k) => k.startsWith(_kSnap) && !k.startsWith(_kSnapTs)).toList();
    final oddsKeys = allKeys.where((k) => k.startsWith(_kOddsSnap) && !k.startsWith(_kOddsTs)).toList();

    int validSnaps = 0;
    int expiredSnaps = 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final key in snapKeys) {
      final tsKey = key.replaceFirst(_kSnap, _kSnapTs);
      final ts = _prefs!.getInt(tsKey) ?? 0;
      final age = now - ts;
      if (age < _snapTtl.inMilliseconds) {
        validSnaps++;
      } else {
        expiredSnaps++;
      }
    }

    return {
      'totalSnapshots': snapKeys.length,
      'validSnapshots': validSnaps,
      'expiredSnapshots': expiredSnaps,
      'oddsSnapshots': oddsKeys.length,
      'totalKeys': allKeys.length,
    };
  }

  // ══════════════════════════════════════════════════════════════════════
  //  [WRITE] 배치 싱크 로그 기록
  // ══════════════════════════════════════════════════════════════════════
  Future<void> recordSyncLog(BatchSyncLog log) async {
    await init();
    final dateStr = _fmtDate(log.runAt);
    final key = '$_kSyncLog$dateStr';
    final existing = _prefs!.getString(key);
    List<dynamic> list = [];
    if (existing != null) {
      try { list = jsonDecode(existing) as List<dynamic>; } catch (_) {}
    }
    list.add(log.toJson());
    // 최대 20건 보존
    if (list.length > 20) list = list.sublist(list.length - 20);
    await _prefs!.setString(key, jsonEncode(list));
    await _prefs!.setString(
        '$_kSyncLast${log.runAt}', log.runAt.toIso8601String());
  }

  /// 마지막 성공 싱크 시각 업데이트
  Future<void> updateLastSyncAt(String venueCode) async {
    await init();
    await _prefs!.setString(
        '$_kSyncLast$venueCode', DateTime.now().toIso8601String());
  }

  // ══════════════════════════════════════════════════════════════════════
  //  [EVICT] 캐시 강제 무효화 (관리자 수동 갱신 후 Cache Evict & Refresh)
  // ══════════════════════════════════════════════════════════════════════

  /// 특정 경주 캐시 무효화
  Future<void> evictRaceSnapshot({
    required String venueCode,
    required DateTime date,
    required String raceNo,
  }) async {
    await init();
    final dateStr = _fmtDate(date);
    await _prefs!.remove('$_kSnap$venueCode:$dateStr:$raceNo');
    await _prefs!.remove('$_kSnapTs$venueCode:$dateStr:$raceNo');
    if (kDebugMode) {
      debugPrint('[SnapCache] EVICT: $venueCode/$dateStr/$raceNo');
    }
  }

  /// 경주장+날짜 전체 캐시 무효화 (강제 벌크싱크 전 호출)
  Future<int> evictAllForDate({
    required String venueCode,
    required DateTime date,
  }) async {
    await init();
    final dateStr = _fmtDate(date);
    final allKeys = _prefs!.getKeys().where(
        (k) => k.startsWith('$_kSnap$venueCode:$dateStr:')).toList();
    for (final key in allKeys) {
      await _prefs!.remove(key);
      // 타임스탬프도 함께 제거
      final tsKey = key.replaceFirst(_kSnap, _kSnapTs);
      await _prefs!.remove(tsKey);
    }
    if (kDebugMode) {
      debugPrint('[SnapCache] EVICT ALL: $venueCode/$dateStr → ${allKeys.length}건 제거');
    }
    return allKeys.length;
  }

  /// 만료된 캐시 정리 (앱 시작 시 1회 실행)
  Future<int> purgeExpired() async {
    await init();
    final allKeys = _prefs!.getKeys()
        .where((k) => k.startsWith(_kSnap) && !k.startsWith(_kSnapTs))
        .toList();
    int removed = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final key in allKeys) {
      final tsKey = key.replaceFirst(_kSnap, _kSnapTs);
      final ts = _prefs!.getInt(tsKey) ?? 0;
      if (now - ts > _snapTtl.inMilliseconds) {
        await _prefs!.remove(key);
        await _prefs!.remove(tsKey);
        removed++;
      }
    }
    if (removed > 0 && kDebugMode) {
      debugPrint('[SnapCache] PURGE: 만료 캐시 $removed건 제거');
    }
    return removed;
  }

  // ── 내부 헬퍼 ─────────────────────────────────────────────────────────

  Future<void> _updateMetaIndex({
    required String venueCode,
    required String dateStr,
    required String raceNo,
  }) async {
    final metaKey = '$_kMeta$venueCode:$dateStr';
    final existing = _prefs!.getString(metaKey);
    List<String> list = [];
    if (existing != null) {
      try { list = (jsonDecode(existing) as List<dynamic>).cast<String>(); }
      catch (_) {}
    }
    if (!list.contains(raceNo)) {
      list.add(raceNo);
      list.sort();
      await _prefs!.setString(metaKey, jsonEncode(list));
    }
  }

  Future<void> _recordPerfLog({
    required String venueCode,
    required String dateStr,
    required String raceNo,
    required int hitMs,
    required String source,
  }) async {
    // 성능 로그는 디버그 전용 (프로덕션 오버헤드 최소화)
    if (!kDebugMode) return;
    final key = 'batch_perf:$venueCode:$dateStr:$raceNo';
    await _prefs!.setString(key, jsonEncode({
      'hitMs': hitMs,
      'source': source,
      'at': DateTime.now().toIso8601String(),
    }));
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2,'0')}${d.day.toString().padLeft(2,'0')}';
}
