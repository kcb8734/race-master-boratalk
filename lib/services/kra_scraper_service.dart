import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/race_models.dart';
import 'race_schedule_cache.dart';
import 'kra_mock_service.dart';

// ══════════════════════════════════════════════════════════════════════════
//  KraScraperService — KRA API 500 장애 Failover 레이어
//
//  ▸ 단계별 Failover 전략 (API 장애 감지 즉시 트리거):
//
//    TIER-1: KRA 공공데이터 API (JSON 모드)          ← 정상 경로
//       ↓ HTTP 500 / Timeout(8초)
//    TIER-2: KRA 공공데이터 API 파라미터 변형 시도
//       - URL 인코딩된 ServiceKey로 재시도
//       - numOfRows 축소(5) + pageNo 초기화
//       - meet 코드 문자열 변환 확인
//       ↓ 여전히 실패
//    TIER-3: KRA 공공데이터 XML 포맷 폴백
//       - _type=json 제거 → 기본 XML 응답 파싱
//       ↓ 여전히 실패
//    TIER-4: 로컬 캐시 타임스탬프 복원
//       - SharedPreferences에 저장된 마지막 성공 스냅샷 적용
//       ↓ 캐시 없음
//    TIER-5: KraMockService 고정 시간표 (최후 수단)
//       - 실제 KRA 공식 시간표로 보정된 Mock 데이터
//
//  ▸ 웹 크롤링 불가 이유:
//    - Flutter Web 환경: CORS 정책으로 외부 HTML 직접 파싱 불가
//    - race.kra.co.kr: IP 화이트리스트 기반 외부 접근 차단
//    - 공공데이터포털 외 별도 경로 없음 (2025-05 기준)
//    → 공공데이터포털 대체 파라미터 시도로 Failover 레이어 구성
//
//  ▸ 에러 투명성:
//    모든 단계별 결과를 RaceScheduleCache.logApiError()에 적재
// ══════════════════════════════════════════════════════════════════════════
class KraScraperService {
  // ── KRA 공공데이터포털 상수 ────────────────────────────────────────────
  static const String _rawKey =
      'ef117e7bebbcea7586234f85acd8292dba6a6d95230131aec62a10b5b2610885';
  static const String _baseUrl = 'https://apis.data.go.kr/B551015';

  // ── 타임아웃 ──────────────────────────────────────────────────────────
  static const Duration _tier2Timeout = Duration(seconds: 5);
  static const Duration _tier3Timeout = Duration(seconds: 5);

