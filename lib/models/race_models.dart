import 'horse_physics_profile.dart';

/// 경주장 코드
enum VenueCode {
  seoul('서울', '1', '서울경마공원'),
  busan('부산경남', '2', '부산경남경마공원'),
  jeju('제주', '3', '제주경마공원');

  const VenueCode(this.label, this.code, this.fullName);
  final String label;
  final String code;
  final String fullName;
}

// ──────────────────────────────────────────────────────────────
// VenueScheduleRule — 요일별 경주장 운영 스케줄 규칙
// ──────────────────────────────────────────────────────────────
//   금요일(weekday=5): 제주·부산경남 O  /  서울 ✕
//   토요일(weekday=6): 서울·제주 O      /  부산경남 ✕
//   일요일(weekday=7): 서울·부산경남 O  /  제주 ✕
//   기타 요일         : 모든 경주장 O   (월요일 특별경주 등 예외처리)
// ──────────────────────────────────────────────────────────────
class VenueScheduleRule {
  // 해당 요일에 운영하는 경주장 코드 집합 반환
  static Set<String> activeVenueCodes(int weekday) {
    switch (weekday) {
      case 5: // 금요일 — 제주(3) + 부산경남(2)
        return {'2', '3'};
      case 6: // 토요일 — 서울(1) + 제주(3)
        return {'1', '3'};
      case 7: // 일요일 — 서울(1) + 부산경남(2)
        return {'1', '2'};
      default: // 월~목 (특별경주) — 전 경주장 허용
        return {'1', '2', '3'};
    }
  }

  /// [weekday]에 [venueCode] 경주장이 운영 중인지 여부
  static bool isVenueActive(int weekday, String venueCode) =>
      activeVenueCodes(weekday).contains(venueCode);

  /// [date] 날짜에 [venue]가 운영 중인지 여부
  static bool isVenueActiveOnDate(DateTime date, VenueCode venue) =>
      isVenueActive(date.weekday, venue.code);

  /// 해당 요일에 비활성화된 경주장 목록 (UI 표시용)
  static List<VenueCode> inactiveVenues(int weekday) => VenueCode.values
      .where((v) => !activeVenueCodes(weekday).contains(v.code))
      .toList();

  /// 해당 요일의 비활성화 이유 설명 문자열
  static String inactiveReason(int weekday, VenueCode venue) {
    final dayName = _weekdayName(weekday);
    final activeNames = activeVenueCodes(weekday)
        .map((c) => VenueCode.values.firstWhere((v) => v.code == c).label)
        .join('·');
    return '$dayName 경주는 $activeNames 경주장에서만 운영됩니다.';
  }

  static String _weekdayName(int wd) {
    const names = {1: '월요일', 2: '화요일', 3: '수요일', 4: '목요일',
                   5: '금요일', 6: '토요일', 7: '일요일'};
    return names[wd] ?? '해당 요일';
  }
}

/// 요일 탭 정보
class DayTab {
  final DateTime date;
  final String label; // 금, 토, 일, 월 등
  final bool hasRaceData;

  const DayTab({
    required this.date,
    required this.label,
    required this.hasRaceData,
  });

  String get dateStr =>
      '${date.month}/${date.day}';
}

/// 경주 정보 (API187 기반)
class RaceInfo {
  final String raceNo;        // 경주번호
  final String raceName;      // 경주명
  final String startTime;     // 출발예정시간
  final int distance;         // 경주거리(m)
  final String condition;     // 경주조건
  final String grade;         // 등급
  final String venueCode;     // 경주장 코드
  final String venueName;     // 경주장명
  final String raceDate;      // 경주일자
  final int totalHorses;      // 출전두수
  final String trackCondition; // 주로상태
  final bool isFinished;      // 경주 종료 여부
  final bool isUpcoming;      // 마감 임박 여부
  final DateTime? activateTime; // 출전마 공지 후 활성화 예정 시각

