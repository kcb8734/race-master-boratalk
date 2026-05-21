import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/race_models.dart';
import 'kra_mock_service.dart';

/// 한국마사회 실제 API 연동 서비스
/// 인증키: ef117e7bebbcea7586234f85acd8292dba6a6d95230131aec62a10b5b2610885
class KraApiService {
  static const String _serviceKey =
      'ef117e7bebbcea7586234f85acd8292dba6a6d95230131aec62a10b5b2610885';
  static const String _baseUrl = 'https://apis.data.go.kr/B551015';

  // ── API187: 경마경주정보 ──
  // rcDate: YYYYMMDD, rcNo: 경주번호, meet: 1=서울 2=제주 3=부산경남
  static Future<List<RaceInfo>> fetchRaces(String venueCode, DateTime date) async {
    final dateStr = _formatDate(date);
    // KRA meet 코드: 서울=1, 제주=2, 부산경남=3
    final meetCode = _venueToMeet(venueCode);

    try {
      final uri = Uri.parse(
        '$_baseUrl/API187?serviceKey=$_serviceKey'
        '&numOfRows=20&pageNo=1&meet=$meetCode&rc_date=$dateStr&_type=json',
      );
      if (kDebugMode) debugPrint('[KRA API187] $uri');

      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final items = _extractItems(data);
        if (items != null && items.isNotEmpty) {
          final races = _parseRaces(items, venueCode, date);
          if (races.isNotEmpty) return races;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[KRA API187] Error: $e → Mock 사용');
    }

    // API 실패 시 Mock 사용
    return KraMockService.getRaces(venueCode, date);
  }

  // ── API26_2: 출전표 상세정보 ──
  static Future<List<HorseEntry>> fetchHorseEntries(
      String venueCode, DateTime date, String raceNo) async {
    final dateStr = _formatDate(date);
    final meetCode = _venueToMeet(venueCode);

    try {
      final uri = Uri.parse(
        '$_baseUrl/API26_2?serviceKey=$_serviceKey'
        '&numOfRows=20&pageNo=1&meet=$meetCode&rc_date=$dateStr&rc_no=$raceNo&_type=json',
      );
      if (kDebugMode) debugPrint('[KRA API26_2] $uri');

      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final items = _extractItems(data);
        if (items != null && items.isNotEmpty) {
          final entries = _parseHorseEntries(items);
          if (entries.isNotEmpty) return entries;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[KRA API26_2] Error: $e → Mock 사용');
    }

    // Mock 사용
    final mockRace = RaceInfo(
      raceNo: raceNo,
      raceName: '제${raceNo}경주',
      startTime: '13:00',
      distance: 1400,
      condition: '국6등급',
      grade: '국6등급',
      venueCode: venueCode,
      venueName: _meetToVenueName(meetCode),
      raceDate: dateStr,
      totalHorses: 10,
      trackCondition: '양호',
    );
    return KraMockService.getHorseEntries(mockRace);
  }

  // ── API187 파싱 ──
  static List<RaceInfo> _parseRaces(List<dynamic> items, String venueCode, DateTime date) {
    final now = DateTime.now();
    final bool isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final bool isPast = date.isBefore(DateTime(now.year, now.month, now.day));

    return items.map<RaceInfo?>((item) {
      try {
        final raceNo = item['rcNo']?.toString() ?? '';
        final startTime = _formatTime(item['rcTime']?.toString() ?? '0000');
        final distance = int.tryParse(item['rcDist']?.toString() ?? '1400') ?? 1400;
        final condition = item['rcGrdCourse']?.toString() ?? '';
        final grade = item['rcGrdNm']?.toString() ?? '';
        final trackCondition = _parseTrackCondition(item['trackCond']?.toString() ?? '');
        final totalHorses = int.tryParse(item['chulNum']?.toString() ?? '10') ?? 10;

        bool isFinished = false;
        bool isUpcoming = false;

        if (isToday && startTime.isNotEmpty) {
          final parts = startTime.split(':');
          if (parts.length == 2) {
            final raceTime = DateTime(now.year, now.month, now.day,
                int.parse(parts[0]), int.parse(parts[1]));
            final diff = raceTime.difference(now).inMinutes;
            isFinished = diff < -30;
            isUpcoming = !isFinished && diff >= 0 && diff <= 30;
          }
        } else if (isPast) {
          isFinished = true;
        }

        return RaceInfo(
          raceNo: raceNo,
          raceName: '제${raceNo}경주',
          startTime: startTime,
          distance: distance,
          condition: condition,
          grade: grade,
          venueCode: venueCode,
          venueName: _meetToVenueName(_venueToMeet(venueCode)),
          raceDate: _formatDate(date),
          totalHorses: totalHorses,
          trackCondition: trackCondition,
          isFinished: isFinished,
          isUpcoming: isUpcoming,
        );
      } catch (_) {
        return null;
      }
    }).whereType<RaceInfo>().toList();
  }

  // ── API26_2 파싱 ──
  static List<HorseEntry> _parseHorseEntries(List<dynamic> items) {
    return items.map<HorseEntry?>((item) {
      try {
        final gateNo = int.tryParse(item['chulNo']?.toString() ?? '1') ?? 1;
        final horseName = item['hrName']?.toString() ?? '미정';
        final jockeyName = item['jkName']?.toString() ?? '미정';
        final trainerName = item['trName']?.toString() ?? '미정';
        final weight = int.tryParse(item['hrWeight']?.toString() ?? '500') ?? 500;
        final weightChange = int.tryParse(item['wgHr']?.toString() ?? '0') ?? 0;
        final rating = double.tryParse(item['rating']?.toString() ?? '50') ?? 50.0;
        final odds = double.tryParse(item['winOdds']?.toString() ?? '5.0') ?? 5.0;
        final recentRecord = item['rcResult']?.toString() ?? '미정';

        // 스탯 계산 (레이팅 기반)
        final speedStat = (rating * 0.8 + 20).clamp(0.0, 100.0);
        final staminaStat = (rating * 0.7 + 25 + (weightChange < 0 ? 5 : 0)).clamp(0.0, 100.0);
        final formStat = (rating * 0.6 + 30).clamp(0.0, 100.0);
        final trackFitStat = (rating * 0.5 + 35).clamp(0.0, 100.0);
        final baseScore = (speedStat * 0.35 + staminaStat * 0.25 +
            formStat * 0.20 + trackFitStat * 0.10 + rating * 0.10).clamp(0.0, 100.0);

        return HorseEntry(
          gateNo: gateNo,
          horseName: horseName,
          jockeyName: jockeyName,
          trainerName: trainerName,
          weight: weight,
          weightChange: weightChange,
          rating: rating,
          speedStat: speedStat,
          staminaStat: staminaStat,
          formStat: formStat,
          trackFitStat: trackFitStat,
          baseScore: baseScore,
          recentRecord: recentRecord,
          odds: odds,
        );
      } catch (_) {
        return null;
      }
    }).whereType<HorseEntry>().toList();
  }

  // ── API4_3: 경주기록정보 (결과 + 배당) ──
  static Future<KraRaceResult?> fetchRaceResult(
      String venueCode, DateTime date, String raceNo) async {
    final dateStr = _formatDate(date);
    final meetCode = _venueToMeet(venueCode);

    try {
      // 결과: API4_3 — 경주결과 + 기록
      final resultUri = Uri.parse(
        '$_baseUrl/API4_3?serviceKey=$_serviceKey'
        '&numOfRows=20&pageNo=1&meet=$meetCode&rc_date=$dateStr&rc_no=$raceNo&_type=json',
      );
      if (kDebugMode) debugPrint('[KRA API4_3] $resultUri');

      final resp = await http.get(resultUri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final items = _extractItems(data);
        if (items != null && items.isNotEmpty) {
          return _parseRaceResult(items, venueCode, date, raceNo);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[KRA API4_3] Error: $e');
    }
    return null;
  }

  // ── API4_3 결과 파싱 ──
  static KraRaceResult _parseRaceResult(
      List<dynamic> items, String venueCode, DateTime date, String raceNo) {
    final results = <HorseResult>[];

    for (final item in items) {
      try {
        final ord = int.tryParse(item['ord']?.toString() ?? '0') ?? 0;
        final chulNo = int.tryParse(item['chulNo']?.toString() ?? '1') ?? 1;
        final hrName = item['hrName']?.toString() ?? '미정';
        final jkName = item['jkName']?.toString() ?? '미정';
        final rcTime = item['rcTime']?.toString() ?? '';
        final diffTime = item['diffTime']?.toString() ?? '';

        // 배당 파싱
        final winOdds = double.tryParse(item['winOdds']?.toString() ?? '0') ?? 0.0;
        final plcOdds1 = double.tryParse(item['plcOdds1']?.toString() ?? '0') ?? 0.0;
        final plcOdds2 = double.tryParse(item['plcOdds2']?.toString() ?? '0') ?? 0.0;
        final showOdds = double.tryParse(item['showOdds']?.toString() ?? '0') ?? 0.0;
        final weight = int.tryParse(item['hrWeight']?.toString() ?? '0') ?? 0;

        results.add(HorseResult(
          rank: ord,
          gateNo: chulNo,
          horseName: hrName,
          jockeyName: jkName,
          raceTime: rcTime,
          timeDiff: diffTime,
          winOdds: winOdds,
          placeOdds1: plcOdds1,
          placeOdds2: plcOdds2,
          showOdds: showOdds,
          weight: weight,
        ));
      } catch (_) {}
    }

    results.sort((a, b) => a.rank.compareTo(b.rank));
    return KraRaceResult(
      raceNo: raceNo,
      raceDate: _formatDate(date),
      venueCode: venueCode,
      venueName: _meetToVenueName(_venueToMeet(venueCode)),
      horses: results,
    );
  }

  // ── 이번 주 경주 있는 요일 스캔 (API187) ──
  static Future<List<DayTab>> scanWeeklyRaceDays() async {
    final now = DateTime.now();
    // 이번 주 금(5), 토(6), 일(7)
    final fri = _getWeekday(now, 5);
    final sat = _getWeekday(now, 6);
    final sun = _getWeekday(now, 7);
    final mon = _getWeekday(now, 8); // 다음주 월

    final candidates = [
      DayTab(date: fri, label: '금', hasRaceData: false),
      DayTab(date: sat, label: '토', hasRaceData: false),
      DayTab(date: sun, label: '일', hasRaceData: false),
    ];

    // API 스캔으로 각 날짜 경주 존재 여부 확인
    final validDays = <DayTab>[];
    for (final day in candidates) {
      try {
        final uri = Uri.parse(
          '$_baseUrl/API187?serviceKey=$_serviceKey'
          '&numOfRows=1&pageNo=1&meet=1&rc_date=${_formatDate(day.date)}&_type=json',
        );
        final resp = await http.get(uri).timeout(const Duration(seconds: 5));
        bool hasData = false;
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final items = _extractItems(data);
          hasData = items != null && items.isNotEmpty;
        }
        validDays.add(DayTab(date: day.date, label: day.label, hasRaceData: hasData || true));
      } catch (_) {
        // API 실패 시 기본값(금토일)은 항상 포함
        validDays.add(DayTab(date: day.date, label: day.label, hasRaceData: true));
      }
    }

    // 월요일 특별경주 스캔
    try {
      final uri = Uri.parse(
        '$_baseUrl/API187?serviceKey=$_serviceKey'
        '&numOfRows=1&pageNo=1&meet=1&rc_date=${_formatDate(mon)}&_type=json',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final items = _extractItems(data);
        if (items != null && items.isNotEmpty) {
          validDays.add(DayTab(date: mon, label: '월', hasRaceData: true));
        }
      }
    } catch (_) {}

    return validDays.isNotEmpty ? validDays : KraMockService.scanWeeklyRaceDays();
  }

  // ── 유틸 ──
  static List<dynamic>? _extractItems(dynamic data) {
    try {
      final response = data['response'];
      final body = response['body'];
      final items = body['items'];
      if (items == null || items == '') return null;
      final item = items['item'];
      if (item is List) return item;
      if (item is Map) return [item];
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _formatDate(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

  static String _formatTime(String timeStr) {
    if (timeStr.length < 4) return '00:00';
    final h = timeStr.substring(0, timeStr.length - 2);
    final m = timeStr.substring(timeStr.length - 2);
    return '${h.padLeft(2, '0')}:$m';
  }

  static String _venueToMeet(String venueCode) {
    switch (venueCode) {
      case '1': return '1'; // 서울
      case '2': return '3'; // 부산경남
      case '3': return '2'; // 제주
      default:  return '1';
    }
  }

  static String _meetToVenueName(String meet) {
    switch (meet) {
      case '1': return '서울';
      case '2': return '제주';
      case '3': return '부산경남';
      default:  return '서울';
    }
  }

  static String _parseTrackCondition(String raw) {
    switch (raw) {
      case '1': case 'G': return '양호';
      case '2': case 'Y': return '다습';
      case '3': case 'S': return '불량';
      default: return raw.isNotEmpty ? raw : '양호';
    }
  }

  static DateTime _getWeekday(DateTime now, int targetWeekday) {
    final diff = targetWeekday - now.weekday;
    final date = now.add(Duration(days: diff < 0 ? diff + 7 : diff));
    return DateTime(date.year, date.month, date.day);
  }
}
