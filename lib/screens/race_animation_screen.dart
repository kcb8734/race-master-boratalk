import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/race_models.dart';
import '../models/race_horse_data.dart';
import '../providers/user_calibration_controller.dart';
import '../utils/horse_cap_colors.dart';



// ══════════════════════════════════════════════════════════════════════════
//  경마통 · 탑다운 단일레인 오벌 레이스 (Round 7)
//
//  [트랙 구조]
//  · 단일 레인 (바깥쪽 1개 라인만) — 내부 레인 완전 제거
//  · 서울 경마공원 평면도 기반 오벌 (직선 + 반원 코너)
//  · 거리별 출발선 자동 산출, 결승선(GOAL) 항상 고정
//
//  [스타트 게이트 뷰 - Round 7 개편]
//  · START 전: 정면 게이트 뷰 (세로 박스 배열)
//  · 상단: 레이스명 배너 (경주장 + 경주번호 + 거리)
//  · 오른쪽=1번마, 왼쪽으로 마번 증가
//  · 각 박스: 마번색 배경 + 번호 + 기수저지(원) + 말이름 + 기수이름
//  · 하단: 경주 방향 표시 (서울·부산경남=CCW, 제주=CW)
//
//  [경주 방향]
//  · CCW (Counter-ClockWise): 서울(1), 부산경남(2) — 기본값
//  · CW  (ClockWise):         제주(3) — toPoint/toAngle 좌우 반전
//
//  [3단계 경마 물리 법칙]
//  1단계 코너  : 85~90% 감속 + 병목 클러스터 현상
//  2단계 직선  : 400m~200m 구간 가점 부스터 풀가속 + 추월 이펙트
//  3단계 스퍼트: 100m~GOAL 스테미나 연산 → 막판 역전극
// ══════════════════════════════════════════════════════════════════════════

// ──────────────────────────────────────────────────────────────────────────
//  트랙 기하학
// ──────────────────────────────────────────────────────────────────────────
// ──────────────────────────────────────────────────────────────────────────
//  제주 트랙 기하학 (_TGJeju) — 실제 도면 기반 세로형 오벌 CCW
//
//  [실제 제주 경마장 도면 기준]
//    - 우측 직선(메인스트래치): 493.7m  ← 출발선 800~1200m 위치
//    - 하단 반원 코너: π × 97.5m ≈ 306.3m  (우→좌)
//    - 좌측 직선(백스트래치): 293.7m    ← GOAL 고정 (좌직선 하단부)
//    - 상단 반원 코너: π × 97.5m ≈ 306.3m  (좌→우, 1300~1400m 출발선)
//    - 총 1주: ≈ 1400.0m
//
//  CCW 반시계 진행 순서 (이미지 화살표 방향):
//    구간0 (0→p2):   우측 직선  위→아래  (800~1200m 출발선, 긴 직선)
//    구간1 (p2→p3):  하단 코너  우→좌   (하단 반원, CCW)
//    구간2 (p3→p4):  좌측 직선  아래→위  (GOAL 포함, 1610m 출발선)
//    구간3 (p4→1.0): 상단 코너  좌→우   (상단 반원, 1300~1400m 출발선)
//
//  화면 배치 (세로형):
//    우직선: 화면 오른쪽, 위에서 아래로
//    하단코너: 화면 하단, 반원 (오른쪽→왼쪽)
//    좌직선: 화면 왼쪽, 아래에서 위로
//    상단코너: 화면 상단, 반원 (왼쪽→오른쪽)
// ──────────────────────────────────────────────────────────────────────────
class _TGJeju {
  // 실제 제주 경마장 구간 거리(m) — 도면 기준
  static const double dRightStr = 493.7;  // 우측 직선 (긴 직선, 출발선 800~1200m)
  static const double dCornB    = 306.3;  // 하단 반원 코너 (pi x 97.5)
  static const double dLeftStr  = 293.7;  // 좌측 직선 (GOAL 상단부)
  static const double dCornT    = 306.3;  // 상단 반원 코너 (1300~1400m 출발선)
  static const double total     = dRightStr + dCornB + dLeftStr + dCornT; // =1400.0

  // 구간 진행률 경계
  static double get p2 => dRightStr / total;                        // 우직선 끝 =0.353
  static double get p3 => (dRightStr + dCornB) / total;             // 좌직선 시작 =0.571
  static double get p4 => (dRightStr + dCornB + dLeftStr) / total;  // 상단코너 시작 =0.781

  // GOAL 고정 위치: 좌직선 상단부 85%
  // p3(좌직선 시작=아래) ~ p4(좌직선 끝=위) 중 85% = 화면 좌측 상단부
  static double get goalP => p3 + (p4 - p3) * 0.85; // =0.750

  // ── 출발 진행률 (goalP 역산 방식) ──
  //
  //  [설계 원칙]
  //    GOAL은 항상 goalP(좌직선 85%, ≈0.7497)로 고정
  //    startP = (goalP - distM/total + N) % 1.0  (N은 양수 보정)
  //    → 말이 startP에서 출발해 goalP까지 달리면 정확히 distM 이동
  //
  //  [거리별 startP 및 위치 — goalP=0.7497 기준]
  //    1610m: 0.5997 → 좌직선 13%  (1바퀴+210m = GOAL+1바퀴 뒤)
  //    1400m: 0.7497 → 좌직선 85%  (GOAL과 동일, 1바퀴 완주)
  //    1300m: 0.8212 → 상단코너 18% (18%지점 출발)
  //    1200m: 0.8926 → 상단코너 51%
  //    1110m: 0.9569 → 상단코너 80%
  //    1000m: 0.0355 → 우직선 10%
  //     900m: 0.1069 → 우직선 30%
  //     800m: 0.1783 → 우직선 51%
  static double startP(int distM) {
    final ratio = distM.clamp(800, 1700) / total;
    return (goalP - ratio + 2.0) % 1.0;
  }

  // ── 진행률 → 화면 좌표 (세로형 CCW) ──
  //
  //  세로형 오벌 배치 (CCW 반시계):
  //    hw  = 가로 반폭 (코너 반지름)
  //    vr  = 세로 반높이
  //
  //  진행 순서 (CCW):
  //    구간0: 우직선  (cx+hw, cy-vr) → (cx+hw, cy+vr)  위→아래
  //    구간1: 하단코너 (cx+hw,cy+vr) → (cx-hw,cy+vr)   오른쪽→왼쪽
  //    구간2: 좌직선  (cx-hw, cy+vr) → (cx-hw, cy-vr)  아래→위
  //    구간3: 상단코너 (cx-hw,cy-vr) → (cx+hw,cy-vr)   왼쪽→오른쪽
  //
  //  clusterOff 방향 (말이 트랙 안에 머무르도록):
  //    우직선: 진행방향(↓)에 수직, 안쪽=왼쪽(-x방향) → clusterOff를 -x로
  //           (양수 clusterOff = 트랙 안쪽으로 이동)
  //    좌직선: 진행방향(↑)에 수직, 안쪽=오른쪽(+x방향) → clusterOff를 +x로
  //    하단코너: 중심(cx,cy+vr)에서 안쪽 방향 (반지름 줄이는 방향)
  //    상단코너: 중심(cx,cy-vr)에서 안쪽 방향
  static Offset toPoint(double p, Rect tr, {double clusterOff = 0}) {
    final pp = p % 1.0;
    final cx = tr.center.dx;
    final cy = tr.center.dy;
    final hw  = tr.width  * 0.38;   // 가로 반폭 (코너 반지름)
    final vr  = tr.height * 0.43;   // 세로 반높이

    // ★ clusterOff 클램핑: hw*0.08 이내 (트랙 폭의 8% = 약 ±4px)
    // 과도한 오프셋은 말이 트랙 안/밖으로 벗어나는 원인
    final clamp = (hw * 0.08).clamp(0.0, 5.0);
    final safeOff = clusterOff.clamp(-clamp, clamp);

    Offset result;

    if (pp < p2) {
      // 구간0: 우직선  위→아래  (CCW)
      // 진행방향: +y (아래), 법선(트랙 안쪽): -x (왼쪽)
      // clusterOff > 0 = 안쪽(왼쪽), < 0 = 바깥쪽(오른쪽)
      final f = pp / p2;
      result = Offset(cx + hw - safeOff, cy - vr + f * vr * 2);
    } else if (pp < p3) {
      // 구간1: 하단 반원 코너 (중심: cx, cy+vr)
      // CCW: 오른쪽(각=0) → 아래(각=π/2) → 왼쪽(각=π)
      // f=0: ang=0 → (cx+hw, cy+vr)
      // f=0.5: ang=π/2 → (cx, cy+vr+hw)  (코너 최하단)
      // f=1: ang=π → (cx-hw, cy+vr)
      final f   = (pp - p2) / (p3 - p2);
      final ang = f * pi; // 0 → π (CCW 하단코너)
      final r = hw - safeOff; // 안쪽 오프셋: 반지름 줄임
      final baseX = cx + cos(ang) * r;
      final baseY = (cy + vr) + sin(ang) * r;
      result = Offset(baseX, baseY);
    } else if (pp < p4) {
      // 구간2: 좌직선  아래→위  (CCW)
      // 진행방향: -y (위), 법선(트랙 안쪽): +x (오른쪽)
      // clusterOff > 0 = 안쪽(오른쪽), < 0 = 바깥쪽(왼쪽)
      final f = (pp - p3) / (p4 - p3);
      result = Offset(cx - hw + safeOff, cy + vr - f * vr * 2);
    } else {
      // 구간3: 상단 반원 코너 (중심: cx, cy-vr)
      // CCW: 왼쪽(각=π) → 위(각=3π/2) → 오른쪽(각=2π)
      // f=0: ang=π → (cx-hw, cy-vr)
      // f=0.5: ang=3π/2 → (cx, cy-vr-hw) (코너 최상단)
      // f=1: ang=2π → (cx+hw, cy-vr)
      final f   = (pp - p4) / (1.0 - p4);
      final ang = pi + f * pi; // π → 2π (CCW 상단코너)
      final r = hw - safeOff; // 안쪽 오프셋: 반지름 줄임
      final baseX = cx + cos(ang) * r;
      final baseY = (cy - vr) - sin(ang) * r;
      result = Offset(baseX, baseY);
    }

    return result;
  }

  // ── 진행률 → 진행 방향각 (라디안, CCW) ──
  //
  //  CCW(반시계) 진행 방향각 (화면 좌표계: y=아래):
  //    우직선 위→아래: π/2
  //    하단코너 CCW: π/2 (오른쪽 접선=아래) → π (아래 접선=왼쪽) → 3π/2 (왼쪽 접선=위)
  //    좌직선 아래→위: 3π/2 (= -π/2, 위쪽)
  //    상단코너 CCW: 3π/2 → 2π (=0, 오른쪽) → π/2 (아래)
  //
  //  toPoint의 ang 공식과 일치시킴:
  //    하단코너: ang=f*π → 접선각 = ang + π/2 = f*π + π/2
  //    상단코너: ang=π+f*π → 접선각 = ang + π/2 = 3π/2+f*π
  static double toAngle(double p) {
    final pp = p % 1.0;
    if (pp < p2) {
      // 우직선: 아래 방향 (π/2)
      return pi / 2;
    } else if (pp < p3) {
      // 하단 코너 (CCW): 접선 방향
      // ang=f*π (toPoint와 동일)
      // 접선각 = ang + π/2 (반시계 접선은 +90도)
      final f = (pp - p2) / (p3 - p2);
      return f * pi + pi / 2; // π/2 → 3π/2 (아래→왼→위)
    } else if (pp < p4) {
      // 좌직선: 위 방향 (3π/2 = -π/2)
      return -pi / 2;
    } else {
      // 상단 코너 (CCW): 접선 방향
      // ang=π+f*π (toPoint와 동일)
      // 접선각 = ang + π/2
      final f = (pp - p4) / (1.0 - p4);
      return (pi + f * pi) + pi / 2; // 3π/2 → 5π/2 → π/2 (위→오→아래)
    }
  }

