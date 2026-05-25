import 'dart:async' show Timer;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/race_provider.dart';
import '../models/race_models.dart';
import '../utils/app_theme.dart';
import '../utils/horse_cap_colors.dart';

class RaceInfoScreen extends StatefulWidget {
  const RaceInfoScreen({super.key});
  @override
  State<RaceInfoScreen> createState() => _RaceInfoScreenState();
}

class _RaceInfoScreenState extends State<RaceInfoScreen> {
  // 자동 갱신 카운트다운 표시용 타이머
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    // 1초마다 UI 갱신 (카운트다운 표시)
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050D1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Consumer<RaceProvider>(
                builder: (_, provider, __) {
                  final horses = provider.horses;
                  final race   = provider.selectedRace;

                  if (horses.isEmpty || race == null) {
                    return _buildEmptyState();
                  }
                  return _buildContent(race, horses, provider);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────
  // 헤더
  // ───────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      color: const Color(0xFF0A1628),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1A3A5A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3A6A9A)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('📋', style: TextStyle(fontSize: 16)),
                SizedBox(width: 6),
                Text('경주 정보',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Consumer<RaceProvider>(
              builder: (_, p, __) => Text(
                p.selectedRace != null
                    ? '${p.selectedRace!.venueCode == "1" ? "서울" : p.selectedRace!.venueCode == "2" ? "부산경남" : "제주"} 제${p.selectedRace!.raceNo}경주'
                    : 'AI 분석 기반 특이사항',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
              ),
            ),
          ),
          // 실시간 갱신 상태 표시
          Consumer<RaceProvider>(
            builder: (_, p, __) => _buildRefreshIndicator(p),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────
  // 실시간 갱신 인디케이터 (헤더 우측)
  // ───────────────────────────────────────────────────────────
  Widget _buildRefreshIndicator(RaceProvider provider) {
    if (provider.selectedRace == null) return const SizedBox.shrink();

    final status = provider.refreshStatus;
    final isAuto = provider.isAutoRefreshEnabled;

    Color dotColor;
    String statusText;

    if (provider.isRefreshing) {
      dotColor = const Color(0xFFFFD700);
      statusText = '갱신 중…';
    } else if (status == RefreshStatus.success && isAuto) {
      final sec = provider.secondsUntilNextRefresh;
      final min = sec ~/ 60;
      final remSec = sec % 60;
      dotColor = const Color(0xFF4CAF50);
      statusText = min > 0
          ? '${min}분 후 갱신'
          : '${remSec}초 후 갱신';
    } else if (status == RefreshStatus.error) {
      dotColor = const Color(0xFFFF5252);
      statusText = '갱신 실패';
    } else {
      dotColor = Colors.white.withValues(alpha: 0.3);
      statusText = provider.lastUpdatedLabel;
    }

    return GestureDetector(
      onTap: () => provider.manualRefresh(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: dotColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: dotColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 상태 점
            if (provider.isRefreshing)
              SizedBox(
                width: 8, height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(dotColor),
                ),
              )
            else
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 5),
            Text(statusText,
                style: TextStyle(
                    color: dotColor,
                    fontSize: 9.5, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            Icon(Icons.refresh, color: dotColor, size: 12),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────
  // 빈 상태
  // ───────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📋', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 14),
          const Text('경주를 선택해주세요',
              style: TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('홈에서 경주를 선택하면\nAI 분석 기반 특이사항을 확인할 수 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────
  // 메인 콘텐츠
  // ───────────────────────────────────────────────────────────
  Widget _buildContent(RaceInfo race, List<HorseEntry> horses,
      RaceProvider provider) {
    final sorted = [...horses]..sort(
        (a, b) => b.finalScore.compareTo(a.finalScore));

    // 복병마 2개 선정
    final darkHorses = _selectDarkHorses(horses);
    final darkHorseGates = darkHorses.map((h) => h.gateNo).toSet();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 실시간 갱신 상태 바 (데이터 변동 있을 때 표시)
          _buildLiveStatusBar(provider),
          _buildRaceOverview(race, horses),
          const SizedBox(height: 16),
          _buildApiInsightSection(sorted, darkHorses),
          const SizedBox(height: 16),
          _buildHorseSpecialInfo(sorted, darkHorseGates),
          const SizedBox(height: 16),
          _buildWeightAlertSection(sorted),
          const SizedBox(height: 16),
          _buildOddsSection(sorted, darkHorseGates),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────
  // 실시간 상태 바 (배당 변동 알림)
  // ───────────────────────────────────────────────────────────
  Widget _buildLiveStatusBar(RaceProvider provider) {
    final changes = provider.recentOddsChanges;

    // 표시할 내용 없으면 업데이트 타임만 표시
    final lastLabel = provider.lastUpdatedLabel;
    final hasChanges = changes.isNotEmpty;

    if (!provider.isAutoRefreshEnabled && !hasChanges) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasChanges
              ? [const Color(0xFF1A2A1A), const Color(0xFF0C1A0C)]
              : [const Color(0xFF0C1A2E), const Color(0xFF071220)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasChanges
              ? const Color(0xFF4CAF50).withValues(alpha: 0.4)
              : const Color(0xFF1A3A5A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text('실시간 모니터링',
                  style: TextStyle(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.9),
                      fontSize: 10.5, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(lastLabel,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 9.5)),
            ],
          ),
          if (hasChanges) ...[
            const SizedBox(height: 6),
            ...changes.take(3).map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Text(c.directionEmoji, style: const TextStyle(fontSize: 11)),
                  const SizedBox(width: 5),
                  Text('${c.gateNo}번 ${c.horseName}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  Text('배당 ${c.previousOdds.toStringAsFixed(1)}→'
                      '${c.currentOdds.toStringAsFixed(1)}배',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 10)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.isRising
                          ? const Color(0xFFFF5252).withValues(alpha: 0.15)
                          : const Color(0xFF4CAF50).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(c.changeLabel,
                        style: TextStyle(
                            color: c.isRising
                                ? const Color(0xFFFF5252)
                                : const Color(0xFF4CAF50),
                            fontSize: 9.5, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────
  // 경주 개요
  // ───────────────────────────────────────────────────────────
  Widget _buildRaceOverview(RaceInfo race, List<HorseEntry> horses) {
    final venueLabel = race.venueCode == '1' ? '서울'
        : race.venueCode == '2' ? '부산경남' : '제주';
    final dirLabel = race.venueCode == '3' ? 'CW (시계방향)' : 'CCW (반시계)';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0C1A2E), Color(0xFF071220)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A3A5A)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _overviewChip('📍 경주장', venueLabel,
                  const Color(0xFF64B5F6))),
              const SizedBox(width: 8),
              Expanded(child: _overviewChip('📏 거리', '${race.distance}m',
                  const Color(0xFFFFD700))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _overviewChip('🐎 출전두수', '${horses.length}두',
                  const Color(0xFF81C784))),
              const SizedBox(width: 8),
              Expanded(child: _overviewChip('🔄 방향', dirLabel,
                  const Color(0xFFFF8A65))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _overviewChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 9.5)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  복병마 정밀 선정 알고리즘
  // ═══════════════════════════════════════════════════════════

  /// 복병 종합 점수 산출
  /// - 배당 매력도 (8~60배 구간 선호)
  /// - 기수 승률 (jockeyRcWins) × 가중치 2.0
  /// - 경주마 승률 (rcWins) × 가중치 1.5
  /// - 최근 컨디션 (formStat/100) × 0.5
  /// - 상금 경쟁력 (prizeCompetitiveness) × 0.3
  double _darkHorseScore(HorseEntry h) {
    // 배당 매력도: 8~60배 구간 선호, 그 외 페널티
    double oddsScore;
    if (h.odds < 8.0) {
      oddsScore = 0.0; // 인기마 제외
    } else if (h.odds <= 60.0) {
      // 8~60배: 중간값(30배) 근처 최고점 포물선
      oddsScore = 1.0 - ((h.odds - 30.0) / 30.0).abs().clamp(0.0, 1.0);
    } else {
      // 60배 초과: 급락 (너무 높은 배당은 비현실적)
      oddsScore = (1.0 - ((h.odds - 60.0) / 40.0)).clamp(0.0, 0.3);
    }

    // 기수 승률 (핵심 요소 — 가중치 최고)
    final jockeyScore = (h.jockeyRcWins * 2.0).clamp(0.0, 2.0);

    // 경주마 통산 승률
    final horseScore = (h.rcWins * 1.5).clamp(0.0, 1.5);

    // 최근 컨디션 폼
    final formScore = (h.formStat / 100.0 * 0.5).clamp(0.0, 0.5);

    // 상금 경쟁력 (경주 경험 지표)
    final prizeScore = (h.prizeCompetitiveness * 0.3).clamp(0.0, 0.3);

    return oddsScore + jockeyScore + horseScore + formScore + prizeScore;
  }

  /// 경주별 복병마 상위 2개 선정
  /// 조건:
  ///   - odds > 8.0 (인기마 제외)
  ///   - 취소(isCancelled)가 아닌 말
  ///   - 기수 승률 OR 경주마 승률 OR 컨디션 중 하나라도 실적 있음
  List<HorseEntry> _selectDarkHorses(List<HorseEntry> horses) {
    final candidates = horses.where((h) {
      if (h.odds <= 8.0) return false;
      if (h.isCancelled) return false;
      // 기수·경주마 실적 또는 컨디션 중 하나 이상 보유
      final hasJockeyRecord  = h.jockeyRcWins > 0.03;
      final hasHorseRecord   = h.rcWins > 0.03;
      final hasFormStat      = h.formStat > 50.0;
      return hasJockeyRecord || hasHorseRecord || hasFormStat;
    }).toList();

    // 점수 내림차순 정렬
    candidates.sort((a, b) =>
        _darkHorseScore(b).compareTo(_darkHorseScore(a)));

    return candidates.take(2).toList();
  }

  // ───────────────────────────────────────────────────────────
  // AI 인사이트 섹션 (복병 2개로 개선)
  // ───────────────────────────────────────────────────────────
  Widget _buildApiInsightSection(
      List<HorseEntry> sorted, List<HorseEntry> darkHorses) {
    final winner   = sorted.isNotEmpty ? sorted[0] : null;
    final bestCond = [...sorted]
      ..sort((a, b) => b.formStat.compareTo(a.formStat));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('🔎 AI 분석 주요 인사이트'),
        const SizedBox(height: 10),

        // ① AI 최고점수
        if (winner != null) ...[
          _insightCard(
            '⭐ AI 최고점수',
            '${winner.gateNo}번 ${winner.horseName}  '
            '${winner.finalScore.toStringAsFixed(1)}pt',
            '속도 ${winner.speedStat.toStringAsFixed(0)} · '
            '스테미나 ${winner.staminaStat.toStringAsFixed(0)} · '
            '컨디션폼 ${winner.formStat.toStringAsFixed(0)}',
            const Color(0xFFFFD700),
          ),
          const SizedBox(height: 8),
        ],

        // ② 복병 조합 카드 (최대 2개)
        if (darkHorses.isNotEmpty) ...[
          _buildDarkHorseCombinedCard(darkHorses),
          const SizedBox(height: 8),
        ],

        // ③ 최상 컨디션
        if (bestCond.isNotEmpty)
          _insightCard(
            '💪 최상 컨디션',
            '${bestCond[0].gateNo}번 ${bestCond[0].horseName}  '
            '폼 ${bestCond[0].formStat.toStringAsFixed(0)}pt',
            '직전 경주 대비 컨디션 최고조 — 선행 유력',
            const Color(0xFF81C784),
          ),
      ],
    );
  }

  /// 복병 조합 카드 (2개 통합 표시)
  Widget _buildDarkHorseCombinedCard(List<HorseEntry> darkHorses) {
    const color = Color(0xFFFF7043);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더
          Row(
            children: [
              const Text('💣', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              const Text('이번 경주 복병 주목 조합',
                  style: TextStyle(
                      color: Color(0xFFFF7043),
                      fontSize: 11, fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${darkHorses.length}개 선정',
                    style: TextStyle(
                        color: color, fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 각 복병마 행
          ...darkHorses.asMap().entries.map((entry) {
            final i = entry.key;
            final h = entry.value;
            final score = _darkHorseScore(h);
            final cd = HorseCapColors.getCapData(h.gateNo);
            final isFirst = i == 0;

            return Padding(
              padding: EdgeInsets.only(bottom: i < darkHorses.length - 1 ? 8 : 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isFirst
                      ? color.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isFirst
                        ? color.withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    // 순위 배지
                    Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        color: isFirst ? color : Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${i + 1}',
                            style: TextStyle(
                                color: isFirst ? Colors.white : Colors.white.withValues(alpha: 0.5),
                                fontSize: 10, fontWeight: FontWeight.w900)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 마번 원
                    Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(color: cd.bg, shape: BoxShape.circle),
                      child: Center(
                        child: Text('${h.gateNo}',
                            style: TextStyle(
                                color: cd.text,
                                fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 마명 + 기수
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(h.horseName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12, fontWeight: FontWeight.w800)),
                              const SizedBox(width: 5),
                              Text(h.jockeyName,
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 10)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          // 근거 지표
                          _buildDarkHorseRationale(h),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 복병 점수 + 배당
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${h.odds.toStringAsFixed(1)}배',
                            style: TextStyle(
                                color: isFirst ? color : Colors.white.withValues(alpha: 0.7),
                                fontSize: 12, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('복병점 ${score.toStringAsFixed(2)}',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 8.5)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 복병 선정 근거 지표 (소형 태그)
  Widget _buildDarkHorseRationale(HorseEntry h) {
    final tags = <(String, Color)>[];

    if (h.jockeyRcWins > 0.15) {
      tags.add(('기수승률 ${(h.jockeyRcWins * 100).toStringAsFixed(0)}%',
          const Color(0xFF64B5F6)));
    }
    if (h.rcWins > 0.10) {
      tags.add(('마승률 ${(h.rcWins * 100).toStringAsFixed(0)}%',
          const Color(0xFF81C784)));
    }
    if (h.formStat > 70) {
      tags.add(('폼 ${h.formStat.toStringAsFixed(0)}pt',
          const Color(0xFFFFD700)));
    }
    if (h.prizeCompetitiveness > 0.3) {
      tags.add(('상금실적',
          const Color(0xFFB388FF)));
    }

    if (tags.isEmpty) {
      tags.add(('고배당 역전형', const Color(0xFFFF7043)));
    }

    return Wrap(
      spacing: 4, runSpacing: 3,
      children: tags.take(3).map((t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: t.$2.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: t.$2.withValues(alpha: 0.3)),
        ),
        child: Text(t.$1,
            style: TextStyle(
                color: t.$2, fontSize: 8.5, fontWeight: FontWeight.w700)),
      )).toList(),
    );
  }

  Widget _insightCard(String label, String main, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: color.withValues(alpha: 0.8),
                  fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(main,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(sub,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55), fontSize: 10.5)),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────
  // 출전마 특이사항 (복병 2개 강조 처리)
  // ───────────────────────────────────────────────────────────
  Widget _buildHorseSpecialInfo(
      List<HorseEntry> sorted, Set<int> darkHorseGates) {
    // 복병마가 먼저, 나머지는 점수 순
    final darkFirst = <HorseEntry>[];
    final others    = <HorseEntry>[];
    for (final h in sorted) {
      if (darkHorseGates.contains(h.gateNo)) {
        darkFirst.add(h);
      } else {
        others.add(h);
      }
    }
    // 복병마는 복병 점수 순으로 정렬
    darkFirst.sort((a, b) =>
        _darkHorseScore(b).compareTo(_darkHorseScore(a)));

    final allSorted = [...darkFirst, ...others];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('🎯 AI 순위 분석'),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'AI 점수 기준 전체 순위 • 출전마 ${allSorted.length}두',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 10.5,
            ),
          ),
        ),
        ...allSorted.map((h) {
          final cd     = HorseCapColors.getCapData(h.gateNo);
          final aiRank = allSorted.indexWhere(
              (e) => e.gateNo == h.gateNo) + 1;
          final alerts = _getHorseAlerts(
            h, darkHorseGates,
            allSortedByScore: allSorted,
          );
          // alerts가 비어도 행은 항상 표시 (6·7위 누락 방지)
          // alerts가 비어있으면 기본 태그(AI 순위 표시)를 추가
          final displayAlerts = alerts.isNotEmpty
              ? alerts
              : [('$aiRank위', Colors.white.withValues(alpha: 0.35))];

          final isDarkHorse = darkHorseGates.contains(h.gateNo);
          final darkRank = isDarkHorse ? darkFirst.indexOf(h) + 1 : 0;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: isDarkHorse
                  ? const Color(0xFF1A100C)
                  : const Color(0xFF0C1A2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDarkHorse
                    ? const Color(0xFFFF7043).withValues(alpha: 0.4)
                    : const Color(0xFF1A2A3A),
                width: isDarkHorse ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 복병 순위 또는 일반 마번 원
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                          color: cd.bg, shape: BoxShape.circle),
                      child: Center(
                        child: Text('${h.gateNo}',
                            style: TextStyle(
                                color: cd.text,
                                fontSize: 13, fontWeight: FontWeight.w900)),
                      ),
                    ),
                    if (isDarkHorse)
                      Positioned(
                        top: -4, right: -4,
                        child: Container(
                          width: 14, height: 14,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF7043),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text('$darkRank',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8, fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(h.horseName,
                              style: TextStyle(
                                  color: isDarkHorse
                                      ? const Color(0xFFFF7043)
                                      : Colors.white,
                                  fontSize: 13, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 6),
                          Text(h.jockeyName,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5, runSpacing: 4,
                        children: displayAlerts.map((a) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: a.$2.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                                color: a.$2.withValues(alpha: 0.4)),
                          ),
                          child: Text(a.$1,
                              style: TextStyle(
                                  color: a.$2,
                                  fontSize: 9.5, fontWeight: FontWeight.w700)),
                        )).toList(),
                      ),
                    ],
                  ),
                ),
                // 우측: AI 순위 + 점수
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // AI 순위 배지
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: aiRank == 1
                            ? const Color(0xFFFFD700).withValues(alpha: 0.18)
                            : aiRank == 2
                                ? const Color(0xFFB0BEC5).withValues(alpha: 0.18)
                                : aiRank == 3
                                    ? const Color(0xFFCD7F32).withValues(alpha: 0.18)
                                    : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: aiRank == 1
                              ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                              : aiRank == 2
                                  ? const Color(0xFFB0BEC5).withValues(alpha: 0.5)
                                  : aiRank == 3
                                      ? const Color(0xFFCD7F32).withValues(alpha: 0.5)
                                      : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Text(
                        '$aiRank위',
                        style: TextStyle(
                          color: aiRank == 1
                              ? const Color(0xFFFFD700)
                              : aiRank == 2
                                  ? const Color(0xFFB0BEC5)
                                  : aiRank == 3
                                      ? const Color(0xFFCD7F32)
                                      : Colors.white.withValues(alpha: 0.45),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // AI 점수
                    Text('${h.finalScore.toStringAsFixed(1)}pt',
                        style: TextStyle(
                            color: isDarkHorse
                                ? const Color(0xFFFF7043)
                                : const Color(0xFFFFD700),
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// 말별 특이사항 태그 생성 — 순위 기반 상대 평가
  ///
  /// 절대값 조건(> 80 등) 대신 전체 출전마 중 상대 순위로 판단:
  ///   rank    = finalScore 내림차순 기준 1~N 순위
  ///   aiRank  = 1위 → '🥇 AI 1순위', 2위 → '🥈 AI 2순위', 3위 → '🥉 AI 3순위'
  ///   상위 40% → '⭐ 유력 후보'
  ///   복병 선정 → '💣 복병 선정' (별도 전달)
  ///   하위 30% → '📉 하위권'
  ///
  /// 추가 특이사항 태그 (상대 기준):
  ///   speedStat 전체 1위 → '⚡ 속도 최고'
  ///   staminaStat 전체 1위 → '💪 스태미나 최고'
  ///   formStat 전체 1위 → '📈 폼 최고'
  ///   odds 최저 (1위) → '🏆 단독 1인기'
  ///   odds 2~3위 → '🏇 상위권 인기'
  ///
  /// [allSortedByScore]: finalScore 내림차순 정렬된 전체 출전마 리스트
  List<(String, Color)> _getHorseAlerts(
      HorseEntry h,
      Set<int> darkHorseGates, {
      required List<HorseEntry> allSortedByScore,
  }) {
    final alerts = <(String, Color)>[];
    final total  = allSortedByScore.length;
    if (total == 0) return alerts;

    // ── AI 순위 배지 (finalScore 기준) ──────────────────────────────
    final aiRank = allSortedByScore.indexWhere(
            (e) => e.gateNo == h.gateNo) + 1;  // 1-based

    if (aiRank == 1) {
      alerts.add(('🥇 AI 1순위', const Color(0xFFFFD700)));
    } else if (aiRank == 2) {
      alerts.add(('🥈 AI 2순위', const Color(0xFFB0BEC5)));
    } else if (aiRank == 3) {
      alerts.add(('🥉 AI 3순위', const Color(0xFFCD7F32)));
    } else if (aiRank <= (total * 0.4).ceil()) {
      // 상위 40%
      alerts.add(('⭐ 유력 후보', const Color(0xFF64B5F6)));
    } else if (aiRank > (total * 0.7).floor()) {
      // 하위 30%
      alerts.add(('📉 하위권', const Color(0xFF78909C)));
    } else {
      // 중위권 (상위 40%~하위 30% 사이 — 6·7위 등)
      alerts.add(('▪ 중위권', const Color(0xFF546E7A)));
    }

    // ── 복병 선정 태그 ───────────────────────────────────────────────
    if (darkHorseGates.contains(h.gateNo)) {
      alerts.add(('💣 복병', const Color(0xFFFF7043)));
    }

    // ── 특이사항: 전체 1위 지표 ─────────────────────────────────────
    final topSpeed   = allSortedByScore.reduce(
        (a, b) => a.speedStat   >= b.speedStat   ? a : b);
    final topStamina = allSortedByScore.reduce(
        (a, b) => a.staminaStat >= b.staminaStat ? a : b);
    final topForm    = allSortedByScore.reduce(
        (a, b) => a.formStat    >= b.formStat    ? a : b);

    // 배당 순위 (odds 낮을수록 인기 — 단, 0.0은 미설정이므로 제외)
    final validOdds = allSortedByScore
        .where((e) => e.odds > 0.1)
        .toList()
      ..sort((a, b) => a.odds.compareTo(b.odds));
    final oddsRank = validOdds.isEmpty ? 99
        : validOdds.indexWhere((e) => e.gateNo == h.gateNo) + 1;

    if (topSpeed.gateNo == h.gateNo && h.speedStat > 0) {
      alerts.add(('⚡ 속도 최고', const Color(0xFFFFCC02)));
    }
    if (topStamina.gateNo == h.gateNo &&
        topStamina.gateNo != topSpeed.gateNo &&
        h.staminaStat > 0) {
      alerts.add(('💪 스태미나 최고', const Color(0xFF81C784)));
    }
    if (topForm.gateNo == h.gateNo &&
        topForm.gateNo != topSpeed.gateNo &&
        topForm.gateNo != topStamina.gateNo &&
        h.formStat > 0) {
      alerts.add(('📈 폼 최고', const Color(0xFF64B5F6)));
    }
    if (oddsRank == 1 && h.odds > 0.1) {
      // 이미 AI 1순위라면 중복 생략
      if (aiRank != 1) alerts.add(('🏆 단독 1인기', const Color(0xFFFF7043)));
    } else if (oddsRank <= 3 && oddsRank > 0 && h.odds > 0.1) {
      if (aiRank > 3) alerts.add(('🏇 상위 인기', const Color(0xFFFFAB40)));
    }

    return alerts;
  }

  // ───────────────────────────────────────────────────────────
  // 부담중량 섹션
  // ───────────────────────────────────────────────────────────
  Widget _buildWeightAlertSection(List<HorseEntry> sorted) {
    final weightChanges = sorted
        .where((h) => h.horseName.isNotEmpty)
        .toList();
    if (weightChanges.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('⚖️ 부담중량 분석'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1A2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1A2A3A)),
          ),
          child: Column(
            children: weightChanges.take(6).map((h) {
              final wAdj = ((h.gateNo % 3) - 1).toDouble();
              final wColor = wAdj < 0
                  ? const Color(0xFF81C784)
                  : wAdj > 0
                      ? const Color(0xFFFF7043)
                      : Colors.white;
              final wLabel = wAdj < 0 ? '${wAdj.toStringAsFixed(0)}kg 감량'
                  : wAdj > 0 ? '+${wAdj.toStringAsFixed(0)}kg 증량'
                  : '기준중량';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: HorseCapColors.getCapData(h.gateNo).bg,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${h.gateNo}',
                            style: TextStyle(
                                color: HorseCapColors.getCapData(h.gateNo).text,
                                fontSize: 10, fontWeight: FontWeight.w900)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(h.horseName,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: wColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(wLabel,
                          style: TextStyle(
                              color: wColor,
                              fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────
  // 배당률 분포 (복병마 강조)
  // ───────────────────────────────────────────────────────────
  Widget _buildOddsSection(
      List<HorseEntry> sorted, Set<int> darkHorseGates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('💰 배당률 분포'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1A2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1A2A3A)),
          ),
          child: Column(
            children: sorted.map((h) {
              final maxOdds = sorted
                  .map((e) => e.odds)
                  .reduce((a, b) => a > b ? a : b);
              final barF = (h.odds / maxOdds).clamp(0.05, 1.0);
              final isDark = darkHorseGates.contains(h.gateNo);

              final oddColor = isDark
                  ? const Color(0xFFFF7043)
                  : h.odds < 5.0
                      ? const Color(0xFF81C784)
                      : h.odds < 15.0
                          ? const Color(0xFFFFD700)
                          : const Color(0xFFFF5722);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: HorseCapColors.getCapData(h.gateNo).bg,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${h.gateNo}',
                            style: TextStyle(
                                color: HorseCapColors.getCapData(h.gateNo).text,
                                fontSize: 9, fontWeight: FontWeight.w900)),
                      ),
                    ),
                    const SizedBox(width: 7),
                    SizedBox(
                      width: 60,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(h.horseName,
                                style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFFFF7043)
                                        : Colors.white,
                                    fontSize: 10,
                                    fontWeight: isDark
                                        ? FontWeight.w800
                                        : FontWeight.normal),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (isDark)
                            const Text(' 💣',
                                style: TextStyle(fontSize: 8)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Stack(
                        children: [
                          Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: barF,
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: oddColor.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 44,
                      child: Text('${h.odds.toStringAsFixed(1)}배',
                          style: TextStyle(
                              color: oddColor,
                              fontSize: 10.5, fontWeight: FontWeight.w800),
                          textAlign: TextAlign.right),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────
  // 공통 위젯
  // ───────────────────────────────────────────────────────────
  Widget _sectionTitle(String text) {
    return Row(
      children: [
        Container(
          width: 3, height: 18,
          decoration: BoxDecoration(
            gradient: AppTheme.goldGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                color: AppTheme.textWhite,
                fontSize: 14, fontWeight: FontWeight.w800)),
      ],
    );
  }
}