  const RaceInfo({
    required this.raceNo,
    required this.raceName,
    required this.startTime,
    required this.distance,
    required this.condition,
    required this.grade,
    required this.venueCode,
    required this.venueName,
    required this.raceDate,
    required this.totalHorses,
    required this.trackCondition,
    this.isFinished = false,
    this.isUpcoming = false,
    this.activateTime,
  });

  /// API26_2 응답 기반으로 출발시간·출전두수 등 동적 갱신용 copyWith
  RaceInfo copyWith({
    String? startTime,
    int? totalHorses,
    String? trackCondition,
    bool? isFinished,
    bool? isUpcoming,
    DateTime? activateTime,
  }) {
    return RaceInfo(
      raceNo:         raceNo,
      raceName:       raceName,
      startTime:      startTime      ?? this.startTime,
      distance:       distance,
      condition:      condition,
      grade:          grade,
      venueCode:      venueCode,
      venueName:      venueName,
      raceDate:       raceDate,
      totalHorses:    totalHorses    ?? this.totalHorses,
      trackCondition: trackCondition ?? this.trackCondition,
      isFinished:     isFinished     ?? this.isFinished,
      isUpcoming:     isUpcoming     ?? this.isUpcoming,
      activateTime:   activateTime   ?? this.activateTime,
    );
  }
}

/// 출전마 정보 (API26_2 + API8_2 기반)
class HorseEntry {
  final int gateNo;           // 게이트번호(마번)
  final String horseName;     // 말이름
  final String jockeyName;    // 기수이름
  final String trainerName;   // 조교사이름
  final int weight;           // 마체중
  final int weightChange;     // 체중변화
  final double rating;        // 레이팅
  final double speedStat;     // 속도스탯(0~100)
  final double staminaStat;   // 지구력스탯(0~100)
  final double formStat;      // 컨디션스탯(0~100)
  final double trackFitStat;  // 주로적성스탯(0~100)
  final double baseScore;     // 기본 AI 점수
  double userBonus;           // 유저 배당 가점(-5~+5)  ← UserGValue
  final String recentRecord;  // 최근 성적
  final double odds;          // 단승식 배당률 (winOdds)
  /// 연승식 배당률 (plcOdds) — API26_2: plcOdds1 필드
  /// 0.0 = 미발표 또는 해당 없음
  final double plcOdds;
  bool isCancelled;           // 출전취소 여부

  // ── [NEW] API4_3 구간기록 기반 물리 프로필 ─────────────────────────
  /// 경주마 고유 물리 프로필 (API4_3 Split Time → HorsePhysicsProfile 변환)
  /// null = 아직 로딩 전 또는 API 실패 → HorsePhysicsProfile.neutral 사용
  /// SplitTimeFetcher.fetchAllProfiles()로 경주 선택 시 자동 주입
  HorsePhysicsProfile? physicsProfile;

  // ── KRA API 원시 파라미터 (데이터 매핑 엔진용) ────────────
  /// 경주마 고유등록번호 (예: "KRA20190001234")
  final String horseRegNo;

  /// 통산 승률 (0.0~1.0) — KRA API: rcWinRate 또는 winCnt/rcCnt
  final double rcWins;

  /// 담당 기수 통산 승률 (0.0~1.0) — KRA API: jockeyWinRate
  final double jockeyRcWins;

  /// 부담중량 (kg, 통상 50~60kg) — KRA API: wgBudam
  final double wgBudam;

  /// 후반 G1F(마지막 1펄롱=200m) 성적 점수 (0.0~1.0 정규화)
  /// kG1fBoostThreshold(0.65) 이상이면 Zone4 가속도 +25% 버프 대상
  final double g1fRating;

