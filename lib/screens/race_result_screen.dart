import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/race_models.dart';
import '../services/kra_api_service.dart';
import '../services/race_result_archive.dart';
import '../utils/horse_cap_colors.dart';

// ──────────────────────────────────────────────────────────────
// RaceResultScreen
// 경주결과 + 배당 조회 화면 (racedetailresult API 기반)
// 필드: 착순, 도착차, 주파기록, 단승/연승배당, 장구, 수습감량, 미출전 여부
// 시즌오프·경주종료 중에도 항상 접근 가능
// ──────────────────────────────────────────────────────────────
class RaceResultScreen extends StatefulWidget {
  final RaceInfo race;
  /// AI 분석 데이터 (선택) — 대시보드 분석 데이터가 있을 때
  /// 예측 vs 실결과 비교 섹션 표시
  final List<HorseEntry>? aiHorses;
  const RaceResultScreen({
    super.key,
    required this.race,
    this.aiHorses,
  });

  @override
  State<RaceResultScreen> createState() => _RaceResultScreenState();
}

class _RaceResultScreenState extends State<RaceResultScreen>
    with SingleTickerProviderStateMixin {
  KraRaceResult? _result;
  bool _isLoading = true;
  bool _isFromArchive = false;   // 관리자 업로드 아카이브에서 로드된 경우
  String? _errorMsg;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadResult();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadResult() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
      _isFromArchive = false;
    });

    try {
      // 경주일자 파싱 (YYYYMMDD → DateTime)
      final dateStr = widget.race.raceDate;
      DateTime raceDate;
      if (dateStr.length == 8) {
        raceDate = DateTime(
          int.parse(dateStr.substring(0, 4)),
          int.parse(dateStr.substring(4, 6)),
          int.parse(dateStr.substring(6, 8)),
        );
      } else {
        raceDate = DateTime.now();
      }

      KraRaceResult? result;
      try {
        result = await KraApiService.fetchRaceResult(
          widget.race.venueCode,
          raceDate,
          widget.race.raceNo,
        );
      } catch (apiErr) {
        if (kDebugMode) debugPrint('[RaceResultScreen] API Error: $apiErr');
        result = null;
      }

      if (!mounted) return;

      // ── API 결과가 있으면 사용 ──────────────────────────────────
      if (result != null && result.horses.isNotEmpty) {
        setState(() {
          _result = result;
          _isLoading = false;
        });
        _fadeCtrl.forward();
        return;
      }

      // ── API 결과 없음 → 관리자 업로드 아카이브 폴백 ────────────
      if (kDebugMode) {
        debugPrint('[RaceResultScreen] API 결과 없음 → 아카이브 조회: '
            '${widget.race.raceDate} / venue=${widget.race.venueCode} / '
            'raceNo=${widget.race.raceNo}');
      }

      final archived = await RaceResultArchive.instance.loadByKey(
        widget.race.raceDate,
        widget.race.venueCode,
        widget.race.raceNo.toString(),
      );

      if (!mounted) return;

      if (archived != null && archived.horses.isNotEmpty) {
        // 아카이브에서 로드 성공
        setState(() {
          _result = archived;
          _isLoading = false;
          _isFromArchive = true;
        });
        _fadeCtrl.forward();
      } else {
        // API + 아카이브 모두 없음 → 경주 미종료 또는 집계 전
        setState(() {
          _isLoading = false;
          _errorMsg = '경주 결과가 아직 집계되지 않았습니다.\n경주 종료 후 잠시 후 다시 확인해 주세요.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (kDebugMode) debugPrint('[RaceResultScreen] Error: $e');
      setState(() {
        _isLoading = false;
        _errorMsg = '결과 데이터를 불러오는 중 오류가 발생했습니다.\n잠시 후 다시 시도해 주세요.';
      });
    }
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
              child: _isLoading
                  ? _buildLoading()
                  : _errorMsg != null
                      ? _buildError()
                      : FadeTransition(
                          opacity: _fadeAnim,
                          child: _buildResultContent(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 상단 헤더 ──
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1F35), Color(0xFF050D1A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1A3A5A), width: 1),
        ),
      ),
      child: Row(
        children: [
          // 뒤로가기
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1A3A5A).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A5A7A).withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: Color(0xFF64B5F6), size: 18),
            ),
          ),
          const SizedBox(width: 12),
          // 경주 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A3A5A),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF2A5A7A)),
                      ),
                      child: Text(
                        widget.race.venueName,
                        style: const TextStyle(
                          color: Color(0xFF64B5F6),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2A),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF3A3A5A)),
                      ),
                      child: Text(
                        widget.race.raceDate.length == 8
                            ? '${widget.race.raceDate.substring(0, 4)}.'
                              '${widget.race.raceDate.substring(4, 6)}.'
                              '${widget.race.raceDate.substring(6, 8)}'
                            : widget.race.raceDate,
                        style: const TextStyle(
                          color: Color(0xFFB0BEC5),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '제${widget.race.raceNo}경주  경주결과 · 배당',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    // 관리자 업로드 데이터 사용 중 배지
                    if (_isFromArchive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6B4FD8).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                              color: const Color(0xFF6B4FD8)
                                  .withValues(alpha: 0.5)),
                        ),
                        child: const Text(
                          '📋 업로드',
                          style: TextStyle(
                            color: Color(0xFFB39DDB),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // 새로고침 버튼
          GestureDetector(
            onTap: _loadResult,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1A3A5A).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A5A7A).withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.refresh, color: Color(0xFF64B5F6), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ── 로딩 ──
  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 44, height: 44,
            child: CircularProgressIndicator(
              color: Color(0xFFFFD700), strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'API4_3 경주기록 조회 중...',
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '착순 기록 · 주파 시간 · 배당 집계',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ── 에러 ──
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.3)),
              ),
              child: const Center(
                child: Text('⏳', style: TextStyle(fontSize: 32)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _errorMsg ?? '결과를 불러올 수 없습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadResult,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('다시 시도'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A3A5A),
                foregroundColor: const Color(0xFF64B5F6),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFF2A5A7A)),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 결과 콘텐츠 전체 ──
  Widget _buildResultContent() {
    final result = _result!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1·2·3착 하이라이트 카드
          if (result.top3.isNotEmpty) _buildPodiumCard(result.top3),
          const SizedBox(height: 20),

          // 배당 요약 배너
          _buildOddsSummaryBanner(result),
          const SizedBox(height: 20),

          // AI 예측 vs 실결과 비교 (선택: aiHorses 있을 때)
          if (widget.aiHorses != null && widget.aiHorses!.isNotEmpty) ...[
            _buildAiComparisonSection(result, widget.aiHorses!),
            const SizedBox(height: 20),
          ],

          // 전체 착순 테이블
          _buildSectionTitle('📋 전체 착순 기록'),
          const SizedBox(height: 10),
          _buildResultTable(result.horses),
        ],
      ),
    );
  }

  // ── AI 예측 vs 실결과 비교 섹션 ──
  Widget _buildAiComparisonSection(
      KraRaceResult result, List<HorseEntry> aiHorses) {
    // AI 점수순으로 정렬 (이미 대시보드에서 정렬되어 오지만 안전 원복)
    final sorted = [...aiHorses]
        .where((h) => !h.isCancelled)
        .toList()
      ..sort((a, b) => b.finalScore.compareTo(a.finalScore));

    // 실결과 맵: gateNo → 실착순
    final resultMap = <int, HorseResult>{};
    for (final h in result.horses) {
      resultMap[h.gateNo] = h;
    }

    // 적중률 계산
    int hit3 = 0; // AI 3순위 안에 실제 3착 내 비율
    for (var i = 0; i < sorted.length && i < 3; i++) {
      final actual = resultMap[sorted[i].gateNo];
      if (actual != null && actual.rank >= 1 && actual.rank <= 3) hit3++;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1F35), Color(0xFF091428)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFFFFD700).withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.06),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 타이틀
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFAA00)],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '🤖  AI 예측 적중률',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'AI 순위 vs 실제 착순 비교',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              // 적중률 배지
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _hitRateColor(hit3, 3).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        _hitRateColor(hit3, 3).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  'TOP3 적중 $hit3/3',
                  style: TextStyle(
                    color: _hitRateColor(hit3, 3),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 비교 행: AI 순위 / 마번 / 마명 / AI점수 / 실제착순
          _buildComparisonHeader(),
          const SizedBox(height: 6),
          ...sorted.asMap().entries.map((entry) {
            final aiRank = entry.key + 1;
            final horse = entry.value;
            final actual = resultMap[horse.gateNo];
            return _buildComparisonRow(
              aiRank: aiRank,
              horse: horse,
              actualRank: actual?.rank ?? 0,
              actualTime: actual?.raceTime ?? '',
            );
          }),
        ],
      ),
    );
  }

  Widget _buildComparisonHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A3A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 36,
            child: Text('AI순위',
                style: TextStyle(
                    color: Color(0xFF64B5F6),
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          const SizedBox(
            width: 26,
            child: Text('마번',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFF64B5F6),
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('마명',
                style: TextStyle(
                    color: Color(0xFF64B5F6),
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(
            width: 36,
            child: Text('AI점수',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: Color(0xFF64B5F6),
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          const SizedBox(
            width: 46,
            child: Text('실제착순',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFF64B5F6),
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow({
    required int aiRank,
    required HorseEntry horse,
    required int actualRank,
    required String actualTime,
  }) {
    // 적중 판정: AI 순위 구간에 실제 착순이 들어오면 적중
    final isHit = actualRank >= 1 && actualRank <= 3 && aiRank <= 3;
    // 완전 일치: AI순위 == 실제착순
    final isPerfect = aiRank == actualRank && actualRank > 0;

    final aiRankColor = switch (aiRank) {
      1 => const Color(0xFFFFD700),
      2 => const Color(0xFFB0BEC5),
      3 => const Color(0xFFBE8C5A),
      _ => const Color(0xFF4A6A8A),
    };

    final actualRankColor = switch (actualRank) {
      1 => const Color(0xFFFFD700),
      2 => const Color(0xFFB0BEC5),
      3 => const Color(0xFFBE8C5A),
      _ => const Color(0xFF4A6A8A),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: isPerfect
            ? const Color(0xFFFFD700).withValues(alpha: 0.07)
            : isHit
                ? const Color(0xFF4CAF50).withValues(alpha: 0.05)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isPerfect
            ? Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          // AI 순위
          SizedBox(
            width: 36,
            child: Row(
              children: [
                Text(
                  switch (aiRank) {
                    1 => '🥇',
                    2 => '🥈',
                    3 => '🥉',
                    _ => '#$aiRank',
                  },
                  style: TextStyle(
                    fontSize: aiRank <= 3 ? 14 : 10,
                    color: aiRankColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // 마번
          SizedBox(
            width: 26,
            child: Center(
              child: HorseCapBadge(
                  gateNo: horse.gateNo, size: 22, showNumber: true),
            ),
          ),
          const SizedBox(width: 6),
          // 마명
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  horse.horseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isPerfect)
                  const Text(
                    '✨ 실제 순위와 일치!',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          // AI 점수
          SizedBox(
            width: 36,
            child: Text(
              horse.finalScore.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _scoreColor(horse.finalScore),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 실제 착순
          SizedBox(
            width: 46,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: BoxDecoration(
                color: actualRank > 0
                    ? actualRankColor.withValues(
                        alpha: actualRank <= 3 ? 0.18 : 0.07)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: actualRank > 0 && actualRank <= 3
                    ? Border.all(
                        color: actualRankColor.withValues(alpha: 0.4))
                    : null,
              ),
              child: Text(
                actualRank > 0 ? '$actualRank착' : '-',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: actualRank > 0
                      ? (actualRank <= 3
                          ? actualRankColor
                          : const Color(0xFF4A6A8A))
                      : const Color(0xFF3A5A7A),
                  fontSize: 11,
                  fontWeight: actualRank <= 3
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _hitRateColor(int hit, int total) {
    final rate = total > 0 ? hit / total : 0.0;
    if (rate >= 0.8) return const Color(0xFF4CAF50);
    if (rate >= 0.5) return const Color(0xFFFFD700);
    if (rate >= 0.3) return const Color(0xFFFF9800);
    return const Color(0xFF78909C);
  }

  Color _scoreColor(double score) {
    if (score >= 75) return const Color(0xFF4CAF50);
    if (score >= 55) return const Color(0xFFFFD700);
    if (score >= 40) return const Color(0xFFFF9800);
    return const Color(0xFFFF5722);
  }

  // ── 섹션 타이틀 ──
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
    );
  }

  // ── 1·2·3착 포디움 카드 ──
  Widget _buildPodiumCard(List<HorseResult> top3) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1F35), Color(0xFF0A1628)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          // 타이틀
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text(
                '착순 결과',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '제${widget.race.raceNo}경주',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 1·2·3착 카드 행
          Row(
            children: top3.map((h) => Expanded(
              child: _buildRankCard(h),
            )).toList(),
          ),
          // 1착 주파기록
          if (top3.isNotEmpty && top3.first.raceTime.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2A3A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2A4A6A).withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_outlined,
                      color: Color(0xFF64B5F6), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '1착 주파기록  ',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    top3.first.raceTime,
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRankCard(HorseResult horse) {
    final (rankEmoji, rankColor) = switch (horse.rank) {
      1 => ('🥇', const Color(0xFFFFD700)),
      2 => ('🥈', const Color(0xFFB0BEC5)),
      3 => ('🥉', const Color(0xFFBE8C5A)),
      _ => ('', const Color(0xFF5A7A9A)),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: rankColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: rankColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(rankEmoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 6),
            HorseCapBadge(gateNo: horse.gateNo, size: 30, showNumber: true),
            const SizedBox(height: 6),
            Text(
              horse.horseName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              horse.jockeyName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
            if (horse.winOdds > 0) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${horse.winOdds.toStringAsFixed(1)}배',
                  style: const TextStyle(
                    color: Color(0xFFFF6B35),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 배당 요약 배너 ──
  Widget _buildOddsSummaryBanner(KraRaceResult result) {
    final winner = result.winner;
    if (winner == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1F35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💰', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              const Text(
                '배당 요약',
                style: TextStyle(
                  color: Color(0xFFFF6B35),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildOddsChip('단승\n(Win)',
                  winner.winOdds > 0 ? '${winner.winOdds.toStringAsFixed(1)}배' : '-',
                  const Color(0xFFFFD700)),
              const SizedBox(width: 8),
              // 연승(Place) — racedetailresult plc 필드 (1착마 기준)
              _buildOddsChip('연승\n(Place)',
                  winner.placeOdds > 0 ? '${winner.placeOdds.toStringAsFixed(1)}배' : '-',
                  const Color(0xFF64B5F6)),
              const SizedBox(width: 8),
              // 2착 연승 배당
              if (result.top3.length >= 2)
                _buildOddsChip('2착연승\n(Place)',
                    result.top3[1].placeOdds > 0
                        ? '${result.top3[1].placeOdds.toStringAsFixed(1)}배'
                        : '-',
                    const Color(0xFF81C784)),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 6),
          Text(
            '※ 단승(1착 단독) · 연승(각 착 연승식 배당) 기준 — KRA racedetailresult API',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOddsChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 9,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 전체 착순 테이블 ──
  Widget _buildResultTable(List<HorseResult> horses) {
    // 출전마와 미출전마 분리
    final starters  = horses.where((h) => h.didStart).toList();
    final scratched = horses.where((h) => !h.didStart).toList();

    return Column(
      children: [
        // ── 출전마 테이블 ──
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A1628),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1A3A5A).withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              _buildTableHeader(),
              ...starters.asMap().entries.map((entry) {
                final idx   = entry.key;
                final horse = entry.value;
                final isLast = idx == starters.length - 1 && scratched.isEmpty;
                return _buildTableRow(horse, isLast: isLast);
              }),
            ],
          ),
        ),
        // ── 미출전마 섹션 (있을 때만) ──
        if (scratched.isNotEmpty) ...
          _buildScratchedSection(scratched),
      ],
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A3A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          bottom: BorderSide(color: const Color(0xFF2A4A6A).withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 28, child: Text('착', style: _hStyle)),
          const SizedBox(width: 8),
          const SizedBox(width: 28, child: Text('마번', style: _hStyle)),
          const SizedBox(width: 8),
          const Expanded(child: Text('말이름 / 기수', style: _hStyle)),
          const SizedBox(width: 8),
          const SizedBox(width: 58, child: Text('기록/도착차', style: _hStyle, textAlign: TextAlign.right)),
          const SizedBox(width: 8),
          const SizedBox(width: 50, child: Text('단/연승', style: _hStyle, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  // ── 미출전마 섹션 ──────────────────────────────────────────────
  List<Widget> _buildScratchedSection(List<HorseResult> scratched) {
    return [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A0A0A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF8B2020).withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B2020).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF8B2020).withValues(alpha: 0.5)),
                  ),
                  child: const Text(
                    '출전취소 (미출전)',
                    style: TextStyle(
                      color: Color(0xFFFF6B6B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${scratched.length}두',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: scratched.map((h) => _buildScratchedChip(h)).toList(),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildScratchedChip(HorseResult horse) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1010),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF8B2020).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HorseCapBadge(gateNo: horse.gateNo, size: 20, showNumber: true),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                horse.horseName,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                horse.jockeyName,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _hStyle = TextStyle(
    color: Color(0xFF64B5F6),
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
  );

  Widget _buildTableRow(HorseResult horse, {required bool isLast}) {
    final isTop3 = horse.rank >= 1 && horse.rank <= 3;
    final rankColor = switch (horse.rank) {
      1 => const Color(0xFFFFD700),
      2 => const Color(0xFFB0BEC5),
      3 => const Color(0xFFBE8C5A),
      _ => const Color(0xFF4A6A8A),
    };

    // 기수명 + 수습감량 표시 (예: "정평수(-1)", "홍길동")
    final jockeyLabel = horse.isApprentice
        ? '${horse.jockeyName}(${horse.jockeyApprentice}kg)'
        : horse.jockeyName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isTop3
            ? rankColor.withValues(alpha: 0.04)
            : Colors.transparent,
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(16))
            : null,
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                    color: const Color(0xFF1A3A5A).withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          // 착순 배지
          SizedBox(
            width: 28,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: rankColor.withValues(alpha: isTop3 ? 0.15 : 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                horse.rank > 0 ? '${horse.rank}착' : '-',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isTop3 ? rankColor : const Color(0xFF5A7A9A),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 마번 배지
          SizedBox(
            width: 28,
            child: HorseCapBadge(gateNo: horse.gateNo, size: 26, showNumber: true),
          ),
          const SizedBox(width: 8),
          // 말이름 + 기수(+수습감량) + 장구
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 말이름 행
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        horse.horseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isTop3
                              ? Colors.white.withValues(alpha: 0.9)
                              : Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                          fontWeight: isTop3 ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    // 장구 뱃지 (hrTool 있을 때)
                    if (horse.hasTool) ...
                      [
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF6B4FD8).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: const Color(0xFF6B4FD8)
                                    .withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            horse.horseTool,
                            style: const TextStyle(
                              color: Color(0xFFB39DDB),
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                  ],
                ),
                // 기수 행 (수습감량 포함)
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        jockeyLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: horse.isApprentice
                              ? const Color(0xFF80CBC4).withValues(alpha: 0.8)
                              : Colors.white.withValues(alpha: 0.38),
                          fontSize: 10,
                        ),
                      ),
                    ),
                    // 수습기수 아이콘 (감량 적용 시)
                    if (horse.isApprentice) ...
                      [
                        const SizedBox(width: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF004D40).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            '수습',
                            style: TextStyle(
                              color: Color(0xFF80CBC4),
                              fontSize: 7,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 주파기록 + 도착차(differ)
          SizedBox(
            width: 58,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  horse.raceTime.isNotEmpty ? horse.raceTime : '-',
                  style: TextStyle(
                    color: horse.rank == 1
                        ? const Color(0xFFFFD700).withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                // 도착차 (differ) — 1착은 표시 안 함
                if (horse.differ.isNotEmpty && horse.rank != 1)
                  Text(
                    horse.differ,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.38),
                      fontSize: 9,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 단승배당 + 연승배당
          SizedBox(
            width: 50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 단승 배당 (win)
                if (horse.winOdds > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35)
                          .withValues(alpha: isTop3 ? 0.18 : 0.08),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                          color: const Color(0xFFFF6B35)
                              .withValues(alpha: isTop3 ? 0.4 : 0.15)),
                    ),
                    child: Text(
                      '단 ${horse.winOdds.toStringAsFixed(1)}',
                      style: TextStyle(
                        color: isTop3
                            ? const Color(0xFFFF6B35)
                            : const Color(0xFFFF6B35).withValues(alpha: 0.55),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  )
                else
                  Text(
                    '-',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.2), fontSize: 11),
                  ),
                // 연승 배당 (plc) — 있을 때만
                if (horse.placeOdds > 0) ...
                  [
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF64B5F6)
                            .withValues(alpha: isTop3 ? 0.15 : 0.06),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color: const Color(0xFF64B5F6)
                                .withValues(alpha: isTop3 ? 0.35 : 0.12)),
                      ),
                      child: Text(
                        '연 ${horse.placeOdds.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: isTop3
                              ? const Color(0xFF64B5F6)
                              : const Color(0xFF64B5F6).withValues(alpha: 0.5),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
