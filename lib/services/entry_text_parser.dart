import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ══════════════════════════════════════════════════════════════════════════
//  EntryTextParser — 한국 경마 출전표 Raw Text 파서 엔진
//
//  ▸ 입력: 출전표 텍스트 전체 (관리자 붙여넣기)
//  ▸ 출력: ParsedRaceCard (마필 목록 + DATA TIPS + 경주 헤더)
//
//  ▸ 파싱 파이프라인:
//    1) 경주 헤더 (경주장/번호/거리/함수율)
//    2) 마필 블록 분리 (마번 패턴 delimiter)
//    3) 개별 마필 파싱 (기본정보 + 전적 + 기수/조교사/체중)
//    4) 최근 4경주 블록 파싱 (날짜 패턴 delimiter + 원형 숫자 착순)
//    5) DATA TIPS 섹션 파싱 (건/양/다/포/불 + 10종 지표)
//    6) HorseTrackPerformance + HorseAdvancedStat → SharedPreferences 저장
// ══════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────
//  파싱 결과 DTO 클래스들
// ─────────────────────────────────────────────────────────────────────────

/// 최근 1개 경주 착순 항목
class PastRaceFinish {
  final int rank;           // 착순 (1~11)
  final int gateNo;         // 마번
  final String horseName;   // 마명
  final String raceTime;    // 주파기록 (예: "1:52.7")
  final double weight;      // 부담중량

  const PastRaceFinish({
    required this.rank,
    required this.gateNo,
    required this.horseName,
    required this.raceTime,
    required this.weight,
  });

  Map<String, dynamic> toJson() => {
    'rank': rank,
    'gateNo': gateNo,
    'horseName': horseName,
    'raceTime': raceTime,
    'weight': weight,
  };
}

/// 최근 1개 경주 블록
class PastRaceBlock {
  final String dateCode;    // 날짜 코드 (예: "260329")
  final String venue;       // 경주장 (예: "서")
  final int raceNo;         // 경주번호
  final String grade;       // 등급 (예: "국6")
  final int distance;       // 거리 (예: 1700)
  final String condition;   // 경주조건 (예: "별A")
  final String weather;     // 날씨 (예: "맑")
  final int moisture;       // 함수율 (%)
  final int selfRank;       // 해당마 착순
  final int totalHorses;    // 출전두수
  final List<PastRaceFinish> finishes; // 착순 목록 (최대 6개)

  const PastRaceBlock({
    required this.dateCode,
    required this.venue,
    required this.raceNo,
    required this.grade,
    required this.distance,
    required this.condition,
    required this.weather,
    required this.moisture,
    required this.selfRank,
    required this.totalHorses,
    required this.finishes,
  });

  Map<String, dynamic> toJson() => {
    'dateCode': dateCode,
    'venue': venue,
    'raceNo': raceNo,
    'grade': grade,
    'distance': distance,
    'condition': condition,
    'weather': weather,
    'moisture': moisture,
    'selfRank': selfRank,
    'totalHorses': totalHorses,
    'finishes': finishes.map((f) => f.toJson()).toList(),
  };
}

/// 주로별 전적 [총출전, 1착, 2착]
class TrackRecord {
  final int total;  // 총 출전
  final int first;  // 1착
  final int second; // 2착

  const TrackRecord({
    required this.total,
    required this.first,
    required this.second,
  });

  static const TrackRecord zero = TrackRecord(total: 0, first: 0, second: 0);

  /// 승률 (1착/총출전)
  double get winRate => total > 0 ? first / total : 0.0;

  /// 복승률 ((1착+2착)/총출전)
  double get placeRate => total > 0 ? (first + second) / total : 0.0;

  Map<String, dynamic> toJson() => {
    'total': total,
    'first': first,
    'second': second,
  };

  factory TrackRecord.fromJson(Map<String, dynamic> j) => TrackRecord(
    total:  (j['total']  as int?) ?? 0,
    first:  (j['first']  as int?) ?? 0,
    second: (j['second'] as int?) ?? 0,
  );
}

/// 주로 환경별 적응도 (HorseTrackPerformance)
class HorseTrackPerformance {
  final int horseGateNo;       // 마번 (경주 내 식별)
  final String horseName;      // 마명
  final TrackRecord dry;       // 건조 (건)
  final TrackRecord good;      // 양호 (양)
  final TrackRecord soft;      // 다습 (다)
  final TrackRecord heavy;     // 포화 (포)
  final TrackRecord bad;       // 불량 (불)

  const HorseTrackPerformance({
    required this.horseGateNo,
    required this.horseName,
    this.dry    = TrackRecord.zero,
    this.good   = TrackRecord.zero,
    this.soft   = TrackRecord.zero,
    this.heavy  = TrackRecord.zero,
    this.bad    = TrackRecord.zero,
  });

  /// 현재 함수율(%)에 맞는 TrackRecord 반환
  TrackRecord trackRecordForMoisture(int moisturePct) {
    if (moisturePct <= 5)       return dry;
    if (moisturePct <= 10)      return good;
    if (moisturePct <= 14)      return soft;
    if (moisturePct <= 20)      return heavy;
    return bad;
  }

  /// 현재 주로 상태에 따른 가속도 가중치 (0.8 ~ 1.2)
  double speedWeightForMoisture(int moisturePct) {
    final rec = trackRecordForMoisture(moisturePct);
    if (rec.total == 0) return 1.0; // 전적 없음 → 중립
    // 승률 기반 가중치: 0% → 0.85, 50%+ → 1.15
    return 0.85 + (rec.winRate.clamp(0.0, 0.5) * 0.6);
  }

  /// 포화/불량 주로 패널티 감면율 (0.0 ~ 0.3)
  double muddyPenaltyRelief(int moisturePct) {
    if (moisturePct < 15) return 0.0;
    final rec = moisturePct <= 20 ? heavy : bad;
    if (rec.total == 0) return 0.0;
    return (rec.placeRate * 0.3).clamp(0.0, 0.3);
  }

  Map<String, dynamic> toJson() => {
    'horseGateNo': horseGateNo,
    'horseName': horseName,
    'dry':   dry.toJson(),
    'good':  good.toJson(),
    'soft':  soft.toJson(),
    'heavy': heavy.toJson(),
    'bad':   bad.toJson(),
  };

  factory HorseTrackPerformance.fromJson(Map<String, dynamic> j) =>
    HorseTrackPerformance(
      horseGateNo: (j['horseGateNo'] as int?) ?? 0,
      horseName:   (j['horseName']   as String?) ?? '',
      dry:   TrackRecord.fromJson((j['dry']   as Map<String, dynamic>?) ?? {}),
      good:  TrackRecord.fromJson((j['good']  as Map<String, dynamic>?) ?? {}),
      soft:  TrackRecord.fromJson((j['soft']  as Map<String, dynamic>?) ?? {}),
      heavy: TrackRecord.fromJson((j['heavy'] as Map<String, dynamic>?) ?? {}),
      bad:   TrackRecord.fromJson((j['bad']   as Map<String, dynamic>?) ?? {}),
    );
}

/// 주행 스타일 분류
enum RunningStyle {
  frontRunner,   // 선행: 초반 빠름 + 종반 느림
  stalker,       // 선입: 초반 중간 + 종반 빠름
  closer,        // 추입: 초반 느림 + 종반 빠름
  unknown,       // 분류 불가
}

/// 고급 통계 (HorseAdvancedStat) - DATA TIPS 10종 지표
class HorseAdvancedStat {
  final int horseGateNo;         // 마번
  final String horseName;        // 마명

  // ── 레이팅 & 승률 ────────────────────────────────────────────────────
  final double rating;           // 레이팅 (0 = 없음)
  final double careerWinRate;    // 통산 승률 (0.0~1.0)
  final double careerPlaceRate;  // 통산 복승률 (0.0~1.0)

  // ── 거리별 전적 ──────────────────────────────────────────────────────
  final int distanceMeters;      // 거리 (m) — 당일 경주 거리
  final double distWinRate;      // 해당 거리 승률
  final String distBestTime;     // 해당 거리 최고기록

  // ── 최근 상금 ────────────────────────────────────────────────────────
  final int prize1Year;          // 최근 1년 상금 (원)
  final int prize6Month;         // 최근 6개월 상금 (원)

  // ── 구간 기록 (속도 분석) ─────────────────────────────────────────────
  final double s1fTime;          // 초반 200m 평균 기록 (초)
  final double g1fTime;          // 종반 200m 평균 기록 (초)
  final double speedIndex;       // 속도지수

  // ── 분류 ─────────────────────────────────────────────────────────────
  final RunningStyle runningStyle; // 주행 스타일 (선행/추입 자동 분류)

