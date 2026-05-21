// ============================================================
// RaceHorseData — 마사회 공공데이터 API 원시 DTO
//
// 23개 KRA API 원시 응답 객체에서 시뮬레이터 연산에 필요한
// 파라미터만 추출·정규화한 데이터 구조체.
//
// 매핑 흐름:
//   KRA API JSON → RaceHorseData.fromJson() → HorseEntry.fromRaceHorseData()
//     → _Horse (시뮬레이터 인스턴스)
// ============================================================
import 'dart:math';

// ── trackCondition 주로상태 저항 계수 ──────────────────────────
// KRA 주로상태 코드 → 속도 페널티 계수 (0.0 = 패널티 없음, 1.0 = 완전 감속)
// 실측 레이스 타임 기반 추정치 (양호→불량 순)
const Map<String, double> kTrackConditionResistance = {
  '양호': 0.00,  // Good   – 기준선, 패널티 없음
  '보통': 0.03,  // Standard – 미세 감속
  '약간불량': 0.07, // Slightly Soft – 코너 구간 7% 감속
  '불량': 0.12,  // Soft  – 12% 감속 (비·습)
  '매우불량': 0.18, // Heavy – 18% 감속 (폭우·泥)
};

/// 주로상태 문자열 → 저항계수 반환 (알 수 없으면 '보통' 적용)
double trackConditionPenalty(String condition) {
  return kTrackConditionResistance[condition] ??
      kTrackConditionResistance['보통']!;
}

// ── G1F 등급 임계값 ──────────────────────────────────────────
/// 후반 G1F 성적이 "우수"로 판정되는 최소 점수 (0~100 정규화 기준)
const double kG1fBoostThreshold = 0.65;

/// 후반 Zone4(400m~GOAL) G1F 우수마 가속도 버프 배수
const double kG1fAccelBoost = 1.25; // +25%

// ──────────────────────────────────────────────────────────────
/// KRA 공공데이터 API 원시 응답 → 시뮬레이터용 DTO
///
/// API26_2(출전마 기본정보) + API8_2(기수 정보) +
/// 추가 API(성적·부담중량 등) 필드를 통합한 단일 구조체.
// ──────────────────────────────────────────────────────────────
class RaceHorseData {
  // ── 식별자 ────────────────────────────────────────────────
  /// 경주마 고유등록번호 (예: "KRA20190001234")
  final String horseRegNo;

  /// 말 이름
  final String horseName;

  /// 마번 (게이트 번호, 1-based)
  final int gateNo;

  // ── 성적 파라미터 ────────────────────────────────────────
  /// 통산 승률 (0.0~1.0, e.g. 0.25 = 25%)
  /// API 필드: rcWinRate 또는 winCnt/rcCnt 계산값
  final double rcWins;

  /// 담당 기수 통산 승률 (0.0~1.0)
  /// API 필드: jockeyWinRate
  final double jockeyRcWins;

  // ── 중량 파라미터 ────────────────────────────────────────
  /// 부담중량 (kg, 통상 50~60kg 범위)
  /// API 필드: wgBudam
  final double wgBudam;

  /// 마체중 (kg)
  final int weight;

  /// 체중변화 (전 레이스 대비 kg, 양수=증가 / 음수=감소)
  final int weightChange;

  // ── 주로상태 ─────────────────────────────────────────────
  /// 주로상태 (양호/보통/약간불량/불량/매우불량)
  final String trackCondition;

  // ── 후반 성적 ────────────────────────────────────────────
  /// 후반 G1F(마지막 1펄롱=200m) 성적 점수 (0.0~1.0 정규화)
  /// API가 초 단위로 제공할 경우: g1fRating = 1 - (time - bestTime) / range
  final double g1fRating;

  // ── 보조 정보 (HorseEntry 호환용) ───────────────────────
  final String jockeyName;
  final String trainerName;
  final double rating;
  final double formStat;      // 최근 컨디션 (0~100)
  final double trackFitStat;  // 주로 적성 (0~100)
  final String recentRecord;
  final double odds;

  const RaceHorseData({
    required this.horseRegNo,
    required this.horseName,
    required this.gateNo,
    required this.rcWins,
    required this.jockeyRcWins,
    required this.wgBudam,
    required this.weight,
    required this.weightChange,
    required this.trackCondition,
    required this.g1fRating,
    required this.jockeyName,
    this.trainerName  = '',
    this.rating       = 0.0,
    this.formStat     = 60.0,
    this.trackFitStat = 60.0,
    this.recentRecord = '',
    this.odds         = 10.0,
  });

