import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/race_models.dart';
import 'kra_bulk_sync_service.dart';

// ══════════════════════════════════════════════════════════════════════════
//  KraBulkDataBinder — 벌크싱크 수집 데이터 → 물리 엔진 바인딩 레이어
//
//  ▸ 목적:
//    KraBulkSyncService.getCachedData()로 가져온 Raw JSON/XML 문자열을
//    HorseEntry / RaceInfo 객체로 파싱하여 물리 엔진(race_stat_engine)에
//    실제 데이터를 공급한다.
//
//  ▸ 지원 API & 파싱 대상:
//    - API8_2  : 경주마 상세정보 → HorseEntry (속도스탯, 레이팅, 체중 등)
//    - API12_1 : 기수 면허/통산전적 → HorseEntry.jockeyRcWins 업데이트
//    - API10_1 : 조교사 통산성적 → HorseEntry.trNo 기반 FatigueIndex 공급
//    - API15   : 경주마 과거성적 → HorseEntry.recentRecord 보강
//    - API187  : 경마경주정보 → RaceInfo 목록 재구성 (Tier-4 폴백 품질 향상)
//    - API26_2 : 출전표 상세정보 → HorseEntry 전체 재구성
//
//  ▸ 바인딩 우선순위 (높을수록 우선):
//    1. 실시간 API 응답 (kra_api_service)
//    2. 관리자 수동 인젝션 (admin_data_panel_screen)
//    3. 벌크싱크 캐시 (이 파일)
//    4. Mock 데이터 (kra_mock_service)
//
//  ▸ 사용법:
//    final binder = KraBulkDataBinder();
//    final horses = await binder.buildHorseEntries(
//      venueCode: '1', date: DateTime.now(), baseHorses: mockHorses,
//    );
// ══════════════════════════════════════════════════════════════════════════
class KraBulkDataBinder {
  // ── 싱글톤 ────────────────────────────────────────────────────────────
  static final KraBulkDataBinder _instance = KraBulkDataBinder._internal();
  factory KraBulkDataBinder() => _instance;
  KraBulkDataBinder._internal();

  final _sync = KraBulkSyncService();

