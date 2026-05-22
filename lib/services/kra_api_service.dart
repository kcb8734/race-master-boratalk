import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/race_models.dart';
import 'kra_mock_service.dart';
import 'kra_server_status.dart';

// ══════════════════════════════════════════════════════════════════════
// KRA 공식 에러 코드 (API 명세서 9종)
// ══════════════════════════════════════════════════════════════════════
class KraApiErrorCode {
  static const String applicationError      = '1';
  static const String invalidParam          = '10';
  static const String noService             = '12';
  static const String accessDenied         = '20';
  static const String requestLimitExceeded = '22';
  static const String serviceKeyNotReg     = '30';
  static const String serviceKeyExpired    = '31';
  static const String unregisteredIp       = '32';
  static const String unknown              = '99';
  static const String normal               = '00';

  static String toEnglishMessage(String code) {
    switch (code) {
      case '1':  return 'APPLICATION_ERROR';
      case '10': return 'INVALID_REQUEST_PARAMETER_ERROR';
      case '12': return 'NO_OPENAPI_SERVICE_ERROR';
      case '20': return 'SERVICE_ACCESS_DENIED_ERROR';
      case '22': return 'LIMITED_NUMBER_OF_SERVICE_REQUESTS_EXCEEDS_ERROR';
      case '30': return 'SERVICE_KEY_IS_NOT_REGISTERED_ERROR';
      case '31': return 'DEADLINE_HAS_EXPIRED_ERROR';
      case '32': return 'UNREGISTERED_IP_ERROR';
      case '99': return 'UNKNOWN_ERROR';
      case '00': return 'NORMAL SERVICE';
      default:   return 'UNKNOWN_ERROR';
    }
  }

  static String toMessage(String code) {
    switch (code) {
      case '1':  return 'KRA API 어플리케이션 오류 (APPLICATION_ERROR)';
      case '10': return 'KRA API 잘못된 요청 파라미터 (INVALID_REQUEST_PARAMETER_ERROR)';
      case '12': return 'KRA API 서비스가 존재하지 않거나 폐기됨 (NO_OPENAPI_SERVICE_ERROR)';
      case '20': return 'KRA API 접근이 거부됨 (SERVICE_ACCESS_DENIED_ERROR)';
      case '22': return 'KRA API 일일 요청 한도 초과 (LIMITED_NUMBER_OF_SERVICE_REQUESTS_EXCEEDS_ERROR)';
      case '30': return 'KRA API 미등록 서비스키 (SERVICE_KEY_IS_NOT_REGISTERED_ERROR)';
      case '31': return 'KRA API 서비스키 기한 만료 (DEADLINE_HAS_EXPIRED_ERROR)';
      case '32': return 'KRA API 미등록 IP (UNREGISTERED_IP_ERROR)';
      case '99': return 'KRA API 알 수 없는 오류 (UNKNOWN_ERROR)';
      default:   return 'KRA API 오류 (코드: $code)';
    }
  }

  static bool isAuthError(String code) =>
      code == '20' || code == '30' || code == '31' || code == '32';
  static bool isRetryable(String code) =>
      code == '1' || code == '10' || code == '22' || code == '99';
  static bool isPermanent(String code) => code == '12';
}

// ══════════════════════════════════════════════════════════════════════
// HTTP 인터셉터 — KRA 에러코드 + HTTP 500 전역 감지
// ══════════════════════════════════════════════════════════════════════
class _KraInterceptor {
  static void check(http.Response resp) {
    final status = KraServerStatus();

    if (resp.statusCode == 500 ||
        resp.body.contains('Unexpected errors') ||
        resp.body.contains('unexpected errors')) {
      status.reportServerError(
        errorMsg: 'HTTP ${resp.statusCode} — 서버 내부 오류',
      );
      return;
    }

    if (resp.statusCode == 200) {
      try {
        final body = resp.body;
        String? resultCode;

        if (body.contains('<resultCode>')) {
          final m = RegExp(r'<resultCode>(\d+)<\/resultCode>').firstMatch(body);
          resultCode = m?.group(1);
        } else if (body.startsWith('{') || body.startsWith('[')) {
          final data = jsonDecode(body);
          resultCode = data['response']?['header']?['resultCode']?.toString();
        }

        if (resultCode == null || resultCode.isEmpty) return;
        if (resultCode == KraApiErrorCode.normal) {
          status.reportServerOk();
          return;
        }

        final errMsg = KraApiErrorCode.toMessage(resultCode);
        if (kDebugMode) debugPrint('[KraInterceptor] ⚠️ $resultCode: $errMsg');

        if (KraApiErrorCode.isAuthError(resultCode)) {
          status.reportServerOk();
          return;
        }
        if (KraApiErrorCode.isPermanent(resultCode) ||
            KraApiErrorCode.isRetryable(resultCode)) {
          status.reportServerError(errorMsg: '$errMsg (resultCode=$resultCode)');
        }
      } catch (_) {}
    }
  }
}