  // ── KRA API26_2 상금 필드 (chaksun1~5, chaksunT, chaksunY, chaksun_6m) ──
  /// 이번 경주 1착 상금 (원) — KRA API: chaksun1
  final int prizeWin;
  /// 이번 경주 2착 상금 (원) — KRA API: chaksun2
  final int prize2nd;
  /// 이번 경주 3착 상금 (원) — KRA API: chaksun3
  final int prize3rd;
  /// 이번 경주 4착 상금 (원) — KRA API: chaksun4
  final int prize4th;
  /// 이번 경주 5착 상금 (원) — KRA API: chaksun5
  final int prize5th;
  /// 통산 수득 상금 (원) — KRA API: chaksunT
  final int prizeTotalCareer;
  /// 최근 1년 수득 상금 (원) — KRA API: chaksunY
  final int prizeTotal1Year;
  /// 최근 6개월 수득 상금 (원) — KRA API: chaksun_6m
  final int prizeTotal6Month;

  /// 상금 경쟁력 지수 (0.0~1.0 정규화) — 최근 1년 상금 기반 AI 가중치
  /// 계산: (prizeTotal1Year / kPrizeNormalizeFactor).clamp(0.0, 1.0)
  /// kPrizeNormalizeFactor = 100,000,000 (1억 기준 정규화)
  double get prizeCompetitiveness =>
      (prizeTotal1Year / 100000000.0).clamp(0.0, 1.0);

  HorseEntry({
    required this.gateNo,
    required this.horseName,
    required this.jockeyName,
    required this.trainerName,
    required this.weight,
    required this.weightChange,
    required this.rating,
    required this.speedStat,
    required this.staminaStat,
    required this.formStat,
    required this.trackFitStat,
    required this.baseScore,
    this.userBonus = 0.0,
    required this.recentRecord,
    required this.odds,
    this.plcOdds           = 0.0,
    this.isCancelled = false,
    // API 원시 파라미터 (기본값: 미제공 시 중립값)
    this.horseRegNo        = '',
    this.rcWins            = 0.0,
    this.jockeyRcWins      = 0.0,
    this.wgBudam           = 55.0,
    this.g1fRating         = 0.5,
    // API26_2 상금 필드 (기본값: 0)
    this.prizeWin          = 0,
    this.prize2nd          = 0,
    this.prize3rd          = 0,
    this.prize4th          = 0,
    this.prize5th          = 0,
    this.prizeTotalCareer  = 0,
    this.prizeTotal1Year   = 0,
    this.prizeTotal6Month  = 0,
    // [NEW] API4_3 물리 프로필 (기본값: null → 물리 엔진에서 neutral 사용)
    this.physicsProfile,
  });

  /// 최종 AI 점수 = 기본점수 + (유저가점(UserGValue) * 배당가중치)
  double get finalScore => baseScore + (userBonus * 2.5);

  HorseEntry copyWith({
    double? userBonus,
    double? plcOdds,
    bool? isCancelled,
    // API 원시 필드도 copyWith 지원
    String? horseRegNo,
    double? rcWins,
    double? jockeyRcWins,
    double? wgBudam,
    double? g1fRating,
    // API26_2 상금 필드
    int? prizeWin,
    int? prize2nd,
    int? prize3rd,
    int? prize4th,
    int? prize5th,
    int? prizeTotalCareer,
    int? prizeTotal1Year,
    int? prizeTotal6Month,
    // [NEW] 물리 프로필
    HorsePhysicsProfile? physicsProfile,
  }) {
    return HorseEntry(
      gateNo:            gateNo,
      horseName:         horseName,
      jockeyName:        jockeyName,
      trainerName:       trainerName,
      weight:            weight,
      weightChange:      weightChange,
      rating:            rating,
      speedStat:         speedStat,
      staminaStat:       staminaStat,
      formStat:          formStat,
      trackFitStat:      trackFitStat,
      baseScore:         baseScore,
      userBonus:         userBonus         ?? this.userBonus,
      recentRecord:      recentRecord,
      odds:              odds,
      plcOdds:           plcOdds           ?? this.plcOdds,
      isCancelled:       isCancelled       ?? this.isCancelled,
      horseRegNo:        horseRegNo        ?? this.horseRegNo,
      rcWins:            rcWins            ?? this.rcWins,
      jockeyRcWins:      jockeyRcWins      ?? this.jockeyRcWins,
      wgBudam:           wgBudam           ?? this.wgBudam,
      g1fRating:         g1fRating         ?? this.g1fRating,
      prizeWin:          prizeWin          ?? this.prizeWin,
      prize2nd:          prize2nd          ?? this.prize2nd,
      prize3rd:          prize3rd          ?? this.prize3rd,
      prize4th:          prize4th          ?? this.prize4th,
      prize5th:          prize5th          ?? this.prize5th,
      prizeTotalCareer:  prizeTotalCareer  ?? this.prizeTotalCareer,
      prizeTotal1Year:   prizeTotal1Year   ?? this.prizeTotal1Year,
      prizeTotal6Month:  prizeTotal6Month  ?? this.prizeTotal6Month,
      physicsProfile:    physicsProfile    ?? this.physicsProfile,
    );
  }
}