  // ────────────────────────────────────────────────────────
  /// KRA API JSON 맵 → RaceHorseData 파싱
  ///
  /// 필드 이름은 KRA 공공데이터 포털 스펙 기준.
  /// 실제 API 응답키가 다를 경우 아래 _str/_dbl/_int 헬퍼로 보정.
  // ────────────────────────────────────────────────────────
  factory RaceHorseData.fromJson(
    Map<String, dynamic> json, {
    String trackCondition = '보통',
  }) {
    // ── 승률 계산 헬퍼 ─────────────────────────────────────
    // API가 winRate를 직접 제공하면 우선 사용,
    // 없으면 (rcWinCnt / rcCnt) 계산
    double parseWinRate(String winRateKey, String winKey, String cntKey) {
      final direct = _dbl(json, winRateKey);
      if (direct != null && direct > 0) {
        // API가 퍼센트(25.0)로 줄 경우 0~1로 정규화
        return direct > 1.0 ? (direct / 100.0).clamp(0.0, 1.0) : direct.clamp(0.0, 1.0);
      }
      final wins = _dbl(json, winKey) ?? 0.0;
      final cnt  = _dbl(json, cntKey) ?? 1.0;
      return cnt > 0 ? (wins / cnt).clamp(0.0, 1.0) : 0.0;
    }

    final rcWins       = parseWinRate('rcWinRate', 'rcWinCnt', 'rcCnt');
    final jockeyRcWins = parseWinRate('jockeyWinRate', 'jockeyWinCnt', 'jockeyRcCnt');

    // ── 부담중량 ───────────────────────────────────────────
    // API 필드명 후보: wgBudam / burdenWeight / wgt
    final wgBudam = _dbl(json, 'wgBudam') ??
                    _dbl(json, 'burdenWeight') ??
                    _dbl(json, 'wgt') ??
                    55.0; // 기본 55kg

    // ── G1F 성적 ───────────────────────────────────────────
    // API가 초(seconds) 단위로 제공한다고 가정;
    // 빠를수록 점수 높음: 10~15초 범위를 0~1로 역정규화
    double g1fRating;
    final g1fSec = _dbl(json, 'g1fTime') ?? _dbl(json, 'lastFurlongTime');
    if (g1fSec != null && g1fSec > 0) {
      // 10초(최고) → 1.0, 15초(최저) → 0.0
      g1fRating = (1.0 - (g1fSec - 10.0) / 5.0).clamp(0.0, 1.0);
    } else {
      // API 미제공 시 formStat 기반 추정
      final form = _dbl(json, 'formStat') ?? _dbl(json, 'conditionScore') ?? 60.0;
      g1fRating = (form / 100.0).clamp(0.0, 1.0);
    }

    return RaceHorseData(
      horseRegNo:    _str(json, 'horseRegNo')    ?? _str(json, 'hrNo') ?? '',
      horseName:     _str(json, 'horseName')     ?? _str(json, 'hrName') ?? '알수없음',
      gateNo:        _int(json, 'gateNo')        ?? _int(json, 'chulNo') ?? 1,
      rcWins:        rcWins,
      jockeyRcWins:  jockeyRcWins,
      wgBudam:       wgBudam,
      weight:        _int(json, 'weight')        ?? _int(json, 'hrWeight') ?? 450,
      weightChange:  _int(json, 'weightChange')  ?? _int(json, 'wgDiff') ?? 0,
      trackCondition: trackCondition,
      g1fRating:     g1fRating,
      jockeyName:    _str(json, 'jockeyName')    ?? _str(json, 'jkName') ?? '',
      trainerName:   _str(json, 'trainerName')   ?? _str(json, 'trName') ?? '',
      rating:        _dbl(json, 'rating')        ?? _dbl(json, 'rcRating') ?? 0.0,
      formStat:      _dbl(json, 'formStat')      ?? _dbl(json, 'conditionScore') ?? 60.0,
      trackFitStat:  _dbl(json, 'trackFitStat')  ?? _dbl(json, 'trackScore') ?? 60.0,
      recentRecord:  _str(json, 'recentRecord')  ?? _str(json, 'rcRecord') ?? '',
      odds:          _dbl(json, 'odds')          ?? _dbl(json, 'winOdds') ?? 10.0,
    );
  }

  // ────────────────────────────────────────────────────────
  /// 시뮬레이터 물리 연산용 파생 속성
  // ────────────────────────────────────────────────────────

  /// Horse.baseSpeed 매핑 공식 (0~100 스케일 반환, _initHorses에서 정규화)
  ///   = rcWins(0~1) * 0.5 * 100
  ///   + jockeyRcWins(0~1) * 0.3 * 100
  ///   + (60 - wgBudam) * 0.2
  ///
  /// 결과 범위: 약 0~80 (100은 이론 최댓값, clamp 적용 권장)
  double get computedSpeedStat {
    final speedPart   = rcWins * 0.5 * 100.0;
    final jockeyPart  = jockeyRcWins * 0.3 * 100.0;
    final weightPart  = (60.0 - wgBudam) * 0.2;
    return (speedPart + jockeyPart + weightPart).clamp(0.0, 100.0);
  }

