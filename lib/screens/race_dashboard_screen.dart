import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/race_models.dart';
import '../providers/race_provider.dart';
import '../services/race_stat_engine.dart';
import '../utils/horse_cap_colors.dart';
import 'race_splash_screen.dart';

class RaceDashboardScreen extends StatefulWidget {
  final RaceInfo race;
  /// 시즌오프 체험 모드 여부 — true이면 가상 데이터 경주임을 상단 배너로 안내
  final bool isDemoMode;
  const RaceDashboardScreen({
    super.key,
    required this.race,
    this.isDemoMode = false,
  });

  @override
  State<RaceDashboardScreen> createState() => _RaceDashboardScreenState();
}

class _RaceDashboardScreenState extends State<RaceDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _slideCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600),
    );
    _slideAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic);
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RaceProvider>(
      builder: (ctx, provider, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF050D1A),
          body: Column(
            children: [
              _buildHeader(context),
              // 시즌오프 체험 모드 안내 배너
              if (widget.isDemoMode) _buildDemoBanner(),
              // API 실패 → Mock 출전마 경고 배너
              if (!widget.isDemoMode && provider.isHorsesMock)
                _buildMockHorsesBanner(),
              if (provider.isLoadingHorses)
                const Expanded(child: _LoadingPanel())
              else ...[
                _buildAiInsightBanner(provider),
                _buildHorseListHeader(),
                Expanded(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 120),
                    itemCount: provider.horses.length,
                    itemBuilder: (ctx, i) {
                      final horse = provider.horses[i];
                      return AnimatedBuilder(
                        animation: _slideAnim,
                        builder: (_, child) => Transform.translate(
                          offset: Offset(0, 30 * (1 - _slideAnim.value)),
                          child: Opacity(
                            opacity: _slideAnim.value.clamp(0.0, 1.0),
                            child: child,
                          ),
                        ),
                        child: horse.isCancelled
                            ? _buildCancelledCard(horse)
                            : _HorseStatCard(
                                horse: horse,
                                rank: i + 1,
                                allHorses: provider.horses,
                                onBonusChanged: (val) {
                                  provider.updateUserBonus(horse.gateNo, val);
                                },
                              ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
          bottomNavigationBar: _buildStartButton(provider),
        );
      },
    );
  }

  // ── 시즌오프 체험 모드 안내 배너 ──
  Widget _buildDemoBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFAA00).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFAA00).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '가상 체험 모드',
                      style: TextStyle(
                        color: Color(0xFFFFAA00),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: const Color(0xFFFF3B30).withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        'DEMO DATA',
                        style: TextStyle(
                          color: Color(0xFFFF3B30),
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '현 모의 레이스는 가상의 데이터로 구현되는 경주입니다. 앱 기능 체험 전용.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── API 실패 → Mock 출전마 경고 배너 ──
  Widget _buildMockHorsesBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF1A0E00),
      child: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: '예시 출전마 표시 중  ',
                    style: TextStyle(
                      color: Color(0xFFFFAA00),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: 'KRA API 미연결 — 마명·기수·배당은 실제와 다릅니다',
                    style: TextStyle(
                      color: Color(0xFFAA7030),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6600).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: const Color(0xFFFF6600).withValues(alpha: 0.5)),
            ),
            child: const Text(
              'MOCK',
              style: TextStyle(
                color: Color(0xFFFF6600),
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 헤더 ──
  Widget _buildHeader(BuildContext context) {
    final race = widget.race;
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16, right: 16, bottom: 12,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A1628), Color(0xFF071220)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1A3A5A), width: 1),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: Color(0xFFFFD700), size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${race.venueName} 제${race.raceNo}경주',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TrackCondBadge(condition: race.trackCondition),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${race.startTime} 출발 · ${race.distance}m · ${race.condition}',
                  style: const TextStyle(color: Color(0xFF7A9AB8), fontSize: 11),
                ),
              ],
            ),
          ),
          // 주로 아이콘
          _buildTrackIndicator(race),
        ],
      ),
    );
  }

  Widget _buildTrackIndicator(RaceInfo race) {
    final isCW = race.venueCode == '3';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A3A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A4A6A)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isCW ? '↻ CW' : '↺ CCW',
            style: TextStyle(
              color: isCW ? const Color(0xFF64B5F6) : const Color(0xFF81C784),
              fontSize: 10, fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            isCW ? '제주' : '서울/부산',
            style: const TextStyle(color: Color(0xFF5A7A8A), fontSize: 8),
          ),
        ],
      ),
    );
  }

  // ── AI 인사이트 배너 ──
  Widget _buildAiInsightBanner(RaceProvider provider) {
    final insights = provider.insights;
    if (insights.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) => Container(
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1A2A1A).withValues(alpha: 0.9),
              const Color(0xFF0D1E0D).withValues(alpha: 0.9),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFFFD700).withValues(
              alpha: 0.3 + _pulseCtrl.value * 0.3,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withValues(
                alpha: 0.05 + _pulseCtrl.value * 0.08,
              ),
              blurRadius: 12, spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFFAA00)],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '🤖  AI 분석',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 10, fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '23개 API 데이터 기반 분석 결과',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 6,
              children: insights.map((ins) => _InsightChip(insight: ins)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── 말 목록 헤더 ──
  Widget _buildHorseListHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          const SizedBox(width: 44),
          const SizedBox(width: 8),
          const Text('출전마 / 기수',
              style: TextStyle(color: Color(0xFF5A7A9A), fontSize: 11)),
          const Spacer(),
          const Text('AI',
              style: TextStyle(color: Color(0xFF5A7A9A), fontSize: 11)),
          const SizedBox(width: 14),
          const SizedBox(
            width: 96,
            child: Text('배당 가점',
                style: TextStyle(color: Color(0xFF5A7A9A), fontSize: 11),
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelledCard(HorseEntry horse) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          HorseCapBadge(gateNo: horse.gateNo, size: 38, showNumber: true),
          const SizedBox(width: 10),
          Text(horse.horseName,
              style: const TextStyle(
                  color: Color(0xFF3A5A7A), fontSize: 13)),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.4)),
            ),
            child: const Text('출전 취소',
                style: TextStyle(
                    color: Color(0xFFFF3B30),
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── 경주 시작 시간 경과 여부 (상세페이지 START 버튼 비활성 판정) ──
  bool get _isRacePast {
    final race = widget.race;
    if (race.isFinished) return true;
    final parts = race.startTime.split(':');
    if (parts.length != 2) return false;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return false;
    final now = DateTime.now();
    final raceTime = DateTime(now.year, now.month, now.day, h, m);
    return now.isAfter(raceTime.add(const Duration(minutes: 30)));
  }

  /// 다음 주 동일 요일 활성화 예정 문자열
  String _nextActiveLabel() {
    final race = widget.race;
    final raceDateStr = race.raceDate;
    final now = DateTime.now();
    if (raceDateStr.length == 8) {
      final year  = int.tryParse(raceDateStr.substring(0, 4)) ?? now.year;
      final month = int.tryParse(raceDateStr.substring(4, 6)) ?? now.month;
      final day   = int.tryParse(raceDateStr.substring(6, 8)) ?? now.day;
      final raceDate = DateTime(year, month, day);
      final nextSame = raceDate.add(const Duration(days: 7));
      final mo = nextSame.month.toString().padLeft(2, '0');
      final dd = nextSame.day.toString().padLeft(2, '0');
      const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
      final dn = dayNames[nextSame.weekday - 1];
      return '다음 주 $mo/$dd($dn) ${race.startTime} 활성화 예정';
    }
    return '다음 주 동일 시간 활성화 예정';
  }

  // ── START 버튼 ──
  Widget _buildStartButton(RaceProvider provider) {
    final canSim = provider.canSimulate;
    // ── 경주 시간 경과 여부 (상세페이지 START 버튼 전용 비활성) ──
    final isRacePast = _isRacePast;

    // ── 라이프사이클 잠금 상태 체크 ──
    // 데모 모드(시즌오프 체험)는 seasonOff 잠금을 건너뜀
    final lockState = widget.isDemoMode
        ? RaceLockState.active
        : provider.raceLockFor(widget.race);
    // 경주 시간 경과 시에도 잠금 처리
    final isLocked = lockState != RaceLockState.active || isRacePast;

    // 잠금 상태별 버튼 표시 정보
    // isRacePast 우선: 경주 시간 경과 시 별도 표시
    final (lockIcon, lockLabel, lockColor) = isRacePast && lockState == RaceLockState.active
        ? ('🏁', _nextActiveLabel(), const Color(0xFF7A7A9A))
        : switch (lockState) {
            RaceLockState.seasonOff    => ('🚫', '시즌 오프 — 모의 레이스 제한',  const Color(0xFFFF3B30)),
            RaceLockState.dataPending  => ('⏳', '데이터 업데이트 대기 중',        const Color(0xFFFFAA00)),
            RaceLockState.raceLocked   => ('🏁', '경주 종료 — 모의 레이서 비활성', const Color(0xFF7A7A9A)),
            RaceLockState.active       => ('', '', Colors.transparent),
          };

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A1628), Color(0xFF071220)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          top: BorderSide(color: Color(0xFF1A3A5A), width: 1),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 라이프사이클 잠금 배너 (잠금 상태일 때만) ──
          if (isLocked)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: lockColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: lockColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(lockIcon, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Text(
                      lockLabel,
                      style: TextStyle(
                        color: lockColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 무료 잔여 횟수 (잠금 해제 + 비프리미엄 시)
          if (!isLocked && !provider.isPremium)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    provider.remainingFree > 0
                        ? Icons.bolt
                        : Icons.lock_outline,
                    color: provider.remainingFree > 0
                        ? const Color(0xFFFFD700)
                        : const Color(0xFFFF3B30),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    provider.remainingFree > 0
                        ? '무료 시뮬레이션 오늘 ${provider.remainingFree}회 남음'
                        : '무료 시뮬레이션 소진 — 프리미엄으로 무제한 이용',
                    style: TextStyle(
                      color: provider.remainingFree > 0
                          ? const Color(0xFFFFD700)
                          : const Color(0xFFFF3B30),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          // 버튼
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => GestureDetector(
              onTap: () {
                // ── 0순위: 경주 시간 경과 체크 (START 버튼 비활성) ──
                if (isRacePast && lockState == RaceLockState.active) {
                  _showLifecycleLockDialog(
                    icon: '🏁',
                    title: '경주 시간 종료',
                    message:
                        '해당 경주 출발 시간이 지났습니다.\n'
                        'AI 모의 레이스는 비활성화 되었습니다.\n\n'
                        '${_nextActiveLabel()}',
                    accentColor: const Color(0xFF7A7A9A),
                  );
                  return;
                }
                // ── 1순위: 라이프사이클 잠금 체크 ──
                if (lockState == RaceLockState.seasonOff) {
                  _showLifecycleLockDialog(
                    icon: '🚫',
                    title: '시즌 오프',
                    message:
                        '금주 실시간 경주 스케줄이 모두 종료되었습니다.\n'
                        '다음 주 경주 데이터 업데이트 전까지\n'
                        '모의 레이스가 제한됩니다.',
                    accentColor: const Color(0xFFFF3B30),
                  );
                  return;
                }
                if (lockState == RaceLockState.dataPending) {
                  _showLifecycleLockDialog(
                    icon: '⏳',
                    title: '데이터 미확정',
                    message:
                        '이번 주 실시간 경주 데이터가 아직\n'
                        '업데이트되지 않았습니다.\n\n'
                        '매주 목요일 오후 5시 이후\n'
                        '순차 업데이트 예정',
                    accentColor: const Color(0xFFFFAA00),
                  );
                  return;
                }
                if (lockState == RaceLockState.raceLocked) {
                  _showLifecycleLockDialog(
                    icon: '🏁',
                    title: '경주 종료',
                    message:
                        '당일 실시간 경주가 종료되어\n'
                        '모의 레이서 가동이 종료되었습니다.',
                    accentColor: const Color(0xFF7A7A9A),
                  );
                  return;
                }
                // ── 2순위: 프리미엄 여부 체크 ──
                if (!canSim) {
                  _showPremiumDialog();
                  return;
                }
                // ── 정상 진입 (데모 모드는 simCount 증가 제외) ──
                if (!widget.isDemoMode) provider.incrementSimCount();
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (c, a1, a2) => RaceSplashScreen(
                      race: widget.race,
                      horses: List.from(
                          provider.horses.where((h) => !h.isCancelled)),
                      isDemoMode: widget.isDemoMode,
                    ),
                    transitionsBuilder: (c, a1, a2, child) =>
                        FadeTransition(opacity: a1, child: child),
                    transitionDuration:
                        const Duration(milliseconds: 500),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: (!isLocked && canSim)
                      ? LinearGradient(
                          colors: [
                            const Color(0xFFFFD700),
                            Color.lerp(const Color(0xFFFFD700),
                                const Color(0xFFFF8C00),
                                0.3 + _pulseCtrl.value * 0.3)!,
                            const Color(0xFFB8960C),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: (!isLocked && canSim) ? null : const Color(0xFF1A2A3A),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: (!isLocked && canSim)
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withValues(
                              alpha: 0.3 + _pulseCtrl.value * 0.25,
                            ),
                            blurRadius: 20 + _pulseCtrl.value * 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isLocked
                          ? lockIcon
                          : (canSim ? '🏁' : '🔒'),
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isLocked
                          ? lockLabel
                          : (canSim
                              ? 'AI 모의 레이스  START'
                              : '프리미엄 구독 후 이용'),
                      style: TextStyle(
                        color: isLocked
                            ? lockColor.withValues(alpha: 0.8)
                            : (canSim
                                ? const Color(0xFF1A1A1A)
                                : const Color(0xFF5A7A9A)),
                        fontSize: isLocked ? 14 : 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 라이프사이클 잠금 팝업 ──
  void _showLifecycleLockDialog({
    required String icon,
    required String title,
    required String message,
    required Color accentColor,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1F35),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accentColor.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.2),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 아이콘
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1.5),
                ),
                child: Center(
                  child: Text(icon, style: const TextStyle(fontSize: 30)),
                ),
              ),
              const SizedBox(height: 16),
              // 제목
              Text(
                title,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              // 메시지
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              // 확인 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor.withValues(alpha: 0.15),
                    foregroundColor: accentColor,
                    side: BorderSide(color: accentColor.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '확인',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPremiumDialog() {
    showDialog(
      context: context,
      builder: (_) => _PremiumDialog(
        onSubscribe: () {
          Navigator.pop(context);
          context.read<RaceProvider>().setPremium(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('👑 프리미엄 구독이 활성화되었습니다!'),
              backgroundColor: Color(0xFFB8960C),
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  로딩 패널
// ══════════════════════════════════════════════════════════════════════
class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48, height: 48,
            child: CircularProgressIndicator(
              color: Color(0xFFFFD700), strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '23개 API 데이터 분석 중...',
            style: TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'API4_3 · API6_1 · API77 · API25_1 · API155',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  인사이트 칩
// ══════════════════════════════════════════════════════════════════════
class _InsightChip extends StatelessWidget {
  final RaceInsight insight;
  const _InsightChip({required this.insight});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (insight.type) {
      InsightType.topPick    => ('🏆', const Color(0xFFFFD700)),
      InsightType.darkHorse  => ('🎯', const Color(0xFF64B5F6)),
      InsightType.weightAlert => ('⚖️', const Color(0xFFFFB74D)),
      InsightType.trackAlert  => ('🌧️', const Color(0xFF81C784)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          if (insight.gateNo > 0) ...[
            HorseCapBadge(gateNo: insight.gateNo, size: 18, showNumber: true),
            const SizedBox(width: 4),
          ],
          Text(
            insight.message,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  주로 상태 배지
// ══════════════════════════════════════════════════════════════════════
class _TrackCondBadge extends StatelessWidget {
  final String condition;
  const _TrackCondBadge({required this.condition});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (condition) {
      '양호' => (const Color(0xFF4CAF50), '☀️'),
      '다습' => (const Color(0xFF2196F3), '🌧️'),
      '불량' => (const Color(0xFFFF5722), '⛈️'),
      '건조' => (const Color(0xFFFF9800), '🌵'),
      _      => (const Color(0xFF5A7A9A), '🌀'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$icon $condition',
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  출전마 스탯 카드 (완전 개편)
// ══════════════════════════════════════════════════════════════════════
class _HorseStatCard extends StatefulWidget {
  final HorseEntry horse;
  final int rank;
  final List<HorseEntry> allHorses;
  final ValueChanged<double> onBonusChanged;

  const _HorseStatCard({
    required this.horse,
    required this.rank,
    required this.allHorses,
    required this.onBonusChanged,
  });

  @override
  State<_HorseStatCard> createState() => _HorseStatCardState();
}

class _HorseStatCardState extends State<_HorseStatCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _expandCtrl;
  late Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300),
    );
    _expandAnim = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() => _expanded = !_expanded);
    _expanded ? _expandCtrl.forward() : _expandCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.horse;
    final isTopPick = widget.rank == 1;
    final isDarkHorse = h.odds >= 10 && h.finalScore >= 58;

    return GestureDetector(
      onTap: _toggleExpand,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isTopPick
                ? [const Color(0xFF1C2A12), const Color(0xFF0F1A0A)]
                : [const Color(0xFF0F1A28), const Color(0xFF080F1A)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isTopPick
                ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                : isDarkHorse
                    ? const Color(0xFF64B5F6).withValues(alpha: 0.35)
                    : const Color(0xFF1A3A5A).withValues(alpha: 0.6),
            width: isTopPick ? 1.5 : 1.0,
          ),
          boxShadow: isTopPick
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                    blurRadius: 14, spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            // ── 메인 행 ──
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // 마번 배지
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      HorseCapBadge(gateNo: h.gateNo, size: 44, showNumber: true),
                      if (isTopPick)
                        Positioned(
                          top: -6, right: -6,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD700),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('👑',
                                style: TextStyle(fontSize: 8)),
                          ),
                        ),
                      if (isDarkHorse && !isTopPick)
                        Positioned(
                          top: -6, right: -6,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1565C0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('🎯',
                                style: TextStyle(fontSize: 8)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),

                  // 말 정보
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(h.horseName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(width: 6),
                            if (h.weightChange != 0)
                              _WeightChangeBadge(change: h.weightChange),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.person_outline,
                                size: 11, color: Color(0xFF5A7A9A)),
                            const SizedBox(width: 2),
                            Text(h.jockeyName,
                                style: const TextStyle(
                                    color: Color(0xFF5A7A9A), fontSize: 11)),
                            const SizedBox(width: 8),
                            Text(
                              h.odds <= 0.0
                                  ? '배당 미발표'
                                  : '배당 ${h.odds.toStringAsFixed(1)}배',
                              style: TextStyle(
                                color: h.odds <= 0.0
                                    ? const Color(0xFF5A7A9A)
                                    : h.odds <= 5
                                        ? const Color(0xFF4CAF50)
                                        : h.odds <= 15
                                            ? const Color(0xFFFFD700)
                                            : const Color(0xFFFF7043),
                                fontSize: 11, fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        // 미니 스탯 바
                        _MiniStatRow(horse: h),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // AI 점수
                  Column(
                    children: [
                      Text(
                        h.finalScore.toStringAsFixed(1),
                        style: TextStyle(
                          color: _scoreColor(h.finalScore),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text('AI 점수',
                          style: const TextStyle(
                              color: Color(0xFF4A6A8A), fontSize: 9)),
                      Text(
                        '#${widget.rank}',
                        style: TextStyle(
                          color: widget.rank == 1
                              ? const Color(0xFFFFD700)
                              : const Color(0xFF4A6A8A),
                          fontSize: 10, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── 배당 가점 슬라이더 ──
            _BonusSlider(horse: h, onChanged: widget.onBonusChanged),

            // ── 확장 상세 패널 ──
            SizeTransition(
              sizeFactor: _expandAnim,
              child: _DetailPanel(horse: h, allHorses: widget.allHorses),
            ),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 75) return const Color(0xFF4CAF50);
    if (score >= 55) return const Color(0xFFFFD700);
    if (score >= 40) return const Color(0xFFFF9800);
    return const Color(0xFFFF5722);
  }
}

// ── 미니 스탯 바 ──
class _MiniStatRow extends StatelessWidget {
  final HorseEntry horse;
  const _MiniStatRow({required this.horse});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _miniBar('S', horse.speedStat, const Color(0xFF2979FF)),
        const SizedBox(width: 4),
        _miniBar('E', horse.staminaStat, const Color(0xFF00BFA5)),
        const SizedBox(width: 4),
        _miniBar('F', horse.formStat, const Color(0xFFFFD700)),
        const SizedBox(width: 4),
        _miniBar('T', horse.trackFitStat, const Color(0xFFFF6D00)),
      ],
    );
  }

  Widget _miniBar(String label, double value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                color: color.withValues(alpha: 0.7), fontSize: 8)),
        const SizedBox(width: 2),
        Container(
          width: 28, height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF1A3A5A),
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (value / 100).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 체중 변화 배지 ──
class _WeightChangeBadge extends StatelessWidget {
  final int change;
  const _WeightChangeBadge({required this.change});

  @override
  Widget build(BuildContext context) {
    final isPos = change > 0;
    final isBig = change.abs() >= 5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: (isBig
                ? const Color(0xFFFF9800)
                : isPos
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFF2196F3))
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: (isBig
                  ? const Color(0xFFFF9800)
                  : isPos
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFF2196F3))
              .withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        '${isPos ? '+' : ''}${change}kg',
        style: TextStyle(
          color: isBig
              ? const Color(0xFFFF9800)
              : isPos
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFF2196F3),
          fontSize: 9, fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── 배당 가점 슬라이더 ──
class _BonusSlider extends StatelessWidget {
  final HorseEntry horse;
  final ValueChanged<double> onChanged;
  const _BonusSlider({required this.horse, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final h = horse;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('배당 가점',
                  style: TextStyle(
                      color: Color(0xFF5A7A9A),
                      fontSize: 11, fontWeight: FontWeight.w600)),
              const Spacer(),
              _BonusBadge(value: h.userBonus),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: h.userBonus >= 0
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFFFF5722),
              inactiveTrackColor: const Color(0xFF1A3A5A),
              thumbColor: h.userBonus >= 0
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFFFF5722),
              overlayColor:
                  (h.userBonus >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5722))
                      .withValues(alpha: 0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            ),
            child: Slider(
              value: h.userBonus,
              min: -5, max: 5, divisions: 10,
              onChanged: onChanged,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('-5  약세',
                  style: TextStyle(
                      color: Color(0xFFFF5722),
                      fontSize: 9, fontWeight: FontWeight.w600)),
              const Text('+5  강세',
                  style: TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 9, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _BonusBadge extends StatelessWidget {
  final double value;
  const _BonusBadge({required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value == 0
        ? const Color(0xFF3A5A7A)
        : value > 0
            ? const Color(0xFF4CAF50)
            : const Color(0xFFFF5722);
    final label = value == 0
        ? '±0'
        : value > 0
            ? '+${value.toStringAsFixed(0)}'
            : value.toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 14, fontWeight: FontWeight.w900)),
    );
  }
}

// ── 상세 확장 패널 ──
class _DetailPanel extends StatelessWidget {
  final HorseEntry horse;
  final List<HorseEntry> allHorses;
  const _DetailPanel({required this.horse, required this.allHorses});

  @override
  Widget build(BuildContext context) {
    final h = horse;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Color(0xFF1A3A5A), height: 1),
          const SizedBox(height: 10),
          // 스탯 상세 바
          _StatBar('속도 (API4_3/6_1)', h.speedStat, const Color(0xFF2979FF)),
          const SizedBox(height: 5),
          _StatBar('지구력 (API77/25_1)', h.staminaStat, const Color(0xFF00BFA5)),
          const SizedBox(height: 5),
          _StatBar('컨디션 (API10_1)', h.formStat, const Color(0xFFFFD700)),
          const SizedBox(height: 5),
          _StatBar('주로적성 (API189_1)', h.trackFitStat, const Color(0xFFFF6D00)),
          const SizedBox(height: 10),
          // 추가 정보
          Row(
            children: [
              _InfoTag('레이팅', h.rating.toStringAsFixed(0), const Color(0xFF9C27B0)),
              const SizedBox(width: 8),
              _InfoTag('체중', '${h.weight}kg', const Color(0xFF5A7A9A)),
              const SizedBox(width: 8),
              _InfoTag('최근', h.recentRecord, const Color(0xFF9E9E9E)),
            ],
          ),
          const SizedBox(height: 8),
          // 상대 비교 레이더
          _RelativeBar('최종점수 비교', h.finalScore,
              allHorses.map((e) => e.finalScore).reduce(max),
              const Color(0xFFFFD700)),
        ],
      ),
    );
  }
}

class _StatBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _StatBar(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label,
              style: const TextStyle(
                  color: Color(0xFF5A7A9A), fontSize: 10)),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                  height: 7,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A3A5A),
                    borderRadius: BorderRadius.circular(4),
                  )),
              FractionallySizedBox(
                widthFactor: (value / 100).clamp(0.0, 1.0),
                child: Container(
                  height: 7,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [color.withValues(alpha: 0.6), color]),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text(value.toStringAsFixed(0),
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _RelativeBar extends StatelessWidget {
  final String label;
  final double value;
  final double maxVal;
  final Color color;
  const _RelativeBar(this.label, this.value, this.maxVal, this.color);

  @override
  Widget build(BuildContext context) {
    final frac = maxVal > 0 ? (value / maxVal).clamp(0.0, 1.0) : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: const TextStyle(
                  color: Color(0xFF5A7A9A), fontSize: 10)),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1628),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: const Color(0xFF1A3A5A), width: 0.5),
                  )),
              FractionallySizedBox(
                widthFactor: frac,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [color.withValues(alpha: 0.5), color]),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('${(frac * 100).toStringAsFixed(0)}%',
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _InfoTag extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _InfoTag(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
                text: '$label ',
                style: TextStyle(
                    color: color.withValues(alpha: 0.6), fontSize: 9)),
            TextSpan(
                text: value,
                style: TextStyle(
                    color: color,
                    fontSize: 10, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  프리미엄 다이얼로그
// ══════════════════════════════════════════════════════════════════════
class _PremiumDialog extends StatelessWidget {
  final VoidCallback onSubscribe;
  const _PremiumDialog({required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0D1B2A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(
            color: Color(0xFFFFD700), width: 1.5),
      ),
      title: const Row(
        children: [
          Text('👑', style: TextStyle(fontSize: 24)),
          SizedBox(width: 8),
          Text('프리미엄 구독',
              style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '23개 API 실시간 분석 + 무제한 시뮬레이션\n정보지 한 권 값으로 한 달 무제한!',
            style: TextStyle(color: Color(0xFFB0C8E0), fontSize: 13),
          ),
          const SizedBox(height: 16),
          ...[
            '✅ 전 경주 무제한 시뮬레이션',
            '✅ 23개 API 실시간 스탯 분석',
            '✅ AI 복병마 자동 탐지',
            '✅ 체중변화 / 기수변경 알림',
          ].map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(t,
                    style: const TextStyle(
                        color: Color(0xFFB0C8E0), fontSize: 12)),
              )),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFB8960C)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('월 9,900원',
                    style: TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 22, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기',
              style: TextStyle(color: Color(0xFF5A7A9A))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: onSubscribe,
          child: const Text('구독하기',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
