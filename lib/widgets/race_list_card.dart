import 'package:flutter/material.dart';
import '../models/race_models.dart';
import '../utils/app_theme.dart';

class RaceListCard extends StatefulWidget {
  final RaceInfo race;
  final VoidCallback onEnter;
  final VoidCallback onViewResult;

  const RaceListCard({
    super.key,
    required this.race,
    required this.onEnter,
    required this.onViewResult,
  });

  @override
  State<RaceListCard> createState() => _RaceListCardState();
}

class _RaceListCardState extends State<RaceListCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkCtrl;
  late Animation<double> _blinkAnim;

  @override
  void initState() {
    super.initState();
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _blinkAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _blinkCtrl, curve: Curves.easeInOut),
    );
    if (widget.race.isUpcoming) {
      _blinkCtrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blinkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final race = widget.race;
    final isFinished = race.isFinished;
    final isUpcoming = race.isUpcoming;

    final hasActivateTime = race.activateTime != null;

    return Opacity(
      opacity: isFinished ? 0.50 : 1.0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          gradient: isFinished
              ? null
              : LinearGradient(
                  colors: [
                    AppTheme.navyCard,
                    AppTheme.navyMid,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: isFinished ? AppTheme.navyCard : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUpcoming
                ? AppTheme.goldPrimary.withValues(alpha: 0.8)
                : isFinished
                    ? AppTheme.navyBorder.withValues(alpha: 0.3)
                    : AppTheme.navyBorder,
            width: isUpcoming ? 1.5 : 1,
          ),
          boxShadow: isUpcoming
              ? [
                  BoxShadow(
                    color: AppTheme.goldPrimary.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: isFinished ? null : widget.onEnter,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  // 마감 임박 배지
                  if (isUpcoming) _buildUpcomingBadge(),

                  // 종료 경주 활성화 예정 안내
                  if (isFinished && hasActivateTime)
                    _buildActivateTimeRow(race.activateTime!),

                  Row(
                    children: [
                      // 레이스 번호 원형 배지
                      _buildRaceNumberBadge(race.raceNo, isFinished),
                      const SizedBox(width: 12),

                      // 레이스 정보
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '제${race.raceNo}경주',
                                  style: TextStyle(
                                    color: isFinished
                                        ? AppTheme.textDisable
                                        : AppTheme.textWhite,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // 주로 상태
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _trackColor(race.trackCondition)
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: _trackColor(race.trackCondition)
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Text(
                                    race.trackCondition,
                                    style: TextStyle(
                                      color: _trackColor(race.trackCondition),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.access_time,
                                    size: 12, color: AppTheme.textMuted),
                                const SizedBox(width: 3),
                                Text(
                                  race.startTime,
                                  style: TextStyle(
                                    color: isFinished
                                        ? AppTheme.textDisable
                                        : AppTheme.goldAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(Icons.straighten,
                                    size: 12, color: AppTheme.textMuted),
                                const SizedBox(width: 3),
                                Text(
                                  '${race.distance}m',
                                  style: TextStyle(
                                    color: isFinished
                                        ? AppTheme.textDisable
                                        : AppTheme.textLight,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(Icons.group,
                                    size: 12, color: AppTheme.textMuted),
                                const SizedBox(width: 3),
                                Text(
                                  '${race.totalHorses}두',
                                  style: TextStyle(
                                    color: isFinished
                                        ? AppTheme.textDisable
                                        : AppTheme.textLight,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              race.condition,
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 액션 버튼
                      _buildActionButton(isFinished, race),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 활성화 예정 일시 안내 행
  Widget _buildActivateTimeRow(DateTime activateTime) {
    final mo = activateTime.month.toString().padLeft(2, '0');
    final dd = activateTime.day.toString().padLeft(2, '0');
    final hh = activateTime.hour.toString().padLeft(2, '0');
    final mm = activateTime.minute.toString().padLeft(2, '0');
    final label = '$mo/$dd $hh:$mm 출전마 공지 후 활성화 예정';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppTheme.greenWin.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded,
              size: 11, color: AppTheme.greenWin.withValues(alpha: 0.8)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.greenWin.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingBadge() {
    return AnimatedBuilder(
      animation: _blinkAnim,
      builder: (ctx, _) {
        return Opacity(
          opacity: _blinkAnim.value,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6D00), Color(0xFFFFD700)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🔥', style: TextStyle(fontSize: 12)),
                SizedBox(width: 4),
                Text(
                  '마감 임박',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRaceNumberBadge(String raceNo, bool isFinished) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: isFinished
            ? null
            : const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFB8960C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: isFinished ? AppTheme.navyBorder : null,
        shape: BoxShape.circle,
        boxShadow: isFinished
            ? null
            : [
                BoxShadow(
                  color: AppTheme.goldPrimary.withValues(alpha: 0.3),
                  blurRadius: 8,
                )
              ],
      ),
      child: Center(
        child: Text(
          raceNo,
          style: TextStyle(
            color: isFinished ? AppTheme.textDisable : AppTheme.navyDeep,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(bool isFinished, RaceInfo race) {
    if (isFinished) {
      return GestureDetector(
        onTap: widget.onViewResult,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.navyBorder,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.textDisable),
          ),
          child: Text(
            '결과\n보기',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onEnter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2979FF), Color(0xFF1565C0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2979FF).withValues(alpha: 0.4),
              blurRadius: 10,
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text('🏇', style: TextStyle(fontSize: 16)),
            SizedBox(height: 3),
            Text(
              'AI 모의\n경주 입장',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _trackColor(String condition) {
    switch (condition) {
      case '양호':
        return AppTheme.greenWin;
      case '다습':
        return AppTheme.tealAccent;
      case '불량':
        return AppTheme.redAlert;
      default:
        return AppTheme.textMuted;
    }
  }
}
