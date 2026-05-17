import 'package:flutter/material.dart';

/// 한국마사회 공식 기수 모자 색상 (마번 순서별)
/// 1~10번: 단색
/// 11~16번: 기본색 + 흰색 줄무늬 혼합
class HorseCapColors {
  /// 배경색 + 줄무늬색 정보
  static const List<_CapColorData> _capData = [
    // 1번: 흰색
    _CapColorData(bg: Color(0xFFFFFFFF), text: Color(0xFF1A1A2E), name: '흰색',    stripe: null),
    // 2번: 노란색
    _CapColorData(bg: Color(0xFFFFD600), text: Color(0xFF1A1A2E), name: '노란색',  stripe: null),
    // 3번: 빨간색
    _CapColorData(bg: Color(0xFFE53935), text: Color(0xFFFFFFFF), name: '빨간색',  stripe: null),
    // 4번: 검은색
    _CapColorData(bg: Color(0xFF1A1A1A), text: Color(0xFFFFFFFF), name: '검은색',  stripe: null),
    // 5번: 파란색
    _CapColorData(bg: Color(0xFF1565C0), text: Color(0xFFFFFFFF), name: '파란색',  stripe: null),
    // 6번: 초록색
    _CapColorData(bg: Color(0xFF2E7D32), text: Color(0xFFFFFFFF), name: '초록색',  stripe: null),
    // 7번: 버건디(적갈색)
    _CapColorData(bg: Color(0xFF880E4F), text: Color(0xFFFFFFFF), name: '적갈색',  stripe: null),
    // 8번: 분홍색
    _CapColorData(bg: Color(0xFFF06292), text: Color(0xFFFFFFFF), name: '분홍색',  stripe: null),
    // 9번: 보라색
    _CapColorData(bg: Color(0xFF6A1B9A), text: Color(0xFFFFFFFF), name: '보라색',  stripe: null),
    // 10번: 하늘색
    _CapColorData(bg: Color(0xFF00ACC1), text: Color(0xFFFFFFFF), name: '하늘색',  stripe: null),
    // 11번: 흰색 + 하늘색 줄무늬 (흰 바탕, 하늘색 줄)
    _CapColorData(bg: Color(0xFFFFFFFF), text: Color(0xFF1A1A2E), name: '흰/하늘', stripe: Color(0xFF00ACC1)),
    // 12번: 노란색 + 하늘색 줄무늬
    _CapColorData(bg: Color(0xFFFFD600), text: Color(0xFF1A1A2E), name: '황/하늘', stripe: Color(0xFF00ACC1)),
    // 13번: 빨간색 + 흰색 줄무늬
    _CapColorData(bg: Color(0xFFE53935), text: Color(0xFFFFFFFF), name: '적/흰색', stripe: Color(0xFFFFFFFF)),
    // 14번: 검은색 + 흰색 줄무늬
    _CapColorData(bg: Color(0xFF1A1A1A), text: Color(0xFFFFFFFF), name: '흑/흰색', stripe: Color(0xFFFFFFFF)),
    // 15번: 흰색 + 파란색 줄무늬
    _CapColorData(bg: Color(0xFFFFFFFF), text: Color(0xFF1A1A2E), name: '흰/파랑', stripe: Color(0xFF1565C0)),
    // 16번: 흰색 + 초록색 줄무늬
    _CapColorData(bg: Color(0xFFFFFFFF), text: Color(0xFF1A1A2E), name: '흰/초록', stripe: Color(0xFF2E7D32)),
  ];

  static _CapColorData getCapData(int horseNumber) {
    final idx = ((horseNumber - 1) % _capData.length);
    return _capData[idx];
  }

  static Color getBgColor(int horseNumber) => getCapData(horseNumber).bg;
  static Color getTextColor(int horseNumber) => getCapData(horseNumber).text;
  static Color? getStripeColor(int horseNumber) => getCapData(horseNumber).stripe;
  static String getColorName(int horseNumber) => getCapData(horseNumber).name;
  static bool hasStripe(int horseNumber) => getCapData(horseNumber).stripe != null;
}

// ignore: library_private_types_in_public_api
class _CapColorData {
  final Color bg;
  final Color text;
  final String name;
  final Color? stripe; // null이면 단색

  const _CapColorData({
    required this.bg,
    required this.text,
    required this.name,
    required this.stripe,
  });
}

/// 기수 모자 색상 배지 위젯 (줄무늬 정확 표현)
class HorseCapBadge extends StatelessWidget {
  final int gateNo;
  final double size;
  final bool showNumber;
  final Color? borderColor;
  final double borderWidth;

  const HorseCapBadge({
    super.key,
    required this.gateNo,
    required this.size,
    this.showNumber = true,
    this.borderColor,
    this.borderWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    final data = HorseCapColors.getCapData(gateNo);
    final hasStripe = data.stripe != null;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.4),
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: data.bg.withValues(alpha: 0.5),
            blurRadius: size * 0.25,
          ),
        ],
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: _CapPainter(
            bgColor: data.bg,
            stripeColor: data.stripe,
            hasStripe: hasStripe,
            stripeCount: 6,
          ),
          child: showNumber
              ? Center(
                  child: Text(
                    '$gateNo',
                    style: TextStyle(
                      color: data.text,
                      fontSize: size * 0.38,
                      fontWeight: FontWeight.w900,
                      shadows: hasStripe
                          ? [
                              Shadow(
                                color: data.bg == const Color(0xFFFFFFFF)
                                    ? Colors.black54
                                    : Colors.white54,
                                blurRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// 줄무늬 모자 커스텀 페인터
class _CapPainter extends CustomPainter {
  final Color bgColor;
  final Color? stripeColor;
  final bool hasStripe;
  final int stripeCount;

  _CapPainter({
    required this.bgColor,
    required this.stripeColor,
    required this.hasStripe,
    required this.stripeCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // 배경색 채우기
    paint.color = bgColor;
    canvas.drawRect(Offset.zero & size, paint);

    if (!hasStripe || stripeColor == null) return;

    // 세로 줄무늬 그리기
    paint.color = stripeColor!;
    final stripeWidth = size.width / (stripeCount * 2);
    for (int i = 0; i < stripeCount; i++) {
      final x = (i * 2 + 1) * stripeWidth;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, stripeWidth, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CapPainter oldDelegate) =>
      oldDelegate.bgColor != bgColor ||
      oldDelegate.stripeColor != stripeColor;
}
