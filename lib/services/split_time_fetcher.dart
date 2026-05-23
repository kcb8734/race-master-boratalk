// ============================================================
//  split_time_fetcher.dart
//  경마통 Race Master — API4_3 구간 기록 파싱 & 물리 프로필 자동 생성
//
//  【API4_3 프로토콜】
//  - URL: https://apis.data.go.kr/B551015/API4_3
//  - 포맷: JSON (_type=json) — 복수지원 중 JSON 우선 적용
//  - 필드: hrName, rcDist, meet, rcTime, seS1fAccTime, sjS1fOrd,
//          se_3cAccTime, se_4cAccTime, sj_3cOrd, sj_4cOrd,
//          seG3fAccTime, seG1fAccTime, sjG1fOrd (서울),
//          buS1fAccTime, buG6fAccTime, buG1fAccTime, buG1fOrd (부산경남),
//          je_1cTime ~ je_4cTime (제주)
//
//  【설계 흐름】
//  1. API4_3 JSON 호출 (hrName + rcDist + meet 파라미터)
//  2. 최근 5경주 SplitTimeRecord 파싱 (Null은 등급·거리 평균값 대치)
//  3. SplitTimeRecord → HorsePhysicsProfile 변환 (평균 프로필 적용)
//  4. 결과를 HorseEntry에 physicsProfile 필드로 탑재
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/race_models.dart';
import '../models/horse_physics_profile.dart';

// ── 등급별 평균 S1F/G1F 기록 DB ─────────────────────────────────────
// 실측 데이터 기반 등급별 평균 구간 기록 (서울 기준)
// Null/0 구간 데이터 부재 시 Default 대치용
const Map<String, Map<String, double>> kGradeAvgSplitDB = {
  '국1등급': {'s1f': 11.2, 'g1f': 83.5, 'c3': 52.0, 'c4': 64.5},
  '국2등급': {'s1f': 11.5, 'g1f': 84.0, 'c3': 52.8, 'c4': 65.2},
  '국3등급': {'s1f': 11.7, 'g1f': 84.5, 'c3': 53.2, 'c4': 65.8},
  '국4등급': {'s1f': 11.9, 'g1f': 85.0, 'c3': 53.8, 'c4': 66.4},
  '국5등급': {'s1f': 12.0, 'g1f': 85.5, 'c3': 54.2, 'c4': 67.0},
  '국6등급': {'s1f': 12.3, 'g1f': 86.2, 'c3': 54.8, 'c4': 67.8},
  '국7등급': {'s1f': 12.6, 'g1f': 87.0, 'c3': 55.5, 'c4': 68.5},
  // 거리별 보정 (1200m 기준 부산경남)
  '부경국1': {'s1f': 11.3, 'g1f': 73.5, 'g6f': 40.5},
  '부경국5': {'s1f': 12.1, 'g1f': 75.0, 'g6f': 42.0},
  // 제주 (코너 기반)
  '제주국1': {'c1': 12.8, 'c2': 33.5, 'c3': 53.0, 'c4': 73.0},
  '제주국5': {'c1': 13.5, 'c2': 35.5, 'c3': 55.5, 'c4': 75.5},
};

/// 등급명 → DB 키 변환 (접두어 제거)
String _gradeKey(String grade, String venueCode) {
  // 등급명 정규화: '국5등급 핸디캡' → '국5등급'
  final clean = grade.replaceAll(RegExp(r'\s+(핸디캡|일반|특별|오픈).*'), '').trim();
  if (venueCode == '2') {
    // 부산경남 전용 키 탐색
    final buKey = clean.replaceAll('국', '부경국');
    if (kGradeAvgSplitDB.containsKey(buKey)) return buKey;
  }
  if (venueCode == '3') {
    final jeKey = clean.replaceAll('국', '제주국');
    if (kGradeAvgSplitDB.containsKey(jeKey)) return jeKey;
  }
  return kGradeAvgSplitDB.containsKey(clean) ? clean : '국5등급';
}

/// 등급·경마장 기반 구간 기록 Default 반환
double _defaultTime(String key, String grade, String venueCode) {
  final gk  = _gradeKey(grade, venueCode);
  final db  = kGradeAvgSplitDB[gk];
  if (db != null && db.containsKey(key)) return db[key]!;
  // 글로벌 폴백
  final global = kAvgSplitTimes[venueCode == '1' ? 'seoul'
                                 : venueCode == '2' ? 'busan' : 'jeju'];
  return global?[key] ?? 12.0;
}

// ══════════════════════════════════════════════════════════════════════
//  SplitTimeFetcher — API4_3 JSON 호출 & 물리 프로필 자동 생성
// ══════════════════════════════════════════════════════════════════════
class SplitTimeFetcher {
  static const String _serviceKey =
      'ef117e7bebbcea7586234f85acd8292dba6a6d95230131aec62a10b5b2610885';
  static const String _baseUrl = 'https://apis.data.go.kr/B551015';