/// 레이스 결과
class RaceResult {
  final int rank;
  final int gateNo;
  final String horseName;
  final String jockeyName;
  final double finalScore;

  const RaceResult({
    required this.rank,
    required this.gateNo,
    required this.horseName,
    required this.jockeyName,
    required this.finalScore,
  });
}

/// 구간별 위치 (애니메이션용)
class HorsePosition {
  final int gateNo;
  double position;  // 0.0 ~ 1.0 (경주로 진행도)
  int currentRank;
  double speed;
  bool hasSpurted;  // 라스트 스퍼트 여부

  HorsePosition({
    required this.gateNo,
    this.position = 0.0,
    this.currentRank = 1,
    required this.speed,
    this.hasSpurted = false,
  });
}

// ──────────────────────────────────────────────────────────────
// racedetailresult 경주별상세성적표 모델
// URL: http://apis.data.go.kr/B551015/racedetailresult/getracedetailresult
// 갱신주기: 일1회 / 응답형식: XML
// ──────────────────────────────────────────────────────────────

/// 개별 말의 경주결과 + 상세성적 (racedetailresult 전체 필드)
class HorseResult {
  // ── 기본 식별 ────────────────────────────────────────────────
  /// 착순 — stOrd (0=미출전)
  final int rank;
  /// 출주번호(마번) — chulNo
  final int gateNo;
  /// 마번(고유등록번호) — hrNo (예: "042013")
  final String horseNo;
  /// 말이름 — hrName
  final String horseName;
  /// 경마장명 — meet (예: "서울")
  final String venueName;

  // ── 마필 정보 ────────────────────────────────────────────────
  /// 산지 — prdCtyNm (예: "한", "외")
  final String origin;
  /// 성별 — sex (예: "거", "牡", "牝")
  final String sex;
  /// 연령 — age (예: "3세", "4세")
  final String age;
  /// 마체중(kg) — wgHr
  final int weight;
  /// 마체중편차(kg) — df (양수=증량, 음수=감량)
  final int weightDiff;
  /// 부담중량(kg) — wgBudam
  final double wgBudam;
  /// 장구내역 — hrTool (예: "망사눈", "빠이블록")
  final String horseTool;
  /// 경주마레이팅 — hrRating (옵션)
  final String horseRating;

  // ── 기수 정보 ────────────────────────────────────────────────
  /// 기수명 — jkName
  final String jockeyName;
  /// 기수번호 — jkNo
  final String jockeyNo;
  /// 기수경마장 — jkMeet (1=서울, 2=제주, 3=부산경남)
  final String jockeyMeet;
  /// 수습기수감량 — jkSymbol (예: "-1", "-2", "-3", null)
  final String jockeyApprentice;

