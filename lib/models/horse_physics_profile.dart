// ============================================================
//  horse_physics_profile.dart
//  경마통 Race Master — 경주마 고유 물리 프로필
//
//  【설계 개요】
//  API4_3 구간 통과 기록(Split Time)을 파싱·정규화하여
//  경주마 객체의 고유 물리 프로필(HorsePhysicsProfile)로 변환.
//
//  ┌─────────────────────────────────────────────────────────┐
//  │  경마장별 구간 기록 매핑 (API4_3 명세서 기준)              │
//  │                                                         │
//  │  [서울]                                                  │
//  │   seS1fAccTime  → 선행/초반 가속력                        │
//  │   sjS1fOrd      → S1F 통과 순위                          │
//  │   se_3cAccTime  → 3코너 통과 누적기록                     │
//  │   se_4cAccTime  → 4코너 통과 누적기록                     │
//  │   sj_3cOrd      → 3코너 통과 순위                        │
//  │   sj_4cOrd      → 4코너 통과 순위                        │
//  │   seG3fAccTime  → G3F 누적 기록                          │
//  │   seG1fAccTime  → G1F(최종 200m) 누적 기록               │
//  │   sjG1fOrd      → G1F 통과 순위                          │
//  │                                                         │
//  │  [부산경남]                                               │
//  │   buS1fAccTime  → S1F 누적 기록                          │
//  │   buG6fAccTime  → G6F 누적 기록                          │
//  │   buG1fAccTime  → G1F(최종 200m) 누적 기록               │
//  │   buS1fOrd / buG1fOrd → 구간별 통과 순위                  │
//  │                                                         │
//  │  [제주]                                                  │
//  │   je_1cTime ~ je_4cTime → 코너별 통과 기록               │
//  └─────────────────────────────────────────────────────────┘
//
//  변환 알고리즘:
//    초반 주도력(initialDrive)   : S1F_Time 기반 100점 환산 가속도 계수
//    코너 손실 방지력(corneringEff): 3c→4c 순위 변동폭 기반 감속 저항력
//    종반 탄력(finalSpurt)       : G1F 기록 기반 최종 스퍼트 속도 최고한도
// ============================================================

// ── 경마장별 기준 시간 상수 (등급·거리 평균, 예외처리 Default용) ──────
// 서울 국5등급 기준 각 구간 평균 통과 시간 (초)
const Map<String, Map<String, double>> kAvgSplitTimes = {
  'seoul': {
    's1f':   12.0,  // S1F(200m) 평균 통과 누적시간(초)
    'c3':    53.5,  // 3코너 평균 누적시간(초) — 거리에 따라 상이
    'c4':    66.0,  // 4코너 평균 누적시간(초)
    'g3f':   71.5,  // G3F(600m 전) 평균 누적시간(초)
    'g1f':   85.0,  // G1F(200m 전) 평균 누적시간(초) — 총 주파기록 근사
  },
  'busan': {
    's1f':   12.2,
    'g6f':   42.0,
    'g1f':   85.5,
  },
  'jeju': {
    'c1':    13.5,
    'c2':    35.0,
    'c3':    55.0,
    'c4':    74.0,
  },
};

// ── 정규화 기준 범위 ──────────────────────────────────────────────────
// S1F 기록: 10.5초(최고) ~ 14.0초(최저) → 점수 100 ~ 0
const double kS1fBest  = 10.5;
const double kS1fWorst = 14.0;

// G1F 기록: 10.0초(최고) ~ 14.5초(최저) → 점수 100 ~ 0
const double kG1fBest  = 10.0;
const double kG1fWorst = 14.5;

// 코너 순위 변동: +5(악화) ~ -5(향상) → 감속저항 -1.0 ~ +1.0
const int kCornerRankDeltaMax = 5;

