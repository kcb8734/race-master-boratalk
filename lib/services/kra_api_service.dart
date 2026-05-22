import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/race_models.dart';
import 'kra_mock_service.dart';
import 'kra_server_status.dart';

// ── KRA 공식 에러 코드 정의 ────────────────────────────────────
// 출처: KRA 공공데이터포털 API26_2 명세서 (OpenAPI 에러코드 정리)
// https://apis.data.go.kr/B551015/API26_2
class KraApiErrorCode {
  static const String applicationError       = '1';   // 어플리케이션 에러
  static const String invalidParam           = '10';  // 잘못된 요청 파라미터
  static const String noService              = '12';  // 해당 오픈API 서비스 없거나 폐기됨
  static const String accessDenied          = '20';  // 서비스 접근 거부
  static const String requestLimitExceeded  = '22';  // 서비스 요청 제한 횟수 초과
  static const String serviceKeyNotReg      = '30';  // 등록되지 않은 서비스키
  static const String serviceKeyExpired     = '31';  // 기한 만료된 서비스키
  static const String unregisteredIp        = '32';  // 등록되지 않은 IP
  static const String unknown               = '99';  // 기타 에러
  static const String normal                = '00';  // 정상

  /// 에러 코드 → 공식 영문 에러메시지명 (OpenAPI 명세서 기준)
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

  /// 에러 코드 → 사용자 친화 메시지 변환 (국문)
  static String toMessage(String code) {
    switch (code) {
      case '1':  return 'KRA API 어플리케이션 오류 (APPLICATION_ERROR)';
      case '10': return 'KRA API 잘못된 요청 파라미터 (INVALID_REQUEST_PARAMETER_ERROR)';
      case '12': return 'KRA API 서비스가 존재하지 않거나 폐기되었습니다 (NO_OPENAPI_SERVICE_ERROR)';
      case '20': return 'KRA API 접근이 거부되었습니다 (SERVICE_ACCESS_DENIED_ERROR)';
      case '22': return 'KRA API 일일 요청 한도 초과 (LIMITED_NUMBER_OF_SERVICE_REQUESTS_EXCEEDS_ERROR)';
      case '30': return 'KRA API 미등록 서비스키 (SERVICE_KEY_IS_NOT_REGISTERED_ERROR)';
      case '31': return 'KRA API 서비스키 기한 만료 (DEADLINE_HAS_EXPIRED_ERROR)';
      case '32': return 'KRA API 미등록 IP (UNREGISTERED_IP_ERROR)';
      case '99': return 'KRA API 알 수 없는 오류 (UNKNOWN_ERROR)';
      default:   return 'KRA API 오류 (코드: $code)';
    }
  }

  /// 서비스키 관련 오류 여부 (30, 31, 32, 20)
  static bool isAuthError(String code) =>
      code == '20' || code == '30' || code == '31' || code == '32';

  /// 일시적 오류 여부 (1, 10, 22, 99) — 재시도 의미 있음
  static bool isRetryable(String code) =>
      code == '1' || code == '10' || code == '22' || code == '99';

  /// 영구적 오류 여부 (12) — 재시도 불필요
  static bool isPermanent(String code) => code == '12';
}

