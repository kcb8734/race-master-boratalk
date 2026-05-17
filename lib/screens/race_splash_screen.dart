import 'package:flutter/material.dart';
import '../models/race_models.dart';
import '../utils/app_theme.dart';
import '../utils/horse_cap_colors.dart';
import 'race_animation_screen.dart';

/// START 버튼 클릭 → 1.5초 경마장 그래픽 스플래시 → 레이스 애니메이션
class RaceSplashScreen extends StatefulWidget {
  final RaceInfo race;
  final List<HorseEntry> horses;

  const RaceSplashScreen({
    super.key,
    required this.race,
    required this.horses,
  });

  @override
  State<RaceSplashScreen> createState() => _RaceSplashScreenState();
}

class _RaceSplashScreenState extends State<RaceSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late AnimationController _zoomCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _zoomAnim;
  late Animation<double> _overlayAnim;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _zoomCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn),
    );
    _zoomAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _zoomCtrl, curve: Curves.easeInOut),
    );
    _overlayAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _zoomCtrl,
        curve: const Interval(0.7, 1.0, curve: Curves.easeIn),
      ),
    );

    _fadeCtrl.forward();
    _zoomCtrl.forward();

    // 1.5초 후 레이스 화면으로 전환
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (c, a1, a2) => RaceAnimationScreen(
            race: widget.race,
            horses: widget.horses,
          ),
          transitionsBuilder: (c, a1, a2, child) =>
              FadeTransition(opacity: a1, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _zoomCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── 배경: 경마장 그래픽 (애니메이션 줌) ──
            AnimatedBuilder(
              animation: _zoomAnim,
              builder: (_, __) => Transform.scale(
                scale: _zoomAnim.value,
                child: _buildRacetrackGraphic(size),
              ),
            ),

            // ── 페이드 아웃 오버레이 ──
            AnimatedBuilder(
              animation: _overlayAnim,
              builder: (_, __) => Container(
                color: Colors.black.withValues(alpha: _overlayAnim.value * 0.7),
              ),
            ),

            // ── 상단 경주 정보 ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.chevron_left,
                          color: AppTheme.goldPrimary, size: 22),
                      const SizedBox(width: 4),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.race.venueName} 제${widget.race.raceNo}경주 AI 시뮬레이션',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${widget.race.distance}m · ${widget.horses.length}두 출전',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // 타이머 디스플레이
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: _TimerDisplay(
                          targetSeconds: _getRaceTargetSeconds(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── 하단 기수들 색상 배지 ──
            Positioned(
              bottom: 130,
              left: 16,
              right: 16,
              child: _buildJockeyColorRow(),
            ),

            // ── START 버튼 (반투명 / 로딩 표시) ──
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFFD700),
                          Color(0xFFF0C040),
                          Color(0xFFB8960C),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.goldPrimary.withValues(alpha: 0.6),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('🏁', style: TextStyle(fontSize: 28)),
                        SizedBox(width: 12),
                        Text(
                          'AI 모의 레이스  START',
                          style: TextStyle(
                            color: Color(0xFF0A0E1A),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── 중앙 로딩 인디케이터 ──
            Center(
              child: AnimatedBuilder(
                animation: _fadeCtrl,
                builder: (_, __) => Opacity(
                  opacity: _fadeCtrl.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 60),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.goldPrimary.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Text(
                          '🏇  경주 준비 중...',
                          style: TextStyle(
                            color: AppTheme.goldPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 실제 경마장 그래픽 (SVG 스타일 Flutter Canvas)
  Widget _buildRacetrackGraphic(Size size) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE8A040), // 석양 하늘 오렌지
            Color(0xFF6B9EC8), // 하늘
            Color(0xFF4A8B5E), // 잔디
            Color(0xFF3A7A4E), // 잔디 어두운
          ],
          stops: [0.0, 0.35, 0.55, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 관중석 (좌우)
          Positioned(
            top: size.height * 0.15,
            left: 0,
            right: 0,
            height: size.height * 0.2,
            child: CustomPaint(painter: _StandsPainter()),
          ),

          // 경주로 트랙
          Positioned(
            top: size.height * 0.3,
            left: 0,
            right: 0,
            height: size.height * 0.3,
            child: CustomPaint(painter: _TrackBgPainter()),
          ),

          // 결승선 아치 구조물
          Positioned(
            top: size.height * 0.28,
            left: size.width * 0.3,
            right: size.width * 0.3,
            height: size.height * 0.22,
            child: CustomPaint(painter: _FinishArchPainter()),
          ),

          // 전광판
          Positioned(
            top: size.height * 0.18,
            left: size.width * 0.25,
            right: size.width * 0.25,
            height: size.height * 0.14,
            child: _buildScoreboard(),
          ),

          // 경주마들 군집 (하단 중앙)
          Positioned(
            bottom: size.height * 0.2,
            left: size.width * 0.05,
            right: size.width * 0.05,
            height: size.height * 0.22,
            child: _buildHorseCluster(),
          ),

          // 광고 배너들
          Positioned(
            top: size.height * 0.52,
            left: 0,
            right: 0,
            child: _buildAdBanners(size.width),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreboard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade600),
      ),
      child: Column(
        children: [
          Container(
            height: 6,
            color: Colors.yellow.shade700,
          ),
          Expanded(
            child: Center(
              child: Text(
                '${widget.race.venueName} ${widget.race.raceNo}R',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          Container(
            height: 6,
            color: Colors.red.shade700,
          ),
        ],
      ),
    );
  }

  Widget _buildHorseCluster() {
    return Stack(
      fit: StackFit.expand,
      children: List.generate(widget.horses.take(8).length, (i) {
        final horse = widget.horses[i];
        final offsetX = (i % 4) * 0.22 + 0.08;
        final offsetY = (i ~/ 4) * 0.4 + 0.1;
        final scale = 0.85 + (i % 3) * 0.08;

        return Positioned(
          left: offsetX * 300,
          top: offsetY * 120,
          child: Transform.scale(
            scale: scale,
            child: _HorseWithJockey(gateNo: horse.gateNo),
          ),
        );
      }),
    );
  }

  Widget _buildAdBanners(double width) {
    return Row(
      children: [
        _adBanner('🏇 경마통', const Color(0xFF1565C0), width * 0.35),
        _adBanner('Seoul Race Park', const Color(0xFF880E4F), width * 0.3),
        _adBanner('KRA 마사회', const Color(0xFF2E7D32), width * 0.35),
      ],
    );
  }

  Widget _adBanner(String text, Color color, double w) {
    return Container(
      width: w,
      height: 22,
      color: color,
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildJockeyColorRow() {
    final horses = widget.horses.take(8).toList();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: horses.map((h) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          child: HorseCapBadge(
            gateNo: h.gateNo,
            size: 32,
            showNumber: true,
          ),
        );
      }).toList(),
    );
  }

  int _getRaceTargetSeconds() {
    // 거리별 실제 경주 시간 (초) - 여기서는 2배속
    final dist = widget.race.distance;
    if (dist <= 1000) return 62;
    if (dist <= 1200) return 74;
    if (dist <= 1400) return 88;
    if (dist <= 1700) return 108;
    if (dist <= 1800) return 116;
    return 130;
  }
}

// ── 경주마+기수 아이콘 ──
class _HorseWithJockey extends StatelessWidget {
  final int gateNo;
  const _HorseWithJockey({required this.gateNo});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 기수 모자 색상 배지
        HorseCapBadge(gateNo: gateNo, size: 24, showNumber: false),
        const SizedBox(height: 2),
        // 말 아이콘 (텍스트 이모지)
        const Text('🐴', style: TextStyle(fontSize: 22)),
      ],
    );
  }
}

// ── 타이머 위젯 ──
class _TimerDisplay extends StatefulWidget {
  final int targetSeconds;
  const _TimerDisplay({required this.targetSeconds});

  @override
  State<_TimerDisplay> createState() => _TimerDisplayState();
}

class _TimerDisplayState extends State<_TimerDisplay> {
  double _elapsed = 0.0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return false;
      setState(() {
        _elapsed += 0.1; // 2배속
      });
      return _elapsed < widget.targetSeconds;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mins = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final secs = (_elapsed % 60).toInt().toString().padLeft(2, '0');
    final tenths = ((_elapsed * 10) % 10).toInt().toString();

    return Text(
      'TIME:  $mins:$secs.$tenths',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w800,
        fontFamily: 'monospace',
        letterSpacing: 1,
      ),
    );
  }
}

