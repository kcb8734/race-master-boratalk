// ============================================================
//  user_calibration_model.dart
//  경마통 Race Master — 사용자 수동 보정 데이터 모델
//
//  저작권: 본 소스코드는 「사용자 주도형 경주 시뮬레이션
//  수동 보정 모듈」의 데이터 계층을 정의합니다.
//  (컴퓨터프로그램저작물, 한국저작권위원회 등록 대상)
// ============================================================

import 'package:flutter/foundation.dart';

// ──────────────────────────────────────────────────────────────
//  SpurtTimingSlot — 마번별 스퍼트 시점 드롭다운 열거형
//  유저가 선택한 스퍼트 발동 시점 → Zone4 진입 트리거 오프셋 변환
// ──────────────────────────────────────────────────────────────
enum SpurtTimingSlot {
  early('조기 스퍼트', -0.05),    // 표준보다 50m 빠름 (고스태미나 말 전략)
  standard('표준', 0.0),          // 기본값 (변경 없음)
  delayed('후기 스퍼트', 0.04),   // 표준보다 40m 늦음 (단거리 폭발형)
  veryLate('극후기', 0.08);       // 표준보다 80m 늦음 (대기만성형)

  const SpurtTimingSlot(this.label, this.progOffset);
  final String label;
  final double progOffset; // prog 단위 오프셋 (±0.00~0.10 범위)
}

// ──────────────────────────────────────────────────────────────
//  HorseCalibration — 마번 1개의 보정 데이터 집합
//
//  각 필드는 UI 컴포넌트에서 실시간으로 업데이트되며,
//  UserCalibrationController가 물리 엔진에 주입(inject)함
// ──────────────────────────────────────────────────────────────
@immutable
class HorseCalibration {
  /// 마번 식별자 (1-based gateNo)
  final int gateNo;

  /// [userOddsWeight] — 배당률 가중치 오버라이드
  /// 범위: -2.0 ~ +2.0 (기본값: 0.0)
  /// 물리 엔진 반영: baseSpeed 산출 시 oddsAdjFactor에 가산
  /// 양수 → 고배당 신뢰도 하락(낮은 승률 보정), 음수 → 저배당 과열 조정
  final double userOddsWeight;

  /// [userJockeyBuff] — 기수 멘탈 보정 슬라이더
  /// 범위: -1.0 ~ +1.0 (기본값: 0.0)
  /// 물리 엔진 반영: mentalBuff 계수에 선형 합산
  /// +1.0 = MentalBuff 최대 발동(+15% × afScale),
  /// -1.0 = SafeMode 페널티 추가(-10% × afScale)
  final double userJockeyBuff;

  /// [spurtTiming] — 스퍼트 시점 드롭다운 선택값
  /// Zone4 진입 prog 오프셋으로 변환 (SpurtTimingSlot.progOffset)
  final SpurtTimingSlot spurtTiming;

  // ── [NEW] HorsePhysicsProfile 물리 가중치 슬라이더 ───────────────────
  /// [userInitialDriveWeight] — 초반 속도(Zone1) 주도력 가중치
  /// 범위: -1.0 ~ +1.0 (기본값: 0.0)
  /// 물리 엔진 반영: HorsePhysicsProfile.zone1SpeedMult × (1.0 + userInitialDriveWeight)
  /// +1.0 = 초반 가속도 최대 증폭,  -1.0 = 초반 주도력 억제
  final double userInitialDriveWeight;

  /// [userFinalSpurtWeight] — 후반 지구력(Zone4) 가중치
  /// 범위: -1.0 ~ +1.0 (기본값: 0.0)
  /// 물리 엔진 반영: HorsePhysicsProfile.zone4SpurtMult × (1.0 + userFinalSpurtWeight)
  /// +1.0 = 종반 스퍼트 최대 증폭,  -1.0 = 후반 탄력 억제
  final double userFinalSpurtWeight;

  const HorseCalibration({
    required this.gateNo,
    this.userOddsWeight        = 0.0,
    this.userJockeyBuff        = 0.0,
    this.spurtTiming           = SpurtTimingSlot.standard,
    this.userInitialDriveWeight = 0.0,
    this.userFinalSpurtWeight   = 0.0,
  });

  HorseCalibration copyWith({
    double?          userOddsWeight,
    double?          userJockeyBuff,
    SpurtTimingSlot? spurtTiming,
    double?          userInitialDriveWeight,
    double?          userFinalSpurtWeight,
  }) => HorseCalibration(
    gateNo:                 gateNo,
    userOddsWeight:         userOddsWeight         ?? this.userOddsWeight,
    userJockeyBuff:         userJockeyBuff         ?? this.userJockeyBuff,
    spurtTiming:            spurtTiming            ?? this.spurtTiming,
    userInitialDriveWeight: userInitialDriveWeight ?? this.userInitialDriveWeight,
    userFinalSpurtWeight:   userFinalSpurtWeight   ?? this.userFinalSpurtWeight,
  );

  /// 모든 보정값이 기본값인지 확인 (패널 리셋 판정용)
  bool get isDefault =>
      userOddsWeight         == 0.0 &&
      userJockeyBuff         == 0.0 &&
      spurtTiming            == SpurtTimingSlot.standard &&
      userInitialDriveWeight == 0.0 &&
      userFinalSpurtWeight   == 0.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HorseCalibration &&
          gateNo                 == other.gateNo &&
          userOddsWeight         == other.userOddsWeight &&
          userJockeyBuff         == other.userJockeyBuff &&
          spurtTiming            == other.spurtTiming &&
          userInitialDriveWeight == other.userInitialDriveWeight &&
          userFinalSpurtWeight   == other.userFinalSpurtWeight;

  @override
  int get hashCode => Object.hash(
    gateNo, userOddsWeight, userJockeyBuff, spurtTiming,
    userInitialDriveWeight, userFinalSpurtWeight,
  );

  @override
  String toString() =>
      'HorseCalibration(gate=$gateNo, oddsW=$userOddsWeight, '
      'jockeyB=$userJockeyBuff, spurt=${spurtTiming.label}, '
      'initDrive=$userInitialDriveWeight, finalSpurt=$userFinalSpurtWeight)';
}

// ──────────────────────────────────────────────────────────────
//  RaceCalibrationSnapshot — 경주 단위 전체 보정 스냅샷
//  모든 마번의 HorseCalibration을 gateNo → 객체 맵으로 보관
// ──────────────────────────────────────────────────────────────
class RaceCalibrationSnapshot {
  final Map<int, HorseCalibration> _map;

  const RaceCalibrationSnapshot._(this._map);

  factory RaceCalibrationSnapshot.empty(List<int> gateNos) =>
      RaceCalibrationSnapshot._(
        {for (final g in gateNos) g: HorseCalibration(gateNo: g)},
      );

  HorseCalibration forGate(int gateNo) =>
      _map[gateNo] ?? HorseCalibration(gateNo: gateNo);

  RaceCalibrationSnapshot update(HorseCalibration updated) =>
      RaceCalibrationSnapshot._(
        {..._map, updated.gateNo: updated},
      );

  /// 전체 보정값 초기화
  RaceCalibrationSnapshot reset(List<int> gateNos) =>
      RaceCalibrationSnapshot.empty(gateNos);

  /// 보정이 적용된 마번 수
  int get modifiedCount =>
      _map.values.where((c) => !c.isDefault).length;

  Iterable<HorseCalibration> get all => _map.values;
}
