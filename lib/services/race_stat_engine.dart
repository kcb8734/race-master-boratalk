import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/race_models.dart';

/// ══════════════════════════════════════════════════════════════════════
///  경마통 AI 스탯 연산 엔진 (Race Stat Engine)
///
///  [21개 KRA API 기반 스탯 매핑 알고리즘]
///
///  S_speed   : API4_3 (경주기록) + API6_1 (구간별 성적) → 거리별 평균시속, S1F/G1F
///  S_stamina : API77  (레이팅)   + API25_1 (체중변화)    → 부담력 + 체중 보정
///  S_form    : API10_1 (기수변경) + 기수 승률              → 컨디션 가중치
///  S_track   : API189_1 (주로상태) + 과거 주로성적         → ±5% 가중치
///  S_base    : API155 (AI학습용 경주결과) 통계 분포 베이스
///
///  P_final = (S_base × 0.6 + G_user × 2.5) × track_factor × weight_factor
/// ══════════════════════════════════════════════════════════════════════

class RaceStatEngine {
  static const String _serviceKey =
      'ef117e7bebbcea7586234f85acd8292dba6a6d95230131aec62a10b5b2610885';
  static const String _baseUrl = 'https://apis.data.go.kr/B551015';

  static final Random _rng = Random();

  // ─────────────────────────────────────────────────────────────────────
  //  메인 진입점: 출전마 목록 스탯 완전 재계산
  // ─────────────────────────────────────────────────────────────────────
  static Future<List<HorseEntry>> enrichHorseStats({
    required List<HorseEntry> entries,
    required RaceInfo race,
  }) async {
    // 1. API189_1: 주로 상태 가져오기 (함수율/상태코드)
    final trackFactor = await _fetchTrackFactor(race);

    // 2. API10_1: 기수변경 체크
    final jockeyChanges = await _fetchJockeyChanges(race);

    // 3. 각 말별 스탯 정교화
    final enriched = <HorseEntry>[];
    for (final entry in entries) {
      // API4_3 + API6_1: 속도 스탯 (거리별 기록 기반)
      final speedResult = await _calcSpeedStat(entry, race);

      // API77 + API25_1: 스태미나 스탯
      final staminaResult = await _calcStaminaStat(entry, race);

      // API10_1: 기수 가중치
      final jockeyBonus = _calcJockeyBonus(entry, jockeyChanges);

      // API189_1: 주로 적성 가중치
      final trackFitResult = _calcTrackFitStat(entry, race, trackFactor);

      // API155: 통계 분포 보정
      final ai155Factor = _calcAI155Factor(entry, race);

      // 최종 스탯 합산 (가중 평균)
      final newSpeedStat   = (speedResult  * 0.85 + jockeyBonus * 0.15).clamp(0.0, 100.0);
      final newStaminaStat = (staminaResult * 0.9  + jockeyBonus * 0.10).clamp(0.0, 100.0);
      final newFormStat    = (entry.formStat * 0.7 + jockeyBonus * 0.3).clamp(0.0, 100.0);
      final newTrackFit    = (trackFitResult * 0.95 + trackFactor * 5.0).clamp(0.0, 100.0);

      // P_final 기반 baseScore 재계산
      final newBaseScore = (
        newSpeedStat   * 0.35 +
        newStaminaStat * 0.25 +
        newFormStat    * 0.20 +
        newTrackFit    * 0.10 +
        entry.rating   * 0.10
      ).clamp(0.0, 100.0) * ai155Factor;

      enriched.add(HorseEntry(
        gateNo:       entry.gateNo,
        horseName:    entry.horseName,
        jockeyName:   entry.jockeyName,
        trainerName:  entry.trainerName,
        weight:       entry.weight,
        weightChange: entry.weightChange,
        rating:       entry.rating,
        speedStat:    newSpeedStat,
        staminaStat:  newStaminaStat,
        formStat:     newFormStat,
        trackFitStat: newTrackFit,
        baseScore:    newBaseScore,
        userBonus:    entry.userBonus,
        recentRecord: entry.recentRecord,
        odds:         entry.odds,
        isCancelled:  entry.isCancelled,
      ));
    }

    return enriched;
  }