// ══════════════════════════════════════════════════════════════════════
//  SplitTimeRecord — 단일 경주의 구간별 원시 기록 컨테이너
//
//  API4_3 JSON 응답의 경마장별 필드를 그대로 저장.
//  null = 해당 구간 기록 없음 (Null Pending → Default 대치)
// ══════════════════════════════════════════════════════════════════════
class SplitTimeRecord {
  // ── 서울 구간 기록 ────────────────────────────────────────────────
  final double? seS1fAccTime;   // S1F 누적시간(초)
  final int?    sjS1fOrd;       // S1F 통과순위
  final double? se_3cAccTime;   // 3코너 누적시간(초)
  final double? se_4cAccTime;   // 4코너 누적시간(초)
  final int?    sj_3cOrd;       // 3코너 통과순위
  final int?    sj_4cOrd;       // 4코너 통과순위
  final double? seG3fAccTime;   // G3F 누적시간(초)
  final double? seG1fAccTime;   // G1F 누적시간(초)
  final int?    sjG1fOrd;       // G1F 통과순위

  // ── 부산경남 구간 기록 ────────────────────────────────────────────
  final double? buS1fAccTime;   // S1F 누적시간(초)
  final int?    buS1fOrd;       // S1F 통과순위
  final double? buG6fAccTime;   // G6F 누적시간(초)
  final double? buG1fAccTime;   // G1F 누적시간(초)
  final int?    buG1fOrd;       // G1F 통과순위

  // ── 제주 코너별 기록 ──────────────────────────────────────────────
  final double? je_1cTime;      // 1코너 통과기록(초)
  final double? je_2cTime;      // 2코너 통과기록(초)
  final double? je_3cTime;      // 3코너 통과기록(초)
  final double? je_4cTime;      // 4코너 통과기록(초)

  // ── 공통 ──────────────────────────────────────────────────────────
  final String  venueCode;      // '1'=서울, '2'=부산경남, '3'=제주
  final int     distance;       // 경주거리 (m)
  final String  grade;          // 등급명 (평균값 Default 산출용)

  const SplitTimeRecord({
    this.seS1fAccTime,
    this.sjS1fOrd,
    this.se_3cAccTime,
    this.se_4cAccTime,
    this.sj_3cOrd,
    this.sj_4cOrd,
    this.seG3fAccTime,
    this.seG1fAccTime,
    this.sjG1fOrd,
    this.buS1fAccTime,
    this.buS1fOrd,
    this.buG6fAccTime,
    this.buG1fAccTime,
    this.buG1fOrd,
    this.je_1cTime,
    this.je_2cTime,
    this.je_3cTime,
    this.je_4cTime,
    this.venueCode = '1',
    this.distance  = 1400,
    this.grade     = '국5등급',
  });

  // ── 팩토리: API4_3 JSON 맵 → SplitTimeRecord 파싱 ──────────────────
  factory SplitTimeRecord.fromJson(
    Map<String, dynamic> json, {
    required String venueCode,
    required int    distance,
    required String grade,
  }) {
    // ignore: no_leading_underscores_for_local_identifiers
    double? _d(String key) {
      final v = json[key];
      if (v == null) return null;
      final parsed = double.tryParse(v.toString());
      return (parsed == null || parsed <= 0) ? null : parsed;
    }
    // ignore: no_leading_underscores_for_local_identifiers
    int? _i(String key) {
      final v = json[key];
      if (v == null) return null;
      final parsed = int.tryParse(v.toString());
      return (parsed == null || parsed <= 0) ? null : parsed;
    }

    return SplitTimeRecord(
      // 서울
      seS1fAccTime:  _d('seS1fAccTime'),
      sjS1fOrd:      _i('sjS1fOrd'),
      se_3cAccTime:  _d('se_3cAccTime') ?? _d('se3cAccTime'),
      se_4cAccTime:  _d('se_4cAccTime') ?? _d('se4cAccTime'),
      sj_3cOrd:      _i('sj_3cOrd')    ?? _i('sj3cOrd'),
      sj_4cOrd:      _i('sj_4cOrd')    ?? _i('sj4cOrd'),
      seG3fAccTime:  _d('seG3fAccTime'),
      seG1fAccTime:  _d('seG1fAccTime'),
      sjG1fOrd:      _i('sjG1fOrd'),
      // 부산경남
      buS1fAccTime:  _d('buS1fAccTime'),
      buS1fOrd:      _i('buS1fOrd'),
      buG6fAccTime:  _d('buG6fAccTime'),
      buG1fAccTime:  _d('buG1fAccTime'),
      buG1fOrd:      _i('buG1fOrd'),
      // 제주
      je_1cTime:     _d('je_1cTime') ?? _d('je1cTime'),
      je_2cTime:     _d('je_2cTime') ?? _d('je2cTime'),
      je_3cTime:     _d('je_3cTime') ?? _d('je3cTime'),
      je_4cTime:     _d('je_4cTime') ?? _d('je4cTime'),
      venueCode:     venueCode,
      distance:      distance,
      grade:         grade,
    );
  }

