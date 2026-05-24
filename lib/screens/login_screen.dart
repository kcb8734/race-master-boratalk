// ══════════════════════════════════════════════════════════════════════
// LoginScreen — 경마통 로그인 / 회원가입 화면
// ══════════════════════════════════════════════════════════════════════
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  /// pop 후 콜백 (로그인 성공 시 호출)
  final VoidCallback? onLoginSuccess;
  const LoginScreen({super.key, this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // ── 탭 (로그인 / 회원가입) ──────────────────────────────────────
  bool _isSignUp = false;

  // ── 컨트롤러 ──────────────────────────────────────────────────
  final _emailCtrl     = TextEditingController();
  final _pwCtrl        = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();
  final _nameCtrl      = TextEditingController();

  bool _obscurePw        = true;
  bool _obscurePwConfirm = true;
  bool _isLoading        = false;
  String? _errorMsg;

  // ── 애니메이션 ─────────────────────────────────────────────────
  late AnimationController _bgAnim;
  late AnimationController _formAnim;
  late Animation<double>   _formSlide;
  late Animation<double>   _formFade;

  @override
  void initState() {
    super.initState();
    _bgAnim = AnimationController(
        vsync: this, duration: const Duration(seconds: 8))
      ..repeat(reverse: true);
    _formAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _formSlide = Tween<double>(begin: 0.06, end: 0.0).animate(
        CurvedAnimation(parent: _formAnim, curve: Curves.easeOutCubic));
    _formFade = CurvedAnimation(parent: _formAnim, curve: Curves.easeOut);
    _formAnim.forward();
  }

  @override
  void dispose() {
    _bgAnim.dispose();
    _formAnim.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _switchTab(bool toSignUp) {
    setState(() {
      _isSignUp = toSignUp;
      _errorMsg = null;
    });
    _formAnim
      ..reset()
      ..forward();
  }

  String? _validateEmail(String v) {
    if (v.trim().isEmpty) return '이메일을 입력해주세요.';
    final emailReg = RegExp(r'^[\w.-]+@[\w.-]+\.\w+$');
    if (!emailReg.hasMatch(v.trim())) return '올바른 이메일 형식을 입력해주세요.';
    return null;
  }

  String? _validatePw(String v) {
    if (v.isEmpty) return '비밀번호를 입력해주세요.';
    if (v.length < 6) return '비밀번호는 6자 이상이어야 합니다.';
    return null;
  }

  Future<void> _submit() async {
    setState(() { _errorMsg = null; });

    final emailErr = _validateEmail(_emailCtrl.text);
    final pwErr    = _validatePw(_pwCtrl.text);
    if (emailErr != null) { setState(() => _errorMsg = emailErr); return; }
    if (pwErr != null)    { setState(() => _errorMsg = pwErr);    return; }

    if (_isSignUp) {
      if (_nameCtrl.text.trim().isEmpty) {
        setState(() => _errorMsg = '닉네임을 입력해주세요.');
        return;
      }
      if (_pwCtrl.text != _pwConfirmCtrl.text) {
        setState(() => _errorMsg = '비밀번호가 일치하지 않습니다.');
        return;
      }
    }

    setState(() => _isLoading = true);

    // ── 간단한 로컬 인증 시뮬레이션 (SharedPreferences 기반) ─────
    await Future.delayed(const Duration(milliseconds: 900));
    final prefs = await SharedPreferences.getInstance();

    if (_isSignUp) {
      // 회원가입: 자격증명 저장
      await prefs.setString('kmt_email',    _emailCtrl.text.trim());
      await prefs.setString('kmt_password', _pwCtrl.text);
      await prefs.setString('kmt_name',     _nameCtrl.text.trim());
      await prefs.setBool('kmt_logged_in',  true);
      if (!mounted) return;
      setState(() => _isLoading = false);
      _onSuccess('${_nameCtrl.text.trim()}님, 환영합니다!');
    } else {
      // 로그인: 저장된 자격증명 검증
      final savedEmail = prefs.getString('kmt_email') ?? '';
      final savedPw    = prefs.getString('kmt_password') ?? '';
      if (savedEmail == _emailCtrl.text.trim() && savedPw == _pwCtrl.text) {
        await prefs.setBool('kmt_logged_in', true);
        final name = prefs.getString('kmt_name') ?? '사용자';
        if (!mounted) return;
        setState(() => _isLoading = false);
        _onSuccess('$name님, 반갑습니다!');
      } else {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMsg  = '이메일 또는 비밀번호가 올바르지 않습니다.';
        });
      }
    }
  }

  void _onSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Text('🏇', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(msg, style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
        backgroundColor: const Color(0xFF1A3A6A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    widget.onLoginSuccess?.call();
    if (Navigator.canPop(context)) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050D1A),
      body: Stack(
        children: [
          // ── 배경 애니메이션 ──────────────────────────────────────
          _buildAnimatedBackground(),

          // ── 본문 ─────────────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  _buildLogo(),
                  const SizedBox(height: 32),
                  _buildTabBar(),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _formFade,
                    child: AnimatedBuilder(
                      animation: _formSlide,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, _formSlide.value *
                            MediaQuery.of(context).size.height * 0.1),
                        child: child,
                      ),
                      child: _buildForm(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildDivider(),
                  const SizedBox(height: 16),
                  _buildSocialButtons(),
                  const SizedBox(height: 32),
                  _buildFooter(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // ── 뒤로가기 버튼 ─────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: GestureDetector(
              onTap: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 배경 애니메이션 ────────────────────────────────────────────
  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _bgAnim,
      builder: (_, __) {
        final t = _bgAnim.value;
        return Container(
          decoration: const BoxDecoration(color: Color(0xFF050D1A)),
          child: CustomPaint(
            painter: _BgPainter(t),
            size: Size.infinite,
          ),
        );
      },
    );
  }

  // ── 로고 영역 ─────────────────────────────────────────────────
  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFF8B6914)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                blurRadius: 24, spreadRadius: 4,
              ),
            ],
          ),
          child: const Center(
            child: Text('🏇', style: TextStyle(fontSize: 36)),
          ),
        ),
        const SizedBox(height: 14),
        const Text('경마통',
            style: TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 28, fontWeight: FontWeight.w900,
                letterSpacing: 2)),
        const SizedBox(height: 4),
        Text('AI 모의 레이스 · 경주 분석 플랫폼',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12, letterSpacing: 0.5)),
      ],
    );
  }

  // ── 탭바 ─────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A3A5A)),
      ),
      child: Row(
        children: [
          Expanded(child: _tabBtn('로그인', !_isSignUp, () => _switchTab(false))),
          Expanded(child: _tabBtn('회원가입', _isSignUp, () => _switchTab(true))),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF1A3A6A), Color(0xFF0C2040)])
              : null,
          borderRadius: BorderRadius.circular(11),
          boxShadow: active
              ? [BoxShadow(
                  color: const Color(0xFF2979FF).withValues(alpha: 0.3),
                  blurRadius: 8)]
              : null,
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF5A7A9A),
                  fontSize: 14, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  // ── 폼 ───────────────────────────────────────────────────────
  Widget _buildForm() {
    return Column(
      children: [
        if (_isSignUp) ...[
          _inputField(
            controller: _nameCtrl,
            label: '닉네임',
            hint: '사용할 닉네임을 입력하세요',
            icon: Icons.person_rounded,
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 12),
        ],
        _inputField(
          controller: _emailCtrl,
          label: '이메일',
          hint: 'example@email.com',
          icon: Icons.email_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _inputField(
          controller: _pwCtrl,
          label: '비밀번호',
          hint: '6자 이상 입력하세요',
          icon: Icons.lock_rounded,
          obscure: _obscurePw,
          onToggleObscure: () => setState(() => _obscurePw = !_obscurePw),
        ),
        if (_isSignUp) ...[
          const SizedBox(height: 12),
          _inputField(
            controller: _pwConfirmCtrl,
            label: '비밀번호 확인',
            hint: '비밀번호를 다시 입력하세요',
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePwConfirm,
            onToggleObscure: () =>
                setState(() => _obscurePwConfirm = !_obscurePwConfirm),
          ),
        ],
        if (!_isSignUp) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: _showForgotPassword,
              child: const Text('비밀번호를 잊으셨나요?',
                  style: TextStyle(
                      color: Color(0xFF64B5F6),
                      fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
        ],

        // ── 에러 메시지 ───────────────────────────────────────────
        if (_errorMsg != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF2A0A0A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Color(0xFFFF5252), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_errorMsg!,
                      style: const TextStyle(
                          color: Color(0xFFFF7070), fontSize: 12)),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // ── 제출 버튼 ─────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: _isLoading ? null : _submit,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: _isLoading
                    ? const LinearGradient(
                        colors: [Color(0xFF1A2A3A), Color(0xFF0C1A2E)])
                    : const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: _isLoading
                    ? null
                    : [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                          blurRadius: 16, spreadRadius: 1,
                        ),
                      ],
              ),
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        _isSignUp ? '회원가입 완료' : '로그인',
                        style: const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontSize: 15, fontWeight: FontWeight.w900,
                            letterSpacing: 0.5),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    VoidCallback? onToggleObscure,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0C1A2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1A3A5A)),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25), fontSize: 13),
              prefixIcon: Icon(icon,
                  color: const Color(0xFF64B5F6), size: 18),
              suffixIcon: onToggleObscure != null
                  ? GestureDetector(
                      onTap: onToggleObscure,
                      child: Icon(
                        obscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: const Color(0xFF4A6A8A), size: 18,
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  // ── 구분선 ───────────────────────────────────────────────────
  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(
            color: Colors.white.withValues(alpha: 0.1), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('또는',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 11)),
        ),
        Expanded(child: Divider(
            color: Colors.white.withValues(alpha: 0.1), thickness: 1)),
      ],
    );
  }

  // ── 소셜 로그인 버튼 ─────────────────────────────────────────
  Widget _buildSocialButtons() {
    return Column(
      children: [
        _socialBtn(
          color: const Color(0xFFFEE500),
          textColor: const Color(0xFF191919),
          label: '카카오 계정으로 계속하기',
          emoji: '💛',
          onTap: () => _showSocialNotice('카카오'),
        ),
        const SizedBox(height: 10),
        _socialBtn(
          color: const Color(0xFF03C75A),
          textColor: Colors.white,
          label: '네이버 계정으로 계속하기',
          emoji: '🟢',
          onTap: () => _showSocialNotice('네이버'),
        ),
        const SizedBox(height: 10),
        _socialBtn(
          color: const Color(0xFF1A2A3A),
          textColor: Colors.white,
          label: 'Google 계정으로 계속하기',
          emoji: '🔵',
          borderColor: const Color(0xFF2A3A4A),
          onTap: () => _showSocialNotice('Google'),
        ),
      ],
    );
  }

  Widget _socialBtn({
    required Color color,
    required Color textColor,
    required String label,
    required String emoji,
    Color? borderColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: borderColor != null ? Border.all(color: borderColor) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: textColor,
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  void _showSocialNotice(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$provider 로그인은 준비 중입니다.',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A2A3A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showForgotPassword() {
    showDialog(
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
              const Text('🔑', style: TextStyle(fontSize: 32)),
              const SizedBox(height: 12),
              const Text('비밀번호 재설정',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('가입하신 이메일로\n비밀번호 재설정 링크를 보내드립니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12)),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF2979FF), Color(0xFF1565C0)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('확인',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 하단 푸터 ─────────────────────────────────────────────────
  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          '로그인 시 서비스 이용약관 및 개인정보처리방침에\n동의하는 것으로 간주됩니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 10),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _footerLink('이용약관'),
            Text(' · ',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 10)),
            _footerLink('개인정보처리방침'),
            Text(' · ',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 10)),
            _footerLink('고객센터'),
          ],
        ),
      ],
    );
  }

  Widget _footerLink(String label) {
    return GestureDetector(
      onTap: () {},
      child: Text(label,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 10, decoration: TextDecoration.underline,
              decorationColor: Colors.white.withValues(alpha: 0.2))),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 배경 애니메이션 페인터
// ══════════════════════════════════════════════════════════════════════
class _BgPainter extends CustomPainter {
  final double t;
  _BgPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // 오브 1 — 금색 (좌하단)
    paint.color = const Color(0xFFFFD700).withValues(alpha: 0.04 + t * 0.03);
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * (0.6 + t * 0.1)),
      size.width * (0.5 + t * 0.15),
      paint,
    );

    // 오브 2 — 블루 (우상단)
    paint.color = const Color(0xFF2979FF).withValues(alpha: 0.05 + (1 - t) * 0.03);
    canvas.drawCircle(
      Offset(size.width * (0.8 + t * 0.05), size.height * (0.2 - t * 0.05)),
      size.width * (0.4 + t * 0.1),
      paint,
    );

    // 오브 3 — 퍼플 (중앙)
    paint.color = const Color(0xFF6A3ABA).withValues(alpha: 0.03 + t * 0.02);
    canvas.drawCircle(
      Offset(size.width * (0.5 + math.sin(t * math.pi) * 0.1),
             size.height * 0.5),
      size.width * (0.3 + t * 0.08),
      paint,
    );
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.t != t;
}