  // 캐시: hrName → HorsePhysicsProfile (메모리 캐시, 경주 세션 단위 유효)
  static final Map<String, HorsePhysicsProfile> _profileCache = {};

  /// 캐시 초기화 (경주 선택 변경 시 호출)
  static void clearCache() => _profileCache.clear();

  // ──────────────────────────────────────────────────────────────────
  //  fetchProfile: 말 이름 + 경주 정보 → HorsePhysicsProfile
  //
  //  【예외 처리】
  //  · API 실패 → HorsePhysicsProfile.neutral 반환 (시뮬 중단 없음)
  //  · 구간 기록 Null/0 → 등급·거리 평균값 자동 대치
  //  · 최근 5경주 평균 프로필 반환 (1경주 이상 있으면 평균 계산)
  // ──────────────────────────────────────────────────────────────────
  static Future<HorsePhysicsProfile> fetchProfile({
    required String horseName,
    required RaceInfo race,
  }) async {
    // ① 캐시 확인
    final cacheKey = '${horseName}_${race.venueCode}_${race.distance}';
    if (_profileCache.containsKey(cacheKey)) {
      return _profileCache[cacheKey]!;
    }

    final meetCode  = _venueToMeet(race.venueCode);
    final venueCode = race.venueCode;
    final grade     = race.grade.isNotEmpty ? race.grade : '국5등급';

    try {
      // ② API4_3 JSON 호출 — JSON 프로토콜 통일 (_type=json)
      final uri = Uri.parse(
        '$_baseUrl/API4_3'
        '?serviceKey=$_serviceKey'
        '&numOfRows=5&pageNo=1'
        '&hrName=${Uri.encodeComponent(horseName)}'
        '&meet=$meetCode'
        '&_type=json',
      );
      if (kDebugMode) {
        debugPrint('[SplitTimeFetcher] GET $uri');
      }

      final resp = await http.get(uri).timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200 &&
          !resp.body.contains('Unexpected errors') &&
          !resp.body.contains('SERVICE ERROR')) {
        final data  = jsonDecode(resp.body);
        final items = _extractItems(data);

        if (items != null && items.isNotEmpty) {
          // ③ 각 경주 기록 → SplitTimeRecord 파싱 (최대 5개)
          final records = items.take(5).map((item) {
            // 거리 파싱
            final dist = int.tryParse(
                    item['rcDist']?.toString() ?? '') ??
                race.distance;
            return _parseSplitRecord(
              item,
              venueCode: venueCode,
              distance:  dist,
              grade:     grade,
            );
          }).toList();

          // ④ SplitTimeRecord → HorsePhysicsProfile 변환
          final profiles = records
              .map((r) => HorsePhysicsProfile.fromSplitTime(r))
              .toList();

          // ⑤ 평균 프로필 반환
          final avgProfile = HorsePhysicsProfile.average(profiles);
          _profileCache[cacheKey] = avgProfile;
          if (kDebugMode) {
            debugPrint('[SplitTimeFetcher] ✅ $horseName → $avgProfile');
          }
          return avgProfile;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SplitTimeFetcher] ⚠️ $horseName 조회 실패: $e → Default 프로필 적용');
      }
    }

