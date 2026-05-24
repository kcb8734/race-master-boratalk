import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/race_models.dart';

// ══════════════════════════════════════════════════════════════════════════
//  RaceScheduleCache — 경주 시간표 로컬 타임스탬프 동기화 시스템
//
//  ▸ 목적: KRA API 장애 시 마지막 성공 응답의 시간표를 로컬에 보존하여
//          Mock 데이터의 시간 꼬임 현상을 100% 차단
//
//  ▸ 동작 원리:
//    ① API 호출 성공 시  → 경주별 startTime(Unix ms) 스냅샷을 저장
//    ② API 장애 감지 시  → 저장된 스냅샷으로 Mock RaceInfo.startTime 교정
//    ③ 목요일 출전표 파싱 성공 시 → 해당 주 스냅샷을 갱신 (정밀 기준값)
//
//  ▸ 저장 키 구조:
//    race_cache:{venueCode}:{dateStr}    → JSON 시간표 스냅샷
//    race_cache_ts:{venueCode}:{dateStr} → 스냅샷 저장 Unix ms
//    race_cache_src:{venueCode}:{dateStr}→ 데이터 출처 (api/scrape/mock)
//
//  ▸ TTL: 경주 당일 기준 +3일 (이후 자동 만료 처리)
// ══════════════════════════════════════════════════════════════════════════
class RaceScheduleCache {
  // ── 싱글톤 ──────────────────────────────────────────────────────────────
  static final RaceScheduleCache _instance = RaceScheduleCache._internal();
  factory RaceScheduleCache() => _instance;
  RaceScheduleCache._internal();

  // ── SharedPreferences 인스턴스 (lazy init) ──────────────────────────────
  SharedPreferences? _prefs;

  // ── 캐시 TTL: 경주일 기준 3일 후 만료 ───────────────────────────────────
  static const Duration _cacheTtl = Duration(days: 3);

  // ── 저장 키 접두어 ─────────────────────────────────────────────────────
  static const String _prefixData   = 'race_cache:';
  static const String _prefixTs     = 'race_cache_ts:';
  static const String _prefixSrc    = 'race_cache_src:';
  static const String _prefixApiLog = 'kra_api_log';

