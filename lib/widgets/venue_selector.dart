import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/race_provider.dart';
import '../models/race_models.dart';
import '../utils/app_theme.dart';

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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on, color: AppTheme.goldPrimary, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '경주장 선택',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: VenueCode.values.map((venue) {
                  final isSelected = provider.selectedVenue == venue;
                  final isActive = VenueScheduleRule.isVenueActive(weekday, venue.code);
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: venue != VenueCode.jeju ? 10 : 0,
                      ),
                      child: _VenueCard(
                        venue: venue,
                        isSelected: isSelected,
                        isActive: isActive,
                        weekday: weekday,
                        onTap: () {
                          if (isActive) {
                            provider.selectVenue(venue);
                          } else {
                            // 비활성 경주장 탭 시 안내 스낵바
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Text('⛔', style: TextStyle(fontSize: 16)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        VenueScheduleRule.inactiveReason(
                                            weekday, venue),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: const Color(0xFF1A2A3A),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(
                                      color: Color(0xFFFF3B30), width: 1),
                                ),
                                duration: const Duration(seconds: 3),
                                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              ),
                            );
                          }
                        },
                      ),
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
}

class _VenueCard extends StatelessWidget {
  final VenueCode venue;
  final bool isSelected;
  final bool isActive;
  final int weekday;
  final VoidCallback onTap;

  const _VenueCard({
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          gradient: (isSelected && isActive)
              ? LinearGradient(
                  colors: [
                    _accentColor.withValues(alpha: 0.35),
                    AppTheme.navyCard,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: (isSelected && isActive) ? null : AppTheme.navyCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? (isSelected ? _accentColor : AppTheme.navyBorder)
                : const Color(0xFF2A3A4A),
            width: (isSelected && isActive) ? 2 : 1,
          ),
          boxShadow: (isSelected && isActive)
              ? [
                  BoxShadow(
                    color: _accentColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 0,
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 비활성 아이콘 오버레이
            if (!isActive)
              const Text('⛔', style: TextStyle(fontSize: 10)),
            if (!isActive) const SizedBox(height: 2),
            Text(
              venue.label,
              style: TextStyle(
                color: isActive
                    ? (isSelected ? Colors.white : AppTheme.textLight)
                    : const Color(0xFF3A4A5A),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                decoration: isActive ? null : TextDecoration.lineThrough,
                decorationColor: const Color(0xFF3A4A5A),
              ),
            ),
            // 활성 경주장: 선택된 경우 하단 바
            if (isSelected && isActive) ...[
              const SizedBox(height: 4),
              Container(
                width: 32,
                height: 2,
                decoration: BoxDecoration(
                  color: _accentColor,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
            // 비활성 경주장: 'OFF' 배지
            if (!isActive) ...[
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3A4A),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF3A4A5A)),
                ),
                child: const Text(
                  'OFF',
                  style: TextStyle(
                    color: Color(0xFF4A5A6A),
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