  // ── Null 보호 Default 반환 ──────────────────────────────────────────
  // 구간 기록이 없으면 경마장·등급 기준 평균값 사용 (시뮬 중단 방지)
  double _defaultS1f() {
    final avg = kAvgSplitTimes[venueCode == '1' ? 'seoul'
                               : venueCode == '2' ? 'busan' : 'jeju'];
    return avg?['s1f'] ?? kAvgSplitTimes['seoul']!['s1f']!;
  }

  double _defaultG1f() {
    final avg = kAvgSplitTimes[venueCode == '1' ? 'seoul'
                               : venueCode == '2' ? 'busan' : 'jeju'];
    return avg?['g1f'] ?? kAvgSplitTimes['seoul']!['g1f']!;
  }

  /// S1F 누적시간 — Null이면 평균값 대치
  double get s1fTime {
    if (venueCode == '1') return seS1fAccTime ?? _defaultS1f();
    if (venueCode == '2') return buS1fAccTime ?? _defaultS1f();
    // 제주: 1코너 통과기록으로 근사
    return je_1cTime ?? _defaultS1f();
  }

  /// G1F 누적시간 — Null이면 평균값 대치
  double get g1fTime {
    if (venueCode == '1') return seG1fAccTime ?? _defaultG1f();
    if (venueCode == '2') return buG1fAccTime ?? _defaultG1f();
    // 제주: 4코너 통과기록으로 근사
    return je_4cTime ?? _defaultG1f();
  }

  /// 3코너 통과 순위 (없으면 중립값 5 반환)
  int get ord3c {
    if (venueCode == '1') return sj_3cOrd ?? 5;
    // 부산경남: 1코너 전쪪H 데이터 없음 → 중립값
    if (venueCode == '2') return 5;
    // 제주: je_2cTime과 기준 시간의 차이로 코너 통과 순위 추정
    // je_2cTime이 빠를수록 코너에서 좋은 위치 → 낙은 순위(=좋음) 추정
    if (venueCode == '3' && je_2cTime != null) {
      final avg = kAvgSplitTimes['jeju']?['c2'] ?? 35.0;
      // avg보다 빠르면 상위권(ord=3), 느리면 하위권(ord=7)
      final ratio = (je_2cTime! / avg).clamp(0.7, 1.3);
      return (ratio * 5.0).round().clamp(1, 9);
    }
    return 5;
  }

  /// 4코너 통과 순위 (없으면 중립값 5 반환)
  int get ord4c {
    if (venueCode == '1') return sj_4cOrd ?? 5;
    if (venueCode == '2') return 5;
    // 제주: je_3cTime과 기준 시간의 차이로 코너 통과 순위 추정
    if (venueCode == '3' && je_3cTime != null) {
      final avg = kAvgSplitTimes['jeju']?['c3'] ?? 55.0;
      final ratio = (je_3cTime! / avg).clamp(0.7, 1.3);
      return (ratio * 5.0).round().clamp(1, 9);
    }
    return 5;
  }

