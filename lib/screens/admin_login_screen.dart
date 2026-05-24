import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_data_panel_screen.dart';

// ══════════════════════════════════════════════════════════════════════════
//  AdminLoginScreen — 관리자 패널 접근 인증 화면
//
//  ▸ ID  : admin
//  ▸ PW  : kra2025!
//  ▸ 세션 : SharedPreferences 'admin_session' 키 (TTL 24h)
//  ▸ 인증 성공 시 → AdminDataPanelScreen 이동
// ══════════════════════════════════════════════════════════════════════════

const String _adminId  = 'admin';
const String _adminPw  = 'kra2025!';
const String _sessionKey = 'admin_session_expiry';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen>
    with SingleTickerProviderStateMixin {
  final _idCtrl   = TextEditingController();
  final _pwCtrl   = TextEditingController();
  final _formKey  = GlobalKey<FormState>();

  bool _obscure    = true;
  bool _loading    = false;
  bool _checking   = true;   // 세션 확인 중
  String _error    = '';

  late AnimationController _shakeCtrl;
  late Animation<double>   _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = Tween<double>(begin: 0, end: 8).chain(
      CurveTween(curve: Curves.elasticIn)).animate(_shakeCtrl);
    _checkExistingSession();
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  // ── 기존 세션 유효성 확인 ───────────────────────────────────────────────
  Future<void> _checkExistingSession() async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = prefs.getInt(_sessionKey) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch < expiry) {
      // 유효한 세션 존재 → 바로 패널로
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDataPanelScreen()),
        );
      }
    } else {
      if (mounted) setState(() => _checking = false);
    }
  }

  // ── 로그인 처리 ─────────────────────────────────────────────────────────
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = ''; });
    await Future.delayed(const Duration(milliseconds: 600)); // 인증 지연 효과

    final id = _idCtrl.text.trim();
    final pw = _pwCtrl.text;

    if (id == _adminId && pw == _adminPw) {
      // 세션 24시간 저장
      final prefs = await SharedPreferences.getInstance();
      final expiry = DateTime.now()
          .add(const Duration(hours: 24))
          .millisecondsSinceEpoch;
      await prefs.setInt(_sessionKey, expiry);
      if (kDebugMode) debugPrint('[AdminLogin] 인증 성공 — 세션 24h 저장');
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDataPanelScreen()),
        );
      }
    } else {
      _shakeCtrl.forward(from: 0);
      if (mounted) {
        setState(() {
          _error = '아이디 또는 비밀번호가 올바르지 않습니다.';
          _loading = false;
        });
      }
    }
  }

  // ── 세션 로그아웃 (admin_data_panel_screen 등 외부에서 호출) ──────────
  // ignore: unused_element
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A1A),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── 로고 ──────────────────────────────────────────────
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF1A0D2A)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                        blurRadius: 24, spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.admin_panel_settings,
                      color: Colors.white, size: 40),
                ),
                const SizedBox(height: 20),
                const Text(
                  '경마통 관리자',
                  style: TextStyle(
                    color: Color(0xFFE0E0FF),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Admin Data Pipeline Console',
                  style: TextStyle(color: Color(0xFF555580), fontSize: 12),
                ),
                const SizedBox(height: 36),

                // ── 로그인 폼 ─────────────────────────────────────────
                AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (ctx, child) {
                    final offset = _shakeCtrl.isAnimating
                        ? _shakeAnim.value *
                            ((_shakeCtrl.value < 0.5) ? 1 : -1)
                        : 0.0;
                    return Transform.translate(
                        offset: Offset(offset, 0), child: child);
                  },
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // ID 필드
                        _InputField(
                          controller: _idCtrl,
                          label: '관리자 ID',
                          icon: Icons.person_outline,
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'ID를 입력하세요' : null,
                        ),
                        const SizedBox(height: 14),

                        // PW 필드
                        _InputField(
                          controller: _pwCtrl,
                          label: '비밀번호',
                          icon: Icons.lock_outline,
                          obscure: _obscure,
                          suffix: IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility_off
                                       : Icons.visibility,
                              color: const Color(0xFF555580),
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          onSubmit: (_) => _login(),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? '비밀번호를 입력하세요' : null,
                        ),
                        const SizedBox(height: 8),

                        // 에러 메시지
                        if (_error.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Color(0xFFEF5350), size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _error,
                                    style: const TextStyle(
                                        color: Color(0xFFEF5350), fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 8),
                        // 로그인 버튼
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6C63FF),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              elevation: 8,
                              shadowColor: const Color(0xFF6C63FF),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 18, width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                                : const Text(
                                    '로그인',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                // ── 힌트 카드 (개발모드) ─────────────────────────────
                if (kDebugMode)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A0D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF3A3A1A)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🔑 개발모드 힌트',
                            style: TextStyle(
                                color: Color(0xFFFFD54F),
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text('ID: admin',
                            style: TextStyle(
                                color: Color(0xFFBBBB88),
                                fontSize: 11,
                                fontFamily: 'monospace')),
                        Text('PW: kra2025!',
                            style: TextStyle(
                                color: Color(0xFFBBBB88),
                                fontSize: 11,
                                fontFamily: 'monospace')),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 공통 입력 필드 위젯 ───────────────────────────────────────────────────
class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmit;

  const _InputField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.validator,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      onFieldSubmitted: onSubmit,
      style: const TextStyle(color: Color(0xFFE0E0FF), fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF7070AA), fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF6C63FF), size: 18),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF12122A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF3A3A6A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF3A3A6A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEF5350)),
        ),
        errorStyle: const TextStyle(color: Color(0xFFEF5350), fontSize: 11),
      ),
      validator: validator,
    );
  }
}
