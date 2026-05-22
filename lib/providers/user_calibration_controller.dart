// ============================================================
//  user_calibration_controller.dart
//  경마통 Race Master — 사용자 주도형 수동 보정 제어 컨트롤러
//
//  ┌─────────────────────────────────────────────────────┐
//  │  저작권 등록 대상 핵심 소스코드                         │
//  │  알고리즘명: 실시간 배팅 배당률 연동 및                 │
//  │  사용자 주도형 경주 시뮬레이션 수동 보정 엔진            │
//  │  (컴퓨터프로그램저작물 — 한국저작권위원회 등록)           │
//  └─────────────────────────────────────────────────────┘
//
//  【핵심 기능 요약】
//  1. UI → 물리엔진 파라미터 실시간 오버라이딩(API Parameter Overriding)
//     - userOddsWeight : 배당률 기반 기초속도(baseSpeed) oddsAdjFactor 보정
//     - userJockeyBuff : 기수 멘탈버프 계수 실시간 재산출
//     - spurtTiming    : Zone4 진입 prog 오프셋 동적 주입
//
//  2. ChangeNotifier 기반 리액티브 상태 관리
//     - notifyListeners() → UI 즉각 갱신 (16ms 이내)
//     - 물리 루프(Timer.periodic 16ms)와 동기화
//
//  3. HorseEntry.userBonus 실시간 갱신 API
//     - applyToEntry(HorseEntry) → 보정값이 반영된 새 HorseEntry 반환
//     - 물리 엔진은 매 틱(16ms)마다 applyToEntry 결과를 speedMult에 반영
// ============================================================

import 'package:flutter/foundation.dart';
import '../models/user_calibration_model.dart';
import '../models/race_models.dart';

// ──────────────────────────────────────────────────────────────
//  물리 엔진 오버라이드 상수
//  (race_horse_data.dart의 k상수와 연동)
// ──────────────────────────────────────────────────────────────

/// 배당률 가중치 → baseSpeed 보정 변환 계수
/// userOddsWeight 1.0 당 baseSpeed에 ±oddsSpeedDelta 적용
const double kOddsWeightSpeedDelta = 0.015;

/// 기수 멘탈 슬라이더 → speedMult 변환 계수
/// userJockeyBuff +1.0 → Zone4 speedMult +kJockeyBuffMaxDelta
const double kJockeyBuffMaxDelta = 0.12;

/// 스퍼트 시점 오프셋의 Zone4 스퍼트 페이드 계수 스케일
/// SpurtTimingSlot.progOffset × kSpurtTimingFadeMult → fade 강도 보정
const double kSpurtTimingFadeMult = 0.8;

/// userOddsWeight 유효 범위
const double kOddsWeightMin = -2.0;
const double kOddsWeightMax =  2.0;

/// userJockeyBuff 유효 범위
const double kJockeyBuffMin = -1.0;
const double kJockeyBuffMax =  1.0;

// ──────────────────────────────────────────────────────────────
//  UserCalibrationController
//  ChangeNotifier — Provider 패턴으로 UI와 물리 엔진을 연결
// ──────────────────────────────────────────────────────────────
class UserCalibrationController extends ChangeNotifier {
  // ── 내부 상태 ───────────────────────────────────────────────
  RaceCalibrationSnapshot _snapshot;
  final List<int> _gateNos;

  /// 패널 활성화 여부 (UI 토글 — 경주 시작 전에만 활성)
  bool _panelEnabled = true;

  /// 마지막 보정 적용 타임스탬프 (물리 엔진 동기화 추적용)
  DateTime _lastUpdated = DateTime.now();

  // ── 생성자 ──────────────────────────────────────────────────
  UserCalibrationController({required List<int> gateNos})
      : _gateNos  = List.unmodifiable(gateNos),
        _snapshot = RaceCalibrationSnapshot.empty(gateNos);

  // ── 공개 읽기 속성 ──────────────────────────────────────────
  bool               get panelEnabled  => _panelEnabled;
  DateTime           get lastUpdated   => _lastUpdated;
  int                get modifiedCount => _snapshot.modifiedCount;
  List<int>          get gateNos       => _gateNos;

  /// 특정 마번의 현재 보정값 반환
  HorseCalibration calibrationFor(int gateNo) =>
      _snapshot.forGate(gateNo);