  /// G1F 통과 순위 (없으면 중립값 5 반환)
  int get g1fOrd {
    if (venueCode == '1') return sjG1fOrd ?? 5;
    if (venueCode == '2') return buG1fOrd ?? 5;
    return 5;
  }
}

// ══════════════════════════════════════════════════════════════════════
//  HorsePhysicsProfile — 경주마 고유 물리 프로필 (정적 값)
//
//  SplitTimeRecord → 변환 알고리즘 → 100점 만점 3대 물리 계수
//
//  ┌─────────────────────────────────────────────────────────┐
//  │  물리 프로필 3대 축                                        │
//  │                                                         │
//  │  1. initialDrive (0.0 ~ 1.0)                            │
//  │     초반 주도력 — S1F 가속도 계수                          │
//  │     빠를수록 Zone1(출발~1코너) 속도 배수 증가               │
//  │                                                         │
//  │  2. corneringEfficiency (0.0 ~ 1.0)                     │
//  │     코너 손실 방지력 — 3c→4c 순위 변동폭 기반               │
//  │     높을수록 코너 구간 감속 페널티 감소                      │
//  │                                                         │
//  │  3. finalSpurt (0.0 ~ 1.0)                              │
//  │     종반 탄력 — G1F 기록 기반 최종 스퍼트 속도 최고한도       │
//  │     높을수록 Zone4(G1F 구간) 가속도 버프 증가               │
//  └─────────────────────────────────────────────────────────┘
// ══════════════════════════════════════════════════════════════════════
class HorsePhysicsProfile {
  /// 초반 주도력 (0.0~1.0) — S1F 기록 기반
  /// 물리 엔진 반영: Zone1 baseSpeed × (1.0 + initialDrive × kInitDriveBoost)
  final double initialDrive;

  /// 코너 손실 방지력 (0.0~1.0) — 3c→4c 순위 변동 기반
  /// 물리 엔진 반영: 코너 구간 감속계수 × (1.0 - corneringEfficiency × kCornerEffBoost)
  final double corneringEfficiency;

  /// 종반 탄력 (0.0~1.0) — G1F 기록 기반
  /// 물리 엔진 반영: Zone4 speedMult += finalSpurt × kFinalSpurtBoost
  final double finalSpurt;

  // ── 원시 기록 보존 (디버그 및 재계산용) ─────────────────────────
  final double rawS1fTime;    // S1F 실제 기록 (초)
  final double rawG1fTime;    // G1F 실제 기록 (초)
  final int    rawOrd3c;      // 3코너 순위
  final int    rawOrd4c;      // 4코너 순위
  final int    rawG1fOrd;     // G1F 순위
  final bool   isDefault;     // true = 기록 없어 평균값 대치됨

  const HorsePhysicsProfile({
    required this.initialDrive,
    required this.corneringEfficiency,
    required this.finalSpurt,
    required this.rawS1fTime,
    required this.rawG1fTime,
    required this.rawOrd3c,
    required this.rawOrd4c,
    required this.rawG1fOrd,
    this.isDefault = false,
  });

  // ── 기본 프로필 (전체 중립값) ──────────────────────────────────────
  static const HorsePhysicsProfile neutral = HorsePhysicsProfile(
    initialDrive:        0.5,
    corneringEfficiency: 0.5,
    finalSpurt:          0.5,
    rawS1fTime:          12.0,
    rawG1fTime:          85.0,
    rawOrd3c:            5,
    rawOrd4c:            5,
    rawG1fOrd:           5,
    isDefault:           true,
  );

