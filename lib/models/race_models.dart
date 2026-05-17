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
  double userBonus;           // 유저 배당 가점(-5~+5)
  final String recentRecord;  // 최근 성적
  final double odds;          // 배당률
  bool isCancelled;           // 출전취소 여부

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
    this.isCancelled = false,
  });

  /// 최종 AI 점수 = 기본점수 + (유저가점 * 배당가중치)
  double get finalScore => baseScore + (userBonus * 2.5);

  HorseEntry copyWith({double? userBonus, bool? isCancelled}) {
    return HorseEntry(
      gateNo: gateNo,
      horseName: horseName,
      jockeyName: jockeyName,
      trainerName: trainerName,
      weight: weight,
      weightChange: weightChange,
      rating: rating,
      speedStat: speedStat,
      staminaStat: staminaStat,
      formStat: formStat,
      trackFitStat: trackFitStat,
      baseScore: baseScore,
      userBonus: userBonus ?? this.userBonus,
      recentRecord: recentRecord,
      odds: odds,
      isCancelled: isCancelled ?? this.isCancelled,
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