  // ─────────────────────────────────────────────────────────────────────────
  //  메인 Failover 엔트리포인트
  //
  //  API 장애(HTTP 500 / Timeout) 감지 후 이 메서드를 호출한다.
  //  반환값: [races, source] — source: 'tier2'|'tier3'|'cache'|'mock'
  // ─────────────────────────────────────────────────────────────────────────
  static Future<FailoverResult> failover({
    required String venueCode,
    required DateTime date,
    required String originalError,
  }) async {
    final dateStr  = _formatDate(date);
    final meetCode = _venueToMeet(venueCode);
    final cache    = RaceScheduleCache();

    // ── ServiceKey 사전 검증 + 로그 ─────────────────────────────────────
    final keyValidation = RaceScheduleCache.validateServiceKey(_rawKey);
    if (kDebugMode) {
      debugPrint('[Failover] ServiceKey 검증: ${keyValidation.summary}');
      debugPrint('[Failover] 인코딩 필요: ${keyValidation.needsEncoding}');
    }

    // ── TIER-2: URL-Encoded Key 재시도 ──────────────────────────────────
    if (kDebugMode) {
      debugPrint('[Failover] TIER-2 시작: URL-Encoded Key 재시도 $meetCode/$dateStr');
    }
    final tier2Result = await _tryTier2(
      meetCode: meetCode,
      dateStr: dateStr,
      venueCode: venueCode,
      date: date,
    );
    if (tier2Result != null) {
      // 성공 → 캐시 저장
      await cache.saveSnapshot(
        races: tier2Result,
        venueCode: venueCode,
        date: date,
        source: 'tier2',
      );
      if (kDebugMode) {
        debugPrint('[Failover] ✅ TIER-2 성공: ${tier2Result.length}경주');
      }
      return FailoverResult(races: tier2Result, source: 'tier2',
          tier: 2, description: 'URL-Encoded Key 재시도 성공');
    }

    // ── TIER-3: XML 포맷 폴백 ────────────────────────────────────────────
    if (kDebugMode) {
      debugPrint('[Failover] TIER-3 시작: XML 포맷 폴백 $meetCode/$dateStr');
    }
    final tier3Result = await _tryTier3(
      meetCode: meetCode,
      dateStr: dateStr,
      venueCode: venueCode,
      date: date,
    );
    if (tier3Result != null) {
      await cache.saveSnapshot(
        races: tier3Result,
        venueCode: venueCode,
        date: date,
        source: 'tier3',
      );
      if (kDebugMode) {
        debugPrint('[Failover] ✅ TIER-3 성공: ${tier3Result.length}경주');
      }
      return FailoverResult(races: tier3Result, source: 'tier3',
          tier: 3, description: 'XML 포맷 폴백 성공');
    }

    // ── TIER-4: 로컬 캐시 복원 ───────────────────────────────────────────
    if (kDebugMode) {
      debugPrint('[Failover] TIER-4: 로컬 캐시 타임스탬프 복원 시도');
    }
    final mockBase = KraMockService.getRaces(venueCode, date);
    final cachedRaces = await cache.applyCachedTimestamps(
      mockRaces: mockBase,
      venueCode: venueCode,
      date: date,
    );

    final cacheInfo = await cache.getCacheInfo(
      venueCode: venueCode,
      date: date,
    );

    if (cacheInfo.hasCache) {
      if (kDebugMode) {
        debugPrint(
          '[Failover] ✅ TIER-4 성공: 캐시 복원 '
          '(저장: ${cacheInfo.savedAtLabel}, 출처: ${cacheInfo.sourceLabel})',
        );
      }
      return FailoverResult(
        races: cachedRaces,
        source: 'cache',
        tier: 4,
        description: '로컬 캐시 복원 (${cacheInfo.savedAtLabel} 저장, 출처: ${cacheInfo.sourceLabel})',
        cacheInfo: cacheInfo,
      );
    }

    // ── TIER-5: Mock 최후 수단 ───────────────────────────────────────────
    if (kDebugMode) {
      debugPrint('[Failover] TIER-5: Mock 최후 수단 (KRA 공식 시간표 반영본)');
    }
    return FailoverResult(
      races: mockBase,
      source: 'mock',
      tier: 5,
      description: 'KRA 공식 시간표 기반 Mock 데이터',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  TIER-2: URL-Encoded Key + 파라미터 변형 재시도
  //
  //  공공데이터포털 API Gateway가 파라미터 규격을 변경했을 가능성 점검:
  //  ① encodedKey 사용 (rawKey와 동일하지만 명시적 처리)
  //  ② numOfRows 축소 (5) — 부하 경감으로 응답 가능성
  //  ③ JSON 타입 명시 (_type=json)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<List<RaceInfo>?> _tryTier2({
    required String meetCode,
    required String dateStr,
    required String venueCode,
    required DateTime date,
  }) async {
    final cache = RaceScheduleCache();

    // 시도할 파라미터 변형 목록
    final variants = [
      // 변형 1: URL-encoded key + 최소 파라미터
      '$_baseUrl/API187?serviceKey=${Uri.encodeComponent(_rawKey)}'
          '&numOfRows=5&pageNo=1&meet=$meetCode'
          '&rc_date=$dateStr&_type=json',
      // 변형 2: rawKey + numOfRows=30 (더 많이 요청)
      '$_baseUrl/API187?serviceKey=$_rawKey'
          '&numOfRows=30&pageNo=1&meet=$meetCode'
          '&rc_date=$dateStr&_type=json',
      // 변형 3: 대소문자 혼용 파라미터 (Gateway 레거시 호환)
      '$_baseUrl/API187?ServiceKey=$_rawKey'
          '&numOfRows=20&pageNo=1&meet=$meetCode'
          '&rc_date=$dateStr&_type=json',
    ];

    for (int i = 0; i < variants.length; i++) {
      final url = variants[i];
      try {
        if (kDebugMode) {
          debugPrint('[Failover/T2] 변형 #${i+1} 시도...');
        }
        final resp = await http.get(Uri.parse(url))
            .timeout(_tier2Timeout);

        await cache.logApiError(
          apiName: 'API187-T2-v${i+1}',
          statusCode: resp.statusCode,
          errorBody: resp.body.length > 200
              ? resp.body.substring(0, 200) : resp.body,
          requestUrl: url,
          serviceKeyMasked: RaceScheduleCache.validateServiceKey(_rawKey).maskedKey,
          encodingNote: i == 0 ? 'URL-encoded key 사용' : 'rawKey 변형 ${i+1}',
        );

        if (resp.statusCode != 200) continue;
        if (resp.body.contains('Unexpected errors')) continue;

        final data = jsonDecode(resp.body);
        final items = _extractJsonItems(data);
        if (items == null || items.isEmpty) continue;

        final races = _parseRacesMinimal(items, venueCode, date);
        if (races.isNotEmpty) return races;

      } catch (e) {
        await cache.logApiError(
          apiName: 'API187-T2-v${i+1}',
          statusCode: 0,
          errorBody: e.toString(),
          requestUrl: url,
          encodingNote: 'Timeout/Exception',
        );
        if (kDebugMode) {
          debugPrint('[Failover/T2] 변형 #${i+1} 실패: $e');
        }
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  TIER-3: XML 포맷 폴백 파싱
  //
  //  공공데이터포털 API는 기본값 XML 응답 → 정규식으로 파싱
  //  _type=json 파라미터 없이 호출
  // ─────────────────────────────────────────────────────────────────────────
  static Future<List<RaceInfo>?> _tryTier3({
    required String meetCode,
    required String dateStr,
    required String venueCode,
    required DateTime date,
  }) async {
    final cache = RaceScheduleCache();
    // XML 포맷 (기본)
    final url = '$_baseUrl/API187?serviceKey=$_rawKey'
        '&numOfRows=20&pageNo=1&meet=$meetCode&rc_date=$dateStr';

    try {
      final resp = await http.get(Uri.parse(url))
          .timeout(_tier3Timeout);

      await cache.logApiError(
        apiName: 'API187-T3-XML',
        statusCode: resp.statusCode,
        errorBody: resp.body.length > 300
            ? resp.body.substring(0, 300) : resp.body,
        requestUrl: url,
        encodingNote: 'XML fallback (no _type=json)',
      );

      if (resp.statusCode != 200) return null;
      if (resp.body.contains('Unexpected errors')) return null;

      // XML에서 경주 시간표 정규식 파싱
      final races = _parseXmlRaces(resp.body, venueCode, date);
      if (races.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('[Failover/T3] XML 파싱 성공: ${races.length}경주');
        }
        return races;
      }
    } catch (e) {
      await cache.logApiError(
        apiName: 'API187-T3-XML',
        statusCode: 0,
        errorBody: e.toString(),
        requestUrl: url,
        encodingNote: 'Timeout/Exception',
      );
      if (kDebugMode) {
        debugPrint('[Failover/T3] XML 시도 실패: $e');
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  XML 경주 데이터 파싱 (정규식 기반)
  //
  //  KRA API187 XML 응답 구조:
  //  <item>
  //    <rcNo>1</rcNo>
  //    <postTime>1035</postTime>  ← HHMM
  //    <rcDist>1200</rcDist>
  //    <rcGrdCourse>일반/국6등급</rcGrdCourse>
  //    <rcGrdNm>국6등급</rcGrdNm>
  //    <chulNum>10</chulNum>
  //    <rcName>제1경주</rcName>
  //    <trackCond>양호</trackCond>
  //  </item>
  // ─────────────────────────────────────────────────────────────────────────
  static List<RaceInfo> _parseXmlRaces(
      String xml, String venueCode, DateTime date) {
    final result = <RaceInfo>[];
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final isPast = date.isBefore(DateTime(now.year, now.month, now.day));

    // <item> 블록 추출
    final itemRegex = RegExp(r'<item>(.*?)</item>', dotAll: true);
    final matches = itemRegex.allMatches(xml);

    for (final match in matches) {
      try {
        final block = match.group(1) ?? '';

        String _tag(String name) {
          final m = RegExp('<$name>([^<]*)</$name>').firstMatch(block);
          return m?.group(1)?.trim() ?? '';
        }

        final raceNo  = _tag('rcNo');
        final rawTime = _tag('postTime').isNotEmpty
            ? _tag('postTime') : _tag('rcPostTime');
        final startTime = rawTime.isNotEmpty
            ? _formatTime(rawTime) : '';
        if (raceNo.isEmpty || startTime.isEmpty) continue;

        final distance    = int.tryParse(_tag('rcDist')) ?? 1400;
        final condition   = _tag('rcGrdCourse');
        final grade       = _tag('rcGrdNm');
        final totalHorses = int.tryParse(_tag('chulNum')) ?? 10;
        final rcName      = _tag('rcName');
        final trackCond   = _tag('trackCond');

        final venueName = venueCode == '1' ? '서울'
            : venueCode == '2' ? '부산경남' : '제주';

        final isSpecialRace = rcName.isNotEmpty &&
            !rcName.contains('일반') &&
            !RegExp(r'^제\d+경주$').hasMatch(rcName);

        bool isFinished = false;
        bool isUpcoming = false;
        if (isToday && startTime.isNotEmpty) {
          final parts = startTime.split(':');
          if (parts.length == 2) {
            final raceTime = DateTime(
              now.year, now.month, now.day,
              int.parse(parts[0]), int.parse(parts[1]),
            );
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
          raceDate:        _formatDate(date),
          totalHorses:     totalHorses,
          trackCondition:  trackCond.isNotEmpty ? trackCond : '양호',
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

  // ─────────────────────────────────────────────────────────────────────────
  //  JSON items에서 최소 RaceInfo 파싱 (TIER-2 전용)
  // ─────────────────────────────────────────────────────────────────────────
  static List<RaceInfo> _parseRacesMinimal(
      List<dynamic> items, String venueCode, DateTime date) {
    final result = <RaceInfo>[];
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final isPast = date.isBefore(DateTime(now.year, now.month, now.day));
    final venueName = venueCode == '1' ? '서울'
        : venueCode == '2' ? '부산경남' : '제주';

    for (final item in items) {
      try {
        final raceNo = item['rcNo']?.toString() ?? '';
        final rawTime = item['postTime']?.toString()
            ?? item['rcPostTime']?.toString()
            ?? '';
        final startTime = rawTime.isNotEmpty ? _formatTime(rawTime) : '';
        if (raceNo.isEmpty || startTime.isEmpty) continue;

        final distance    = int.tryParse(item['rcDist']?.toString() ?? '') ?? 1400;
        final condition   = item['rcGrdCourse']?.toString() ?? '';
        final grade       = item['rcGrdNm']?.toString() ?? '';
        final totalHorses = int.tryParse(item['chulNum']?.toString() ?? '') ?? 10;
        final rcName      = item['rcName']?.toString().trim() ?? '';
        final trackCond   = item['trackCond']?.toString() ?? '양호';

        final isSpecialRace = rcName.isNotEmpty &&
            !rcName.contains('일반') &&
            !RegExp(r'^제\d+경주$').hasMatch(rcName);

        bool isFinished = false;
        bool isUpcoming = false;
        if (isToday) {
          final parts = startTime.split(':');
          if (parts.length == 2) {
            final raceTime = DateTime(
              now.year, now.month, now.day,
              int.parse(parts[0]), int.parse(parts[1]),
            );
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
          raceDate:        _formatDate(date),
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

  // ─────────────────────────────────────────────────────────────────────────
  //  유틸
  // ─────────────────────────────────────────────────────────────────────────
  static String _venueToMeet(String venueCode) {
    switch (venueCode) {
      case '1': return '1';  // 서울
      case '2': return '3';  // 부산경남 (KRA meet=3)
      case '3': return '2';  // 제주 (KRA meet=2)
      default:  return '1';
    }
  }

  static String _formatDate(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';

  static String _formatTime(String raw) {
    final s = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (s.length < 3) return '';
    final h = s.substring(0, s.length - 2);
    final m = s.substring(s.length - 2);
    return '${h.padLeft(2, '0')}:$m';
  }

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

// ══════════════════════════════════════════════════════════════════════════
//  FailoverResult — Failover 실행 결과
// ══════════════════════════════════════════════════════════════════════════
class FailoverResult {
  /// 최종 경주 목록
  final List<RaceInfo> races;

  /// 데이터 출처 식별자
  /// 'tier2' = URL-Encoded Key 재시도 성공
  /// 'tier3' = XML 폴백 성공
  /// 'cache' = 로컬 캐시 복원
  /// 'mock'  = Mock 최후 수단
  final String source;

  /// Failover 단계 (2~5)
  final int tier;

  /// 설명 메시지
  final String description;

  /// 캐시 메타 정보 (TIER-4일 때만 non-null)
  final CacheMetaInfo? cacheInfo;

  const FailoverResult({
    required this.races,
    required this.source,
    required this.tier,
    required this.description,
    this.cacheInfo,
  });

  bool get isFromApi    => tier <= 3;
  bool get isFromCache  => source == 'cache';
  bool get isFromMock   => source == 'mock';

  String get tierLabel {
    switch (tier) {
      case 2: return '[TIER-2] 파라미터 변형 재시도';
      case 3: return '[TIER-3] XML 폴백';
      case 4: return '[TIER-4] 캐시 복원';
      case 5: return '[TIER-5] Mock 최후 수단';
      default: return '[TIER-?]';
    }
  }
}
