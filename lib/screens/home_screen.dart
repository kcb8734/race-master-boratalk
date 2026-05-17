import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/race_provider.dart';
import '../utils/app_theme.dart';
import '../widgets/day_tab_bar.dart';
import '../widgets/venue_selector.dart';
import '../widgets/race_list_card.dart';
import 'race_dashboard_screen.dart';
import 'ai_analysis_screen.dart';
import 'race_info_screen.dart';
import 'my_page_screen.dart';

// ──────────────────────────────────────────────
// HomeScreen — 메인 진입점 (BottomNavigationBar 4탭)
// ──────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  // ── 하단 탭 인덱스
  int _selectedIndex = 0;

  // ── 자동 스크롤 배너
  late AnimationController _bannerCtrl;
  late Animation<double> _bannerAnim;
  static const _bannerTexts = [
    '📰 아직도 종이 정보지? 경마통이 싹 해결!',
    '💡 정보지 한 권 값으로 AI 분석 한 달 무제한!',
    '🎯 고배당 복병마 조합까지, 경마통 하나면 끝!',
    '🤖 23개 API 데이터 기반 AI 정밀 분석!',
    '🏆 실시간 AI 모의 레이스로 최적 조합 찾기!',
    '📊 직전 5경주 성적·조교·컨디션 전부 분석!',
  ];
  // 무한 스크롤을 위해 배너 텍스트를 이어붙인 단일 문자열
  String get _bannerFull =>
      _bannerTexts.map((t) => '  $t  ·').join('  ') * 3;

  @override
  void initState() {
    super.initState();
    // 배너 애니메이션: 0→1 무한 반복 (12초)
    _bannerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _bannerAnim = Tween<double>(begin: 0, end: 1).animate(_bannerCtrl);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<RaceProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _bannerCtrl.dispose();
    super.dispose();
  }

  // ── 탭별 페이지
  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return _HomeContent(
          bannerAnim: _bannerAnim,
          bannerFull: _bannerFull,
          onShowPremium: _showPremiumSheet,
        );
      case 1:
        return const AiAnalysisScreen();
      case 2:
        return const RaceInfoScreen();
      case 3:
        return const MyPageScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navyDeep,
      // ── IndexedStack: 탭 전환 시 상태 유지
      body: IndexedStack(
        index: _selectedIndex,
        children: List.generate(4, _buildPage),
      ),
      // ── 하단 네비게이션 바
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    const activeColor  = Color(0xFFFFD700);   // 골드
    const inactiveColor = Color(0xFF6B7A99);  // 회색
    const bgColor      = Color(0xFF0A1428);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: const Border(
          top: BorderSide(color: Color(0xFF1E2D4A), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _navItem(0, Icons.home_rounded, Icons.home_outlined, '홈',
                  activeColor, inactiveColor),
              _navItem(1, Icons.analytics_rounded, Icons.analytics_outlined,
                  'AI분석', activeColor, inactiveColor),
              _navItem(2, Icons.list_alt_rounded, Icons.list_alt_outlined,
                  '경주정보', activeColor, inactiveColor),
              _navItem(3, Icons.person_rounded, Icons.person_outlined,
                  '마이페이지', activeColor, inactiveColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData activeIcon, IconData inactiveIcon,
      String label, Color activeColor, Color inactiveColor) {
    final isActive = _selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selectedIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                  horizontal: isActive ? 14 : 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? activeColor.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                isActive ? activeIcon : inactiveIcon,
                color: isActive ? activeColor : inactiveColor,
                size: isActive ? 24 : 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isActive ? activeColor : inactiveColor,
                fontSize: 10,
                fontWeight:
                    isActive ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPremiumSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.navyCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PremiumBottomSheet(
        onSubscribe: () {
          Navigator.pop(context);
          context.read<RaceProvider>().setPremium(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('👑 프리미엄 구독이 활성화되었습니다!'),
              backgroundColor: AppTheme.goldDark,
            ),
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────
// _HomeContent — 홈 탭 본문
// ──────────────────────────────────────────────
class _HomeContent extends StatelessWidget {
  final Animation<double> bannerAnim;
  final String bannerFull;
  final VoidCallback onShowPremium;

  const _HomeContent({
    required this.bannerAnim,
    required this.bannerFull,
    required this.onShowPremium,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // ── 상단 헤더
          _buildAppHeader(context),

          // ── 자동 스크롤 광고 배너
          _buildScrollingBanner(),

          // ── 요일 탭 바
          const DayTabBar(),

          Container(height: 1, color: AppTheme.navyBorder),

          // ── 경주장 선택
          const VenueSelector(),

          Container(height: 1, color: AppTheme.navyBorder),

          // ── 경주 목록 헤더
          _buildRaceListLabel(context),

          // ── 경주 목록
          Expanded(child: _buildRaceList(context)),
        ],
      ),
    );
  }

  // ── 상단 헤더
  Widget _buildAppHeader(BuildContext context) {
    return Container(
      color: AppTheme.navyDark,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: AppTheme.goldGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏇', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Text(
                  '경마통',
                  style: TextStyle(
                    color: AppTheme.navyDeep,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'AI 모의 레이스',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          const Spacer(),
          Consumer<RaceProvider>(
            builder: (_, p, __) => p.isPremium
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: AppTheme.goldGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('👑', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        Text(
                          'PREMIUM',
                          style: TextStyle(
                            color: AppTheme.navyDeep,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  )
                : GestureDetector(
                    onTap: onShowPremium,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.navyCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.navyBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('👑', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(
                            '9,900원/월',
                            style: TextStyle(
                              color: AppTheme.goldAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
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

  // ── 자동 스크롤 광고 배너
  Widget _buildScrollingBanner() {
    return Container(
      height: 36,
      color: const Color(0xFF0D1929),
      child: ClipRect(
        child: AnimatedBuilder(
          animation: bannerAnim,
          builder: (_, __) {
            return CustomPaint(
              painter: _MarqueePainter(
                text: bannerFull,
                progress: bannerAnim.value,
                textColor: const Color(0xFFFFD700),
                fontSize: 12.0,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }

  // ── 경주 목록 헤더
  Widget _buildRaceListLabel(BuildContext context) {
    return Consumer<RaceProvider>(
      builder: (_, provider, __) {
        final day = provider.selectedDay;
        final venue = provider.selectedVenue;
        return Container(
          color: AppTheme.navyDeep,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  gradient: AppTheme.goldGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                day != null
                    ? '${day.label}요일 ${venue.label} 경주 목록'
                    : '경주 목록',
                style: const TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Consumer<RaceProvider>(
                builder: (_, p, __) => !p.isPremium
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: p.remainingFree > 0
                              ? AppTheme.greenWin.withValues(alpha: 0.15)
                              : AppTheme.redAlert.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: p.remainingFree > 0
                                ? AppTheme.greenWin.withValues(alpha: 0.5)
                                : AppTheme.redAlert.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          '무료 ${p.remainingFree}회 남음',
                          style: TextStyle(
                            color: p.remainingFree > 0
                                ? AppTheme.greenWin
                                : AppTheme.redAlert,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 경주 목록
  Widget _buildRaceList(BuildContext context) {
    return Consumer<RaceProvider>(
      builder: (ctx, provider, __) {
        if (provider.isLoadingRaces) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppTheme.goldPrimary),
                const SizedBox(height: 12),
                Text(
                  'KRA 경주 데이터 로딩 중...',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
              ],
            ),
          );
        }

        if (provider.races.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🏇', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  '해당 날짜/경주장에\n경주 데이터가 없습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: AppTheme.goldPrimary,
          backgroundColor: AppTheme.navyCard,
          onRefresh: () async {
            provider.refreshRaces();
            await Future.delayed(const Duration(milliseconds: 600));
          },
          child: ListView.builder(
            padding: EdgeInsets.only(
              top: 6,
              bottom: MediaQuery.of(ctx).padding.bottom + 80,
            ),
            itemCount: provider.races.length,
            itemBuilder: (c, i) {
              final race = provider.races[i];
              return RaceListCard(
                race: race,
                onEnter: () async {
                  await provider.selectRace(race);
                  if (!ctx.mounted) return;
                  Navigator.push(
                    ctx,
                    PageRouteBuilder(
                      pageBuilder: (cc, a1, a2) =>
                          RaceDashboardScreen(race: race),
                      transitionsBuilder: (cc, a1, a2, child) =>
                          FadeTransition(opacity: a1, child: child),
                      transitionDuration:
                          const Duration(milliseconds: 400),
                    ),
                  );
                },
                onViewResult: () {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                          '제${race.raceNo}경주 실제 결과 (API 연결 후 제공)'),
                      backgroundColor: AppTheme.navyCard,
                      action: SnackBarAction(
                        label: '확인',
                        textColor: AppTheme.goldPrimary,
                        onPressed: () {},
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────
// _MarqueePainter — Canvas 기반 마퀴 스크롤 텍스트
// ──────────────────────────────────────────────
class _MarqueePainter extends CustomPainter {
  final String text;
  final double progress; // 0.0 ~ 1.0
  final Color textColor;
  final double fontSize;

  const _MarqueePainter({
    required this.text,
    required this.progress,
    required this.textColor,
    required this.fontSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);

    final textW = tp.width;
    if (textW <= 0) return;

    // 텍스트가 왼쪽 끝에서 시작해 오른쪽으로 사라지는 방향 (좌→우 방향 이동)
    // progress: 0 → textW 만큼 이동 → 다시 0 (무한 반복)
    final offset = -(progress * textW * 0.5) % textW;

    // 두 번 그려서 끊김 없이 연결
    tp.paint(canvas, Offset(offset, (size.height - tp.height) / 2));
    tp.paint(canvas, Offset(offset + textW, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(_MarqueePainter old) =>
      old.progress != progress || old.text != text;
}

// ──────────────────────────────────────────────
// _PremiumBottomSheet
// ──────────────────────────────────────────────
class _PremiumBottomSheet extends StatelessWidget {
  final VoidCallback onSubscribe;
  const _PremiumBottomSheet({required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppTheme.navyBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text('👑', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text(
            '경마통 프리미엄',
            style: TextStyle(
              color: AppTheme.goldPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '아직도 종이 정보지 보며 고민하시나요?\n경마통이 싹 해결해 드립니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          _benefitRow('🔓', '전 레이스 무제한 시뮬레이션'),
          _benefitRow('🤖', 'AI 복병마 자동 가점 칩'),
          _benefitRow('📊', '일별 훈련 상세 데이터'),
          _benefitRow('🔔', '기수변경·출전취소 실시간 알림'),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onSubscribe,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.goldPrimary.withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Text(
                '월 9,900원으로 구독하기',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.navyDeep,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '정보지 한 권 값으로 한 달 내내 AI 분석 무제한!',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _benefitRow(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Text(text,
              style: TextStyle(color: AppTheme.textLight, fontSize: 13)),
        ],
      ),
    );
  }
}
