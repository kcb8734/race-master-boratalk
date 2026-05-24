import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'race_schedule_cache.dart';

// ══════════════════════════════════════════════════════════════════════════
//  KraServerStatus — KRA 공공데이터 API 서버 장애 감지 & 자동 복구 시스템
//
//  ▸ isDown: true  → HTTP 500 / "Unexpected errors" 감지 → 장애 배너 노출
//  ▸ isDown: false → HTTP 200 + 정상 JSON 응답 확인     → 배너 해제
//  ▸ 10분 주기 헬스체크 (서버 회복 자동 감지)
//  ▸ ChangeNotifier → Consumer<KraServerStatus>로 UI 반응
//
//  ▸ [v2] 타임스탬프 캐시 동기화 연동:
//    - initialCheck() → purgeExpiredCache() 호출 (만료 캐시 선제 정리)
//    - reportServerOk() → _cacheRefreshNeeded = true (복구 후 다음 API
//      호출 시 fetchRaces()에서 캐시 갱신 자동 처리)
//    - _runHealthCheck() 결과 → logApiError()로 헬스체크 에러도 투명 적재
// ══════════════════════════════════════════════════════════════════════════
class KraServerStatus extends ChangeNotifier {
  // ── 싱글톤 ──────────────────────────────────────────────────
  static final KraServerStatus _instance = KraServerStatus._internal();
  factory KraServerStatus() => _instance;
  KraServerStatus._internal();

  // ── 상태 변수 ────────────────────────────────────────────────
  bool _isDown = false;           // 서버 장애 여부
  bool _isChecking = false;       // 헬스체크 진행 중 여부
  DateTime? _detectedAt;          // 장애 최초 감지 시각
  DateTime? _recoveredAt;         // 복구 확인 시각
  String _lastErrorMsg = '';      // 마지막 오류 메시지 원문
  int _checkCount = 0;            // 헬스체크 총 횟수

  // ── [v2] 캐시 갱신 플래그 ────────────────────────────────────
  // reportServerOk() 호출 시 true → fetchRaces()에서 캐시 갱신 신호로 사용
  bool _cacheRefreshNeeded = false;

  Timer? _healthTimer;

  // ── Public Getters ───────────────────────────────────────────
  bool get isDown       => _isDown;
  bool get isChecking   => _isChecking;
  bool get isUp         => !_isDown;
  DateTime? get detectedAt   => _detectedAt;
  DateTime? get recoveredAt  => _recoveredAt;
  String get lastErrorMsg    => _lastErrorMsg;
  int get checkCount         => _checkCount;

  /// [v2] 서버 복구 후 캐시 갱신이 필요한지 여부
  /// fetchRaces()에서 이 플래그를 확인하고, true이면 API 재호출 후 캐시 저장
  bool get cacheRefreshNeeded => _cacheRefreshNeeded;

  // ── 캐시 갱신 플래그 리셋 (fetchRaces() 갱신 완료 후 호출) ──
  void clearCacheRefreshFlag() {
    _cacheRefreshNeeded = false;
  }

