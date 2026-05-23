import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/race_provider.dart';
import '../utils/app_theme.dart';
import 'sandbox_mode_screen.dart';
import 'login_screen.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  bool   _isLoggedIn = false;
  String _userName   = '';
  String _userEmail  = '';

  @override
  void initState() {
    super.initState();
    _loadLoginState();
  }

  Future<void> _loadLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = prefs.getBool('kmt_logged_in') ?? false;
      _userName   = prefs.getString('kmt_name')  ?? '';
      _userEmail  = prefs.getString('kmt_email') ?? '';
    });
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1A2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1A3A5A)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🚪', style: TextStyle(fontSize: 32)),
              const SizedBox(height: 12),
              const Text('로그아웃',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('정말 로그아웃하시겠습니까?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2A3A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF3A5A7A)),
                      ),
                      child: const Center(child: Text('취소',
                          style: TextStyle(color: Color(0xFF8A9ABB),
                              fontSize: 13, fontWeight: FontWeight.w700))),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A0A0A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFFF3B30).withValues(alpha: 0.6)),
                      ),
                      child: const Center(child: Text('로그아웃',
                          style: TextStyle(color: Color(0xFFFF5252),
                              fontSize: 13, fontWeight: FontWeight.w700))),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('kmt_logged_in', false);
      if (!mounted) return;
      setState(() { _isLoggedIn = false; _userName = ''; _userEmail = ''; });
    }
  }

  Future<void> _goToLogin() async {
    final result = await Navigator.push<bool>(
      context,
      PageRouteBuilder(
        pageBuilder: (c, a1, a2) => const LoginScreen(),
        transitionsBuilder: (c, a1, a2, child) =>
            FadeTransition(opacity: a1, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
    if (result == true) await _loadLoginState();
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileCard(context),
                    const SizedBox(height: 20),
                    _buildSubscriptionSection(context),
                    const SizedBox(height: 20),
                    // ── 샌드박스 모드 배너 ──────────────────────────
                    _buildSandboxBanner(context),
                    const SizedBox(height: 20),
                    _buildMenuSection(context),
                    const SizedBox(height: 20),
                    _buildLegalSection(context),
                    const SizedBox(height: 20),
                    _buildAppInfo(),
                  ],
                ),
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
              color: const Color(0xFF1A2A3A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3A5A7A)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('👤', style: TextStyle(fontSize: 16)),
                SizedBox(width: 6),
                Text('마이페이지',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    return Consumer<RaceProvider>(
      builder: (_, provider, __) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0C1A2E), Color(0xFF071220)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            // ── 프로필 행 ─────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    gradient: AppTheme.goldGradient,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.25),
                      blurRadius: 12)],
                  ),
                  child: Center(
                    child: Text(
                      _isLoggedIn ? '🏇' : '👤',
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 로그인 상태 + 회원등급 배지
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _isLoggedIn
                                  ? const Color(0xFF1A3A1A)
                                  : const Color(0xFF2A1A1A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _isLoggedIn
                                    ? const Color(0xFF2ECC71).withValues(alpha: 0.5)
                                    : const Color(0xFFFF5252).withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              _isLoggedIn ? '● 로그인' : '● 비로그인',
                              style: TextStyle(
                                  color: _isLoggedIn
                                      ? const Color(0xFF2ECC71)
                                      : const Color(0xFFFF7070),
                                  fontSize: 9, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            provider.isPremium ? '프리미엄 회원' : '일반 회원',
                            style: TextStyle(
                                color: provider.isPremium
                                    ? const Color(0xFFFFD700)
                                    : Colors.white.withValues(alpha: 0.5),
                                fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isLoggedIn && _userName.isNotEmpty
                            ? _userName
                            : '경마통 사용자',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      if (_isLoggedIn && _userEmail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(_userEmail,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 10)),
                      ],
                      const SizedBox(height: 6),
                      Row(children: [
                        _statBadge('시뮬', provider.isPremium
                            ? '무제한' : '${provider.remainingFree}회 남음'),
                        const SizedBox(width: 6),
                        _statBadge('레이스', 'AI 모의'),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ── 로그인/로그아웃 + 업그레이드 버튼 행 ─────────────
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _isLoggedIn ? _logout : _goToLogin,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _isLoggedIn
                            ? const Color(0xFF2A1A1A)
                            : const Color(0xFF1A2A3A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isLoggedIn
                              ? const Color(0xFFFF3B30).withValues(alpha: 0.5)
                              : const Color(0xFF2979FF).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isLoggedIn
                                  ? Icons.logout_rounded
                                  : Icons.login_rounded,
                              color: _isLoggedIn
                                  ? const Color(0xFFFF5252)
                                  : const Color(0xFF64B5F6),
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _isLoggedIn ? '로그아웃' : '로그인',
                              style: TextStyle(
                                  color: _isLoggedIn
                                      ? const Color(0xFFFF5252)
                                      : const Color(0xFF64B5F6),
                                  fontSize: 12, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!provider.isPremium) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showUpgradeDialog(context, provider),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          gradient: AppTheme.goldGradient,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                            blurRadius: 8)],
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('👑', style: TextStyle(fontSize: 13)),
                              SizedBox(width: 4),
                              Text('프리미엄 업그레이드',
                                  style: TextStyle(
                                      color: Color(0xFF1A1A1A),
                                      fontSize: 10, fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBadge(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$label: $value',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 9.5)),
    );
  }

  Widget _buildSubscriptionSection(BuildContext context) {
    return Consumer<RaceProvider>(
      builder: (_, provider, __) {
        // ── 이미 구독 중일 때 ──────────────────────────────────────
        if (provider.isPremium) {
          return _buildActivePlanCard(provider);
        }

        // ── 플랜 선택 카드 ────────────────────────────────────────
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 섹션 타이틀
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(width: 3, height: 16,
                      decoration: BoxDecoration(
                          gradient: AppTheme.goldGradient,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  const Text('💎 플랜 선택',
                      style: TextStyle(color: AppTheme.textWhite,
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            // 베이직 플랜 카드
            _buildPlanCard(
              context: context,
              provider: provider,
              planType: 'basic',
              emoji: '⚡',
              title: '베이직',
              price: '5,500원',
              badgeText: '입문 추천',
              badgeColor: const Color(0xFF3B82F6),
              borderColor: const Color(0xFF3B82F6),
              benefits: [
                ('✅', '하루 3경주 AI 시뮬레이션'),
                ('✅', '기본 스탯 분석 (15개 API)'),
                ('✅', '경주 배당률 실시간 조회'),
                ('❌', '고배당 복병마 조합 추천'),
                ('❌', '경주별 상세 AI 인사이트'),
              ],
              ctaText: '⚡  월 5,500원으로 시작하기',
              ctaGradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
              ),
            ),
            const SizedBox(height: 10),
            // 프리미엄 플랜 카드
            _buildPlanCard(
              context: context,
              provider: provider,
              planType: 'premium',
              emoji: '👑',
              title: '프리미엄',
              price: '9,900원',
              badgeText: 'BEST',
              badgeColor: const Color(0xFFFFD700),
              borderColor: const Color(0xFFFFD700),
              benefits: [
                ('✅', '전 레이스 무제한 AI 시뮬레이션'),
                ('✅', '23개 API 실시간 스탯 분석'),
                ('✅', '고배당 복병마 조합 추천'),
                ('✅', '경주별 상세 AI 인사이트'),
                ('✅', '샌드박스 모드 & 정밀도 리포트'),
              ],
              ctaText: '👑  월 9,900원으로 시작하기',
              ctaGradient: AppTheme.goldGradient,
              isRecommended: true,
            ),
          ],
        );
      },
    );
  }

  /// 구독 활성 카드
  Widget _buildActivePlanCard(RaceProvider provider) {
    final isPremiumPlan = provider.isPremium;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFD700).withValues(alpha: 0.12),
            const Color(0xFF0C1A2E),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Text(isPremiumPlan ? '👑' : '⚡',
              style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPremiumPlan ? '프리미엄 구독 활성' : '베이직 구독 활성',
                  style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 14, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  isPremiumPlan
                      ? '전 레이스 무제한 AI 시뮬레이션 이용 가능'
                      : '하루 3경주 AI 시뮬레이션 이용 가능',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 플랜 카드 공통 위젯
  Widget _buildPlanCard({
    required BuildContext context,
    required RaceProvider provider,
    required String planType,
    required String emoji,
    required String title,
    required String price,
    required String badgeText,
    required Color badgeColor,
    required Color borderColor,
    required List<(String, String)> benefits,
    required String ctaText,
    required Gradient ctaGradient,
    bool isRecommended = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRecommended
              ? borderColor.withValues(alpha: 0.6)
              : borderColor.withValues(alpha: 0.35),
          width: isRecommended ? 1.5 : 1.0,
        ),
        boxShadow: isRecommended
            ? [BoxShadow(
                color: borderColor.withValues(alpha: 0.12),
                blurRadius: 10, spreadRadius: 1)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      color: isRecommended
                          ? const Color(0xFFFFD700)
                          : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              // 배지
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                ),
                child: Text(badgeText,
                    style: TextStyle(
                        color: badgeColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800)),
              ),
              const Spacer(),
              // 가격
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '월 $price',
                      style: TextStyle(
                          color: isRecommended
                              ? const Color(0xFFFFD700)
                              : const Color(0xFF60A5FA),
                          fontSize: 13,
                          fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 혜택 목록
          ...benefits.map((b) => _benefitRow(b.$1, b.$2, enabled: b.$1 == '✅')),
          const SizedBox(height: 12),
          // CTA 버튼
          GestureDetector(
            onTap: () => _showPlanUpgradeDialog(context, provider, planType),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                gradient: ctaGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                ctaText,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: isRecommended
                        ? const Color(0xFF1A1A1A)
                        : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _benefitRow(String icon, String text, {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  color: enabled
                      ? Colors.white.withValues(alpha: 0.75)
                      : Colors.white.withValues(alpha: 0.3),
                  fontSize: 11,
                  decoration: enabled ? null : TextDecoration.lineThrough,
                  decorationColor: Colors.white.withValues(alpha: 0.25))),
        ],
      ),
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    final menus = [
      ('🔔', '공지사항', '최신 업데이트 및 서비스 안내',
          () => _showNoticeSheet(context)),
      ('⭐', '앱 평점 남기기', '경마통에 별점을 주세요! 리뷰가 큰 힘이 돼요',
          () => _showRatingSheet(context)),
      ('📤', '친구에게 공유', '카카오톡 친구 1명 공유 시 3회 모의 레이스 추가!',
          () => _showShareSheet(context)),
      ('📧', '문의하기', '서비스 관련 문의 및 버그 신고',
          () => _showInquirySheet(context)),
    ];

    return _menuGroup('⚙️ 앱 설정', menus, context);
  }

  /// 샌드박스 모드 진입 배너 카드
  Widget _buildSandboxBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SandboxModeScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A0A2E), Color(0xFF0D1A2E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.7), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
              blurRadius: 12, spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            // 아이콘 컨테이너
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('🧪', style: TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 14),
            // 텍스트
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '샌드박스 모드',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: const Color(0xFF7C3AED).withValues(alpha: 0.6)),
                        ),
                        child: const Text(
                          'BETA',
                          style: TextStyle(
                            color: Color(0xFFB57BFF),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '과거 경주 재현 · 보정 시뮬레이션 · 예측 정밀도 분석',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 화살표
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.science_rounded,
                color: Color(0xFFB57BFF),
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegalSection(BuildContext context) {
    final menus = [
      ('📜', '이용약관', '서비스 이용약관 확인', () => _showTermsSheet(context)),
      ('🔒', '개인정보처리방침', '개인정보 수집 및 이용 안내', () => _showPrivacySheet(context)),
      ('⚖️', '법적 고지', '책임의 한계 및 법적 고지사항', () => _showLegalNoticeSheet(context)),
    ];

    return _menuGroup('📋 약관 및 정책', menus, context);
  }

  Widget _menuGroup(String title, List<(String, String, String, VoidCallback?)> items, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 3, height: 16,
                decoration: BoxDecoration(
                  gradient: AppTheme.goldGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0C1A2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1A2A3A)),
          ),
          child: Column(
            children: items.asMap().entries.map((e) {
              final i = e.key;
              final (emoji, label, sub, onTap) = e.value;
              return GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    border: i < items.length - 1
                        ? const Border(
                            bottom: BorderSide(
                                color: Color(0xFF1A2A3A), width: 0.7))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            Text(sub,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 10.5)),
                          ],
                        ),
                      ),
                      if (onTap != null)
                        Icon(Icons.chevron_right,
                            color: Colors.white.withValues(alpha: 0.3),
                            size: 18),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAppInfo() {
    return Center(
      child: Column(
        children: [
          const Text('🏇', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 6),
          const Text('경마통',
              style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('버전 1.0.0  ·  AI 모의 레이스',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
          const SizedBox(height: 4),
          Text('© 2025 경마통. All rights reserved.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25), fontSize: 10)),
        ],
      ),
    );
  }

  // ── 기존 호환 (내부 참조 유지용) ──────────────────────────────
  void _showUpgradeDialog(BuildContext context, RaceProvider provider) {
    _showPlanUpgradeDialog(context, provider, 'premium');
  }

  // ── 플랜별 구독 다이얼로그 ────────────────────────────────────
  void _showPlanUpgradeDialog(
      BuildContext context, RaceProvider provider, String planType) {
    final isBasic   = planType == 'basic';
    final emoji     = isBasic ? '⚡' : '👑';
    final title     = isBasic ? '베이직 구독' : '프리미엄 구독';
    final price     = isBasic ? '월 5,500원' : '월 9,900원';
    final accentClr = isBasic ? const Color(0xFF3B82F6) : const Color(0xFFFFD700);
    final desc      = isBasic
        ? '월 5,500원으로 하루 3경주 AI 시뮬레이션을\n이용할 수 있습니다.'
        : '월 9,900원으로 전 레이스 무제한\nAI 시뮬레이션을 이용할 수 있습니다.';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0C1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text('$title 신청',
                style: TextStyle(color: accentClr,
                    fontSize: 15, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(desc,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12, height: 1.55)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: accentClr.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accentClr.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('결제 금액',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11)),
                  Text(price,
                      style: TextStyle(
                          color: accentClr,
                          fontSize: 14,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () {
              provider.setPremium(true);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$emoji $title이 활성화되었습니다!'),
                  backgroundColor: const Color(0xFF1A3A1A),
                ),
              );
            },
            child: Text('구독하기',
                style: TextStyle(
                    color: accentClr, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ── 앱 평점 시트 ──────────────────────────────────────────────
  void _showRatingSheet(BuildContext context) {
    int selectedStars = 5;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            left: 20, right: 20, top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text('⭐ 앱 평점 남기기',
                  style: TextStyle(color: Color(0xFFFFD700),
                      fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('경마통을 이용해 주셔서 감사합니다!\n별점을 남겨 서비스 개선에 도움을 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12, height: 1.5)),
              const SizedBox(height: 20),
              // 별점 선택
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => GestureDetector(
                  onTap: () => setState(() => selectedStars = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      i < selectedStars ? '⭐' : '☆',
                      style: TextStyle(
                        fontSize: 36,
                        color: i < selectedStars
                            ? const Color(0xFFFFD700)
                            : Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                )),
              ),
              const SizedBox(height: 8),
              Text(
                ['', '별로예요', '그저 그래요', '괜찮아요', '좋아요!', '최고예요! 🎉'][selectedStars],
                style: TextStyle(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.8),
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: const Color(0xFF1A1A1A),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${'⭐' * selectedStars} 평점 ${selectedStars}점을 남겨주셔서 감사합니다!',
                        ),
                        backgroundColor: const Color(0xFF1A3A1A),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  },
                  child: const Text('평점 제출하기',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 친구 공유 시트 (카카오톡 1명 → 3회 모의 레이스 추가) ──────
  void _showShareSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text('📤 친구에게 공유',
                style: TextStyle(color: Color(0xFFFFD700),
                    fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            // 보상 배너
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A3A1A), Color(0xFF0D1E0D)],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Text('🎁', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('카카오톡 1명 공유 시',
                            style: TextStyle(
                                color: Color(0xFF22C55E),
                                fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        const Text('모의 레이스 +3회 무료 추가!',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text('최대 10명 공유 → +30회 적립 가능',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 공유 링크
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF071220),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1A2A3A)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'https://play.google.com/store/apps/경마통',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(const ClipboardData(
                          text: 'https://play.google.com/store/apps/경마통'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('링크가 복사되었습니다!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2A3A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('복사',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 카카오톡 공유 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFE000),
                  foregroundColor: const Color(0xFF191600),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _sendKakaoShare(context),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('💬', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 8),
                    Text('카카오톡으로 공유하기',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 카카오톡 공유 처리 (3회 모의 레이스 지급)
  Future<void> _sendKakaoShare(BuildContext context) async {
    // 공유 텍스트 클립보드 복사 + SharedPreferences 보상 처리
    const shareText =
        '🏇 경마통 AI 모의 레이스 앱을 추천드려요!\n'
        '실제 KRA 데이터 기반 AI 시뮬레이션으로 경주를 예측해보세요.\n'
        '▶ https://play.google.com/store/apps/경마통';
    await Clipboard.setData(const ClipboardData(text: shareText));

    // SharedPreferences에 공유 횟수 및 보상 저장
    final prefs = await SharedPreferences.getInstance();
    final shareCount = (prefs.getInt('share_count') ?? 0) + 1;
    final bonusRaces  = (prefs.getInt('bonus_race_count') ?? 0) + 3;
    await prefs.setInt('share_count', shareCount);
    await prefs.setInt('bonus_race_count', bonusRaces);

    if (!context.mounted) return;
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0C1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🎁 공유 완료!',
            style: TextStyle(color: Color(0xFF22C55E),
                fontSize: 16, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('공유 텍스트가 클립보드에 복사되었습니다.\n카카오톡에 붙여넣어 친구에게 보내주세요!',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12, height: 1.5)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A3A1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Text('🎫', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('모의 레이스 +3회 지급!',
                            style: TextStyle(
                                color: Color(0xFF22C55E),
                                fontSize: 13, fontWeight: FontWeight.w800)),
                        Text('누적 보너스: 총 ${bonusRaces}회',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 10.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인',
                style: TextStyle(
                    color: Color(0xFF22C55E), fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ── 문의하기 시트 ─────────────────────────────────────────────
  void _showInquirySheet(BuildContext context) {
    final ctrlName    = TextEditingController();
    final ctrlEmail   = TextEditingController();
    final ctrlContent = TextEditingController();
    String inquiryCategory = '기능 문의';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            left: 20, right: 20, top: 8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Center(
                  child: Text('📧 문의하기',
                      style: TextStyle(color: Color(0xFFFFD700),
                          fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text('빠른 시간 내에 답변드리겠습니다.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11)),
                ),
                const SizedBox(height: 16),
                // 문의 유형
                const Text('문의 유형',
                    style: TextStyle(color: Colors.white,
                        fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ['기능 문의', '버그 신고', '결제 문의', '기타'].map((cat) =>
                    GestureDetector(
                      onTap: () => setState(() => inquiryCategory = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: inquiryCategory == cat
                              ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                              : const Color(0xFF071220),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: inquiryCategory == cat
                                ? const Color(0xFFFFD700).withValues(alpha: 0.6)
                                : const Color(0xFF1A2A3A),
                          ),
                        ),
                        child: Text(cat,
                            style: TextStyle(
                                color: inquiryCategory == cat
                                    ? const Color(0xFFFFD700)
                                    : Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                                fontWeight: inquiryCategory == cat
                                    ? FontWeight.w700
                                    : FontWeight.w400)),
                      ),
                    ),
                  ).toList(),
                ),
                const SizedBox(height: 14),
                // 이름
                _inquiryField('닉네임', ctrlName, '닉네임을 입력하세요', maxLines: 1),
                const SizedBox(height: 10),
                // 이메일
                _inquiryField('이메일 (답변 수신용)', ctrlEmail,
                    'example@email.com', maxLines: 1,
                    keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 10),
                // 내용
                _inquiryField('문의 내용', ctrlContent,
                    '문의 내용을 자세히 작성해 주세요.\n\n예) 앱 버전, 기기 모델, 문제 상황',
                    maxLines: 5),
                const SizedBox(height: 6),
                Text('문의 이메일: pizon8113@gmail.com',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 10)),
                const SizedBox(height: 16),
                // 제출 버튼
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: const Color(0xFF1A1A1A),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      if (ctrlContent.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('문의 내용을 입력해 주세요.')),
                        );
                        return;
                      }
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              '📧 문의가 접수되었습니다!\n빠른 시간 내에 이메일로 답변드리겠습니다.'),
                          backgroundColor: Color(0xFF1A3A1A),
                          duration: Duration(seconds: 4),
                        ),
                      );
                    },
                    child: const Text('문의 제출하기',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inquiryField(
    String label,
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF071220),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1A2A3A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1A2A3A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: Color(0xFFFFD700), width: 1.2),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  void _showNoticeSheet(BuildContext context) {
    _showInfoSheet(context, '🔔 공지사항', [
      _NoticeItem('v1.0.0 서비스 출시', '2025.05.17',
          '경마통 AI 모의 레이스 서비스가 출시되었습니다. 23개 API 데이터 기반 AI 분석으로 더욱 정확한 레이스 예측을 제공합니다.'),
      _NoticeItem('서울/부산경남/제주 전 경마장 지원', '2025.05.17',
          '국내 3개 경마장의 모든 경주를 지원합니다. 각 경마장별 트랙 특성이 AI 시뮬레이션에 반영됩니다.'),
      _NoticeItem('개인정보처리방침 안내', '2025.05.01',
          '서비스 이용 전 개인정보처리방침을 반드시 확인해 주시기 바랍니다.'),
    ]);
  }

  void _showTermsSheet(BuildContext context) {
    _showTextSheet(context, '📜 이용약관',
      '''제1조 (목적)
본 약관은 경마통(이하 "서비스")이 제공하는 AI 모의 레이스 서비스의 이용과 관련하여 서비스와 이용자 간의 권리, 의무 및 책임사항을 규정함을 목적으로 합니다.

제2조 (서비스 내용)
① 경마통은 KRA 공식 데이터를 기반으로 AI 분석 정보 및 모의 레이스 시뮬레이션을 제공합니다.
② 본 서비스는 정보 제공 목적으로만 운영되며, 실제 경마 결과와 일치하지 않을 수 있습니다.
③ 프리미엄 서비스는 월 9,900원의 구독료가 부과됩니다.

제3조 (이용자 의무)
① 이용자는 서비스를 통해 제공되는 정보를 불법 도박 등 부정한 목적으로 이용해서는 안 됩니다.
② 이용자는 타인의 정보를 무단으로 수집하거나 이용해서는 안 됩니다.

제4조 (책임의 한계)
① 경마통이 제공하는 AI 분석 정보는 참고용이며, 실제 투표 결과에 대한 책임을 지지 않습니다.
② 서비스 장애, 데이터 지연 등에 의한 손해에 대해 책임을 지지 않습니다.

제5조 (지식재산권)
서비스 내 모든 콘텐츠(AI 분석, UI 디자인 등)의 지식재산권은 경마통에 귀속됩니다.''');
  }

  void _showPrivacySheet(BuildContext context) {
    _showTextSheet(context, '🔒 개인정보처리방침',
      '''1. 수집하는 개인정보 항목
- 서비스 이용 기록 (경주 조회, 시뮬레이션 실행)
- 구독 결제 정보 (결제 처리 목적)
- 기기 정보 (앱 최적화 목적)

2. 개인정보의 수집 및 이용 목적
- AI 분석 서비스 제공 및 개선
- 구독 서비스 관리
- 고객 문의 대응

3. 개인정보의 보유 및 이용 기간
- 서비스 이용 기간 동안 보유
- 관련 법령에 따라 일정 기간 보관 후 파기

4. 개인정보의 제3자 제공
- 원칙적으로 이용자의 개인정보를 제3자에게 제공하지 않습니다.
- 법령의 규정에 의한 경우 예외로 합니다.

5. 개인정보 보호 책임자
- 담당: 경마통 개발팀
- 이메일: pizon8113@gmail.com

6. 이용자의 권리
이용자는 언제든지 개인정보 열람, 정정, 삭제를 요청할 수 있습니다.''');
  }

  void _showLegalNoticeSheet(BuildContext context) {
    _showTextSheet(context, '⚖️ 법적 고지',
      '''■ 서비스 목적
경마통은 KRA(한국마사회) 공식 API 데이터를 활용한 AI 분석 정보 제공 서비스입니다. 본 서비스는 교육 및 오락 목적의 정보 제공 서비스이며, 실제 "마권 구매"와는 무관합니다.

■ 면책 조항
① 본 서비스에서 제공하는 AI 예측 정보는 통계적 분석에 기반한 참고 자료입니다.
② 실제 경마 결과는 예측과 다를 수 있으며, 이로 인한 손해에 대해 경마통은 책임지지 않습니다.
③ 만 19세 미만은 경마 관련 서비스 이용이 제한될 수 있습니다.

■ 도박 중독 예방
경마 도박 중독 상담: 국번없이 1336 (24시간)
한국도박문제관리센터: www.kcgp.or.kr

■ 데이터 출처
- 한국마사회(KRA) 공식 Open API
- 실시간 경주 데이터 제공''');
  }

  void _showInfoSheet(BuildContext context, String title, List<_NoticeItem> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => Column(
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(title,
                  style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 16, fontWeight: FontWeight.w900)),
            ),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: items.map((n) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF071220),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1A2A3A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(n.title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13, fontWeight: FontWeight.w800)),
                          ),
                          Text(n.date,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(n.content,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 11, height: 1.5)),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTextSheet(BuildContext context, String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.80,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => Column(
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(title,
                  style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 16, fontWeight: FontWeight.w900)),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: Text(content,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12, height: 1.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeItem {
  final String title;
  final String date;
  final String content;
  const _NoticeItem(this.title, this.date, this.content);
}
