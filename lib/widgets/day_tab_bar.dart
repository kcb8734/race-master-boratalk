import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/race_provider.dart';
import '../models/race_models.dart';
import '../utils/app_theme.dart';

/// 상단 요일 탭 바 (API187 스캔 결과로 동적 렌더링)
class DayTabBar extends StatelessWidget {
  const DayTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RaceProvider>(
      builder: (context, provider, _) {
        final days = provider.weekDays;
        if (days.isEmpty) return const SizedBox.shrink();

        return Container(
          color: AppTheme.navyDark,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 라벨
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppTheme.goldPrimary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '이번 주 경주 일정',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  // API 스캔 표시
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.goldDark.withValues(alpha: 0.6)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: AppTheme.greenWin,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'LIVE RACE',
                          style: TextStyle(
                            color: AppTheme.goldAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 요일 탭 가로 바
              Row(
                children: List.generate(days.length, (i) {
                  final isSelected = i == provider.selectedDayIndex;
                  final day = days[i];
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i < days.length - 1 ? 8 : 0),
                      child: _DayTabCard(
                        day: day,
                        isSelected: isSelected,
                        onTap: () => provider.selectDay(i),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DayTabCard extends StatelessWidget {
  final DayTab day;
  final bool isSelected;
  final VoidCallback onTap;

  const _DayTabCard({
    required this.day,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          gradient: isSelected ? AppTheme.goldGradient : null,
          color: isSelected ? null : AppTheme.navyCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.goldPrimary
                : AppTheme.navyBorder,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.goldPrimary.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 0,
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              day.label,
              style: TextStyle(
                color: isSelected ? AppTheme.navyDeep : AppTheme.textLight,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              day.dateStr,
              style: TextStyle(
                color: isSelected
                    ? AppTheme.navyDeep.withValues(alpha: 0.8)
                    : AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Container(
                width: 20,
                height: 2,
                decoration: BoxDecoration(
                  color: AppTheme.navyDeep.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
