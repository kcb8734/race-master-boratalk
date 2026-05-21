import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/race_provider.dart';
import '../utils/app_theme.dart';
import '../widgets/day_tab_bar.dart';
import '../widgets/venue_selector.dart';
import '../widgets/race_list_card.dart';
import 'race_dashboard_screen.dart';
import 'race_result_screen.dart';
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
    '🐎 승률·배당·조교 데이터를 한눈에!',
    '⚡ 빠른 분석, 정확한 예측 — 경마통!',
  ];
  // 무한 스크롤을 위해 배너 텍스트를 이어붙인 단일 문자열 (충분히 반복)
  String get _bannerFull =>
      _bannerTexts.map((t) => '   $t   ◆').join('   ') * 4;

  @override
  void initState() {
    super.initState();
    // 배너 애니메이션: 0→1 무한 반복 (속도 기반 스크롤)
    _bannerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28), // 28초에 텍스트 전체 1회 순환
    )..repeat();
    _bannerAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bannerCtrl, curve: Curves.linear),
    );

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

          // ── 라이프사이클 공지 배너 (Null / 시즌오프)
          _buildLifecycleBanner(context),

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
      height: 34,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF050E1C), Color(0xFF0D1929), Color(0xFF050E1C)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          // 왼쪽 골드 구분선
          Container(
            width: 3,
            height: 34,
            color: const Color(0xFFFFD700),
          ),
          const SizedBox(width: 6),
          // 스크롤 텍스트 영역
          Expanded(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: bannerAnim,
                builder: (_, __) => CustomPaint(
                  painter: _MarqueePainter(
                    text: bannerFull,
                    progress: bannerAnim.value,
                    textColor: const Color(0xFFFFD700),
                    fontSize: 12.0,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 오른쪽 골드 구분선
          Container(
            width: 3,
            height: 34,
            color: const Color(0xFFFFD700),
          ),
        ],
      ),
    );
  }

  // ── 라이프사이클 공지 배너 ─────────────────────────────────────
  Widget _buildLifecycleBanner(BuildContext context) {
    return Consumer<RaceProvider>(
      builder: (_, provider, __) {
        final lock = provider.globalLockState;

        // 정상 활성 상태 → 배너 없음
        if (lock == RaceLockState.active &&
            provider.dataStatus == DataStatus.available) {
          return const SizedBox.shrink();
        }

        // 시즌오프 배너
        if (lock == RaceLockState.seasonOff) {
          return _LifecycleBanner(
            icon: '🚫',
            color: const Color(0xFFFF3B30),
            title: '시즌 오프 기간',
            message: '금주 실시간 경주 스케줄이 모두 종료되었습니다.',
            sub: '다음 주 목요일 오후 5시 이후 경주 데이터 업데이트 예정',
            badgeText: 'SEASON OFF',
            badgeColor: const Color(0xFFFF3B30),
          );
        }

        // 데이터 미확정 배너
        if (lock == RaceLockState.dataPending ||
            provider.dataStatus == DataStatus.nullPending) {
          return const _LifecycleBanner(
            icon: '⏳',
            color: Color(0xFFFFAA00),
            title: '데이터 업데이트 대기 중',
            message: '이번 주 실시간 경주 데이터가 아직 업데이트되지 않았습니다.',
            sub: '매주 목요일 오후 5시 이후 순차 업데이트 예정',
            badgeText: 'DATA PENDING',
            badgeColor: Color(0xFFFFAA00),
          );
        }

        return const SizedBox.shrink();
      },
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
                  // ── 라이프사이클 잠금 체크 ──────────────────────
                  final lockState = provider.raceLockFor(race);

                  if (lockState == RaceLockState.seasonOff) {
                    if (!ctx.mounted) return;
                    // 시즌오프: 차단 대신 데모 모드로 진입 안내
                    await _showSeasonOffDemoDialog(ctx, provider);
                    return;
                  }

                  if (lockState == RaceLockState.dataPending) {
                    if (!ctx.mounted) return;
                    _showLockDialogStatic(
                      ctx,
                      icon: '⏳',
                      title: '데이터 미확정',
                      message: '이번 주 실시간 경주 데이터가 아직\n업데이트되지 않았습니다.\n\n'
                          '매주 목요일 오후 5시 이후 순차 업데이트 예정',
                    );
                    return;
                  }

                  if (lockState == RaceLockState.raceLocked) {
                    if (!ctx.mounted) return;
                    _showLockDialogStatic(
                      ctx,
                      icon: '🏁',
                      title: '경주 종료',
                      message: '당일 실시간 경주가 종료되어\n모의 레이서 가동이 종료되었습니다.',
                    );
                    return;
                  }

                  // ── 정상 진입 ──────────────────────────────────
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
                  // ── 경주결과 조회 (시즌오프 중에도 항상 허용) ──
                  Navigator.push(
                    ctx,
                    PageRouteBuilder(
                      pageBuilder: (cc, a1, a2) =>
                          RaceResultScreen(race: race),
                      transitionsBuilder: (cc, a1, a2, child) =>
                          FadeTransition(opacity: a1, child: child),
                      transitionDuration:
                          const Duration(milliseconds: 300),
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

  // ── 라이프사이클 잠금 팝업 (StatelessWidget용 정적 헬퍼) ─────────
  static void _showLockDialogStatic(
    BuildContext context, {
    required String icon,
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => _LockDialog(icon: icon, title: title, message: message),
    );
  }

  // ── 시즌오프 데모 모드 진입 다이얼로그 ───────────────────────
  static Future<void> _showSeasonOffDemoDialog(
    BuildContext context,
    RaceProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (_) => const _SeasonOffDemoDialog(),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    // 가상 데이터 로드 후 대시보드 진입
    await provider.loadDemoRaceForSeasonOff();
    if (!context.mounted) return;

    final demoRace = provider.selectedRace;
    if (demoRace == null) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (c, a1, a2) =>
            RaceDashboardScreen(race: demoRace, isDemoMode: true),
        transitionsBuilder: (c, a1, a2, child) =>
            FadeTransition(opacity: a1, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// _MarqueePainter — Canvas 기반 마퀴 스크롤 텍스트 (개선판)
// progress 0.0→1.0 에 따라 텍스트 전체 폭만큼 왼쪽으로 스크롤 (오른쪽→왼쪽)
// ──────────────────────────────────────────────
class _MarqueePainter extends CustomPainter {
  final String text;
  final double progress; // 0.0 ~ 1.0 (AnimationController.repeat 값)
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
          letterSpacing: 0.3,
          shadows: [
            Shadow(
              color: textColor.withValues(alpha: 0.4),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);

    final textW = tp.width;
    if (textW <= 0) return;

    // ── 오른쪽에서 왼쪽으로 흐르는 마퀴 스크롤 ──
    // progress 0.0→1.0 에 따라 왼쪽으로 textW 만큼 이동 → 무한 반복
    // ★ 수정: Dart에서 -scrollX % textW 는 음수 피연산자로 인해 양수 반환
    //         올바른 표현: -(scrollX % textW) → 항상 0 ~ -textW 범위 음수
    final scrollX = progress * textW;
    final ty = (size.height - tp.height) / 2;

    // 첫 번째 복사본 (x0: 0 → -(textW-ε) 범위, 왼쪽으로 이동)
    final x0 = -(scrollX % textW);
    tp.paint(canvas, Offset(x0, ty));

    // 두 번째 복사본 (첫 번째 복사본 뒤에 이어붙여 끊김 방지)
    tp.paint(canvas, Offset(x0 + textW, ty));

    // 세 번째 복사본 (창 폭이 텍스트 폭보다 넓을 경우 대비)
    if (x0 + textW * 2 < size.width) {
      tp.paint(canvas, Offset(x0 + textW * 2, ty));
    }
  }

  @override
  bool shouldRepaint(_MarqueePainter old) =>
      old.progress != progress || old.text != text || old.textColor != textColor;
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

// ──────────────────────────────────────────────────────────────
// _LifecycleBanner — Null/시즌오프 공지 배너
// ──────────────────────────────────────────────────────────────
class _LifecycleBanner extends StatelessWidget {
  final String icon;
  final Color color;
  final String title;
  final String message;
  final String sub;
  final String badgeText;
  final Color badgeColor;

  const _LifecycleBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.sub,
    required this.badgeText,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: badgeColor.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                            color: badgeColor,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 11,
                      height: 1.4),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                      color: color.withValues(alpha: 0.7),
                      fontSize: 10,
                      height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// _LockDialog — 모의레이서 잠금 팝업
// ──────────────────────────────────────────────────────────────
class _LockDialog extends StatelessWidget {
  final String icon;
  final String title;
  final String message;

  const _LockDialog({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1628),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1E3A5A), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.70),
                  fontSize: 13,
                  height: 1.6),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF1A3A5A), Color(0xFF0D2040)]),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: const Color(0xFF2A5A8A), width: 1),
                ),
                child: const Text(
                  '확인',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// _SeasonOffDemoDialog — 시즌오프 체험 모드 진입 안내 다이얼로그
// ──────────────────────────────────────────────────────────────
class _SeasonOffDemoDialog extends StatelessWidget {
  const _SeasonOffDemoDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1628),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFFFD700).withValues(alpha: 0.45),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withValues(alpha: 0.12),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 아이콘
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: const Center(
                child: Text('🏇', style: TextStyle(fontSize: 32)),
              ),
            ),
            const SizedBox(height: 16),

            // 제목
            const Text(
              '체험 모의레이스',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),

            // 시즌오프 안내 배지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.4),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🚫', style: TextStyle(fontSize: 11)),
                  SizedBox(width: 5),
                  Text(
                    'SEASON OFF',
                    style: TextStyle(
                      color: Color(0xFFFF3B30),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 안내 메시지 박스
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFAA00).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFFAA00).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('⚠️', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '현재 모의 레이스는 가상의 데이터로 구현되는 경주입니다.',
                          style: TextStyle(
                            color: const Color(0xFFFFAA00).withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '실제 경주 데이터가 아닌 시뮬레이션 전용 가상 말·기수 데이터를 사용합니다. '
                    '앱의 기능과 구조를 체험하는 용도로만 활용해 주세요.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Text(
              '다음 주 목요일 오후 5시 이후 실제 경주 데이터 업데이트 예정',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 10,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // 버튼 2개
            Row(
              children: [
                // 취소
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2A3A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF2A4A6A)),
                      ),
                      child: Text(
                        '취소',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 체험 시작
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFB8960C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('🏁', style: TextStyle(fontSize: 16)),
                          SizedBox(width: 6),
                          Text(
                            '체험 시작',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