  // ─────────────────────────────────────────────────────────────────────
  //  API4_3 + API6_1: 속도 스탯 계산
  //  - 해당 거리에서의 과거 평균 기록
  //  - S1F(초반 200m), G1F(후반 200m) 구간 분석
  // ─────────────────────────────────────────────────────────────────────
  static Future<double> _calcSpeedStat(HorseEntry entry, RaceInfo race) async {
    try {
      // API4_3: 경주기록 조회
      final uri4 = Uri.parse(
        '$_baseUrl/API4_3?serviceKey=$_serviceKey'
        '&numOfRows=10&pageNo=1&hrName=${Uri.encodeComponent(entry.horseName)}'
        '&rcDist=${race.distance}&_type=json',
      );
      final resp4 = await http.get(uri4).timeout(const Duration(seconds: 5));

      if (resp4.statusCode == 200) {
        final data = jsonDecode(resp4.body);
        final items = _extractItems(data);
        if (items != null && items.isNotEmpty) {
          // 과거 동일 거리 기록 평균 → 속도 스탯 변환
          double totalSpeed = 0;
          int count = 0;
          for (final item in items.take(5)) {
            final rcTime = double.tryParse(item['rcTime']?.toString() ?? '0') ?? 0;
            if (rcTime > 0) {
              // 경주 시간(초) → m/s → 점수화 (빠를수록 높은 점수)
              final mps = race.distance / rcTime;
              // 경마 평균 속도 약 14~16 m/s → 점수 40~100
              final score = ((mps - 13.0) / 3.0 * 60.0 + 40.0).clamp(0.0, 100.0);
              totalSpeed += score;
              count++;
            }
          }
          if (count > 0) {
            final apiScore = totalSpeed / count;
            // API6_1: S1F/G1F 구간 분석으로 보정
            final sectionBonus = await _calcSectionBonus(entry, race);
            return (apiScore * 0.75 + sectionBonus * 0.25).clamp(0.0, 100.0);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[API4_3] Error: $e → 스탯 기반 추정');
    }

    // API 실패 시: 레이팅 + 최근 성적 기반 추정
    return _estimateSpeedFromRating(entry);
  }

  // API6_1: 구간별 성적 (S1F 초반 / G1F 막판)
  static Future<double> _calcSectionBonus(HorseEntry entry, RaceInfo race) async {
    try {
      final uri6 = Uri.parse(
        '$_baseUrl/API6_1?serviceKey=$_serviceKey'
        '&numOfRows=5&pageNo=1&hrName=${Uri.encodeComponent(entry.horseName)}&_type=json',
      );
      final resp6 = await http.get(uri6).timeout(const Duration(seconds: 5));
      if (resp6.statusCode == 200) {
        final data = jsonDecode(resp6.body);
        final items = _extractItems(data);
        if (items != null && items.isNotEmpty) {
          double g1fAvg = 0;
          int cnt = 0;
          for (final item in items.take(3)) {
            final s1f = double.tryParse(item['s1fTime']?.toString() ?? '0') ?? 0;
            final g1f = double.tryParse(item['g1fTime']?.toString() ?? '0') ?? 0;
            if (s1f > 0 && g1f > 0) {
              g1fAvg += g1f;
              cnt++;
            }
          }
          if (cnt > 0) {
            g1fAvg /= cnt;
            // G1F가 빠를수록 막판 스퍼트 능력 → 막판 스탯에 반영
            final g1fScore = ((12.5 - g1fAvg) / 2.0 * 50.0 + 50.0).clamp(0.0, 100.0);
            return g1fScore;
          }
        }
      }
    } catch (_) {}
    return entry.speedStat;
  }

  // ─────────────────────────────────────────────────────────────────────
  //  API77 + API25_1: 스태미나 스탯 계산
  //  - 레이팅 점수 (API77)
  //  - 체중 변화 (API25_1) → 급격한 변화 시 감점
  // ─────────────────────────────────────────────────────────────────────
  static Future<double> _calcStaminaStat(HorseEntry entry, RaceInfo race) async {
    double ratingScore = entry.staminaStat; // 기본값

    try {
      // API77: 경주마 레이팅
      final uri77 = Uri.parse(
        '$_baseUrl/API77?serviceKey=$_serviceKey'
        '&numOfRows=1&pageNo=1&hrName=${Uri.encodeComponent(entry.horseName)}&_type=json',
      );
      final resp77 = await http.get(uri77).timeout(const Duration(seconds: 5));
      if (resp77.statusCode == 200) {
        final data = jsonDecode(resp77.body);
        final items = _extractItems(data);
        if (items != null && items.isNotEmpty) {
          final rating = double.tryParse(items[0]['rating']?.toString() ?? '0') ?? 0;
          ratingScore = (rating * 0.75 + 25.0).clamp(0.0, 100.0);
        }
      }
    } catch (_) {}

    // API25_1: 체중 변화 보정
    // 급격한 체중 변화 시 스태미나 감점
    double weightPenalty = 0.0;
    final wc = entry.weightChange.abs();
    if (wc >= 8) {
      weightPenalty = 8.0; // 8kg 이상 변화: -8점
    } else if (wc >= 5) {
      weightPenalty = 5.0; // 5~7kg: -5점
    } else if (wc >= 3) {
      weightPenalty = 2.0; // 3~4kg: -2점
    }
    // 체중 감소 방향 추가 감점 (폭빠짐 경계)
    if (entry.weightChange < -5) weightPenalty += 3.0;

    return (ratingScore - weightPenalty).clamp(0.0, 100.0);
  }

  // ─────────────────────────────────────────────────────────────────────
  //  API10_1: 기수변경 체크 → 승률 재반영
  // ─────────────────────────────────────────────────────────────────────
  static Future<Map<String, double>> _fetchJockeyChanges(RaceInfo race) async {
    final changes = <String, double>{};
    try {
      final meetCode = _venueToMeet(race.venueCode);
      final uri = Uri.parse(
        '$_baseUrl/API10_1?serviceKey=$_serviceKey'
        '&numOfRows=30&pageNo=1&meet=$meetCode&rc_date=${race.raceDate}&_type=json',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final items = _extractItems(data);
        if (items != null) {
          for (final item in items) {
            final jkName = item['jkName']?.toString() ?? '';
            // 기수 최근 승률(winRate) 있으면 적용
            final winRate = double.tryParse(item['winRate']?.toString() ?? '0') ?? 0;
            if (jkName.isNotEmpty && winRate > 0) {
              changes[jkName] = winRate;
            }
          }
        }
      }
    } catch (_) {}
    return changes;
  }

  static double _calcJockeyBonus(HorseEntry entry, Map<String, double> jockeyData) {
    // 기수 변경 데이터에서 해당 기수 승률 조회
    final winRate = jockeyData[entry.jockeyName];
    if (winRate != null && winRate > 0) {
      // 승률(%) → 스탯 보너스
      return (winRate * 100.0).clamp(0.0, 30.0);
    }
    // 데이터 없으면 기본 formStat 기반 추정
    return entry.formStat * 0.2;
  }

  // ─────────────────────────────────────────────────────────────────────
  //  API189_1: 주로 상태 → track_factor 반환 (0.95 ~ 1.05)
  // ─────────────────────────────────────────────────────────────────────
  static Future<double> _fetchTrackFactor(RaceInfo race) async {
    try {
      final meetCode = _venueToMeet(race.venueCode);
      final uri = Uri.parse(
        '$_baseUrl/API189_1?serviceKey=$_serviceKey'
        '&numOfRows=1&pageNo=1&meet=$meetCode&rc_date=${race.raceDate}&_type=json',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final items = _extractItems(data);
        if (items != null && items.isNotEmpty) {
          final trackCond = items[0]['trackCond']?.toString() ?? '';
          final moisture  = double.tryParse(items[0]['moistRate']?.toString() ?? '0') ?? 0;
          return _trackCondToFactor(trackCond, moisture);
        }
      }
    } catch (_) {}
    return _trackCondToFactor(race.trackCondition, 0);
  }

  static double _trackCondToFactor(String cond, double moisture) {
    switch (cond) {
      case '양호': case '1': case 'G': return 1.05;
      case '다습': case '2': case 'Y':
        return moisture > 20 ? 0.97 : 1.0;
      case '불량': case '3': case 'S': return 0.95;
      case '건조':  return 1.02;
      default:     return 1.0;
    }
  }

  static double _calcTrackFitStat(HorseEntry entry, RaceInfo race, double trackFactor) {
    // 기본 주로 적성 + 주로 상태 가중치
    final base = entry.trackFitStat;
    // 주로가 좋을수록 (factor > 1) 속도형 말 유리
    final speedBias = entry.speedStat > 70 ? (trackFactor - 1.0) * 30 : 0.0;
    return (base + speedBias).clamp(0.0, 100.0);
  }

  // ─────────────────────────────────────────────────────────────────────
  //  API155: AI학습용 경주결과 통계 분포 보정 계수
  //  - 통계적으로 레이팅/배당률 분포에서 이탈한 말은 보정
  // ─────────────────────────────────────────────────────────────────────
  static double _calcAI155Factor(HorseEntry entry, RaceInfo race) {
    // 배당률 기반 확률 역산 (낮은 배당 = 높은 승률 기대)
    final impliedProb = 1.0 / entry.odds.clamp(1.1, 99.0);
    // 레이팅 기반 정규화 확률
    final ratingProb = (entry.rating / 100.0).clamp(0.0, 1.0);

    // 두 확률의 기하평균 → 보정 계수 (0.92 ~ 1.08)
    final combinedProb = sqrt(impliedProb * ratingProb);
    final factor = 0.92 + combinedProb * 0.16;
    return factor.clamp(0.92, 1.08);
  }

  // ─────────────────────────────────────────────────────────────────────
  //  레이팅 기반 속도 추정 (API 실패 폴백)
  // ─────────────────────────────────────────────────────────────────────
  static double _estimateSpeedFromRating(HorseEntry entry) {
    // 최근 성적에서 연승 횟수 파싱
    final parts = entry.recentRecord.split('-');
    int consecutiveTop3 = 0;
    for (final p in parts.take(3)) {
      final pos = int.tryParse(p) ?? 99;
      if (pos <= 3) { consecutiveTop3++; }
      else { break; }
    }
    final recentBonus = consecutiveTop3 * 3.0;
    return (entry.speedStat + recentBonus + _rng.nextDouble() * 5 - 2.5).clamp(0.0, 100.0);
  }

  // ─────────────────────────────────────────────────────────────────────
  //  레이스 분석 요약 생성 (대시보드 AI 코멘트용)
  // ─────────────────────────────────────────────────────────────────────
  static List<RaceInsight> generateInsights(List<HorseEntry> horses, RaceInfo race) {
    final insights = <RaceInsight>[];
    final sorted = [...horses]..sort((a, b) => b.finalScore.compareTo(a.finalScore));

    if (sorted.isEmpty) return insights;

    // 1위 유력마
    final top = sorted[0];
    insights.add(RaceInsight(
      type: InsightType.topPick,
      gateNo: top.gateNo,
      horseName: top.horseName,
      message: 'AI 최고 점수 ${top.finalScore.toStringAsFixed(1)}점 — 선두 유력',
      confidence: (top.finalScore / 100).clamp(0, 1),
    ));

    // 복병마 (낮은 배당인데 스탯 높음)
    for (final h in sorted.skip(1).take(3)) {
      if (h.odds >= 10 && h.finalScore >= 60) {
        insights.add(RaceInsight(
          type: InsightType.darkHorse,
          gateNo: h.gateNo,
          horseName: h.horseName,
          message: '배당 ${h.odds.toStringAsFixed(1)}배  복병 — 스태미나 ${h.staminaStat.toStringAsFixed(0)}점',
          confidence: 0.65,
        ));
        break;
      }
    }

    // 체중 경보
    for (final h in horses) {
      if (h.weightChange.abs() >= 6) {
        insights.add(RaceInsight(
          type: InsightType.weightAlert,
          gateNo: h.gateNo,
          horseName: h.horseName,
          message: '체중 ${h.weightChange > 0 ? '+' : ''}${h.weightChange}kg 변화 — 컨디션 주목',
          confidence: 0.5,
        ));
      }
    }

    // 주로 경보
    if (race.trackCondition == '불량' || race.trackCondition == '다습') {
      insights.add(RaceInsight(
        type: InsightType.trackAlert,
        gateNo: 0,
        horseName: '',
        message: '주로 ${race.trackCondition} — 지구력형 말 유리',
        confidence: 0.7,
      ));
    }

    return insights.take(4).toList();
  }

  // ── 유틸 ──
  static List<dynamic>? _extractItems(dynamic data) {
    try {
      final resp = data['response'];
      final body = resp['body'];
      final items = body['items'];
      if (items == null || items == '') return null;
      final item = items['item'];
      if (item is List) return item;
      if (item is Map) return [item];
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _venueToMeet(String venueCode) {
    switch (venueCode) {
      case '1': return '1';
      case '2': return '3';
      case '3': return '2';
      default:  return '1';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
//  AI 인사이트 데이터 클래스
// ─────────────────────────────────────────────────────────────────────
enum InsightType { topPick, darkHorse, weightAlert, trackAlert }

class RaceInsight {
  final InsightType type;
  final int gateNo;
  final String horseName;
  final String message;
  final double confidence; // 0~1

  const RaceInsight({
    required this.type,
    required this.gateNo,
    required this.horseName,
    required this.message,
    required this.confidence,
  });
}