  // 현재 구간
  static _Seg segment(double p) {
    final pp = p % 1.0;
    if (pp < p2) return _Seg.topStr;   // 우직선 (세로형에서 직선1)
    if (pp < p3) return _Seg.cornerR;  // 하단 코너
    if (pp < p4) return _Seg.botStr;   // 좌직선 (세로형에서 직선2)
    return _Seg.cornerL;               // 상단 코너
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  서울/부산경남 트랙 기하학 (_TG) — 실제 도면 기반 세로형 오벌 CW
//
//  [서울경마장 도면 기준 — 2단 트랙(내측/외측 겸용)]
//    - 우직선(백스트래치):     ≈ 400m  (아래→위, CW 구간0) ← 1000/1200/1300/1400m 출발선
//    - 상단 반원 코너:         ≈ 350m  (우→좌, CW 구간1)  ← 2000/2300m 출발선
//    - 좌직선(메인스트래치):   ≈ 600m  (위→아래, CW 구간2) ← GOAL(하단85%) + 1700~1900m 출발선
//    - 하단 반원 코너:         ≈ 350m  (좌→우, CW 구간3)  ← 1600m 출발선(코너 센터)
//    - 총 1주: ≈ 1700m (내측 기준)
//
//  CW 시계방향 진행 (실제 서울/부산경남 경주 방향):
//    구간0 (0→p2):   우직선   아래→위  (1000/1200/1300/1400m 출발선) ★
//    구간1 (p2→p3):  상단코너 우→좌   (2000/2300m 출발선)
//    구간2 (p3→p4):  좌직선   위→아래  (GOAL 하단85% + 1700~1900m 출발선) ★
//    구간3 (p4→1.0): 하단코너 좌→우   (1600m 출발선 코너 중앙)
//
//  GOAL 위치: 좌직선 하단부 (~85% 지점) = 화면 좌측 하단, 하단코너 진입 전
//    → 도면 기준: 좌직선 하단 결승선 (실제 서울 경마장 메인스트레치 하단)
//    → CW 진행: p3(좌직선 시작=상단) → p4(좌직선 끝=하단)
//    → GOAL은 p3+(p4-p3)*0.85 = 좌직선 85% 지점 ≈ 화면 좌측 하단부
//
//  출발선 거리별 위치 (도면 기준):
//    1000m: 우직선 65%   (특별 경주 전용, 우상단 바깥 표시) ← 우직선 구간0
//    1200m: 우직선 15%   (우직선 하단부)                    ← 우직선 구간0
//    1300m: 우직선 30%   (우직선 중하단)                    ← 우직선 구간0
//    1400m: 우직선 50%   (우직선 중간)                      ← 우직선 구간0
//    1600m: 하단코너 50% (코너 센터, 화면 하단 중앙)         ← 하단코너 구간3
//    1700m: 좌직선 85%   (GOAL과 동일선상, 1바퀴)           ← 좌직선 구간2
//    1800m: 좌직선 67%   (좌직선 중하단)                    ← 좌직선 구간2
//    1900m: 좌직선 49%   (좌직선 중간)                      ← 좌직선 구간2
//    2000m: 좌직선 31%   (좌직선 중상단)                    ← 좌직선 구간2
//    2300m: 상단코너 57% (상단코너 중간)                    ← 상단코너 구간1
//
//  2단 트랙 구조:
//    - 내측 레인 (innerR): clusterOff < 0 → 안쪽
//    - 외측 레인 (outerR): clusterOff > 0 → 바깥쪽
// ──────────────────────────────────────────────────────────────────────────
class _TG {
  // 서울/부산경남 트랙 구간 거리(m) — CW 기준
  static const double dRight  = 400.0; // 우직선 (아래→위, CW 구간0)
  static const double dCornT  = 350.0; // 상단 반원 코너 (우→좌, CW 구간1)
  static const double dLeft   = 600.0; // 좌직선 (위→아래, GOAL+1700~1900m, CW 구간2)
  static const double dCornB  = 350.0; // 하단 반원 코너 (좌→우, 1600m 출발, CW 구간3)
  static const double total   = dRight + dCornT + dLeft + dCornB; // ≈1700m

  // 구간 진행률 경계 (CW 기준)
  static double get p2 => dRight / total;                          // 상단코너 시작 ≈0.2353
  static double get p3 => (dRight + dCornT) / total;               // 좌직선 시작  ≈0.4412
  static double get p4 => (dRight + dCornT + dLeft) / total;       // 하단코너 시작 ≈0.7941

  // ── GOAL 고정 위치 ──
  // 도면 기준: 좌직선 하단부 85% 지점 = 화면 좌측 하단, 하단코너 진입 전
  // CW 진행: p3(좌직선 시작=상단) → p4(좌직선 끝=하단)
  // GOAL = p3 + (p4-p3)*0.85 ≈ 0.4412 + 0.3529*0.85 ≈ 0.7412
  static double get goalP => p3 + (p4 - p3) * 0.85; // 좌직선 85% ≈ 화면 좌측 하단

  // ── 출발 진행률 (GOAL 역산, CW 기준) ──
  //  서울 경주거리: 1000, 1200, 1300, 1400, 1600, 1700, 1800, 1900, 2000, 2300m
  //  총 트랙 1700m 기준 각 위치 (goalP=0.7412 기준 역산):
  //    1000m: goalP - 1000/1700 ≈ 0.1529  → 우직선 65%  (특별 경주 전용)
  //    1200m: goalP - 1200/1700 ≈ 0.0353  → 우직선 15%
  //    1300m: goalP - 1300/1700 ≈ (0.9647+1.0)%1 ≈ 0.9647 → 우직선 가장 하단
  //    1400m: goalP - 1400/1700 ≈ 0.8882  → 우직선 중단~하단
  //    1600m: goalP - 1600/1700 ≈ 0.7647→반전→ 하단코너 약50%
  //    1700m: goalP - 1700/1700 = goalP   → 좌직선 85% (GOAL과 동일, 1바퀴)
  //    1800m: goalP - 1800/1700 ≈ 0.6824  → 좌직선 67%
  //    1900m: goalP - 1900/1700 ≈ 0.6235  → 좌직선 49%
  //    2000m: goalP - 2000/1700 ≈ 0.5647  → 좌직선 31%
  //    2300m: goalP - 2300/1700 ≈ 0.3882  → 상단코너 약57%
  static double startP(int distM) {
    final ratio = distM.clamp(1000, 2400) / total;
    return (goalP - ratio + 10.0) % 1.0;
  }

  // ──────────────────────────────────────────────────────────────────────
  //  진행률 → 트랙 상의 Offset (세로형 오벌 CW)
  //
  //  CW 시계방향 화면 좌표계 (y=아래가 +):
  //    구간0: 우직선 아래→위  (cx+hw, cy+hr) → (cx+hw, cy-hr)
  //    구간1: 상단코너 우→좌  중심(cx, cy-hr), ang: 0 → -π (위쪽 반원)
  //    구간2: 좌직선 위→아래  (cx-hw, cy-hr) → (cx-hw, cy+hr)  ← GOAL 구간
  //    구간3: 하단코너 좌→우  중심(cx, cy+hr), ang: π → 0 (아래쪽 반원)
  //
  //  clusterOff 방향 (트랙 안에 머물도록):
  //    우직선(아래→위): 안쪽=-x → safeOff 차감
  //    좌직선(위→아래): 안쪽=+x → safeOff 가산
  //    상단코너: 반지름 줄임 (hw-safeOff)
  //    하단코너: 반지름 줄임 (hw-safeOff)
  // ──────────────────────────────────────────────────────────────────────
  static Offset toPoint(double p, Rect tr, {double clusterOff = 0, bool isCW = false}) {
    final pp = p % 1.0;
    final cx = tr.center.dx;
    final cy = tr.center.dy;
    final hw = tr.width  * 0.42;  // 가로 반폭 (코너 반지름)
    final hr = tr.height * 0.44;  // 세로 반높이 (직선 절반)

    // ★ clusterOff 클램핑: hw*0.08 이내 (트랙 폭의 8% = 약 ±4px)
    final clamp = (hw * 0.08).clamp(0.0, 5.0);
    final safeOff = clusterOff.clamp(-clamp, clamp);

    Offset result;

    if (pp < p2) {
      // 구간0: 우직선 아래→위 (CW)
      // f=0: (cx+hw, cy+hr) 하단 → f=1: (cx+hw, cy-hr) 상단
      final f = pp / p2;
      result = Offset(cx + hw - safeOff, cy + hr - f * hr * 2);
    } else if (pp < p3) {
      // 구간1: 상단 반원 코너 CW (중심: cx, cy-hr)
      // 오른쪽(ang=0) → 위(ang=-π/2) → 왼쪽(ang=-π)
      // f=0: (cx+hw, cy-hr) → f=0.5: (cx, cy-hr-hw) 최상단 → f=1: (cx-hw, cy-hr)
      final f   = (pp - p2) / (p3 - p2);
      final ang = -(f * pi); // 0 → -π (CW: 위쪽 반원)
      final r = hw - safeOff;
      result = Offset(cx + cos(ang) * r, cy - hr + sin(ang) * r);
    } else if (pp < p4) {
      // 구간2: 좌직선 위→아래 (CW), GOAL 구간
      // f=0: (cx-hw, cy-hr) 상단 → f=1: (cx-hw, cy+hr) 하단
      final f = (pp - p3) / (p4 - p3);
      result = Offset(cx - hw + safeOff, cy - hr + f * hr * 2);
    } else {
      // 구간3: 하단 반원 코너 CW (중심: cx, cy+hr)
      // 왼쪽(ang=π) → 아래(ang=π/2) → 오른쪽(ang=0)
      // f=0: (cx-hw, cy+hr) → f=0.5: (cx, cy+hr+hw) 최하단 → f=1: (cx+hw, cy+hr)
      final f   = (pp - p4) / (1.0 - p4);
      final ang = pi - f * pi; // π → 0 (CW: 아래쪽 반원 좌→우)
      final r = hw - safeOff;
      result = Offset(cx + cos(ang) * r, cy + hr + sin(ang) * r);
    }

    return result;
  }

  // 진행률 → 진행 방향각 (라디안, CW)
  //
  //  CW 시계방향 접선각 (화면 좌표계 y=아래):
  //    구간0 우직선(아래→위): -π/2  (위쪽)
  //    구간1 상단코너 CW: ang=-(f*π) → 접선 = ang - π/2
  //      f=0: -π/2(위), f=0.5: -π(왼쪽), f=1: -3π/2(아래)
  //    구간2 좌직선(위→아래): π/2  (아래쪽)
  //    구간3 하단코너 CW: ang=π-f*π → 접선 = ang - π/2
  //      f=0: π/2(아래), f=0.5: 0(오른쪽), f=1: -π/2(위)
  static double toAngle(double p, {bool isCW = false}) {
    final pp = p % 1.0;
    if (pp < p2) {
      // 우직선 아래→위: 위방향 (-π/2)
      return -pi / 2;
    } else if (pp < p3) {
      // 상단코너 CW: ang=-(f*π), 접선 = ang - π/2
      final f = (pp - p2) / (p3 - p2);
      return -(f * pi) - pi / 2; // -π/2 → -3π/2
    } else if (pp < p4) {
      // 좌직선 위→아래: 아래방향 (π/2)
      return pi / 2;
    } else {
      // 하단코너 CW: ang=π-f*π, 접선 = ang - π/2
      final f = (pp - p4) / (1.0 - p4);
      return (pi - f * pi) - pi / 2; // π/2 → -π/2 (아래→오른→위)
    }
  }

  // 현재 구간 판별 (CW 기준)
  static _Seg segment(double p) {
    final pp = p % 1.0;
    if (pp < p2) return _Seg.topStr;    // 우직선 (아래→위)
    if (pp < p3) return _Seg.cornerL;   // 상단코너 (우→좌)
    if (pp < p4) return _Seg.botStr;    // 좌직선 (위→아래, GOAL구간)
    return _Seg.cornerR;                // 하단코너 (좌→우)
  }
}

enum _Seg { topStr, cornerR, botStr, cornerL }

// ──────────────────────────────────────────────────────────────────────────
//  부산경남 트랙 기하학 (_TGBusan) — 도면 실측 기반 2D 탑다운 평면 뷰 CW
//
//  [도면 실측치 기반 구간 거리]
//    - 구간0 우직선(백스트래치):   500m  (하→상, CW) ← 1000~1600m 출발선
//    - 구간1 상단코너:             257m  (우→좌, π×r, r≈81.7m)
//    - 구간2 좌직선(메인스트래치): 460m  (상→하, CW) ← GOAL 고정 + 1800~2200m
//    - 구간3 하단코너:             283m  (좌→우, π×r, r≈90m, 도면 504m 폭 기준)
//    - 총 1주 내측: ≈ 1500m (실제 경주 1주 1700m 기준으로 goalP 역산)
//
//  [2D 탑다운 평면 좌표계]
//    - 코너: 순수 반원(half-circle), 납작 타원 사용 안 함
//    - rx(가로반지름) = hw, ry(세로반지름) = hw (정원형 코너)
//    - 직선: 완벽히 수직 평행 (cx±hw, cy-hr ↔ cy+hr)
//
//  [2D 화면 배치]
//    구간0: 우직선  하→상  (cx+hw, cy+hr) → (cx+hw, cy-hr)
//    구간1: 상단코너 CW (중심: cx, cy-hr), 반원 0→-π
//    구간2: 좌직선  상→하  (cx-hw, cy-hr) → (cx-hw, cy+hr)  ← GOAL
//    구간3: 하단코너 CW (중심: cx, cy+hr), 반원 π→0
//
//  [레인 구조 - 도면 이중 트랙]
//    kLaneStd   (0):  내측 표준 레인 (1000~1700m)
//    kLaneInner (-1): 내측 하단코너 경유 (1800~2000m)
//    kLaneOuter (+1): 외측 하단코너 경유 (2200m, 도면 504m 대형 반원)
//
//  GOAL: 좌직선 하단 78% 지점 (p3 + (p4-p3)*0.78 ≈ 0.760)
// ──────────────────────────────────────────────────────────────────────────
class _TGBusan {
  // ── 도면 실측 기반 구간 거리(m) ──
  static const double dRight  = 500.0; // 우직선 (도면 우측 500m)
  static const double dCornT  = 257.0; // 상단 반원 코너 (π × 81.7m)
  static const double dLeft   = 460.0; // 좌직선 (도면 좌측 460m)
  static const double dCornB  = 283.0; // 하단 반원 코너 (π × 90m, 내측 기준)
  static const double total   = dRight + dCornT + dLeft + dCornB; // ≈ 1500m

  // ── 구간 경계 진행률 (CW 기준) ──
  static double get p2 => dRight / total;                           // ≈0.333
  static double get p3 => (dRight + dCornT) / total;               // ≈0.505
  static double get p4 => (dRight + dCornT + dLeft) / total;       // ≈0.811

  // ── 2D 탑다운 렌더 파라미터 ★ toPoint/_drawBusanTrack 완전 동기화 ──
  static const double kHwFrac = 0.36; // 코너 반지름 (tr.width 기준)
  static const double kHrFrac = 0.40; // 직선 반높이 비율 (tr.height 기준)
  // ★ 2D 탑다운: 코너는 정원형(rx=ry=hw), _busanOvalPath 내부에서 hw*2 그대로 사용

  // ── 레인 타입 상수 ──
  static const int kLaneStd   =  0; // 표준 내측 레인 (1000~1700m)
  static const int kLaneInner = -1; // 내측 하단코너 경유 (1800~2000m)
  static const int kLaneOuter =  1; // 외측 하단코너 경유 (2200m, 대형 반원)

  // ── GOAL: 좌직선 하단 78% 고정 ──
  // 도면 GOAL = 좌직선 하단부, GOAL 표지 위치
  // goalP = p3 + (p4-p3)*0.78
  static double get goalP => p3 + (p4 - p3) * 0.78;

  // ── 거리별 레인 타입 ──
  static int laneType(int distM) {
    if (distM >= 1800 && distM <= 2000) return kLaneInner;
    if (distM == 2200) return kLaneOuter;
    return kLaneStd;
  }

  // ── 거리별 실제 goalP 계산 ──
  // 우직선 출발 (1000~1700m): startP < goalP → goalP 그대로
  // 좌직선 출발 1800~2000m: startP > goalP → goalP + 1.0
  // 2200m: GOAL 한번 통과 후 → goalP + 1.0
  static double calcGoalP(int distM) {
    final sp = startP(distM);
    final gp = goalP;
    final lt = laneType(distM);
    if (lt == kLaneInner) return gp + 1.0;
    if (lt == kLaneOuter) return gp + 1.0;
    if (sp <= gp) return gp;
    return gp + 1.0;
  }

  // ── 출발 진행률 (도면 실측 기반 직접 매핑) ──
  //
  // [도면 기준 출발선 위치]
  // total ≈ 1500m, goalP ≈ 0.760
  // 우직선(구간0: 0~p2≈0.333): p클수록 하단(출발지점 낮음=짧은거리)
  //   1600m: 우직선 최하단  p=0.005 (하단코너 직후)
  //   1500m: 우직선 8%     p=0.027
  //   1400m: 우직선 18%    p=0.060
  //   1300m: 우직선 32%    p=0.107
  //   1200m: 우직선 50%    p=0.167
  //   1000m: 우직선 82%    p=0.273 (상단코너 근처)
  // 좌직선(구간2: p3≈0.505~p4≈0.811): p클수록 하단(GOAL쪽)
  //   1700m: GOAL 동일선   p=goalP=0.760
  //   1800m: 좌직선 58%    p=0.685
  //   1900m: 좌직선 47%    p=0.657
  //   2000m: 좌직선 36%    p=0.629
  //   2200m: 좌직선 12%    p=0.573
  static double startP(int distM) {
    switch (distM) {
      case 1600: return 0.005;
      case 1500: return 0.027;
      case 1400: return 0.060;
      case 1300: return 0.107;
      case 1200: return 0.167;
      case 1000: return 0.273;
      case 1700: return goalP;
      case 1800: return 0.685;
      case 1900: return 0.657;
      case 2000: return 0.629;
      case 2200: return 0.573;
      default:
        final ratio = distM.clamp(1000, 2400) / total;
        return (goalP - ratio + 10.0) % 1.0;
    }
  }

  // ── 진행률 → 트랙 Offset (2D 탑다운, 정원형 코너) ──
  //
  //  CW 시계방향 좌표:
  //    구간0: 우직선 하→상  (cx+hw, cy+hr) → (cx+hw, cy-hr)
  //    구간1: 상단 반원 CW  중심(cx, cy-hr), ang 0→-π
  //    구간2: 좌직선 상→하  (cx-hw, cy-hr) → (cx-hw, cy+hr)  ← GOAL
  //    구간3: 하단 반원 CW  중심(cx, cy+hr), ang π→0
  //
  //  clusterOff: 직선=x축 오프셋, 코너=반지름 조절
  static Offset toPoint(double p, Rect tr, {double clusterOff = 0}) {
    final pp = p % 1.0;
    final cx = tr.center.dx;
    final cy = tr.center.dy;
    final hw = tr.width  * kHwFrac; // 코너 반지름
    final hr = tr.height * kHrFrac; // 직선 반높이
    final cV  = (hw * 0.08).clamp(0.0, 6.0);
    final off = clusterOff.clamp(-cV, cV);

    if (pp < p2) {
      // 구간0: 우직선 하→상
      final f = pp / p2;
      return Offset(cx + hw - off, cy + hr - f * hr * 2);
    } else if (pp < p3) {
      // 구간1: 상단 반원 CW — 정원형(rx=ry=hw)
      final f = (pp - p2) / (p3 - p2);
      final a = -(f * pi); // 0 → -π (CW)
      final r = hw - off;
      return Offset(cx + r * cos(a), cy - hr + r * sin(a));
    } else if (pp < p4) {
      // 구간2: 좌직선 상→하
      final f = (pp - p3) / (p4 - p3);
      return Offset(cx - hw + off, cy - hr + f * hr * 2);
    } else {
      // 구간3: 하단 반원 CW — 정원형(rx=ry=hw)
      final f = (pp - p4) / (1.0 - p4);
      final a = pi - f * pi; // π → 0 (CW)
      final r = hw - off;
      return Offset(cx + r * cos(a), cy + hr + r * sin(a));
    }
  }

  // ── 진행률 → 접선 방향각 (2D 탑다운, 정원형 코너) ──
  static double toAngle(double p) {
    final pp = p % 1.0;
    if (pp < p2) {
      return -pi / 2; // 우직선: 위방향
    } else if (pp < p3) {
      // 상단 반원 CW 접선
      final f = (pp - p2) / (p3 - p2);
      final a = -(f * pi);
      return a - pi / 2; // CW 접선
    } else if (pp < p4) {
      return pi / 2;  // 좌직선: 아래방향
    } else {
      // 하단 반원 CW 접선
      final f = (pp - p4) / (1.0 - p4);
      final a = pi - f * pi;
      return a - pi / 2; // CW 접선
    }
  }

  // 현재 구간 판별
  static _Seg segment(double p) {
    final pp = p % 1.0;
    if (pp < p2) return _Seg.topStr;   // 우직선
    if (pp < p3) return _Seg.cornerL;  // 상단코너
    if (pp < p4) return _Seg.botStr;   // 좌직선
    return _Seg.cornerR;               // 하단코너
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  레이스 단계
// ──────────────────────────────────────────────────────────────────────────
enum _Phase {
  waiting,   // 스타트 전 (게이트 뷰)
  racing,    // 레이스 중
  finishing, // 결승선 통과 직후 (암전 진행)
  result,    // 결과 팝업
}

// ══════════════════════════════════════════════════════════════════════════
//  Grid Rail Engine (Round 9)
//  트랙을 세로(구간) × 가로(격자 레인) 바둑판으로 관리
//  Zone1(출발~코너): 16레인 → Zone2(코너): 8레인 → Zone3(400m~200m): 4레인
//  Zone4(200m~GOAL): 2레인 → 머리차 경합
// ══════════════════════════════════════════════════════════════════════════
class _GridRailEngine {
  // 구간별 최대 레인 수 (가로 격자)
  static const int kZone1Lanes = 16; // 출발~코너 입구
  static const int kZone2Lanes = 8;  // 코너 구간 (병목)
  static const int kZone3Lanes = 4;  // 400m~200m (추월 판단)
  static const int kZone4Lanes = 2;  // 200m~GOAL (머리차 경합)

  // 진행률(prog) 기준 구간 판별
  // isCW 파라미터 = isJeju로 대체 사용 (제주=true, 서울/부산경남=false)
  static int maxLanes(double prog, double goalP,
      {bool isCW = false, bool isBusan = false}) {
    final bool isJeju = isCW; // 호출 시 isCW: _isJeju 로 전달됨
    final double totalDist = isJeju
        ? _TGJeju.total
        : isBusan
            ? _TGBusan.total
            : _TG.total;
    final fromGoal = goalP - prog;
    if (fromGoal <= 200.0 / totalDist) { return kZone4Lanes; }
    if (fromGoal <= 400.0 / totalDist) { return kZone3Lanes; }
    // 코너 구간 판별
    final pp = prog % 1.0;
    final bool inCorner;
    if (isJeju) {
      inCorner = (pp >= _TGJeju.p2 && pp < _TGJeju.p3) ||
                 (pp >= _TGJeju.p4);
    } else if (isBusan) {
      // 부산경남: 상단코너(p2~p3) 또는 하단코너(p4~1.0)
      inCorner = (pp >= _TGBusan.p2 && pp < _TGBusan.p3) ||
                 (pp >= _TGBusan.p4);
    } else {
      inCorner = (pp >= _TG.p2 && pp < _TG.p3) ||
                 (pp >= _TG.p4);
    }
    if (inCorner) { return kZone2Lanes; }
    return kZone1Lanes;
  }

  // 격자 점유 맵: key = (segIdx * 100 + lane) 형태의 간이 해시
  // ★ prog % 1.0 을 먼저 적용하여 누적값(1.0 초과)도 올바르게 처리
  static int _segIdx(double prog) => ((prog % 1.0) * 50).floor(); // 0.02 단위

  // 점유 상태 체크: 앞 격자(프로그레스 높은 쪽)에 다른 말이 있는가?
  // ★ 출발 직후 모든 말이 같은 seg에 몰려 있을 때의 블록아웃 방지:
  //   prog 차이가 0.005(전체 트랙의 0.5%) 미만이면 「같은 격자」로 취급 안 함
  static bool isFrontBlocked(
      _Horse self, List<_Horse> horses, double goalP) {
    final selfPP   = self.prog % 1.0;
    final ahead    = _segIdx(selfPP) + 1;
    final lane     = self.gridLane;
    for (final h in horses) {
      if (identical(h, self) || h.finished) { continue; }
      // 실질 prog 차이가 너무 작으면 블록아웃 무시 (출발 몰림 방지)
      if ((h.prog - self.prog).abs() < 0.002) { continue; }
      if (_segIdx(h.prog) == ahead && h.gridLane == lane) { return true; }
    }
    return false;
  }

  // 좌우 격자 점유 여부
  static bool isSideBlocked(
      _Horse self, List<_Horse> horses, int deltaLane, int maxL) {
    final targetLane = self.gridLane + deltaLane;
    if (targetLane < 0 || targetLane >= maxL) { return true; } // 벽
    final seg = _segIdx(self.prog);
    for (final h in horses) {
      if (identical(h, self) || h.finished) { continue; }
      if ((h.prog - self.prog).abs() < 0.002) { continue; }
      if (_segIdx(h.prog) == seg && h.gridLane == targetLane) { return true; }
    }
    return false;
  }

  // 레인 압축: 레인 수가 줄어드는 구간 진입 시 gridLane 클램핑
  static void clampLane(_Horse h, int newMax) {
    h.gridLane = h.gridLane.clamp(0, newMax - 1);
  }

  // 진로 방해 해결: 전방 막힘 → 횡이동, 양옆 막힘 → 지체
  // 반환: speedMult 보정값 (0.7~1.0)
  static double resolveBlock(
      _Horse self, List<_Horse> horses, double goalP, Random rng,
      {bool isCW = false, bool isBusan = false}) {
    final maxL = maxLanes(self.prog, goalP, isCW: isCW, isBusan: isBusan);
    clampLane(self, maxL);

    if (!isFrontBlocked(self, horses, goalP)) {
      return 1.0; // 전방 개방 → 정상 주행
    }

    // 전방 막힘 → 횡이동 시도 (안쪽/바깥쪽 교대)
    final tryLeft  = !isSideBlocked(self, horses, -1, maxL);
    final tryRight = !isSideBlocked(self, horses,  1, maxL);

    if (tryLeft || tryRight) {
      // 여유가 있는 방향으로 이동 (랜덤 가중치 + 스피드가 높은 말은 바깥쪽 선호)
      if (tryLeft && tryRight) {
        self.gridLane += (rng.nextBool() ? -1 : 1);
      } else if (tryLeft) {
        self.gridLane -= 1;
      } else {
        self.gridLane += 1;
      }
      self.gridLane = self.gridLane.clamp(0, maxL - 1);
      return 0.88; // 횡이동 소폭 감속
    }

    // 양옆 모두 막힘 → 전진 지체
    return 0.65; // 심각한 감속
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  말 상태 (Round 9: gridLane, gridSegment 추가)
// ──────────────────────────────────────────────────────────────────────────
class _Horse {
  final HorseEntry entry;
  double prog;          // 트랙 진행률
  double speed;         // 현재 속도 (prog/s 단위)
  double baseSpeed;     // 기준 속도
  double clusterOff;    // 렌더링용 횡오프셋 (gridLane → 픽셀 변환)
  double targetClOff;   // 목표 오프셋

  // ── Round 9: 격자 필드 ──
  int gridLane    = 0;  // 가로 격자 위치 (0 ~ maxLanes-1)
  int gridSegment = 0;  // 세로 구간 인덱스 (진행률의 0.02 단위 양자화)
  double _stuckTimer = 0.0; // 지체 누적 시간

  // ── 부산경남 전용: 레인 타입 ──
  // _TGBusan.kLaneStd(0)=표준, kLaneInner(-1)=내측, kLaneOuter(+1)=외측
  int busanLane = 0;

  bool finished = false;
  int  rank     = 0;
  double? finishProg;

  // 애니
  double legPhase  = 0.0;
  double headBob   = 0.0;
  double headPhase = 0.0;

  // 이펙트
  bool   boostActive = false; // 2단계 부스터
  double boostGlow   = 0.0;  // 글로우 강도 0~1
  bool   spurtFading = false; // 3단계 스테미나 고갈

  // 스탯 캐시
  late double staminaNorm; // 0~1
  late double speedNorm;   // 0~1
  late double formNorm;    // 0~1
  late double userBonus;   // -5~+5  ← UserGValue
  late double g1fNorm;     // 0~1  후반 G1F 성적 (Zone4 가속도 버프 판정용)

  // ── Jockey Engine 버프/페널티 플래그 ──────────────────────────
  /// 안전주행 모드: 엘리트 기수 당일 2승+ → G1F 가속도 -10%, 코너 aggressiveness -30%
  bool safeMode   = false;
  /// 독기 모드: 엘리트 기수 3경기+ & 0승 → G1F 가속도 +15%
  bool mentalBuff = false;
  /// 고배당 서지 버프: HighOddsWindow 발동 시 배당 상위 3마번 → G1F 가속도 +20%
  bool surgeBuff  = false;

  _Horse({
    required this.entry,
    required this.prog,
    required this.baseSpeed,
    required int initLane,
  })  : speed      = baseSpeed * 0.25,
        clusterOff = 0,
        targetClOff = 0,
        gridLane    = initLane {
    staminaNorm = (entry.staminaStat / 100.0).clamp(0.0, 1.0);
    speedNorm   = (entry.speedStat   / 100.0).clamp(0.0, 1.0);
    formNorm    = (entry.formStat    / 100.0).clamp(0.0, 1.0);
    userBonus   = entry.userBonus;
    g1fNorm     = entry.g1fRating.clamp(0.0, 1.0);
    legPhase    = Random().nextDouble() * 2 * pi;
    headPhase   = Random().nextDouble() * 2 * pi;
    gridSegment = (prog * 50).floor();

    // ── Jockey Engine: 기수 상태 바인딩 ─────────────────────────
    final tracker = JockeyDailyTracker.instance;
    safeMode   = tracker.isSafeMode(entry.jockeyName, entry.jockeyRcWins);
    mentalBuff = tracker.isMentalBuff(entry.jockeyName, entry.jockeyRcWins);
    // surgeBuff는 _initHorses()에서 HighOddsWindowDetector 평가 후 주입
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  메인 위젯
// ══════════════════════════════════════════════════════════════════════════
class RaceAnimationScreen extends StatefulWidget {
  final RaceInfo race;
  final List<HorseEntry> horses;
  /// 시즌오프 체험 모드 여부 — 결과 화면에 DEMO 배너 표시
  final bool isDemoMode;
  /// 샌드박스 모드 여부 — 과거 경주 재현 시 결과를 Navigator.pop으로 반환
  final bool isSandbox;

  const RaceAnimationScreen({
    super.key,
    required this.race,
    required this.horses,
    this.isDemoMode = false,
    this.isSandbox  = false,
  });

  @override
  State<RaceAnimationScreen> createState() => _RaceAnimationScreenState();
}

class _RaceAnimationScreenState extends State<RaceAnimationScreen>
    with TickerProviderStateMixin {

  // ── 게임루프: dart:async Timer.periodic ──
  bool   _gameActive = false;
  Timer? _gameTimer;            // 게임루프 타이머 (dart:async Timer.periodic)

  // 렌더 트리거: ValueNotifier → AnimatedBuilder 즉시 리빌드
  final ValueNotifier<int> _renderTick = ValueNotifier<int>(0);

  // 애니메이션 컨트롤러
  late AnimationController _glowAnim;    // 부스터 글로우 펄스
  late AnimationController _zoomAnim;    // 미사용, dispose용 유지
  late AnimationController _fadeAnim;    // 결승 암전
  late AnimationController _gatePulse;  // 게이트뷰 펄스
  late AnimationController _gateAnim;   // ★ 게이트뷰 페이드아웃 (Timer 대체)

  // 컨디션바+게이트박스 공유 스크롤 컨트롤러 (동기화)
  late ScrollController _gateScrollCtrl;

  late List<_Horse>    _horses;
  final List<_Horse>   _ranking = [];
  _Phase _phase = _Phase.waiting;

  double _elapsed   = 0.0;
  int    _frameIdx  = 0;
  double _frameTmr  = 0.0;
  static const double _fps = 1 / 14.0; // 초당 14프레임 (0.071s 간격)
  DateTime? _lastTickTime; // ★ 실제 경과시간 측정용

  final Random _rng = Random(42);

  // ── 사용자 수동 보정 컨트롤러 ────────────────────────────────────────
  late UserCalibrationController _calibCtrl;
  // 마번별 개별 spurt 오프셋 (spurtTiming 드롭다운 반영)
  final Map<int, double> _horseSpurtOffset = {};

  // 레이스 파라미터
  late double _startP;
  late double _goalP;
  late double _baseSec;

  late double _boost400;
  late double _boost200;
  late double _spurt100;


  // 경주 방향 — 서울/부산경남: CW(시계방향), 제주: CCW(반시계방향)
  bool get _isCW    => !_isJeju; // 서울/부산경남은 CW
  bool get _isJeju  => widget.race.venueCode == '3'; // 제주 전용 트랙
  bool get _isBusan => widget.race.venueCode == '2'; // 부산경남 전용 트랙

  // 경마장명
  String get _venueName {
    switch (widget.race.venueCode) {
      case '1': return '서울';
      case '2': return '부산경남';
      case '3': return '제주';
      default:  return '서울';
    }
  }

  @override
  void initState() {
    super.initState();
    _calcParams();
    // ── UserCalibrationController 초기화 (마번 목록 기반) ────────────────
    final gateNos = widget.horses.isNotEmpty
        ? widget.horses.map((h) => h.gateNo).toList()
        : List.generate(10, (i) => i + 1);
    _calibCtrl = UserCalibrationController(gateNos: gateNos);
    _initHorses();

    _glowAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _zoomAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    ); // 실제 줌은 _onJsTick에서 직접 계산 (AnimationController throttle 회피)

    _fadeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _gatePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // ★ 게이트뷰 페이드아웃 컨트롤러 (1.0→0.0, 600ms)
    _gateAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1.0, // 초기값: 완전 불투명
    );

    // 컨디션바+게이트박스 공유 스크롤 컨트롤러
    _gateScrollCtrl = ScrollController();
  }

  void _calcParams() {
    if (_isJeju) {
      // 제주 전용 트랙 파라미터 (_TGJeju, total≈1400m, CCW)
      //
      // ★ 핵심 설계:
      //   _goalP = _TGJeju.goalP (고정 좌직선 85% ≈0.7497) — 절대 불변
      //   _startP = goalP - dist/total 역산 (말이 startP→goalP 달리면 정확히 dist이동)
      //   말의 h.prog는 startP에서 단조증가, h.prog >= _goalP 시 완주
      //
      // CCW 진행: 우직선(0~p2) → 하단코너(p2~p3) → 좌직선(p3~p4) → 상단코너(p4~1)
      //   GOAL = 좌직선 85% (p3~p4 구간 안)
      //
      // 가점부스터: 하단 우측 코너(p2) 진입 ~ 좌직선 진입(p3) 감속 구간
      //   _boost400 = p2 (하단코너 시작)
      //   _boost200 = p3 (하단코너 끝 = 좌직선 시작)
      // 파이널스퍼트: 좌직선 진입(p3) ~ GOAL
      //   _spurt100 = goalP - 150/total (GOAL 150m 전)
      _startP   = _TGJeju.startP(widget.race.distance);
      _goalP    = _TGJeju.goalP;   // ★ 항상 고정 GOAL 위치 (0.7497)
      _baseSec  = 30.0;
      // 가점부스터: 하단코너 진입(p2) ~ 좌직선 시작(p3)
      _boost400 = _TGJeju.p2;      // 하단코너 진입 시 부스터 ON
      _boost200 = _TGJeju.p3;      // 좌직선 진입 시 부스터 OFF
      // 파이널스퍼트: GOAL 150m 전 ~ GOAL
      _spurt100 = _goalP - 150.0 / _TGJeju.total; // GOAL 150m 전 스퍼트 ON
    } else if (_isBusan) {
      // 부산경남 전용 트랙 파라미터 (_TGBusan, total=1600m, CW)
      // startP: 도면 기반 직접 매핑
      // goalP: 거리별 실제 경로 기반 정확 계산 (1800~2200m는 1바퀴+α)
      _startP   = _TGBusan.startP(widget.race.distance);
      _goalP    = _TGBusan.calcGoalP(widget.race.distance);
      _baseSec  = 30.0;
      // ★ 부산경남 CW:
      //   구간0=우직선(↑), 구간1=상단코너(p2~p3), 구간2=좌직선(↓), 구간3=하단코너
      //   가점부스터: 상단 우측 코너 돌 때 (p2~p3) — goalP에서 역산
      //   파이널스퍼트: 상단 좌측 코너 돌아 좌직선 진입(p3)부터 GOAL까지
      // goalP 기준 역산: 상단코너 구간 길이 = p3-p2
      final cornTLen = _TGBusan.p3 - _TGBusan.p2; // 상단코너 구간 길이 (진행률)
      final leftLen  = _TGBusan.p4 - _TGBusan.p3; // 좌직선 구간 길이 (진행률)
      // GOAL에서 (좌직선 + 상단코너) 이전 = 부스터 시작 (p2 진입)
      _boost400 = _goalP - leftLen - cornTLen; // 상단코너 진입 (부스터 ON)
      _boost200 = _goalP - leftLen;            // 상단코너 끝 = 좌직선 시작 (부스터 OFF)
      // 스퍼트: 좌직선 진입(p3)부터 GOAL까지 = goalP - leftLen
      _spurt100 = _goalP - leftLen; // 좌직선 진입 = 파이널 스퍼트 시작
    } else {
      // 서울 트랙 파라미터 (_TG, total≈1700m, CW)
      _startP   = _TG.startP(widget.race.distance);
      _goalP    = _startP + widget.race.distance / _TG.total;
      _baseSec  = 30.0;
      // ★ 서울 CW:
      //   구간0=우직선(↑), 구간1=상단코너(p2~p3), 구간2=좌직선(↓), 구간3=하단코너
      //   가점부스터: 상단 우측 코너 돌 때 (p2~p3)
      //   파이널스퍼트: 상단 좌측 코너 돌아 좌직선 진입(p3)부터 GOAL까지
      final cornTLen = _TG.p3 - _TG.p2; // 상단코너 구간 길이
      final leftLen  = _TG.p4 - _TG.p3; // 좌직선 구간 길이
      _boost400 = _goalP - leftLen - cornTLen; // 상단코너 진입 (부스터 ON)
      _boost200 = _goalP - leftLen;            // 상단코너 끝 = 좌직선 시작 (부스터 OFF)
      _spurt100 = _goalP - leftLen;            // 좌직선 진입 = 파이널 스퍼트 시작
    }
  }

  void _initHorses() {
    final n = widget.horses.isEmpty ? 10 : widget.horses.length;

    // ── 더미 엔트리 생성 (실제 API 데이터 없을 때) ──────────────────────
    // 더미는 API 필드(rcWins, jockeyRcWins, wgBudam, g1fRating)를 포함
    final entries = widget.horses.isEmpty
        ? List.generate(n, (i) {
            final rcW     = 0.05 + _rng.nextDouble() * 0.35; // 5~40% 승률
            final jocW    = 0.05 + _rng.nextDouble() * 0.30; // 5~35% 기수 승률
            final wgB     = 52.0 + _rng.nextDouble() * 8.0;  // 52~60kg 부담중량
            final wgChg   = _rng.nextInt(7) - 3;             // -3~+3kg 체중변동
            final g1f     = 0.30 + _rng.nextDouble() * 0.60; // 0.30~0.90 G1F
            final cond    = widget.race.trackCondition;

            // ── baseSpeed 공식 (DTO와 동일 로직) ──
            final speedS  = (rcW * 0.5 * 100.0
                             + jocW * 0.3 * 100.0
                             + (60.0 - wgB) * 0.2).clamp(0.0, 100.0);

            // ── stamina 공식 ──
            final staminaS = (100.0
                              - wgChg.abs() * 1.5
                              - trackConditionPenalty(cond) * 100.0)
                             .clamp(20.0, 100.0);

            return HorseEntry(
              gateNo:       i + 1,
              horseName:    '${i + 1}번마',
              jockeyName:   '기수${i + 1}',
              trainerName:  '',
              weight:       440 + _rng.nextInt(40),
              weightChange: wgChg,
              rating:       60 + _rng.nextDouble() * 35,
              speedStat:    speedS,
              staminaStat:  staminaS,
              formStat:     40 + _rng.nextDouble() * 55,
              trackFitStat: 40 + _rng.nextDouble() * 55,
              baseScore:    50 + _rng.nextDouble() * 40,
              recentRecord: '',
              odds:         3 + _rng.nextDouble() * 25,
              // API 원시 파라미터
              horseRegNo:   'DUMMY${(i + 1).toString().padLeft(4, '0')}',
              rcWins:       rcW,
              jockeyRcWins: jocW,
              wgBudam:      wgB,
              g1fRating:    g1f,
            );
          })
        : widget.horses;

    // ── 출발 레인: gateNo → Zone1(16레인) 중 균등 배분 ─────────────────
    final totalEntries = entries.length;
    _horses = entries.asMap().entries.map((e) {
      final h = e.value;

      // ── baseSpeed 계산 ─────────────────────────────────────────────────
      // API 데이터 보유 여부에 따라 공식 적용
      final double speedS;
      final double staminaS;

      if (h.rcWins > 0.0 || h.jockeyRcWins > 0.0) {
        // ★ KRA API 기반 baseSpeed 공식
        //   rcWins(0~1)*50 + jockeyRcWins(0~1)*30 + (60-wgBudam)*0.2
        speedS  = (h.rcWins * 50.0
                   + h.jockeyRcWins * 30.0
                   + (60.0 - h.wgBudam) * 0.2).clamp(0.0, 100.0);

        // ★ KRA API 기반 stamina 공식
        //   100 - |weightChange|*1.5 - trackConditionPenalty*100
        staminaS = (100.0
                    - h.weightChange.abs() * 1.5
                    - trackConditionPenalty(widget.race.trackCondition) * 100.0)
                   .clamp(20.0, 100.0);
      } else {
        // API 데이터 없음 → 기존 스탯 그대로 사용
        speedS   = h.speedStat;
        staminaS = h.staminaStat;
      }

      // ── statAvg 기반 baseSpeed (prog/s 단위 정규화) ───────────────────
      // speedS(0~100) + staminaS(0~100) + formStat(0~100) → 0.0~1.0 평균
      final statAvg = (speedS + staminaS + h.formStat) / 300.0;
      // prog/s: 0.90~1.10 범위의 기준 속도
      final base = (1.0 / _baseSec) * (0.90 + statAvg * 0.20)
                   + (_rng.nextDouble() * 0.003 - 0.0015);

      // ── 출발 레인 배정 ────────────────────────────────────────────────
      final initLane = ((h.gateNo - 1) * (_GridRailEngine.kZone1Lanes - 1) ~/
                        (totalEntries > 1 ? totalEntries - 1 : 1))
                       .clamp(0, _GridRailEngine.kZone1Lanes - 1);

      // ── UserCalibration: oddsAdjFactor → baseSpeed 보정 ────────────────
      // userOddsWeight(±2.0) → baseSpeed ×= 0.97~1.03
      final calibratedBase = base * _calibCtrl.oddsAdjFactor(h.gateNo);

      // ── UserCalibration: spurtTiming → 개별 spurt 오프셋 캐싱 ───────────
      _horseSpurtOffset[h.gateNo] = _calibCtrl.spurtProgOffset(h.gateNo);

      final horse = _Horse(
        entry:     h,
        prog:      _startP,
        baseSpeed: calibratedBase,
        initLane:  initLane,
      );
      // 부산경남: 거리별 레인 타입 설정
      if (_isBusan) {
        horse.busanLane = _TGBusan.laneType(widget.race.distance);
      }
      return horse;
    }).toList();

    // ── Jockey Engine: HighOddsWindow 평가 & surgeBuff 주입 ───────────────
    // 안전주행 기수 비율 50%+ 이면 고배당 상위 3마번에 surgeBuff = true
    final detector = HighOddsWindowDetector.instance;
    detector.evaluate(entries, int.tryParse(widget.race.raceNo) ?? 1);
    if (detector.isActive) {
      for (final h in _horses) {
        if (detector.isSurgeBuff(h.entry.gateNo)) {
          h.surgeBuff = true;
        }
      }
    }
  }

  // ── 게임루프: dart:async Timer.periodic (16ms ≈ 60fps) ──
  void _startGameTimer() {
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _onTick());
  }

  void _onTick() {
    if (!_gameActive || _phase != _Phase.racing) return;

    try {
    // ★ 실제 경과시간(DateTime) 기반 dt → 고정 16ms 대신 실측값 사용
    final now = DateTime.now();
    final double realDt;
    if (_lastTickTime == null) {
      realDt = 0.016; // 첫 tick은 기본값
    } else {
      final dtMs = now.difference(_lastTickTime!).inMicroseconds / 1000.0;
      // 최소 8ms, 최대 50ms로 클램핑 (이상값 방어)
      realDt = (dtMs / 1000.0).clamp(0.008, 0.050);
    }
    _lastTickTime = now;

    _elapsed += realDt;

    _frameTmr += realDt;
    if (_frameTmr > _fps) {
      _frameTmr -= _fps;
      _frameIdx = (_frameIdx + 1) % 4;
    }

    bool anyRunning = false;

    for (final h in _horses) {
      if (h.finished) { continue; }
      anyRunning = true;

      final p   = h.prog;
      final seg = _isJeju  ? _TGJeju.segment(p % 1.0)
                  : _isBusan ? _TGBusan.segment(p % 1.0)
                  : _TG.segment(p % 1.0);

      // ── Zone 판별 ──────────────────────────────────────────────────────
      final bool inCorner  = (seg == _Seg.cornerR || seg == _Seg.cornerL);
      // ★ 부스터: 코너 진입(_boost400) ~ 직선 진입(_boost200) 구간
      //   제주 CCW: 하단코너(p2) ~ 좌직선(p3)  [감속 + 병목]
      //   서울/부산 CW: 상단코너(p2) ~ 좌직선(p3)
      // ★ 스퍼트: GOAL 150m 전(_spurt100) ~ GOAL
      //   제주: 좌직선 중반(goalP-150/total) ~ goalP
      //   서울/부산: 좌직선 진입(p3) ~ goalP
      final bool inBoost   = (p >= _boost400 && p < _boost200);
      final bool inSpurt   = (p >= _spurt100 && p < _goalP);
      final int  curMaxL   = _GridRailEngine.maxLanes(p, _goalP,
          isCW: _isJeju, isBusan: _isBusan);

      // ── Zone 레인 압축: 진입 시 clamp ──────────────────────────────────
      _GridRailEngine.clampLane(h, curMaxL);

      // ── GridRailEngine: 진로 방해 해결 → speedMult 보정 ───────────────
      double blockMult = _GridRailEngine.resolveBlock(h, _horses, _goalP, _rng,
          isCW: _isJeju, isBusan: _isBusan);

      // ── 1단계: Zone별 기본 속도 조정 ──────────────────────────────────
      double speedMult = blockMult;

      if (inCorner) {
        // ── Zone2(코너): 8→4 격자 압축 구간 ──────────────────────────────
        // ① 기본 감속 + 레인 외측 미세 변동
        double laneF = curMaxL > 1 ? h.gridLane / (curMaxL - 1.0) : 0.5;

        // ★ safeMode(안전주행): aggressiveness -30% → 외측 레인 강제 보정
        // 인코스 공격 성향을 줄여 외곽으로 안전하게 돌도록 laneF를 외측으로 이동
        if (h.safeMode) {
          // laneF를 외측 방향(1.0)으로 30% 보정: 공격적 인코스 파고들기 억제
          laneF = (laneF + kAggressivenessReduction * (1.0 - laneF))
                  .clamp(0.0, 1.0);
        }

        speedMult *= 0.84 + laneF * 0.04 + _rng.nextDouble() * 0.04;

        // ② ★ trackCondition 페널티 — 코너 압축(8→4레인) 시 주로상태 저항 적용
        //    computeCornerTrackPenalty: 양호=1.0, 불량=~0.88, 매우불량=~0.82
        //    외측 레인(laneF≈1)은 코너 반경 증가로 추가 페널티 ×1.3 적용
        final trackMult = computeCornerTrackPenalty(
          widget.race.trackCondition,
          laneF,
        );
        speedMult *= trackMult;

        // ③ 코너 clusterOff: 트랙 너비 안에 머물도록 스케일 대폭 축소
        // safeMode: 보정된 laneF 기준으로 외곽 렌더링 좌표 산출
        h.targetClOff = (h.gridLane - curMaxL / 2.0) * 0.4
            + (h.safeMode ? laneF * 0.3 : 0.0);
      } else {
        // ★ 직선 clusterOff: 레인 간격 축소 (이전 1.8~3.5 → 0.5~0.8)
        h.targetClOff = (h.gridLane - curMaxL / 2.0) *
            (curMaxL > 4 ? 0.5 : curMaxL > 2 ? 0.6 : 0.8);
      }

      // ── 2단계: Zone3(400m~200m) 부스터 ────────────────────────────────
      if (inBoost) {
        final bf   = ((p - _boost400) / (_boost200 - _boost400)).clamp(0.0, 1.0);
        // ★ userBonus = UserGValue 실시간 합산 (-5~+5 → -1~+1 정규화)
        final user = (h.userBonus / 5.0).clamp(-1.0, 1.0);
        final stat = (h.speedNorm + h.formNorm) * 0.5;
        speedMult  *= 1.12 + bf * 0.15 * stat + bf * 0.08 * user;
        h.boostActive = true;
        h.boostGlow   = (_glowAnim.value * 0.6 + bf * 0.4).clamp(0, 1);
      } else if (!inCorner) {
        h.boostActive = false;
        h.boostGlow   = (h.boostGlow * 0.85).clamp(0, 1);
      }

      // ── 3단계: Zone4(스퍼트 100m~GOAL) 스테미나 소진 ──────────────────
      if (inSpurt) {
        final sf   = ((p - _spurt100) / (_goalP - _spurt100)).clamp(0.0, 1.0);
        final stam = h.staminaNorm;
        final user = (h.userBonus / 5.0).clamp(-1.0, 1.0);
        final fade = (1.0 - stam) * sf * 0.22;
        final boost = stam * sf * 0.08 + user * sf * 0.06;
        speedMult *= (1.0 - fade + boost).clamp(0.6, 1.18);
        h.spurtFading = (stam < 0.5);
      }

      // ── Zone4 후반 400m~GOAL: G1F 우수마 가속도 +25% 버프 ─────────────
      // inBoost = _boost400 ~ _boost200 (400m~200m 직선 부스터 구간과 동일)
      // 스펙: 후반 400m 직선 주로 격자 2레인 압축 구역 = _boost400 ~ _goalP
      final inZone4Straight = (p >= _boost400); // 400m~GOAL 전체 구간
      if (inZone4Straight) {
        // ★ G1F 우수마 가속도 버프 적용
        // computeG1fBoostMult: g1fNorm >= 0.65면 구간 진행도 비례로 최대 +25%
        final zoneFactor =
            ((p - _boost400) / (_goalP - _boost400)).clamp(0.0, 1.0);
        final g1fMult = computeG1fBoostMult(h.g1fNorm, zoneFactor);
        speedMult *= g1fMult;
        // 우수마 글로우 이펙트 유지 (boostGlow 이미 설정 → 추가 강화만)
        if (g1fMult > 1.0 && !h.boostActive) {
          h.boostGlow = (h.boostGlow + (g1fMult - 1.0) * 0.5).clamp(0, 1);
        }

        // ── Jockey Engine: P_final 동적 바인딩 ─────────────────────────
        final tracker    = JockeyDailyTracker.instance;
        // raceNo: String → int (파싱 실패 시 1번 경주로 폴백)
        final raceNoInt  = int.tryParse(widget.race.raceNo) ?? 1;
        final afScale    = tracker.afternoonScale(raceNoInt);

        // [1] 안전주행 패널티: 엘리트 기수 2승+ → maxAccel -10% × 오후배율
        if (h.safeMode) {
          speedMult *= (1.0 - kSafeModeAccelPenalty * afScale);
        }

        // [2] 독기 모드 가점: 엘리트 기수 3경기+ & 0승 → A_zone +15% × 오후배율
        if (h.mentalBuff) {
          speedMult *= (1.0 + kMentalBuffBonus * afScale);
          // 독기 모드 글로우 이펙트
          if (!h.boostActive) {
            h.boostGlow = (h.boostGlow + kMentalBuffBonus * afScale * 0.6)
                          .clamp(0, 1);
          }
        }

        // [3] 고배당 서지 버프: HighOddsWindow 발동 상위 3마번 → A_zone +20% × 오후배율
        if (h.surgeBuff) {
          final detector = HighOddsWindowDetector.instance;
          speedMult *= detector.surgeMultiplier(raceNoInt);
          // 서지 버프 글로우 이펙트
          if (!h.boostActive) {
            h.boostGlow = (h.boostGlow + kSurgeBuffBonus * afScale * 0.8)
                          .clamp(0, 1);
          }
        }

        // [4] UserCalibration: 기수 멘탈 슬라이더 → speedMultOverride
        //     userJockeyBuff(±1.0) → speedMult ×= 1.0 ± 0.12×afScale
        final userMultOverride =
            _calibCtrl.speedMultOverride(h.entry.gateNo, afScale);
        if (userMultOverride != 1.0) {
          speedMult *= userMultOverride;
          if (userMultOverride > 1.0 && !h.boostActive) {
            h.boostGlow = (h.boostGlow + (userMultOverride - 1.0) * 0.5)
                          .clamp(0, 1);
          }
        }
      }

      // ── 지체 누적 (양옆 모두 막힌 경우 stuckTimer 증가) ──────────────
      if (blockMult < 0.7) {
        h._stuckTimer += realDt;
        if (h._stuckTimer > 2.0) {
          // 2초 이상 막히면 강제 돌파 시도 (바깥쪽 강제 이동)
          h.gridLane = (h.gridLane + 1).clamp(0, curMaxL - 1);
          h._stuckTimer = 0.0;
        }
      } else {
        h._stuckTimer = (h._stuckTimer - realDt * 0.5).clamp(0, 5.0);
      }

      // ── 격자 세그먼트 업데이트 ────────────────────────────────────────
      h.gridSegment = (h.prog * 50).floor();

      // ── 오프셋 스무딩 + 애니 ──────────────────────────────────────────
      h.clusterOff += (h.targetClOff - h.clusterOff) * 0.12;

      // ── Ticker 기반 realDt는 초 단위 → speed도 prog/s 단위로 통일 ──
      // baseSpeed = 1/baseSec (prog/s), realDt = 초
      // 애니 페이즈는 speed*realDt 비례로 진행
      h.legPhase  += realDt * 14.0 * (h.speed * _baseSec);
      h.headPhase += realDt * 11.0 * (h.speed * _baseSec);
      h.headBob    = sin(h.headPhase) * 1.6;

      final noise = (_rng.nextDouble() - 0.5) * 0.00002;
      h.speed = h.baseSpeed * speedMult + noise;
      // 모든 경주: prog 증가 (서울/부산경남 CW 포함)
      h.prog += h.speed * realDt;

      // 완주 조건: prog >= _goalP (통일)
      final bool crossed = (h.prog >= _goalP);
      if (crossed && !h.finished) {
        h.finished   = true;
        h.finishProg = h.prog;
        final rank   = _ranking.length + 1;
        h.rank       = rank;
        _ranking.add(h);

        if (_ranking.length >= _horses.length || rank == 1) {
          if (rank == 1) { _onFirstFinish(); }
        }
        if (_ranking.length >= _horses.length) {
          _doFinish();
          return;
        }
      }
    }

    if (!anyRunning && _phase == _Phase.racing) {
      _doFinish();
      return;
    }
    // ValueNotifier.value++ → AnimatedBuilder 즉시 리빌드 → CustomPaint 재렌더
    if (mounted) _renderTick.value++;

    } catch (e, st) {
      // 게임루프 내 예외: 루프만 중단, 화면은 유지 (Navigator.pop 하지 않음)
      _gameActive = false;
      _gameTimer?.cancel();
      _gameTimer = null;
      // 개발용 로그 (release 빌드에서는 무시됨)
      assert(() { debugPrint('[_onTick] 예외: $e\n$st'); return true; }());
    }
  }

  // 레이스 경과 시간 (결과 팝업 표시용)
  double _raceElapsed = 0.0;

  void _onFirstFinish() {
    _raceElapsed = _elapsed;
  }

  bool _finishCalled = false; // _doFinish 중복 호출 방지

  void _doFinish() {
    if (_finishCalled) return; // 중복 호출 방지
    _finishCalled = true;

    _gameActive = false;
    _gameTimer?.cancel();
    _gameTimer = null;

    final sorted = [..._horses]..sort((a, b) => b.prog.compareTo(a.prog));
    for (final h in sorted) {
      if (!h.finished) {
        h.finished = true;
        h.rank     = _ranking.length + 1;
        _ranking.add(h);
      }
    }
    if (_raceElapsed == 0.0) _raceElapsed = _elapsed;

    // ── Jockey Engine: 경주 완료 후 기수 성적 기록 ──────────────────────
    // 1착 확정 시 JockeyDailyTracker에 당일 성적 누적
    // safeMode/mentalBuff 상태 갱신 → 다음 경주부터 반영
    final tracker = JockeyDailyTracker.instance;
    for (final h in _ranking) {
      tracker.recordFinish(
        jockeyName:    h.entry.jockeyName,
        jockeyRcWins:  h.entry.jockeyRcWins,
        won:           (h.rank == 1),
      );
    }
    // HighOddsWindow 상태 초기화 (다음 경주 재평가를 위해)
    HighOddsWindowDetector.instance.reset();

    // ── UserCalibration: 경주 종료 후 패널 해제 ──────────────────────────
    // 잠금 해제 → 결과 화면에서 다음 경주 보정 준비 가능
    _calibCtrl.unlockPanel();

    // ★ setState 로 _phase 전환 → UI 즉시 갱신
    if (!mounted) return;

    // 샌드박스 모드: 결과를 RaceResult 리스트로 변환하여 Navigator.pop 반환
    if (widget.isSandbox) {
      final results = _ranking.map((h) => RaceResult(
        rank:       h.rank,
        gateNo:     h.entry.gateNo,
        horseName:  h.entry.horseName,
        jockeyName: h.entry.jockeyName,
        finalScore: h.entry.finalScore,
      )).toList();
      // 결과 화면 잠깐 표시 후 반환
      setState(() => _phase = _Phase.finishing);
      _fadeAnim.reset();
      _fadeAnim.forward().then((_) {
        if (mounted) {
          setState(() => _phase = _Phase.result);
          // 3초 후 자동 반환
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) Navigator.pop(context, results);
          });
        }
      });
      return;
    }

    setState(() => _phase = _Phase.finishing);

    _fadeAnim.reset();
    _fadeAnim.forward().then((_) {
      if (mounted) setState(() => _phase = _Phase.result);
    });
  }

  void _startRace() {
    if (_phase != _Phase.waiting) return;
    if (_gameActive) return; // 중복 방지

    // ★ 게이트뷰를 즉시 숨기고(opacity=0) 레이스 시작
    // AnimationController로 600ms 페이드아웃 → Timer 중복 실행 완전 제거
    _gateAnim.animateTo(0.0).then((_) {
      // 페이드아웃 완료 후 게이트뷰 Widget 자체를 트리에서 제거 (성능)
      if (mounted) setState(() {});
    });

    // ★ phase와 gameActive를 setState 안에서 원자적으로 변경
    setState(() {
      _gameActive = true;
      _phase = _Phase.racing;
      _lastTickTime = null; // dt 초기화
    });

    // 게임루프 시작 (dart:async Timer.periodic)
    _startGameTimer();
  }

  @override
  void dispose() {
    _gameActive = false;
    _gameTimer?.cancel();
    _gameTimer = null;
    _renderTick.dispose();
    _glowAnim.dispose();
    _zoomAnim.dispose();
    _fadeAnim.dispose();
    _gatePulse.dispose();
    _gateAnim.dispose();
    _gateScrollCtrl.dispose(); // 공유 스크롤 컨트롤러
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────────────
  //  빌드
  // ────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand, // ★ Stack 자체가 화면 전체를 채우도록 강제
          children: [
            // ── 레이스 트랙 캔버스 (항상 전체화면) ──
            Positioned.fill(
              child: AnimatedBuilder(
                animation: Listenable.merge([_glowAnim, _renderTick]),
                builder: (_, __) => CustomPaint(
                  size: size, // ★ 명시적 size 전달 → paint() 에서 정확한 크기 사용
                  painter: _RacePainter(
                    horses:    _horses,
                    distance:  widget.race.distance,
                    raceNo:    widget.race.raceNo,
                    venueCode: widget.race.venueCode,
                    venueName: _venueName,
                    startP:    _startP,
                    goalP:     _goalP,
                    boost400:  _boost400,
                    boost200:  _boost200,
                    spurt100:  _spurt100,
                    frameIdx:  _frameIdx,
                    glowVal:   _glowAnim.value,
                    gatePulse: 0.0,
                    ranking:   _ranking,
                    isJeju:    _isJeju,
                    isBusan:   _isBusan,
                    isCW:      _isCW,
                  ),
                ),
              ),
            ),

            // ── 게이트뷰 Flutter 위젯 오버레이 (가로 스크롤 지원) ──
            // _gateAnim: 1.0(대기)→0.0(페이드아웃완료)
            AnimatedBuilder(
              animation: _gateAnim,
              builder: (_, __) {
                final op = _gateAnim.value;
                if (op <= 0.01) return const SizedBox.shrink();
                return Positioned.fill(
                  child: Opacity(
                    opacity: op,
                    child: _buildFlutterGateOverlay(size),
                  ),
                );
              },
            ),

            // ── 암전 오버레이 (전체화면) ──
            if (_phase == _Phase.finishing)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _fadeAnim,
                  builder: (_, __) => ColoredBox(
                    color: Colors.black.withValues(alpha: _fadeAnim.value * 0.92),
                  ),
                ),
              ),

            // ── 상단 HUD + 이벤트 배너 ──
            AnimatedBuilder(
              animation: _renderTick,
              builder: (_, __) => Stack(
                children: [
                  _buildHUD(size),
                  if (_phase == _Phase.racing) _buildEventBanner(),
                ],
              ),
            ),

            // ── 스타트 버튼 ──
            if (_phase == _Phase.waiting) _buildStartButton(size),

            // ── 결과 팝업 ──
            if (_phase == _Phase.result) _buildResult(size),
          ],
        ),
      ),
    );
  }

  // ── HUD ──
  Widget _buildHUD(Size size) {
    final showTime = (_phase == _Phase.racing || _phase == _Phase.finishing);
    // ★ 타이머 표시: 정수 초 단위 (예: 01:23) — 소수점 제거로 "초 이하 단위" 오해 방지
    final totalSec = _elapsed.floor();
    final mins = (totalSec ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSec % 60).toString().padLeft(2, '0');

    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 4,
          left: 12, right: 12, bottom: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.chevron_left, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_venueName 제${widget.race.raceNo}경주  AI 시뮬레이션',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${widget.race.distance}m · ${_horses.length}두 출전 · ${_isJeju ? '반시계(CCW)' : '시계(CW)'}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                  ),
                ],
              ),
            ),
            if (showTime)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2A3A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF3A5A7A)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('TIME', style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 8, letterSpacing: 1.5,
                    )),
                    Text('$mins:$secs', style: const TextStyle(
                      color: Color(0xFFFFD700), fontSize: 17,
                      fontWeight: FontWeight.bold, fontFamily: 'monospace',
                    )),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 이벤트 배너 (코너진입/병목 메시지 삭제, 스퍼트/부스터만 유지) ──
  Widget _buildEventBanner() {
    final inBoost = _horses.any((h) => h.boostActive);
    final inSpurt = _horses.any((h) => h.prog > _spurt100);

    String? msg;
    Color?  col;
    if (inSpurt)      { msg = '⚡  파이널 스퍼트  ⚡';  col = Colors.redAccent; }
    else if (inBoost) { msg = '🚀  가점 부스터 발동!'; col = const Color(0xFFFFD700); }
    // 코너진입-병목발생 매시지 삭제 (사용자 요청)

    if (msg == null) return const SizedBox.shrink();

    return Positioned(
      bottom: 80, left: 0, right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _glowAnim,
          builder: (_, __) => Opacity(
            opacity: 0.55 + _glowAnim.value * 0.45,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: col!, width: 1.5),
              ),
              child: Text(msg!, style: TextStyle(
                color: col,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              )),
            ),
          ),
        ),
      ),
    );
  }

  // ── Flutter 게이트뷰 오버레이 (가로 스크롤 지원 — Canvas 대체) ──
  Widget _buildFlutterGateOverlay(Size size) {
    final horses = _horses;
    final n = horses.length;
    if (n == 0) return const SizedBox.shrink();

    // ── 표시 순서 계산 (중복 없이, gateNo 기준 정렬된 리스트 직접 사용) ──
    // 서울/부산경남: 오른쪽=1번 → 왼쪽부터 n번,n-1번,...1번
    // 제주: 왼쪽=1번 → 왼쪽부터 1번,2번,...n번
    final List<_Horse> ordered;
    if (_isJeju) {
      ordered = List.from(horses)
        ..sort((a, b) => a.entry.gateNo.compareTo(b.entry.gateNo));
    } else {
      ordered = List.from(horses)
        ..sort((a, b) => b.entry.gateNo.compareTo(a.entry.gateNo));
    }

    // 박스 너비: 말이 많을수록 좁게, 최소 52px 보장 (스크롤로 처리)
    final double boxW = n > 14
        ? 52.0
        : n > 10
            ? 56.0
            : 62.0;

    const double condH = 92.0;   // 컨디션바 영역 높이
    const double gateH = 148.0;  // 게이트박스 영역 높이
    final double panelTop =
        size.height * 0.11 + size.height * 0.40 + size.height * 0.010;
    final double totalPanelH = condH + gateH + 14; // 14 = 구분선+발판

    return Stack(
      fit: StackFit.expand,
      children: [
        // ① 배경
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF050D1A), Color(0xFF0A1628), Color(0xFF071220)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),

        // ② 상단 배너 (Canvas — 시나리오 정보 유지)
        Positioned(
          top: size.height * 0.11,
          left: 0, right: 0,
          height: size.height * 0.40,
          child: CustomPaint(
            painter: _BannerOnlyPainter(
              horses:    horses,
              distance:  widget.race.distance,
              raceNo:    widget.race.raceNo,
              venueCode: widget.race.venueCode,
              venueName: _venueName,
              isJeju:    _isJeju,
              isBusan:   _isBusan,
            ),
          ),
        ),

        // ③ 기수 컨디션바 + 게이트박스 — 단일 ScrollController 공유 (동기 스크롤)
        Positioned(
          top: panelTop,
          left: 0, right: 0,
          height: totalPanelH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 섹션 헤더
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 3),
                child: Row(
                  children: [
                    const Text('🏇 기수 컨디션',
                      style: TextStyle(
                        color: Color(0xFFFFD700), fontSize: 10,
                        fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Text('← 스크롤',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 8)),
                  ],
                ),
              ),

              // ── 컨디션바 (공유 스크롤 컨트롤러) ──
              SizedBox(
                height: condH - 18, // 헤더 높이 제외
                child: SingleChildScrollView(
                  controller: _gateScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const SizedBox(width: 8),
                      ...ordered.map((horse) => _buildCondBar(horse, boxW)),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),

              // 구분선 (게이트 헤더 프레임)
              Container(height: 6, color: const Color(0xFF4A3A20)),

              // ── 게이트박스 (동일 ScrollController → 동기 스크롤) ──
              Expanded(
                child: _GateSyncScrollView(
                  linkedController: _gateScrollCtrl,
                  boxW: boxW,
                  ordered: ordered,
                  buildGateBox: _buildGateBox,
                ),
              ),

              // 하단 발판
              Container(height: 8, color: const Color(0xFF4A3A20)),
            ],
          ),
        ),

        // ④ 경주 방향 바 (하단 고정)
        Positioned(
          bottom: 80, left: 0, right: 0,
          child: _buildDirectionWidget(size),
        ),
      ],
    );
  }

  // 단일 컨디션 바 위젯
  Widget _buildCondBar(_Horse horse, double boxW) {
    final cd = HorseCapColors.getCapData(horse.entry.gateNo);
    final condF = (horse.entry.formStat / 100.0).clamp(0.0, 1.0);
    final condColor = condF > 0.75
        ? const Color(0xFF4CAF50)
        : condF > 0.5
            ? const Color(0xFFFFD700)
            : const Color(0xFFFF5722);
    final grade = condF > 0.8 ? '최상'
        : condF > 0.6 ? '양호'
        : condF > 0.4 ? '보통'
        : '주의';

    const double barMaxH = 38.0;
    final fillH = barMaxH * condF;

    return SizedBox(
      width: boxW,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 등급 텍스트
          Text(grade,
            style: TextStyle(color: condColor, fontSize: 8, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          // 세로 바
          Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // 배경
              Container(
                width: 10, height: barMaxH,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // 채우기
              Container(
                width: 10, height: fillH.clamp(2.0, barMaxH),
                decoration: BoxDecoration(
                  color: condColor.withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 마번 원 배지
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(shape: BoxShape.circle, color: cd.bg),
            alignment: Alignment.center,
            child: Text(
              '${horse.entry.gateNo}',
              style: TextStyle(
                color: cd.text, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // 단일 게이트 박스 위젯
  Widget _buildGateBox(_Horse horse, double boxW) {
    final cd = HorseCapColors.getCapData(horse.entry.gateNo);
    final nameStr = horse.entry.horseName.length > 5
        ? horse.entry.horseName.substring(0, 5)
        : horse.entry.horseName;
    final jockeyStr = horse.entry.jockeyName.length > 4
        ? horse.entry.jockeyName.substring(0, 4)
        : horse.entry.jockeyName;

    return Container(
      width: boxW,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cd.bg.withValues(alpha: 0.95),
            Color.lerp(cd.bg, Colors.black, 0.35)!,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 마번
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.30),
            ),
            alignment: Alignment.center,
            child: Text(
              '${horse.entry.gateNo}',
              style: TextStyle(
                color: cd.text,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 기수 저지 원
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(shape: BoxShape.circle, color: cd.bg,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.55), width: 1.2)),
            alignment: Alignment.center,
            child: Text('J',
              style: TextStyle(color: cd.text, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          // 말이름
          Text(
            nameStr,
            style: const TextStyle(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          // 기수이름
          if (horse.entry.jockeyName.isNotEmpty)
            Text(
              jockeyStr,
              style: TextStyle(
                color: cd.text.withValues(alpha: 0.85), fontSize: 8),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  // 경주 방향 안내 위젯
  Widget _buildDirectionWidget(Size size) {
    final n = _horses.length;
    return Container(
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1628).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A4A6A).withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.swap_horiz, color: Color(0xFFFFD700), size: 14),
          const SizedBox(width: 6),
          Text(
            _isJeju
                ? '좌측 → $n번    경주 방향 CCW    우측 → 1번'
                : '좌측 → $n번    경주 방향 CW     우측 → 1번',
            style: const TextStyle(color: Color(0xFFFFD700), fontSize: 10),
          ),
        ],
      ),
    );
  }

  // ── 스타트 버튼 ──
  Widget _buildStartButton(Size size) {
    return Positioned(
      bottom: 28, left: 20, right: 20,
      child: GestureDetector(
        onTap: _startRace,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFAA00)]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
              color: const Color(0xFFFFD700).withValues(alpha: 0.4),
              blurRadius: 18, spreadRadius: 2,
            )],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('🏁', style: TextStyle(fontSize: 20)),
              SizedBox(width: 10),
              Text('AI 모의 레이스  START', style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ── 결과 전광판 팝업 (완전 개편) ──
  Widget _buildResult(Size size) {
    return _RaceResultBoard(
      ranking: _ranking,
      raceTime: _raceElapsed,
      race: widget.race,
      venueName: _venueName,
      isDemoMode: widget.isDemoMode,
      onHome: () => Navigator.pop(context),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  레이스 페인터 (단일레인 탑다운)
// ══════════════════════════════════════════════════════════════════════════
class _RacePainter extends CustomPainter {
  final List<_Horse> horses;
  final int          distance;
  final String       raceNo;
  final String       venueCode;
  final String       venueName;
  final double       startP, goalP, boost400, boost200, spurt100;
  final int          frameIdx;
  final double       glowVal, gatePulse;
  final List<_Horse> ranking;
  final bool         isJeju;  // 제주 전용 트랙
  final bool         isBusan; // 부산경남 전용 트랙
  final bool         isCW;    // 항상 false (CCW)

  _RacePainter({
    required this.horses,
    required this.distance,
    required this.raceNo,
    required this.venueCode,
    required this.venueName,
    required this.startP,
    required this.goalP,
    required this.boost400,
    required this.boost200,
    required this.spurt100,
    required this.frameIdx,
    required this.glowVal,
    required this.gatePulse,
    required this.ranking,
    required this.isJeju,
    required this.isBusan,
    required this.isCW,
  });

  // 트랙 Rect 계산
  // 서울/부산경남/제주: 모두 세로형 오벌 (H:W 비율만 차이)
  Rect _trackRect(Size size) {
    const topReserve    = 0.13;
    const bottomReserve = 0.22;
    const hPadFrac      = 0.05;

    final hpad   = size.width  * hPadFrac;
    final topY   = size.height * topReserve;
    final availW = size.width  - hpad * 2;
    final availH = size.height * (1.0 - topReserve - bottomReserve);

    double trackW, trackH;

    if (isJeju) {
      // 제주 세로형: H:W ≈ 2.2:1
      // (우직선493.7m + 하단코너97.5m 반지름 → 세로 길이 > 가로 폭)
      const ratioHW = 2.2;
      trackW = availW;
      trackH = trackW * ratioHW;
      if (trackH > availH) {
        trackH = availH;
        trackW = trackH / ratioHW;
      }
    } else {
      // 서울/부산경남 세로형: H:W ≈ 2.0:1 (도면 기준)
      const ratioHW = 2.0;
      trackW = availW;
      trackH = trackW * ratioHW;
      if (trackH > availH) {
        trackH = availH;
        trackW = trackH / ratioHW;
      }
    }

    final leftX     = hpad + (availW - trackW) / 2;
    final topYFinal = topY + (availH - trackH) / 2;

    return Rect.fromLTWH(leftX, topYFinal, trackW, trackH);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fullTr = _trackRect(size);
    // 항상 트랙만 그림
    // 게이트뷰는 Widget 레벨 AnimatedOpacity로 처리 (canvas 블렌딩 문제 완전 제거)
    _paintFullTrack(canvas, size, fullTr);
  }

  // ────────────────────────────────────────────────────────────────────────
  //  정면 게이트 뷰 (Round 11 — 정보 배너 확대 + 색상바 최소화)
  // ────────────────────────────────────────────────────────────────────────
  void _paintGateView(Canvas canvas, Size size, Rect fullTr, double zv) {
    // ★ saveLayer 완전 제거 — Flutter Web에서 렌더 블록킹 원인
    // opacity는 Widget 레벨(AnimatedOpacity)에서 처리하므로 여기서는 항상 불투명하게 그림

    final w = size.width;
    final h = size.height;

    // ── ① 배경: 관중석 그라데이션 ──
    _paintGateBackground(canvas, size);

    // ── ② 상단 레이스 정보 배너 (40%로 축소 → 시나리오·컨디션 겹침 방지) ──
    final bannerTop = h * 0.11;  // HUD 아래
    final bannerH   = h * 0.40;  // 45% → 40% 축소 (겹침 해소)
    _paintRaceBanner(canvas, w, bannerTop, bannerH);

    // ── ③ 기수 컨디션 세로형 바 (배너 바로 아래 충분한 간격) ──
    final condBarTop = bannerTop + bannerH + h * 0.012; // 간격 확대
    final condBarH   = h * 0.085;  // 컨디션바 영역 높이 (살짝 축소)
    _paintConditionBarOverlay(canvas, size, condBarTop, condBarH);

    // ── ④ 게이트 박스 영역 ──
    final gateAreaTop = condBarTop + condBarH + h * 0.008; // 간격 확대
    final gateAreaBot = h * 0.87;
    final gateAreaH   = (gateAreaBot - gateAreaTop).clamp(0.0, h * 0.26);
    _paintGateBoxes(canvas, size, gateAreaTop, gateAreaH);

    // ── ⑤ 하단: 경주 방향 바 ──
    _paintDirectionBar(canvas, size, h * 0.88);
  }

  // 관중석 느낌 배경
  void _paintGateBackground(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 어두운 기본 배경
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF050D1A), Color(0xFF0A1628), Color(0xFF071220)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, w, h)));

    // 관중석 격자 패턴 (상단 1/3)
    final seatH = h * 0.35;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, seatH));

    // 관중석 색상 계층
    const rowH = 14.0;
    const seatColors = [
      Color(0xFF1A2A3A), Color(0xFF152235),
      Color(0xFF1C2D3F), Color(0xFF142030),
    ];
    final rowCount = (seatH / rowH).ceil();
    for (int row = 0; row < rowCount; row++) {
      final y = row * rowH;
      canvas.drawRect(
        Rect.fromLTWH(0, y, w, rowH - 1),
        Paint()..color = seatColors[row % seatColors.length],
      );
      // 좌석 칸막이
      for (double x = 0; x < w; x += 18.0) {
        canvas.drawLine(
          Offset(x, y), Offset(x, y + rowH - 1),
          Paint()..color = Colors.black.withValues(alpha: 0.3)..strokeWidth = 0.5,
        );
      }
    }
    // 관중석 상단 조명 효과
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, 40),
      Paint()..shader = LinearGradient(
        colors: [
          const Color(0xFFFFE082).withValues(alpha: 0.18),
          Colors.transparent,
        ],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, w, 40)),
    );
    canvas.restore();

    // 트랙 지면 (하단 2/3)
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.35, w, h * 0.65),
      Paint()..shader = LinearGradient(
        colors: [const Color(0xFF2A5A1A), const Color(0xFF1E4012)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, h * 0.35, w, h * 0.65)),
    );

    // 더트 구역 (게이트 앞)
    final dirtTop = h * 0.68;
    canvas.drawRect(
      Rect.fromLTWH(0, dirtTop, w, h * 0.18),
      Paint()..shader = LinearGradient(
        colors: [const Color(0xFF8B6035), const Color(0xFFA07845), const Color(0xFF8B6035)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, dirtTop, w, h * 0.18)),
    );

    // 구역 경계선
    canvas.drawLine(
      Offset(0, h * 0.35), Offset(w, h * 0.35),
      Paint()..color = const Color(0xFF3A5A2A)..strokeWidth = 2,
    );
    canvas.drawLine(
      Offset(0, dirtTop), Offset(w, dirtTop),
      Paint()..color = Colors.white.withValues(alpha: 0.4)..strokeWidth = 2.5,
    );
    canvas.drawLine(
      Offset(0, dirtTop + h * 0.18), Offset(w, dirtTop + h * 0.18),
      Paint()..color = Colors.white.withValues(alpha: 0.4)..strokeWidth = 2.5,
    );

    // 스포트라이트 효과 (양쪽)
    for (final xFrac in [0.15, 0.85]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * xFrac, h * 0.35),
          width: w * 0.5,
          height: h * 0.3,
        ),
        Paint()..shader = RadialGradient(
          colors: [
            const Color(0xFFFFE082).withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCenter(
          center: Offset(w * xFrac, h * 0.35),
          width: w * 0.5, height: h * 0.3,
        )),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  레이스 정보 배너 (Round 12 — 폰트 확대 + 시나리오 상세화 + 컨디션바 최소화)
  // ─────────────────────────────────────────────────────────────────────────
  void _paintRaceBanner(Canvas canvas, double w, double top, double bannerH) {
    final bannerRect = Rect.fromLTWH(0, top, w, bannerH);

    // ── 배경 ──
    canvas.drawRect(bannerRect, Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF080F1A),
          const Color(0xFF0A1628),
          const Color(0xFF080F1A),
        ],
        begin: Alignment.centerLeft, end: Alignment.centerRight,
      ).createShader(bannerRect));

    // 골드 상단/하단 라인
    canvas.drawLine(Offset(0, top), Offset(w, top),
        Paint()..color = const Color(0xFFFFD700)..strokeWidth = 2.5);
    canvas.drawLine(Offset(0, top + bannerH), Offset(w, top + bannerH),
        Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.4)..strokeWidth = 1.5);

    // ── 섹션 1: 상단 레이스명 바 (bannerH의 14%) ──
    final sec1H = bannerH * 0.14;
    final sec1Rect = Rect.fromLTWH(0, top, w, sec1H);
    canvas.drawRect(sec1Rect, Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFF8B1A1A), const Color(0xFF6A1010), const Color(0xFF8B1A1A)],
        begin: Alignment.centerLeft, end: Alignment.centerRight,
      ).createShader(sec1Rect));

    // 좌측 로고 박스
    canvas.drawRect(Rect.fromLTWH(0, top, w * 0.16, sec1H),
        Paint()..color = Colors.black.withValues(alpha: 0.4));
    _txt(canvas, '경마통', Offset(w * 0.08, top + sec1H * 0.5),
        const Color(0xFFFFD700), 11.5, bold: true, centered: true);

    // 중앙: 경주명 + 거리 (폰트 확대)
    _txt(canvas, '$venueName 제$raceNo경주',
        Offset(w * 0.54, top + sec1H * 0.34),
        Colors.white, 16, bold: true, centered: true);
    _txt(canvas, '${distance}m  ·  ${horses.length}두 출전',
        Offset(w * 0.54, top + sec1H * 0.76),
        const Color(0xFFFFD700).withValues(alpha: 0.9), 11.5, centered: true);

    // 우측 방향 뱃지 (항상 CCW)
    const dirText = '←CCW';
    const dirColor = Color(0xFF81C784);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.87, top + sec1H * 0.12, w * 0.12, sec1H * 0.76),
        const Radius.circular(4),
      ),
      Paint()..color = dirColor.withValues(alpha: 0.22),
    );
    _txt(canvas, dirText, Offset(w * 0.93, top + sec1H * 0.5),
        dirColor, 10.5, bold: true, centered: true);

    // ── 섹션 2: 전개 예상 시나리오 (bannerH의 15%~100% → 충분한 공간 확보) ──
    final sec2Top = top + bannerH * 0.15;
    final sec2H   = bannerH * 0.84; // 배너 높이 줄었으므로 비율 확대

    // 섹션 제목 (폰트 확대, Y 위치 더 위로)
    _txt(canvas, '📊 전개 예상 시나리오',
        Offset(w * 0.04, sec2Top + sec2H * 0.04),
        const Color(0xFFFFD700), 12, bold: true);

    // AI 분류: speed/stamina 기반 전략 결정
    final sorted = [...horses]..sort(
        (a, b) => b.entry.finalScore.compareTo(a.entry.finalScore));
    final bySpeed   = [...horses]..sort(
        (a, b) => b.entry.speedStat.compareTo(a.entry.speedStat));
    final byStamina = [...horses]..sort(
        (a, b) => b.entry.staminaStat.compareTo(a.entry.staminaStat));

    final n = horses.length;
    final frontRunners = bySpeed.take((n / 3).ceil()).toList();
    final closers      = byStamina.take((n / 3).ceil()).toList();
    final midRunners   = horses.where((h) =>
        !frontRunners.any((f) => f.entry.gateNo == h.entry.gateNo) &&
        !closers.any((c) => c.entry.gateNo == h.entry.gateNo)).toList();

    // 상세 전략 설명 행
    final strategies = [
      (
        '선행', '⚡',
        frontRunners.take(3).map((h) => '${h.entry.gateNo}번').join('·'),
        '초반 선두 장악 · 페이스 메이킹 · 코너 내측 유리',
        const Color(0xFFFF6B35),
      ),
      (
        '선입', '🏃',
        midRunners.take(3).map((h) => '${h.entry.gateNo}번').join('·'),
        '선두 후방 2~3마신 위치 · 직선 400m서 추격',
        const Color(0xFF64B5F6),
      ),
      (
        '추입', '🚀',
        closers.take(3).map((h) => '${h.entry.gateNo}번').join('·'),
        '후반 지구력 부스터 발동 · 막판 역전 狙',
        const Color(0xFF81C784),
      ),
    ];

    final rowH = sec2H * 0.24;
    for (int si = 0; si < strategies.length; si++) {
      final (label, emoji, horseNos, desc, color) = strategies[si];
      final rowY = sec2Top + sec2H * 0.16 + si * rowH;

      // 전략 레이블 배경 박스
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.02, rowY - rowH * 0.44, w * 0.145, rowH * 0.88),
          const Radius.circular(4),
        ),
        Paint()..color = color.withValues(alpha: 0.28),
      );
      _txt(canvas, '$emoji$label', Offset(w * 0.092, rowY),
          color, 11, bold: true, centered: true);

      // 말 번호 (큰 폰트)
      _txt(canvas, horseNos,
          Offset(w * 0.185, rowY - rowH * 0.22),
          Colors.white, 11, bold: true);

      // 상세 설명 (확대된 폰트)
      _txt(canvas, desc,
          Offset(w * 0.185, rowY + rowH * 0.24),
          color.withValues(alpha: 0.78), 9.5);
    }

    // 주목마 하이라이트 박스 (폰트 확대)
    if (sorted.isNotEmpty) {
      final fav = sorted[0];
      final favStr = '⭐ 주목마: ${fav.entry.gateNo}번 ${fav.entry.horseName}  AI ${fav.entry.finalScore.toStringAsFixed(1)}pt';
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.03, sec2Top + sec2H * 0.88, w * 0.94, sec2H * 0.10),
          const Radius.circular(4),
        ),
        Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.12),
      );
      _txt(canvas, favStr,
          Offset(w * 0.5, sec2Top + sec2H * 0.932),
          const Color(0xFFFFD700), 11, bold: true, centered: true);
    }

    // 섹션3: 기수 컨디션은 게이트 박스 위 전용 메서드로 이동 (bannerH 70%이후 공간 확보)
    // 아무것도 그리지 않음 → _paintConditionBarOverlay로 대체
  }


  // ─────────────────────────────────────────────────────────────────────────
  //  기수 컨디션 세로형 바 오버레이
  //  서울/부산경남: 오른쪽=1번 (CCW 내측)
  //  제주: 왼쪽=1번 (제주 전용 별도 로직)
  // ─────────────────────────────────────────────────────────────────────────
  void _paintConditionBarOverlay(Canvas canvas, Size size, double top, double areaH) {
    final w = size.width;
    final n = horses.length;
    if (n == 0) return;

    // 게이트 박스와 동일한 가로 레이아웃 계산
    const minBoxW = 30.0;
    const maxBoxW = 50.0;
    final available = w * 0.96;
    final rawW = available / n;
    final boxW = rawW.clamp(minBoxW, maxBoxW);
    final totalW = boxW * n;
    final startX = (w - totalW) / 2;

    // 섹션 타이틀
    _txt(canvas, '🏇 기수 컨디션',
        Offset(w * 0.04, top + areaH * 0.10),
        const Color(0xFFFFD700), 9.5, bold: true);

    // 최대 세로 바 높이 (타이틀 제외)
    const titleH = 0.25;
    final barMaxH = areaH * (1.0 - titleH - 0.08); // 하단 여백 포함
    final barStartY = top + areaH * (titleH + 0.05);

    // ── 정렬 기준 ──
    // 제주: 왼쪽=1번 (idx=0 → gateNo=1)
    // 서울/부산경남: 오른쪽=1번 (idx=0 → gateNo=n)
    for (int idx = 0; idx < n; idx++) {
      final gateNo = isJeju ? (idx + 1) : (n - idx);  // 제주=왼쪽1번, 서울=오른쪽1번
      final horse = horses.firstWhere(
        (h) => h.entry.gateNo == gateNo,
        orElse: () => horses[idx % n],
      );

      final cd    = HorseCapColors.getCapData(horse.entry.gateNo);
      final cx    = startX + idx * boxW + boxW * 0.5;
      final condF = (horse.entry.formStat / 100.0).clamp(0.0, 1.0);
      final condColor = condF > 0.75
          ? const Color(0xFF4CAF50)
          : condF > 0.5
              ? const Color(0xFFFFD700)
              : const Color(0xFFFF5722);

      // 세로 바 배경 (회색)
      final barW  = (boxW * 0.50).clamp(6.0, 18.0);
      final barX  = cx - barW / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, barStartY, barW, barMaxH),
          const Radius.circular(3),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.10),
      );

      // 세로 바 채우기 (아래→위, 퍼센트만큼)
      final fillH  = barMaxH * condF;
      final fillY  = barStartY + barMaxH - fillH;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, fillY, barW, fillH),
          const Radius.circular(3),
        ),
        Paint()..color = condColor.withValues(alpha: 0.90),
      );

      // 바 위에 등급 텍스트 (최상/양호/보통/주의)
      final grade = condF > 0.8 ? '최상'
          : condF > 0.6 ? '양호'
          : condF > 0.4 ? '보통'
          : '주의';
      final gradeFontSize = (boxW * 0.16).clamp(5.5, 9.0);
      _txt(canvas, grade,
          Offset(cx, barStartY - 6),
          condColor, gradeFontSize, bold: true, centered: true);

      // 바 아래 마번 원 배지
      final circR = (boxW * 0.20).clamp(7.0, 13.0);
      final circY = barStartY + barMaxH + circR + 2;
      canvas.drawCircle(Offset(cx, circY), circR, Paint()..color = cd.bg);
      _txt(canvas, '${horse.entry.gateNo}',
          Offset(cx, circY),
          cd.text, circR * 0.90, bold: true, centered: true);
    }
  }

  // 게이트 박스들 (세로 배열, 오른쪽=1번마)
  void _paintGateBoxes(Canvas canvas, Size size, double areaTop, double areaH) {
    final w = size.width;
    final n = horses.length;
    if (n == 0) return;

    // 박스 크기 계산 (더 축소)
    const minBoxW = 30.0;
    const maxBoxW = 50.0;
    final available = w * 0.96;
    final rawW = available / n;
    final boxW = rawW.clamp(minBoxW, maxBoxW);
    final totalW = boxW * n;
    final startX = (w - totalW) / 2;

    // 게이트 구조물 — 배너 확대로 박스 영역이 좁아짐 → 높이 더 컴팩트
    final gateTop    = areaTop;
    final gateBot    = areaTop + areaH * 0.95;  // 주어진 영역 최대 활용
    final gateH      = gateBot - gateTop;

    // 게이트 배경 전체 프레임
    canvas.drawRect(
      Rect.fromLTWH(startX - 4, gateTop - 4, totalW + 8, gateH + 8),
      Paint()..color = const Color(0xFF2A2A2A),
    );

    // ── 게이트 박스 순서 ──
    // 제주:         idx=0 → 왼쪽 → gateNo=1  (왼쪽=1번마, 제주 전용)
    // 서울/부산경남: idx=0 → 오른쪽 → gateNo=1 (오른쪽=1번마, CCW 내측)
    for (int idx = 0; idx < n; idx++) {
      final gateNo = isJeju ? (idx + 1) : (n - idx); // 제주=왼쪽1번, 서울=오른쪽1번
      final horse = horses.firstWhere(
        (h) => h.entry.gateNo == gateNo,
        orElse: () => horses[idx % horses.length],
      );

      final bx = startX + idx * boxW;
      _paintSingleGateBox(canvas, horse, bx, gateTop, boxW, gateH);
    }

    // 게이트 하단 발판 (더트 구역)
    final footY = gateBot;
    canvas.drawRect(
      Rect.fromLTWH(startX - 4, footY, totalW + 8, 8),
      Paint()..color = const Color(0xFF4A3A20),
    );
  }

  // 단일 게이트 박스
  void _paintSingleGateBox(Canvas canvas, _Horse horse,
      double bx, double gateTop, double boxW, double gateH) {
    final cd = HorseCapColors.getCapData(horse.entry.gateNo);
    final bRect = Rect.fromLTWH(bx + 1, gateTop, boxW - 2, gateH);

    // 박스 배경 (마번 색상)
    final bgColor = cd.bg;

    // 배경 그라데이션
    canvas.drawRect(bRect, Paint()
      ..shader = LinearGradient(
        colors: [
          bgColor.withValues(alpha: 0.95),
          Color.lerp(bgColor, Colors.black, 0.35)!,
        ],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ).createShader(bRect));

    // 줄무늬 패턴 (stripe 색상 있을 때)
    if (cd.stripe != null) {
      canvas.save();
      canvas.clipRect(bRect);
      for (double sx = bRect.left - bRect.height; sx < bRect.right + bRect.height; sx += boxW * 0.45) {
        final stripePath = Path()
          ..moveTo(sx, bRect.top)
          ..lineTo(sx + boxW * 0.22, bRect.top)
          ..lineTo(sx + boxW * 0.22 - bRect.height * 0.3, bRect.bottom)
          ..lineTo(sx - bRect.height * 0.3, bRect.bottom)
          ..close();
        canvas.drawPath(stripePath, Paint()..color = cd.stripe!.withValues(alpha: 0.35));
      }
      canvas.restore();
    }

    // 박스 테두리 (골드)
    canvas.drawRect(bRect, Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0);

    // 내부 분할선
    canvas.drawLine(
      Offset(bx + 1, gateTop + gateH * 0.38),
      Offset(bx + boxW - 1, gateTop + gateH * 0.38),
      Paint()..color = Colors.white.withValues(alpha: 0.2)..strokeWidth = 0.7,
    );

    final cx = bx + boxW * 0.5;

    // ── 마번 (상단 배경 원 + 숫자 — 단일 렌더) ──
    final numSize = (boxW * 0.48).clamp(14.0, 26.0);
    final numCY   = gateTop + gateH * 0.18;
    // 배경 원 1개만 그린 뒤 숫자 오버레이
    canvas.drawCircle(
      Offset(cx, numCY),
      numSize * 0.70,
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );
    _txt(canvas, '${horse.entry.gateNo}',
        Offset(cx, numCY),
        cd.text, numSize * 0.88, bold: true, centered: true);

    // ── 기수 저지 (색상 원 + J) ──
    final capY = gateTop + gateH * 0.40;
    final capR = (boxW * 0.22).clamp(8.0, 18.0);
    canvas.drawCircle(Offset(cx, capY), capR,
        Paint()..color = cd.bg);
    if (cd.stripe != null) {
      final cl = Path()..addOval(Rect.fromCircle(center: Offset(cx, capY), radius: capR));
      canvas.save();
      canvas.clipPath(cl);
      for (int s = 0; s < 3; s++) {
        canvas.drawRect(
          Rect.fromLTWH(cx - capR + s * capR * 0.75, capY - capR, capR * 0.42, capR * 2),
          Paint()..color = cd.stripe!.withValues(alpha: 0.85),
        );
      }
      canvas.restore();
    }
    canvas.drawCircle(Offset(cx, capY), capR, Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
    _txt(canvas, 'J', Offset(cx, capY),
        cd.text, capR * 0.85, bold: true, centered: true);

    // ── 말이름 ──
    final horseNameY = gateTop + gateH * 0.62;
    final nameStr = horse.entry.horseName.length > 5
        ? horse.entry.horseName.substring(0, 5)
        : horse.entry.horseName;
    final nameFontSize = (boxW * 0.19).clamp(7.5, 11.5);
    _txt(canvas, nameStr,
        Offset(cx, horseNameY),
        Colors.white, nameFontSize, bold: true, centered: true);

    // ── 기수이름 ──
    if (horse.entry.jockeyName.isNotEmpty) {
      final jockeyStr = horse.entry.jockeyName.length > 4
          ? horse.entry.jockeyName.substring(0, 4)
          : horse.entry.jockeyName;
      final jockeyFontSize = (boxW * 0.16).clamp(6.5, 10.0);
      _txt(canvas, jockeyStr,
          Offset(cx, gateTop + gateH * 0.79),
          cd.text.withValues(alpha: 0.85), jockeyFontSize, centered: true);
    }

    // 하단 게이트 빗장
    canvas.drawRect(
      Rect.fromLTWH(bx + 1, gateTop + gateH - 10, boxW - 2, 10),
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    // 빗장 볼트
    canvas.drawCircle(
      Offset(cx, gateTop + gateH - 5),
      2.5,
      Paint()..color = const Color(0xFF888888),
    );
  }

  // 경주 방향 바 + 미니 오벌
  void _paintDirectionBar(Canvas canvas, Size size, double top) {
    final w = size.width;
    final barH = size.height * 0.12;

    // 배경
    canvas.drawRect(
      Rect.fromLTWH(0, top, w, barH),
      Paint()..color = const Color(0xFF0A1628).withValues(alpha: 0.85),
    );
    canvas.drawLine(
      Offset(0, top), Offset(w, top),
      Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.4)..strokeWidth = 1.5,
    );

    // 방향 텍스트 — 서울·부산경남: CW(시계방향), 제주: CCW(반시계방향)
    final dirText  = isJeju ? '시계 반대 방향 ←' : '시계 방향 →';
    final dirLabel = isJeju ? 'CCW (제주)' : 'CW (서울·부산경남)';
    final dirColor = isJeju ? const Color(0xFF81C784) : const Color(0xFF64B5F6);

    _txt(canvas, dirText,
        Offset(w * 0.5, top + barH * 0.32),
        dirColor, 13, bold: true, centered: true);
    _txt(canvas, dirLabel,
        Offset(w * 0.5, top + barH * 0.68),
        dirColor.withValues(alpha: 0.65), 9.5, centered: true);

    // 미니 오벌 (좌측) — 제주: CCW, 서울·부산경남: CW
    _paintMiniOval(canvas, Offset(w * 0.12, top + barH * 0.5), 20, !isJeju);

    // 마번 순서 안내 (우측)
    // 제주: 왼쪽=1번 / 서울·부산경남: 오른쪽=1번
    if (isJeju) {
      _txt(canvas, '좌측 → 1번',
          Offset(w * 0.88, top + barH * 0.32),
          Colors.white.withValues(alpha: 0.6), 9, centered: true);
      _txt(canvas, '우측 → ${horses.length}번',
          Offset(w * 0.88, top + barH * 0.68),
          Colors.white.withValues(alpha: 0.6), 9, centered: true);
    } else {
      _txt(canvas, '우측 → 1번',
          Offset(w * 0.88, top + barH * 0.32),
          Colors.white.withValues(alpha: 0.6), 9, centered: true);
      _txt(canvas, '좌측 → ${horses.length}번',
          Offset(w * 0.88, top + barH * 0.68),
          Colors.white.withValues(alpha: 0.6), 9, centered: true);
    }
  }

  // 미니 오벌 방향 아이콘
  void _paintMiniOval(Canvas canvas, Offset center, double r, bool cw) {
    canvas.drawOval(
      Rect.fromCenter(center: center, width: r * 2.2, height: r * 1.4),
      Paint()
        ..color = const Color(0xFF3A5A3A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // 화살표 (방향 표시)
    final arrowAngle = cw ? pi * 0.25 : pi * 0.75;
    final ax = center.dx + cos(arrowAngle) * r * 1.1;
    final ay = center.dy + sin(arrowAngle) * r * 0.7;
    final headLen = 5.0;
    final headAngle = cw ? arrowAngle + pi * 0.6 : arrowAngle - pi * 0.6;
    canvas.drawLine(
      Offset(ax, ay),
      Offset(ax + cos(headAngle) * headLen, ay + sin(headAngle) * headLen),
      Paint()..color = const Color(0xFF81C784)..strokeWidth = 2.5..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(ax, ay),
      Offset(ax + cos(headAngle + pi * 0.5) * headLen, ay + sin(headAngle + pi * 0.5) * headLen),
      Paint()..color = const Color(0xFF81C784)..strokeWidth = 2.5..strokeCap = StrokeCap.round,
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  //  전체 트랙 뷰
  // ────────────────────────────────────────────────────────────────────────
  void _paintFullTrack(Canvas canvas, Size size, Rect tr) {
    _drawBg(canvas, size);
    if (isJeju) {
      // 제주 전용 트랙 렌더링
      _drawJejuTrack(canvas, size, tr);
      _drawJejuMarkers(canvas, size, tr);
      _drawJejuStartFinishLines(canvas, size, tr);
    } else if (isBusan) {
      // 부산경남 전용 트랙 렌더링
      _drawBusanTrack(canvas, size, tr);
      _drawBusanMarkers(canvas, size, tr);
      _drawBusanStartFinishLines(canvas, size, tr);
    } else {
      _drawTrack(canvas, size, tr);
      _drawMarkers(canvas, size, tr);
      _drawStartFinishLines(canvas, size, tr);
    }
    _drawHorses(canvas, size, tr);
    _drawLegend(canvas, size, tr);
  }

  void _drawBg(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF071220), Color(0xFF0D1E34), Color(0xFF071220)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    final gp = Paint()..color = Colors.white.withValues(alpha: 0.025)..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gp);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
    }
  }

  // ── 서울 단일 트랙 (CW 세로형) ──
  // 단일 더트 링 + 중앙 잔디 — 코너/직선 색상 완전 연속
  // ★ hw/hr은 _TG.toPoint 와 완전 동일한 값 사용 (0.42/0.44)
  // ★ 내측 잔디 경계 hw_grass = hw - trackW (hr 고정) → 코너 빈 공간 없음
  void _drawTrack(Canvas canvas, Size size, Rect tr) {
    final cx  = tr.center.dx;
    final cy  = tr.center.dy;
    final hw  = tr.width  * 0.42;   // 코너 가로 반지름 (= toPoint 동일)
    final hr  = tr.height * 0.44;   // 직선 세로 반높이 (= toPoint 동일)

    // 트랙 너비 (hr 고정, hw만 줄여서 내측 경계)
    final trackW = (hw * 0.28).clamp(16.0, 28.0); // 단일 트랙 폭
    final hwGrass = hw - trackW;                   // 내측 잔디 경계 hw

    // ── ① 외측 오벌 (전체 트랙 영역) ──
    final outerPath = _ovalPath(cx, cy, hw,       hr);         // 외측 경계
    final innerPath = _ovalPath(cx, cy, hwGrass,  hr);         // 내측 잔디 경계 (hr 고정!)
    final trackRing = Path.combine(PathOperation.difference, outerPath, innerPath);

    // ── ② 내측 잔디 채우기 ──
    canvas.drawPath(innerPath, Paint()..color = const Color(0xFF1A5A1A));
    _drawGrassStripes(canvas, cx, cy, hwGrass, hr);

    // ── ③ 트랙 단색 베이스 (코너/직선 모두 연속) ──
    canvas.drawPath(trackRing,
        Paint()..color = const Color(0xFFBB8B40)..style = PaintingStyle.fill);

    // ── ④ 직선 구간 하이라이트 (좌/우 직선 세로 띠) ──
    canvas.save();
    canvas.clipPath(trackRing);
    // 우직선 (cx+hwGrass ~ cx+hw)
    canvas.drawRect(
      Rect.fromLTRB(cx + hwGrass, cy - hr, cx + hw, cy + hr),
      Paint()..color = const Color(0xFFD4A055).withValues(alpha: 0.60),
    );
    // 좌직선 (cx-hw ~ cx-hwGrass)
    canvas.drawRect(
      Rect.fromLTRB(cx - hw, cy - hr, cx - hwGrass, cy + hr),
      Paint()..color = const Color(0xFFD4A055).withValues(alpha: 0.60),
    );
    canvas.restore();

    // ── ⑤ 더트 텍스처 (트랙 전체) ──
    final rng = Random(11111);
    canvas.save();
    canvas.clipPath(trackRing);
    for (int i = 0; i < 300; i++) {
      final t = rng.nextDouble();
      final off = (rng.nextDouble() - 0.5) * trackW * 0.7;
      final pt = _TG.toPoint(t, tr, clusterOff: off, isCW: false);
      final gs = 0.6 + rng.nextDouble() * 1.6;
      canvas.drawOval(
        Rect.fromCenter(center: pt, width: gs * 2, height: gs),
        Paint()..color = Color.lerp(const Color(0xFFDDBB88), const Color(0xFF8B6035),
            rng.nextDouble())!.withValues(alpha: 0.22 + rng.nextDouble() * 0.32),
      );
    }
    canvas.restore();

    // ── ⑥ 경계선 (외곽 + 내측) — 2선으로 단순화 ──
    canvas.drawPath(outerPath, Paint()
      ..color = Colors.white.withValues(alpha: 0.80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0);
    canvas.drawPath(innerPath, Paint()
      ..color = Colors.white.withValues(alpha: 0.60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);

    // ── ⑦ 코너 하이라이트 ──
    _drawCornerHighlight(canvas, cx, cy, hw, hr);

    // ── ⑦ 내측 텍스트 ──
    _txt(canvas, '${distance}m 레이스',
        Offset(cx, cy - hr * 0.3),
        Colors.white.withValues(alpha: 0.5), 10, centered: true);
    _txt(canvas, '$venueName 경마공원',
        Offset(cx, cy + hr * 0.3),
        Colors.white.withValues(alpha: 0.35), 9, centered: true);
    _txt(canvas, '↻ CW', Offset(cx, cy),
        const Color(0xFF81C784).withValues(alpha: 0.4), 10, bold: true, centered: true);

    // ── ⑧ 직선 레이블 ──
    // CW 우직선: 아래→위 ← 1000m(특별)/1200/1300/1400m 출발선
    // CW 좌직선: 위→아래 ← GOAL(하단85%) + 1700~2000m 출발선
    _txt(canvas, '우직선 400m',
        Offset(tr.right + 6, cy),
        Colors.white.withValues(alpha: 0.35), 7.5, centered: false);
    _txt(canvas, '↑1000~1400m',
        Offset(tr.right + 6, cy - 14),
        Colors.white.withValues(alpha: 0.25), 6.5, centered: false);
    _txt(canvas, '좌직선 600m',
        Offset(tr.left - 74, cy),
        Colors.white.withValues(alpha: 0.35), 7.5, centered: false);
    _txt(canvas, 'GOAL+1700~2000m',
        Offset(tr.left - 74, cy + 12),
        Colors.white.withValues(alpha: 0.25), 6.0, centered: false);
  }

  void _drawGrassStripes(Canvas canvas, double cx, double cy, double hw, double hr) {
    for (int i = 0; i < 4; i++) {
      final h2 = hw * (0.4 + i * 0.15);  // 가로
      final r2 = hr * (0.4 + i * 0.15);  // 세로
      if (i.isEven) {
        canvas.drawPath(_ovalPath(cx, cy, h2, r2), Paint()
          ..color = const Color(0xFF154A15).withValues(alpha: 0.55)
          ..style = PaintingStyle.fill);
      }
    }
  }

  void _drawCornerHighlight(Canvas canvas, double cx, double cy, double hw, double hr) {
    // 세로형: 코너가 상·하에 위치
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy + hr), width: hw * 2.6, height: hw * 2.6),
      0, pi, false,
      Paint()..color = const Color(0xFFFFAA00).withValues(alpha: 0.08)..style = PaintingStyle.fill,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy - hr), width: hw * 2.6, height: hw * 2.6),
      pi, pi, false,
      Paint()..color = const Color(0xFFFFAA00).withValues(alpha: 0.08)..style = PaintingStyle.fill,
    );
    _txt(canvas, '코너', Offset(cx, cy + hr + hw * 0.15),
        Colors.white.withValues(alpha: 0.35), 8, centered: true);
    _txt(canvas, '코너', Offset(cx, cy - hr - hw * 0.15),
        Colors.white.withValues(alpha: 0.35), 8, centered: true);
  }

  // ── 거리 마커 (GOAL 기준 역산 잔여거리 표시) ──
  void _drawMarkers(Canvas canvas, Size size, Rect tr) {
    // distance가 1000m인 경우에도 200/400/600/800m 마커 표시
    final dists = [200, 400, 600, 800, 1000, 1200, 1400, 1600, 1800];
    final gp = _TG.goalP;
    for (final d in dists) {
      if (d >= distance) continue;
      // goalP에서 d미터 전의 진행률
      final markerP = (gp - d.toDouble() / _TG.total + 10.0) % 1.0;
      final pt  = _TG.toPoint(markerP, tr, isCW: false);
      final ang = _TG.toAngle(markerP, isCW: false);
      // 트랙에 수직 방향
      final nx  = -sin(ang) * 16.0;
      final ny  =  cos(ang) * 16.0;

      canvas.drawLine(pt + Offset(nx, ny), pt - Offset(nx, ny),
          Paint()..color = Colors.white.withValues(alpha: 0.3)..strokeWidth = 1.0);
      // 마커 텍스트 (트랙 안쪽에 표시)
      _txt(canvas, '${d}m', pt + Offset(nx * 1.8, ny * 1.8 - 4),
          Colors.white.withValues(alpha: 0.5), 7.5, centered: true);
    }
  }

  // ── 서울/부산경남 전체 출발선 + GOAL ──
  // 도면 기준:
  //   GOAL = 좌직선 하단부 85% (화면 좌측 하단, 하단코너 바로 전)
  //   1000m(특별)/1200/1300/1400m = 우직선
  //   1600m = 하단코너 센터
  //   1700~2000m = 좌직선
  //   2300m = 상단코너
  void _drawStartFinishLines(Canvas canvas, Size size, Rect tr) {
    // ① 모든 출발선 (흐리게)
    _drawSeoulAllStartLines(canvas, tr);

    // ② GOAL 결승선 (체크무늬 + 빨간 표지판)
    // 도면 기준: 좌직선 하단 85% = 화면 좌측 하단, 하단코너 진입 전
    const tw = 26.0;
    final gpp  = _TG.goalP % 1.0;
    final gpt  = _TG.toPoint(gpp, tr);
    final gang = _TG.toAngle(gpp);
    // GOAL은 좌직선 → gang=π/2 → gnx=cos(π/2)*체크폭, gny=-sin(π/2)*체크폭
    // 좌직선 바깥(왼쪽)이 레이블 위치 → -sin(gang) = -1 방향 (x 감소)
    final gnx  = -sin(gang) * (tw + 8); // 좌직선: sin(π/2)=1 → gnx=-(tw+8) (왼쪽 바깥)
    final gny  =  cos(gang) * (tw + 8); // 좌직선: cos(π/2)=0 → gny=0

    // 체크무늬 결승선
    for (int i = 0; i < 10; i++) {
      final ptA = gpt + Offset(gnx, gny) * (1 - i / 10.0 * 2);
      final ptB = gpt + Offset(gnx, gny) * (1 - (i + 1) / 10.0 * 2);
      canvas.drawLine(ptA, ptB, Paint()
        ..color = i.isEven ? Colors.white : Colors.red
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.butt);
    }
    // GOAL 표지판 (좌직선 바깥 왼쪽에 배치)
    final goalTag = gpt + Offset(gnx * 2.8, gny * 2.8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: goalTag, width: 50, height: 20),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.red,
    );
    _txt(canvas, 'GOAL', goalTag, Colors.white, 10, bold: true, centered: true);

    // ③ 현재 경주 출발선 강조 (황금색 굵은선)
    final spp  = startP % 1.0;
    final spt  = _TG.toPoint(spp, tr);
    final sang = _TG.toAngle(spp);
    final snx  = -sin(sang) * (tw + 4);
    final sny  =  cos(sang) * (tw + 4);
    canvas.drawLine(spt + Offset(snx, sny), spt - Offset(snx, sny),
        Paint()..color = Colors.white..strokeWidth = 3.0);
    canvas.drawLine(spt + Offset(snx, sny), spt - Offset(snx, sny),
        Paint()..color = const Color(0xFFFFD700)..strokeWidth = 2.0);

    // ④ 1600m: 하단코너 코너 마커 추가 시각화
    if (distance == 1600) {
      _draw1600CornerMarker(canvas, tr);
    }

    // ⑤ 우직선 바깥 스타트라인 안내 마커 (1000/1200/1300/1400m 경주)
    _drawRightStraightStartMarkers(canvas, tr);
  }

  // ── 1600m 하단코너 출발선 특별 마커 ──
  // 하단코너 중앙부(50% 지점)에 아치형 마커 표시
  void _draw1600CornerMarker(Canvas canvas, Rect tr) {
    final cx = tr.center.dx;
    final cy = tr.center.dy;
    final hw = tr.width  * 0.42;
    final hr = tr.height * 0.44;

    final sp  = _TG.startP(1600);
    final pt  = _TG.toPoint(sp % 1.0, tr);
    final ang = _TG.toAngle(sp % 1.0);
    final nx  = -sin(ang) * 30.0;
    final ny  =  cos(ang) * 30.0;

    // 코너 중앙 마커 (외측 호 방향으로 표지선)
    canvas.drawLine(pt + Offset(nx, ny), pt - Offset(nx, ny),
        Paint()
          ..color = const Color(0xFFFFD700).withValues(alpha: 0.85)
          ..strokeWidth = 2.5);

    // 코너 안쪽 아치 표시 (코너임을 시각적으로 강조)
    final arcCenter = Offset(cx, cy + hr);
    canvas.drawArc(
      Rect.fromCenter(center: arcCenter, width: hw * 1.6, height: hw * 1.6),
      pi * 0.85, pi * 0.3, false,
      Paint()
        ..color = const Color(0xFFFFD700).withValues(alpha: 0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // "하단코너 1600m" 레이블 (코너 안쪽)
    _txt(canvas, '1600m', pt + Offset(nx * 2.2, ny * 2.2),
        const Color(0xFFFFD700).withValues(alpha: 0.90), 8.0,
        bold: true, centered: true);
    _txt(canvas, '하단코너', pt + Offset(nx * 2.2, ny * 2.2 + 12),
        Colors.white.withValues(alpha: 0.60), 6.5, centered: true);
  }

  // ── CW: 우직선(오른쪽) 1000/1200/1300/1400m 출발선 바깥 안내 마커 ──
  // 도면 기준: 1000m(특별경주)/1200/1300/1400m 출발선은 우직선(화면 우측)에 위치
  // CW 진행: 우직선 아래→위 → 상단코너 → 좌직선 위→아래 → GOAL
  // 마커는 우직선 바깥(오른쪽)에 표시 — 도면과 동일
  void _drawRightStraightStartMarkers(Canvas canvas, Rect tr) {
    final cx = tr.center.dx;
    final hw = tr.width  * 0.42;
    const outerOffX = 40.0; // 트랙 오른쪽 바깥으로 떨어뜨릴 거리

    // 우직선에 위치하는 출발선 (아래쪽부터 순서: 1200→1300→1400→1000)
    // CW 우직선: 아래→위 진행 → 1200m(하단부, 큰 y), 1400m(중단), 1000m(상단, 작은 y)
    final dists = [1200, 1300, 1400, 1000]; // 화면 아래→위 순

    // 브라켓 연결선: 1200m(하단) ~ 1400m(중단) 그룹 (통상 경주 구간)
    final p1200  = _TG.startP(1200);
    final p1400  = _TG.startP(1400);
    final pt1200 = _TG.toPoint(p1200 % 1.0, tr);
    final pt1400 = _TG.toPoint(p1400 % 1.0, tr);
    final bracketX = cx + hw + outerOffX;

    // 1200~1400m 브라켓 (통상 거리 그룹)
    canvas.drawLine(
      Offset(bracketX, pt1200.dy), // 1200m: 아래쪽 (더 큰 y)
      Offset(bracketX, pt1400.dy), // 1400m: 위쪽 (더 작은 y)
      Paint()..color = Colors.white.withValues(alpha: 0.22)..strokeWidth = 1.0,
    );

    // 1000m 별도 점선 마커 (특별경주 전용 — 브라켓 위쪽 따로 표시)
    final p1000  = _TG.startP(1000);
    final pt1000 = _TG.toPoint(p1000 % 1.0, tr);
    canvas.drawLine(
      Offset(cx + hw, pt1000.dy),
      Offset(bracketX + 4, pt1000.dy),
      Paint()
        ..color = const Color(0xFF00BFFF).withValues(alpha: 0.45)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    // 각 거리 눈금선 + 레이블
    for (final d in dists) {
      final sp = _TG.startP(d);
      final pt = _TG.toPoint(sp % 1.0, tr);
      final isCurrent  = (d == distance);
      final is1000m    = (d == 1000);

      final lineColor = isCurrent
          ? const Color(0xFFFFD700)
          : is1000m
              ? const Color(0xFF00BFFF).withValues(alpha: 0.50)
              : Colors.white.withValues(alpha: 0.32);
      final lineW = isCurrent ? 2.0 : (is1000m ? 1.4 : 1.0);

      // 트랙 경계 → 브라켓까지 눈금선 (우측 방향)
      canvas.drawLine(
        Offset(cx + hw, pt.dy),
        Offset(bracketX + 6, pt.dy),
        Paint()..color = lineColor..strokeWidth = lineW,
      );

      // 레이블
      final labelColor = isCurrent
          ? const Color(0xFFFFD700)
          : is1000m
              ? const Color(0xFF00BFFF).withValues(alpha: 0.80)
              : Colors.white.withValues(alpha: 0.55);
      final labelSize  = isCurrent ? 8.5 : (is1000m ? 8.0 : 7.5);

      if (isCurrent) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(bracketX + 10, pt.dy - 8, 44, 16),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFF1A3A1A).withValues(alpha: 0.85),
        );
      } else if (is1000m) {
        // 1000m: 하늘색 배경 박스
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(bracketX + 10, pt.dy - 8, 50, 16),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFF003A5A).withValues(alpha: 0.75),
        );
      }
      _txt(canvas, is1000m ? '1000m(특)' : '${d}m',
          Offset(bracketX + 32, pt.dy),
          labelColor, labelSize, bold: isCurrent || is1000m, centered: true);
    }
  }

  // 서울/부산경남 전체 출발선 (1000~2300m, 흐리게)
  // 도면 기준:
  //   · 우직선 (구간0): 1000m(특별경주), 1200m, 1300m, 1400m
  //   · 하단코너 (구간3): 1600m (코너 센터)
  //   · 좌직선 (구간2): GOAL + 1700m, 1800m, 1900m, 2000m
  //   · 상단코너 (구간1): 2300m
  void _drawSeoulAllStartLines(Canvas canvas, Rect tr) {
    const allDists = [1000, 1200, 1300, 1400, 1600, 1700, 1800, 1900, 2000, 2300];
    // 우직선에 위치하는 경주 (우직선 바깥 마커 별도 표시)
    const rightStraightDists = {1000, 1200, 1300, 1400};
    // 좌직선에 위치하는 경주
    const leftStraightDists  = {1700, 1800, 1900, 2000};
    const tw = 20.0;

    for (final d in allDists) {
      final bool isCurrent   = (d == distance);
      final bool isRightStr  = rightStraightDists.contains(d);
      final bool isLeftStr   = leftStraightDists.contains(d);
      final bool is1000m     = (d == 1000);
      final bool is1600m     = (d == 1600);
      final sp  = _TG.startP(d);
      final pt  = _TG.toPoint(sp, tr);
      final ang = _TG.toAngle(sp);
      final nx  = -sin(ang) * tw;
      final ny  =  cos(ang) * tw;

      // 횡단선 색상 및 두께
      final lineColor = isCurrent
          ? const Color(0xFFFFD700)
          : is1000m
              ? const Color(0xFF00BFFF).withValues(alpha: 0.55)  // 1000m: 하늘색 강조
              : is1600m
                  ? Colors.white.withValues(alpha: 0.38)          // 1600m 코너: 밝게
                  : isRightStr
                      ? Colors.white.withValues(alpha: 0.32)      // 우직선 단거리
                      : isLeftStr
                          ? Colors.white.withValues(alpha: 0.22)  // 좌직선 중거리
                          : Colors.white.withValues(alpha: 0.16); // 코너/기타
      final lineW = isCurrent ? 2.5
          : is1000m  ? 1.8
          : is1600m  ? 1.5
          : isRightStr ? 1.3
          : 0.9;

      canvas.drawLine(pt + Offset(nx, ny), pt - Offset(nx, ny),
          Paint()..color = lineColor..strokeWidth = lineW);

      // 라벨 위치: 법선 방향 × 2.1
      final labelOff = Offset(nx * 2.1, ny * 2.1);

      if (isCurrent) {
        // 현재 경주 출발선: 황금색 강조 + START Xm 박스
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: pt + labelOff + const Offset(0, -2), width: 72, height: 16),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFF0A2A0A).withValues(alpha: 0.88),
        );
        _txt(canvas, 'START ${d}m', pt + labelOff,
            const Color(0xFFFFD700), 8.0, bold: true, centered: true);
        // 구간 안내
        final seg = _TG.segment(sp);
        final segLabel = switch (seg) {
          _Seg.topStr  => '우직선',
          _Seg.botStr  => '좌직선',
          _Seg.cornerR => '하단코너',
          _Seg.cornerL => '상단코너',
        };
        _txt(canvas, segLabel, pt + labelOff + const Offset(0, 12),
            Colors.white.withValues(alpha: 0.55), 6.5, centered: true);
      } else if (is1000m) {
        // 1000m 특별경주: 하늘색 강조 표시
        _txt(canvas, '1000m', pt + labelOff,
            const Color(0xFF00BFFF).withValues(alpha: 0.80), 7.5,
            bold: true, centered: true);
        _txt(canvas, '(특별)', pt + labelOff + const Offset(0, 10),
            const Color(0xFF00BFFF).withValues(alpha: 0.55), 6.0, centered: true);
      } else if (isRightStr) {
        // 1200~1400m (우직선): 안쪽에 거리 표시
        _txt(canvas, '${d}m', pt + labelOff,
            Colors.white.withValues(alpha: 0.50), 7.5, centered: true);
      } else if (is1600m) {
        // 1600m (하단코너): 코너 마커
        _txt(canvas, '1600m', pt + labelOff,
            Colors.white.withValues(alpha: 0.55), 7.5, centered: true);
      } else if (isLeftStr) {
        // 1700~2000m (좌직선): 안쪽에 거리 표시
        _txt(canvas, '${d}m', pt + labelOff,
            Colors.white.withValues(alpha: 0.40), 7.0, centered: true);
      } else {
        // 2300m (상단코너) 등 기타
        _txt(canvas, '${d}m', pt + labelOff,
            Colors.white.withValues(alpha: 0.36), 7.0, centered: true);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  부산경남 전용 트랙 렌더링 — 2D 탑다운 평면 뷰
  //  도면 기반: 좌우 완벽 평행 직선 + 상하 정원형 반원 코너
  //  내측 표준 트랙 + 2200m 외측 대형 반원 이중 구조 시각화
  // ══════════════════════════════════════════════════════════════════════════

  // ── 2D 탑다운 오벌 경로 (정원형 반원 코너, 바깥으로 볼록) ──
  //
  // ══════════════════════════════════════════════════════════════
  //  _busanOvalPath — 완전 재작성 v5 (arcTo/bezier 전면 폐기)
  //
  //  ▸ 구조: 순수 lineTo 세그먼트 근사화 (반원 = 60분할 다각형)
  //  ▸ 상단 반원: 중심(cx, cy-hr) → 위로 볼록
  //  ▸ 하단 반원: 중심(cx, cy+hr) → 아래로 볼록
  //
  //  [모든 호 API 폐기 이유]
  //  Flutter Web(CanvasKit)에서 arcTo/addArc 모두 내부 winding 방향이
  //  플랫폼별 PathFillType 해석에 따라 달라질 수 있음.
  //  lineTo만 사용하면 winding이 완전히 예측 가능함.
  //
  //  [경로 조립 순서 — CW 시계방향, 위에서 내려다보는 탑다운]
  //  ① 우직선:  (cx+hw, cy+hr) → (cx+hw, cy-hr)   ↑  (남→북)
  //  ② 상단호:  CW 0→-π (우→위→좌)               위로 볼록 ✅
  //  ③ 좌직선:  (cx-hw, cy-hr) → (cx-hw, cy+hr)   ↓  (북→남)
  //  ④ 하단호:  CW π→0 (좌→아래→우)              아래로 볼록 ✅
  // ══════════════════════════════════════════════════════════════
  Path _busanOvalPath(double cx, double cy, double hw, double hr) {
    if (hw <= 0 || hr <= 0) return Path();
    const int steps = 60; // 반원을 60등분 → 충분히 부드러운 곡선
    final path = Path();

    // ① 우직선 시작점 (우하단)
    path.moveTo(cx + hw, cy + hr);
    // ② 우직선: 위쪽 방향
    path.lineTo(cx + hw, cy - hr);

    // ③ 상단 반원: CW, 오른쪽(0°) → 위(-90°) → 왼쪽(180°)
    //    angle: 0 → -π (CW = 음의 방향)
    //    중심: (cx, cy - hr)
    for (int i = 1; i <= steps; i++) {
      final a = -(pi * i / steps); // 0 → -π
      path.lineTo(cx + hw * cos(a), cy - hr + hw * sin(a));
    }
    // 상단 반원 끝점은 (cx - hw, cy - hr)

    // ④ 좌직선: 아래쪽 방향
    path.lineTo(cx - hw, cy + hr);

    // ⑤ 하단 반원: CW, 왼쪽(π) → 아래(-270°=아래) → 오른쪽(0°)
    //    angle: π → 0 (CW = π에서 감소하여 0으로)
    //    중심: (cx, cy + hr)
    for (int i = 1; i <= steps; i++) {
      final a = pi - (pi * i / steps); // π → 0
      path.lineTo(cx + hw * cos(a), cy + hr + hw * sin(a));
    }
    // 하단 반원 끝점은 (cx + hw, cy + hr) → close

    path.close();
    return path;
  }

  // ── 2D 탑다운 부산경남 트랙 메인 렌더링 ──
  void _drawBusanTrack(Canvas canvas, Size size, Rect tr) {
    final cx = tr.center.dx;
    final cy = tr.center.dy;
    final hw = tr.width  * _TGBusan.kHwFrac; // 코너 반지름 = 직선 가로 반폭
    final hr = tr.height * _TGBusan.kHrFrac; // 직선 반높이

    final trackW  = (hw * 0.28).clamp(16.0, 30.0); // 표준 트랙 폭
    final hwGrass = hw - trackW;                    // 내측 잔디 경계 반폭
    final hwOuter = hw + trackW * 0.9;              // 2200m 외측 경계 반폭
    final extR    = hw + trackW * 2.8;              // 2200m 외측 대형 반원 반지름

    // ── 경로 생성 ──
    final outerPath    = _busanOvalPath(cx, cy, hw,       hr);
    final innerPath    = _busanOvalPath(cx, cy, hwGrass,  hr);
    final outerRingPath= _busanOvalPath(cx, cy, hwOuter,  hr);
    final trackRing    = Path.combine(PathOperation.difference, outerPath, innerPath);
    final outerTrackRing = Path.combine(PathOperation.difference, outerRingPath, outerPath);

    final lt = _TGBusan.laneType(distance);

    // ━━━━ ① 내측 잔디 ━━━━
    canvas.drawPath(innerPath, Paint()..color = const Color(0xFF1A5A1A));
    _drawGrassStripesBusan(canvas, cx, cy, hwGrass, hr);

    // ━━━━ ② 내측 트랙 링 (전체 균일 색상) ━━━━
    canvas.drawPath(trackRing,
        Paint()..color = const Color(0xFFD4A055)..style = PaintingStyle.fill);

    // ━━━━ ③ 외측 확장 트랙 (2200m 도면의 대형 반원 구간) ━━━━
    canvas.drawPath(outerTrackRing,
        Paint()
          ..color = const Color(0xFFB8903A).withValues(
              alpha: lt == _TGBusan.kLaneOuter ? 0.78 : 0.20)
          ..style = PaintingStyle.fill);

    // ━━━━ ④ 더트 텍스처 ━━━━
    final rng = Random(44444);
    canvas.save();
    canvas.clipPath(trackRing);
    for (int i = 0; i < 280; i++) {
      final t   = rng.nextDouble();
      final off = (rng.nextDouble() - 0.5) * trackW * 0.7;
      final pt  = _TGBusan.toPoint(t, tr, clusterOff: off);
      final gs  = 0.5 + rng.nextDouble() * 1.5;
      canvas.drawOval(
        Rect.fromCenter(center: pt, width: gs * 2, height: gs),
        Paint()..color = Color.lerp(const Color(0xFFDDBA88), const Color(0xFF8B6035),
            rng.nextDouble())!.withValues(alpha: 0.18 + rng.nextDouble() * 0.28),
      );
    }
    canvas.restore();

    // ━━━━ ⑤ 경계선 ━━━━
    canvas.drawPath(outerPath, Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0);
    canvas.drawPath(innerPath, Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    canvas.drawPath(outerRingPath, Paint()
      ..color = lt == _TGBusan.kLaneOuter
          ? const Color(0xFFFFAB40).withValues(alpha: 0.82)
          : Colors.white.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = lt == _TGBusan.kLaneOuter ? 2.0 : 1.0);

    // ━━━━ ⑥ 1800~2000m 내측 하단코너 경로 강조 ━━━━
    if (lt == _TGBusan.kLaneInner) {
      final paint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.68)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final cornOff = -trackW * 0.35;
      Offset? prev;
      for (int i = 0; i <= 20; i++) {
        final pp = _TGBusan.p4 + (1.0 - _TGBusan.p4) * (i / 20.0);
        final pt = _TGBusan.toPoint(pp, tr, clusterOff: cornOff);
        if (prev != null) canvas.drawLine(prev, pt, paint);
        prev = pt;
      }
      // 화살촉
      final pEnd = _TGBusan.toPoint(0.995, tr, clusterOff: cornOff);
      final pPre = _TGBusan.toPoint(0.985, tr, clusterOff: cornOff);
      final ha = atan2(pEnd.dy - pPre.dy, pEnd.dx - pPre.dx);
      canvas.drawLine(pEnd, pEnd + Offset(cos(ha+2.5)*7, sin(ha+2.5)*7), paint..strokeWidth=2.0);
      canvas.drawLine(pEnd, pEnd + Offset(cos(ha-2.5)*7, sin(ha-2.5)*7), paint..strokeWidth=2.0);
    }

    // ━━━━ ⑦ 2200m 외측 대형 하단코너 경로 강조 (도면의 504m 대형 반원) ━━━━
    if (lt == _TGBusan.kLaneOuter) {
      final paint = Paint()
        ..color = const Color(0xFFFFAB40).withValues(alpha: 0.82)
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      Offset? prev;
      for (int i = 0; i <= 24; i++) {
        final ang = pi + (pi * i / 24.0);
        final pt  = Offset(cx + extR * cos(ang), cy + hr + extR * sin(ang));
        if (prev != null) canvas.drawLine(prev, pt, paint);
        prev = pt;
      }
      // 화살촉 우측 끝
      final pEnd = Offset(cx + extR, cy + hr);
      final pPre = Offset(cx + extR * cos(pi * 23.0/24 + pi),
                          cy + hr + extR * sin(pi * 23.0/24 + pi));
      final ha = atan2(pEnd.dy - pPre.dy, pEnd.dx - pPre.dx);
      canvas.drawLine(pEnd, pEnd + Offset(cos(ha+2.5)*9, sin(ha+2.5)*9), paint..strokeWidth=2.5);
      canvas.drawLine(pEnd, pEnd + Offset(cos(ha-2.5)*9, sin(ha-2.5)*9), paint..strokeWidth=2.5);
      // 레이블
      _txt(canvas, '외측코너 504m',
          Offset(cx, cy + hr + extR + 14),
          const Color(0xFFFFAB40).withValues(alpha: 0.88), 8.0,
          bold: true, centered: true);
    }

    // ━━━━ ⑧ 내측 텍스트 ━━━━
    _txt(canvas, '${distance}m 레이스',
        Offset(cx, cy - hr * 0.28),
        Colors.white.withValues(alpha: 0.52), 10, centered: true);
    _txt(canvas, '부산경남 경마공원',
        Offset(cx, cy + hr * 0.28),
        Colors.white.withValues(alpha: 0.38), 9, centered: true);
    _txt(canvas, '↻ CW', Offset(cx, cy),
        const Color(0xFF81C784).withValues(alpha: 0.40), 10, bold: true, centered: true);
    _txt(canvas, '상단코너', Offset(cx, cy - hr - hw * 0.55),
        Colors.white.withValues(alpha: 0.32), 7.5, centered: true);
    _txt(canvas, '하단코너', Offset(cx, cy + hr + hw * 0.55),
        Colors.white.withValues(alpha: 0.32), 7.5, centered: true);

    // ━━━━ ⑨ 직선 레이블 ━━━━
    _txt(canvas, '우직선  500m',
        Offset(tr.right + 6, cy - 6),
        Colors.white.withValues(alpha: 0.40), 7.5);
    _txt(canvas, '↑1600~1000m',
        Offset(tr.right + 6, cy + 8),
        Colors.white.withValues(alpha: 0.28), 6.5);
    _txt(canvas, '좌직선  460m',
        Offset(tr.left - 76, cy - 6),
        Colors.white.withValues(alpha: 0.40), 7.5);
    final routeLabel = switch (lt) {
      _TGBusan.kLaneInner => '1800~2000m (내측코너)',
      _TGBusan.kLaneOuter => '2200m (외측 대형코너)',
      _ => 'GOAL·1800~2200m',
    };
    _txt(canvas, routeLabel,
        Offset(tr.left - 82, cy + 8),
        lt == _TGBusan.kLaneInner
            ? const Color(0xFF00E5FF).withValues(alpha: 0.60)
            : lt == _TGBusan.kLaneOuter
                ? const Color(0xFFFFAB40).withValues(alpha: 0.60)
                : Colors.white.withValues(alpha: 0.30),
        6.0);
  }

  // 부산경남 잔디 줄무늬 (내측) — hw만 비율로 줄이고 hr은 고정
  void _drawGrassStripesBusan(Canvas canvas, double cx, double cy, double hw, double hr) {
    for (int i = 0; i < 4; i++) {
      final h2 = hw * (0.35 + i * 0.18); // hw만 비율 변경
      if (i.isEven) {
        canvas.drawPath(_busanOvalPath(cx, cy, h2, hr), Paint() // hr 고정
          ..color = const Color(0xFF154A15).withValues(alpha: 0.55)
          ..style = PaintingStyle.fill);
      }
    }
  }

  // ── 부산경남 거리 마커 (GOAL 기준 역산) ──
  void _drawBusanMarkers(Canvas canvas, Size size, Rect tr) {
    final dists = [200, 400, 600, 800, 1000, 1200, 1400];
    final gp = _TGBusan.goalP;
    for (final d in dists) {
      if (d >= distance) continue;
      final markerP = (gp - d.toDouble() / _TGBusan.total + 10.0) % 1.0;
      final pt  = _TGBusan.toPoint(markerP, tr);
      final ang = _TGBusan.toAngle(markerP);
      final nx  = -sin(ang) * 16.0;
      final ny  =  cos(ang) * 16.0;
      canvas.drawLine(pt + Offset(nx, ny), pt - Offset(nx, ny),
          Paint()..color = Colors.white.withValues(alpha: 0.3)..strokeWidth = 1.0);
      _txt(canvas, '${d}m', pt + Offset(nx * 1.8, ny * 1.8 - 4),
          Colors.white.withValues(alpha: 0.5), 7.5, centered: true);
    }
  }

  // ── 부산경남 출발선 + GOAL 종합 ──
  void _drawBusanStartFinishLines(Canvas canvas, Size size, Rect tr) {
    final lt = _TGBusan.laneType(distance);

    // ① 전체 출발선 (흐리게)
    _drawBusanAllStartLines(canvas, tr);

    // ② GOAL 결승선 (체크무늬 + 빨간 표지판) — 좌직선 하단 75% 고정
    const tw = 26.0;
    final gpp  = _TGBusan.goalP % 1.0;
    final gpt  = _TGBusan.toPoint(gpp, tr);
    final gang = _TGBusan.toAngle(gpp);
    // 좌직선: gang=π/2 → 법선 = 좌우 방향
    final gnx  = -sin(gang) * (tw + 8);
    final gny  =  cos(gang) * (tw + 8);

    // 체크무늬 결승선
    for (int i = 0; i < 10; i++) {
      final ptA = gpt + Offset(gnx, gny) * (1 - i / 10.0 * 2);
      final ptB = gpt + Offset(gnx, gny) * (1 - (i + 1) / 10.0 * 2);
      canvas.drawLine(ptA, ptB, Paint()
        ..color = i.isEven ? Colors.white : Colors.red
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.butt);
    }
    // GOAL 표지판
    final goalTag = gpt + Offset(gnx * 2.8, gny * 2.8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: goalTag, width: 50, height: 20),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.red,
    );
    _txt(canvas, 'GOAL', goalTag, Colors.white, 10, bold: true, centered: true);

    // 2200m 전용: GOAL 선 위에 "통과 후 계속" 표시 (주황색 작은 배너)
    if (lt == _TGBusan.kLaneOuter) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: goalTag + const Offset(0, -18), width: 58, height: 14),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFFFF6D00).withValues(alpha: 0.85),
      );
      _txt(canvas, '→ 외측코너', goalTag + const Offset(0, -18),
          Colors.white, 7.5, bold: true, centered: true);
    }
    // 1800~2000m: GOAL 선 옆에 "내측코너 경유" 표시 (시안색 작은 배너)
    if (lt == _TGBusan.kLaneInner) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: goalTag + const Offset(0, -18), width: 60, height: 14),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFF006064).withValues(alpha: 0.85),
      );
      _txt(canvas, '내측코너 경유', goalTag + const Offset(0, -18),
          Colors.white, 7.5, bold: true, centered: true);
    }

    // ③ 현재 경주 출발선 강조 (황금색)
    final spp  = startP % 1.0;
    final spt  = _TGBusan.toPoint(spp, tr);
    final sang = _TGBusan.toAngle(spp);
    final snx  = -sin(sang) * (tw + 4);
    final sny  =  cos(sang) * (tw + 4);
    canvas.drawLine(spt + Offset(snx, sny), spt - Offset(snx, sny),
        Paint()..color = Colors.white..strokeWidth = 3.0);
    canvas.drawLine(spt + Offset(snx, sny), spt - Offset(snx, sny),
        Paint()..color = const Color(0xFFFFD700)..strokeWidth = 2.0);

    // ④ 우직선 바깥 마커 (1000~1600m)
    _drawBusanRightStraightMarkers(canvas, tr);
  }

  // ── 부산경남 전체 출발선 (모든 거리, 흐리게) ──
  void _drawBusanAllStartLines(Canvas canvas, Rect tr) {
    // 부산경남 경주 거리 전체 (1700m 추가)
    const allDists = [1000, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900, 2000, 2200];
    // 우직선 (1000~1600m)
    const rightDists = {1000, 1200, 1300, 1400, 1500, 1600};
    // 좌직선 (1700~2200m)
    const leftDists  = {1700, 1800, 1900, 2000, 2200};
    const tw = 20.0;

    for (final d in allDists) {
      final bool isCurrent  = (d == distance);
      final bool isRight    = rightDists.contains(d);
      final bool isLeft     = leftDists.contains(d);
      final bool is1000m    = (d == 1000);
      final bool is1500m    = (d == 1500);
      final bool is1600m    = (d == 1600);
      final bool is1700m    = (d == 1700); // 좌직선 GOAL 동일선 (1바퀴)
      final sp  = _TGBusan.startP(d);
      final pt  = _TGBusan.toPoint(sp, tr);
      final ang = _TGBusan.toAngle(sp);
      final nx  = -sin(ang) * tw;
      final ny  =  cos(ang) * tw;

      // 색상/두께
      final lineColor = isCurrent
          ? const Color(0xFFFFD700)
          : is1000m
              ? const Color(0xFF00BFFF).withValues(alpha: 0.55)
              : is1700m
                  ? const Color(0xFF81C784).withValues(alpha: 0.50) // 1700m: 연두 (GOAL 동선)
                  : is1600m || is1500m
                      ? Colors.white.withValues(alpha: 0.38)
                      : isRight
                          ? Colors.white.withValues(alpha: 0.32)
                          : isLeft
                              ? Colors.white.withValues(alpha: 0.22)
                              : Colors.white.withValues(alpha: 0.16);
      final lineW = isCurrent ? 2.5
          : is1000m  ? 1.8
          : is1700m  ? 1.6
          : is1600m || is1500m ? 1.5
          : isRight  ? 1.3
          : 0.9;

      canvas.drawLine(pt + Offset(nx, ny), pt - Offset(nx, ny),
          Paint()..color = lineColor..strokeWidth = lineW);

      final labelOff = Offset(nx * 2.1, ny * 2.1);

      if (isCurrent) {
        // 현재 경주 출발선 강조
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: pt + labelOff + const Offset(0, -2), width: 72, height: 16),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFF0A2A0A).withValues(alpha: 0.88),
        );
        _txt(canvas, 'START ${d}m', pt + labelOff,
            const Color(0xFFFFD700), 8.0, bold: true, centered: true);
        final seg = _TGBusan.segment(sp);
        final segLabel = switch (seg) {
          _Seg.topStr  => '우직선',
          _Seg.botStr  => '좌직선',
          _Seg.cornerR => '하단코너',
          _Seg.cornerL => '상단코너',
        };
        _txt(canvas, segLabel, pt + labelOff + const Offset(0, 12),
            Colors.white.withValues(alpha: 0.55), 6.5, centered: true);
      } else if (is1000m) {
        _txt(canvas, '1000m', pt + labelOff,
            const Color(0xFF00BFFF).withValues(alpha: 0.80), 7.5,
            bold: true, centered: true);
        _txt(canvas, '(특별)', pt + labelOff + const Offset(0, 10),
            const Color(0xFF00BFFF).withValues(alpha: 0.55), 6.0, centered: true);
      } else if (is1700m) {
        _txt(canvas, '1700m', pt + labelOff,
            const Color(0xFF81C784).withValues(alpha: 0.85), 7.5,
            bold: true, centered: true);
        _txt(canvas, '(GOAL선)', pt + labelOff + const Offset(0, 10),
            const Color(0xFF81C784).withValues(alpha: 0.60), 6.0, centered: true);
      } else if (isRight) {
        _txt(canvas, '${d}m', pt + labelOff,
            Colors.white.withValues(alpha: 0.50), 7.5, centered: true);
      } else if (isLeft) {
        _txt(canvas, '${d}m', pt + labelOff,
            Colors.white.withValues(alpha: 0.40), 7.0, centered: true);
      } else {
        _txt(canvas, '${d}m', pt + labelOff,
            Colors.white.withValues(alpha: 0.36), 7.0, centered: true);
      }
    }
  }

  // ── 부산경남: 우직선 오른쪽 바깥 브라켓 안내 마커 (1000~1600m) ──
  void _drawBusanRightStraightMarkers(Canvas canvas, Rect tr) {
    final cx = tr.center.dx;
    // ★ toPoint/_drawBusanTrack 과 동일한 hw (kHwFrac=0.38)
    final hw = tr.width * _TGBusan.kHwFrac;
    const outerOffX = 40.0; // 트랙 오른쪽 바깥 여백

    // 우직선 출발선 목록 (화면 아래→위 순: 1500→1200→1300→1400→1000)
    // CW 우직선: 아래→위, p 작을수록 위(더 먼 거리), p 클수록 아래(짧은 거리)
    final dists = [1600, 1500, 1400, 1300, 1200, 1000]; // 화면 아래→위 순

    final bracketX = cx + hw + outerOffX;

    // 1200~1500m 구간 브라켓 (통상 단거리 그룹)
    final p1200  = _TGBusan.startP(1200);
    final p1500  = _TGBusan.startP(1500);
    final pt1200 = _TGBusan.toPoint(p1200 % 1.0, tr);
    final pt1500 = _TGBusan.toPoint(p1500 % 1.0, tr);
    canvas.drawLine(
      Offset(bracketX, pt1200.dy),
      Offset(bracketX, pt1500.dy),
      Paint()..color = Colors.white.withValues(alpha: 0.22)..strokeWidth = 1.0,
    );

    // 1000m 별도 점선 마커 (특별경주 전용)
    final p1000  = _TGBusan.startP(1000);
    final pt1000 = _TGBusan.toPoint(p1000 % 1.0, tr);
    canvas.drawLine(
      Offset(cx + hw, pt1000.dy),
      Offset(bracketX + 4, pt1000.dy),
      Paint()
        ..color = const Color(0xFF00BFFF).withValues(alpha: 0.45)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    // 1600m: 하단코너 전 위치 (우직선 하단부 — 별도 점선)
    final p1600  = _TGBusan.startP(1600);
    final pt1600 = _TGBusan.toPoint(p1600 % 1.0, tr);
    // 1600m은 하단코너 직전이라 y가 크므로 하단코너 브라켓 아래에 별도 표시
    canvas.drawLine(
      Offset(cx + hw, pt1600.dy),
      Offset(bracketX + 4, pt1600.dy),
      Paint()
        ..color = Colors.orange.withValues(alpha: 0.40)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    // 각 거리 눈금선 + 레이블
    for (final d in dists) {
      final sp = _TGBusan.startP(d);
      final pt = _TGBusan.toPoint(sp % 1.0, tr);
      final isCurrent = (d == distance);
      final is1000m   = (d == 1000);
      final is1600m   = (d == 1600);

      final lineColor = isCurrent
          ? const Color(0xFFFFD700)
          : is1000m
              ? const Color(0xFF00BFFF).withValues(alpha: 0.50)
              : is1600m
                  ? Colors.orange.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.32);
      final lineW = isCurrent ? 2.0 : (is1000m || is1600m ? 1.4 : 1.0);

      canvas.drawLine(
        Offset(cx + hw, pt.dy),
        Offset(bracketX + 6, pt.dy),
        Paint()..color = lineColor..strokeWidth = lineW,
      );

      final labelColor = isCurrent
          ? const Color(0xFFFFD700)
          : is1000m
              ? const Color(0xFF00BFFF).withValues(alpha: 0.80)
              : is1600m
                  ? Colors.orange.withValues(alpha: 0.80)
                  : Colors.white.withValues(alpha: 0.55);
      final labelSize = isCurrent ? 8.5 : (is1000m || is1600m ? 8.0 : 7.5);

      if (isCurrent) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(bracketX + 10, pt.dy - 8, 44, 16),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFF1A3A1A).withValues(alpha: 0.85),
        );
      } else if (is1000m) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(bracketX + 10, pt.dy - 8, 50, 16),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFF003A5A).withValues(alpha: 0.75),
        );
      } else if (is1600m) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(bracketX + 10, pt.dy - 8, 44, 16),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFF3A2A00).withValues(alpha: 0.75),
        );
      }
      _txt(canvas, is1000m ? '1000m(특)' : '${d}m',
          Offset(bracketX + 32, pt.dy),
          labelColor, labelSize, bold: isCurrent || is1000m, centered: true);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  제주 전용 트랙 렌더링 — 실제 도면 기반 세로형 오벌 CCW
  // ══════════════════════════════════════════════════════════════════════════

  // 제주 트랙 세로형 오벌 경로
  // 우직선(긴), 하단코너, 좌직선, 상단코너  — CCW 반시계
  // hw = 가로 반폭(코너 반지름), vr = 세로 반높이
  Path _jejuOvalPath(double cx, double cy, double hw, double vr) {
    if (hw <= 0 || vr <= 0) return Path();
    final path = Path();
    // 우직선 시작점 (우상단)
    path.moveTo(cx + hw, cy - vr);
    // 우직선: 위→아래
    path.lineTo(cx + hw, cy + vr);
    // 하단 코너: 중심(cx, cy+vr), 오른쪽(0°)→왼쪽(180°) CCW
    path.arcTo(
      Rect.fromCenter(center: Offset(cx, cy + vr), width: hw * 2, height: hw * 2),
      0, pi, false, // 0 → π (CCW: 오른쪽→아래→왼쪽)
    );
    // 좌직선: 아래→위
    path.lineTo(cx - hw, cy - vr);
    // 상단 코너: 중심(cx, cy-vr), 왼쪽(180°)→오른쪽(360°) CCW
    path.arcTo(
      Rect.fromCenter(center: Offset(cx, cy - vr), width: hw * 2, height: hw * 2),
      pi, pi, false, // π → 2π (CCW: 왼쪽→위→오른쪽)
    );
    path.close();
    return path;
  }

  // ── 제주 단일 트랙 (CCW 세로형, 정원형 코너) ──
  //
  // [렌더링 전략 — 서울/부산과 동일 방식]
  // ① hw만 줄여서 innerPath 생성 (vr 고정!) → 코너/직선 색상 완전 연속
  // ② 단일 트랙 링 = PathOperation.difference(outerPath, innerPath)
  // ③ 직선 구간 하이라이트 (세로 띠, clipPath 내부)
  // ④ 더트 텍스처 (트랙 전체, clipPath 내부)
  // ⑤ 경계선 2개 (외곽+내측) — 이중/삼중 선 없음
  //
  // ★ hw = 0.38*width, vr = 0.43*height — toPoint와 완전 동일
  // ★ innerPath: hw-trackW, vr 고정 → 코너 형태 일치 보장
  void _drawJejuTrack(Canvas canvas, Size size, Rect tr) {
    final cx = tr.center.dx;
    final cy = tr.center.dy;
    final hw  = tr.width  * 0.38;  // 가로 반폭 (= toPoint 동일)
    final vr  = tr.height * 0.43;  // 세로 반높이 고정 (= toPoint 동일)

    // 단일 트랙 폭 (hw만 변경, vr 항상 고정)
    final trackW  = (hw * 0.28).clamp(14.0, 26.0);
    final hwGrass = hw - trackW; // 내측 잔디 경계 hw

    // ━━━━ 오벌 경로 (vr 고정, hw만 변경) ━━━━
    // ★ _jejuOvalPath(cx, cy, hw, vr) — vr 파라미터를 항상 동일하게 고정
    final outerPath = _jejuOvalPath(cx, cy, hw,       vr); // 외측 경계
    final innerPath = _jejuOvalPath(cx, cy, hwGrass,  vr); // 내측 잔디 경계 (vr 고정!)
    final trackRing = Path.combine(PathOperation.difference, outerPath, innerPath);

    // ━━━━ ① 내측 잔디 ━━━━
    canvas.drawPath(innerPath, Paint()..color = const Color(0xFF1B4A1B));
    // 잔디 줄무늬 (hw만 줄이고 vr 고정)
    for (int i = 0; i < 4; i++) {
      final h2 = hwGrass * (0.4 + i * 0.18);
      if (i.isEven) {
        canvas.drawPath(_jejuOvalPath(cx, cy, h2, vr), Paint()
          ..color = const Color(0xFF154A15).withValues(alpha: 0.55));
      }
    }

    // ━━━━ ② 트랙 단색 베이스 (코너/직선 모두 연속) ━━━━
    canvas.drawPath(trackRing,
        Paint()..color = const Color(0xFFBB8B40)..style = PaintingStyle.fill);

    // ━━━━ ③ 직선 구간 하이라이트 (세로 띠) ━━━━
    canvas.save();
    canvas.clipPath(trackRing);
    // 우직선 (cx+hwGrass ~ cx+hw)
    canvas.drawRect(
      Rect.fromLTRB(cx + hwGrass, cy - vr, cx + hw, cy + vr),
      Paint()..color = const Color(0xFFD4A055).withValues(alpha: 0.55),
    );
    // 좌직선 (cx-hw ~ cx-hwGrass)
    canvas.drawRect(
      Rect.fromLTRB(cx - hw, cy - vr, cx - hwGrass, cy + vr),
      Paint()..color = const Color(0xFFD4A055).withValues(alpha: 0.55),
    );
    canvas.restore();

    // ━━━━ ④ 더트 텍스처 (트랙 전체, 코너 포함) ━━━━
    final rng = Random(99999);
    canvas.save();
    canvas.clipPath(trackRing);
    for (int i = 0; i < 280; i++) {
      final t = rng.nextDouble();
      final off = (rng.nextDouble() - 0.5) * trackW * 0.7;
      final pt = _TGJeju.toPoint(t, tr, clusterOff: off);
      final gs = 0.6 + rng.nextDouble() * 1.6;
      canvas.drawOval(
        Rect.fromCenter(center: pt, width: gs * 2, height: gs),
        Paint()..color = Color.lerp(const Color(0xFFDDBA88), const Color(0xFF8B6035),
            rng.nextDouble())!.withValues(alpha: 0.25 + rng.nextDouble() * 0.35),
      );
    }
    canvas.restore();

    // ━━━━ ⑤ 경계선 (2선 단순화) ━━━━
    canvas.drawPath(outerPath, Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0);
    canvas.drawPath(innerPath, Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);

    // ━━━━ ⑥ 코너 하이라이트 (상단/하단 반원) ━━━━
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy + vr), width: hw * 2.6, height: hw * 2.6),
      0, pi, false,
      Paint()..color = const Color(0xFFFFAA00).withValues(alpha: 0.08)..style = PaintingStyle.fill,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy - vr), width: hw * 2.6, height: hw * 2.6),
      pi, pi, false,
      Paint()..color = const Color(0xFFFFAA00).withValues(alpha: 0.08)..style = PaintingStyle.fill,
    );
    _txt(canvas, '하단코너', Offset(cx, cy + vr + hw * 0.55),
        Colors.white.withValues(alpha: 0.35), 7.5, centered: true);
    _txt(canvas, '상단코너', Offset(cx, cy - vr - hw * 0.55),
        Colors.white.withValues(alpha: 0.35), 7.5, centered: true);

    // ━━━━ ⑦ 내측 텍스트 ━━━━
    _txt(canvas, '${distance}m 레이스',
        Offset(cx, cy - vr * 0.25),
        Colors.white.withValues(alpha: 0.5), 10, centered: true);
    _txt(canvas, '제주 경마공원',
        Offset(cx, cy + vr * 0.25),
        Colors.white.withValues(alpha: 0.35), 9, centered: true);
    _txt(canvas, '↺ CCW', Offset(cx, cy),
        const Color(0xFF81C784).withValues(alpha: 0.4), 9, bold: true, centered: true);

    // ━━━━ ⑧ 직선 레이블 ━━━━
    _txt(canvas, '우직선 493.7m',
        Offset(cx + hw + trackW + 18, cy),
        Colors.white.withValues(alpha: 0.35), 7, centered: true);
    _txt(canvas, '좌직선 293.7m',
        Offset(cx - hw - trackW - 18, cy),
        Colors.white.withValues(alpha: 0.30), 7, centered: true);
  }

  void _drawJejuMarkers(Canvas canvas, Size size, Rect tr) {
    // 제주 거리 마커: GOAL 기준 역산 (200m, 400m 잔여거리 마커)
    final markDists = [200, 400];
    final gp = _TGJeju.goalP;
    for (final d in markDists) {
      if (d >= distance) continue;
      final markerP = (gp - d.toDouble() / _TGJeju.total + 10.0) % 1.0;
      final pt  = _TGJeju.toPoint(markerP, tr);
      final ang = _TGJeju.toAngle(markerP);
      final nx  = -sin(ang) * 14.0;
      final ny  =  cos(ang) * 14.0;
      canvas.drawLine(pt + Offset(nx, ny), pt - Offset(nx, ny),
          Paint()..color = Colors.white.withValues(alpha: 0.35)..strokeWidth = 1.2);
      _txt(canvas, '${d}m', pt + Offset(nx * 2.0, ny * 2.0),
          Colors.white.withValues(alpha: 0.55), 7.5, centered: true);
    }
  }

  // 제주 모든 출발선 표시 (역산 기준: 800m~1610m)
  // ★ 새 설계: startP = (goalP - d/total + 2.0) % 1.0
  //   1610m: 좌직선 13% (GOAL과 다른 위치 — 1바퀴+210m 출발)
  //   1400m: 좌직선 85% (= GOAL 위치, 1바퀴 출발)
  //   1000m~1200m: 우직선 / 상단코너
  //   800m/900m: 우직선
  void _drawJejuAllStartLines(Canvas canvas, Size size, Rect tr) {
    // 제주 공식 경주거리 목록
    const allDists = [800, 900, 1000, 1110, 1200, 1300, 1400, 1610];
    const tw = 18.0;

    for (final d in allDists) {
      final bool isCurrentStart = (d == distance);

      // 해당 거리의 출발선 진행률 (goalP 역산)
      final sp = _TGJeju.startP(d);
      final pt  = _TGJeju.toPoint(sp, tr);
      final ang = _TGJeju.toAngle(sp);
      final nx  = -sin(ang) * tw;
      final ny  =  cos(ang) * tw;

      // 1400m 출발선은 GOAL 위치와 동일 (별도 처리)
      if (d == 1400 && distance != 1400) continue;

      // 선 색상: 현재 경주 출발선=황금색, 나머지=흰색 반투명
      final lineColor = isCurrentStart
          ? const Color(0xFFFFD700)
          : Colors.white.withValues(alpha: 0.22);
      final lineW = isCurrentStart ? 2.5 : 1.0;

      canvas.drawLine(pt + Offset(nx, ny), pt - Offset(nx, ny),
          Paint()..color = lineColor..strokeWidth = lineW);

      // 라벨 위치: 트랙 바깥(우직선→오른쪽, 좌직선→왼쪽, 코너→바깥)
      final labelOffset = Offset(nx * 2.0, ny * 2.0);
      final labelColor = isCurrentStart
          ? const Color(0xFFFFD700)
          : Colors.white.withValues(alpha: 0.40);
      final labelSize = isCurrentStart ? 8.5 : 7.0;

      // 현재 출발선이면 박스 배경 + 구간 안내 추가
      if (isCurrentStart) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: pt + labelOffset + const Offset(0, -2), width: 62, height: 16),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFF0A2A0A).withValues(alpha: 0.88),
        );
        _txt(canvas, 'START ${d}m', pt + labelOffset,
            labelColor, labelSize, bold: true, centered: true);
        // 구간 안내
        final seg = _TGJeju.segment(sp);
        final segLabel = switch (seg) {
          _Seg.topStr  => '우직선',
          _Seg.botStr  => '좌직선',
          _Seg.cornerR => '하단코너',
          _Seg.cornerL => '상단코너',
        };
        _txt(canvas, segLabel,
            pt + labelOffset + const Offset(0, 12),
            Colors.white.withValues(alpha: 0.55), 6.5, centered: true);
      } else {
        _txt(canvas, '${d}m', pt + labelOffset,
            labelColor, labelSize, centered: true);
      }
    }
  }

  void _drawJejuStartFinishLines(Canvas canvas, Size size, Rect tr) {
    const tw = 24.0;

    // ── ① 모든 출발선 표시 (800m~1400m, 흐리게) ──
    _drawJejuAllStartLines(canvas, size, tr);

    // ── ② 결승선 (GOAL) — 좌직선 85% (goalP = 0.7497) ──
    //   ★ 새 설계: GOAL은 _TGJeju.goalP 고정 (1400m 출발선 위치와 동일)
    //   1610m 출발선 = goalP - 1610/1400 + 2 = 0.5997 (좌직선 13%) ← GOAL과 다른 위치
    final gpp  = _TGJeju.goalP % 1.0;
    final gpt  = _TGJeju.toPoint(gpp, tr);
    final gang = _TGJeju.toAngle(gpp);
    // 좌직선 수직 방향
    final gnx  = -sin(gang) * (tw + 8);
    final gny  =  cos(gang) * (tw + 8);

    // 체크무늬 결승선 (진하게)
    for (int i = 0; i < 10; i++) {
      final t2 = i / 10.0;
      final t3 = (i + 1) / 10.0;
      final ptA = gpt + Offset(gnx, gny) * (1 - t2 * 2);
      final ptB = gpt + Offset(gnx, gny) * (1 - t3 * 2);
      canvas.drawLine(ptA, ptB, Paint()
        ..color = i.isEven ? Colors.white : Colors.red
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.butt);
    }

    // GOAL 표지판 (좌직선 바깥=왼쪽)
    final goalTagOffset = Offset(gnx * 2.8, gny * 2.8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: gpt + goalTagOffset, width: 52, height: 20),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.red,
    );
    _txt(canvas, 'GOAL', gpt + goalTagOffset,
        Colors.white, 10, bold: true, centered: true);

    // 1400m 출발선 = GOAL 위치 안내 (1400m 경주일 때만)
    if (distance == 1400) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: gpt + goalTagOffset + const Offset(0, 14), width: 52, height: 14),
          const Radius.circular(3),
        ),
        Paint()..color = Colors.red.withValues(alpha: 0.75),
      );
      _txt(canvas, '1400m START', gpt + goalTagOffset + const Offset(0, 14),
          Colors.white.withValues(alpha: 0.9), 7, bold: true, centered: true);
    }

    // ── ③ 현재 경주 출발선 (강조) ──
    // _drawJejuAllStartLines에서 현재 거리 = 황금색 강조선으로 이미 표시됨
    // 1400m 출발선은 GOAL 위치이므로 별도 표시 불필요
    if (distance != 1400) {
      final spp  = startP % 1.0;
      final spt  = _TGJeju.toPoint(spp, tr);
      final sang = _TGJeju.toAngle(spp);
      final snx  = -sin(sang) * (tw + 4);
      final sny  =  cos(sang) * (tw + 4);

      // 황금색 출발선 (강조 — 두 줄로 두께감)
      canvas.drawLine(spt + Offset(snx, sny), spt - Offset(snx, sny),
          Paint()..color = Colors.white..strokeWidth = 3.0);
      canvas.drawLine(spt + Offset(snx, sny), spt - Offset(snx, sny),
          Paint()..color = const Color(0xFFFFD700)..strokeWidth = 2.0);
    }
  }

  // ── 말 전체 렌더 (Round 9: gridLane 기반 clusterOff 매핑) ──
  void _drawHorses(Canvas canvas, Size size, Rect tr) {
    // 세로형 트랙: 트랙 너비(단축) 기준 아이콘 스케일
    final iconScale = (tr.width / 160.0).clamp(0.55, 1.0);

    // prog 순으로 정렬 (뒤에 있는 말이 앞에 그려지도록 역순)
    final sorted = [...horses]..sort((a, b) => a.prog.compareTo(b.prog));
    for (final h in sorted) {
      final pp  = h.prog % 1.0;

      // Grid → clusterOff 렌더링 매핑
      final Offset pt;
      final double ang;
      if (isJeju) {
        pt  = _TGJeju.toPoint(pp, tr, clusterOff: h.clusterOff);
        ang = _TGJeju.toAngle(pp);
      } else if (isBusan) {
        // ── 부산경남: 레인 타입별 clusterOff 조정 ──
        // 하단코너(구간3: pp >= p4) 진입 시 내측/외측 레인 분리
        final isBottomCorner = (pp >= _TGBusan.p4);
        double busanOff = h.clusterOff;
        if (h.busanLane == _TGBusan.kLaneInner && isBottomCorner) {
          // 내측 루트 (1800~2000m): 하단코너 안쪽으로 이동 (clusterOff 음수 = 안쪽)
          busanOff = h.clusterOff - 3.0;
        } else if (h.busanLane == _TGBusan.kLaneOuter && isBottomCorner) {
          // 외측 루트 (2200m): 하단코너 바깥쪽으로 이동 (clusterOff 양수 = 바깥쪽)
          busanOff = h.clusterOff + 3.0;
        }
        pt  = _TGBusan.toPoint(pp, tr, clusterOff: busanOff);
        ang = _TGBusan.toAngle(pp);
      } else {
        pt  = _TG.toPoint(pp, tr, clusterOff: h.clusterOff, isCW: false);
        ang = _TG.toAngle(pp, isCW: false);
      }
      _drawHorseIcon(canvas, pt, ang, h, scale: iconScale);
    }

    _drawLiveRanking(canvas, size);
  }

  // ── 말 아이콘 ──
  void _drawHorseIcon(Canvas canvas, Offset pos, double angle,
      _Horse h, {double scale = 1.0}) {
    final cd    = HorseCapColors.getCapData(h.entry.gateNo);
    final bodyR = 7.5 * scale;
    final headR = bodyR * 0.52;

    if (h.boostGlow > 0.05) {
      canvas.drawCircle(pos, bodyR * 2.5,
          Paint()
            ..color = const Color(0xFFFFD700).withValues(alpha: h.boostGlow * 0.35)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, bodyR * 1.6));
    }

    if (h.spurtFading) {
      canvas.drawCircle(pos, bodyR * 2.0,
          Paint()
            ..color = Colors.red.withValues(alpha: 0.15 + glowVal * 0.1)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, bodyR * 1.2));
    }

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);

    canvas.drawCircle(Offset(1.0, 1.5), bodyR,
        Paint()..color = Colors.black.withValues(alpha: 0.4));
    canvas.drawCircle(Offset.zero, bodyR, Paint()..color = cd.bg);

    if (cd.stripe != null) {
      final cl = Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: bodyR));
      canvas.save();
      canvas.clipPath(cl);
      for (int s = 0; s < 4; s++) {
        canvas.drawRect(
          Rect.fromLTWH(-bodyR + s * bodyR * 0.6, -bodyR, bodyR * 0.35, bodyR * 2),
          Paint()..color = cd.stripe!.withValues(alpha: 0.9),
        );
      }
      canvas.restore();
    }

    canvas.drawCircle(Offset.zero, bodyR, Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3);

    _txt(canvas, '${h.entry.gateNo}', Offset(0, bodyR * 0.55),
        cd.text, bodyR * 1.1, bold: true, centered: true);

    canvas.restore();

    final headDist = bodyR * 1.55;
    final nx = cos(angle) * headDist + (-sin(angle)) * h.headBob;
    final ny = sin(angle) * headDist + ( cos(angle)) * h.headBob;
    final headPos = Offset(pos.dx + nx, pos.dy + ny);

    canvas.save();
    canvas.translate(headPos.dx, headPos.dy);

    canvas.drawCircle(Offset(0.7, 1.0), headR,
        Paint()..color = Colors.black.withValues(alpha: 0.3));
    canvas.drawCircle(Offset.zero, headR, Paint()..color = cd.bg);
    if (cd.stripe != null) {
      final cl = Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: headR));
      canvas.save();
      canvas.clipPath(cl);
      for (int s = 0; s < 3; s++) {
        canvas.drawRect(
          Rect.fromLTWH(-headR + s * headR * 0.75, -headR, headR * 0.4, headR * 2),
          Paint()..color = cd.stripe!.withValues(alpha: 0.9),
        );
      }
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, headR, Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9);
    canvas.drawCircle(Offset(headR * 0.3, -headR * 0.1), 0.9,
        Paint()..color = Colors.black);

    canvas.restore();

    if (h.boostActive || h.spurtFading) {
      _drawDust(canvas, pos, angle, h);
    }
  }

  void _drawDust(Canvas canvas, Offset pos, double angle, _Horse h) {
    final rng2 = Random(h.entry.gateNo * 7 + frameIdx * 3);
    for (int i = 0; i < 5; i++) {
      final back = -cos(angle) * (10 + rng2.nextDouble() * 14);
      final side = (rng2.nextDouble() - 0.5) * 10;
      final dustPos = Offset(
        pos.dx + back + (-sin(angle)) * side,
        pos.dy + (-sin(angle)).abs() * back + cos(angle) * side,
      );
      final ds = 1.5 + rng2.nextDouble() * 3.0;
      canvas.drawOval(
        Rect.fromCenter(center: dustPos, width: ds * 2.2, height: ds * 0.9),
        Paint()..color = const Color(0xFFD4A070)
            .withValues(alpha: 0.35 + glowVal * 0.25),
      );
    }
  }

  // ── 실시간 순위 (세로형 트랙 우측 상단) ──
  void _drawLiveRanking(Canvas canvas, Size size) {
    if (horses.isEmpty) return;
    final sorted = [...horses]..sort((a, b) => b.prog.compareTo(a.prog));
    double rx = size.width - 54;
    double ry = size.height * 0.13;

    for (int i = 0; i < sorted.length.clamp(0, 6); i++) {
      final h  = sorted[i];
      final cd = HorseCapColors.getCapData(h.entry.gateNo);

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(rx, ry, 44, 18), const Radius.circular(4)),
        Paint()..color = Colors.black.withValues(alpha: 0.62),
      );
      _txt(canvas, '${i + 1}', Offset(rx + 9, ry + 12),
          i == 0 ? const Color(0xFFFFD700) : Colors.white.withValues(alpha: 0.7),
          8.5, bold: true, centered: true);
      canvas.drawCircle(Offset(rx + 25, ry + 9), 6, Paint()..color = cd.bg);
      _txt(canvas, '${h.entry.gateNo}', Offset(rx + 25, ry + 12),
          cd.text, 6.5, bold: true, centered: true);
      canvas.drawRect(Rect.fromLTWH(rx + 33, ry + 13, 9, 2),
          Paint()..color = Colors.white.withValues(alpha: 0.2));
      final totalRange = (goalP - startP).abs().clamp(0.001, 2.0);
      // 모든 경주: prog 증가 방향 (서울/부산경남 CW 포함)
      final relP = ((h.prog - startP) / totalRange).clamp(0.0, 1.0);
      canvas.drawRect(Rect.fromLTWH(rx + 33, ry + 13, 9 * relP, 2),
          Paint()..color = (i == 0 ? const Color(0xFFFFD700) : Colors.white).withValues(alpha: 0.75));

      ry += 22;
    }
  }

  // ── 범례 (세로형 트랙 우측 세로 배치) ──
  void _drawLegend(Canvas canvas, Size size, Rect tr) {
    final n = horses.length.clamp(0, 20); // KRA 최대 20두 지원
    if (n == 0) return;

    // 세로형: 범례를 트랙 우측 바깥에 세로로 배치
    final legendX = tr.right + 10.0;
    final spacing = tr.height / (n + 1).toDouble();
    double ly = tr.top + spacing * 0.5;

    for (int i = 0; i < n; i++) {
      final h  = horses[i];
      final cd = HorseCapColors.getCapData(h.entry.gateNo);
      final cy2 = ly + i * spacing;

      canvas.drawCircle(Offset(legendX + 7, cy2), 7, Paint()..color = cd.bg);
      if (cd.stripe != null) {
        final cl = Path()..addOval(Rect.fromCircle(
            center: Offset(legendX + 7, cy2), radius: 7));
        canvas.save();
        canvas.clipPath(cl);
        for (int s = 0; s < 3; s++) {
          canvas.drawRect(
            Rect.fromLTWH(legendX + s * 5.0, cy2 - 7, 2.5, 14),
            Paint()..color = cd.stripe!.withValues(alpha: 0.9),
          );
        }
        canvas.restore();
      }
      canvas.drawCircle(Offset(legendX + 7, cy2), 7, Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke..strokeWidth = 0.8);
      _txt(canvas, '${h.entry.gateNo}',
          Offset(legendX + 7, cy2 + 0.5),
          cd.text, 6.5, bold: true, centered: true);
    }
  }

  // ── 유틸: 세로형 오벌 경로 ──
  // 세로형: 직선이 좌·우, 코너(반원)가 상·하
  // hw = 좌우 반폭 (= 코너 반지름), hr = 직선 절반 높이
  // ★ 서울 오벌 경로 (_TG.toPoint 와 동기화)
  // CW 방향: 우직선(아래→위) → 상단코너(CW 위쪽반원) → 좌직선(위→아래) → 하단코너(CW 아래쪽반원)
  //
  // 핵심: arcTo의 sweepAngle은 CW(음수) 대신 pi(양수)를 사용해도
  //       경로 자체는 동일하게 닫힘 — fill에는 방향 무관
  // ★ hr은 항상 직선 반높이 고정 (hw와 독립) → 코너/직선 경계 완전 연속
  Path _ovalPath(double cx, double cy, double hw, double hr) {
    if (hw <= 0) return Path();
    // hr이 너무 작으면 직선 부분이 없어짐 → 최소값 보장
    final safeHr = hr.clamp(hw * 0.1, double.infinity);
    final path = Path();
    // 우직선 상단(cx+hw, cy-safeHr) → 하단(cx+hw, cy+safeHr)
    path.moveTo(cx + hw, cy - safeHr);
    path.lineTo(cx + hw, cy + safeHr);
    // 하단 코너: 중심(cx, cy+safeHr), 반원 (0 → π)
    path.arcTo(
      Rect.fromCenter(center: Offset(cx, cy + safeHr), width: hw * 2, height: hw * 2),
      0, pi, false,
    );
    // 좌직선 하단(cx-hw, cy+safeHr) → 상단(cx-hw, cy-safeHr)
    path.lineTo(cx - hw, cy - safeHr);
    // 상단 코너: 중심(cx, cy-safeHr), 반원 (π → 2π)
    path.arcTo(
      Rect.fromCenter(center: Offset(cx, cy - safeHr), width: hw * 2, height: hw * 2),
      pi, pi, false,
    );
    path.close();
    return path;
  }

  void _txt(Canvas canvas, String text, Offset pos, Color color,
      double fontSize, {bool bold = false, bool centered = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        color: color, fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        shadows: bold ? [Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 2)] : null,
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(
      centered ? pos.dx - tp.width  / 2 : pos.dx,
      centered ? pos.dy - tp.height / 2 : pos.dy,
    ));
  }

  @override
  bool shouldRepaint(_RacePainter old) => true;
}

