import 'dart:async' show Timer;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/race_provider.dart';
import '../models/race_models.dart';
import '../services/entry_text_parser.dart';
import '../utils/app_theme.dart';
import '../utils/horse_cap_colors.dart';

// ══════════════════════════════════════════════════════════════════════════
//  RaceInfoScreen — 출전표 상세 분석 탭 (전면 개편 v2.0)
//
//  ▸ HorseCardList : 마필 카드 (기본정보 + TrendLine 꺾은선 + 주로전적)
//  ▸ Top5GridView  : 복승률/6개월상금/유전능력/거리기록 4카테고리 TOP5
//  ▸ SpeedBarChart : S1F(초반200m) / G1F(종반200m) 가로 바 차트
//  ▸ 파서 실시간 연동 + 데이터 누락 fallback 처리
// ══════════════════════════════════════════════════════════════════════════

class RaceInfoScreen extends StatefulWidget {
  const RaceInfoScreen({super.key});
  @override
  State<RaceInfoScreen> createState() => _RaceInfoScreenState();
}

class _RaceInfoScreenState extends State<RaceInfoScreen>
    with SingleTickerProviderStateMixin {
  Timer? _uiTimer;
  late TabController _tabController;

  // ── 파서 연동 데이터 ──────────────────────────────────────────────────
  Map<int, ParsedHorseEntry> _parsedHorseMap = {};
  bool _hasParsedData = false;
  bool _isLoadingParsed = false;

  // ── TOP5 파서 데이터 (PDF 구조 기반) ─────────────────────────────────
  /// 마번 → 유전능력 점수 (parsedHorseMap advancedStat 기반 fallback)
  Map<int, double> _geneticScoreMap = {};
  /// 마번 → 거리기록 추정 문자열
  Map<int, String> _distanceRecordMap = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadParsedData());
  }

  // ── 파서 데이터 로드 ──────────────────────────────────────────────────
  Future<void> _loadParsedData() async {
    if (_isLoadingParsed) return;
    setState(() => _isLoadingParsed = true);
    try {
      final provider = Provider.of<RaceProvider>(context, listen: false);
      final race = provider.selectedRace;
      if (race == null) return;

      final venueName = _venueCodeToName(race.venueCode);
      final raceNo = int.tryParse(race.raceNo) ?? 1;

      final summary = await EntryTextParser.loadHorseSummary(
        venue: venueName, raceNo: raceNo,
      );
      if (summary == null || summary.isEmpty) return;

      final map = <int, ParsedHorseEntry>{};
      final genMap = <int, double>{};
      final distMap = <int, String>{};

      for (final s in summary) {
        final gateNo   = (s['gateNo']       as int?) ?? 0;
        final name     = (s['horseName']    as String?) ?? '';
        final jockey   = (s['jockeyName']   as String?) ?? '';
        final budam    = (s['wgBudam']      as num?)?.toDouble() ?? 55.0;
        final weight   = (s['weight']       as int?) ?? 0;
        final wChg     = (s['weightChange'] as int?) ?? 0;
        final recent   = (s['recentRecord'] as String?) ?? '';
        final best     = (s['bestTime']     as String?) ?? '';
        final speedIdx = (s['speedIndex']   as num?)?.toDouble() ?? 0.0;
        final styleIdx = (s['runningStyle'] as int?) ?? RunningStyle.unknown.index;
        final prize6m  = (s['prize6Month']  as int?) ?? 0;
        final winRate  = (s['careerWinRate'] as num?)?.toDouble() ?? 0.0;
        final placeRate = (s['careerPlaceRate'] as num?)?.toDouble() ?? 0.0;
        final s1f      = (s['s1fTime']      as num?)?.toDouble() ?? 0.0;
        final g1f      = (s['g1fTime']      as num?)?.toDouble() ?? 0.0;
        final rawRanks = s['recentRanks'] as List<dynamic>?;
        final recentRanks = rawRanks?.map((r) => (r as int?) ?? 0).toList() ?? [];
        final distBest  = (s['distBestTime'] as String?) ?? '';
        final distWinR  = (s['distWinRate']  as num?)?.toDouble() ?? 0.0;

        if (gateNo < 1) continue;

        // 유전능력 점수: 파서 없을 때 speedIndex + prize6m 기반 추정
        final genScore = speedIdx > 0
            ? speedIdx + (prize6m / 1000000.0).clamp(0, 30)
            : 0.0;
        if (genScore > 0) genMap[gateNo] = genScore;

        // 거리기록 문자열
        if (distBest.isNotEmpty) distMap[gateNo] = distBest;

        final advStat = HorseAdvancedStat(
          horseGateNo:    gateNo,
          horseName:      name,
          careerWinRate:  winRate,
          careerPlaceRate: placeRate,
          speedIndex:     speedIdx,
          prize6Month:    prize6m,
          s1fTime:        s1f,
          g1fTime:        g1f,
          distBestTime:   distBest,
          distWinRate:    distWinR,
          runningStyle:   RunningStyle.values[styleIdx.clamp(0, RunningStyle.values.length - 1)],
        );

        map[gateNo] = ParsedHorseEntry(
          gateNo:       gateNo,
          horseName:    name,
          jockeyName:   jockey,
          wgBudam:      budam,
          weight:       weight,
          weightChange: wChg,
          recentRecord: recent,
          bestTime:     best,
          trackPerformance: HorseTrackPerformance(
            horseGateNo: gateNo, horseName: name,
          ),
          advancedStat: advStat,
          pastRaces: recentRanks.asMap().entries.map((e) => PastRaceBlock(
            dateCode:   '',
            venue:      '',
            raceNo:     e.key + 1,
            grade:      '',
            distance:   race.distance,
            condition:  '',
            weather:    '',
            moisture:   0,
            selfRank:   e.value,
            totalHorses: 11,
            finishes:   [],
          )).toList(),
        );
      }

      if (mounted && map.isNotEmpty) {
        setState(() {
          _parsedHorseMap = map;
          _geneticScoreMap = genMap;
          _distanceRecordMap = distMap;
          _hasParsedData = true;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingParsed = false);
    }
  }

  String _venueCodeToName(String code) {
    if (code == '2') return '부산경남';
    if (code == '3') return '제주';
    return '서울';
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════
  //  빌드
  // ══════════════════════════════════════════════════════════════════════
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
                  final race = provider.selectedRace;
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

  // ── 헤더 ────────────────────────────────────────────────────────────────
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
                Text('출전표 분석',
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
                    : '경주를 선택해주세요',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
              ),
            ),
          ),
          Consumer<RaceProvider>(
            builder: (_, p, __) => _buildRefreshIndicator(p),
          ),
        ],
      ),
    );
  }

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
      statusText = min > 0 ? '${min}분 후 갱신' : '${remSec}초 후 갱신';
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
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
            const SizedBox(width: 5),
            Text(statusText,
                style: TextStyle(
                    color: dotColor, fontSize: 9.5, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            Icon(Icons.refresh, color: dotColor, size: 12),
          ],
        ),
      ),
    );
  }

  // ── 빈 상태 ─────────────────────────────────────────────────────────────
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
          Text('홈에서 경주를 선택하면\n출전표 분석 데이터를 확인할 수 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  메인 콘텐츠 (탭 구조)
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildContent(RaceInfo race, List<HorseEntry> horses, RaceProvider provider) {
    final sorted = [...horses]..sort((a, b) => a.gateNo.compareTo(b.gateNo));

    return Column(
      children: [
        // ── 탭 바 ────────────────────────────────────────────────────────
        Container(
          color: const Color(0xFF0A1628),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFFFD700),
            indicatorWeight: 2.5,
            labelColor: const Color(0xFFFFD700),
            unselectedLabelColor: Colors.white.withValues(alpha: 0.45),
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            tabs: const [
              Tab(icon: Icon(Icons.bar_chart, size: 15), text: '출전마 분석'),
              Tab(icon: Icon(Icons.track_changes, size: 15), text: '경주 통계'),
            ],
          ),
        ),
        // ── 파서 상태 배너 ─────────────────────────────────────────────
        _buildParserStatusBanner(),
        // ── 탭 뷰 ────────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // 탭1: 출전마 분석 (마필 카드 + TrendLine)
              _buildHorseCardsTab(race, sorted, provider),
              // 탭2: 경주 통계 (TOP5 그리드 + SpeedBarChart)
              _buildStatsTab(race, sorted),
            ],
          ),
        ),
      ],
    );
  }

  // ── 파서 상태 배너 ────────────────────────────────────────────────────
  Widget _buildParserStatusBanner() {
    if (_isLoadingParsed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        color: const Color(0xFF0A1628),
        child: Row(
          children: [
            const SizedBox(
              width: 10, height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4DB6AC)),
              ),
            ),
            const SizedBox(width: 8),
            Text('출전표 파싱 데이터 로드 중...',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
          ],
        ),
      );
    }
    if (!_hasParsedData) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        color: const Color(0xFF0A1628),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                color: Colors.white.withValues(alpha: 0.3), size: 12),
            const SizedBox(width: 6),
            Text('파싱 데이터 없음 — API 데이터로 표시',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 10)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      color: const Color(0xFF0A1628),
      child: Row(
        children: [
          Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF4CAF50), shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '출전표 파싱 데이터 반영 중 (${_parsedHorseMap.length}마필)',
            style: const TextStyle(color: Color(0xFF81C784), fontSize: 10),
          ),
          const Spacer(),
          const Text('0 크레딧',
              style: TextStyle(color: Color(0xFF4CAF50), fontSize: 9)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  탭1: 출전마 분석 탭
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildHorseCardsTab(
      RaceInfo race, List<HorseEntry> horses, RaceProvider provider) {
    final darkHorses = _selectDarkHorses(horses);
    final darkGates = darkHorses.map((h) => h.gateNo).toSet();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 실시간 갱신 상태
          _buildLiveStatusBar(provider),
          // 경주 개요
          _buildRaceOverview(race, horses),
          const SizedBox(height: 14),
          // 섹션 제목
          _sectionTitle('🐴 마필 카드 (기세 트렌드)'),
          const SizedBox(height: 10),
          // 마필 카드 리스트
          ...horses.map((h) => _buildHorseCard(h, race, darkGates.contains(h.gateNo))),
          const SizedBox(height: 14),
          // AI 추천 복병마 (기존 기능 유지)
          if (darkHorses.isNotEmpty) ...[
            _sectionTitle('💣 AI 추천 복병마'),
            const SizedBox(height: 10),
            _buildDarkHorseCards(darkHorses),
          ],
          const SizedBox(height: 14),
          // 배당 순위 섹션
          _buildOddsSection([...horses]..sort(
              (a, b) => a.odds.compareTo(b.odds)), darkGates),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  탭2: 경주 통계 탭
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildStatsTab(RaceInfo race, List<HorseEntry> horses) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TOP5 그리드 뷰
          _sectionTitle('🏆 기타 추리 항목별 TOP 5'),
          const SizedBox(height: 10),
          _buildTop5GridView(horses, race),
          const SizedBox(height: 18),
          // S1F / G1F 바 차트
          _sectionTitle('⚡ 경주 구간 스퍼트 분석'),
          const SizedBox(height: 10),
          _buildSpeedBarChartSection(horses),
          const SizedBox(height: 18),
          // 기존 API 인사이트 (하단 유지)
          _sectionTitle('🤖 AI 분석 인사이트'),
          const SizedBox(height: 10),
          _buildApiInsightSection(
              [...horses]..sort((a, b) => b.finalScore.compareTo(a.finalScore)),
              _selectDarkHorses(horses)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  마필 카드 (HorseCard)
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildHorseCard(HorseEntry h, RaceInfo race, bool isDark) {
    final parsed = _parsedHorseMap[h.gateNo];
    final jockey = parsed?.jockeyName.isNotEmpty == true
        ? parsed!.jockeyName : h.jockeyName;
    final budam = parsed?.wgBudam ?? h.wgBudam;
    final weight = parsed?.weight ?? h.weight;
    final weightChg = parsed?.weightChange ?? h.weightChange;
    final style = parsed?.advancedStat.runningStyle ?? RunningStyle.unknown;
    final speedIdx = parsed?.advancedStat.speedIndex ?? 0.0;
    final prize6m = parsed?.advancedStat.prize6Month ?? 0;
    final recentRanks = parsed?.pastRaces.map((r) => r.selfRank).toList() ?? [];
    final capData = HorseCapColors.getCapData(h.gateNo);
    final styleColor = _styleColor(style);
    final styleLabel = EntryTextParser.runningStyleLabel(style);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A0C08)
            : const Color(0xFF0C1420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? const Color(0xFFFF7043).withValues(alpha: 0.4)
              : const Color(0xFF1A3050),
          width: isDark ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        children: [
          // ── 카드 상단: 기본정보 + 주행스타일 ─────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 마번 원형 뱃지
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: capData.bg,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: capData.bg.withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text('${h.gateNo}',
                        style: TextStyle(
                            color: capData.text,
                            fontSize: 13, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(width: 10),
                // 마명 + 부담중량
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(h.horseName,
                                style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFFFF7043)
                                        : Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (isDark)
                            const Text('💣', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          _infoChip(
                            '기수: ${jockey.isNotEmpty ? jockey : "-"}',
                            const Color(0xFF64B5F6),
                          ),
                          const SizedBox(width: 5),
                          _infoChip(
                            '${budam}kg',
                            const Color(0xFFFFD700),
                          ),
                          if (weight > 0) ...[
                            const SizedBox(width: 5),
                            _infoChip(
                              '체중 $weight(${weightChg >= 0 ? '+' : ''}$weightChg)',
                              weightChg > 2
                                  ? const Color(0xFFEF9A9A)
                                  : weightChg < -2
                                      ? const Color(0xFFA5D6A7)
                                      : Colors.white.withValues(alpha: 0.5),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 우측: 배당 + 속도지수
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${h.odds.toStringAsFixed(1)}배',
                        style: TextStyle(
                            color: h.odds < 5
                                ? const Color(0xFFFF5252)
                                : h.odds < 15
                                    ? const Color(0xFFFFD700)
                                    : Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                    if (speedIdx > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: speedIdx >= 90
                              ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                              : const Color(0xFF333355),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '속도 ${speedIdx.toStringAsFixed(0)}',
                          style: TextStyle(
                              color: speedIdx >= 90
                                  ? const Color(0xFFFFD54F)
                                  : Colors.white.withValues(alpha: 0.5),
                              fontSize: 9,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    if (style != RunningStyle.unknown)
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: styleColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: styleColor.withValues(alpha: 0.35)),
                        ),
                        child: Text(styleLabel,
                            style: TextStyle(
                                color: styleColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // ── 트렌드 라인 ──────────────────────────────────────────────
          if (recentRanks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _TrendLineWidget(
                ranks: recentRanks,
                prize6m: prize6m,
                gateNo: h.gateNo,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _buildNoDataStrip(
                '최근 성적 데이터 없음',
                h.recentRecord.isNotEmpty ? h.recentRecord : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color.withValues(alpha: 0.85),
              fontSize: 9.5, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildNoDataStrip(String msg, String? fallback) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(Icons.remove, color: Colors.white.withValues(alpha: 0.2), size: 12),
          const SizedBox(width: 6),
          Text(
            fallback != null && fallback.isNotEmpty
                ? '최근기록: $fallback'
                : msg,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  TOP 5 그리드 뷰 (PDF 기반 4카테고리)
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildTop5GridView(List<HorseEntry> horses, RaceInfo race) {
    // ── 카테고리 1: 복승률 높은 말 ─────────────────────────────────────
    final top5PlaceRate = _buildPlaceRateTop5(horses);
    // ── 카테고리 2: 최근 6개월 경주당 상금 많은 말 ───────────────────────
    final top5Prize6m = _buildPrize6mTop5(horses);
    // ── 카테고리 3: 유전능력 좋은 말 ──────────────────────────────────
    final top5Genetic = _buildGeneticTop5(horses);
    // ── 카테고리 4: 거리기록 빠른 말 ──────────────────────────────────
    final top5DistRecord = _buildDistRecordTop5(horses, race.distance);

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _Top5Card(
              title: '복승률',
              icon: '🏅',
              color: const Color(0xFFFFD700),
              items: top5PlaceRate,
            )),
            const SizedBox(width: 8),
            Expanded(child: _Top5Card(
              title: '6개월 상금',
              icon: '💰',
              color: const Color(0xFF4CAF50),
              items: top5Prize6m,
            )),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _Top5Card(
              title: '유전능력',
              icon: '🧬',
              color: const Color(0xFFCE93D8),
              items: top5Genetic,
            )),
            const SizedBox(width: 8),
            Expanded(child: _Top5Card(
              title: '${race.distance}m 기록',
              icon: '⏱️',
              color: const Color(0xFF4FC3F7),
              items: top5DistRecord,
            )),
          ],
        ),
      ],
    );
  }

  // 복승률 TOP5
  List<_Top5Item> _buildPlaceRateTop5(List<HorseEntry> horses) {
    final items = <_Top5Item>[];
    for (final h in horses) {
      final parsed = _parsedHorseMap[h.gateNo];
      double rate = parsed?.advancedStat.careerPlaceRate ?? 0.0;
      if (rate <= 0) rate = (h.jockeyRcWins * 0.6).clamp(0.0, 1.0);
      if (rate > 0) {
        items.add(_Top5Item(
          gateNo: h.gateNo,
          horseName: h.horseName,
          value: '${(rate * 100).toStringAsFixed(1)}%',
          sortKey: rate,
        ));
      }
    }
    items.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return items.take(5).toList();
  }

  // 6개월 상금 TOP5
  List<_Top5Item> _buildPrize6mTop5(List<HorseEntry> horses) {
    final items = <_Top5Item>[];
    for (final h in horses) {
      final parsed = _parsedHorseMap[h.gateNo];
      final prize = parsed?.advancedStat.prize6Month ?? 0;
      if (prize > 0) {
        final label = prize >= 100000000
            ? '${(prize / 100000000.0).toStringAsFixed(1)}억원'
            : prize >= 10000000
                ? '${(prize / 10000000.0).toStringAsFixed(1)}천만'
                : prize >= 1000000
                    ? '${(prize / 1000000.0).toStringAsFixed(1)}백만'
                    : '${prize ~/ 1000}천원';
        items.add(_Top5Item(
          gateNo: h.gateNo,
          horseName: h.horseName,
          value: label,
          sortKey: prize.toDouble(),
        ));
      }
    }
    items.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return items.take(5).toList();
  }

  // 유전능력 TOP5 (속도지수 + 상금 기반)
  List<_Top5Item> _buildGeneticTop5(List<HorseEntry> horses) {
    final items = <_Top5Item>[];
    for (final h in horses) {
      final score = _geneticScoreMap[h.gateNo] ?? 0.0;
      if (score > 0) {
        items.add(_Top5Item(
          gateNo: h.gateNo,
          horseName: h.horseName,
          value: '${score.toStringAsFixed(1)}pt',
          sortKey: score,
        ));
      }
    }
    items.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return items.take(5).toList();
  }

  // 거리기록 TOP5
  List<_Top5Item> _buildDistRecordTop5(List<HorseEntry> horses, int distance) {
    final items = <_Top5Item>[];
    for (final h in horses) {
      final distBest = _distanceRecordMap[h.gateNo] ?? '';
      final parsed = _parsedHorseMap[h.gateNo];
      final bestTime = distBest.isNotEmpty
          ? distBest
          : parsed?.bestTime.isNotEmpty == true
              ? parsed!.bestTime
              : '';
      if (bestTime.isNotEmpty) {
        // 기록을 초 단위 float으로 변환해 정렬키로 사용
        final sortKey = _timeToSeconds(bestTime);
        if (sortKey > 0) {
          items.add(_Top5Item(
            gateNo: h.gateNo,
            horseName: h.horseName,
            value: bestTime,
            sortKey: sortKey,
            ascending: true, // 기록은 빠를수록(낮을수록) 좋음
          ));
        }
      }
    }
    items.sort((a, b) => a.sortKey.compareTo(b.sortKey)); // 오름차순
    return items.take(5).toList();
  }

  double _timeToSeconds(String t) {
    // "1:24.5" → 84.5
    try {
      if (t.contains(':')) {
        final parts = t.split(':');
        final min = double.tryParse(parts[0]) ?? 0;
        final sec = double.tryParse(parts[1]) ?? 0;
        return min * 60 + sec;
      }
      return double.tryParse(t) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  S1F / G1F 가로 바 차트 섹션
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildSpeedBarChartSection(List<HorseEntry> horses) {
    // S1F 데이터 수집
    final s1fList = <_SpeedBarItem>[];
    final g1fList = <_SpeedBarItem>[];

    for (final h in horses) {
      final parsed = _parsedHorseMap[h.gateNo];
      final s1f = parsed?.advancedStat.s1fTime ?? 0.0;
      final g1f = parsed?.advancedStat.g1fTime ?? 0.0;
      if (s1f > 0) {
        s1fList.add(_SpeedBarItem(gateNo: h.gateNo, horseName: h.horseName, time: s1f));
      }
      if (g1f > 0) {
        g1fList.add(_SpeedBarItem(gateNo: h.gateNo, horseName: h.horseName, time: g1f));
      }
    }

    // 정렬: 기록 빠른 순 (시간 낮은 순)
    s1fList.sort((a, b) => a.time.compareTo(b.time));
    g1fList.sort((a, b) => a.time.compareTo(b.time));

    final hasS1f = s1fList.isNotEmpty;
    final hasG1f = g1fList.isNotEmpty;

    if (!hasS1f && !hasG1f) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0C1420),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1A3050)),
        ),
        child: Column(
          children: [
            Icon(Icons.bar_chart, color: Colors.white.withValues(alpha: 0.2), size: 32),
            const SizedBox(height: 8),
            Text('구간 기록 데이터 없음\n출전표 텍스트를 파싱하면 표시됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (hasS1f) ...[
          _SpeedBarChart(
            title: '경주 초반 빠른 말',
            subtitle: '출발 후 200m 구간 (S1F)',
            icon: '🚀',
            color: const Color(0xFFFF7043),
            items: s1fList.take(7).toList(),
            lowerIsBetter: true,
          ),
          const SizedBox(height: 12),
        ],
        if (hasG1f)
          _SpeedBarChart(
            title: '경주 후반 빠른 말',
            subtitle: '마지막 200m 구간 (G1F)',
            icon: '💨',
            color: const Color(0xFF4FC3F7),
            items: g1fList.take(7).toList(),
            lowerIsBetter: true,
          ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  경주 개요
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildRaceOverview(RaceInfo race, List<HorseEntry> horses) {
    final venueLabel = race.venueCode == '1' ? '서울'
        : race.venueCode == '2' ? '부산경남' : '제주';
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
              Expanded(child: _overviewChip('📊 파서데이터',
                  _hasParsedData ? '${_parsedHorseMap.length}마 연동' : '대기 중',
                  _hasParsedData ? const Color(0xFF4CAF50) : Colors.grey)),
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

  // ══════════════════════════════════════════════════════════════════════
  //  AI 인사이트 (기존 기능 유지)
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildApiInsightSection(
      List<HorseEntry> sorted, List<HorseEntry> darkHorses) {
    if (sorted.isEmpty) return const SizedBox.shrink();

    // 상위 3마 예측
    final top3 = sorted.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1830), Color(0xFF060E20)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A2A50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🤖', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('AI 분석 기반 예상 순위',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: top3.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final h = entry.value;
              final rankColor = rank == 1
                  ? const Color(0xFFFFD700)
                  : rank == 2
                      ? const Color(0xFFB0BEC5)
                      : const Color(0xFFCD7F32);
              final capData = HorseCapColors.getCapData(h.gateNo);
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: rank < 3 ? 8 : 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: rankColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: rankColor.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Text('$rank위',
                          style: TextStyle(
                              color: rankColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: capData.bg,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text('${h.gateNo}',
                              style: TextStyle(
                                  color: capData.text,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(h.horseName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text('${h.finalScore.toStringAsFixed(1)}점',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 9)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (darkHorses.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('💣', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text('복병마: ${darkHorses.map((h) => '${h.gateNo}번 ${h.horseName}').join(', ')}',
                    style: TextStyle(
                        color: const Color(0xFFFF7043).withValues(alpha: 0.85),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  복병마 카드
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildDarkHorseCards(List<HorseEntry> darkHorses) {
    return Row(
      children: darkHorses.take(3).toList().asMap().entries.map((entry) {
        final h = entry.value;
        final capData = HorseCapColors.getCapData(h.gateNo);
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: entry.key < darkHorses.length - 1 ? 8 : 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0808),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFFF7043).withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('💣', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 6),
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: capData.bg, shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('${h.gateNo}',
                        style: TextStyle(
                            color: capData.text,
                            fontSize: 12, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(h.horseName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFFFF8A65),
                        fontSize: 10, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${h.odds.toStringAsFixed(1)}배',
                    style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 11, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  실시간 상태 바
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildLiveStatusBar(RaceProvider provider) {
    final changes = provider.recentOddsChanges;
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
                    color: Color(0xFF4CAF50), shape: BoxShape.circle),
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

  // ══════════════════════════════════════════════════════════════════════
  //  배당 섹션
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildOddsSection(List<HorseEntry> sorted, Set<int> darkGates) {
    if (sorted.isEmpty) return const SizedBox.shrink();
    final maxOdds = sorted.fold(0.0, (m, h) => math.max(m, h.odds));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1628),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A2A4A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('📊 배당 현황'),
          const SizedBox(height: 10),
          ...sorted.take(8).map((h) {
            final barF = maxOdds > 0 ? (h.odds / maxOdds).clamp(0.05, 1.0) : 0.05;
            final isDark = darkGates.contains(h.gateNo);
            final oddColor = h.odds < 5
                ? const Color(0xFFFF5252)
                : h.odds < 15
                    ? const Color(0xFFFFD700)
                    : Colors.white.withValues(alpha: 0.6);
            final capData = HorseCapColors.getCapData(h.gateNo);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: capData.bg, shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('${h.gateNo}',
                          style: TextStyle(
                              color: capData.text,
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
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  복병마 정밀 선정 알고리즘 (기존 로직 유지)
  // ══════════════════════════════════════════════════════════════════════
  double _darkHorseScore(HorseEntry h) {
    double oddsScore;
    if (h.odds < 8.0) {
      oddsScore = 0.0;
    } else if (h.odds <= 60.0) {
      oddsScore = 1.0 - ((h.odds - 30.0) / 30.0).abs().clamp(0.0, 1.0);
    } else {
      oddsScore = (1.0 - ((h.odds - 60.0) / 40.0)).clamp(0.0, 0.3);
    }
    final jockeyScore = (h.jockeyRcWins * 2.0).clamp(0.0, 2.0);
    final horseScore  = (h.rcWins * 1.5).clamp(0.0, 1.5);
    final formScore   = (h.formStat / 100.0 * 0.5).clamp(0.0, 0.5);
    return oddsScore + jockeyScore + horseScore + formScore;
  }

  List<HorseEntry> _selectDarkHorses(List<HorseEntry> horses) {
    final candidates = horses
        .where((h) => h.odds >= 8.0)
        .toList()
      ..sort((a, b) => _darkHorseScore(b).compareTo(_darkHorseScore(a)));
    return candidates.take(2).toList();
  }

  // ── 공통 유틸 ───────────────────────────────────────────────────────
  Color _styleColor(RunningStyle style) {
    switch (style) {
      case RunningStyle.frontRunner: return const Color(0xFFFF8A65);
      case RunningStyle.stalker:     return const Color(0xFF81C784);
      case RunningStyle.closer:      return const Color(0xFF64B5F6);
      case RunningStyle.unknown:     return const Color(0xFF888888);
    }
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

// ══════════════════════════════════════════════════════════════════════════
//  _TrendLineWidget — 최근 착순 꺾은선 + 화살표 커스텀 위젯
// ══════════════════════════════════════════════════════════════════════════
class _TrendLineWidget extends StatelessWidget {
  final List<int> ranks;    // 최근 순서대로 [가장오래된 → 최근]
  final int prize6m;        // 최근 6개월 상금 (원)
  final int gateNo;

  const _TrendLineWidget({
    required this.ranks,
    required this.prize6m,
    required this.gateNo,
  });

  @override
  Widget build(BuildContext context) {
    if (ranks.isEmpty) return const SizedBox.shrink();

    // 최근 4개만 사용
    final displayRanks = ranks.length > 4
        ? ranks.sublist(ranks.length - 4)
        : List<int>.from(ranks);

    // 추세 계산 (마지막 - 첫번째, 양수면 악화/큰 착순, 음수면 개선)
    final trend = displayRanks.length >= 2
        ? displayRanks.last - displayRanks.first
        : 0;
    final isImproving = trend < -1; // 2착순 이상 개선
    final isDeclining = trend > 1;  // 2착순 이상 악화

    // 상금 표시 (fallback 없음)
    final hasF6m = prize6m > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isImproving
            ? const Color(0xFF0A1A10)
            : isDeclining
                ? const Color(0xFF1A0A0A)
                : const Color(0xFF0A0F1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isImproving
              ? const Color(0xFF4CAF50).withValues(alpha: 0.3)
              : isDeclining
                  ? const Color(0xFFEF5350).withValues(alpha: 0.3)
                  : const Color(0xFF1A2A3A),
        ),
      ),
      child: Row(
        children: [
          // 꺾은선 그래프 영역
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 40,
              child: CustomPaint(
                painter: _TrendLinePainter(
                  ranks: displayRanks,
                  isImproving: isImproving,
                  isDeclining: isDeclining,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 착순 뱃지 행
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: displayRanks.map((rank) {
                    final isLast = rank == displayRanks.last;
                    return Container(
                      margin: const EdgeInsets.only(left: 3),
                      width: isLast ? 18 : 16,
                      height: isLast ? 18 : 16,
                      decoration: BoxDecoration(
                        color: _rankBgColor(rank, isLast),
                        borderRadius: BorderRadius.circular(3),
                        border: isLast
                            ? Border.all(
                                color: _rankColor(rank).withValues(alpha: 0.7))
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          rank > 0 ? '$rank' : '-',
                          style: TextStyle(
                              color: isLast
                                  ? _rankColor(rank)
                                  : Colors.white.withValues(alpha: 0.6),
                              fontSize: isLast ? 9 : 8,
                              fontWeight: isLast
                                  ? FontWeight.w900
                                  : FontWeight.normal),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 3),
                // 추세 화살표 + 레이블
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isImproving) ...[
                      const Icon(Icons.trending_up,
                          color: Color(0xFF4CAF50), size: 13),
                      const SizedBox(width: 3),
                      const Text('기세 상승',
                          style: TextStyle(
                              color: Color(0xFF4CAF50),
                              fontSize: 9, fontWeight: FontWeight.w700)),
                    ] else if (isDeclining) ...[
                      const Icon(Icons.trending_down,
                          color: Color(0xFFEF5350), size: 13),
                      const SizedBox(width: 3),
                      const Text('기세 하락',
                          style: TextStyle(
                              color: Color(0xFFEF5350),
                              fontSize: 9, fontWeight: FontWeight.w700)),
                    ] else ...[
                      const Icon(Icons.trending_flat,
                          color: Color(0xFF888888), size: 12),
                      const SizedBox(width: 3),
                      Text('유지',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 9)),
                    ],
                    if (hasF6m) ...[
                      const SizedBox(width: 6),
                      Text(
                        _formatPrize6m(prize6m),
                        style: const TextStyle(
                            color: Color(0xFF81C784),
                            fontSize: 8.5),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrize6m(int prize) {
    if (prize >= 100000000) return '${(prize / 100000000.0).toStringAsFixed(1)}억';
    if (prize >= 10000000) return '${(prize / 10000000.0).toStringAsFixed(1)}천만';
    if (prize >= 1000000) return '${(prize / 1000000.0).toStringAsFixed(1)}백만';
    return '${prize ~/ 1000}천원';
  }

  Color _rankColor(int rank) {
    if (rank == 1) return const Color(0xFFFFD700);
    if (rank <= 2) return const Color(0xFF4CAF50);
    if (rank <= 5) return const Color(0xFFCCCCDD);
    return const Color(0xFF666688);
  }

  Color _rankBgColor(int rank, bool isLast) {
    if (!isLast) {
      return rank == 1
          ? const Color(0xFFFFD700).withValues(alpha: 0.15)
          : rank <= 2
              ? const Color(0xFF4CAF50).withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.05);
    }
    return rank == 1
        ? const Color(0xFFFFD700).withValues(alpha: 0.2)
        : rank <= 2
            ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.08);
  }
}

// ── CustomPainter: 꺾은선 + 화살표 ─────────────────────────────────────
class _TrendLinePainter extends CustomPainter {
  final List<int> ranks;
  final bool isImproving;
  final bool isDeclining;

  _TrendLinePainter({
    required this.ranks,
    required this.isImproving,
    required this.isDeclining,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (ranks.length < 2) {
      // 1개만 있으면 점 하나
      if (ranks.isNotEmpty) {
        final y = _rankToY(ranks[0], size.height);
        final paint = Paint()
          ..color = const Color(0xFFFFD700)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(size.width / 2, y), 5, paint);
      }
      return;
    }

    final n = ranks.length;
    final lineColor = isImproving
        ? const Color(0xFFEF5350) // 착순 낮아짐(좋아짐) = 붉은 추세선
        : isDeclining
            ? const Color(0xFF78909C)
            : const Color(0xFFEF5350);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.15),
          lineColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final dotPaint = Paint()
      ..style = PaintingStyle.fill;

    final points = <Offset>[];
    for (int i = 0; i < n; i++) {
      final x = size.width * i / (n - 1);
      final y = _rankToY(ranks[i], size.height);
      points.add(Offset(x, y));
    }

    // 채우기 영역
    final fillPath = Path()
      ..moveTo(points.first.dx, size.height)
      ..lineTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      fillPath.lineTo(points[i].dx, points[i].dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();
    canvas.drawPath(fillPath, fillPaint);

    // 꺾은선
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(linePath, linePaint);

    // 마지막 화살표 (추세 방향)
    if (points.length >= 2) {
      final last = points.last;
      final prev = points[points.length - 2];
      final angle = math.atan2(
          last.dy - prev.dy, last.dx - prev.dx);
      _drawArrow(canvas, last, angle, lineColor);
    }

    // 점들
    for (int i = 0; i < points.length; i++) {
      final isLast = i == points.length - 1;
      final rank = ranks[i];
      final dotColor = rank == 1
          ? const Color(0xFFFFD700)
          : rank <= 2
              ? const Color(0xFF4CAF50)
              : lineColor;
      dotPaint.color = dotColor;
      canvas.drawCircle(points[i], isLast ? 5.5 : 3.5, dotPaint);
      // 흰색 내부 점
      canvas.drawCircle(
          points[i],
          isLast ? 2.5 : 1.5,
          Paint()..color = Colors.white.withValues(alpha: 0.9));
    }
  }

  double _rankToY(int rank, double height) {
    // 착순 1~12 → Y좌표 (1착이 위쪽 = 작은 Y)
    final clamped = rank.clamp(1, 12);
    return height * (clamped - 1) / 11.0 * 0.85 + height * 0.075;
  }

  void _drawArrow(Canvas canvas, Offset tip, double angle, Color color) {
    const arrowLen = 8.0;
    const arrowAngle = 0.4; // 라디안
    final p1 = Offset(
      tip.dx - arrowLen * math.cos(angle - arrowAngle),
      tip.dy - arrowLen * math.sin(angle - arrowAngle),
    );
    final p2 = Offset(
      tip.dx - arrowLen * math.cos(angle + arrowAngle),
      tip.dy - arrowLen * math.sin(angle + arrowAngle),
    );
    final arrowPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p2.dx, p2.dy);
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) {
    return oldDelegate.ranks != ranks;
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _Top5Item — TOP5 데이터 모델
// ══════════════════════════════════════════════════════════════════════════
class _Top5Item {
  final int gateNo;
  final String horseName;
  final String value;
  final double sortKey;
  final bool ascending;

  const _Top5Item({
    required this.gateNo,
    required this.horseName,
    required this.value,
    required this.sortKey,
    this.ascending = false,
  });
}

// ══════════════════════════════════════════════════════════════════════════
//  _Top5Card — TOP5 카테고리 카드 위젯
// ══════════════════════════════════════════════════════════════════════════
class _Top5Card extends StatelessWidget {
  final String title;
  final String icon;
  final Color color;
  final List<_Top5Item> items;

  const _Top5Card({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: color.withValues(alpha: 0.15), height: 1),
          const SizedBox(height: 6),
          // TOP5 항목 (5개 고정, 없으면 '없음')
          ...List.generate(5, (i) {
            final rankLabel = ['1위', '2위', '3위', '4위', '5위'][i];
            final hasItem = i < items.length;
            final item = hasItem ? items[i] : null;
            final rankColors = [
              const Color(0xFFFFD700),
              const Color(0xFFB0BEC5),
              const Color(0xFFCD7F32),
              Colors.white,
              Colors.white,
            ];
            final capData = item != null
                ? HorseCapColors.getCapData(item.gateNo)
                : null;

            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  // 순위
                  SizedBox(
                    width: 22,
                    child: Text(rankLabel,
                        style: TextStyle(
                            color: rankColors[i].withValues(
                                alpha: hasItem ? 1.0 : 0.3),
                            fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ),
                  // 마번 원형
                  if (hasItem && capData != null) ...[
                    Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: capData.bg, shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${item!.gateNo}',
                            style: TextStyle(
                                color: capData.text,
                                fontSize: 7.5,
                                fontWeight: FontWeight.w900)),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ] else
                    const SizedBox(width: 20),
                  // 마명
                  Expanded(
                    child: Text(
                      hasItem ? item!.horseName : '없음',
                      style: TextStyle(
                          color: hasItem
                              ? Colors.white.withValues(alpha: 0.85)
                              : Colors.white.withValues(alpha: 0.2),
                          fontSize: 9.5,
                          fontWeight: hasItem
                              ? FontWeight.w600
                              : FontWeight.normal),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 수치
                  if (hasItem)
                    Text(item!.value,
                        style: TextStyle(
                            color: color.withValues(alpha: 0.9),
                            fontSize: 9,
                            fontWeight: FontWeight.w700))
                  else
                    Text('-',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.2),
                            fontSize: 9)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _SpeedBarItem — S1F/G1F 바 차트 데이터 모델
// ══════════════════════════════════════════════════════════════════════════
class _SpeedBarItem {
  final int gateNo;
  final String horseName;
  final double time;
  const _SpeedBarItem({
    required this.gateNo,
    required this.horseName,
    required this.time,
  });
}

// ══════════════════════════════════════════════════════════════════════════
//  _SpeedBarChart — 가로 바 차트 위젯
// ══════════════════════════════════════════════════════════════════════════
class _SpeedBarChart extends StatelessWidget {
  final String title;
  final String subtitle;
  final String icon;
  final Color color;
  final List<_SpeedBarItem> items;
  final bool lowerIsBetter;

  const _SpeedBarChart({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.items,
    this.lowerIsBetter = true,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    // 기록 범위 계산
    final minTime = items.map((i) => i.time).reduce(math.min);
    final maxTime = items.map((i) => i.time).reduce(math.max);
    final range = maxTime - minTime;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 9.5)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 바 차트 항목
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final isFirst = i == 0;
            final capData = HorseCapColors.getCapData(item.gateNo);

            // 바 길이 계산
            // 기록이 낮을수록 빠름 → 바 길이는 (maxTime - time) / range
            double barFraction;
            if (range < 0.01) {
              barFraction = 1.0; // 모두 동일 기록
            } else if (lowerIsBetter) {
              barFraction = (maxTime - item.time) / range;
              barFraction = barFraction * 0.85 + 0.15; // 최소 15% 보장
            } else {
              barFraction = (item.time - minTime) / range;
              barFraction = barFraction * 0.85 + 0.15;
            }
            barFraction = barFraction.clamp(0.05, 1.0);

            // 1위는 강조색
            final barColor = isFirst
                ? color
                : color.withValues(alpha: 0.45 - i * 0.03);
            final rankBadgeColor = isFirst
                ? color
                : Colors.white.withValues(alpha: 0.3);

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  // 순위 뱃지
                  Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: rankBadgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: isFirst
                          ? Border.all(
                              color: color.withValues(alpha: 0.5))
                          : null,
                    ),
                    child: Center(
                      child: Text('${i + 1}',
                          style: TextStyle(
                              color: isFirst
                                  ? color
                                  : Colors.white.withValues(alpha: 0.45),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 5),
                  // 마번 원형
                  Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: capData.bg, shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('${item.gateNo}',
                          style: TextStyle(
                              color: capData.text,
                              fontSize: 8,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(width: 5),
                  // 마명
                  SizedBox(
                    width: 56,
                    child: Text(item.horseName,
                        style: TextStyle(
                            color: isFirst
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.6),
                            fontSize: 9.5,
                            fontWeight: isFirst
                                ? FontWeight.w700
                                : FontWeight.normal),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  // 가로 바
                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 배경
                        Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        // 채워진 바
                        FractionallySizedBox(
                          widthFactor: barFraction,
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: barColor,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: isFirst
                                  ? [
                                      BoxShadow(
                                        color: color.withValues(alpha: 0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      )
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 기록 수치
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 38,
                    child: Text('${item.time.toStringAsFixed(1)}초',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: isFirst
                                ? color
                                : Colors.white.withValues(alpha: 0.5),
                            fontSize: 10,
                            fontWeight: isFirst
                                ? FontWeight.w800
                                : FontWeight.normal)),
                  ),
                ],
              ),
            );
          }).toList(),
          // 주석
          const SizedBox(height: 4),
          Text(
            lowerIsBetter
                ? '※ 기록이 짧을수록(낮을수록) 빠름'
                : '※ 기록이 높을수록 우수',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 8.5),
          ),
        ],
      ),
    );
  }
}