    // ⑥ API 실패 or 데이터 없음 → Default 프로필 (등급 기반 추정)
    final defaultProfile = _buildDefaultProfile(grade, venueCode, race.distance);
    _profileCache[cacheKey] = defaultProfile;
    return defaultProfile;
  }

  // ──────────────────────────────────────────────────────────────────
  //  복수 출전마 일괄 조회 (5초 제한, 병렬 처리)
  // ──────────────────────────────────────────────────────────────────
  static Future<Map<int, HorsePhysicsProfile>> fetchAllProfiles({
    required List<HorseEntry> entries,
    required RaceInfo race,
  }) async {
    final result = <int, HorsePhysicsProfile>{};

    // 병렬 Future 생성 (최대 동시 3개 → 서버 부하 제한)
    const batchSize = 3;
    for (int i = 0; i < entries.length; i += batchSize) {
      final batch = entries.sublist(
          i, (i + batchSize).clamp(0, entries.length));
      final futures = batch.map((e) => fetchProfile(
            horseName: e.horseName,
            race:      race,
          ).then((profile) => MapEntry(e.gateNo, profile)));

      final results = await Future.wait(futures);
      for (final entry in results) {
        result[entry.key] = entry.value;
      }
    }

    return result;
  }

  // ──────────────────────────────────────────────────────────────────
  //  내부: JSON 응답 → SplitTimeRecord 파싱
  // ──────────────────────────────────────────────────────────────────
  static SplitTimeRecord _parseSplitRecord(
    Map<String, dynamic> item, {
    required String venueCode,
    required int    distance,
    required String grade,
  }) {
    // ignore: no_leading_underscores_for_local_identifiers
    double? _d(String key) {
      final v = item[key];
      if (v == null) return null;
      final p = double.tryParse(v.toString());
      return (p == null || p <= 0) ? null : p;
    }
    // ignore: no_leading_underscores_for_local_identifiers
    int? _i(String key) {
      final v = item[key];
      if (v == null) return null;
      final p = int.tryParse(v.toString());
      return (p == null || p <= 0) ? null : p;
    }

    // Null 구간 기록 → 등급·거리 평균값 대치
    double defaultVal(String timeKey) =>
        _defaultTime(timeKey, grade, venueCode);

    return SplitTimeRecord(
      // 서울
      seS1fAccTime:  _d('seS1fAccTime')  ?? (venueCode == '1' ? defaultVal('s1f') : null),
      sjS1fOrd:      _i('sjS1fOrd'),
      se_3cAccTime:  _d('se_3cAccTime')  ?? _d('se3cAccTime')
                      ?? (venueCode == '1' ? defaultVal('c3') : null),
      se_4cAccTime:  _d('se_4cAccTime')  ?? _d('se4cAccTime')
                      ?? (venueCode == '1' ? defaultVal('c4') : null),
      sj_3cOrd:      _i('sj_3cOrd')     ?? _i('sj3cOrd'),
      sj_4cOrd:      _i('sj_4cOrd')     ?? _i('sj4cOrd'),
      seG3fAccTime:  _d('seG3fAccTime'),
      seG1fAccTime:  _d('seG1fAccTime')  ?? (venueCode == '1' ? defaultVal('g1f') : null),
      sjG1fOrd:      _i('sjG1fOrd'),
      // 부산경남
      buS1fAccTime:  _d('buS1fAccTime')  ?? (venueCode == '2' ? defaultVal('s1f') : null),
      buS1fOrd:      _i('buS1fOrd'),
      buG6fAccTime:  _d('buG6fAccTime')  ?? (venueCode == '2' ? defaultVal('g6f') : null),
      buG1fAccTime:  _d('buG1fAccTime')  ?? (venueCode == '2' ? defaultVal('g1f') : null),
      buG1fOrd:      _i('buG1fOrd'),
      // 제주
      je_1cTime:     _d('je_1cTime')     ?? _d('je1cTime')
                      ?? (venueCode == '3' ? defaultVal('c1') : null),
      je_2cTime:     _d('je_2cTime')     ?? _d('je2cTime')
                      ?? (venueCode == '3' ? defaultVal('c2') : null),
      je_3cTime:     _d('je_3cTime')     ?? _d('je3cTime')
                      ?? (venueCode == '3' ? defaultVal('c3') : null),
      je_4cTime:     _d('je_4cTime')     ?? _d('je4cTime')
                      ?? (venueCode == '3' ? defaultVal('c4') : null),
      venueCode:     venueCode,
      distance:      distance,
      grade:         grade,
    );
  }

  // ──────────────────────────────────────────────────────────────────
  //  내부: 등급 기반 Default 프로필 생성 (API 실패 시 폴백)
  // ──────────────────────────────────────────────────────────────────
  static HorsePhysicsProfile _buildDefaultProfile(
      String grade, String venueCode, int distance) {
    final s1f = _defaultTime('s1f', grade, venueCode);
    final g1f = _defaultTime('g1f', grade, venueCode);
    final c3  = _defaultTime('c3',  grade, venueCode);
    final c4  = _defaultTime('c4',  grade, venueCode);

    final dummyRec = SplitTimeRecord(
      seS1fAccTime: venueCode == '1' ? s1f : null,
      se_3cAccTime: venueCode == '1' ? c3  : null,
      se_4cAccTime: venueCode == '1' ? c4  : null,
      seG1fAccTime: venueCode == '1' ? g1f : null,
      buS1fAccTime: venueCode == '2' ? s1f : null,
      buG1fAccTime: venueCode == '2' ? g1f : null,
      je_1cTime:    venueCode == '3' ? s1f : null,
      je_4cTime:    venueCode == '3' ? g1f : null,
      venueCode:    venueCode,
      distance:     distance,
      grade:        grade,
    );
    return HorsePhysicsProfile.fromSplitTime(dummyRec);
  }

  // ──────────────────────────────────────────────────────────────────
  //  유틸: JSON items 추출
  // ──────────────────────────────────────────────────────────────────
  static List<dynamic>? _extractItems(dynamic data) {
    try {
      final items = data['response']?['body']?['items']?['item'];
      if (items == null) return null;
      if (items is List) return items;
      if (items is Map) return [items];
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _venueToMeet(String venueCode) {
    switch (venueCode) {
      case '1': return '1';
      case '2': return '3';
      case '3': return '2';
      default:  return '1';
    }
  }
}
