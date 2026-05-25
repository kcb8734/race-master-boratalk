// ══════════════════════════════════════════════════════════════════════
// RaceResultArchive — racedetailresult 배치 아카이빙 서비스
//
// [설계 원칙]
//   · racedetailresult 는 갱신주기 일1회 → 실시간 폴링 금지
//   · 앱 구동 시 또는 매일 23시 이후 최초 1회만 배치 호출
//   · SharedPreferences 로컬 DB에 JSON 직렬화하여 아카이빙
//   · 정적 출전표(API26_2) 데이터 메모리 캐시 + 사용자 보정 오버라이드
//
// [데이터 파이프라인]
//   KRA API26_2 XML → 정적 HorseEntry 메모리 적재 (1회)
//     └─ 사용자 보정(UserCalibration) 오버라이드 → 시뮬레이션 연산
//   KRA racedetailresult XML → 배치 파싱 → SharedPreferences 아카이빙
//     └─ 샌드박스 모드에서 실제 착순 교차 대조용으로 활용
// ══════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/race_models.dart';
import 'kra_api_service.dart';

// ── 아카이브 키 접두사 ─────────────────────────────────────────────
const String _kArchivePrefix   = 'kra_result_';
const String _kArchiveIndexKey = 'kra_result_index';
const String _kLastBatchKey    = 'kra_last_batch_date';

// ── 배치 호출 허용 시간대: 23:00 이후 또는 경주 당일 종료 후 ──────
bool _isBatchWindow() {
  final now = DateTime.now();
  // 23시 이후 또는 다음날 0~5시
  return now.hour >= 23 || now.hour < 6;
}

// ══════════════════════════════════════════════════════════════════════
// 아카이브된 경주 메타데이터 (목록용)
// ══════════════════════════════════════════════════════════════════════
class ArchivedRaceMeta {
  final String key;         // SharedPreferences 저장 키
  final String raceDate;    // YYYYMMDD
  final String raceNo;      // 경주번호
  final String venueCode;   // 경주장코드
  final String venueName;   // 경주장명
  final String archivedAt;  // 아카이빙 시각 (ISO8601)
  final int horseCount;     // 출전마 수

  const ArchivedRaceMeta({
    required this.key,
    required this.raceDate,
    required this.raceNo,
    required this.venueCode,
    required this.venueName,
    required this.archivedAt,
    required this.horseCount,
  });

  String get displayDate {
    if (raceDate.length < 8) return raceDate;
    return '${raceDate.substring(0, 4)}.${raceDate.substring(4, 6)}'
        '.${raceDate.substring(6, 8)}';
  }

  String get venueLabel {
    switch (venueCode) {
      case '1': return '서울';
      case '2': return '부산경남';
      case '3': return '제주';
      default:  return venueName;
    }
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'raceDate': raceDate,
        'raceNo': raceNo,
        'venueCode': venueCode,
        'venueName': venueName,
        'archivedAt': archivedAt,
        'horseCount': horseCount,
      };

  factory ArchivedRaceMeta.fromJson(Map<String, dynamic> j) =>
      ArchivedRaceMeta(
        key:         j['key']         as String,
        raceDate:    j['raceDate']    as String,
        raceNo:      j['raceNo']      as String,
        venueCode:   j['venueCode']   as String,
        venueName:   j['venueName']   as String,
        archivedAt:  j['archivedAt']  as String,
        horseCount:  j['horseCount']  as int,
      );
}

