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
                  return _buildContent(race, horses);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

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
          Consumer<RaceProvider>(
            builder: (_, p, __) => Text(
              p.selectedRace != null
                  ? '${p.selectedRace!.venueCode == "1" ? "서울" : p.selectedRace!.venueCode == "2" ? "부산경남" : "제주"} 제${p.selectedRace!.raceNo}경주'
                  : 'AI 분석 기반 특이사항',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

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

  Widget _buildContent(RaceInfo race, List<HorseEntry> horses) {
    final sorted = [...horses]..sort(
        (a, b) => b.finalScore.compareTo(a.finalScore));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRaceOverview(race, horses),
          const SizedBox(height: 16),
          _buildApiInsightSection(sorted),
          const SizedBox(height: 16),
          _buildHorseSpecialInfo(sorted),
          const SizedBox(height: 16),
          _buildWeightAlertSection(sorted),
          const SizedBox(height: 16),
          _buildOddsSection(sorted),
        ],
      ),
    );
  }

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
              Expanded(
                child: _overviewChip('📍 경주장', venueLabel,
                    const Color(0xFF64B5F6)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _overviewChip('📏 거리', '${race.distance}m',
                    const Color(0xFFFFD700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _overviewChip('🐎 출전두수', '${horses.length}두',
                    const Color(0xFF81C784)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _overviewChip('🔄 방향', dirLabel,
                    const Color(0xFFFF8A65)),
              ),
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
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 9.5)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildApiInsightSection(List<HorseEntry> sorted) {
    final winner  = sorted.isNotEmpty ? sorted[0] : null;
    final darkhorse = sorted.length > 1
        ? sorted.firstWhere(
            (h) => h.odds > 10.0,
            orElse: () => sorted.last,
          )
        : null;
    final bestCond = [...sorted]
      ..sort((a, b) => b.formStat.compareTo(a.formStat));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('🔎 AI 분석 주요 인사이트'),
        const SizedBox(height: 10),
        if (winner != null)
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
        if (darkhorse != null)
          _insightCard(
            '💣 복병 주목마',
            '${darkhorse.gateNo}번 ${darkhorse.horseName}  '
            '배당 ${darkhorse.odds.toStringAsFixed(1)}배',
            '높은 배당 대비 스테미나 ${darkhorse.staminaStat.toStringAsFixed(0)} — 후반 역전 가능성',
            const Color(0xFFFF7043),
          ),
        const SizedBox(height: 8),
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

  Widget _buildHorseSpecialInfo(List<HorseEntry> sorted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('🐎 출전마 특이사항'),
        const SizedBox(height: 10),
        ...sorted.map((h) {
          final cd    = HorseCapColors.getCapData(h.gateNo);
          final alerts = _getHorseAlerts(h);
          if (alerts.isEmpty) return const SizedBox.shrink();

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1A2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1A2A3A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(h.horseName,
                              style: const TextStyle(
                                  color: Colors.white,
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
                        children: alerts.map((a) => Container(
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
                Text('${h.finalScore.toStringAsFixed(1)}pt',
                    style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 13, fontWeight: FontWeight.w800)),
              ],
            ),
          );
        }),
      ],
    );
  }

  List<(String, Color)> _getHorseAlerts(HorseEntry h) {
    final alerts = <(String, Color)>[];
    if (h.speedStat > 80) { alerts.add(('⚡ 고속 선행', const Color(0xFFFFD700))); }
    if (h.staminaStat > 80) { alerts.add(('💪 후반 강세', const Color(0xFF81C784))); }
    if (h.formStat > 80) { alerts.add(('📈 최상 컨디션', const Color(0xFF64B5F6))); }
    if (h.odds < 5.0) { alerts.add(('🏆 인기마', const Color(0xFFFF7043))); }
    if (h.odds > 20.0) { alerts.add(('💣 고배당 복병', const Color(0xFFE91E63))); }
    if (h.finalScore > 70) { alerts.add(('🤖 AI 추천', const Color(0xFFB388FF))); }
    return alerts;
  }

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
              // 부담중량 보정값 시뮬레이션
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

  Widget _buildOddsSection(List<HorseEntry> sorted) {
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
              final oddColor = h.odds < 5.0
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
                      child: Text(h.horseName,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                          overflow: TextOverflow.ellipsis),
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
