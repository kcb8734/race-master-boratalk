import 'dart:math';
import '../models/race_models.dart';

/// KRA API Mock 서비스
/// 실제 API 연결 전 동일한 데이터 구조의 Mock 데이터 제공
/// 인증키: ef117e7bebbcea7586234f85acd8292dba6a6d95230131aec62a10b5b2610885
class KraMockService {
  static final Random _random = Random();

  // ── 이번 주 경주가 있는 요일 동적 스캔 (API187 시뮬레이션) ──
  static List<DayTab> scanWeeklyRaceDays() {
    final now = DateTime.now();
    final weekday = now.weekday; // 1=월 7=일
    // 이번 주 금(5), 토(6), 일(7) 계산
    final thisWeekFri = now.subtract(Duration(days: weekday - 5 < 0 ? weekday + 2 : weekday - 5));
    final thisWeekSat = thisWeekFri.add(const Duration(days: 1));
    final thisWeekSun = thisWeekFri.add(const Duration(days: 2));
    // 다음주 월요일 (특별 경주 시뮬레이션)
    final nextMon = thisWeekFri.add(const Duration(days: 3));

    // Mock: 금토일은 항상 경주 있음, 월요일은 특별경주 추가 여부(랜덤 or 조건부)
    // 실제로는 API187 호출 후 해당 날짜 데이터 존재 여부 확인
    final bool hasMonRace = _checkHasMonRace();

    final List<DayTab> days = [
      DayTab(
        date: _toDateOnly(thisWeekFri),
        label: '금',
        hasRaceData: true,
      ),
      DayTab(
        date: _toDateOnly(thisWeekSat),
        label: '토',
        hasRaceData: true,
      ),
      DayTab(
        date: _toDateOnly(thisWeekSun),
        label: '일',
        hasRaceData: true,
      ),
      if (hasMonRace)
        DayTab(
          date: _toDateOnly(nextMon),
          label: '월',
          hasRaceData: true,
        ),
    ];
    return days;
  }

  // 월요일 특별경주 여부 (실제는 API187 스캔으로 결정)
  static bool _checkHasMonRace() {
    // Mock: 현재는 false (실제 API 연결 시 동적으로 변경)
    // 월요일 특별경주 데이터가 API에 존재하면 true 반환
    return false;
  }