// ══════════════════════════════════════════════════════════════════════
// RaceResultArchive — 싱글톤
// ══════════════════════════════════════════════════════════════════════
class RaceResultArchive {
  RaceResultArchive._();
  static final RaceResultArchive instance = RaceResultArchive._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _sharedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ─────────────────────────────────────────────────────────────────
  // 배치 아카이빙 (앱 구동 시 또는 23시 이후 1회)
  //
  // [호출 조건]
  //   1) 앱 구동 시 최초 1회
  //   2) 오늘 날짜에 대한 배치가 아직 실행되지 않은 경우
  //   3) 배치 윈도우(23시 이후)인 경우
  // ─────────────────────────────────────────────────────────────────
  Future<int> runBatchArchive({
    required String venueCode,
    required DateTime date,
    required List<String> raceNos,
    bool forceRun = false,
  }) async {
    final prefs  = await _sharedPrefs;
    final today  = _formatDate(date);
    final lastBatch = prefs.getString(_kLastBatchKey) ?? '';

    // 이미 오늘 배치 완료 + 강제 실행 아님 → 스킵
    if (!forceRun && lastBatch == today && !_isBatchWindow()) {
      if (kDebugMode) debugPrint('[Archive] 배치 스킵 (오늘 완료: $today)');
      return 0;
    }

    int archived = 0;
    for (final raceNo in raceNos) {
      try {
        final result = await KraApiService.fetchRaceResult(
            venueCode, date, raceNo);
        if (result != null && result.horses.isNotEmpty) {
          await _saveResult(result);
          archived++;
          if (kDebugMode) {
            debugPrint('[Archive] ✅ $today 제${raceNo}경주 아카이빙 완료'
                ' (${result.horses.length}두)');
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Archive] ❌ $today 제${raceNo}경주 오류: $e');
      }
    }

    if (archived > 0) {
      await prefs.setString(_kLastBatchKey, today);
    }
    return archived;
  }

  // ─────────────────────────────────────────────────────────────────
  // [PUBLIC] 이미지 업로드 경로 직접 저장
  // Admin 파이프라인에서 파싱 완료된 KraRaceResult를 직접 아카이빙
  // 배치 윈도우 체크 없이 즉시 저장
  // ─────────────────────────────────────────────────────────────────
  Future<void> saveImageUploadResult(KraRaceResult result) async {
    await _saveResult(result);
    if (kDebugMode) {
      debugPrint('[Archive] 📸 이미지 업로드 결과 저장 → '
          '${result.raceDate} ${result.venueName} 제${result.raceNo}경주 '
          '(${result.horses.length}두)');
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // 단일 경주 결과 로컬 저장 (SharedPreferences JSON)
  // ─────────────────────────────────────────────────────────────────
  Future<void> _saveResult(KraRaceResult result) async {
    final prefs = await _sharedPrefs;
    final key   = '$_kArchivePrefix${result.raceDate}_'
        '${result.venueCode}_${result.raceNo}';

    // 결과 직렬화
    final json = _serializeResult(result);
    await prefs.setString(key, jsonEncode(json));

    // 인덱스 업데이트
    final indexRaw = prefs.getString(_kArchiveIndexKey) ?? '[]';
    final index = (jsonDecode(indexRaw) as List)
        .map((e) => ArchivedRaceMeta.fromJson(e as Map<String, dynamic>))
        .toList();

    // 이미 있으면 교체
    index.removeWhere((m) => m.key == key);
    index.add(ArchivedRaceMeta(
      key:        key,
      raceDate:   result.raceDate,
      raceNo:     result.raceNo,
      venueCode:  result.venueCode,
      venueName:  result.venueName,
      archivedAt: DateTime.now().toIso8601String(),
      horseCount: result.horses.length,
    ));

    // 최신 100건 유지
    if (index.length > 100) {
      index.sort((a, b) => b.archivedAt.compareTo(a.archivedAt));
      index.removeRange(100, index.length);
    }

    await prefs.setString(
        _kArchiveIndexKey, jsonEncode(index.map((m) => m.toJson()).toList()));
  }

  // ─────────────────────────────────────────────────────────────────
  // 아카이브 목록 조회 (샌드박스 모드 경주 선택용)
  // ─────────────────────────────────────────────────────────────────
  Future<List<ArchivedRaceMeta>> listArchived() async {
    final prefs    = await _sharedPrefs;
    final indexRaw = prefs.getString(_kArchiveIndexKey) ?? '[]';
    try {
      final list = (jsonDecode(indexRaw) as List)
          .map((e) =>
              ArchivedRaceMeta.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.archivedAt.compareTo(a.archivedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // 특정 경주 결과 로드
  // ─────────────────────────────────────────────────────────────────
  Future<KraRaceResult?> loadResult(ArchivedRaceMeta meta) async {
    final prefs = await _sharedPrefs;
    final raw   = prefs.getString(meta.key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _deserializeResult(json);
    } catch (e) {
      if (kDebugMode) debugPrint('[Archive] 로드 오류: $e');
      return null;
    }
  }

  /// 키로 직접 로드
  Future<KraRaceResult?> loadByKey(String raceDate, String venueCode, String raceNo) async {
    final key = '$_kArchivePrefix${raceDate}_${venueCode}_$raceNo';
    final prefs = await _sharedPrefs;
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return _deserializeResult(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // 직렬화 / 역직렬화
  // ─────────────────────────────────────────────────────────────────
  static Map<String, dynamic> _serializeResult(KraRaceResult r) => {
        'raceNo':    r.raceNo,
        'raceDate':  r.raceDate,
        'venueCode': r.venueCode,
        'venueName': r.venueName,
        'horses':    r.horses.map(_serializeHorse).toList(),
      };

  static Map<String, dynamic> _serializeHorse(HorseResult h) => {
        'rank':              h.rank,
        'gateNo':            h.gateNo,
        'horseNo':           h.horseNo,
        'horseName':         h.horseName,
        'venueName':         h.venueName,
        'origin':            h.origin,
        'sex':               h.sex,
        'age':               h.age,
        'weight':            h.weight,
        'weightDiff':        h.weightDiff,
        'wgBudam':           h.wgBudam,
        'horseTool':         h.horseTool,
        'horseRating':       h.horseRating,
        'jockeyName':        h.jockeyName,
        'jockeyNo':          h.jockeyNo,
        'jockeyMeet':        h.jockeyMeet,
        'jockeyApprentice':  h.jockeyApprentice,
        'trainerName':       h.trainerName,
        'trainerNo':         h.trainerNo,
        'trainerMeet':       h.trainerMeet,
        'ownerName':         h.ownerName,
        'ownerNo':           h.ownerNo,
        'ownerCloth':        h.ownerCloth,
        'raceTime':          h.raceTime,
        'differ':            h.differ,
        'didStart':          h.didStart,
        'winOdds':           h.winOdds,
        'placeOdds':         h.placeOdds,
      };

  static KraRaceResult _deserializeResult(Map<String, dynamic> j) =>
      KraRaceResult(
        raceNo:    j['raceNo']    as String,
        raceDate:  j['raceDate']  as String,
        venueCode: j['venueCode'] as String,
        venueName: j['venueName'] as String,
        horses: (j['horses'] as List)
            .map((h) => _deserializeHorse(h as Map<String, dynamic>))
            .toList(),
      );

  static HorseResult _deserializeHorse(Map<String, dynamic> h) =>
      HorseResult(
        rank:             h['rank']             as int,
        gateNo:           h['gateNo']           as int,
        horseNo:          h['horseNo']          as String? ?? '',
        horseName:        h['horseName']        as String,
        venueName:        h['venueName']        as String? ?? '',
        origin:           h['origin']           as String? ?? '',
        sex:              h['sex']              as String? ?? '',
        age:              h['age']              as String? ?? '',
        weight:           h['weight']           as int,
        weightDiff:       h['weightDiff']       as int? ?? 0,
        wgBudam:          (h['wgBudam'] as num).toDouble(),
        horseTool:        h['horseTool']        as String? ?? '',
        horseRating:      h['horseRating']      as String? ?? '',
        jockeyName:       h['jockeyName']       as String,
        jockeyNo:         h['jockeyNo']         as String? ?? '',
        jockeyMeet:       h['jockeyMeet']       as String? ?? '',
        jockeyApprentice: h['jockeyApprentice'] as String? ?? '',
        trainerName:      h['trainerName']      as String? ?? '',
        trainerNo:        h['trainerNo']        as String? ?? '',
        trainerMeet:      h['trainerMeet']      as String? ?? '',
        ownerName:        h['ownerName']        as String? ?? '',
        ownerNo:          h['ownerNo']          as String? ?? '',
        ownerCloth:       h['ownerCloth']       as String? ?? '',
        raceTime:         h['raceTime']         as String,
        differ:           h['differ']           as String? ?? '',
        didStart:         h['didStart']         as bool? ?? true,
        winOdds:          (h['winOdds']   as num).toDouble(),
        placeOdds:        (h['placeOdds'] as num).toDouble(),
      );

  static String _formatDate(DateTime date) =>
      '${date.year}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
}