  // ──────────────────────────────────────────────────────────
  //  [공개 API] ① 배당률 가중치 입력창 업데이트
  //  호출처: CalibrationOddsField.onChanged
  //
  //  물리 엔진 반영 경로:
  //    userOddsWeight → applyToEntry() → HorseEntry.userBonus
  //    → _Horse.userBonus → Zone3 speedMult *= 1.12 + bf*0.08*user
  // ──────────────────────────────────────────────────────────
  void setOddsWeight(int gateNo, double value) {
    if (!_panelEnabled) return;
    final clamped = value.clamp(kOddsWeightMin, kOddsWeightMax);
    final current = _snapshot.forGate(gateNo);
    if (current.userOddsWeight == clamped) return; // 변경 없으면 skip

    _snapshot    = _snapshot.update(current.copyWith(userOddsWeight: clamped));
    _lastUpdated = DateTime.now();
    notifyListeners(); // ← UI + 물리 루프 즉시 갱신 트리거
  }

  // ──────────────────────────────────────────────────────────
  //  [공개 API] ② 기수 멘탈 보정 슬라이더 업데이트
  //  호출처: CalibrationJockeySlider.onChanged
  //
  //  물리 엔진 반영 경로:
  //    userJockeyBuff → applyToEntry() → HorseEntry.userBonus에 합산
  //    → _Horse.userBonus → Zone4 Jockey Engine 계수 오버라이드
  //    +1.0: mentalBuff 강제 활성화 + kJockeyBuffMaxDelta(+12%) 가산
  //    -1.0: safeMode 페널티 추가 + kJockeyBuffMaxDelta(-12%) 감산
  // ──────────────────────────────────────────────────────────
  void setJockeyBuff(int gateNo, double value) {
    if (!_panelEnabled) return;
    final clamped = value.clamp(kJockeyBuffMin, kJockeyBuffMax);
    final current = _snapshot.forGate(gateNo);
    if (current.userJockeyBuff == clamped) return;

    _snapshot    = _snapshot.update(current.copyWith(userJockeyBuff: clamped));
    _lastUpdated = DateTime.now();
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────
  //  [공개 API] ③ 스퍼트 시점 드롭다운 선택
  //  호출처: CalibrationSpurtDropdown.onChanged
  //
  //  물리 엔진 반영 경로:
  //    spurtTiming.progOffset → spurtProgOffset(gateNo)
  //    → RaceAnimationScreen._spurt100 동적 보정
  //    early(-0.05): _spurt100 -= 0.05 → 더 빨리 스퍼트 발동
  //    veryLate(+0.08): _spurt100 += 0.08 → 늦은 스퍼트 발동
  // ──────────────────────────────────────────────────────────
  void setSpurtTiming(int gateNo, SpurtTimingSlot slot) {
    if (!_panelEnabled) return;
    final current = _snapshot.forGate(gateNo);
    if (current.spurtTiming == slot) return;

    _snapshot    = _snapshot.update(current.copyWith(spurtTiming: slot));
    _lastUpdated = DateTime.now();
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────
  //  [핵심 API] applyToEntry — HorseEntry에 보정값 주입
  //
  //  물리 루프(Timer.periodic 16ms)에서 매 틱마다 호출:
  //    final adjusted = controller.applyToEntry(h.entry);
  //    h.userBonus = adjusted.userBonus;  // → speedMult 체인에 반영
  //
  //  ┌────────────────────────────────────────────────────┐
  //  │  P_final 오버라이딩 연산식                           │
  //  │                                                    │
  //  │  userBonus_final =                                 │
  //  │    entry.userBonus (기존 KRA API 기반)              │
  //  │    + userOddsWeight × kOddsWeightSpeedDelta × 333 │
  //  │    + userJockeyBuff × kJockeyBuffMaxDelta  × 333  │
  //  │                                                    │
  //  │  (× 333: -1~+1 → -5~+5 userBonus 스케일 역변환)   │
  //  └────────────────────────────────────────────────────┘
  // ──────────────────────────────────────────────────────────
  HorseEntry applyToEntry(HorseEntry entry) {
    final calib = _snapshot.forGate(entry.gateNo);
    if (calib.isDefault) return entry; // 보정 없으면 원본 반환 (zero-cost)

    // ① oddsWeight → userBonus 가산
    //    userOddsWeight +2.0 → userBonus +10.0 (물리 엔진 최대 보정)
    final oddsAdj = calib.userOddsWeight * kOddsWeightSpeedDelta * 333.0;

    // ② jockeyBuff → userBonus 가산
    //    userJockeyBuff +1.0 → userBonus +40.0 (Zone4 speedMult ≈ +12%)
    final jockeyAdj = calib.userJockeyBuff * kJockeyBuffMaxDelta * 333.0;

    // ③ 합산 후 userBonus 범위 클램프 (-5.0 ~ +5.0)
    final newUserBonus = (entry.userBonus + oddsAdj + jockeyAdj)
        .clamp(-5.0, 5.0);

    return entry.copyWith(userBonus: newUserBonus);
  }

  // ──────────────────────────────────────────────────────────
  //  [공개 API] spurtProgOffset — 스퍼트 시점 prog 오프셋 반환
  //  호출처: RaceAnimationScreen._initHorses() 내
  //    final offset = controller.spurtProgOffset(entry.gateNo);
  //    horse._spurt100 = base_spurt100 + offset;
  // ──────────────────────────────────────────────────────────
  double spurtProgOffset(int gateNo) =>
      _snapshot.forGate(gateNo).spurtTiming.progOffset;

  // ──────────────────────────────────────────────────────────
  //  [공개 API] speedMultOverride — Zone4 speedMult 추가 계수
  //  호출처: 물리 루프 inZone4Straight 블록
  //    speedMult *= controller.speedMultOverride(h.entry.gateNo, raceNoInt);
  //
  //  연산식:
  //    Δmult = userJockeyBuff × kJockeyBuffMaxDelta × afScale
  //    반환:  1.0 + Δmult  (Δmult ∈ [-0.162, +0.162])
  // ──────────────────────────────────────────────────────────
  double speedMultOverride(int gateNo, double afScale) {
    final calib = _snapshot.forGate(gateNo);
    if (calib.userJockeyBuff == 0.0) return 1.0; // 보정 없으면 항등원
    final delta = calib.userJockeyBuff * kJockeyBuffMaxDelta * afScale;
    return (1.0 + delta).clamp(0.7, 1.35);
  }

  // ──────────────────────────────────────────────────────────
  //  [공개 API] oddsAdjFactor — baseSpeed oddsAdj 추가 계수
  //  호출처: _initHorses() baseSpeed 계산 블록
  //    baseSpeed *= controller.oddsAdjFactor(entry.gateNo);
  //
  //  연산식:
  //    Δfactor = userOddsWeight × kOddsWeightSpeedDelta
  //    반환:    1.0 + Δfactor  (Δfactor ∈ [-0.03, +0.03])
  // ──────────────────────────────────────────────────────────
  double oddsAdjFactor(int gateNo) {
    final calib = _snapshot.forGate(gateNo);
    if (calib.userOddsWeight == 0.0) return 1.0;
    return (1.0 + calib.userOddsWeight * kOddsWeightSpeedDelta)
        .clamp(0.97, 1.03);
  }

  // ──────────────────────────────────────────────────────────
  //  패널 잠금/해제 (경주 시작 시 잠금 → 종료 후 해제)
  // ──────────────────────────────────────────────────────────
  void lockPanel()   { _panelEnabled = false; notifyListeners(); }
  void unlockPanel() { _panelEnabled = true;  notifyListeners(); }

  // ──────────────────────────────────────────────────────────
  //  전체 보정값 초기화
  // ──────────────────────────────────────────────────────────
  void resetAll() {
    _snapshot    = RaceCalibrationSnapshot.empty(_gateNos);
    _lastUpdated = DateTime.now();
    notifyListeners();
  }

  /// 단일 마번 초기화
  void resetGate(int gateNo) {
    _snapshot    = _snapshot.update(HorseCalibration(gateNo: gateNo));
    _lastUpdated = DateTime.now();
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────
  //  디버그 출력 (kDebugMode 전용)
  // ──────────────────────────────────────────────────────────
  void debugDump() {
    if (!kDebugMode) return;
    debugPrint('[UserCalib] modified=$modifiedCount, '
               'lastUpdated=$_lastUpdated');
    for (final c in _snapshot.all) {
      if (!c.isDefault) debugPrint('  → $c');
    }
  }
}