// ══════════════════════════════════════════════════════════════════════
//  게이트박스 동기화 스크롤 위젯
//  — 컨디션바의 ScrollController position을 listener로 구독하여
//    게이트박스 ScrollView를 동일 위치로 동기화
// ══════════════════════════════════════════════════════════════════════
class _GateSyncScrollView extends StatefulWidget {
  final ScrollController linkedController; // 컨디션바 컨트롤러
  final double           boxW;
  final List<_Horse>     ordered;
  final Widget Function(_Horse, double) buildGateBox;

  const _GateSyncScrollView({
    required this.linkedController,
    required this.boxW,
    required this.ordered,
    required this.buildGateBox,
  });

  @override
  State<_GateSyncScrollView> createState() => _GateSyncScrollViewState();
}

class _GateSyncScrollViewState extends State<_GateSyncScrollView> {
  late final ScrollController _ownCtrl;
  bool _syncing = false; // 재귀 방지 플래그

  @override
  void initState() {
    super.initState();
    _ownCtrl = ScrollController();
    // 컨디션바 컨트롤러 → 게이트박스 동기화
    widget.linkedController.addListener(_onLinkedScroll);
    _ownCtrl.addListener(_onOwnScroll);
  }

  void _onLinkedScroll() {
    if (_syncing) return;
    if (!_ownCtrl.hasClients || !widget.linkedController.hasClients) return;
    _syncing = true;
    _ownCtrl.jumpTo(widget.linkedController.offset);
    _syncing = false;
  }