  // ─────────────────────────────────────────────────────────────────────────
  //  초기화
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  저장 — API/크롤링 성공 시 호출
  //
  //  [races]     : 성공적으로 파싱한 RaceInfo 목록
  //  [venueCode] : 경주장 코드 ('1'=서울, '2'=부산경남, '3'=제주)
  //  [date]      : 경주 날짜
  //  [source]    : 데이터 출처 ('api' | 'scrape' | 'mock')
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> saveSnapshot({
    required List<RaceInfo> races,
    required String venueCode,
    required DateTime date,
    required String source,
  }) async {
    await init();
    final dateStr = _formatDate(date);
    final key = '$_prefixData$venueCode:$dateStr';
    final tsKey = '$_prefixTs$venueCode:$dateStr';
    final srcKey = '$_prefixSrc$venueCode:$dateStr';

    // 스냅샷 데이터: 경주번호 → {startTime, distance, condition, isSpecialRace, specialRaceName}
    final snapshot = <String, dynamic>{};
    for (final race in races) {
      snapshot[race.raceNo] = {
        'startTime':      race.startTime,
        'startUnixMs':    _toUnixMs(date, race.startTime),
        'distance':       race.distance,
        'condition':      race.condition,
        'grade':          race.grade,
        'isSpecialRace':  race.isSpecialRace,
        'specialRaceName': race.specialRaceName,
        'totalHorses':    race.totalHorses,
        'trackCondition': race.trackCondition,
      };
    }

    await _prefs!.setString(key, jsonEncode(snapshot));
    await _prefs!.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
    await _prefs!.setString(srcKey, source);

    if (kDebugMode) {
      debugPrint(
        '[RaceScheduleCache] 💾 스냅샷 저장 [$source] '
        '$venueCode/$dateStr → ${races.length}경주',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  조회 — API 장애 시 캐시된 시간표로 Mock RaceInfo 교정
  //
  //  반환값: 경주번호 → 교정 데이터 맵 (없으면 null)
  // ─────────────────────────────────────────────────────────────────────────
  Future<Map<String, CachedRaceEntry>?> loadSnapshot({
    required String venueCode,
    required DateTime date,
  }) async {
    await init();
    final dateStr = _formatDate(date);
    final key  = '$_prefixData$venueCode:$dateStr';
    final tsKey = '$_prefixTs$venueCode:$dateStr';

    final raw = _prefs!.getString(key);
    if (raw == null) {
      if (kDebugMode) {
        debugPrint('[RaceScheduleCache] ⚠️ 캐시 없음: $venueCode/$dateStr');
      }
      return null;
    }

    // TTL 체크: 경주일 +3일 이후 만료
    final savedTs = _prefs!.getInt(tsKey) ?? 0;
    final savedAt = DateTime.fromMillisecondsSinceEpoch(savedTs);
    final expireAt = DateTime(date.year, date.month, date.day)
        .add(_cacheTtl);
    if (DateTime.now().isAfter(expireAt)) {
      if (kDebugMode) {
        debugPrint('[RaceScheduleCache] ⏰ 캐시 만료: $venueCode/$dateStr');
      }
      await _prefs!.remove(key);
      await _prefs!.remove(tsKey);
      return null;
    }

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, CachedRaceEntry>{};
      for (final e in map.entries) {
        result[e.key] = CachedRaceEntry.fromJson(e.value as Map<String, dynamic>);
      }
      final src = _prefs!.getString('$_prefixSrc$venueCode:$dateStr') ?? 'unknown';
      if (kDebugMode) {
        debugPrint(
          '[RaceScheduleCache] ✅ 캐시 히트 [$src] '
          '$venueCode/$dateStr → ${result.length}경주 '
          '(저장: ${_formatDateTime(savedAt)})',
        );
      }
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RaceScheduleCache] ❌ 캐시 파싱 오류: $e');
      }
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Mock 경주 목록에 캐시 타임스탬프 적용
  //
  //  API 장애 시 Mock 데이터가 생성된 후 이 메서드로 시간표를 교정한다.
  //  ① 캐시에 해당 경주가 있으면 → 캐시 startTime으로 교체
  //  ② 없으면 → 기존 Mock startTime 유지
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<RaceInfo>> applyCachedTimestamps({
    required List<RaceInfo> mockRaces,
    required String venueCode,
    required DateTime date,
  }) async {
    final cached = await loadSnapshot(venueCode: venueCode, date: date);
    if (cached == null || cached.isEmpty) {
      // 캐시 없음 → Mock 그대로 반환
      return mockRaces;
    }

    final now = DateTime.now();
    return mockRaces.map((race) {
      final entry = cached[race.raceNo];
      if (entry == null) return race;

      // 캐시 타임스탬프로 isFinished/isUpcoming 재계산
      final parts = entry.startTime.split(':');
      bool isFinished = race.isFinished;
      bool isUpcoming = race.isUpcoming;

      if (parts.length == 2) {
        final raceTime = DateTime(
          date.year, date.month, date.day,
          int.tryParse(parts[0]) ?? 0,
          int.tryParse(parts[1]) ?? 0,
        );
        final diffMin = raceTime.difference(now).inMinutes;
        isFinished = diffMin < -30;
        isUpcoming = !isFinished && diffMin >= 0 && diffMin <= 30;
      }

      return RaceInfo(
        raceNo:          race.raceNo,
        raceName:        entry.isSpecialRace ? entry.specialRaceName : race.raceName,
        startTime:       entry.startTime,           // ← 캐시 시간 적용
        distance:        entry.distance > 0 ? entry.distance : race.distance,
        condition:       entry.condition.isNotEmpty ? entry.condition : race.condition,
        grade:           entry.grade.isNotEmpty ? entry.grade : race.grade,
        venueCode:       race.venueCode,
        venueName:       race.venueName,
        raceDate:        race.raceDate,
        totalHorses:     entry.totalHorses > 0 ? entry.totalHorses : race.totalHorses,
        trackCondition:  entry.trackCondition.isNotEmpty
            ? entry.trackCondition : race.trackCondition,
        isFinished:      isFinished,
        isUpcoming:      isUpcoming,
        activateTime:    race.activateTime,
        isSpecialRace:   entry.isSpecialRace,
        specialRaceName: entry.specialRaceName,
      );
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  캐시 메타 정보 조회 (UI 표시용)
  // ─────────────────────────────────────────────────────────────────────────
  Future<CacheMetaInfo> getCacheInfo({
    required String venueCode,
    required DateTime date,
  }) async {
    await init();
    final dateStr = _formatDate(date);
    final tsKey  = '$_prefixTs$venueCode:$dateStr';
    final srcKey = '$_prefixSrc$venueCode:$dateStr';
    final dataKey = '$_prefixData$venueCode:$dateStr';

    final hasCache = _prefs!.containsKey(dataKey);
    final savedTs  = _prefs!.getInt(tsKey) ?? 0;
    final source   = _prefs!.getString(srcKey) ?? 'none';

    return CacheMetaInfo(
      hasCache:  hasCache,
      savedAt:   savedTs > 0
          ? DateTime.fromMillisecondsSinceEpoch(savedTs)
          : null,
      source:    source,
      venueCode: venueCode,
      dateStr:   dateStr,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  API 에러 로그 기록 (투명성 확보)
  //  최근 50건 순환 저장
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> logApiError({
    required String apiName,
    required int statusCode,
    required String errorBody,
    required String requestUrl,
    String? serviceKeyMasked,
    String? encodingNote,
  }) async {
    await init();
    final existing = _prefs!.getStringList(_prefixApiLog) ?? [];
    final entry = jsonEncode({
      'ts':         DateTime.now().toIso8601String(),
      'api':        apiName,
      'status':     statusCode,
      'body':       errorBody.length > 200 ? errorBody.substring(0, 200) : errorBody,
      'url':        _maskServiceKey(requestUrl),
      'keyNote':    serviceKeyMasked ?? '',
      'encNote':    encodingNote ?? '',
    });
    existing.add(entry);
    // 최대 50건 유지 (FIFO)
    final trimmed = existing.length > 50
        ? existing.sublist(existing.length - 50)
        : existing;
    await _prefs!.setStringList(_prefixApiLog, trimmed);
  }

  /// 최근 API 에러 로그 조회 (최신순)
  Future<List<ApiErrorLogEntry>> getApiErrorLogs({int limit = 20}) async {
    await init();
    final raw = _prefs!.getStringList(_prefixApiLog) ?? [];
    return raw.reversed
        .take(limit)
        .map((e) {
          try {
            final m = jsonDecode(e) as Map<String, dynamic>;
            return ApiErrorLogEntry(
              timestamp:    DateTime.tryParse(m['ts'] as String? ?? '') ?? DateTime.now(),
              apiName:      m['api'] as String? ?? '',
              statusCode:   (m['status'] as num?)?.toInt() ?? 0,
              errorBody:    m['body'] as String? ?? '',
              requestUrl:   m['url'] as String? ?? '',
              keyNote:      m['keyNote'] as String? ?? '',
              encodingNote: m['encNote'] as String? ?? '',
            );
          } catch (_) {
            return ApiErrorLogEntry(
              timestamp:  DateTime.now(),
              apiName:    'parse_error',
              statusCode: 0,
              errorBody:  e,
              requestUrl: '',
            );
          }
        })
        .toList();
  }

  /// 에러 로그 초기화
  Future<void> clearApiErrorLogs() async {
    await init();
    await _prefs!.remove(_prefixApiLog);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  ServiceKey URL 인코딩 검증
  //
  //  KRA API가 URL-Encoded key를 거부하는지 Raw key를 사용해야 하는지 검증
  //  검증 결과를 로그에 기록
  // ─────────────────────────────────────────────────────────────────────────
  static ServiceKeyValidationResult validateServiceKey(String rawKey) {
    // 1. 길이 검증
    final lengthOk = rawKey.length == 64;

    // 2. 문자셋 검증 (hex lowercase)
    final hexPattern = RegExp(r'^[a-f0-9]+$');
    final isHexLower = hexPattern.hasMatch(rawKey);

    // 3. URL 인코딩 필요 여부 (hex는 특수문자 없으므로 동일)
    // 실제 서비스키가 +, /, = 등을 포함하면 인코딩 필요
    final needsEncoding = rawKey.contains(RegExp(r'[+/=&%]'));
    final encodedKey = needsEncoding ? Uri.encodeComponent(rawKey) : rawKey;
    final encodingRequired = needsEncoding && encodedKey != rawKey;

    // 4. 진단 메시지
    final issues = <String>[];
    if (!lengthOk) issues.add('키 길이 오류: ${rawKey.length}자 (정상: 64자)');
    if (!isHexLower) issues.add('키 형식 오류: 소문자 hex 아님');
    if (encodingRequired) issues.add('URL 인코딩 필요: 특수문자 포함');

    // 5. 마스킹 (앞 8자 + *** + 뒤 4자)
    final maskedKey = rawKey.length > 12
        ? '${rawKey.substring(0, 8)}***${rawKey.substring(rawKey.length - 4)}'
        : '***';

    return ServiceKeyValidationResult(
      isValid:           issues.isEmpty,
      maskedKey:         maskedKey,
      needsEncoding:     encodingRequired,
      encodedKey:        encodedKey,
      issues:            issues,
      keyLength:         rawKey.length,
      isHexFormat:       isHexLower,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  유틸
  // ─────────────────────────────────────────────────────────────────────────
  static String _formatDate(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';

  static String _formatDateTime(DateTime dt) {
    final t = dt.toLocal();
    return '${t.month}/${t.day} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  /// startTime("HH:MM") → 해당 날짜의 Unix ms
  static int _toUnixMs(DateTime date, String startTime) {
    final parts = startTime.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return DateTime(date.year, date.month, date.day, h, m)
        .millisecondsSinceEpoch;
  }

  /// URL에서 서비스키 마스킹
  static String _maskServiceKey(String url) {
    return url.replaceAllMapped(
      RegExp(r'serviceKey=([a-fA-F0-9+/=]{10,})'),
      (m) {
        final k = m.group(1) ?? '';
        return 'serviceKey=${k.substring(0, 6)}***${k.substring(k.length - 4)}';
      },
    );
  }

  /// 오래된 캐시 정리 (앱 시작 시 호출 권장)
  Future<void> purgeExpiredCache() async {
    await init();
    final keys = _prefs!.getKeys()
        .where((k) => k.startsWith(_prefixData))
        .toList();
    int removed = 0;
    for (final key in keys) {
      // key 형식: race_cache:{venueCode}:{dateStr}
      final parts = key.split(':');
      if (parts.length < 3) continue;
      final dateStr = parts[2]; // YYYYMMDD
      if (dateStr.length != 8) continue;
      final y = int.tryParse(dateStr.substring(0, 4));
      final mo = int.tryParse(dateStr.substring(4, 6));
      final d  = int.tryParse(dateStr.substring(6, 8));
      if (y == null || mo == null || d == null) continue;
      final raceDate = DateTime(y, mo, d);
      if (DateTime.now().isAfter(raceDate.add(_cacheTtl))) {
        await _prefs!.remove(key);
        await _prefs!.remove('$_prefixTs${parts[1]}:$dateStr');
        await _prefs!.remove('$_prefixSrc${parts[1]}:$dateStr');
        removed++;
      }
    }
    if (kDebugMode && removed > 0) {
      debugPrint('[RaceScheduleCache] 🧹 만료 캐시 $removed건 정리');
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  CachedRaceEntry — 경주 1개의 캐시 데이터
// ══════════════════════════════════════════════════════════════════════════
class CachedRaceEntry {
  final String startTime;      // "HH:MM"
  final int    startUnixMs;    // Unix milliseconds
  final int    distance;       // 경주거리(m)
  final String condition;      // 경주조건
  final String grade;          // 등급
  final bool   isSpecialRace;
  final String specialRaceName;
  final int    totalHorses;
  final String trackCondition;

  const CachedRaceEntry({
    required this.startTime,
    this.startUnixMs   = 0,
    this.distance      = 0,
    this.condition     = '',
    this.grade         = '',
    this.isSpecialRace = false,
    this.specialRaceName = '',
    this.totalHorses   = 0,
    this.trackCondition = '',
  });

  factory CachedRaceEntry.fromJson(Map<String, dynamic> j) => CachedRaceEntry(
    startTime:       j['startTime'] as String? ?? '',
    startUnixMs:     (j['startUnixMs'] as num?)?.toInt() ?? 0,
    distance:        (j['distance'] as num?)?.toInt() ?? 0,
    condition:       j['condition'] as String? ?? '',
    grade:           j['grade'] as String? ?? '',
    isSpecialRace:   j['isSpecialRace'] as bool? ?? false,
    specialRaceName: j['specialRaceName'] as String? ?? '',
    totalHorses:     (j['totalHorses'] as num?)?.toInt() ?? 0,
    trackCondition:  j['trackCondition'] as String? ?? '',
  );
}

// ══════════════════════════════════════════════════════════════════════════
//  CacheMetaInfo — 캐시 메타 정보 (UI 표시용)
// ══════════════════════════════════════════════════════════════════════════
class CacheMetaInfo {
  final bool     hasCache;
  final DateTime? savedAt;
  final String   source;    // 'api' | 'scrape' | 'mock' | 'none'
  final String   venueCode;
  final String   dateStr;

  const CacheMetaInfo({
    required this.hasCache,
    required this.source,
    required this.venueCode,
    required this.dateStr,
    this.savedAt,
  });

  String get sourceLabel {
    switch (source) {
      case 'api':    return 'KRA 공식 API';
      case 'scrape': return '웹 파싱 보조';
      case 'mock':   return 'Mock 데이터';
      default:       return '없음';
    }
  }

  String get savedAtLabel {
    if (savedAt == null) return '없음';
    final t = savedAt!.toLocal();
    return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  ApiErrorLogEntry — API 에러 로그 1건
// ══════════════════════════════════════════════════════════════════════════
class ApiErrorLogEntry {
  final DateTime timestamp;
  final String   apiName;
  final int      statusCode;
  final String   errorBody;
  final String   requestUrl;
  final String   keyNote;
  final String   encodingNote;

  const ApiErrorLogEntry({
    required this.timestamp,
    required this.apiName,
    required this.statusCode,
    required this.errorBody,
    required this.requestUrl,
    this.keyNote      = '',
    this.encodingNote = '',
  });

  String get timeLabel {
    final t = timestamp.toLocal();
    return '${t.month}/${t.day} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  bool get is500 => statusCode == 500;
  bool get isTimeout => statusCode == 0;
  String get statusLabel => statusCode == 0 ? 'TIMEOUT' : 'HTTP $statusCode';
}

// ══════════════════════════════════════════════════════════════════════════
//  ServiceKeyValidationResult — ServiceKey 검증 결과
// ══════════════════════════════════════════════════════════════════════════
class ServiceKeyValidationResult {
  final bool   isValid;
  final String maskedKey;
  final bool   needsEncoding;
  final String encodedKey;
  final List<String> issues;
  final int    keyLength;
  final bool   isHexFormat;

  const ServiceKeyValidationResult({
    required this.isValid,
    required this.maskedKey,
    required this.needsEncoding,
    required this.encodedKey,
    required this.issues,
    required this.keyLength,
    required this.isHexFormat,
  });

  String get summary {
    if (isValid) return '✅ ServiceKey 정상 (${maskedKey}, ${keyLength}자, hex형식)';
    return '❌ ServiceKey 이상: ${issues.join(' / ')}';
  }
}