  static DateTime _toDateOnly(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  // ── 경마경주정보 API187 Mock ──
  static List<RaceInfo> getRaces(String venueCode, DateTime date) {
    final now = DateTime.now();
    final races = _generateRaceList(venueCode, date, now);
    return races;
  }

  static List<RaceInfo> _generateRaceList(
      String venueCode, DateTime date, DateTime now) {
    final venueName = venueCode == '1'
        ? '서울'
        : venueCode == '2'
            ? '부산경남'
            : '제주';

    // 경주장별 레이스 수
    final int raceCount = venueCode == '3' ? 8 : 11;
    final dateStr =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

    // 오늘 경주인지 확인
    final bool isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    final List<RaceInfo> result = [];
    final List<String> startTimes = _getStartTimes(venueCode);
    final List<int> distances = _getDistances(venueCode);
    final List<String> conditions = _getConditions();
    final List<String> grades = _getGrades();
    final List<String> trackConditions = ['양호', '다습', '불량', '건조'];

    final trackCond = trackConditions[_random.nextInt(trackConditions.length)];

    for (int i = 0; i < raceCount; i++) {
      final raceNo = (i + 1).toString();
      final timeStr = startTimes[i];
      bool isFinished = false;
      bool isUpcoming = false;

      DateTime? activateTime;
      if (isToday) {
        final timeParts = timeStr.split(':');
        final raceTime = DateTime(
          now.year,
          now.month,
          now.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
        final diff = raceTime.difference(now).inMinutes;
        isFinished = diff < -30; // 30분 이상 지나면 종료
        isUpcoming = !isFinished && diff >= 0 && diff <= 30 && i == _findFirstUpcomingIndex(startTimes, now);
        // 종료된 경주: 다음 경주일 동일 시간대에 출전마 공지 후 활성화 예정
        if (isFinished) {
          // 다음 경주일(7일 후) 동일 시간대 활성화 예정
          activateTime = raceTime.add(const Duration(days: 7));
        }
      } else if (date.isBefore(DateTime(now.year, now.month, now.day))) {
        // 과거 날짜는 모두 종료 + 다음 예정 없음
        isFinished = true;
      } else {
        // 미래 날짜 경주: 출전마 API 공지 전 (비활성)
        // 요일별 출전마 공지 일정:
        //   금요일(5) 경주 → 수요일(금-3일) 14:00 활성화
        //   토요일(6) 경주 → 목요일(토-2일) 14:00 활성화
        //   일요일(7) 경주 → 금요일(일-2일) 14:00 활성화
        activateTime = _calcActivateTime(date);
        // 이미 활성화 시각이 지났으면 활성 상태 (null)
        if (now.isAfter(activateTime)) {
          activateTime = null; // 이미 활성화됨
        } else {
          isFinished = false; // 미래지만 아직 미활성
        }
      }

      result.add(RaceInfo(
        raceNo: raceNo,
        raceName: '제${raceNo}경주',
        startTime: timeStr,
        distance: distances[i % distances.length],
        condition: conditions[i % conditions.length],
        grade: grades[i % grades.length],
        venueCode: venueCode,
        venueName: venueName,
        raceDate: dateStr,
        totalHorses: 8 + _random.nextInt(9), // 8~16두
        trackCondition: trackCond,
        isFinished: isFinished,
        isUpcoming: isUpcoming,
        activateTime: activateTime,
      ));
    }
    return result;
  }

  /// 경주 날짜(date)를 기준으로 출전마 공지 활성화 예정 일시를 계산한다.
  ///
  /// - 금요일(weekday == 5) 경주 → 당주 수요일(date - 3일) 14:00
  /// - 토요일(weekday == 6) 경주 → 당주 목요일(date - 2일) 14:00
  /// - 일요일(weekday == 7) 경주 → 당주 금요일(date - 2일) 14:00
  /// - 기타 요일           → 전날(date - 1일) 14:00 (안전 폴백)
  static DateTime _calcActivateTime(DateTime date) {
    final int daysBack;
    switch (date.weekday) {
      case 5: // 금요일 → 수요일 (3일 전)
        daysBack = 3;
        break;
      case 6: // 토요일 → 목요일 (2일 전)
        daysBack = 2;
        break;
      case 7: // 일요일 → 금요일 (2일 전)
        daysBack = 2;
        break;
      default: // 기타 요일 → 전날
        daysBack = 1;
    }
    // DateTime 생성 시 day - daysBack 이 음수가 되어도 Dart가 자동으로 월을 조정
    return DateTime(date.year, date.month, date.day - daysBack, 14, 0);
  }

  static int _findFirstUpcomingIndex(List<String> times, DateTime now) {
    for (int i = 0; i < times.length; i++) {
      final parts = times[i].split(':');
      final t = DateTime(now.year, now.month, now.day,
          int.parse(parts[0]), int.parse(parts[1]));
      if (t.isAfter(now)) return i;
    }
    return -1;
  }

  static List<String> _getStartTimes(String venueCode) {
    if (venueCode == '3') {
      // 제주 (8경주)
      return ['10:00', '10:30', '11:05', '11:40', '12:15', '12:50', '13:30', '14:10'];
    } else if (venueCode == '2') {
      // 부산경남 (11경주)
      return ['10:00','10:40','11:20','12:00','12:40','13:20','14:00','14:40','15:20','16:00','16:40'];
    } else {
      // 서울 (11경주)
      return ['11:00','11:40','12:20','13:00','13:40','14:20','15:00','15:40','16:20','17:00','17:40'];
    }
  }

  static List<int> _getDistances(String venueCode) {
    if (venueCode == '3') return [1000, 1200, 1400, 1700, 1000, 1200, 1400, 1700];
    return [1200, 1400, 1700, 1800, 2000, 1200, 1400, 1700, 1800, 2000, 1400];
  }

  static List<String> _getConditions() => [
        '국6등급 별정A',
        '국5등급 별정B',
        '국4등급 핸디캡',
        '국3등급 별정A',
        '국2등급 별정A',
        '국1등급 핸디캡',
        '암말 한정 별정A',
        '3세 한정 별정A',
        '4세 이상 별정B',
        '국6등급 핸디캡',
        '특별 별정A',
      ];

  static List<String> _getGrades() => [
        '국6등급',
        '국5등급',
        '국4등급',
        '국3등급',
        '국2등급',
        '국1등급',
        '암말한정',
        '3세한정',
        '4세이상',
        '국6등급',
        '특별',
      ];

  // ── 출전마 정보 API26_2 + API8_2 + API25_1 + API77 Mock ──
  static List<HorseEntry> getHorseEntries(RaceInfo race) {
    final int count = race.totalHorses.clamp(8, 16);
    final List<HorseEntry> entries = [];

    final horseNames = _horseNamePool();
    final jockeyNames = _jockeyNamePool();
    final trainerNames = _trainerNamePool();

    final usedHorses = <String>{};
    final usedJockeys = <String>{};

    for (int i = 0; i < count; i++) {
      final gateNo = i + 1;

      String horseName;
      do {
        horseName = horseNames[_random.nextInt(horseNames.length)];
      } while (usedHorses.contains(horseName));
      usedHorses.add(horseName);

      String jockeyName;
      do {
        jockeyName = jockeyNames[_random.nextInt(jockeyNames.length)];
      } while (usedJockeys.contains(jockeyName));
      usedJockeys.add(jockeyName);

      final trainerName = trainerNames[_random.nextInt(trainerNames.length)];

      // API77: 레이팅 기반 스탯 계산
      final rating = 40.0 + _random.nextDouble() * 60.0;
      // API4_3 + API6_1: 기초 스피드
      final speedStat = 40.0 + _random.nextDouble() * 55.0 + (rating * 0.05);
      // API77 + API25_1: 스태미나
      final weightBase = 480 + _random.nextInt(60);
      final weightChange = _random.nextInt(11) - 5; // -5 ~ +5
      final staminaStat = 35.0 + _random.nextDouble() * 55.0 + (weightChange < 0 ? 3 : 0);
      // 컨디션
      final formStat = 30.0 + _random.nextDouble() * 60.0;
      // API189_1: 주로 적성
      final trackFitStat = _calcTrackFit(race.trackCondition);
      // 기본 AI 점수 (가중 합산)
      final baseScore = (speedStat * 0.35 + staminaStat * 0.25 +
              formStat * 0.20 + trackFitStat * 0.10 + rating * 0.10)
          .clamp(0.0, 100.0);

      // 최근 성적
      final recentRecord = _genRecentRecord();
      // 배당률
      final odds = 1.5 + _random.nextDouble() * 48.5;

      entries.add(HorseEntry(
        gateNo: gateNo,
        horseName: horseName,
        jockeyName: jockeyName,
        trainerName: trainerName,
        weight: weightBase,
        weightChange: weightChange,
        rating: rating,
        speedStat: speedStat.clamp(0.0, 100.0),
        staminaStat: staminaStat.clamp(0.0, 100.0),
        formStat: formStat.clamp(0.0, 100.0),
        trackFitStat: trackFitStat,
        baseScore: baseScore,
        recentRecord: recentRecord,
        odds: odds,
      ));
    }
    return entries;
  }

  static double _calcTrackFit(String trackCondition) {
    final base = 40.0 + _random.nextDouble() * 50.0;
    switch (trackCondition) {
      case '양호':
        return (base + 10).clamp(0.0, 100.0);
      case '다습':
        return base.clamp(0.0, 100.0);
      case '불량':
        return (base - 5).clamp(0.0, 100.0);
      default:
        return base;
    }
  }

  static String _genRecentRecord() {
    final positions = List.generate(5, (_) {
      final r = _random.nextInt(16) + 1;
      return r <= 10 ? r.toString() : (r <= 13 ? '중' : '낙');
    });
    return positions.join('-');
  }

  static List<String> _horseNamePool() => [
        '천하무적', '황금마차', '번개질주', '청룡기상', '대왕별',
        '폭풍전야', '금빛질주', '하늘나래', '독수리', '왕자의길',
        '영광의날', '빛나는별', '산악질주', '우주영웅', '황제의꿈',
        '바람의아들', '신기록', '스피드킹', '대한의힘', '별똥별',
        '챔피언로드', '비상하라', '태양마', '동방의빛', '승리의신',
        '질풍노도', '황금빛날', '최강자', '영원한별', '전설의말',
        '무적함대', '골든스타', '빅퀘스천', '드림레이서', '파워풀',
        '뇌전번개', '청운의꿈', '하이스피드', '세계일류', '무한질주',
      ];

  static List<String> _jockeyNamePool() => [
        '조성곤', '유현명', '최범현', '김용근', '박도영',
        '이채택', '강민준', '문세영', '박준영', '이창섭',
        '서승운', '정해인', '나승찬', '김경준', '이준혁',
        '박태준', '윤기원', '최원혁', '강태훈', '이영진',
      ];

  static List<String> _trainerNamePool() => [
        '김영규', '박병두', '신기철', '이동훈', '최만호',
        '정재흥', '고석철', '박경율', '송상준', '권순일',
      ];

  // ──────────────────────────────────────────────────────────────
  // 시즌오프 전용 가상 경주 데이터 (체험 모드)
  // ──────────────────────────────────────────────────────────────

  /// 시즌오프 기간 체험용 가상 경주 1개 생성
  static RaceInfo getDemoRace() {
    return RaceInfo(
      raceNo: 'DEMO',
      raceName: '체험 모의경주',
      startTime: '14:00',
      distance: 1400,
      condition: '체험 전용 경주',
      grade: '체험등급',
      venueCode: '1',
      venueName: '서울(가상)',
      raceDate: _formatDemoDate(),
      totalHorses: 10,
      trackCondition: '양호',
      isFinished: false,
      isUpcoming: false,
    );
  }

  /// 체험 경주용 말 10두 생성
  static List<HorseEntry> getDemoHorseEntries() {
    final rng = Random(42); // 고정 시드 — 항상 동일한 데이터
    final horseNames = [
      '황금질주', '번개왕', '청운마', '천마', '대왕스피드',
      '바람의왕', '폭풍마', '빛나는길', '영웅마', '스타레이서',
    ];
    final jockeyNames = [
      '김용근', '조성곤', '박도영', '유현명', '최범현',
      '이채택', '강민준', '문세영', '박준영', '이창섭',
    ];
    final trainerName = '체험조교사';

    final entries = <HorseEntry>[];
    for (int i = 0; i < 10; i++) {
      final rating = 45.0 + rng.nextDouble() * 50.0;
      final speedStat = (40.0 + rng.nextDouble() * 55.0 + rating * 0.05).clamp(0.0, 100.0);
      final staminaStat = (38.0 + rng.nextDouble() * 55.0).clamp(0.0, 100.0);
      final formStat = (35.0 + rng.nextDouble() * 58.0).clamp(0.0, 100.0);
      final trackFitStat = (42.0 + rng.nextDouble() * 48.0).clamp(0.0, 100.0);
      final baseScore = (speedStat * 0.35 + staminaStat * 0.25 +
              formStat * 0.20 + trackFitStat * 0.10 + rating * 0.10)
          .clamp(0.0, 100.0);
      final odds = 1.8 + rng.nextDouble() * 28.0;
      final weight = 480 + rng.nextInt(55);
      final weightChange = rng.nextInt(9) - 4;

      entries.add(HorseEntry(
        gateNo: i + 1,
        horseName: horseNames[i],
        jockeyName: jockeyNames[i],
        trainerName: trainerName,
        weight: weight,
        weightChange: weightChange,
        rating: rating,
        speedStat: speedStat,
        staminaStat: staminaStat,
        formStat: formStat,
        trackFitStat: trackFitStat,
        baseScore: baseScore,
        recentRecord: _genDemoRecord(rng),
        odds: double.parse(odds.toStringAsFixed(1)),
      ));
    }
    return entries;
  }

  static String _genDemoRecord(Random rng) {
    return List.generate(5, (_) {
      final r = rng.nextInt(12) + 1;
      return r <= 8 ? r.toString() : (r <= 10 ? '중' : '낙');
    }).join('-');
  }

  static String _formatDemoDate() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }
}