  // ── 장애 감지 시각 문자열 (KST HH:mm 기준) ──────────────────
  String get detectedAtLabel {
    if (_detectedAt == null) return '';
    final t = _detectedAt!.toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  // ── 경과 시간 문자열 ─────────────────────────────────────────
  String get elapsedLabel {
    if (_detectedAt == null) return '';
    final diff = DateTime.now().difference(_detectedAt!);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    return '${diff.inHours}시간 ${diff.inMinutes % 60}분 전';
  }

  // ── KRA API 상수 ─────────────────────────────────────────────
  static const String _serviceKey =
      'ef117e7bebbcea7586234f85acd8292dba6a6d95230131aec62a10b5b2610885';
  static const String _baseUrl = 'https://apis.data.go.kr/B551015';

  // ── 헬스체크 주기 (10분) ─────────────────────────────────────
  static const Duration _healthInterval = Duration(minutes: 10);

  // ══════════════════════════════════════════════════════════════
  //  외부 호출: API 호출 결과로 인터셉트
  //  kra_api_service.dart에서 응답 수신 시 즉시 호출
  // ══════════════════════════════════════════════════════════════

  /// HTTP 500 또는 "Unexpected errors" 응답 수신 시 호출
  void reportServerError({String errorMsg = 'HTTP 500 Unexpected errors'}) {
    _lastErrorMsg = errorMsg;
    if (!_isDown) {
      _isDown = true;
      _detectedAt = DateTime.now();
      _recoveredAt = null;
      _cacheRefreshNeeded = false; // 장애 시 갱신 플래그 초기화
      if (kDebugMode) {
        debugPrint('[KraServerStatus] 🔴 서버 장애 감지: $errorMsg');
      }
      // 즉시 헬스체크 타이머 시작 (10분 주기)
      _startHealthCheck();
      notifyListeners();
    }
  }

  /// HTTP 200 + 정상 JSON 응답 수신 시 호출
  /// [v2] 복구 감지 시 → _cacheRefreshNeeded = true 설정
  ///   → fetchRaces() 다음 호출에서 API 재조회 + 캐시 갱신 자동 처리
  void reportServerOk() {
    if (_isDown) {
      _isDown = false;
      _recoveredAt = DateTime.now();
      _cacheRefreshNeeded = true; // [v2] 복구 후 캐시 갱신 신호
      if (kDebugMode) {
        debugPrint('[KraServerStatus] ✅ 서버 복구 확인: $_recoveredAt');
        debugPrint('[KraServerStatus] 📌 캐시 갱신 플래그 설정 (다음 fetchRaces() 호출 시 적용)');
      }
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  헬스체크 타이머 관리
  // ══════════════════════════════════════════════════════════════

  void _startHealthCheck() {
    _healthTimer?.cancel();
    // 즉시 1회 + 이후 10분 주기
    _runHealthCheck();
    _healthTimer = Timer.periodic(_healthInterval, (_) => _runHealthCheck());
    if (kDebugMode) {
      debugPrint('[KraServerStatus] ⏱️ 헬스체크 시작 (10분 주기)');
    }
  }

  Future<void> _runHealthCheck() async {
    if (_isChecking) return; // 중복 실행 방지
    _isChecking = true;
    _checkCount++;
    notifyListeners();

    if (kDebugMode) {
      debugPrint('[KraServerStatus] 🔍 헬스체크 #$_checkCount 실행 중...');
    }

    final cache = RaceScheduleCache();

    try {
      final today = _todayStr();
      final reqUrl = '$_baseUrl/API187?serviceKey=$_serviceKey'
          '&numOfRows=1&pageNo=1&meet=1&rc_date=$today&_type=json';
      final uri = Uri.parse(reqUrl);

      final resp = await http.get(uri).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final body = resp.body;

        // "Unexpected errors" 텍스트 포함 시 → 여전히 장애
        if (body.contains('Unexpected errors') ||
            body.contains('unexpected errors')) {
          if (kDebugMode) {
            debugPrint('[KraServerStatus] 🔴 #$_checkCount: 여전히 장애 (200 but Unexpected errors)');
          }
          // [v2] 헬스체크 장애 결과 → 에러 로그 적재
          await cache.logApiError(
            apiName: 'HealthCheck-#$_checkCount',
            statusCode: 200,
            errorBody: 'Unexpected errors in response body',
            requestUrl: reqUrl,
            serviceKeyMasked: RaceScheduleCache.validateServiceKey(_serviceKey).maskedKey,
            encodingNote: '헬스체크: 200 but Unexpected errors',
          );
          // 상태 유지 (이미 isDown=true)
        } else {
          // 정상 JSON 응답 확인 → 복구 판단
          try {
            final data = jsonDecode(body);
            final resultCode = data['response']?['header']?['resultCode'];
            // resultCode 00 = 정상, 30 = 인증오류 (서버는 살아있음)
            if (resultCode != null) {
              if (kDebugMode) {
                debugPrint('[KraServerStatus] ✅ #$_checkCount: 서버 복구 (resultCode=$resultCode)');
              }
              reportServerOk();
              // 복구 시 타이머 정지
              _stopHealthCheck();
            }
          } catch (_) {
            // JSON 파싱 실패 → 여전히 장애로 유지
            // [v2] 파싱 실패도 로그 적재
            await cache.logApiError(
              apiName: 'HealthCheck-#$_checkCount',
              statusCode: 200,
              errorBody: 'JSON parse failed in health check response',
              requestUrl: reqUrl,
              encodingNote: '헬스체크: JSON 파싱 실패',
            );
          }
        }
      } else {
        // 여전히 500 등 오류
        if (kDebugMode) {
          debugPrint('[KraServerStatus] 🔴 #$_checkCount: HTTP ${resp.statusCode}');
        }
        // [v2] HTTP 오류 → 에러 로그 적재
        await cache.logApiError(
          apiName: 'HealthCheck-#$_checkCount',
          statusCode: resp.statusCode,
          errorBody: resp.body.length > 200
              ? resp.body.substring(0, 200) : resp.body,
          requestUrl: reqUrl,
          serviceKeyMasked: RaceScheduleCache.validateServiceKey(_serviceKey).maskedKey,
          encodingNote: '헬스체크 #$_checkCount: HTTP ${resp.statusCode}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[KraServerStatus] ⚠️ #$_checkCount: 네트워크 오류 $e');
      }
      // [v2] 네트워크 예외도 로그 적재
      try {
        final cache2 = RaceScheduleCache();
        await cache2.logApiError(
          apiName: 'HealthCheck-#$_checkCount',
          statusCode: 0,
          errorBody: e.toString(),
          requestUrl: '$_baseUrl/API187 health-check',
          encodingNote: 'Timeout/NetworkException',
        );
      } catch (_) {
        // 로그 적재 실패 시 무시 (순환 오류 방지)
      }
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  void _stopHealthCheck() {
    _healthTimer?.cancel();
    _healthTimer = null;
    if (kDebugMode) {
      debugPrint('[KraServerStatus] 🛑 헬스체크 타이머 정지 (복구 완료)');
    }
  }

  // ── 수동 헬스체크 트리거 (앱 재개 시 등) ─────────────────────
  Future<void> triggerManualCheck() async {
    if (_isDown) {
      await _runHealthCheck();
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  [v2] 앱 초기화 시 1회 실행
  //
  //  추가 동작:
  //  ① RaceScheduleCache.purgeExpiredCache() → 만료 캐시 선제 정리
  //  ② ServiceKey 검증 진단 로그
  //  ③ 기존 헬스체크 로직
  // ══════════════════════════════════════════════════════════════
  Future<void> initialCheck() async {
    // ── [v2] 만료 캐시 선제 정리 ──────────────────────────────
    try {
      final cache = RaceScheduleCache();
      await cache.purgeExpiredCache();
      if (kDebugMode) {
        debugPrint('[KraServerStatus] 🧹 initialCheck: 만료 캐시 정리 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[KraServerStatus] ⚠️ purgeExpiredCache 오류: $e');
      }
    }

    // ── [v2] ServiceKey 진단 (최초 1회) ─────────────────────────
    if (kDebugMode) {
      final keyValidation = RaceScheduleCache.validateServiceKey(_serviceKey);
      debugPrint('[KraServerStatus] 🔑 ServiceKey 진단: ${keyValidation.summary}');
      debugPrint('[KraServerStatus] 🔑 URL 인코딩 필요: ${keyValidation.needsEncoding}');
    }

    // ── 기존 헬스체크 로직 ───────────────────────────────────
    await _runHealthCheck();
    if (_isDown) {
      _startHealthCheck();
    }
  }

  // ── 유틸 ─────────────────────────────────────────────────────
  static String _todayStr() {
    final now = DateTime.now().toLocal();
    return '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    super.dispose();
  }
}