// ── HTTP 500 / KRA 공식 에러코드 인터셉터 ───────────────────────
// 모든 KRA API 응답을 통과시키며 장애 여부를 전역 KraServerStatus에 보고
// 지원 에러코드: 1, 10, 12, 20, 22, 30, 31, 32, 99 (API 명세서 전체)
class _KraInterceptor {
  static void check(http.Response resp) {
    final status = KraServerStatus();

    // ── HTTP 레벨 장애 감지 ──────────────────────────────────────
    if (resp.statusCode == 500 ||
        resp.body.contains('Unexpected errors') ||
        resp.body.contains('unexpected errors')) {
      status.reportServerError(
        errorMsg: 'HTTP ${resp.statusCode} — 서버 내부 오류 (Unexpected errors)',
      );
      return;
    }

    // ── HTTP 200 이지만 KRA 공식 에러코드 포함 여부 확인 ─────────
    if (resp.statusCode == 200) {
      try {
        // XML 응답인 경우 resultCode 태그로 추출
        final body = resp.body;
        String? resultCode;

        if (body.contains('<resultCode>')) {
          // XML 파싱: <resultCode>XX</resultCode>
          final match = RegExp(r'<resultCode>(\d+)<\/resultCode>').firstMatch(body);
          resultCode = match?.group(1);
        } else {
          // JSON 파싱
          final data = jsonDecode(body);
          resultCode = data['response']?['header']?['resultCode']?.toString();
        }

        if (resultCode == null || resultCode.isEmpty) {
          // resultCode 없음 → JSON/XML 구조 이상
          return;
        }

        if (resultCode == KraApiErrorCode.normal) {
          // ✅ 00 = 정상 → 장애 해제
          status.reportServerOk();
          return;
        }

        // ── KRA 공식 에러코드 처리 ────────────────────────────────
        final errMsg = KraApiErrorCode.toMessage(resultCode);
        if (kDebugMode) {
          debugPrint('[_KraInterceptor] ⚠️ KRA 에러코드 $resultCode: $errMsg');
        }

        // 서비스키·접근 권한 에러(20,30,31,32): 서버는 살아있음 → 장애로 취급하지 않음
        if (KraApiErrorCode.isAuthError(resultCode)) {
          // 서버 자체는 정상이므로 reportServerOk()
          // 단, 인증 관련 에러이므로 디버그 로그만 출력
          if (kDebugMode) {
            debugPrint('[_KraInterceptor] 🔑 인증 관련 오류 ($resultCode) — 서버 자체는 정상');
          }
          status.reportServerOk();
          return;
        }

        // 서비스 폐기(12): 영구 오류 → 장애로 보고
        if (KraApiErrorCode.isPermanent(resultCode)) {
          status.reportServerError(
            errorMsg: '$errMsg (resultCode=$resultCode)',
          );
          return;
        }

        // 일시적 오류(1, 10, 22, 99): 장애로 보고 (재시도 가능)
        if (KraApiErrorCode.isRetryable(resultCode)) {
          status.reportServerError(
            errorMsg: '$errMsg (resultCode=$resultCode)',
          );
          return;
        }

        // 그 외 알 수 없는 코드
        if (kDebugMode) {
          debugPrint('[_KraInterceptor] ❓ 미정의 resultCode=$resultCode');
        }

      } catch (_) {
        // 파싱 실패 → 무시 (정상 응답으로 처리)
      }
    }
  }
}

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
      _KraInterceptor.check(resp); // ★ HTTP 500 인터셉터
      if (resp.statusCode == 200 &&
          !resp.body.contains('Unexpected errors')) {
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
      _KraInterceptor.check(resp); // ★ HTTP 500 인터셉터
      if (resp.statusCode == 200 &&
          !resp.body.contains('Unexpected errors')) {
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

  // ── API26_2 파싱 ──────────────────────────────────────────────
  // entrySheet_2 응답 필드 전체 활용:
  //   chulNo → gateNo
  //   hrName → horseName
  //   jkName → jockeyName
  //   trName → trainerName
  //   hrNo   → horseRegNo
  //   wgBudam → wgBudam (부담중량, 실제 API 값 사용)
  //   rating  → rating
  //   ord1CntT / rcCntT → rcWins (통산 경주마 승률 직접 계산)
  //   chaksun1~5   → prizeWin~prize5th (이번 경주 착순 상금)
  //   chaksunT     → prizeTotalCareer  (통산 수득 상금)
  //   chaksunY     → prizeTotal1Year   (최근 1년 수득 상금)
  //   chaksun_6m   → prizeTotal6Month  (최근 6개월 수득 상금)
  // ─────────────────────────────────────────────────────────────
  static List<HorseEntry> _parseHorseEntries(List<dynamic> items) {
    return items.map<HorseEntry?>((item) {
      try {
        // ── 기본 식별 정보 ──────────────────────────────────────
        final gateNo       = int.tryParse(item['chulNo']?.toString() ?? '1') ?? 1;
        final horseName    = item['hrName']?.toString() ?? '미정';
        final jockeyName   = item['jkName']?.toString() ?? '미정';
        final trainerName  = item['trName']?.toString() ?? '미정';
        final horseRegNo   = item['hrNo']?.toString() ?? '';

        // ── 체중 / 부담중량 ────────────────────────────────────
        final weight       = int.tryParse(item['hrWeight']?.toString() ?? '500') ?? 500;
        final weightChange = int.tryParse(item['wgHr']?.toString() ?? '0') ?? 0;
        // wgBudam: API26_2 실제 필드 (예: "53" → 53.0 kg)
        final wgBudam      = double.tryParse(item['wgBudam']?.toString() ?? '55') ?? 55.0;

        // ── 레이팅 / 배당 / 성적 ──────────────────────────────
        final ratingRaw    = item['rating']?.toString() ?? '';
        final rating       = double.tryParse(ratingRaw) ?? 50.0;
        final odds         = double.tryParse(item['winOdds']?.toString() ?? '5.0') ?? 5.0;
        final recentRecord = item['rcResult']?.toString() ?? '미정';

        // ── 통산 경주마 승률 직접 계산 ─────────────────────────
        // ord1CntT: 통산1위횟수 / rcCntT: 통산출주횟수
        final ord1CntT = int.tryParse(item['ord1CntT']?.toString() ?? '0') ?? 0;
        final rcCntT   = int.tryParse(item['rcCntT']?.toString() ?? '0') ?? 0;
        // 0으로 나누기 방지: 출주 이력 없으면 0.0
        final rcWins   = rcCntT > 0 ? (ord1CntT / rcCntT).clamp(0.0, 1.0) : 0.0;

        // ── 최근 1년 승률 (복수 지표 가중 평균) ─────────────────
        // ord1CntY / rcCntY 기반 최근 폼 반영
        final ord1CntY = int.tryParse(item['ord1CntY']?.toString() ?? '0') ?? 0;
        final rcCntY   = int.tryParse(item['rcCntY']?.toString() ?? '0') ?? 0;
        final rcWins1Y = rcCntY > 0 ? (ord1CntY / rcCntY).clamp(0.0, 1.0) : 0.0;

        // ── 착순 상금 파싱 (원 단위) ───────────────────────────
        final prizeWin        = int.tryParse(item['chaksun1']?.toString()   ?? '0') ?? 0;
        final prize2nd        = int.tryParse(item['chaksun2']?.toString()   ?? '0') ?? 0;
        final prize3rd        = int.tryParse(item['chaksun3']?.toString()   ?? '0') ?? 0;
        final prize4th        = int.tryParse(item['chaksun4']?.toString()   ?? '0') ?? 0;
        final prize5th        = int.tryParse(item['chaksun5']?.toString()   ?? '0') ?? 0;
        final prizeTotalCareer= int.tryParse(item['chaksunT']?.toString()   ?? '0') ?? 0;
        final prizeTotal1Year = int.tryParse(item['chaksunY']?.toString()   ?? '0') ?? 0;
        final prizeTotal6Month= int.tryParse(item['chaksun_6m']?.toString() ?? '0') ?? 0;

        // ── 스탯 계산 ─────────────────────────────────────────
        // rating 기반에 rcWins·rcWins1Y·상금 지수를 보정 인자로 활용
        final prizeComp    = (prizeTotal1Year / 100000000.0).clamp(0.0, 1.0); // 1억 기준 정규화
        final winBonus     = (rcWins * 10.0) + (rcWins1Y * 5.0);   // 통산+최근 승률 가산
        final prizebonus   = prizeComp * 5.0;                        // 상금 경쟁력 가산 (max +5)

        final speedStat    = (rating * 0.8 + 20 + winBonus * 0.4).clamp(0.0, 100.0);
        final staminaStat  = (rating * 0.7 + 25 + (weightChange < 0 ? 5 : 0) + prizebonus * 0.3).clamp(0.0, 100.0);
        final formStat     = (rating * 0.6 + 30 + rcWins1Y * 8.0).clamp(0.0, 100.0);
        final trackFitStat = (rating * 0.5 + 35 + winBonus * 0.2).clamp(0.0, 100.0);
        final baseScore    = (speedStat * 0.35 + staminaStat * 0.25 +
            formStat * 0.20 + trackFitStat * 0.10 +
            rating   * 0.07 + prizebonus   * 0.03).clamp(0.0, 100.0);

        // ── g1fRating: 최근 6개월 상금 기반 추정 ─────────────
        // 실제 G1F 데이터가 없을 때 상금 기반으로 근사 추정
        final g1fRating = (prizeTotal6Month / 50000000.0).clamp(0.0, 1.0); // 5천만 기준

        return HorseEntry(
          gateNo:           gateNo,
          horseName:        horseName,
          jockeyName:       jockeyName,
          trainerName:      trainerName,
          weight:           weight,
          weightChange:     weightChange,
          rating:           rating,
          speedStat:        speedStat,
          staminaStat:      staminaStat,
          formStat:         formStat,
          trackFitStat:     trackFitStat,
          baseScore:        baseScore,
          recentRecord:     recentRecord,
          odds:             odds,
          // API 원시 파라미터
          horseRegNo:       horseRegNo,
          rcWins:           rcWins,
          jockeyRcWins:     0.0,   // API26_2에 기수 개인 승률 없음 → 별도 API 또는 0.0
          wgBudam:          wgBudam,
          g1fRating:        g1fRating,
          // 상금 필드
          prizeWin:         prizeWin,
          prize2nd:         prize2nd,
          prize3rd:         prize3rd,
          prize4th:         prize4th,
          prize5th:         prize5th,
          prizeTotalCareer: prizeTotalCareer,
          prizeTotal1Year:  prizeTotal1Year,
          prizeTotal6Month: prizeTotal6Month,
        );
      } catch (_) {
        return null;
      }
    }).whereType<HorseEntry>().toList();
  }

  // ── racedetailresult: 경주별상세성적표 (결과 + 전체 상세정보) ──────────
  // URL: http://apis.data.go.kr/B551015/racedetailresult/getracedetailresult
  // 응답형식: XML (JSON 미지원 — _type=json 파라미터 제거)
  // 필드: stOrd, chulNo, hrNo, hrName, jkName, jkNo, jkSymbol, jkMeet,
  //        trNo, trName, trMeet, owNo, owName, owCloth, wgBudam, wgHr, df,
  //        prdCtyNm, sex, age, hrRating, hrTool, rcTime, differ, win, plc,
  //        chulYn, meet
  // ─────────────────────────────────────────────────────────────────────
  static Future<KraRaceResult?> fetchRaceResult(
      String venueCode, DateTime date, String raceNo) async {
    final dateStr = _formatDate(date);
    final meetCode = _venueToMeet(venueCode);

    try {
      // racedetailresult — XML 응답 (numOfRows=16: 최대 출전마 수 대비 여유)
      final uri = Uri.parse(
        'http://apis.data.go.kr/B551015/racedetailresult/getracedetailresult'
        '?serviceKey=$_serviceKey'
        '&numOfRows=16&pageNo=1&meet=$meetCode&rc_date=$dateStr&rc_no=$raceNo',
      );
      if (kDebugMode) debugPrint('[KRA racedetailresult] $uri');

      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      _KraInterceptor.check(resp);

      if (resp.statusCode == 200 &&
          !resp.body.contains('Unexpected errors')) {
        // XML 파싱 — JSON 미지원이므로 정규식 기반 추출
        final items = _extractXmlItems(resp.body);
        if (items != null && items.isNotEmpty) {
          final result = _parseDetailResult(items, venueCode, date, raceNo);
          if (result.horses.isNotEmpty) return result;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[KRA racedetailresult] Error: $e → API4_3 시도');
    }

    // Fallback: 기존 API4_3 (JSON 지원) — racedetailresult 실패 시
    try {
      final fallbackUri = Uri.parse(
        '$_baseUrl/API4_3?serviceKey=$_serviceKey'
        '&numOfRows=20&pageNo=1&meet=$meetCode&rc_date=$dateStr&rc_no=$raceNo&_type=json',
      );
      if (kDebugMode) debugPrint('[KRA API4_3 fallback] $fallbackUri');

      final resp = await http.get(fallbackUri).timeout(const Duration(seconds: 8));
      _KraInterceptor.check(resp);
      if (resp.statusCode == 200 && !resp.body.contains('Unexpected errors')) {
        final data = jsonDecode(resp.body);
        final items = _extractItems(data);
        if (items != null && items.isNotEmpty) {
          return _parseFallbackResult(items, venueCode, date, raceNo);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[KRA API4_3] Error: $e');
    }

    return null;
  }

  // ── racedetailresult XML 파싱 ─────────────────────────────────────────
  // XML 구조: <response><body><items><item>...</item></items></body></response>
  // 정규식 기반으로 <item>...</item> 블록 추출 → 각 필드 파싱
  static List<Map<String, String>>? _extractXmlItems(String xml) {
    try {
      // resultCode 확인
      final codeMatch = RegExp(r'<resultCode>(\d+)<\/resultCode>').firstMatch(xml);
      final code = codeMatch?.group(1) ?? '';
      if (code.isNotEmpty && code != '00') {
        if (kDebugMode) debugPrint('[XmlParse] resultCode=$code: ${KraApiErrorCode.toMessage(code)}');
        return null;
      }

      // <item>...</item> 블록 추출 (DOTALL 모드)
      final itemMatches = RegExp(
        r'<item>([\s\S]*?)<\/item>',
        multiLine: true,
      ).allMatches(xml);

      if (itemMatches.isEmpty) return null;

      return itemMatches.map((m) {
        final block = m.group(1) ?? '';
        final map = <String, String>{};
        // 각 <tag>value</tag> 파싱
        final tagMatches = RegExp(r'<(\w+)>([\s\S]*?)<\/\1>').allMatches(block);
        for (final t in tagMatches) {
          map[t.group(1)!] = t.group(2)!.trim();
        }
        return map;
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[XmlParse] Error: $e');
      return null;
    }
  }

  // ── racedetailresult 전체 필드 파싱 ──────────────────────────────────
  static KraRaceResult _parseDetailResult(
      List<Map<String, String>> items,
      String venueCode, DateTime date, String raceNo) {
    final results = <HorseResult>[];

    for (final item in items) {
      try {
        // ── 착순 / 출전 여부 ──────────────────────────────────
        // stOrd: 착순 (1~n), chulYn: 출전여부 (1=출전, 0=미출전)
        final stOrd   = int.tryParse(item['stOrd']  ?? '0') ?? 0;
        final chulYn  = (item['chulYn'] ?? '1') == '1';
        final chulNo  = int.tryParse(item['chulNo'] ?? '1') ?? 1;

        // ── 마필 기본정보 ────────────────────────────────────
        final hrNo      = item['hrNo']      ?? '';
        final hrName    = item['hrName']    ?? '미정';
        final venueName = item['meet']      ?? '';
        final prdCtyNm  = item['prdCtyNm'] ?? '';
        final sex       = item['sex']       ?? '';
        final age       = item['age']       ?? '';

        // ── 체중 정보 ─────────────────────────────────────
        final wgHr    = int.tryParse(item['wgHr']    ?? '0') ?? 0;
        final df      = int.tryParse(item['df']      ?? '0') ?? 0;
        final wgBudam = double.tryParse(item['wgBudam'] ?? '55') ?? 55.0;

        // ── 장구 / 레이팅 ────────────────────────────────────
        final hrTool   = item['hrTool']   ?? '';
        final hrRating = item['hrRating'] ?? '';

        // ── 기수 정보 ─────────────────────────────────────
        final jkName       = item['jkName']   ?? '미정';
        final jkNo         = item['jkNo']     ?? '';
        final jkMeet       = item['jkMeet']   ?? '';
        // jkSymbol: 수습기수감량 (예: "-1", "-2", "-3" 또는 null/빈값)
        final jkSymbol     = item['jkSymbol'] ?? '';

        // ── 조교사 정보 ────────────────────────────────────
        final trName   = item['trName'] ?? '';
        final trNo     = item['trNo']   ?? '';
        final trMeet   = item['trMeet'] ?? '';

        // ── 마주 정보 ─────────────────────────────────────
        final owName   = item['owName']  ?? '';
        final owNo     = item['owNo']    ?? '';
        final owCloth  = item['owCloth'] ?? '';

        // ── 성적 / 기록 ────────────────────────────────────
        final rcTime = item['rcTime'] ?? '';
        // differ: 도착차 (1착은 공백, 이후 "1/2마신", "코", "동착" 등)
        // 9999.9 또는 빈값 처리
        final differRaw = item['differ'] ?? '';
        final differ    = (differRaw == '9999.9' || differRaw.isEmpty) ? '' : differRaw;

        // ── 배당 정보 ─────────────────────────────────────
        // 9999.9 = 비대상(미발매) → 0.0으로 변환
        double parseOdds(String? s) {
          final v = double.tryParse(s ?? '0') ?? 0.0;
          return v >= 9999.0 ? 0.0 : v;
        }
        final winOdds   = parseOdds(item['win']);
        final placeOdds = parseOdds(item['plc']);

        results.add(HorseResult(
          rank:              stOrd,
          gateNo:            chulNo,
          horseNo:           hrNo,
          horseName:         hrName,
          venueName:         venueName,
          origin:            prdCtyNm,
          sex:               sex,
          age:               age,
          weight:            wgHr,
          weightDiff:        df,
          wgBudam:           wgBudam,
          horseTool:         hrTool,
          horseRating:       hrRating,
          jockeyName:        jkName,
          jockeyNo:          jkNo,
          jockeyMeet:        jkMeet,
          jockeyApprentice:  jkSymbol,
          trainerName:       trName,
          trainerNo:         trNo,
          trainerMeet:       trMeet,
          ownerName:         owName,
          ownerNo:           owNo,
          ownerCloth:        owCloth,
          raceTime:          rcTime,
          differ:            differ,
          didStart:          chulYn,
          winOdds:           winOdds,
          placeOdds:         placeOdds,
        ));
      } catch (_) {}
    }

    // 착순 정렬: 출전마 → 미출전마 순서
    // 출전마 중 stOrd 오름차순, 미출전마는 마번 오름차순
    results.sort((a, b) {
      if (a.didStart && !b.didStart) return -1;
      if (!a.didStart && b.didStart) return 1;
      if (a.didStart && b.didStart) return a.rank.compareTo(b.rank);
      return a.gateNo.compareTo(b.gateNo);
    });

    return KraRaceResult(
      raceNo:    raceNo,
      raceDate:  _formatDate(date),
      venueCode: venueCode,
      venueName: _meetToVenueName(_venueToMeet(venueCode)),
      horses:    results,
    );
  }

  // ── API4_3 Fallback 파싱 (racedetailresult 실패 시) ─────────────────
  static KraRaceResult _parseFallbackResult(
      List<dynamic> items, String venueCode, DateTime date, String raceNo) {
    final results = <HorseResult>[];

    for (final item in items) {
      try {
        final ord    = int.tryParse(item['ord']?.toString()      ?? '0') ?? 0;
        final chulNo = int.tryParse(item['chulNo']?.toString()   ?? '1') ?? 1;
        final hrName = item['hrName']?.toString() ?? '미정';
        final jkName = item['jkName']?.toString() ?? '미정';
        final rcTime = item['rcTime']?.toString()  ?? '';
        final weight = int.tryParse(item['hrWeight']?.toString() ?? '0') ?? 0;

        double parseOdds(String? s) {
          final v = double.tryParse(s ?? '0') ?? 0.0;
          return v >= 9999.0 ? 0.0 : v;
        }
        final winOdds = parseOdds(item['winOdds']?.toString());
        final plcOdds = parseOdds(item['plcOdds1']?.toString());

        results.add(HorseResult(
          rank:      ord,
          gateNo:    chulNo,
          horseName: hrName,
          jockeyName:jkName,
          raceTime:  rcTime,
          weight:    weight,
          winOdds:   winOdds,
          placeOdds: plcOdds,
        ));
      } catch (_) {}
    }

    results.sort((a, b) => a.rank.compareTo(b.rank));
    return KraRaceResult(
      raceNo:    raceNo,
      raceDate:  _formatDate(date),
      venueCode: venueCode,
      venueName: _meetToVenueName(_venueToMeet(venueCode)),
      horses:    results,
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
        _KraInterceptor.check(resp); // ★ HTTP 500 인터셉터
        bool hasData = false;
        if (resp.statusCode == 200 &&
            !resp.body.contains('Unexpected errors')) {
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