  // ── 팩토리: SplitTimeRecord → HorsePhysicsProfile ──────────────────
  factory HorsePhysicsProfile.fromSplitTime(SplitTimeRecord rec) {
    // ① 초반 주도력: S1F 기록 → 100점 환산
    //    빠를수록 높은 점수: 10.5초=1.0, 14.0초=0.0
    final s1f = rec.s1fTime;
    final initialDrive = ((kS1fWorst - s1f) / (kS1fWorst - kS1fBest))
        .clamp(0.0, 1.0);

    // ② 코너 손실 방지력: 3c→4c 순위 변동 기반
    //    변동폭이 작을수록(순위 유지) 높은 점수
    //    delta > 0 = 순위 하락(악화), delta < 0 = 순위 상승(호전)
    final ord3c = rec.ord3c;
    final ord4c = rec.ord4c;
    final delta  = (ord4c - ord3c).clamp(
        -kCornerRankDeltaMax, kCornerRankDeltaMax);
    // delta = -5(최고 향상) → 1.0, 0(유지) → 0.5, +5(최악 하락) → 0.0
    final corneringEfficiency =
        ((kCornerRankDeltaMax - delta) / (kCornerRankDeltaMax * 2.0))
            .clamp(0.0, 1.0);

    // ③ 종반 탄력: G1F 기록 → 100점 환산
    //    빠를수록 높은 점수: 10.0초=1.0, 14.5초=0.0
    final g1f = rec.g1fTime;
    final finalSpurt = ((kG1fWorst - g1f) / (kG1fWorst - kG1fBest))
        .clamp(0.0, 1.0);

    // 기록이 평균값으로 대치됐는지 여부
    final hasReal = rec.seS1fAccTime != null || rec.buS1fAccTime != null
        || rec.je_1cTime != null;

    return HorsePhysicsProfile(
      initialDrive:        initialDrive,
      corneringEfficiency: corneringEfficiency,
      finalSpurt:          finalSpurt,
      rawS1fTime:          s1f,
      rawG1fTime:          g1f,
      rawOrd3c:            rec.ord3c,
      rawOrd4c:            rec.ord4c,
      rawG1fOrd:           rec.g1fOrd,
      isDefault:           !hasReal,
    );
  }

  // ── 복수 경주 기록 → 평균 프로필 ────────────────────────────────────
  static HorsePhysicsProfile average(List<HorsePhysicsProfile> profiles) {
    if (profiles.isEmpty) return neutral;
    final n = profiles.length.toDouble();
    final avgDrive      = profiles.map((p) => p.initialDrive).reduce((a, b) => a + b) / n;
    final avgCorner     = profiles.map((p) => p.corneringEfficiency).reduce((a, b) => a + b) / n;
    final avgSpurt      = profiles.map((p) => p.finalSpurt).reduce((a, b) => a + b) / n;
    final avgS1f        = profiles.map((p) => p.rawS1fTime).reduce((a, b) => a + b) / n;
    final avgG1f        = profiles.map((p) => p.rawG1fTime).reduce((a, b) => a + b) / n;
    return HorsePhysicsProfile(
      initialDrive:        avgDrive,
      corneringEfficiency: avgCorner,
      finalSpurt:          avgSpurt,
      rawS1fTime:          avgS1f,
      rawG1fTime:          avgG1f,
      rawOrd3c:            5,
      rawOrd4c:            5,
      rawG1fOrd:           5,
      isDefault:           profiles.every((p) => p.isDefault),
    );
  }

  // ── 물리 엔진 반영 계수 (물리 루프에서 직접 사용) ────────────────────
  // Zone1(출발~1코너) 속도 배수 보정: 1.0 + initialDrive × 0.15
  double get zone1SpeedMult => 1.0 + initialDrive * 0.15;

  // 코너 감속 계수 보정: 기준 0.88 + corneringEfficiency × 0.07 (0.88~0.95)
  double get cornerDeccelMult => 0.88 + corneringEfficiency * 0.07;

  // Zone4(G1F 구간) 가속도 배수 보정: 1.0 + finalSpurt × 0.20
  double get zone4SpurtMult => 1.0 + finalSpurt * 0.20;

  @override
  String toString() =>
      'HorsePhysicsProfile('
      'drive=${initialDrive.toStringAsFixed(2)}, '
      'corner=${corneringEfficiency.toStringAsFixed(2)}, '
      'spurt=${finalSpurt.toStringAsFixed(2)}, '
      'isDefault=$isDefault)';
}