  // ── 조교사 / 마주 정보 ──────────────────────────────────────
  /// 조교사명 — trName
  final String trainerName;
  /// 조교사번호 — trNo
  final String trainerNo;
  /// 조교사경마장 — trMeet
  final String trainerMeet;
  /// 마주명 — owName
  final String ownerName;
  /// 마주번호 — owNo
  final String ownerNo;
  /// 마주복식 — owCloth (말주인 실크 패턴)
  final String ownerCloth;

  // ── 성적 / 기록 ──────────────────────────────────────────────
  /// 주파기록 — rcTime (예: "1:16.6")
  final String raceTime;
  /// 도착차 — differ (예: "1/2마신", "코", "동착"; 1착은 공백)
  final String differ;
  /// 출전여부 — chulYn (1=출전, 0=미출전·취소)
  final bool didStart;

  // ── 배당 정보 ────────────────────────────────────────────────
  /// 단승식배당율 — win (0=비대상 또는 미발매)
  final double winOdds;
  /// 연승식배당율 — plc
  final double placeOdds;

  // ── 하위 호환 (기존 코드 유지용) ────────────────────────────
  /// 연승 배당1 — 기존 placeOdds1과 동일 (= placeOdds)
  double get placeOdds1 => placeOdds;
  /// 연승 배당2 (racedetailresult에는 없음 → 0.0 반환)
  double get placeOdds2 => 0.0;
  /// 복승 배당 (racedetailresult에는 없음 → 0.0 반환)
  double get showOdds => 0.0;
  /// 착차 문자열 (기존 timeDiff와 동일)
  String get timeDiff => differ;

  /// 미출전 여부 (chulYn=0)
  bool get isScratch => !didStart;
  /// 수습기수 감량 여부
  bool get isApprentice => jockeyApprentice.isNotEmpty && jockeyApprentice != '-';
  /// 장구 사용 여부
  bool get hasTool => horseTool.isNotEmpty && horseTool != '-';

  const HorseResult({
    required this.rank,
    required this.gateNo,
    this.horseNo          = '',
    required this.horseName,
    this.venueName        = '',
    this.origin           = '',
    this.sex              = '',
    this.age              = '',
    required this.weight,
    this.weightDiff       = 0,
    this.wgBudam          = 55.0,
    this.horseTool        = '',
    this.horseRating      = '',
    required this.jockeyName,
    this.jockeyNo         = '',
    this.jockeyMeet       = '',
    this.jockeyApprentice = '',
    this.trainerName      = '',
    this.trainerNo        = '',
    this.trainerMeet      = '',
    this.ownerName        = '',
    this.ownerNo          = '',
    this.ownerCloth       = '',
    required this.raceTime,
    this.differ           = '',
    this.didStart         = true,
    required this.winOdds,
    this.placeOdds        = 0.0,
  });
}

/// racedetailresult 경주결과 전체 (1경주 단위)
class KraRaceResult {
  final String raceNo;       // 경주번호
  final String raceDate;     // 경주일자 (YYYYMMDD)
  final String venueCode;    // 경주장코드
  final String venueName;    // 경주장명
  final List<HorseResult> horses; // 착순 정렬된 결과

  const KraRaceResult({
    required this.raceNo,
    required this.raceDate,
    required this.venueCode,
    required this.venueName,
    required this.horses,
  });

  /// 1~3착 출전마만 (미출전 제외)
  List<HorseResult> get top3 =>
      horses.where((h) => h.rank >= 1 && h.rank <= 3 && h.didStart).toList();

  /// 1착마
  HorseResult? get winner =>
      horses.isNotEmpty && horses.first.rank == 1 && horses.first.didStart
          ? horses.first
          : null;

  /// 미출전마 목록
  List<HorseResult> get scratched =>
      horses.where((h) => !h.didStart).toList();

  /// 출전마만 (착순 정렬)
  List<HorseResult> get starters =>
      horses.where((h) => h.didStart).toList();
}