  // ══════════════════════════════════════════════════════════════════════
  //  RaceInfo 보강 — API187 벌크 캐시 적용
  //
  //  [baseRaces]: KraMockService 또는 TIER-5 기본 경주 목록
  //  반환값: 벌크 캐시 데이터로 보강된 RaceInfo 목록
  //         (캐시 없으면 baseRaces 그대로)
  // ══════════════════════════════════════════════════════════════════════
  Future<List<RaceInfo>> enrichRaceInfoFromBulk({
    required List<RaceInfo> baseRaces,
    required String venueCode,
    required DateTime date,
  }) async {
    final raw = await _sync.getCachedData('API187');
    if (raw == null) {
      if (kDebugMode) {
        debugPrint('[BulkBinder] API187 캐시 없음 → baseRaces 유지');
      }
      return baseRaces;
    }

    try {
      // JSON 파싱 시도
      final items = _extractJsonItems(raw);
      if (items != null && items.isNotEmpty) {
        final built = _buildRaceInfosFromJson(items, venueCode, date);
        if (built.isNotEmpty) {
          if (kDebugMode) {
            debugPrint('[BulkBinder] API187 캐시 → ${built.length}경주 재구성');
          }
          return built;
        }
      }

      // XML 파싱 시도 (JSON 실패 시)
      if (raw.contains('<item>')) {
        final built = _buildRaceInfosFromXml(raw, venueCode, date);
        if (built.isNotEmpty) {
          if (kDebugMode) {
            debugPrint('[BulkBinder] API187 XML 캐시 → ${built.length}경주');
          }
          return built;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BulkBinder] API187 파싱 실패: $e');
      }
    }
    return baseRaces;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  HorseEntry 보강 — API8_2 (경주마 상세정보) 캐시 적용
  //
  //  [baseHorses]: Mock 또는 API26_2 부분 파싱된 출전마 목록
  //  반환값: API8_2 레이팅/체중/속도스탯이 보강된 HorseEntry 목록
  // ══════════════════════════════════════════════════════════════════════
  Future<List<HorseEntry>> enrichHorseStatsFromBulk({
    required List<HorseEntry> baseHorses,
  }) async {
    final raw = await _sync.getCachedData('API8_2');
    if (raw == null) {
      if (kDebugMode) {
        debugPrint('[BulkBinder] API8_2 캐시 없음 → baseHorses 유지');
      }
      return baseHorses;
    }

    try {
      final items = _extractJsonItems(raw) ?? _extractXmlItems(raw);
      if (items == null || items.isEmpty) return baseHorses;

      // 마명 → 통계 맵 구성
      final statMap = <String, _HorseStat>{};
      for (final item in items) {
        final name  = _str(item, ['hrName', 'hrNm', 'horseName']) ?? '';
        final regNo = _str(item, ['hrNo', 'hrRegNo']) ?? '';
        if (name.isEmpty) continue;

        final rating   = _dbl(item, ['rating', 'hrRating']) ?? 0.0;
        final wgHr     = _int(item, ['wgHr', 'weight']) ?? 500;
        final rcWinRate= _dbl(item, ['rcWinRate', 'winRate']) ?? 0.0;
        final wgBudam  = _dbl(item, ['wgBudam', 'budam']) ?? 55.0;

        statMap[name] = _HorseStat(
          horseRegNo: regNo,
          rating: rating,
          weight: wgHr,
          rcWins: rcWinRate,
          wgBudam: wgBudam,
        );
      }

      if (statMap.isEmpty) return baseHorses;

      // baseHorses에 적용
      int enriched = 0;
      final result = baseHorses.map((horse) {
        final stat = statMap[horse.horseName];
        if (stat == null) return horse;
        enriched++;
        // 레이팅이 의미있는 값이면 speedStat / staminaStat에 반영
        final ratingNorm = (stat.rating / 100.0).clamp(0.0, 1.0);
        return HorseEntry(
          gateNo:        horse.gateNo,
          horseName:     horse.horseName,
          jockeyName:    horse.jockeyName,
          trainerName:   horse.trainerName,
          weight:        stat.weight > 0 ? stat.weight : horse.weight,
          weightChange:  horse.weightChange,
          rating:        stat.rating > 0 ? stat.rating : horse.rating,
          speedStat:     horse.speedStat > 50
              ? horse.speedStat : (ratingNorm * 80 + 20),
          staminaStat:   horse.staminaStat > 50
              ? horse.staminaStat : (ratingNorm * 75 + 15),
          formStat:      horse.formStat,
          trackFitStat:  horse.trackFitStat,
          baseScore:     horse.baseScore,
          userBonus:     horse.userBonus,
          recentRecord:  horse.recentRecord,
          odds:          horse.odds,
          plcOdds:       horse.plcOdds,
          isCancelled:   horse.isCancelled,
          horseRegNo:    stat.horseRegNo.isNotEmpty ? stat.horseRegNo : horse.horseRegNo,
          rcWins:        stat.rcWins > 0 ? stat.rcWins : horse.rcWins,
          jockeyRcWins:  horse.jockeyRcWins,
          wgBudam:       stat.wgBudam > 0 ? stat.wgBudam : horse.wgBudam,
          g1fRating:     horse.g1fRating,
          prizeWin:      horse.prizeWin,
          prize2nd:      horse.prize2nd,
          prize3rd:      horse.prize3rd,
          prize4th:      horse.prize4th,
          prize5th:      horse.prize5th,
          prizeTotalCareer: horse.prizeTotalCareer,
          prizeTotal1Year:  horse.prizeTotal1Year,
          prizeTotal6Month: horse.prizeTotal6Month,
          physicsProfile: horse.physicsProfile,
          jkNo:          horse.jkNo,
          trNo:          horse.trNo,
          userSpeedWeight:   horse.userSpeedWeight,
          userStaminaWeight: horse.userStaminaWeight,
        );
      }).toList();

      if (kDebugMode) {
        debugPrint('[BulkBinder] API8_2 → $enriched/${baseHorses.length}두 스탯 보강');
      }
      return result;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BulkBinder] API8_2 파싱 실패: $e');
      }
      return baseHorses;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  HorseEntry 기수 통산전적 보강 — API12_1 캐시 적용
  //
  //  기수명 → 통산 승률 매핑 후 jockeyRcWins 업데이트
  // ══════════════════════════════════════════════════════════════════════
  Future<List<HorseEntry>> enrichJockeyStatsFromBulk({
    required List<HorseEntry> baseHorses,
  }) async {
    final raw = await _sync.getCachedData('API12_1');
    if (raw == null) return baseHorses;

    try {
      final items = _extractJsonItems(raw) ?? _extractXmlItems(raw);
      if (items == null || items.isEmpty) return baseHorses;

      // 기수명 → 승률 맵
      final jockeyMap = <String, double>{};
      for (final item in items) {
        final name = _str(item, ['jkName', 'jockeyName']) ?? '';
        if (name.isEmpty) continue;
        final winRate = _dbl(item, ['jkWinRate', 'winRate', 'rcWinRate']) ?? 0.0;
        jockeyMap[name] = winRate;
      }

      int enriched = 0;
      final result = baseHorses.map((horse) {
        final winRate = jockeyMap[horse.jockeyName];
        if (winRate == null || winRate <= 0) return horse;
        enriched++;
        return horse.copyWith(jockeyRcWins: winRate);
      }).toList();

      if (kDebugMode) {
        debugPrint('[BulkBinder] API12_1 → $enriched두 기수 승률 보강');
      }
      return result;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BulkBinder] API12_1 파싱 실패: $e');
      }
      return baseHorses;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  통합 HorseEntry 보강 파이프라인
  //
  //  API8_2(마필 스탯) → API12_1(기수 승률) 순서로 순차 보강
  //  캐시가 없는 단계는 자동 스킵
  // ══════════════════════════════════════════════════════════════════════
  Future<List<HorseEntry>> buildHorseEntries({
    required List<HorseEntry> baseHorses,
    required String venueCode,
    required DateTime date,
  }) async {
    if (baseHorses.isEmpty) return baseHorses;

    var horses = baseHorses;

    // Step 1: 마필 스탯 보강 (API8_2)
    horses = await enrichHorseStatsFromBulk(baseHorses: horses);

    // Step 2: 기수 승률 보강 (API12_1)
    horses = await enrichJockeyStatsFromBulk(baseHorses: horses);

    return horses;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  벌크싱크 캐시 현황 진단 (어드민 UI 지원)
  // ══════════════════════════════════════════════════════════════════════
  Future<BulkDataBinderDiagnostic> getDiagnostic() async {
    final apis = ['API187', 'API26_2', 'API8_2', 'API12_1',
                  'API10_1', 'API15', 'API4_3', 'trnweekentry'];
    final available = <String>[];
    final missing   = <String>[];

    for (final id in apis) {
      final data = await _sync.getCachedData(id);
      if (data != null) {
        available.add(id);
      } else {
        missing.add(id);
      }
    }

    return BulkDataBinderDiagnostic(
      checkedApis:     apis.length,
      availableApis:   available,
      missingApis:     missing,
      bindingReady:    available.isNotEmpty,
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  //  내부 파싱 유틸
  // ──────────────────────────────────────────────────────────────────────

  List<dynamic>? _extractJsonItems(String raw) {
    try {
      final data = jsonDecode(raw);
      // 공공데이터포털 표준 래퍼: {"response":{"body":{"items":{"item":[...]}}}}
      dynamic items;
      if (data is Map) {
        final response = data['response'];
        if (response is Map) {
          final body = response['body'];
          if (body is Map) {
            final itm = body['items'];
            if (itm is Map) {
              items = itm['item'];
            } else if (itm is List) {
              items = itm;
            }
          }
        }
        // 래퍼 없이 직접 배열인 경우
        if (items == null && data['items'] != null) {
          items = data['items'];
        }
      } else if (data is List) {
        items = data;
      }

      if (items is List) return items;
      if (items is Map)  return [items];
      return null;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>>? _extractXmlItems(String raw) {
    if (!raw.contains('<item>')) return null;
    final result = <Map<String, dynamic>>[];
    final itemRegex = RegExp(r'<item>(.*?)</item>', dotAll: true);
    for (final match in itemRegex.allMatches(raw)) {
      final block = match.group(1) ?? '';
      final map = <String, dynamic>{};
      final tagRegex = RegExp(r'<(\w+)>([^<]*)</\1>');
      for (final m in tagRegex.allMatches(block)) {
        map[m.group(1)!] = m.group(2)!.trim();
      }
      if (map.isNotEmpty) result.add(map);
    }
    return result.isEmpty ? null : result;
  }

  List<RaceInfo> _buildRaceInfosFromJson(
      List<dynamic> items, String venueCode, DateTime date) {
    final result = <RaceInfo>[];
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month && date.day == now.day;
    final isPast = date.isBefore(DateTime(now.year, now.month, now.day));
    final venueName = venueCode == '1' ? '서울'
        : venueCode == '2' ? '부산경남' : '제주';

    for (final item in items) {
      try {
        final raceNo  = _str(item, ['rcNo', 'raceNo']) ?? '';
        final rawTime = _str(item, ['postTime', 'rcPostTime', 'startTime']) ?? '';
        final startTime = rawTime.isNotEmpty ? _fmtTime(rawTime) : '';
        if (raceNo.isEmpty || startTime.isEmpty) continue;

        final distance    = _int(item, ['rcDist', 'distance']) ?? 1400;
        final condition   = _str(item, ['rcGrdCourse', 'condition']) ?? '';
        final grade       = _str(item, ['rcGrdNm', 'grade']) ?? '';
        final totalHorses = _int(item, ['chulNum', 'totalHorses']) ?? 10;
        final rcName      = _str(item, ['rcName', 'raceName']) ?? '';
        final trackCond   = _str(item, ['trackCond', 'trackCondition']) ?? '양호';

        final isSpecialRace = rcName.isNotEmpty &&
            !rcName.contains('일반') &&
            !RegExp(r'^제\d+경주$').hasMatch(rcName);

        bool isFinished = false;
        bool isUpcoming = false;
        if (isToday && startTime.isNotEmpty) {
          final parts = startTime.split(':');
          if (parts.length == 2) {
            final raceTime = DateTime(now.year, now.month, now.day,
                int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
            final diff = raceTime.difference(now).inMinutes;
            isFinished = diff < -30;
            isUpcoming = !isFinished && diff >= 0 && diff <= 30;
          }
        } else if (isPast) {
          isFinished = true;
        }

        result.add(RaceInfo(
          raceNo:          raceNo,
          raceName:        isSpecialRace ? rcName : '제${raceNo}경주',
          startTime:       startTime,
          distance:        distance,
          condition:       condition,
          grade:           grade,
          venueCode:       venueCode,
          venueName:       venueName,
          raceDate:        _fmtDate(date),
          totalHorses:     totalHorses,
          trackCondition:  trackCond,
          isFinished:      isFinished,
          isUpcoming:      isUpcoming,
          isSpecialRace:   isSpecialRace,
          specialRaceName: isSpecialRace ? rcName : '',
        ));
      } catch (_) {
        continue;
      }
    }
    return result;
  }

  List<RaceInfo> _buildRaceInfosFromXml(
      String xml, String venueCode, DateTime date) {
    final items = _extractXmlItems(xml);
    if (items == null) return [];
    return _buildRaceInfosFromJson(items, venueCode, date);
  }

  // ── 필드 추출 헬퍼 ───────────────────────────────────────────────────
  static String? _str(dynamic item, List<String> keys) {
    if (item is! Map) return null;
    for (final k in keys) {
      final v = item[k];
      if (v != null && v.toString().isNotEmpty) return v.toString().trim();
    }
    return null;
  }

  static double? _dbl(dynamic item, List<String> keys) {
    final s = _str(item, keys);
    if (s == null) return null;
    return double.tryParse(s);
  }

  static int? _int(dynamic item, List<String> keys) {
    final s = _str(item, keys);
    if (s == null) return null;
    return int.tryParse(s);
  }

  static String _fmtTime(String raw) {
    final s = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (s.length < 3) return '';
    final h = s.substring(0, s.length - 2);
    final m = s.substring(s.length - 2);
    return '${h.padLeft(2, '0')}:$m';
  }

  static String _fmtDate(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
}

// ══════════════════════════════════════════════════════════════════════════
//  내부 전용 — 마필 스탯 임시 구조체
// ══════════════════════════════════════════════════════════════════════════
class _HorseStat {
  final String horseRegNo;
  final double rating;
  final int    weight;
  final double rcWins;
  final double wgBudam;

  const _HorseStat({
    required this.horseRegNo,
    required this.rating,
    required this.weight,
    required this.rcWins,
    required this.wgBudam,
  });
}

// ══════════════════════════════════════════════════════════════════════════
//  BulkDataBinderDiagnostic — 캐시 가용성 진단 결과
// ══════════════════════════════════════════════════════════════════════════
class BulkDataBinderDiagnostic {
  final int          checkedApis;
  final List<String> availableApis;
  final List<String> missingApis;
  final bool         bindingReady;

  const BulkDataBinderDiagnostic({
    required this.checkedApis,
    required this.availableApis,
    required this.missingApis,
    required this.bindingReady,
  });

  int get availableCount => availableApis.length;
  int get missingCount   => missingApis.length;

  String get summary {
    if (!bindingReady) return '⚠️ 벌크싱크 캐시 없음 — 새벽 수집 후 활성화';
    return '✅ ${availableCount}/${checkedApis}개 API 캐시 가용 (바인딩 준비 완료)';
  }
}