  // ── 컨디션 가중치 (최근 6개월 상금 기반) ─────────────────────────────
  /// 최근 6개월 상금이 높을수록 컨디션 가중치 증가 (0.9 ~ 1.1)
  double get conditionWeight {
    if (prize6Month <= 0) return 1.0;
    // 3000만원 = 기준선(1.0), 6000만원 이상 = 1.1, 0 = 0.9
    final normalized = (prize6Month / 60000000.0).clamp(0.0, 1.0);
    return 0.9 + normalized * 0.2;
  }

  /// 거리 적성 가중치 (0.85 ~ 1.15)
  double get distanceAptitude {
    if (distWinRate <= 0) return 1.0;
    return 0.85 + (distWinRate.clamp(0.0, 1.0) * 0.3);
  }

  /// 속도지수 정규화 (0.0~1.0, 70~120 범위 기준)
  double get normalizedSpeedIndex {
    if (speedIndex <= 0) return 0.5;
    return ((speedIndex - 70) / 50.0).clamp(0.0, 1.0);
  }

  const HorseAdvancedStat({
    required this.horseGateNo,
    required this.horseName,
    this.rating            = 0.0,
    this.careerWinRate     = 0.0,
    this.careerPlaceRate   = 0.0,
    this.distanceMeters    = 1700,
    this.distWinRate       = 0.0,
    this.distBestTime      = '',
    this.prize1Year        = 0,
    this.prize6Month       = 0,
    this.s1fTime           = 0.0,
    this.g1fTime           = 0.0,
    this.speedIndex        = 0.0,
    this.runningStyle      = RunningStyle.unknown,
  });

  Map<String, dynamic> toJson() => {
    'horseGateNo':    horseGateNo,
    'horseName':      horseName,
    'rating':         rating,
    'careerWinRate':  careerWinRate,
    'careerPlaceRate':careerPlaceRate,
    'distanceMeters': distanceMeters,
    'distWinRate':    distWinRate,
    'distBestTime':   distBestTime,
    'prize1Year':     prize1Year,
    'prize6Month':    prize6Month,
    's1fTime':        s1fTime,
    'g1fTime':        g1fTime,
    'speedIndex':     speedIndex,
    'runningStyle':   runningStyle.index,
  };

  factory HorseAdvancedStat.fromJson(Map<String, dynamic> j) =>
    HorseAdvancedStat(
      horseGateNo:    (j['horseGateNo']    as int?)    ?? 0,
      horseName:      (j['horseName']      as String?) ?? '',
      rating:         (j['rating']         as num?)?.toDouble()  ?? 0.0,
      careerWinRate:  (j['careerWinRate']  as num?)?.toDouble()  ?? 0.0,
      careerPlaceRate:(j['careerPlaceRate'] as num?)?.toDouble() ?? 0.0,
      distanceMeters: (j['distanceMeters'] as int?)    ?? 1700,
      distWinRate:    (j['distWinRate']    as num?)?.toDouble()  ?? 0.0,
      distBestTime:   (j['distBestTime']   as String?) ?? '',
      prize1Year:     (j['prize1Year']     as int?)    ?? 0,
      prize6Month:    (j['prize6Month']    as int?)    ?? 0,
      s1fTime:        (j['s1fTime']        as num?)?.toDouble()  ?? 0.0,
      g1fTime:        (j['g1fTime']        as num?)?.toDouble()  ?? 0.0,
      speedIndex:     (j['speedIndex']     as num?)?.toDouble()  ?? 0.0,
      runningStyle:   RunningStyle.values[
                        (j['runningStyle'] as int?) ?? RunningStyle.unknown.index
                      ],
    );
}

/// 개별 마필 파싱 결과
class ParsedHorseEntry {
  final int gateNo;           // 마번
  final String horseName;     // 마명
  final String sex;           // 성별 (수/암/거)
  final int birthYear;        // 출생년도 (예: 2022)
  final String sire;          // 부마
  final String dam;           // 모마
  final String jockeyName;    // 기수명
  final String trainerCode;   // 조교사 코드/번호
  final String trainerName;   // 조교사명
  final double wgBudam;       // 부담중량
  final double wgBudamChange; // 부담중량 변화 (+/-)
  final int weight;           // 마체중
  final int weightChange;     // 마체중 변화
  final String bestTime;      // 최고기록
  final String avgTime;       // 평균기록
  final int careerTotal;      // 통산 출전
  final int careerWin;        // 통산 1착
  final int careerPlace;      // 통산 2착
  final int careerShow;       // 통산 3착
  final int careerFourth;     // 통산 4착
  final int careerFifth;      // 통산 5착+
  final int totalPrize;       // 통산 상금 (원)
  final String recentRecord;  // 최근 성적 문자열 (예: "7 7 9 8 5")
  final List<PastRaceBlock> pastRaces; // 최근 4경주 블록
  final HorseTrackPerformance trackPerformance; // 주로별 적응도
  final HorseAdvancedStat advancedStat;         // 고급 통계

  const ParsedHorseEntry({
    required this.gateNo,
    required this.horseName,
    this.sex             = '',
    this.birthYear       = 0,
    this.sire            = '',
    this.dam             = '',
    this.jockeyName      = '',
    this.trainerCode     = '',
    this.trainerName     = '',
    this.wgBudam         = 55.0,
    this.wgBudamChange   = 0.0,
    this.weight          = 0,
    this.weightChange    = 0,
    this.bestTime        = '',
    this.avgTime         = '',
    this.careerTotal     = 0,
    this.careerWin       = 0,
    this.careerPlace     = 0,
    this.careerShow      = 0,
    this.careerFourth    = 0,
    this.careerFifth     = 0,
    this.totalPrize      = 0,
    this.recentRecord    = '',
    this.pastRaces       = const [],
    required this.trackPerformance,
    required this.advancedStat,
  });

  Map<String, dynamic> toJson() => {
    'gateNo':        gateNo,
    'horseName':     horseName,
    'sex':           sex,
    'birthYear':     birthYear,
    'sire':          sire,
    'dam':           dam,
    'jockeyName':    jockeyName,
    'trainerCode':   trainerCode,
    'trainerName':   trainerName,
    'wgBudam':       wgBudam,
    'wgBudamChange': wgBudamChange,
    'weight':        weight,
    'weightChange':  weightChange,
    'bestTime':      bestTime,
    'avgTime':       avgTime,
    'careerTotal':   careerTotal,
    'careerWin':     careerWin,
    'careerPlace':   careerPlace,
    'careerShow':    careerShow,
    'careerFourth':  careerFourth,
    'careerFifth':   careerFifth,
    'totalPrize':    totalPrize,
    'recentRecord':  recentRecord,
    'pastRaces':     pastRaces.map((r) => r.toJson()).toList(),
    'trackPerformance': trackPerformance.toJson(),
    'advancedStat':     advancedStat.toJson(),
  };
}

/// 경주 헤더 파싱 결과
class ParsedRaceHeader {
  final String venue;        // 경주장 (예: "서울")
  final int raceNo;          // 경주번호
  final int distance;        // 거리 (m)
  final String grade;        // 등급 (예: "국6등급")
  final String condition;    // 연령조건
  final int moisture;        // 함수율 (%)
  final String raceType;     // 경주종류 (예: "일반경주")
  final String prize1st;     // 1위 상금 문자열

  const ParsedRaceHeader({
    this.venue       = '서울',
    this.raceNo      = 1,
    this.distance    = 1700,
    this.grade       = '',
    this.condition   = '',
    this.moisture    = 0,
    this.raceType    = '일반경주',
    this.prize1st    = '',
  });

  Map<String, dynamic> toJson() => {
    'venue':    venue,
    'raceNo':   raceNo,
    'distance': distance,
    'grade':    grade,
    'condition':condition,
    'moisture': moisture,
    'raceType': raceType,
    'prize1st': prize1st,
  };
}

/// DATA TIPS 구간 요약
class ParsedDataTips {
  // ── 레이팅 Top 순위 ────────────────────────────────────────────────
  final List<MapEntry<int, double>> ratingRanking; // [(마번, 레이팅)]

  // ── 1700m 승률 Top / 최고기록 Top ─────────────────────────────────
  final List<MapEntry<int, double>> distWinRanking;    // [(마번, 승률%)]
  final List<MapEntry<int, String>> distBestRanking;   // [(마번, 기록)]

  // ── 최근 상금 Top ─────────────────────────────────────────────────
  final List<MapEntry<int, int>> prize1YearRanking;   // [(마번, 원)]
  final List<MapEntry<int, int>> prize6MonthRanking;  // [(마번, 원)]

