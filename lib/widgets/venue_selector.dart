import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/race_provider.dart';
import '../models/race_models.dart';
import '../utils/app_theme.dart';

// ──────────────────────────────────────────────────────────────────────
// VenueSelector — 경주장 탭바 (서울 / 부산경남 / 제주)
//
// ● 기존 카드 버튼 → 컴팩트 탭바로 변경: 세로 패딩 최소화, 경주 카드 공간 확보
// ● 비활성 경주장 탭 → SnackBar 대신 하단 모달(BottomSheet) 안내로 변경
//   → 텍스트 색상·대비 개선, 가독성 향상
// ● 각 탭: 경주장명 + 선택 인디케이터 밑줄 + OFF 뱃지
// ──────────────────────────────────────────────────────────────────────
class VenueSelector extends StatelessWidget {
  const VenueSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RaceProvider>(
      builder: (context, provider, _) {
        final day = provider.selectedDay;
        final weekday = day?.date.weekday ?? DateTime.now().weekday;

        return Container(
          color: AppTheme.navyDeep,
          // ── 컴팩트: 세로 패딩 줄여서 카드 영역 확보 ──
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 경주장 레이블 ──────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: AppTheme.goldPrimary, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      '경주장 선택',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              // ── 탭바 행 ────────────────────────────────────
              Row(
                children: VenueCode.values.map((venue) {
                  final isSelected = provider.selectedVenue == venue;
                  final isActive =
                      VenueScheduleRule.isVenueActive(weekday, venue.code);

                  return Expanded(
                    child: _VenueTab(
                      venue: venue,
                      isSelected: isSelected,
                      isActive: isActive,
                      weekday: weekday,
                      onTap: () {
                        if (isActive) {
                          provider.selectVenue(venue);
                        } else {
                          _showInactiveSheet(context, weekday, venue);
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 비활성 경주장: 모달 바텀시트 안내 ─────────────────────────────
  void _showInactiveSheet(
      BuildContext context, int weekday, VenueCode venue) {
    final reason = VenueScheduleRule.inactiveReason(weekday, venue);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => _InactiveVenueSheet(
        venue: venue,
        reason: reason,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// _VenueTab — 개별 탭 위젯
// ──────────────────────────────────────────────────────────────────────
class _VenueTab extends StatelessWidget {
  final VenueCode venue;
  final bool isSelected;
  final bool isActive;
  final int weekday;
  final VoidCallback onTap;

  const _VenueTab({
    required this.venue,
    required this.isSelected,
    required this.isActive,
    required this.weekday,
    required this.onTap,
  });

  Color get _accentColor {
    if (!isActive) return const Color(0xFF3A4A5A);
    switch (venue) {
      case VenueCode.seoul:
        return const Color(0xFF2979FF);
      case VenueCode.busan:
        return const Color(0xFFFF6D00);
      case VenueCode.jeju:
        return const Color(0xFF00BFA5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: (isSelected && isActive)
              ? _accentColor.withValues(alpha: 0.10)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: (isSelected && isActive)
                  ? _accentColor
                  : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 비활성 아이콘 ──
            if (!isActive) ...[
              const Icon(Icons.block_rounded,
                  color: Color(0xFF4A5A6A), size: 12),
              const SizedBox(height: 2),
            ],

            // ── 경주장명 ──
            Text(
              venue.label,
              style: TextStyle(
                color: isActive
                    ? (isSelected ? Colors.white : AppTheme.textLight)
                    : const Color(0xFF4A5A6A),
                fontSize: 14,
                fontWeight: isSelected && isActive
                    ? FontWeight.w900
                    : FontWeight.w600,
                letterSpacing: 0.3,
                decoration: isActive ? null : TextDecoration.lineThrough,
                decorationColor: const Color(0xFF4A5A6A),
              ),
            ),

            // ── OFF 뱃지 (비활성) ──
            if (!isActive) ...[
              const SizedBox(height: 2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3A4A),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFF3A4A5A)),
                ),
                child: const Text(
                  'OFF',
                  style: TextStyle(
                    color: Color(0xFF6A7A8A),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// _InactiveVenueSheet — 비활성 경주장 안내 모달 (가독성 개선)
// ──────────────────────────────────────────────────────────────────────
class _InactiveVenueSheet extends StatelessWidget {
  final VenueCode venue;
  final String reason;

  const _InactiveVenueSheet({
    required this.venue,
    required this.reason,
  });

  Color get _venueColor {
    switch (venue) {
      case VenueCode.seoul:
        return const Color(0xFF2979FF);
      case VenueCode.busan:
        return const Color(0xFFFF6D00);
      case VenueCode.jeju:
        return const Color(0xFF00BFA5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1F35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFF3B30).withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 헤더 ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30).withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.25),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFF3B30).withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Icon(
                    Icons.block_rounded,
                    color: Color(0xFFFF6B6B),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _venueColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _venueColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              venue.label,
                              style: TextStyle(
                                color: _venueColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '경주 없음',
                            style: TextStyle(
                              // ★ 가독성: 밝은 흰색 텍스트
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFFB0BEC5),
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 안내 메시지 ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFFFFB74D),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    reason,
                    style: const TextStyle(
                      // ★ 가독성: 밝고 선명한 텍스트
                      color: Color(0xFFECEFF1),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 서브 안내 ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: Color(0xFF90A4AE),
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '활성화된 다른 경주장을 선택하시거나\n해당 경주장 운영일에 다시 접속해 주세요.',
                    style: TextStyle(
                      // ★ 서브텍스트도 충분히 밝게
                      color: Colors.white.withValues(alpha: 0.70),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          Divider(
            color: Colors.white.withValues(alpha: 0.08),
            thickness: 1,
            indent: 20,
            endIndent: 20,
          ),

          // ── 확인 버튼 ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A3A5A), Color(0xFF0D2040)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF2A5A8A).withValues(alpha: 0.6),
                    ),
                  ),
                  child: const Text(
                    '확인',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF90CAF9),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