  void _onOwnScroll() {
    if (_syncing) return;
    if (!_ownCtrl.hasClients || !widget.linkedController.hasClients) return;
    _syncing = true;
    widget.linkedController.jumpTo(_ownCtrl.offset);
    _syncing = false;
  }

  @override
  void dispose() {
    widget.linkedController.removeListener(_onLinkedScroll);
    _ownCtrl.removeListener(_onOwnScroll);
    _ownCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _ownCtrl,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: 4),
          ...widget.ordered.map(
              (horse) => widget.buildGateBox(horse, widget.boxW)),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  배너 전용 Painter — 시나리오/레이스명 배너만 그리는 경량 페인터
//  Flutter 게이트뷰 오버레이에서 배너 부분만 Canvas로 유지
// ══════════════════════════════════════════════════════════════════════
class _BannerOnlyPainter extends CustomPainter {
  final List<_Horse> horses;
  final int          distance;
  final String       raceNo;
  final String       venueCode;
  final String       venueName;
  final bool         isJeju;
  final bool         isBusan;

  const _BannerOnlyPainter({
    required this.horses,
    required this.distance,
    required this.raceNo,
    required this.venueCode,
    required this.venueName,
    required this.isJeju,
    required this.isBusan,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // 배너: _RacePainter._paintRaceBanner 와 동일 로직 인라인
    final bannerRect = Rect.fromLTWH(0, 0, w, h);

    // 배너 배경
    canvas.drawRect(bannerRect, Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0D1F35), Color(0xFF142035)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ).createShader(bannerRect));
    canvas.drawLine(Offset(0, 0), Offset(w, 0),
        Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.5)..strokeWidth = 1.5);
    canvas.drawLine(Offset(0, h), Offset(w, h),
        Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.3)..strokeWidth = 1.0);

    void txt(String t, Offset o, Color c, double fs,
        {bool bold = false, bool centered = false}) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: TextStyle(
          color: c, fontSize: fs,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = centered ? o.dx - tp.width / 2 : o.dx;
      tp.paint(canvas, Offset(dx, o.dy - tp.height / 2));
    }

    // ── 섹션 1: 레이스명 바 ──
    final sec1H = h * 0.14;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, sec1H), Paint()
      ..color = const Color(0xFF0A1628).withValues(alpha: 0.7));
    txt('$venueName 제${raceNo}경주', Offset(w * 0.5, sec1H * 0.5),
        Colors.white, 13, bold: true, centered: true);
    txt('${distance}m  ·  ${horses.length}두 출전',
        Offset(w * 0.5, sec1H * 0.85),
        Colors.white.withValues(alpha: 0.6), 9.5, centered: true);

    // ── 섹션 2: 전개 예상 시나리오 ──
    if (horses.isEmpty) return;
    final sec2Top = h * 0.15;
    final sec2H   = h * 0.84;
    final n = horses.length;

    // 선행 그룹 (상위 스피드)
    final sorted = [...horses]..sort((a, b) => b.entry.speedStat.compareTo(a.entry.speedStat));
    final leaders = sorted.take(3).map((h) => h.entry.gateNo).toList()..sort();
    final midField = sorted.skip(3).take(3).map((h) => h.entry.gateNo).toList()..sort();
    final closers  = sorted.skip(6).take(3).map((h) => h.entry.gateNo).toList()..sort();

    void scenRow(String icon, String label, List<int> gates, String desc, double topFrac) {
      final rowTop = sec2Top + sec2H * topFrac;
      final rowH   = sec2H * 0.28;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.03, rowTop, w * 0.94, rowH - 4),
            const Radius.circular(8)),
        Paint()..color = const Color(0xFF0F1F33).withValues(alpha: 0.85),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.03, rowTop, w * 0.94, rowH - 4),
            const Radius.circular(8)),
        Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke ..strokeWidth = 1.0,
      );
      txt(icon, Offset(w * 0.08, rowTop + rowH * 0.35), Colors.white, 13, centered: true);
      txt(label, Offset(w * 0.17, rowTop + rowH * 0.30),
          const Color(0xFFFFD700), 10, bold: true);
      final gateStr = gates.map((g) => '${g}번').join('·');
      txt(gateStr, Offset(w * 0.17, rowTop + rowH * 0.62),
          Colors.white, 11, bold: true);
      txt(desc, Offset(w * 0.17, rowTop + rowH * 0.87),
          Colors.white.withValues(alpha: 0.55), 8);
    }

    if (n > 0) {
      scenRow('⚡', '선행', leaders,
          '초반 선두 장악 · 페이스 메이킹 · 코너 내측 유리', 0.00);
    }
    if (n > 3) {
      scenRow('↗', '선입', midField,
          '선두 후방 2~3마신 위치 · 직선 400m서 추격', 0.32);
    }
    if (n > 6) {
      // 주목마: AI 점수 최고
      final star = sorted.first;
      final starTop = sec2Top + sec2H * 0.64;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.03, starTop, w * 0.94, sec2H * 0.10),
          const Radius.circular(6)),
        Paint()..color = const Color(0xFF1A2A10).withValues(alpha: 0.8),
      );
      txt('⭐ 주목마: ${star.entry.gateNo}번 ${star.entry.horseName}  AI ${star.entry.baseScore.toStringAsFixed(1)}pt',
          Offset(w * 0.5, starTop + sec2H * 0.05),
          const Color(0xFFFFD700), 9, bold: true, centered: true);

      scenRow('🚀', '추입', closers,
          '후반 지구력 부스터 발동 · 막판 역전 狙', 0.74);
    }
  }

  @override
  bool shouldRepaint(_BannerOnlyPainter old) =>
      old.horses != horses || old.distance != distance;
}