  // ── 구간 기록 Top ─────────────────────────────────────────────────
  final List<MapEntry<int, double>> s1fRanking; // [(마번, 초)] 빠를수록 낮음
  final List<MapEntry<int, double>> g1fRanking; // [(마번, 초)]

  // ── 속도지수 Top ──────────────────────────────────────────────────
  final List<MapEntry<int, double>> speedIndexRanking; // [(마번, 지수)]

  const ParsedDataTips({
    this.ratingRanking    = const [],
    this.distWinRanking   = const [],
    this.distBestRanking  = const [],
    this.prize1YearRanking  = const [],
    this.prize6MonthRanking = const [],
    this.s1fRanking       = const [],
    this.g1fRanking       = const [],
    this.speedIndexRanking= const [],
  });
}

/// 전체 파싱 결과 (경주 카드)
class ParsedRaceCard {
  final ParsedRaceHeader header;
  final List<ParsedHorseEntry> horses;
  final ParsedDataTips dataTips;
  final DateTime parsedAt;
  final String rawText;       // 원본 텍스트 (디버깅용)
  final List<String> warnings;

  const ParsedRaceCard({
    required this.header,
    required this.horses,
    required this.dataTips,
    required this.parsedAt,
    this.rawText  = '',
    this.warnings = const [],
  });

  /// SharedPreferences 저장 키
  String get cacheKey =>
    'parsed_race_card:${header.venue}:${header.raceNo}';
}

// ─────────────────────────────────────────────────────────────────────────
//  EntryTextParser — 메인 파서 클래스
// ─────────────────────────────────────────────────────────────────────────
class EntryTextParser {

  // ── SharedPreferences 저장 키 접두사 ──────────────────────────────────
  static const String _kCardPrefix = 'parsed_race_card:';
  static const String _kTrackPerfPrefix = 'horse_track_perf:';
  static const String _kAdvStatPrefix   = 'horse_adv_stat:';

  // ── 원형 숫자 → 정수 매핑 ──────────────────────────────────────────────
  static const Map<String, int> _circleNums = {
    '①': 1, '②': 2, '③': 3, '④': 4, '⑤': 5,
    '⑥': 6, '⑦': 7, '⑧': 8, '⑨': 9, '⑩': 10, '⑪': 11,
  };

  // ── 상금 단위 변환 패턴 (내부 사용) ──────────────────────────────────

