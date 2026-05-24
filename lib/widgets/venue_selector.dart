import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/race_provider.dart';
import '../models/race_models.dart';
import '../utils/app_theme.dart';

// ──────────────────────────────────────────────────────────────────────
// VenueSelector — 경주장 필터 (전체 + 개별 체크박스 탭)
//
// 마사회 공식 앱 레이아웃 참조:
//   [✓ 전체]  [✓ 서울]  [✓ 부산경남]  [✓ 제주]
//
// ● 전체 탭: 활성 경주장 모두 병렬 로딩 → 시간순 병합 목록
// ● 개별 탭: 기존 단일 경주장 선택
// ● 비활성 경주장: 회색 + OFF 배지 (탭 → 바텀시트 안내)
// ● 컴팩트 높이: 세로 공간 최소화로 경주 카드 영역 확보
// ──────────────────────────────────────────────────────────────────────
class VenueSelector extends StatelessWidget {
  const VenueSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RaceProvider>(
      builder: (context, provider, _) {
        final day = provider.selectedDay;
        final weekday = day?.date.weekday ?? DateTime.now().weekday;
        final isAll = provider.isAllVenuesMode;

        return Container(
          color: AppTheme.navyDeep,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              // ── 전체 탭 ─────────────────────────────────────
              _VenueFilterChip(
                label: '전체',
                isSelected: isAll,
                isActive: true,
                accentColor: const Color(0xFFFFD700),
                onTap: () async {
                  if (!isAll) {
                    await provider.selectAllVenues();
                  }
                },
              ),
              const SizedBox(width: 6),

              // ── 개별 경주장 탭 ────────────────────────────────
              ...VenueCode.values.map((venue) {
                final isSelected =
                    !isAll && provider.selectedVenue == venue;
                final isActive =
                    VenueScheduleRule.isVenueActive(weekday, venue.code);

                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _VenueFilterChip(
                    label: _shortLabel(venue),
                    isSelected: isSelected,
                    isActive: isActive,
                    accentColor: _accentColor(venue),
                    onTap: () {
                      if (isActive) {
                        provider.selectVenue(venue);
                      } else {
                        _showInactiveSheet(context, weekday, venue);
                      }
                    },
                  ),
                );
              }),

              // ── 로딩 스피너 (전체보기 로딩 중) ─────────────────
              if (provider.isLoadingAllVenues) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFFFD700),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // 짧은 레이블
  String _shortLabel(VenueCode v) {
    switch (v) {
      case VenueCode.seoul:
        return '서울';
      case VenueCode.busan:
        return '부경';
      case VenueCode.jeju:
        return '제주';
    }
  }

  Color _accentColor(VenueCode v) {
    switch (v) {
      case VenueCode.seoul:
        return const Color(0xFF2979FF);
      case VenueCode.busan:
        return const Color(0xFFFF6D00);
      case VenueCode.jeju:
        return const Color(0xFF00BFA5);
    }
  }

  void _showInactiveSheet(
      BuildContext context, int weekday, VenueCode venue) {
    final reason = VenueScheduleRule.inactiveReason(weekday, venue);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => _InactiveVenueSheet(venue: venue, reason: reason),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// _VenueFilterChip — 체크박스 스타일 개별 필터 칩
// ──────────────────────────────────────────────────────────────────────
class _VenueFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isActive;
  final Color accentColor;
  final VoidCallback onTap;

  const _VenueFilterChip({
    required this.label,
    required this.isSelected,
    required this.isActive,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isActive ? accentColor : const Color(0xFF3A4A5A);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? effectiveColor.withValues(alpha: 0.15)
              : AppTheme.navyCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? effectiveColor
                : (isActive
                    ? const Color(0xFF2A3A4A)
                    : const Color(0xFF232F3A)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 체크박스 아이콘 ──
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isSelected
                  ? Icon(
                      Icons.check_box_rounded,
                      key: const ValueKey('checked'),
                      color: effectiveColor,
                      size: 14,
                    )
                  : Icon(
                      isActive
                          ? Icons.check_box_outline_blank_rounded
                          : Icons.block_rounded,
                      key: const ValueKey('unchecked'),
                      color: isActive
                          ? const Color(0xFF5A7A9A)
                          : const Color(0xFF3A4A5A),
                      size: 14,
                    ),
            ),
            const SizedBox(width: 5),

            // ── 레이블 ──
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? (isSelected ? Colors.white : AppTheme.textLight)
                    : const Color(0xFF4A5A6A),
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.w800 : FontWeight.w600,
                decoration: isActive ? null : TextDecoration.lineThrough,
                decorationColor: const Color(0xFF4A5A6A),
              ),
            ),

            // ── OFF 뱃지 ──
            if (!isActive) ...[
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3A4A),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'OFF',
                  style: TextStyle(
                    color: Color(0xFF5A6A7A),
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
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

  const _InactiveVenueSheet({required this.venue, required this.reason});

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
          // ── 헤더 ──────────────────────────────────────────────
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
                  child: const Icon(Icons.block_rounded,
                      color: Color(0xFFFF6B6B), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _venueColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: _venueColor.withValues(alpha: 0.4)),
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
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
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
                    child: const Icon(Icons.close_rounded,
                        color: Color(0xFFB0BEC5), size: 16),
                  ),
                ),
              ],
            ),
          ),

          // ── 안내 메시지 ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: Color(0xFFFFB74D), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    reason,
                    style: const TextStyle(
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

          // ── 서브 안내 ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    color: Color(0xFF90A4AE), size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '전체 탭을 선택하시면 운영 중인\n경주장의 모든 경주를 확인할 수 있습니다.',
                    style: TextStyle(
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
              endIndent: 20),

          // ── 확인 버튼 ──────────────────────────────────────────
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
                      color:
                          const Color(0xFF2A5A8A).withValues(alpha: 0.6),
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
