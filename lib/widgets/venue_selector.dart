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
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: venue != VenueCode.jeju ? 10 : 0,
                      ),
                      child: _VenueCard(
                        venue: venue,
                        isSelected: isSelected,
                        onTap: () => provider.selectVenue(venue),
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
  final VoidCallback onTap;

  const _VenueCard({
    required this.venue,
    required this.isSelected,
    required this.onTap,
  });

  Color get _accentColor {
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
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    _accentColor.withValues(alpha: 0.35),
                    AppTheme.navyCard,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : AppTheme.navyCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _accentColor : AppTheme.navyBorder,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
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
            Text(
              venue.label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textLight,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            if (isSelected) ...[
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
          ],
        ),
      ),
    );
  }
}
