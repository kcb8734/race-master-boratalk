import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// ══════════════════════════════════════════════════════════════════════════
//  KraServerStatus — KRA 공공데이터 API 서버 장애 감지 & 자동 복구 시스템
//
//  ▸ isDown: true  → HTTP 500 / "Unexpected errors" 감지 → 장애 배너 노출
//  ▸ isDown: false → HTTP 200 + 정상 JSON 응답 확인     → 배너 해제
//  ▸ 10분 주기 헬스체크 (서버 회복 자동 감지)
//  ▸ ChangeNotifier → Consumer<KraServerStatus>로 UI 반응
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

  Timer? _healthTimer;

  // ── Public Getters ───────────────────────────────────────────
  bool get isDown       => _isDown;
  bool get isChecking   => _isChecking;
  bool get isUp         => !_isDown;
  DateTime? get detectedAt   => _detectedAt;
  DateTime? get recoveredAt  => _recoveredAt;
  String get lastErrorMsg    => _lastErrorMsg;
  int get checkCount         => _checkCount;

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
      if (kDebugMode) {
        debugPrint('[KraServerStatus] 🔴 서버 장애 감지: $errorMsg');
      }
      // 즉시 헬스체크 타이머 시작 (10분 주기)
      _startHealthCheck();
      notifyListeners();
    }
  }

  /// HTTP 200 + 정상 JSON 응답 수신 시 호출
  void reportServerOk() {
    if (_isDown) {
      _isDown = false;
      _recoveredAt = DateTime.now();
      if (kDebugMode) {
        debugPrint('[KraServerStatus] ✅ 서버 복구 확인: ${_recoveredAt}');
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

    try {
      final today = _todayStr();
      final uri = Uri.parse(
        '$_baseUrl/API187?serviceKey=$_serviceKey'
        '&numOfRows=1&pageNo=1&meet=1&rc_date=$today&_type=json',
      );

      final resp = await http.get(uri).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final body = resp.body;

        // "Unexpected errors" 텍스트 포함 시 → 여전히 장애
        if (body.contains('Unexpected errors') ||
            body.contains('unexpected errors')) {
          if (kDebugMode) {
            debugPrint('[KraServerStatus] 🔴 #$_checkCount: 여전히 장애 (200 but Unexpected errors)');
          }
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
          }
        }
      } else {
        // 여전히 500 등 오류
        if (kDebugMode) {
          debugPrint('[KraServerStatus] 🔴 #$_checkCount: HTTP ${resp.statusCode}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[KraServerStatus] ⚠️ #$_checkCount: 네트워크 오류 $e');
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

  // ── 헬스체크 즉시 강제 시작 (앱 초기화 시 1회 실행) ──────────
  Future<void> initialCheck() async {
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
