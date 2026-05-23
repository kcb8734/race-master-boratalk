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
import 'race_models.dart';

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

// ══════════════════════════════════════════════════════════════════════════
//  JockeyDailyTracker
//  ─────────────────────────────────────────────────────────────────────────
//  기수 당일 성적 누적 추적 엔진
//
//  ▸ 엘리트 기수 판정: jockeyRcWins >= 0.22 (통산 승률 22% 이상)
//  ▸ 안전주행 모드 (Satisfaction Penalty):
//      dailyWinCount >= 2  → safeMode = true
//      → maxAcceleration -10%, aggressiveness -30% (코너 G1F 구간)
//  ▸ 독기 모드 (Win-Desire / Mental Buff):
//      isElite && racesRidden >= 3 && dailyWinCount == 0
//      → mentalBuff = true
//      → A_zone(G1F 400m~GOAL) +15% 가점
//      → 첫 승리(dailyWinCount >= 1) 즉시 Reset
//
//  ▸ 오후 누적 가중치:
//      경주 번호(raceNo)가 클수록 afternoon weight 증가
//      = effectScale(raceNo) → 1.0~1.35 범위 선형 보정
// ══════════════════════════════════════════════════════════════════════════

/// 엘리트 기수 승률 임계값 (통산 22% 이상 = 상위 기수)
const double kEliteJockeyThreshold = 0.22;

/// 안전주행 모드 발동 조건: 당일 N승 이상
const int kSafeModeTriggerWins = 2;

/// 독기 모드 발동 조건: 당일 N경기 이상 출전 & 0승
const int kMentalBuffTriggerRaces = 3;

/// 코너 진입 시 aggressiveness 감산율 (안전주행 모드)
const double kAggressivenessReduction = 0.30; // -30%

/// 안전주행 모드 maxAcceleration 감산율
const double kSafeModeAccelPenalty = 0.10;    // -10%

/// 독기 모드 A_zone 가점
const double kMentalBuffBonus = 0.15;          // +15%

/// 고배당 SurgeBuff A_zone 가점
const double kSurgeBuffBonus = 0.20;           // +20%

/// 오후 가중치 최대 보정 배율 (경주 9번 이후 최대)
const double kAfternoonMaxScale = 1.35;

// ── [NEW] 세션 4: 피로도 지수 (FatigueIndex) 상수 ──────────────────────
/// 피로도 발동 조건: 당일 N회 이상 출전 시 누적 페널티 적용
const int kFatigueTriggerRaces = 4;            // 4회 이상 출전 시 발동

/// 출전 1회 초과당 maxAcceleration 감산율
const double kFatigueAccelPenaltyPerRace = 0.03; // 회당 -3%

// ── 기수 1명의 당일 성적 레코드 ─────────────────────────────────────
class _JockeyRecord {
  int dailyWinCount  = 0; // 당일 승수
  int racesRidden    = 0; // 당일 출전 경기 수
  bool safeMode      = false; // 안전주행 모드
  bool mentalBuff    = false; // 독기 모드

  // ── [NEW] 세션 4: 피로도 지수 ──────────────────────────────────────
  /// 피로도 누적 maxAcceleration 감산율
  /// 4회 이상 출전 시: (racesRidden - 3) × 3% 씩 누적 감산
  double get fatigueAccelPenalty {
    if (racesRidden < kFatigueTriggerRaces) return 0.0;
    // 4회째부터 1회당 3% 누적, 최대 -15% 상한
    final extraRaces = racesRidden - (kFatigueTriggerRaces - 1);
    return (extraRaces * kFatigueAccelPenaltyPerRace).clamp(0.0, 0.15);
  }

  /// 피로도 발동 여부
  bool get isFatigued => racesRidden >= kFatigueTriggerRaces;

  /// 승리 기록 → 상태 재계산
  void recordWin() {
    dailyWinCount++;
    racesRidden++;
    _recalc();
  }

  /// 비승리 완주 기록
  void recordRace() {
    racesRidden++;
    _recalc();
  }

  void _recalc() {
    // 안전주행 모드: 2승 이상 달성 시
    safeMode = (dailyWinCount >= kSafeModeTriggerWins);
    // 독기 모드: 3경기 이상 출전 & 0승 → 활성 / 첫 승리 시 즉시 해제
    mentalBuff = (racesRidden >= kMentalBuffTriggerRaces &&
                  dailyWinCount == 0);
  }
}

// ── JockeyDailyTracker 싱글톤 ─────────────────────────────────────────
/// 당일 기수 성적 전역 추적기.
/// 레이스 시뮬레이터 초기화 시 race_provider에서 reset() 호출,
/// 경주 완료 시 recordFinish() 호출.
class JockeyDailyTracker {
  JockeyDailyTracker._();
  static final JockeyDailyTracker instance = JockeyDailyTracker._();

  final Map<String, _JockeyRecord> _records = {};

  /// 날짜가 바뀌었을 때 또는 새 날 첫 경주 시작 시 리셋
  void resetDay() {
    _records.clear();
  }

  /// 기수 결과 기록
  /// [jockeyName]: 기수 이름 (키)
  /// [jockeyRcWins]: 통산 승률 (엘리트 여부 판단)
  /// [won]: 해당 경주 1착 여부
  void recordFinish({
    required String jockeyName,
    required double jockeyRcWins,
    required bool won,
  }) {
    if (!isElite(jockeyRcWins)) return; // 비엘리트 기수는 추적 불필요
    final rec = _records.putIfAbsent(jockeyName, () => _JockeyRecord());
    if (won) {
      rec.recordWin();
    } else {
      rec.recordRace();
    }
  }