  // ══════════════════════════════════════════════════════════════════════
  //  메인 파싱 엔트리포인트
  // ══════════════════════════════════════════════════════════════════════
  static ParsedRaceCard parse(String rawText) {
    final warnings = <String>[];

    try {
      // 1) 경주 헤더 파싱
      final header = _parseRaceHeader(rawText, warnings);

      // 2) DATA TIPS 구간 분리 (하단)
      final dataTipsIndex = rawText.indexOf('DATA');
      final mainText = dataTipsIndex > 0
          ? rawText.substring(0, dataTipsIndex)
          : rawText;
      final dataTipsText = dataTipsIndex > 0
          ? rawText.substring(dataTipsIndex)
          : '';

      // 3) 마필 블록 분리 및 파싱
      final horseBlocks = _splitHorseBlocks(mainText);
      final horses = <ParsedHorseEntry>[];

      for (final block in horseBlocks) {
        try {
          final h = _parseHorseBlock(block, header.distance, warnings);
          if (h != null) horses.add(h);
        } catch (e) {
          warnings.add('마필 파싱 오류: $e');
        }
      }

      // 4) DATA TIPS 파싱
      ParsedDataTips dataTips = const ParsedDataTips();
      if (dataTipsText.isNotEmpty) {
        try {
          dataTips = _parseDataTips(dataTipsText, horses, warnings);
        } catch (e) {
          warnings.add('DATA TIPS 파싱 오류: $e');
        }
      }

      // 5) DATA TIPS 지표를 HorseAdvancedStat에 병합
      final mergedHorses = _mergeDataTipsIntoAdvancedStat(
        horses, dataTips, warnings,
      );

      return ParsedRaceCard(
        header:   header,
        horses:   mergedHorses,
        dataTips: dataTips,
        parsedAt: DateTime.now(),
        rawText:  rawText.length > 2000
            ? rawText.substring(0, 2000) + '...[truncated]'
            : rawText,
        warnings: warnings,
      );
    } catch (e, st) {
      warnings.add('최상위 파싱 오류: $e\n$st');
      return ParsedRaceCard(
        header:   const ParsedRaceHeader(),
        horses:   [],
        dataTips: const ParsedDataTips(),
        parsedAt: DateTime.now(),
        warnings: warnings,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  1. 경주 헤더 파싱
  // ══════════════════════════════════════════════════════════════════════
  static ParsedRaceHeader _parseRaceHeader(String text, List<String> warnings) {
    // 경주장 추출 (예: "서울 2경주" → 서울, 2)
    String venue = '서울';
    int raceNo = 1;
    int distance = 1700;
    int moisture = 0;
    String grade = '';

    // 경주장명 패턴
    final venueMatch = RegExp(r'(서울|부산경남|제주)\s+(\d+)경주').firstMatch(text);
    if (venueMatch != null) {
      venue  = venueMatch.group(1)!;
      raceNo = int.tryParse(venueMatch.group(2)!) ?? 1;
    }

    // 거리 패턴 (예: 1700M)
    final distMatch = RegExp(r'(\d{3,4})\s*M').firstMatch(text);
    if (distMatch != null) {
      distance = int.tryParse(distMatch.group(1)!) ?? 1700;
    }

    // 등급 패턴 (예: 국6등급)
    final gradeMatch = RegExp(r'([국외혼]\d등급|[GⅠⅡⅢ]+등급?)').firstMatch(text);
    if (gradeMatch != null) grade = gradeMatch.group(0)!;

    // 함수율: [부담중량,함수율] 구간에서 추출 또는 최고기록 행에서 추출
    final moistureMatch = RegExp(r'\([\d.]+\s*,\s*(-|\d+)\)').firstMatch(text);
    if (moistureMatch != null) {
      final val = moistureMatch.group(1);
      if (val != null && val != '-') moisture = int.tryParse(val) ?? 0;
    }

    // 1위 상금
    String prize1st = '';
    final prizeMatch = RegExp(r'1위\s*([\d,]+천원)').firstMatch(text);
    if (prizeMatch != null) prize1st = prizeMatch.group(1)!;

    return ParsedRaceHeader(
      venue:    venue,
      raceNo:   raceNo,
      distance: distance,
      grade:    grade,
      moisture: moisture,
      prize1st: prize1st,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  2. 마필 블록 분리
  //  패턴: 줄 시작의 "숫자+한글" 마번·마명 조합으로 분리
  // ══════════════════════════════════════════════════════════════════════
  static List<String> _splitHorseBlocks(String text) {
    // 마번 패턴: 1~11번이 줄 시작 또는 공백 후에 위치
    // 예: "1브리도갤럭시", "11세명피크"
    final horseStartPattern = RegExp(
      r'(?:^|\n)\s*(\d{1,2})\s*([가-힣]{2,}(?:\s+[가-힣]+)*)',
      multiLine: true,
    );

    final matches = horseStartPattern.allMatches(text).toList();
    if (matches.isEmpty) return [];

    final blocks = <String>[];
    for (int i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end   = i + 1 < matches.length ? matches[i + 1].start : text.length;
      final block = text.substring(start, end).trim();
      // 마번이 1~11 범위인지 확인
      final gateNo = int.tryParse(matches[i].group(1)!);
      if (gateNo != null && gateNo >= 1 && gateNo <= 11 && block.length > 30) {
        blocks.add(block);
      }
    }
    return blocks;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  3. 개별 마필 블록 파싱
  // ══════════════════════════════════════════════════════════════════════
  static ParsedHorseEntry? _parseHorseBlock(
    String block, int raceDistance, List<String> warnings,
  ) {
    // ── 마번·마명 추출 ───────────────────────────────────────────────────
    final gateNameMatch = RegExp(
      r'^\s*(\d{1,2})\s*([가-힣\s]+?)(?=\n|\d|\s{3})',
      multiLine: true,
    ).firstMatch(block);
    if (gateNameMatch == null) return null;

    final gateNo   = int.tryParse(gateNameMatch.group(1)!) ?? 0;
    final horseName = gateNameMatch.group(2)!
        .replaceAll(RegExp(r'\s+'), '').trim();
    if (gateNo < 1 || gateNo > 11 || horseName.isEmpty) return null;

    // ── 부마/모마 파싱 (` - ` 구분자) ────────────────────────────────────
    String sire = '', dam = '';
    final parentMatch = RegExp(
      r'([가-힣A-Za-z·\s]+?)\s+-\s+([가-힣A-Za-z·\s]+)',
    ).firstMatch(block.substring(0, block.length.clamp(0, 200)));
    if (parentMatch != null) {
      sire = parentMatch.group(1)!.trim();
      dam  = parentMatch.group(2)!.trim();
      // 지나치게 긴 경우 제한
      if (sire.length > 30) sire = sire.substring(0, 30);
      if (dam.length  > 30) dam  = dam.substring(0, 30);
    }

    // ── 성별·출생년도 파싱 ───────────────────────────────────────────────
    // 예: "3거(230213)흑갈색" → 3세, 거(거세), 2023년생
    String sex = '';
    int birthYear = 0;
    final ageSexMatch = RegExp(
      r'(\d)세?\s*(수|암|거|牡|牝)\s*\((\d{6})\)',
    ).firstMatch(block);
    if (ageSexMatch != null) {
      sex       = ageSexMatch.group(2)!;
      final yy  = ageSexMatch.group(3)!.substring(0, 2);
      birthYear = 2000 + (int.tryParse(yy) ?? 0);
    }

    // ── 기수명 파싱 ──────────────────────────────────────────────────────
    // 기수명은 마번·마명 다음 줄 또는 부담중량 옆에 위치
    // 패턴: 단독 한글 2~4자 이름 (기수 특유 패턴)
    String jockeyName = '';
    // "조수영(11승)" 패턴으로 기수 추출
    final jockeyMatch = RegExp(
      r'([가-힣]{2,4})\s*\(\s*(\d+)승\s*\)',
    ).firstMatch(block.substring(0, block.length.clamp(0, 500)));
    if (jockeyMatch != null) {
      jockeyName = jockeyMatch.group(1)!;
    }

    // ── 조교사명 파싱 ─────────────────────────────────────────────────────
    // 패턴: "(15조)정하백 11승(9.6%)"
    String trainerCode = '', trainerName = '';
    final trainerMatch = RegExp(
      r'\((\d+)조\)\s*([가-힣]{2,4})\s+\d+승',
    ).firstMatch(block);
    if (trainerMatch != null) {
      trainerCode = trainerMatch.group(1)!;
      trainerName = trainerMatch.group(2)!;
    }

    // ── 부담중량 파싱 ─────────────────────────────────────────────────────
    // 패턴: "57.0( +0.5)" 또는 "55.0( -2.0)" 또는 "54.0( -3.0)-3권중석"
    double wgBudam = 55.0, wgBudamChange = 0.0;
    final budamMatch = RegExp(
      r'([\d.]+)\s*\(\s*([+-][\d.]+)\s*\)',
    ).firstMatch(block.substring(0, block.length.clamp(0, 400)));
    if (budamMatch != null) {
      wgBudam       = double.tryParse(budamMatch.group(1)!) ?? 55.0;
      wgBudamChange = double.tryParse(budamMatch.group(2)!.replaceAll(' ', '')) ?? 0.0;
    }

    // ── 마체중 파싱 ───────────────────────────────────────────────────────
    // 패턴: "484+3복5.7주로" → 484kg, +3변화
    int weight = 0, weightChange = 0;
    // 최근 경주 구간에서 체중 추출 (3자리 숫자 + [+-]숫자)
    final weightMatch = RegExp(
      r'(\d{3})\s*([+-]\d+)\s*복',
    ).firstMatch(block);
    if (weightMatch != null) {
      weight       = int.tryParse(weightMatch.group(1)!) ?? 0;
      weightChange = int.tryParse(weightMatch.group(2)!) ?? 0;
    }

    // ── 최고기록/평균기록 파싱 ────────────────────────────────────────────
    // 패턴: "최1:54.8(260329, 56.5, 3%, ⑤/11)" 또는 "최-없음"
    String bestTime = '', avgTime = '';
    final bestMatch = RegExp(r'최\s*(-없음|[\d:]+\.[\d]+)').firstMatch(block);
    if (bestMatch != null) {
      final val = bestMatch.group(1)!;
      bestTime = val == '-없음' ? '' : val;
    }
    final avgMatch = RegExp(r'평\s*(-없음|[\d:]+\.[\d]+)').firstMatch(block);
    if (avgMatch != null) {
      final val = avgMatch.group(1)!;
      avgTime = val == '-없음' ? '' : val;
    }

    // ── 통산 전적 파싱 ───────────────────────────────────────────────────
    // 패턴: "9전(  -/  1/  -/  2/  -)" → total=9, 각 착순 개수
    int careerTotal = 0, careerWin = 0, careerPlace = 0,
        careerShow = 0, careerFourth = 0, careerFifth = 0;
    final careerMatch = RegExp(
      r'(\d+)전\s*\(\s*(-|\s*\d+)\s*/\s*(-|\s*\d+)\s*/\s*(-|\s*\d+)\s*/\s*(-|\s*\d+)\s*/\s*(-|\s*\d+)\s*\)',
    ).firstMatch(block);
    if (careerMatch != null) {
      careerTotal  = int.tryParse(careerMatch.group(1)!) ?? 0;
      int _v(String? s) => int.tryParse(s?.trim() ?? '-') ?? 0;
      careerWin    = _v(careerMatch.group(2));
      careerPlace  = _v(careerMatch.group(3));
      careerShow   = _v(careerMatch.group(4));
      careerFourth = _v(careerMatch.group(5));
      careerFifth  = _v(careerMatch.group(6));
    }

    // ── 통산 상금 파싱 ───────────────────────────────────────────────────
    // 패턴: "2,700천원" 또는 "24,150천원" 또는 "9,600천원"
    int totalPrize = 0;
    // 전적 직후 상금 패턴
    final prizeLineMatch = RegExp(
      r'\)\s*　?([\d,]+)\s*(천원|만원|억원)',
    ).firstMatch(block.substring(0, block.length.clamp(0, 600)));
    if (prizeLineMatch != null) {
      totalPrize = _parsePrizeAmount(
        prizeLineMatch.group(1)!, prizeLineMatch.group(2)!,
      );
    }

    // ── 최근 성적 문자열 파싱 ────────────────────────────────────────────
    // 패턴: 연속 숫자+공백+* (예: "9*598", "775*96476*")
    // 마필 카드에서 성적 숫자 문자열 추출
    String recentRecord = '';
    final recentMatch = RegExp(
      r'([\d*]{3,20})\s+\d+주',
    ).firstMatch(block.substring(0, block.length.clamp(0, 800)));
    if (recentMatch != null) {
      recentRecord = recentMatch.group(1)!
          .replaceAll('*', '취')
          .split('').join(' ');
    }

    // ── 주로별 전적 파싱 (건/양/다/포/불) ───────────────────────────────
    final trackPerf = _parseTrackRecord(block, gateNo, horseName);

    // ── 최근 4경주 블록 파싱 ─────────────────────────────────────────────
    final pastRaces = _parsePastRaceBlocks(block, warnings);

    // ── HorseAdvancedStat 기본값 (DATA TIPS에서 병합 예정) ──────────────
    // 통산 승률 계산
    final careerWinRate  = careerTotal > 0 ? careerWin / careerTotal : 0.0;
    final careerPlaceRate= careerTotal > 0 ? (careerWin + careerPlace) / careerTotal : 0.0;

    final advancedStat = HorseAdvancedStat(
      horseGateNo:    gateNo,
      horseName:      horseName,
      careerWinRate:  careerWinRate,
      careerPlaceRate:careerPlaceRate,
      distanceMeters: raceDistance,
    );

    return ParsedHorseEntry(
      gateNo:          gateNo,
      horseName:       horseName,
      sex:             sex,
      birthYear:       birthYear,
      sire:            sire,
      dam:             dam,
      jockeyName:      jockeyName,
      trainerCode:     trainerCode,
      trainerName:     trainerName,
      wgBudam:         wgBudam,
      wgBudamChange:   wgBudamChange,
      weight:          weight,
      weightChange:    weightChange,
      bestTime:        bestTime,
      avgTime:         avgTime,
      careerTotal:     careerTotal,
      careerWin:       careerWin,
      careerPlace:     careerPlace,
      careerShow:      careerShow,
      careerFourth:    careerFourth,
      careerFifth:     careerFifth,
      totalPrize:      totalPrize,
      recentRecord:    recentRecord,
      pastRaces:       pastRaces,
      trackPerformance:trackPerf,
      advancedStat:    advancedStat,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  4. 최근 4경주 블록 파싱
  // ══════════════════════════════════════════════════════════════════════
  static List<PastRaceBlock> _parsePastRaceBlocks(
    String block, List<String> warnings,
  ) {
    final pastRaces = <PastRaceBlock>[];

    // 날짜 블록 헤더 패턴 (예: "260329서3R국6 1700별A맑3%(0)")
    final headerPattern = RegExp(
      r'(\d{6})([가-힣])\s*(\d{1,2})R([가-힣]+\d?)\s+(\d{3,4})([가-힣]+[A-Z]?)\s*([가-힣]+)\s*(\d+)%\s*\((\d+)\)',
    );

    final headers = headerPattern.allMatches(block).toList();
    if (headers.isEmpty) return pastRaces;

    for (int i = 0; i < headers.length && i < 4; i++) {
      final h = headers[i];
      try {
        final dateCode  = h.group(1)!;
        final venue     = h.group(2)!;
        final raceNoStr = h.group(3)!;
        final grade     = h.group(4)!;
        final distStr   = h.group(5)!;
        final condition = h.group(6)!;
        final weather   = h.group(7)!;
        final moistStr  = h.group(8)!;
        final totalStr  = h.group(9)!;

        // 이 블록의 텍스트 범위
        final blockStart = h.end;
        final blockEnd   = i + 1 < headers.length
            ? headers[i + 1].start
            : block.length;
        final subBlock = block.substring(blockStart, blockEnd);

        // 착순 라인 파싱 (원형 숫자 기반)
        final finishes = <PastRaceFinish>[];
        // 패턴: ① 5럭키조이1:52.7 56.5 기원(1)
        final finishPattern = RegExp(
          r'([①②③④⑤⑥⑦⑧⑨⑩⑪])\s*(\d{1,2})([가-힣A-Za-z]+(?:[가-힣A-Za-z]+)*)\s*([\d:]+\.[\d]+)\s*([\d.]+)\s+([가-힣]+)\s*\(',
        );

        for (final fm in finishPattern.allMatches(subBlock)) {
          final rank     = _circleNums[fm.group(1)] ?? 0;
          final gateNo   = int.tryParse(fm.group(2)!) ?? 0;
          final hName    = fm.group(3)!.trim();
          final time     = fm.group(4)!;
          final wt       = double.tryParse(fm.group(5)!) ?? 55.0;
          finishes.add(PastRaceFinish(
            rank:      rank,
            gateNo:    gateNo,
            horseName: hName,
            raceTime:  time,
            weight:    wt,
          ));
          if (finishes.length >= 6) break; // 최대 6착까지
        }

        // selfRank 추출: 해당 마필의 착순을 서브블록에서 직접 추출
        // (finishes가 비어있어도 subBlock에서 마지막 라인으로 유추)
        int selfRank = 0;
        if (finishes.isNotEmpty) {
          // 가장 큰 착순 번호가 해당 마필일 가능성 높음 (보통 마지막에 기록)
          selfRank = finishes.last.rank;
        }

        pastRaces.add(PastRaceBlock(
          dateCode:    dateCode,
          venue:       venue,
          raceNo:      int.tryParse(raceNoStr) ?? 1,
          grade:       grade,
          distance:    int.tryParse(distStr) ?? 1700,
          condition:   condition,
          weather:     weather,
          moisture:    int.tryParse(moistStr) ?? 0,
          selfRank:    selfRank,
          totalHorses: int.tryParse(totalStr) ?? 11,
          finishes:    finishes,
        ));
      } catch (e) {
        warnings.add('과거경주 블록 파싱 오류: $e');
      }
    }

    return pastRaces;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  5. 주로별 전적 파싱 (건/양/다/포/불)
  // ══════════════════════════════════════════════════════════════════════
  static HorseTrackPerformance _parseTrackRecord(
    String block, int gateNo, String horseName,
  ) {
    // 패턴 예시: "건 -/ -/ - 양 -/ -/ - 다 -/ -/ - 포 -/ -/ - 불 -/ -/ -"
    // 또는:      "건 -/ -/1 양 -/ -/ - 다 -/ -/ - ..."
    // 전적형:    "건 4/1/2"
    TrackRecord _parseOne(String key, String text) {
      // key 뒤의 전적 패턴 추출
      final pattern = RegExp(
        '$key\\s*(-?\\s*\\d+|-)\\s*/\\s*(-?\\s*\\d+|-)\\s*/\\s*(-?\\s*\\d+|-)',
      );
      final m = pattern.firstMatch(text);
      if (m == null) return TrackRecord.zero;
      int _n(String? s) {
        if (s == null || s.trim() == '-' || s.trim().isEmpty) return 0;
        return int.tryParse(s.trim()) ?? 0;
      }
      final total  = _n(m.group(1));
      final first  = _n(m.group(2));
      final second = _n(m.group(3));
      return TrackRecord(
        total:  total < 0 ? 0 : total,
        first:  first  < 0 ? 0 : first,
        second: second < 0 ? 0 : second,
      );
    }

    return HorseTrackPerformance(
      horseGateNo: gateNo,
      horseName:   horseName,
      dry:   _parseOne('건', block),
      good:  _parseOne('양', block),
      soft:  _parseOne('다', block),
      heavy: _parseOne('포', block),
      bad:   _parseOne('불', block),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  6. DATA TIPS 파싱  ── 마명(horseName) 딕셔너리 기반 역추적 매핑 ──
  // ══════════════════════════════════════════════════════════════════════
  //
  //  [설계 원칙]
  //  1) 마명(horseName)을 Key로 삼는 Map<String, int> nameToGate 빌드
  //     → 마번+공백 없이 "11세명피크" 형식도 마명으로 gateNo 역추적
  //  2) 섹션 추출 후 각 줄을 _parseDtLine() 으로 {gateNo, name, value} 추출
  //     → gateNo 먼저 시도, 실패 시 마명 딕셔너리에서 역방향 조회
  //  3) 속도지수 섹션 끝 탐지: '\n\n' 우선 탐지, 없으면 파일 끝까지
  //  4) 상금 단위: 백만/억원/만원/천원 모두 처리
  //  5) 속도지수 fallback: 미등재 마필 → 경주군 평균값 (디폴트85 하드코딩 제거)
  //
  static ParsedDataTips _parseDataTips(
    String dataTipsText,
    List<ParsedHorseEntry> horses,
    List<String> warnings,
  ) {
    // ── Step 0: 마명 → 마번 역방향 딕셔너리 구축 ──────────────────────
    // 공백 제거·초성 일치 등 fuzzy 처리: 마명 정규화 후 Map 구성
    final nameToGate = <String, int>{};
    for (final h in horses) {
      // 원본 마명
      nameToGate[h.horseName.trim()] = h.gateNo;
      // 공백 제거 버전 (다음절 마명 공백 오류 대응)
      nameToGate[h.horseName.replaceAll(' ', '')] = h.gateNo;
    }

    // ── 헬퍼: 한 줄에서 (마번, 마명, 숫자값) 추출 ─────────────────────
    // 지원 형식:
    //   "9 블랙마마 14.0"       (공백구분)
    //   "11세명피크 13.7"       (마번+마명 붙여쓰기)
    //   "11 세명피크 13.7"      (표준)
    //   "6 레전드매치 94"       (속도지수)
    //   "9 블랙마마 16.7%"      (승률)
    //   "8 명품족 1:53.3"       (최고기록)
    //   "11 세명피크 9.9백만"   (상금)
    //   "2 온누리빛 94pt"       (레이팅)

    // 패턴A: 마번 + 공백 + 마명 + 공백 + 값
    final linePatternA = RegExp(
      r'^\s*(\d{1,2})\s+([가-힣]{2,8}(?:\s+[가-힣]{1,4})?)\s+([\d:.]+(?:\.\d)?(?:pt|%|백만|억원|만원|천원)?)',
      multiLine: true,
    );
    // 패턴B: 마번 + 마명(공백없음) + 공백 + 값  → "11세명피크 13.7"
    final linePatternB = RegExp(
      r'^\s*(\d{1,2})([가-힣]{2,8})\s+([\d:.]+(?:\.\d)?(?:pt|%|백만|억원|만원|천원)?)',
      multiLine: true,
    );

    // 단일 섹션 전체 파싱: Map<int gateNo, double value>
    Map<int, double> parseSectionDouble(
      String section,
      double Function(String raw) valueParser,
    ) {
      final result = <int, double>{};
      void tryAdd(int gateNo, String nameRaw, String valRaw) {
        if (gateNo < 1 || gateNo > 16) return;
        final v = valueParser(valRaw);
        if (v <= 0) return;
        result.putIfAbsent(gateNo, () => v);
      }

      for (final m in linePatternA.allMatches(section)) {
        int gateNo = int.tryParse(m.group(1)!) ?? 0;
        final nameRaw = m.group(2)!.trim();
        final valRaw  = m.group(3)!.trim();
        // 마명 역추적 교차검증: gateNo가 이미 nameToGate와 다른 경우 보정
        if (gateNo == 0) {
          gateNo = nameToGate[nameRaw] ??
                   nameToGate[nameRaw.replaceAll(' ', '')] ?? 0;
        }
        tryAdd(gateNo, nameRaw, valRaw);
      }
      // 패턴A 매칭 실패한 줄 → 패턴B로 재시도
      for (final m in linePatternB.allMatches(section)) {
        int gateNo = int.tryParse(m.group(1)!) ?? 0;
        final nameRaw = m.group(2)!.trim();
        final valRaw  = m.group(3)!.trim();
        if (gateNo == 0) {
          gateNo = nameToGate[nameRaw] ??
                   nameToGate[nameRaw.replaceAll(' ', '')] ?? 0;
        }
        tryAdd(gateNo, nameRaw, valRaw);
      }
      return result;
    }

    // 최고기록(mm:ss.d) 파싱용 별도 헬퍼
    Map<int, String> parseSectionBestTime(String section) {
      final result = <int, String>{};
      final bestPat = RegExp(
        r'^\s*(\d{1,2})\s*([가-힣]{2,8}(?:\s+[가-힣]{1,4})?)\s+(\d:\d{2}\.\d)',
        multiLine: true,
      );
      for (final m in bestPat.allMatches(section)) {
        int gateNo = int.tryParse(m.group(1)!) ?? 0;
        final nameRaw = m.group(2)!.trim();
        if (gateNo == 0) gateNo = nameToGate[nameRaw] ?? 0;
        if (gateNo >= 1 && gateNo <= 16) {
          result.putIfAbsent(gateNo, () => m.group(3)!);
        }
      }
      return result;
    }

    // 상금 금액 파싱 (단위 변환 포함)
    double parseMoneyVal(String raw) {
      // "9.9백만" → 9900000, "1.2억원" → 120000000, "24.2백만" → 24200000
      final mBaek = RegExp(r'([\d.]+)백만').firstMatch(raw);
      if (mBaek != null) {
        return (double.tryParse(mBaek.group(1)!) ?? 0.0) * 1000000;
      }
      final mEok = RegExp(r'([\d.]+)억원').firstMatch(raw);
      if (mEok != null) {
        return (double.tryParse(mEok.group(1)!) ?? 0.0) * 100000000;
      }
      final mMan = RegExp(r'([\d.]+)만원').firstMatch(raw);
      if (mMan != null) {
        return (double.tryParse(mMan.group(1)!) ?? 0.0) * 10000;
      }
      final mCheon = RegExp(r'([\d.]+)천원').firstMatch(raw);
      if (mCheon != null) {
        return (double.tryParse(mCheon.group(1)!) ?? 0.0) * 1000;
      }
      return double.tryParse(raw.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
    }

    // ── Step 1: 섹션별 파싱 실행 ──────────────────────────────────────

    // 1-1. 레이팅 (단위: pt)
    final ratingSection = _extractSection(dataTipsText, '레이팅', '1700m');
    final ratingMap = parseSectionDouble(ratingSection, (v) {
      return double.tryParse(v.replaceAll('pt', '').trim()) ?? 0.0;
    });

    // 1-2. 거리별 승률 (단위: %)
    final winSection = _extractSection(
        dataTipsText,
        RegExp(r'\d+m\s*승률').firstMatch(dataTipsText)?.group(0) ?? '승률',
        RegExp(r'\d+m\s*최고기록').firstMatch(dataTipsText)?.group(0) ?? '최고기록');
    final distWinMap = parseSectionDouble(winSection, (v) {
      return (double.tryParse(v.replaceAll('%', '').trim()) ?? 0.0) / 100.0;
    });

    // 1-3. 거리별 최고기록 (mm:ss.d)
    final bestSection = _extractSection(
        dataTipsText,
        RegExp(r'\d+m\s*최고기록').firstMatch(dataTipsText)?.group(0) ?? '최고기록',
        '최근 1년');
    final distBestMap = parseSectionBestTime(bestSection);

    // 1-4. 최근 1년 상금
    final prize1Section = _extractSection(dataTipsText, '최근 1년 상금', '최근 6개월 상금');
    final prize1Map = parseSectionDouble(prize1Section, parseMoneyVal);

    // 1-5. 최근 6개월 상금
    final prize6Section = _extractSection(dataTipsText, '최근 6개월 상금', '초반 200m');
    final prize6Map = parseSectionDouble(prize6Section, parseMoneyVal);

    // 1-6. 초반 200m (S1F) — 단위: 초(소수)
    final s1fSection = _extractSection(dataTipsText, '초반 200m', '종반 200m');
    final s1fMap = parseSectionDouble(s1fSection, (v) {
      return double.tryParse(v) ?? 0.0;
    });

    // 1-7. 종반 200m (G1F) — 단위: 초(소수)
    // 섹션 끝: '속도지수' 키워드 먼저, 없으면 파일 끝
    final g1fSection = _extractSection(dataTipsText, '종반 200m', '속도지수');
    final g1fMap = parseSectionDouble(g1fSection, (v) {
      return double.tryParse(v) ?? 0.0;
    });

    // 1-8. 속도지수 — 섹션 끝: 빈 줄 or 파일 끝 (둘 다 처리)
    // _extractSectionToEnd가 파일 끝까지 반환 → 안전
    final speedSection = _extractSectionToEnd(dataTipsText, '속도지수');
    final speedMap = parseSectionDouble(speedSection, (v) {
      final n = double.tryParse(v.replaceAll(RegExp(r'[^\d.]'), '').trim());
      return (n != null && n >= 50 && n <= 150) ? n : 0.0;
    });

    // ── Step 2: MapEntry 리스트로 변환 ────────────────────────────────
    List<MapEntry<int, T>> toEntries<T>(Map<int, T> m) =>
        m.entries.map((e) => MapEntry(e.key, e.value)).toList();

    return ParsedDataTips(
      ratingRanking:      toEntries(ratingMap),
      distWinRanking:     toEntries(distWinMap),
      distBestRanking:    toEntries(distBestMap),
      prize1YearRanking:  toEntries(prize1Map)
          .map((e) => MapEntry(e.key, e.value.round())).toList(),
      prize6MonthRanking: toEntries(prize6Map)
          .map((e) => MapEntry(e.key, e.value.round())).toList(),
      s1fRanking:         toEntries(s1fMap),
      g1fRanking:         toEntries(g1fMap),
      speedIndexRanking:  toEntries(speedMap),
    );
  }

  // ── DATA TIPS 구간 텍스트 추출 헬퍼 (섹션 시작→다음 섹션) ──────────
  static String _extractSection(String text, String startKey, String endKey) {
    final si = text.indexOf(startKey);
    if (si < 0) return '';
    final ei = text.indexOf(endKey, si + startKey.length);
    return ei > si
        ? text.substring(si + startKey.length, ei)
        : text.substring(si + startKey.length);
  }

  // ── 섹션 시작 → 파일 끝까지 (속도지수처럼 마지막 섹션용) ─────────
  static String _extractSectionToEnd(String text, String startKey) {
    final si = text.indexOf(startKey);
    if (si < 0) return '';
    // 빈 줄 (\n\n) 우선 탐지 → 없으면 파일 끝까지
    final ei = text.indexOf('\n\n', si + startKey.length);
    return ei > si
        ? text.substring(si + startKey.length, ei)
        : text.substring(si + startKey.length);
  }

  // ══════════════════════════════════════════════════════════════════════
  //  7. DATA TIPS → HorseAdvancedStat 병합
  // ══════════════════════════════════════════════════════════════════════
  static List<ParsedHorseEntry> _mergeDataTipsIntoAdvancedStat(
    List<ParsedHorseEntry> horses,
    ParsedDataTips tips,
    List<String> warnings,
  ) {
    // ── 경주군 평균값 계산 (fallback용) ──────────────────────────────
    // s1f/g1f: 실측값만 평균 (0값 제외)
    final s1fActual = tips.s1fRanking.where((e) => e.value > 0).toList();
    final g1fActual = tips.g1fRanking.where((e) => e.value > 0).toList();
    final speedActual = tips.speedIndexRanking.where((e) => e.value > 0).toList();

    final avgS1f = s1fActual.isNotEmpty
        ? s1fActual.map((e) => e.value).reduce((a, b) => a + b) / s1fActual.length
        : 13.5;
    final avgG1f = g1fActual.isNotEmpty
        ? g1fActual.map((e) => e.value).reduce((a, b) => a + b) / g1fActual.length
        : 13.8;
    // 속도지수 평균: 하드코딩 85 대신 실측 평균 사용
    final avgSpeed = speedActual.isNotEmpty
        ? speedActual.map((e) => e.value).reduce((a, b) => a + b) / speedActual.length
        : 88.0; // 일반적인 경주 평균 속도지수

    // ── 주행스타일 판정 임계값 동적 계산 ────────────────────────────
    // S1F 범위 기반: 경주군 최소-최대 차이의 20%를 임계값으로 설정
    final s1fMin = s1fActual.isNotEmpty
        ? s1fActual.map((e) => e.value).reduce((a, b) => a < b ? a : b) : avgS1f;
    final s1fMax = s1fActual.isNotEmpty
        ? s1fActual.map((e) => e.value).reduce((a, b) => a > b ? a : b) : avgS1f;
    final g1fMin = g1fActual.isNotEmpty
        ? g1fActual.map((e) => e.value).reduce((a, b) => a < b ? a : b) : avgG1f;
    final g1fMax = g1fActual.isNotEmpty
        ? g1fActual.map((e) => e.value).reduce((a, b) => a > b ? a : b) : avgG1f;

    // 임계값: 범위의 20% (최소 0.1초)
    final s1fThreshold = ((s1fMax - s1fMin) * 0.20).clamp(0.10, 0.50);
    final g1fThreshold = ((g1fMax - g1fMin) * 0.20).clamp(0.10, 0.50);

    return horses.map((horse) {
      // ── DATA TIPS에서 해당 마번 데이터 조회 (마번 기준 직접 조회) ──
      double distWinRate = 0.0;
      String distBestTime = '';
      int prize1Year = 0, prize6Month = 0;
      // 실측값 없으면 null (평균 대입은 아래에서 처리)
      double? s1fTimeRaw, g1fTimeRaw, speedIndexRaw;

      // 거리별 승률
      final dwr = tips.distWinRanking
          .where((e) => e.key == horse.gateNo).firstOrNull;
      if (dwr != null) distWinRate = dwr.value;

      // 거리별 최고기록
      final dbr = tips.distBestRanking
          .where((e) => e.key == horse.gateNo).firstOrNull;
      if (dbr != null) distBestTime = dbr.value;

      // 최근 상금
      final p1 = tips.prize1YearRanking
          .where((e) => e.key == horse.gateNo).firstOrNull;
      if (p1 != null) prize1Year = p1.value;

      final p6 = tips.prize6MonthRanking
          .where((e) => e.key == horse.gateNo).firstOrNull;
      if (p6 != null) prize6Month = p6.value;

      // S1F — 실측값 저장 (fallback은 아래 주행스타일 분류 후)
      final s1 = tips.s1fRanking
          .where((e) => e.key == horse.gateNo).firstOrNull;
      if (s1 != null && s1.value > 0) s1fTimeRaw = s1.value;

      // G1F
      final g1 = tips.g1fRanking
          .where((e) => e.key == horse.gateNo).firstOrNull;
      if (g1 != null && g1.value > 0) g1fTimeRaw = g1.value;

      // 속도지수 — 실측값 없으면 null (평균값으로 나중에 채움)
      final si = tips.speedIndexRanking
          .where((e) => e.key == horse.gateNo).firstOrNull;
      if (si != null && si.value > 0) speedIndexRaw = si.value;

      // ── 주행 스타일 정밀 분류기 ───────────────────────────────────
      //
      //  [분류 로직]
      //  실측 s1f/g1f 모두 있는 경우만 분류 → 한쪽만 있으면 unknown
      //
      //  s1fRelative = horse.s1f - avgS1f
      //    음수 → 초반 빠름  (선행 후보)
      //    양수 → 초반 느림  (추입 후보)
      //
      //  g1fRelative = horse.g1f - avgG1f
      //    음수 → 종반 빠름  (추입 후보)
      //    양수 → 종반 느림  (선행 후보)
      //
      //  [임계값] 경주군 범위의 20% (동적 계산)
      //
      //  선행 (frontRunner):  s1f << avg AND g1f >> avg
      //  추입 (closer):       s1f >> avg AND g1f << avg
      //  선입 (stalker):      그 외 (초반 중간권 + 종반 중간권)
      //  unknown:             s1f/g1f 실측값 없음
      //
      RunningStyle style = RunningStyle.unknown;
      final double s1fTime;
      final double g1fTime;

      if (s1fTimeRaw != null && g1fTimeRaw != null) {
        s1fTime = s1fTimeRaw;
        g1fTime = g1fTimeRaw;
        final s1fRelative = s1fTime - avgS1f; // 음수 = 초반 빠름
        final g1fRelative = g1fTime - avgG1f; // 음수 = 종반 빠름

        if (s1fRelative <= -s1fThreshold && g1fRelative >= g1fThreshold) {
          style = RunningStyle.frontRunner;  // 선행: 초반↑ 종반↓
        } else if (s1fRelative >= s1fThreshold && g1fRelative <= -g1fThreshold) {
          style = RunningStyle.closer;       // 추입: 초반↓ 종반↑
        } else if (s1fRelative <= 0 && g1fRelative <= 0) {
          // 초반/종반 모두 평균보다 빠름 → 선입(stalker)
          style = RunningStyle.stalker;
        } else if (s1fRelative <= -s1fThreshold) {
          // 초반만 빠름, 종반은 평균 → 선행 경향
          style = RunningStyle.frontRunner;
        } else if (g1fRelative <= -g1fThreshold) {
          // 종반만 빠름, 초반은 평균 → 추입 경향
          style = RunningStyle.closer;
        } else {
          style = RunningStyle.stalker;      // 선입: 나머지
        }
      } else if (s1fTimeRaw != null) {
        // s1f만 있음: 초반 기록만으로 분류
        s1fTime = s1fTimeRaw;
        g1fTime = avgG1f; // 종반 fallback
        final s1fRelative = s1fTime - avgS1f;
        style = s1fRelative <= -s1fThreshold
            ? RunningStyle.frontRunner
            : s1fRelative >= s1fThreshold
                ? RunningStyle.stalker
                : RunningStyle.stalker;
      } else if (g1fTimeRaw != null) {
        // g1f만 있음: 종반 기록만으로 분류
        s1fTime = avgS1f; // 초반 fallback
        g1fTime = g1fTimeRaw;
        final g1fRelative = g1fTime - avgG1f;
        style = g1fRelative <= -g1fThreshold
            ? RunningStyle.closer
            : RunningStyle.stalker;
      } else {
        // 실측값 없음 → 평균값 사용 + unknown
        s1fTime = avgS1f;
        g1fTime = avgG1f;
        style = RunningStyle.unknown;
      }

      // 속도지수: 실측값 우선, 없으면 경주군 평균 (하드코딩 85 제거)
      final double speedIndex = speedIndexRaw ?? avgSpeed;

      // ── 업데이트된 HorseAdvancedStat 생성 ─────────────────────────
      final updatedStat = HorseAdvancedStat(
        horseGateNo:    horse.gateNo,
        horseName:      horse.horseName,
        rating:         horse.advancedStat.rating,
        careerWinRate:  horse.advancedStat.careerWinRate,
        careerPlaceRate:horse.advancedStat.careerPlaceRate,
        distanceMeters: horse.advancedStat.distanceMeters,
        distWinRate:    distWinRate,
        distBestTime:   distBestTime.isNotEmpty
            ? distBestTime : horse.bestTime,
        prize1Year:     prize1Year > 0 ? prize1Year : horse.totalPrize,
        prize6Month:    prize6Month,
        s1fTime:        s1fTime,
        g1fTime:        g1fTime,
        speedIndex:     speedIndex,
        runningStyle:   style,
      );

      return ParsedHorseEntry(
        gateNo:          horse.gateNo,
        horseName:       horse.horseName,
        sex:             horse.sex,
        birthYear:       horse.birthYear,
        sire:            horse.sire,
        dam:             horse.dam,
        jockeyName:      horse.jockeyName,
        trainerCode:     horse.trainerCode,
        trainerName:     horse.trainerName,
        wgBudam:         horse.wgBudam,
        wgBudamChange:   horse.wgBudamChange,
        weight:          horse.weight,
        weightChange:    horse.weightChange,
        bestTime:        horse.bestTime,
        avgTime:         horse.avgTime,
        careerTotal:     horse.careerTotal,
        careerWin:       horse.careerWin,
        careerPlace:     horse.careerPlace,
        careerShow:      horse.careerShow,
        careerFourth:    horse.careerFourth,
        careerFifth:     horse.careerFifth,
        totalPrize:      horse.totalPrize,
        recentRecord:    horse.recentRecord,
        pastRaces:       horse.pastRaces,
        trackPerformance:horse.trackPerformance,
        advancedStat:    updatedStat,
      );
    }).toList();
  }

  // ══════════════════════════════════════════════════════════════════════
  //  SharedPreferences 저장 메서드
  // ══════════════════════════════════════════════════════════════════════

  /// ParsedRaceCard → SharedPreferences 저장
  static Future<void> saveToCache(ParsedRaceCard card) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 경주 카드 전체 저장
      final cardKey = '$_kCardPrefix${card.header.venue}:${card.header.raceNo}';
      final cardData = {
        'parsedAt': card.parsedAt.toIso8601String(),
        'header':   card.header.toJson(),
        'horseCount': card.horses.length,
        'warnings': card.warnings,
      };
      await prefs.setString(cardKey, jsonEncode(cardData));

      // 마필별 TrackPerformance + AdvancedStat 저장
      for (final horse in card.horses) {
        // HorseTrackPerformance
        final tpKey = '$_kTrackPerfPrefix${card.header.venue}:${card.header.raceNo}:${horse.gateNo}';
        await prefs.setString(tpKey, jsonEncode(horse.trackPerformance.toJson()));

        // HorseAdvancedStat
        final asKey = '$_kAdvStatPrefix${card.header.venue}:${card.header.raceNo}:${horse.gateNo}';
        await prefs.setString(asKey, jsonEncode(horse.advancedStat.toJson()));
      }

      // 전체 마필 목록 (홈화면 표시용 요약)
      final summaryKey = 'parsed_horses:${card.header.venue}:${card.header.raceNo}';
      final summaryList = card.horses.map((h) => {
        'gateNo':      h.gateNo,
        'horseName':   h.horseName,
        'jockeyName':  h.jockeyName,
        'wgBudam':     h.wgBudam,
        'weight':      h.weight,
        'weightChange':h.weightChange,
        'recentRecord':h.recentRecord,
        'bestTime':    h.bestTime,
        'speedIndex':  h.advancedStat.speedIndex,
        'runningStyle':h.advancedStat.runningStyle.index,
        'prize6Month': h.advancedStat.prize6Month,
        'careerWinRate':h.advancedStat.careerWinRate,
        'pastRaceCount':h.pastRaces.length,
        // 최근 4경주 착순 (홈화면 표시용)
        'recentRanks': h.pastRaces.map((r) => r.selfRank).toList(),
      }).toList();
      await prefs.setString(summaryKey, jsonEncode(summaryList));

      if (kDebugMode) {
        debugPrint('[EntryTextParser] 💾 저장 완료: '
          '${card.header.venue} ${card.header.raceNo}경주 '
          '/ ${card.horses.length}마필');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[EntryTextParser] ❌ 저장 오류: $e');
    }
  }

  /// 저장된 마필 요약 데이터 로드 (홈화면 표시용)
  static Future<List<Map<String, dynamic>>?> loadHorseSummary({
    required String venue,
    required int raceNo,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'parsed_horses:$venue:$raceNo';
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final list = jsonDecode(raw) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      return null;
    }
  }

  /// 저장된 HorseAdvancedStat 로드
  static Future<HorseAdvancedStat?> loadAdvancedStat({
    required String venue,
    required int raceNo,
    required int gateNo,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kAdvStatPrefix$venue:$raceNo:$gateNo';
      final raw = prefs.getString(key);
      if (raw == null) return null;
      return HorseAdvancedStat.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      return null;
    }
  }

  /// 저장된 HorseTrackPerformance 로드
  static Future<HorseTrackPerformance?> loadTrackPerformance({
    required String venue,
    required int raceNo,
    required int gateNo,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kTrackPerfPrefix$venue:$raceNo:$gateNo';
      final raw = prefs.getString(key);
      if (raw == null) return null;
      return HorseTrackPerformance.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      return null;
    }
  }

  /// 파싱 결과 존재 여부 확인
  static Future<bool> hasParsedData({
    required String venue,
    required int raceNo,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'parsed_horses:$venue:$raceNo';
      return prefs.containsKey(key);
    } catch (e) {
      return false;
    }
  }

  /// 모든 파싱 데이터 목록 조회
  static Future<List<Map<String, dynamic>>> listAllParsedCards() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys()
          .where((k) => k.startsWith(_kCardPrefix))
          .toList();
      final result = <Map<String, dynamic>>[];
      for (final key in keys) {
        final raw = prefs.getString(key);
        if (raw != null) {
          try {
            final data = jsonDecode(raw) as Map<String, dynamic>;
            result.add({
              'key': key,
              ...data,
            });
          } catch (_) {}
        }
      }
      result.sort((a, b) {
        final ta = a['parsedAt'] as String? ?? '';
        final tb = b['parsedAt'] as String? ?? '';
        return tb.compareTo(ta); // 최신순
      });
      return result;
    } catch (e) {
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  유틸리티 메서드
  // ══════════════════════════════════════════════════════════════════════

  /// 상금 문자열 → 정수(원) 변환
  static int _parsePrizeAmount(String numStr, String unit) {
    final clean = numStr.replaceAll(',', '');
    final value = double.tryParse(clean) ?? 0.0;
    switch (unit) {
      case '천원': return (value * 1000).round();
      case '만원': return (value * 10000).round();
      case '억원': return (value * 100000000).round();
      default:     return value.round();
    }
  }

  /// 주행 스타일 한국어 레이블
  static String runningStyleLabel(RunningStyle style) {
    switch (style) {
      case RunningStyle.frontRunner: return '선행';
      case RunningStyle.stalker:     return '선입';
      case RunningStyle.closer:      return '추입';
      case RunningStyle.unknown:     return '-';
    }
  }

  /// 파싱 결과 검증 로그 (인젝션 테스트용)
  static String generateInjectionTestLog(ParsedRaceCard card) {
    final sb = StringBuffer();
    sb.writeln('═══════ 파싱 인젝션 테스트 로그 ═══════');
    sb.writeln('경주: ${card.header.venue} ${card.header.raceNo}경주 '
        '${card.header.distance}m');
    sb.writeln('파싱일시: ${card.parsedAt}');
    sb.writeln('마필수: ${card.horses.length}');
    if (card.warnings.isNotEmpty) {
      sb.writeln('⚠️ 경고 ${card.warnings.length}건:');
      for (final w in card.warnings) {
        sb.writeln('  - $w');
      }
    }
    sb.writeln('');
    sb.writeln('── 마필별 파싱 결과 ──');
    for (final h in card.horses) {
      sb.writeln('${h.gateNo}번 ${h.horseName}');
      sb.writeln('  기수: ${h.jockeyName}  부담중량: ${h.wgBudam}kg'
          '  마체중: ${h.weight}kg');
      sb.writeln('  최고기록: ${h.bestTime.isNotEmpty ? h.bestTime : "없음"}'
          '  평균기록: ${h.avgTime.isNotEmpty ? h.avgTime : "없음"}');
      sb.writeln('  통산: ${h.careerTotal}전 ${h.careerWin}승'
          '  승률: ${(h.advancedStat.careerWinRate * 100).toStringAsFixed(1)}%');
      sb.writeln('  주행스타일: ${runningStyleLabel(h.advancedStat.runningStyle)}'
          '  속도지수: ${h.advancedStat.speedIndex.toStringAsFixed(0)}');
      sb.writeln('  S1F: ${h.advancedStat.s1fTime.toStringAsFixed(1)}초'
          '  G1F: ${h.advancedStat.g1fTime.toStringAsFixed(1)}초');
      sb.writeln('  최근6개월상금: ${(h.advancedStat.prize6Month / 1000000).toStringAsFixed(1)}백만원');
      sb.writeln('  최근경주수: ${h.pastRaces.length}경주');
      // 주로 전적
      final tp = h.trackPerformance;
      sb.writeln('  주로전적 건:${tp.dry.total}/${tp.dry.first}/${tp.dry.second}'
          ' 양:${tp.good.total}/${tp.good.first}/${tp.good.second}'
          ' 다:${tp.soft.total}/${tp.soft.first}/${tp.soft.second}'
          ' 포:${tp.heavy.total}/${tp.heavy.first}/${tp.heavy.second}'
          ' 불:${tp.bad.total}/${tp.bad.first}/${tp.bad.second}');
      sb.writeln('');
    }
    sb.writeln('═══════════════════════════════════════');
    return sb.toString();
  }
}