// ══════════════════════════════════════════════════════════════════════
//  레이스 결과 전광판 (완전 개편 — 화려한 시상식 스타일)
// ══════════════════════════════════════════════════════════════════════
class _RaceResultBoard extends StatefulWidget {
  final List<_Horse> ranking;
  final double raceTime;
  final RaceInfo race;
  final String venueName;
  final bool isDemoMode;
  final VoidCallback onHome;

  const _RaceResultBoard({
    required this.ranking,
    required this.raceTime,
    required this.race,
    required this.venueName,
    required this.onHome,
    this.isDemoMode = false,
  });

  @override
  State<_RaceResultBoard> createState() => _RaceResultBoardState();
}

class _RaceResultBoardState extends State<_RaceResultBoard>
    with TickerProviderStateMixin {
  late AnimationController _entryCtrl;   // 전광판 등장
  late AnimationController _glowCtrl;    // 골드 글로우 펄스
  late AnimationController _confettiCtrl; // 컨페티
  late Animation<double> _entryAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _confettiCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat();

    _entryAnim  = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutBack);
    _scaleAnim  = Tween(begin: 0.6, end: 1.0).animate(_entryAnim);
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _glowCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Stack(
      children: [
        // ── 컨페티 배경 ──
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _confettiCtrl,
            builder: (_, __) => CustomPaint(
              painter: _ConfettiPainter(_confettiCtrl.value),
            ),
          ),
        ),

        // ── 고급 배경 오버레이 (그라데이션) ──
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xEE050D1A),
                Color(0xF0071220),
                Color(0xEE050D1A),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),

        // ── 전광판 본체 (화면 꽉 채움 + 세로 스크롤) ──
        Positioned(
          top:    size.height * 0.03,
          bottom: size.height * 0.02,
          left:   size.width  * 0.03,
          right:  size.width  * 0.03,
          child: AnimatedBuilder(
            animation: _entryAnim,
            builder: (_, child) => Transform.scale(
              scale: _scaleAnim.value,
              child: Opacity(opacity: _entryAnim.value.clamp(0.0, 1.0), child: child),
            ),
            child: AnimatedBuilder(
              animation: _glowCtrl,
              builder: (_, child) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0C1A2E),
                      const Color(0xFF071220),
                      const Color(0xFF0C1A2E),
                    ],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Color.lerp(
                      const Color(0xFFFFD700).withValues(alpha: 0.6),
                      const Color(0xFFFFEE44).withValues(alpha: 0.85),
                      _glowCtrl.value * 0.5)!,
                    width: 1.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(
                          alpha: 0.12 + _glowCtrl.value * 0.12),
                      blurRadius: 28, spreadRadius: 3,
                    ),
                  ],
                ),
                child: child,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  children: [
                    // 헤더 (고정)
                    _buildBoardHeader(),
                    // 시즌오프 데모 안내 배너
                    if (widget.isDemoMode) _buildDemoBadgeBanner(),
                    // 스크롤 영역 (포디엄 + 전체순위 + 통계)
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildPodium(),
                            _buildFullRanking(),
                            _buildRaceStats(),
                          ],
                        ),
                      ),
                    ),
                    // 홈버튼 (고정 하단)
                    _buildHomeButton(),
                  ],
                ),
              ),
            ),  // AnimatedBuilder(_glowCtrl) 닫기
          ),    // AnimatedBuilder(_entryAnim) 닫기
        ),  // Positioned 닫기
      ],
    );
  }

  // ── 시즌오프 데모 배지 배너 ──
  Widget _buildDemoBadgeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFFFAA00).withValues(alpha: 0.12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '현 모의 레이스는 가상의 데이터로 구현되는 경주입니다. 앱 기능 체험 전용으로 실제 경주 결과와 무관합니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFFFFAA00).withValues(alpha: 0.9),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.45)),
            ),
            child: const Text(
              'DEMO',
              style: TextStyle(
                color: Color(0xFFFF3B30),
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 전광판 헤더 (Round 11 — 고급 UI + 실제 러닝타임 병행) ──
  Widget _buildBoardHeader() {
    // 시뮬레이션 타임 (표시용)
    final simMins = (widget.raceTime ~/ 60).toString().padLeft(2, '0');
    final simSecs = (widget.raceTime % 60).toStringAsFixed(1).padLeft(4, '0');

    // 실제 경주 러닝타임 환산
    // 서울 기준 실제 평균: 1000m=58s, 1200m=1:10, 1400m=1:23, 1700m=1:44, 2000m=2:06
    final dist = widget.race.distance;
    final realSec = _estimateRealRaceTime(dist);
    final realMins = (realSec ~/ 60).toString().padLeft(2, '0');
    final realSecs = (realSec % 60).toStringAsFixed(1).padLeft(4, '0');

    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (_, __) {
        final glow = _glowCtrl.value;
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF0A1628),
                Color.lerp(const Color(0xFF0D1E34), const Color(0xFF142A44), glow)!,
                const Color(0xFF0A1628),
              ],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            border: Border(
              bottom: BorderSide(
                color: Color.lerp(
                  const Color(0xFFFFD700),
                  const Color(0xFFFFEE88),
                  glow * 0.5)!,
                width: 1.5,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 상단 레이스 정보 + 타이틀 한 줄로 ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF8B1A1A).withValues(alpha: 0.9),
                      const Color(0xFF5A0A0A),
                      const Color(0xFF8B1A1A).withValues(alpha: 0.9),
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 좌: 경마통 배지
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🏇', style: TextStyle(fontSize: 10)),
                          SizedBox(width: 3),
                          Text('경마통',
                              style: TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 9, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    // 중: 타이틀 + 경주명 합체
                    Flexible(
                      child: Column(
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [
                                const Color(0xFFFFD700),
                                Color.lerp(const Color(0xFFFFEE44), const Color(0xFFFFFFAA), glow)!,
                                const Color(0xFFFFAA00),
                              ],
                            ).createShader(bounds),
                            child: const Text('🏆 AI 모의 레이스 결과 🏆',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14, fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Text(
                            '${widget.venueName} 제${widget.race.raceNo}경주 · ${widget.race.distance}m',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 10, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    // 우: 시뮬/실제 타임 (컴팩트)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('시뮬 $simMins:$simSecs',
                            style: const TextStyle(
                                color: Color(0xFF7EC8E3),
                                fontSize: 9, fontWeight: FontWeight.w700,
                                fontFamily: 'monospace')),
                        Text('추정 $realMins:$realSecs',
                            style: TextStyle(
                                color: const Color(0xFFFFD700).withValues(alpha: 0.9),
                                fontSize: 9, fontWeight: FontWeight.w700,
                                fontFamily: 'monospace')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 거리별 실제 경주 러닝타임 추정 (서울 더트 기준 평균)
  double _estimateRealRaceTime(int distM) {
    // 서울 더트 기준 평균 러닝타임 (초)
    const timeTable = {
      1000: 62.0,
      1200: 74.5,
      1300: 81.0,
      1400: 87.5,
      1700: 108.0,
      1800: 114.5,
      2000: 127.0,
      2200: 140.0,
      2400: 153.0,
    };
    // 가장 가까운 거리 보간
    final keys = timeTable.keys.toList()..sort();
    for (int i = 0; i < keys.length - 1; i++) {
      final k1 = keys[i]; final k2 = keys[i + 1];
      if (distM >= k1 && distM <= k2) {
        final t = (distM - k1) / (k2 - k1);
        return timeTable[k1]! + (timeTable[k2]! - timeTable[k1]!) * t;
      }
    }
    if (distM <= keys.first) return timeTable[keys.first]!;
    return timeTable[keys.last]!;
  }

  // ── 1~3위 포디엄 (1위 중앙 압도적 강조) ──
  Widget _buildPodium() {
    if (widget.ranking.isEmpty) return const SizedBox.shrink();

    final top3 = widget.ranking.take(3).toList();

    // 포디엄 배치 순서: [왼쪽=2위, 중앙=1위, 오른쪽=3위]
    // 각 슬롯의 원래 ranking 인덱스
    final slotRankIdx = [1, 0, 2]; // slot 0→2위, slot 1→1위, slot 2→3위

    // 발판 높이: 1위(중앙) 압도적으로 높게 (한 화면 맞추기 위해 축소)
    final podiumH = [42.0, 80.0, 32.0];

    // 발판 배경색
    final podiumColors = [
      const Color(0xFFC0C0C0).withValues(alpha: 0.35), // 2위 — 실버
      const Color(0xFFFFD700).withValues(alpha: 0.40), // 1위 — 골드
      const Color(0xFFCD7F32).withValues(alpha: 0.30), // 3위 — 브론즈
    ];

    // 발판 텍스트
    final rankLabels = ['2nd', '1st', '3rd'];

    // 메달 이모지 크기: 1위는 훨씬 크게 (컴팩트화)
    final medalSizes = [16.0, 28.0, 13.0];

    // 배지(HorseCapBadge) 크기: 1위는 훨씬 크게 (한 화면 맞추기 위해 축소)
    final badgeSizes = [32.0, 48.0, 26.0];

    // 말이름 폰트 크기
    final nameFontSizes = [9.0, 12.0, 8.0];

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (slot) {
          final rankIdx = slotRankIdx[slot];
          if (rankIdx >= top3.length) return const Expanded(child: SizedBox());

          final horse      = top3[rankIdx];
          final pH         = podiumH[slot];
          final pColor     = podiumColors[slot];
          final rankLabel  = rankLabels[slot];
          final medalSize  = medalSizes[slot];
          final badgeSize  = badgeSizes[slot];
          final nameFSize  = nameFontSizes[slot];
          final isFirst    = rankIdx == 0;

          // 1위 슬롯 확장 비율: Expanded flex로 1위를 더 넓게
          final flexVal = isFirst ? 2 : 1;

          return Expanded(
            flex: flexVal,
            child: AnimatedBuilder(
              animation: _glowCtrl,
              builder: (_, __) {
                // 1위 글로우 테두리 애니메이션
                final glowBorder = isFirst
                    ? Border.all(
                        color: const Color(0xFFFFD700).withValues(
                            alpha: 0.35 + _glowCtrl.value * 0.4),
                        width: 1.8)
                    : null;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── 1위 전용: WINNER 배지 (왕관 삭제 — 금메달색으로 차별화) ──
                    if (isFirst) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFAA00)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('WINNER',
                            style: TextStyle(
                                color: Color(0xFF1A1A1A),
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0)),
                      ),
                      const SizedBox(height: 2),
                    ] else
                      const SizedBox(height: 4),

                    // 메달 이모지
                    Text(
                      isFirst ? '🥇' : rankIdx == 1 ? '🥈' : '🥉',
                      style: TextStyle(fontSize: medalSize),
                    ),
                    const SizedBox(height: 3),

                    // 말 배지
                    HorseCapBadge(
                        gateNo: horse.entry.gateNo,
                        size: badgeSize,
                        showNumber: true),
                    const SizedBox(height: 4),

                    // 말이름
                    Text(
                      horse.entry.horseName,
                      style: TextStyle(
                          color: isFirst
                              ? const Color(0xFFFFD700)
                              : Colors.white.withValues(alpha: 0.80),
                          fontSize: nameFSize,
                          fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // 기수
                    Text(
                      horse.entry.jockeyName,
                      style: TextStyle(
                          color: isFirst
                              ? const Color(0xFFFFE082)
                              : const Color(0xFF7A9AB8),
                          fontSize: isFirst ? 10 : 8.5),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),

                    // 점수 배지
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isFirst
                            ? const Color(0xFFFFD700).withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: isFirst
                            ? Border.all(
                                color: const Color(0xFFFFD700).withValues(
                                    alpha: 0.5 + _glowCtrl.value * 0.35),
                                width: 1.2)
                            : Border.all(
                                color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Text(
                        '${horse.entry.finalScore.toStringAsFixed(1)}pt',
                        style: TextStyle(
                            color: isFirst
                                ? const Color(0xFFFFD700)
                                : Colors.white.withValues(alpha: 0.55),
                            fontSize: isFirst ? 11 : 9,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 5),

                    // 포디엄 발판
                    Container(
                      height: pH,
                      decoration: BoxDecoration(
                        color: pColor,
                        borderRadius: const BorderRadius.only(
                          topLeft:  Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                        border: glowBorder,
                        boxShadow: isFirst
                            ? [BoxShadow(
                                color: const Color(0xFFFFD700).withValues(
                                    alpha: 0.25 + _glowCtrl.value * 0.2),
                                blurRadius: 12, spreadRadius: 2)]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          rankLabel,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: isFirst ? 15 : 11,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        }),
      ),
    );
  }

  // ── 4위~ 전체 순위 (세로 스크롤 가로형 행 리스트) ──
  Widget _buildFullRanking() {
    // 4위부터 전체 출전마 순위 표시
    final rest = widget.ranking.skip(3).toList();
    if (rest.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1A3A5A), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 섹션 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1628).withValues(alpha: 0.8),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              border: const Border(
                bottom: BorderSide(color: Color(0xFF1A3A5A)),
              ),
            ),
            child: Row(
              children: [
                const Text('📋 전체 순위',
                    style: TextStyle(
                        color: Color(0xFF7EC8E3),
                        fontSize: 11, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Text('4위 ~ ${rest.length + 3}위',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 9.5)),
              ],
            ),
          ),
          // 각 말 가로형 행 (세로 나열)
          ...rest.asMap().entries.map((e) {
            final rank = e.key + 4;
            final h    = e.value;
            final condF = (h.entry.formStat / 100.0).clamp(0.0, 1.0);
            final condColor = condF > 0.75
                ? const Color(0xFF4CAF50)
                : condF > 0.5
                    ? const Color(0xFFFFD700)
                    : const Color(0xFFFF5722);

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: const Border(
                  bottom: BorderSide(
                      color: Color(0xFF1A2A3A), width: 0.7),
                ),
                color: rank.isEven
                    ? Colors.white.withValues(alpha: 0.02)
                    : Colors.transparent,
              ),
              child: Row(
                children: [
                  // 순위 번호
                  SizedBox(
                    width: 28,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2A3A),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$rank위',
                        style: const TextStyle(
                            color: Color(0xFF5A8AAA),
                            fontSize: 9.5, fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 마번 배지
                  HorseCapBadge(
                      gateNo: h.entry.gateNo, size: 28, showNumber: true),
                  const SizedBox(width: 8),

                  // 말이름 + 기수이름
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          h.entry.horseName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          h.entry.jockeyName,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.50),
                              fontSize: 9.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // 컨디션 점 (색상)
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: condColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // AI 점수
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${h.entry.finalScore.toStringAsFixed(1)}pt',
                        style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '배당${h.entry.odds.toStringAsFixed(1)}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.40),
                            fontSize: 8.5),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── 레이스 통계 (컴팩트) ──
  Widget _buildRaceStats() {
    if (widget.ranking.isEmpty) return const SizedBox.shrink();
    final winner = widget.ranking[0];

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2A12), Color(0xFF0F1A0A)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Text('🏆', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${winner.entry.horseName} · ${winner.entry.jockeyName} 기수',
              style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 11, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          _buildStatTag('점수', winner.entry.finalScore.toStringAsFixed(1),
              const Color(0xFFFFD700)),
          const SizedBox(width: 8),
          _buildStatTag('배당', '${winner.entry.odds.toStringAsFixed(1)}배',
              const Color(0xFF64B5F6)),
          const SizedBox(width: 8),
          _buildStatTag('속도', winner.entry.speedStat.toStringAsFixed(0),
              const Color(0xFF81C784)),
        ],
      ),
    );
  }

  Widget _buildStatTag(String label, String val, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(val,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w900)),
        Text(label,
            style: const TextStyle(
                color: Color(0xFF5A7A9A), fontSize: 8)),
      ],
    );
  }

  // ── 홈 버튼 (컴팩트) ──
  Widget _buildHomeButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: GestureDetector(
        onTap: widget.onHome,
        child: AnimatedBuilder(
          animation: _glowCtrl,
          builder: (_, __) => Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1A3A5A),
                  Color.lerp(
                      const Color(0xFF1A3A5A),
                      const Color(0xFF2A5A8A),
                      _glowCtrl.value * 0.4)!,
                  const Color(0xFF1A3A5A),
                ],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF3A6A9A).withValues(
                      alpha: 0.5 + _glowCtrl.value * 0.3)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.home_outlined, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('확인  →  홈으로',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  컨페티 페인터
// ══════════════════════════════════════════════════════════════════════
class _ConfettiPainter extends CustomPainter {
  final double progress;
  static final Random _rng = Random(42);

  static final List<_ConfettiParticle> _particles = List.generate(60, (i) {
    return _ConfettiParticle(
      x: _rng.nextDouble(),
      startY: -0.1 - _rng.nextDouble() * 0.5,
      speed: 0.15 + _rng.nextDouble() * 0.25,
      wobble: _rng.nextDouble() * 2 * 3.14159,
      wobbleSpeed: 2.0 + _rng.nextDouble() * 3.0,
      size: 4 + _rng.nextDouble() * 8,
      color: [
        const Color(0xFFFFD700), const Color(0xFFFF6B6B),
        const Color(0xFF4ECDC4), const Color(0xFF45B7D1),
        const Color(0xFF96CEB4), const Color(0xFFFF88B2),
        Colors.white,
      ][_rng.nextInt(7)],
      shape: _rng.nextBool(),
    );
  });

  _ConfettiPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final y = (p.startY + p.speed * progress) % 1.2;
      if (y < 0) continue;
      final wobbleX = p.x + 0.04 * sin(p.wobble + progress * p.wobbleSpeed * 6.28);
      final cx = wobbleX * size.width;
      final cy = y * size.height;
      final paint = Paint()
        ..color = p.color.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;
      if (p.shape) {
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset(cx, cy), width: p.size, height: p.size * 0.5),
          paint,
        );
      } else {
        canvas.drawCircle(Offset(cx, cy), p.size * 0.4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => progress != old.progress;
}

class _ConfettiParticle {
  final double x, startY, speed, wobble, wobbleSpeed, size;
  final Color color;
  final bool shape;

  const _ConfettiParticle({
    required this.x, required this.startY, required this.speed,
    required this.wobble, required this.wobbleSpeed, required this.size,
    required this.color, required this.shape,
  });
}