  /// 엘리트 기수 여부 판정
  bool isElite(double jockeyRcWins) =>
      jockeyRcWins >= kEliteJockeyThreshold;

  /// 안전주행 모드 여부
  bool isSafeMode(String jockeyName, double jockeyRcWins) {
    if (!isElite(jockeyRcWins)) return false;
    return _records[jockeyName]?.safeMode ?? false;
  }

  /// 독기 모드 여부
  bool isMentalBuff(String jockeyName, double jockeyRcWins) {
    if (!isElite(jockeyRcWins)) return false;
    return _records[jockeyName]?.mentalBuff ?? false;
  }

  /// 당일 승수 조회
  int getDailyWins(String jockeyName) =>
      _records[jockeyName]?.dailyWinCount ?? 0;

  /// 당일 출전 횟수 조회
  int getDailyRaces(String jockeyName) =>
      _records[jockeyName]?.racesRidden ?? 0;

  // ── [NEW] 세션 4: FatigueIndex 관련 공개 API ──────────────────────────

  /// 피로도 발동 여부 (4회 이상 출전 기수)
  bool isFatigued(String jockeyName, double jockeyRcWins) {
    if (!isElite(jockeyRcWins)) return false;
    return _records[jockeyName]?.isFatigued ?? false;
  }

  /// 피로도 누적 maxAcceleration 감산율 반환 (0.0~0.15)
  /// 4회 출전 시 0.03, 5회 시 0.06, ... 최대 0.15
  double fatigueAccelPenalty(String jockeyName, double jockeyRcWins) {
    if (!isElite(jockeyRcWins)) return 0.0;
    return _records[jockeyName]?.fatigueAccelPenalty ?? 0.0;
  }

  /// 경주 번호 기반 오후 가중치 배율 (raceNo 1~12 기준)
  /// 오후 후반부일수록 엘리트 기수 피로/독기 효과 더 강해짐
  double afternoonScale(int raceNo) {
    // raceNo 1 → 1.00, raceNo 9+ → kAfternoonMaxScale(1.35)
    final t = ((raceNo - 1) / 8.0).clamp(0.0, 1.0);
    return 1.0 + t * (kAfternoonMaxScale - 1.0);
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  HighOddsWindowDetector
//  ─────────────────────────────────────────────────────────────────────────
//  고배당 변동 레이스 감지 + 비인기 경주마 SurgeBuff 주입 엔진
//
//  ▸ 발동 조건:
//      출전 기수 중 safeMode 활성 기수 비율 >= 50%
//      → isHighOddsWindow = true
//  ▸ SurgeBuff 대상:
//      배당률 상위 3개 마번 (winOdds 높은 순)
//      → A_zone(후반 400m~GOAL) 가속력 +20% 주입
//  ▸ 오후 누적 가중치:
//      afternoonScale 반영 → SurgeBuffBonus 동적 강화
// ══════════════════════════════════════════════════════════════════════════

/// 고배당 윈도우 발동 임계 (안전모드 기수 비율)
const double kHighOddsWindowThreshold = 0.50; // 50%

/// SurgeBuff 대상 최대 마두 수
const int kSurgeBuffTopN = 3;

class HighOddsWindowDetector {
  HighOddsWindowDetector._();
  static final HighOddsWindowDetector instance = HighOddsWindowDetector._();

  bool _isActive = false;
  final Set<int> _surgeGates = {}; // SurgeBuff 적용 대상 마번 set

  bool get isActive => _isActive;

  /// 경주 시작 전 호출: 출전마 목록 기반 고배당 윈도우 여부 계산
  void evaluate(List<HorseEntry> entries, int raceNo) {
    _isActive = false;
    _surgeGates.clear();

    if (entries.isEmpty) return;

    final tracker = JockeyDailyTracker.instance;
    int safeModeCount = 0;
    for (final e in entries) {
      if (tracker.isSafeMode(e.jockeyName, e.jockeyRcWins)) {
        safeModeCount++;
      }
    }

    final ratio = safeModeCount / entries.length;
    if (ratio < kHighOddsWindowThreshold) return;

    // 고배당 윈도우 활성 → 상위 N개 배당마 추출
    _isActive = true;
    final sorted = List<HorseEntry>.from(entries)
      ..sort((a, b) => b.odds.compareTo(a.odds)); // 배당 높은 순 내림차순
    for (int i = 0; i < kSurgeBuffTopN && i < sorted.length; i++) {
      _surgeGates.add(sorted[i].gateNo);
    }
  }

  /// 해당 마번이 SurgeBuff 대상인지 여부
  bool isSurgeBuff(int gateNo) => _surgeGates.contains(gateNo);

  /// SurgeBuff 실제 가점 배율 (오후 가중치 반영)
  double surgeMultiplier(int raceNo) {
    if (!_isActive) return 1.0;
    final scale = JockeyDailyTracker.instance.afternoonScale(raceNo);
    return 1.0 + kSurgeBuffBonus * scale;
  }

  void reset() {
    _isActive = false;
    _surgeGates.clear();
  }
}