  /// Horse.stamina 매핑 공식 (0~100 스케일 반환)
  ///   = 100
  ///   - |weightChange| * kWeightDecayCoeff       (마체중 변동 페널티)
  ///   - trackConditionPenalty(trackCondition) * 100 (주로 저항계수)
  ///
  /// kWeightDecayCoeff: 체중 변동 1kg당 스태미나 감소량
  ///   - 증가(+)·감소(-) 모두 절댓값으로 처리 (급격한 변동 = 컨디션 불안)
  double get computedStaminaStat {
    const kWeightDecayCoeff = 1.5; // 1kg 변동 → 1.5pt 감소
    final weightPenalty = weightChange.abs() * kWeightDecayCoeff;
    final trackPenalty  = trackConditionPenalty(trackCondition) * 100.0;
    return (100.0 - weightPenalty - trackPenalty).clamp(20.0, 100.0);
  }

  /// G1F 우수마 판정 (후반 Zone4 가속도 버프 대상 여부)
  bool get isG1fElite => g1fRating >= kG1fBoostThreshold;

  // ────────────────────────────────────────────────────────
  // JSON 파싱 헬퍼
  // ────────────────────────────────────────────────────────
  static String? _str(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v == null) return null;
    return v.toString().trim().isEmpty ? null : v.toString().trim();
  }

  static double? _dbl(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _int(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v.toString());
  }

  // ────────────────────────────────────────────────────────
  /// 목록 파싱: API 응답 배열 → List of RaceHorseData
  ///
  /// [trackCondition]: 해당 경주의 주로상태 (RaceInfo.trackCondition에서 전달)
  // ────────────────────────────────────────────────────────
  static List<RaceHorseData> parseList(
    List<dynamic> jsonList, {
    String trackCondition = '보통',
  }) {
    return jsonList
        .whereType<Map<String, dynamic>>()
        .map((j) => RaceHorseData.fromJson(j, trackCondition: trackCondition))
        .toList();
  }

  @override
  String toString() =>
      'RaceHorseData($gateNo번 $horseName | '
      'speed=${computedSpeedStat.toStringAsFixed(1)} '
      'stam=${computedStaminaStat.toStringAsFixed(1)} '
      'g1f=${g1fRating.toStringAsFixed(2)} '
      'isElite=$isG1fElite)';
}

// ──────────────────────────────────────────────────────────────
/// RaceHorseData → HorseEntry 변환 확장
///
/// race_models.dart의 HorseEntry를 직접 임포트하지 않고
/// race_animation_screen.dart에서 HorseEntry.fromRaceHorseData()
/// 팩토리 생성자를 추가해 사용하도록 설계.
///
/// 또는 아래 유틸 함수로 대체 가능:
///   final entry = horseEntryFromRaceData(raceHorseData);
// ──────────────────────────────────────────────────────────────

/// G1F 버프 계산 헬퍼 — Zone4 진입 시 speedMult에 적용
///
/// [g1fRating]: _Horse.entry에서 가져온 G1F 점수 (0~1)
/// [zoneFactor]: 후반 400m 구간 내 진행도 (0~1)
/// 반환: speedMult 승수 (예: 1.25 = +25%)
double computeG1fBoostMult(double g1fRating, double zoneFactor) {
  if (g1fRating < kG1fBoostThreshold) return 1.0; // 비해당마
  // 우수마: 구간 진행도에 따라 점진 강화 (0 → +25% 선형)
  final boost = (kG1fAccelBoost - 1.0) * zoneFactor * g1fRating;
  return 1.0 + boost;
}

/// trackCondition 코너 페널티 계산 헬퍼 — Zone2(8→4 압축) 진입 시 적용
///
/// [condition]: RaceInfo.trackCondition 문자열
/// [laneF]: 외측 레인일수록 페널티 강화 (0=안쪽, 1=바깥쪽)
/// 반환: speedMult 승수 (예: 0.93 = -7%)
double computeCornerTrackPenalty(String condition, double laneF) {
  final resistance = trackConditionPenalty(condition);
  if (resistance <= 0.0) return 1.0; // 양호 → 페널티 없음
  // 외측 레인은 코너 반경이 커서 페널티 1.3배 추가
  final adjusted = resistance * (1.0 + laneF * 0.3);
  return max(0.60, 1.0 - adjusted); // 최소 0.60 (과도한 감속 방지)
}
