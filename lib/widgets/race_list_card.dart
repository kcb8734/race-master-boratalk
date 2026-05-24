import 'package:flutter/material.dart';
import '../models/race_models.dart';
import '../utils/app_theme.dart';

class RaceListCard extends StatefulWidget {
  final RaceInfo race;
  /// 'AI 모의 경주 입장' 버튼 탭 콜백 — 시간 경과 시 null
  final VoidCallback? onEnter;
  /// 카드 전체 탭(상세페이지 이동) 콜백 — 항상 활성
  final VoidCallback onDetail;
  final VoidCallback onViewResult;

  const RaceListCard({
    super.key,
    required this.race,
    required this.onEnter,
    required this.onDetail,
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

  /// 경주 시작 시간이 현재 시간보다 30분 이상 지났는지 (AI 모의 경주 입장 비활성 판정)
  bool get _isRacePast {
    final race = widget.race;
    if (race.isFinished) return true;
    // startTime 파싱 ("HH:MM" 형식)
    final parts = race.startTime.split(':');
    if (parts.length != 2) return false;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return false;
    final now = DateTime.now();
    final raceTime = DateTime(now.year, now.month, now.day, h, m);
    return now.isAfter(raceTime.add(const Duration(minutes: 30)));
  }

  /// 다음 주 해당 요일 안내 문자열
  String _nextActiveLabel() {
    final now = DateTime.now();
    // 다음 주 해당 요일
    final race = widget.race;
    final raceDateStr = race.raceDate; // YYYYMMDD
    if (raceDateStr.length == 8) {
      final year   = int.tryParse(raceDateStr.substring(0, 4)) ?? now.year;
      final month  = int.tryParse(raceDateStr.substring(4, 6)) ?? now.month;
      final day    = int.tryParse(raceDateStr.substring(6, 8)) ?? now.day;
      final raceDate = DateTime(year, month, day);
      final nextSame = raceDate.add(const Duration(days: 7));
      final m = nextSame.month.toString().padLeft(2, '0');
      final d = nextSame.day.toString().padLeft(2, '0');
      const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
      final dn = dayNames[nextSame.weekday - 1];
      return '다음 주 $m/$d($dn) ${race.startTime} 활성화 예정';
    }
    return '다음 주 동일 시간 활성화 예정';
  }

  @override
  Widget build(BuildContext context) {
    final race      = widget.race;
    final isFinished = race.isFinished;
    final isUpcoming = race.isUpcoming;
    final isPast     = _isRacePast;   // 경주 시간 경과 여부

    final hasActivateTime = race.activateTime != null;

    return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          // isFinished: 짙은 그린 배경 + 그린 테두리로 '결과 확인 가능' 표시
          gradient: isFinished
              ? const LinearGradient(
                  colors: [Color(0xFF0D1B12), Color(0xFF081410)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [
                    AppTheme.navyCard,
                    AppTheme.navyMid,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUpcoming
                ? AppTheme.goldPrimary.withValues(alpha: 0.8)
                : isFinished
                    ? const Color(0xFF2E7D52).withValues(alpha: 0.6)
                    : AppTheme.navyBorder,
            width: isUpcoming ? 1.5 : (isFinished ? 1.2 : 1),
          ),
          boxShadow: isUpcoming
              ? [
                  BoxShadow(
                    color: AppTheme.goldPrimary.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: 2,
                  )
                ]
              : isFinished
                  ? [
                      BoxShadow(
                        color: const Color(0xFF2E7D52).withValues(alpha: 0.1),
                        blurRadius: 10,
                        spreadRadius: 0,
                      )
                    ]
                  : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            // 카드 전체 탭 → 상세페이지 이동 (종료 경주 포함 항상 허용)
            onTap: widget.onDetail,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  // 마감 임박 배지
                  if (isUpcoming) _buildUpcomingBadge(),

                  // 경주 종료 후 다음 활성화 예정 안내
                  if (isPast && !isFinished) _buildNextActiveBanner(),

                  // 종료 경주: 분석 데이터 확인 가능 안내 배너
                  if (isFinished) _buildFinishedDataBanner(),

                  // 종료 경주 활성화 예정 안내
                  if (isFinished && hasActivateTime)
                    _buildActivateTimeRow(race.activateTime!),

                  Row(
                    children: [
                      // 레이스 번호 원형 배지 (황금색)
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
                                    // isFinished여도 읽기 가능한 밝기 유지
                                    color: isFinished
                                        ? const Color(0xFF8ABFA8)
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
                                        ? const Color(0xFF6A9A88)
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
                                        ? const Color(0xFF5A8A78)
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
                                        ? const Color(0xFF5A8A78)
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
                      _buildActionButton(isFinished, isPast, race),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  // ── 종료 경주: 분석 데이터 확인 가능 안내 배너 ──────────────────
  Widget _buildFinishedDataBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2018),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFF2E7D52).withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D52).withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '경주 종료',
              style: TextStyle(
                color: Color(0xFF4CAF7D),
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Flexible(
            child: Text(
              'AI 분석 데이터 확인 가능 · 탭하여 상세보기',
              style: TextStyle(
                color: Color(0xFF6DBF99),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 경주 시간 지남 → 다음 활성화 안내 배너
  Widget _buildNextActiveBanner() {
    final label = _nextActiveLabel();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFF5A5A8A).withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🏁', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: const Color(0xFF8A8AB8).withValues(alpha: 0.9),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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

  // ★ 원형 배지 — 종료 경주는 그린 계열, 진행 경주는 골드 계열
  Widget _buildRaceNumberBadge(String raceNo, bool isFinished) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: isFinished
            ? const LinearGradient(
                colors: [Color(0xFF2E7D52), Color(0xFF1B4D35)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFD4AF37), Color(0xFF8B6914)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (isFinished
                    ? const Color(0xFF2E7D52)
                    : const Color(0xFFD4AF37))
                .withValues(alpha: 0.35),
            blurRadius: 8,
          )
        ],
      ),
      child: Center(
        child: Text(
          raceNo,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(bool isFinished, bool isPast, RaceInfo race) {
    // ── 경주 완전 종료 → 결과 보기 버튼 (강조 디자인) ──────────────
    if (isFinished) {
      return GestureDetector(
        onTap: widget.onViewResult,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A3A2A), Color(0xFF0D2018)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF2E7D52),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E7D52).withValues(alpha: 0.25),
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFF4CAF7D),
                size: 16,
              ),
              const SizedBox(height: 3),
              const Text(
                '결과\n보기',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF81D4A8),
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

    // 경주 시간 경과 → AI 모의 경주 비활성 버튼 (탭 효과 없음)
    if (isPast) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF3A3A5A).withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🏁', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 3),
            Text(
              'AI 모의\n경주 종료',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF5A5A8A).withValues(alpha: 0.8),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
        ),
      );
    }

    // 정상 활성 버튼
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
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