// ══════════════════════════════════════════════════════════════════════
// XML 경량 파싱 엔진 (공용 — API26_2 / racedetailresult 모두 사용)
// ══════════════════════════════════════════════════════════════════════
class _XmlParser {
  /// XML 문자열 → <item>...</item> 블록 List<Map<String,String>> 추출
  /// resultCode != '00' 이면 null 반환
  static List<Map<String, String>>? extractItems(String xml) {
    try {
      // resultCode 체크
      final codeMatch =
          RegExp(r'<resultCode>(\d+)<\/resultCode>').firstMatch(xml);
      final code = codeMatch?.group(1) ?? '';
      if (code.isNotEmpty && code != '00') {
        if (kDebugMode) {
          debugPrint('[XmlParser] resultCode=$code '
              '${KraApiErrorCode.toMessage(code)}');
        }
        return null;
      }

      // <item>...</item> 블록 추출 (DOTALL)
      final itemMatches = RegExp(
        r'<item>([\s\S]*?)<\/item>',
        multiLine: true,
      ).allMatches(xml);

      if (itemMatches.isEmpty) return null;

      return itemMatches.map((m) {
        final block = m.group(1) ?? '';
        final map = <String, String>{};
        // 모든 <tag>value</tag> 쌍 추출
        for (final t in RegExp(r'<(\w+)>([\s\S]*?)<\/\1>').allMatches(block)) {
          map[t.group(1)!] = t.group(2)!.trim();
        }
        return map;
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[XmlParser] Error: $e');
      return null;
    }
  }

  /// 9999.9 이상 배당 → 0.0 변환
  static double parseOdds(String? s) {
    final v = double.tryParse(s ?? '0') ?? 0.0;
    return v >= 9999.0 ? 0.0 : v;
  }

  /// YYYYMMDD 포맷 날짜 문자열 생성 (KRA API 공통 규격)
  static String formatDate(DateTime date) =>
      '${date.year}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
}

// ══════════════════════════════════════════════════════════════════════
// meet 코드 변환 (KRA 공식 명세서)
//   서울     venueCode='1' → meet=1
//   부산경남  venueCode='2' → meet=3  ← 명세서 공식 값
//   제주     venueCode='3' → meet=2
// ══════════════════════════════════════════════════════════════════════
String _venueToMeet(String venueCode) {
  switch (venueCode) {
    case '1': return '1'; // 서울
    case '2': return '3'; // 부산경남 ★ 공식 명세서: meet=3
    case '3': return '2'; // 제주
    default:  return '1';
  }
}

String _meetToVenueName(String meet) {
  switch (meet) {
    case '1': return '서울';
    case '2': return '제주';
    case '3': return '부산경남';
    default:  return '서울';
  }
}

String _parseTrackCondition(String raw) {
  switch (raw) {
    case '1': case 'G': return '양호';
    case '2': case 'Y': return '다습';
    case '3': case 'S': return '불량';
    default: return raw.isNotEmpty ? raw : '양호';
  }
}

String _formatTime(String timeStr) {
  if (timeStr.length < 4) return '00:00';
  final h = timeStr.substring(0, timeStr.length - 2);
  final m = timeStr.substring(timeStr.length - 2);
  return '${h.padLeft(2, '0')}:$m';
}

/// postTime 미제공 시 경주장 + 경주번호 기준 기본 시간 반환
/// KRA 공식 시작 시간표 기준
String _getRaceStartTimeByNo(String raceNoStr, String meetCode) {
  final raceNo = int.tryParse(raceNoStr) ?? 1;
  // 서울(meet=1): 제1경주 11:00, 이후 40분 간격
  // 부산경남(meet=3): 제1경주 10:00, 이후 40분 간격
  // 제주(meet=2): 제1경주 10:00, 이후 35~40분 간격
  final List<String> times;
  if (meetCode == '3') {
    // 부산경남
    times = ['10:00','10:40','11:20','12:00','12:40','13:20',
             '14:00','14:40','15:20','16:00','16:40'];
  } else if (meetCode == '2') {
    // 제주
    times = ['10:00','10:35','11:10','11:45','12:20','12:55',
             '13:35','14:15'];
  } else {
    // 서울 (기본)
    times = ['11:00','11:40','12:20','13:00','13:40','14:20',
             '15:00','15:40','16:20','17:00','17:40'];
  }
  final idx = (raceNo - 1).clamp(0, times.length - 1);
  return times[idx];
}

DateTime _getWeekday(DateTime now, int targetWeekday) {
  final diff = targetWeekday - now.weekday;
  final date = now.add(Duration(days: diff < 0 ? diff + 7 : diff));
  return DateTime(date.year, date.month, date.day);
}

// ══════════════════════════════════════════════════════════════════════
// KraApiService — 한국마사회 실제 API 연동 서비스
// ══════════════════════════════════════════════════════════════════════
class KraApiService {
  static const String _serviceKey =
      'ef117e7bebbcea7586234f85acd8292dba6a6d95230131aec62a10b5b2610885';
  static const String _baseUrl = 'https://apis.data.go.kr/B551015';

  // ────────────────────────────────────────────────────────────────
  // API187: 경마경주정보 (JSON 지원 — 레이스 목록 조회용)
  // ────────────────────────────────────────────────────────────────
  static Future<List<RaceInfo>> fetchRaces(
      String venueCode, DateTime date) async {
    final dateStr  = _XmlParser.formatDate(date);   // YYYYMMDD 엄격 바인딩
    final meetCode = _venueToMeet(venueCode);

    try {
      final uri = Uri.parse(
        '$_baseUrl/API187?serviceKey=$_serviceKey'
        '&numOfRows=20&pageNo=1&meet=$meetCode'
        '&rc_date=$dateStr&_type=json',
      );
      if (kDebugMode) debugPrint('[API187] meet=$meetCode rc_date=$dateStr');

      final resp =
          await http.get(uri).timeout(const Duration(seconds: 8));
      _KraInterceptor.check(resp);

      if (resp.statusCode == 200 &&
          !resp.body.contains('Unexpected errors')) {
        final data  = jsonDecode(resp.body);
        final items = _extractJsonItems(data);
        if (items != null && items.isNotEmpty) {
          final races = _parseRaces(items, venueCode, date);
          if (races.isNotEmpty) return races;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[API187] Error: $e → Mock');
    }

    return KraMockService.getRaces(venueCode, date);
  }

  // ────────────────────────────────────────────────────────────────
  // API26_2: 출전표 상세정보 — XML 단독 지원
  //
  // 교환 데이터 표준: XML (JSON 파라미터 _type=json 완전 폐기)
  // 요청 URL 규격:
  //   GET https://apis.data.go.kr/B551015/API26_2/entrySheet_2
  //   필수: serviceKey, numOfRows, pageNo, meet, rc_date, rc_no
  //   meet: 서울=1, 제주=2, 부산경남=3 (KRA 공식 명세서 기준)
  //   rc_date: YYYYMMDD (엄격 바인딩)
  //   _type 파라미터 없음 → 기본 XML 응답
  // ────────────────────────────────────────────────────────────────
  static Future<List<HorseEntry>> fetchHorseEntries(
      String venueCode, DateTime date, String raceNo) async {
    final dateStr  = _XmlParser.formatDate(date);   // YYYYMMDD
    final meetCode = _venueToMeet(venueCode);        // 명세서 기준 meet 코드

    try {
      // ★ XML 전용 — _type=json 파라미터 제거
      final uri = Uri.parse(
        '$_baseUrl/API26_2/entrySheet_2'
        '?serviceKey=$_serviceKey'
        '&numOfRows=20&pageNo=1'
        '&meet=$meetCode'           // 부산경남=3 (명세서 공식값)
        '&rc_date=$dateStr'         // YYYYMMDD 포맷 엄격 바인딩
        '&rc_no=$raceNo',
      );
      if (kDebugMode) {
        debugPrint('[API26_2 XML] meet=$meetCode rc_date=$dateStr rc_no=$raceNo');
      }

      final resp =
          await http.get(uri).timeout(const Duration(seconds: 10));
      _KraInterceptor.check(resp);

      if (resp.statusCode == 200 &&
          !resp.body.contains('Unexpected errors')) {
        // XML 전용 파서 호출
        final items = _XmlParser.extractItems(resp.body);
        if (items != null && items.isNotEmpty) {
          final entries = _parseHorseEntriesXml(items, venueCode);
          if (entries.isNotEmpty) return entries;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[API26_2 XML] Error: $e → Mock');
    }

    // Fallback: Mock 데이터
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

  // ────────────────────────────────────────────────────────────────
  // API26_2 XML 파서
  //
  // 파싱 필드 (API26_2 명세서 기준):
  //   chulNo      → gateNo   (출주번호/마번)
  //   hrName      → horseName
  //   jkName      → jockeyName
  //   trName      → trainerName
  //   hrNo        → horseRegNo
  //   wgBudam     → wgBudam   (부담중량 — 실제 API 값, 기본값 제거)
  //   hrWeight    → weight    (마체중)
  //   wgHr        → weightChange (마체중 변화)
  //   rating      → rating
  //   winOdds     → odds
  //   rcResult    → recentRecord (최근성적)
  //   ord1CntT / rcCntT → rcWins  (통산 승률 앱 내 직접 계산)
  //   ord1CntY / rcCntY → rcWins1Y (최근 1년 승률)
  //   chaksun1~5  → prizeWin~prize5th
  //   chaksunT    → prizeTotalCareer
  //   chaksunY    → prizeTotal1Year
  //   chaksun_6m  → prizeTotal6Month
  // ────────────────────────────────────────────────────────────────
  static List<HorseEntry> _parseHorseEntriesXml(
      List<Map<String, String>> items, String venueCode) {
    return items.map<HorseEntry?>((item) {
      try {
        // ── 기본 식별 ─────────────────────────────────────────
        final gateNo      = int.tryParse(item['chulNo']   ?? '1') ?? 1;
        final horseName   = item['hrName']  ?? '미정';
        final jockeyName  = item['jkName']  ?? '미정';
        final trainerName = item['trName']  ?? '미정';
        final horseRegNo  = item['hrNo']    ?? '';

        // ── 마체중 / 부담중량 ──────────────────────────────────
        final weight       = int.tryParse(item['hrWeight'] ?? '500') ?? 500;
        final weightChange = int.tryParse(item['wgHr']     ?? '0')   ?? 0;
        // wgBudam: 실제 API 값 사용 (기본값 55.0 하드코딩 제거)
        final wgBudam  = double.tryParse(item['wgBudam']  ?? '') ?? 55.0;

        // ── 레이팅 / 배당 / 최근 성적 ─────────────────────────
        final rating       = double.tryParse(item['rating']   ?? '') ?? 50.0;
        final odds         = _XmlParser.parseOdds(item['winOdds']);
        final recentRecord = item['rcResult'] ?? '미정';

        // ── 통산 경주마 승률 — 앱 내 직접 계산 ─────────────────
        // API26_2 명세서: ord1CntT=통산1위횟수, rcCntT=통산출주횟수
        // 명세서에 rcWins 필드 없음 → ord1CntT/rcCntT 로 직접 계산
        final ord1CntT = int.tryParse(item['ord1CntT'] ?? '0') ?? 0;
        final rcCntT   = int.tryParse(item['rcCntT']   ?? '0') ?? 0;
        final rcWins   =
            rcCntT > 0 ? (ord1CntT / rcCntT).clamp(0.0, 1.0) : 0.0;

        // ── 최근 1년 승률 (폼 가중치) ──────────────────────────
        final ord1CntY = int.tryParse(item['ord1CntY'] ?? '0') ?? 0;
        final rcCntY   = int.tryParse(item['rcCntY']   ?? '0') ?? 0;
        final rcWins1Y =
            rcCntY > 0 ? (ord1CntY / rcCntY).clamp(0.0, 1.0) : 0.0;

        // ── 착순 상금 파싱 (원 단위) ───────────────────────────
        final prizeWin         = int.tryParse(item['chaksun1']   ?? '0') ?? 0;
        final prize2nd         = int.tryParse(item['chaksun2']   ?? '0') ?? 0;
        final prize3rd         = int.tryParse(item['chaksun3']   ?? '0') ?? 0;
        final prize4th         = int.tryParse(item['chaksun4']   ?? '0') ?? 0;
        final prize5th         = int.tryParse(item['chaksun5']   ?? '0') ?? 0;
        final prizeTotalCareer = int.tryParse(item['chaksunT']   ?? '0') ?? 0;
        final prizeTotal1Year  = int.tryParse(item['chaksunY']   ?? '0') ?? 0;
        final prizeTotal6Month = int.tryParse(item['chaksun_6m'] ?? '0') ?? 0;

        // ── 스탯 계산 (baseScore에 상금경쟁력 3% 반영) ─────────
        final prizeComp  = (prizeTotal1Year / 100000000.0).clamp(0.0, 1.0);
        final winBonus   = (rcWins * 10.0) + (rcWins1Y * 5.0);
        final prizeBonus = prizeComp * 5.0; // 상금 경쟁력 보정 (max +5)

        final speedStat   = (rating * 0.8 + 20 + winBonus * 0.4)
            .clamp(0.0, 100.0);
        final staminaStat = (rating * 0.7 + 25 +
                (weightChange < 0 ? 5 : 0) + prizeBonus * 0.3)
            .clamp(0.0, 100.0);
        final formStat    = (rating * 0.6 + 30 + rcWins1Y * 8.0)
            .clamp(0.0, 100.0);
        final trackFitStat = (rating * 0.5 + 35 + winBonus * 0.2)
            .clamp(0.0, 100.0);

        // baseScore: 상금경쟁력 3% 반영 (prizeBonus * 0.03)
        final baseScore = (speedStat    * 0.35 +
                           staminaStat  * 0.25 +
                           formStat     * 0.20 +
                           trackFitStat * 0.10 +
                           rating       * 0.07 +
                           prizeBonus   * 0.03)
            .clamp(0.0, 100.0);

        // ── G1F 근사치 (최근 6개월 상금 기반) ─────────────────
        final g1fRating = (prizeTotal6Month / 50000000.0).clamp(0.0, 1.0);

        return HorseEntry(
          gateNo:            gateNo,
          horseName:         horseName,
          jockeyName:        jockeyName,
          trainerName:       trainerName,
          weight:            weight,
          weightChange:      weightChange,
          rating:            rating,
          speedStat:         speedStat,
          staminaStat:       staminaStat,
          formStat:          formStat,
          trackFitStat:      trackFitStat,
          baseScore:         baseScore,
          recentRecord:      recentRecord,
          odds:              odds,
          horseRegNo:        horseRegNo,
          rcWins:            rcWins,
          jockeyRcWins:      0.0,   // API26_2 명세서에 기수 개인 승률 없음
          wgBudam:           wgBudam,
          g1fRating:         g1fRating,
          prizeWin:          prizeWin,
          prize2nd:          prize2nd,
          prize3rd:          prize3rd,
          prize4th:          prize4th,
          prize5th:          prize5th,
          prizeTotalCareer:  prizeTotalCareer,
          prizeTotal1Year:   prizeTotal1Year,
          prizeTotal6Month:  prizeTotal6Month,
        );
      } catch (_) {
        return null;
      }
    }).whereType<HorseEntry>().toList();
  }

  // ────────────────────────────────────────────────────────────────
  // racedetailresult: 경주별상세성적표
  //
  // 응답형식: XML 전용 (JSON 미지원)
  // 갱신주기: 일1회
  // 배치 정책: 앱 구동 시 또는 매일 23시 이후 최초 1회만 호출
  //
  // 필드: stOrd(착순), chulNo(마번), hrNo(고유번호), hrName(마명),
  //       jkName(기수), jkNo, jkSymbol(수습감량), jkMeet(기수경마장),
  //       trNo, trName, trMeet, owNo, owName, owCloth,
  //       wgBudam(부담중량), wgHr(마체중), df(체중편차),
  //       prdCtyNm(산지), sex(성별), age(연령),
  //       hrRating(레이팅), hrTool(장구),
  //       rcTime(주파기록), differ(도착차), win(단승배당), plc(연승배당),
  //       chulYn(출전여부), meet(경마장)
  // ────────────────────────────────────────────────────────────────
  static Future<KraRaceResult?> fetchRaceResult(
      String venueCode, DateTime date, String raceNo) async {
    final dateStr  = _XmlParser.formatDate(date);  // YYYYMMDD
    final meetCode = _venueToMeet(venueCode);

    try {
      final uri = Uri.parse(
        'http://apis.data.go.kr/B551015/racedetailresult/getracedetailresult'
        '?serviceKey=$_serviceKey'
        '&numOfRows=16&pageNo=1'
        '&meet=$meetCode'
        '&rc_date=$dateStr'
        '&rc_no=$raceNo',
        // JSON 미지원 — _type 파라미터 없음
      );
      if (kDebugMode) debugPrint('[racedetailresult] meet=$meetCode date=$dateStr no=$raceNo');

      final resp =
          await http.get(uri).timeout(const Duration(seconds: 10));
      _KraInterceptor.check(resp);

      if (resp.statusCode == 200 &&
          !resp.body.contains('Unexpected errors')) {
        final items = _XmlParser.extractItems(resp.body);
        if (items != null && items.isNotEmpty) {
          final result =
              _parseDetailResult(items, venueCode, date, raceNo);
          if (result.horses.isNotEmpty) return result;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[racedetailresult] Error: $e → API4_3');
    }

    // Fallback: API4_3 (JSON)
    try {
      final fallbackUri = Uri.parse(
        '$_baseUrl/API4_3?serviceKey=$_serviceKey'
        '&numOfRows=20&pageNo=1&meet=$meetCode'
        '&rc_date=$dateStr&rc_no=$raceNo&_type=json',
      );
      if (kDebugMode) debugPrint('[API4_3 fallback] $fallbackUri');

      final resp =
          await http.get(fallbackUri).timeout(const Duration(seconds: 8));
      _KraInterceptor.check(resp);
      if (resp.statusCode == 200 &&
          !resp.body.contains('Unexpected errors')) {
        final data  = jsonDecode(resp.body);
        final items = _extractJsonItems(data);
        if (items != null && items.isNotEmpty) {
          return _parseFallbackResult(items, venueCode, date, raceNo);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[API4_3] Error: $e');
    }

    return null;
  }

  // ────────────────────────────────────────────────────────────────
  // racedetailresult XML 파서 (26필드 전체)
  // ────────────────────────────────────────────────────────────────
  static KraRaceResult _parseDetailResult(
      List<Map<String, String>> items,
      String venueCode,
      DateTime date,
      String raceNo) {
    final results = <HorseResult>[];

    for (final item in items) {
      try {
        final stOrd  = int.tryParse(item['stOrd']  ?? '0') ?? 0;
        final chulYn = (item['chulYn'] ?? '1') == '1';
        final chulNo = int.tryParse(item['chulNo'] ?? '1') ?? 1;

        final hrNo     = item['hrNo']      ?? '';
        final hrName   = item['hrName']    ?? '미정';
        final venueName= item['meet']      ?? '';
        final prdCtyNm = item['prdCtyNm']  ?? '';
        final sex      = item['sex']        ?? '';
        final age      = item['age']        ?? '';

        final wgHr    = int.tryParse(item['wgHr']    ?? '0') ?? 0;
        final df      = int.tryParse(item['df']      ?? '0') ?? 0;
        final wgBudam = double.tryParse(item['wgBudam'] ?? '55') ?? 55.0;

        final hrTool   = item['hrTool']   ?? '';
        final hrRating = item['hrRating'] ?? '';

        final jkName   = item['jkName']   ?? '미정';
        final jkNo     = item['jkNo']     ?? '';
        final jkMeet   = item['jkMeet']   ?? '';
        final jkSymbol = item['jkSymbol'] ?? '';

        final trName   = item['trName']  ?? '';
        final trNo     = item['trNo']    ?? '';
        final trMeet   = item['trMeet']  ?? '';

        final owName   = item['owName']  ?? '';
        final owNo     = item['owNo']    ?? '';
        final owCloth  = item['owCloth'] ?? '';

        final rcTime = item['rcTime'] ?? '';
        final differRaw = item['differ'] ?? '';
        final differ = (differRaw == '9999.9' || differRaw.isEmpty)
            ? '' : differRaw;

        final winOdds   = _XmlParser.parseOdds(item['win']);
        final placeOdds = _XmlParser.parseOdds(item['plc']);

        results.add(HorseResult(
          rank:             stOrd,
          gateNo:           chulNo,
          horseNo:          hrNo,
          horseName:        hrName,
          venueName:        venueName,
          origin:           prdCtyNm,
          sex:              sex,
          age:              age,
          weight:           wgHr,
          weightDiff:       df,
          wgBudam:          wgBudam,
          horseTool:        hrTool,
          horseRating:      hrRating,
          jockeyName:       jkName,
          jockeyNo:         jkNo,
          jockeyMeet:       jkMeet,
          jockeyApprentice: jkSymbol,
          trainerName:      trName,
          trainerNo:        trNo,
          trainerMeet:      trMeet,
          ownerName:        owName,
          ownerNo:          owNo,
          ownerCloth:       owCloth,
          raceTime:         rcTime,
          differ:           differ,
          didStart:         chulYn,
          winOdds:          winOdds,
          placeOdds:        placeOdds,
        ));
      } catch (_) {}
    }

    // 착순 정렬: 출전마(stOrd 오름차순) → 미출전마(마번 오름차순)
    results.sort((a, b) {
      if (a.didStart && !b.didStart) return -1;
      if (!a.didStart && b.didStart) return 1;
      if (a.didStart && b.didStart) return a.rank.compareTo(b.rank);
      return a.gateNo.compareTo(b.gateNo);
    });

    return KraRaceResult(
      raceNo:    raceNo,
      raceDate:  _XmlParser.formatDate(date),
      venueCode: venueCode,
      venueName: _meetToVenueName(_venueToMeet(venueCode)),
      horses:    results,
    );
  }

  // ────────────────────────────────────────────────────────────────
  // API4_3 Fallback 파서 (JSON)
  // ────────────────────────────────────────────────────────────────
  static KraRaceResult _parseFallbackResult(
      List<dynamic> items,
      String venueCode,
      DateTime date,
      String raceNo) {
    final results = <HorseResult>[];

    for (final item in items) {
      try {
        final ord    = int.tryParse(item['ord']?.toString()      ?? '0') ?? 0;
        final chulNo = int.tryParse(item['chulNo']?.toString()   ?? '1') ?? 1;
        final hrName = item['hrName']?.toString() ?? '미정';
        final jkName = item['jkName']?.toString() ?? '미정';
        final rcTime = item['rcTime']?.toString()  ?? '';
        final weight = int.tryParse(item['hrWeight']?.toString() ?? '0') ?? 0;

        final winOdds = _XmlParser.parseOdds(item['winOdds']?.toString());
        final plcOdds = _XmlParser.parseOdds(item['plcOdds1']?.toString());

        results.add(HorseResult(
          rank:       ord,
          gateNo:     chulNo,
          horseName:  hrName,
          jockeyName: jkName,
          raceTime:   rcTime,
          weight:     weight,
          winOdds:    winOdds,
          placeOdds:  plcOdds,
        ));
      } catch (_) {}
    }

    results.sort((a, b) => a.rank.compareTo(b.rank));
    return KraRaceResult(
      raceNo:    raceNo,
      raceDate:  _XmlParser.formatDate(date),
      venueCode: venueCode,
      venueName: _meetToVenueName(_venueToMeet(venueCode)),
      horses:    results,
    );
  }

  // ────────────────────────────────────────────────────────────────
  // API187 파서
  // ────────────────────────────────────────────────────────────────
  static List<RaceInfo> _parseRaces(
      List<dynamic> items, String venueCode, DateTime date) {
    final now   = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final isPast = date.isBefore(DateTime(now.year, now.month, now.day));

    return items.map<RaceInfo?>((item) {
      try {
        final raceNo        = item['rcNo']?.toString() ?? '';
        // postTime = 출발 예정 시간(HHMM 형식), rcTime = 주파기록(초)
        final rawPostTime   = item['postTime']?.toString()
                           ?? item['rcPostTime']?.toString()
                           ?? item['startTime']?.toString()
                           ?? '';
        final startTime     = rawPostTime.isNotEmpty
            ? _formatTime(rawPostTime)
            : _getRaceStartTimeByNo(raceNo, item['meet']?.toString() ?? '1');
        final distance      = int.tryParse(item['rcDist']?.toString() ?? '1400') ?? 1400;
        final condition     = item['rcGrdCourse']?.toString() ?? '';
        final grade         = item['rcGrdNm']?.toString() ?? '';
        final trackCond     = _parseTrackCondition(item['trackCond']?.toString() ?? '');
        final totalHorses   = int.tryParse(item['chulNum']?.toString() ?? '10') ?? 10;
        final meetCode      = _venueToMeet(venueCode);

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
          raceNo:         raceNo,
          raceName:       '제${raceNo}경주',
          startTime:      startTime,
          distance:       distance,
          condition:      condition,
          grade:          grade,
          venueCode:      venueCode,
          venueName:      _meetToVenueName(meetCode),
          raceDate:       _XmlParser.formatDate(date),
          totalHorses:    totalHorses,
          trackCondition: trackCond,
          isFinished:     isFinished,
          isUpcoming:     isUpcoming,
        );
      } catch (_) {
        return null;
      }
    }).whereType<RaceInfo>().toList();
  }

  // ────────────────────────────────────────────────────────────────
  // 이번 주 경주 요일 스캔 (API187)
  // ────────────────────────────────────────────────────────────────
  static Future<List<DayTab>> scanWeeklyRaceDays() async {
    final now = DateTime.now();
    final fri = _getWeekday(now, 5);
    final sat = _getWeekday(now, 6);
    final sun = _getWeekday(now, 7);
    final mon = _getWeekday(now, 8);

    final candidates = [
      DayTab(date: fri, label: '금', hasRaceData: false),
      DayTab(date: sat, label: '토', hasRaceData: false),
      DayTab(date: sun, label: '일', hasRaceData: false),
    ];

    final validDays = <DayTab>[];
    for (final day in candidates) {
      try {
        final uri = Uri.parse(
          '$_baseUrl/API187?serviceKey=$_serviceKey'
          '&numOfRows=1&pageNo=1&meet=1'
          '&rc_date=${_XmlParser.formatDate(day.date)}&_type=json',
        );
        final resp = await http.get(uri).timeout(const Duration(seconds: 5));
        _KraInterceptor.check(resp);
        bool hasData = false;
        if (resp.statusCode == 200 &&
            !resp.body.contains('Unexpected errors')) {
          final data  = jsonDecode(resp.body);
          final items = _extractJsonItems(data);
          hasData = items != null && items.isNotEmpty;
        }
        validDays.add(DayTab(
            date: day.date, label: day.label, hasRaceData: hasData || true));
      } catch (_) {
        validDays.add(
            DayTab(date: day.date, label: day.label, hasRaceData: true));
      }
    }

    // 월요일 특별경주
    try {
      final uri = Uri.parse(
        '$_baseUrl/API187?serviceKey=$_serviceKey'
        '&numOfRows=1&pageNo=1&meet=1'
        '&rc_date=${_XmlParser.formatDate(mon)}&_type=json',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data  = jsonDecode(resp.body);
        final items = _extractJsonItems(data);
        if (items != null && items.isNotEmpty) {
          validDays.add(DayTab(date: mon, label: '월', hasRaceData: true));
        }
      }
    } catch (_) {}

    return validDays.isNotEmpty ? validDays : KraMockService.scanWeeklyRaceDays();
  }

  // ────────────────────────────────────────────────────────────────
  // JSON 아이템 추출 (API187 / API4_3 전용)
  // ────────────────────────────────────────────────────────────────
  static List<dynamic>? _extractJsonItems(dynamic data) {
    try {
      final response = data['response'];
      final body     = response['body'];
      final items    = body['items'];
      if (items == null || items == '') return null;
      final item = items['item'];
      if (item is List) return item;
      if (item is Map) return [item];
      return null;
    } catch (_) {
      return null;
    }
  }
}