// ── 페인터들 ──
class _StandsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    // 관중석 배경
    paint.color = const Color(0xFF8B7355);
    canvas.drawRect(Offset.zero & size, paint);

    // 관중석 구획선
    paint.color = const Color(0xFF6B5335);
    paint.strokeWidth = 1;
    paint.style = PaintingStyle.stroke;
    for (int i = 0; i < 8; i++) {
      final y = size.height * i / 8;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // 군중 점들
    paint.style = PaintingStyle.fill;
    final colors = [
      const Color(0xFFE0E0E0), const Color(0xFF90CAF9),
      const Color(0xFFEF9A9A), const Color(0xFFA5D6A7),
    ];
    for (int row = 0; row < 5; row++) {
      for (int col = 0; col < 30; col++) {
        paint.color = colors[(row + col) % colors.length];
        canvas.drawCircle(
          Offset(
            col * size.width / 30 + size.width / 60,
            row * size.height / 5 + size.height / 10,
          ),
          3,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _TrackBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    // 흙 트랙
    paint.color = const Color(0xFFB5895A);
    canvas.drawRect(Offset.zero & size, paint);

    // 레인 라인
    paint.color = const Color(0xFF8B6235);
    paint.strokeWidth = 2;
    paint.style = PaintingStyle.stroke;
    for (int i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _FinishArchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // 아치 기둥 (좌)
    paint.color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.1, 0, 8, size.height), paint);

    // 아치 기둥 (우)
    canvas.drawRect(
        Rect.fromLTWH(size.width * 0.9 - 8, 0, 8, size.height), paint);

    // 가로 바
    canvas.drawRect(
        Rect.fromLTWH(size.width * 0.1, size.height * 0.2,
            size.width * 0.8, 10),
        paint);

    // 체크 패턴
    paint.color = Colors.red;
    for (int i = 0; i < 6; i++) {
      if (i.isEven) {
        canvas.drawRect(
          Rect.fromLTWH(
            size.width * 0.1 + i * size.width * 0.8 / 6,
            size.height * 0.2,
            size.width * 0.8 / 6,
            10,
          ),
          paint,
        );
      }
    }

    // FINISH 텍스트
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'FINISH',
        style: TextStyle(
          color: Colors.yellow,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        size.height * 0.05,
      ),
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
