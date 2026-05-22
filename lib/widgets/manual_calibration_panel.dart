// ============================================================
//  manual_calibration_panel.dart
//  경마통 Race Master — 수동 변수 보정 패널 UI
//
//  【저작권 등록 대상 UI 레이아웃 명세】
//  컴포넌트 트리:
//
//  ManualCalibrationPanel (StatelessWidget)
//  └─ _PanelScaffold (Container + Column)
//     ├─ _PanelHeader            → 패널 제목 + 활성 보정수 배지 + 전체초기화
//     ├─ _HorseCalibTile (×N)    → 마번별 보정 행 (gateNo당 1개)
//     │  ├─ _GateNoChip          → 마번 번호 + 색상 칩
//     │  ├─ CalibrationOddsField → 배당률 가중치 입력창 (TextFormField)
//     │  ├─ CalibrationJockeySlider → 기수 멘탈 슬라이더 (Slider)
//     │  └─ CalibrationSpurtDropdown → 스퍼트 시점 드롭다운 (DropdownButton)
//     └─ _PanelFooter            → 적용 확인 버튼 + 마지막 업데이트 시각
//
//  데이터 바인딩 트리:
//    UserCalibrationController (ChangeNotifier)
//      ├─ setOddsWeight(gateNo, value) ← CalibrationOddsField.onChanged
//      ├─ setJockeyBuff(gateNo, value) ← CalibrationJockeySlider.onChanged
//      └─ setSpurtTiming(gateNo, slot) ← CalibrationSpurtDropdown.onChanged
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/user_calibration_controller.dart';
import '../models/user_calibration_model.dart';
import '../models/race_models.dart';

// ── 디자인 상수 ────────────────────────────────────────────────
const _kPanelBg       = Color(0xFF0E1E3A);
const _kCardBg        = Color(0xFF0A1628);
const _kAccent        = Color(0xFFFFD700);
const _kAccentDim     = Color(0x33FFD700);
const _kTextPrimary   = Color(0xFFE0E8FF);
const _kTextSecondary = Color(0xFF7B8BB2);
const _kNegative      = Color(0xFFEF5350);
const _kPositive      = Color(0xFF66BB6A);

// ──────────────────────────────────────────────────────────────
//  ManualCalibrationPanel — 메인 진입 위젯
//  배당률 테이블 옆에 배치되는 수동 보정 패널
//
//  사용 예:
//    ManualCalibrationPanel(entries: entries)
//
//  ChangeNotifierProvider는 상위 위젯(RaceInfoScreen)에서 주입:
//    ChangeNotifierProvider(
//      create: (_) => UserCalibrationController(gateNos: gateNos),
//      child: ManualCalibrationPanel(entries: entries),
//    )
// ──────────────────────────────────────────────────────────────
class ManualCalibrationPanel extends StatelessWidget {
  final List<HorseEntry> entries;

  const ManualCalibrationPanel({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        _kPanelBg,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: _kAccentDim, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ① 패널 헤더
          const _PanelHeader(),
          const Divider(color: Color(0x22FFFFFF), height: 1),

          // ② 마번별 보정 타일 목록
          ...entries.map((e) => _HorseCalibTile(entry: e)),

          // ③ 푸터 (적용 확인 + 타임스탬프)
          const _PanelFooter(),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  _PanelHeader — 패널 제목 + 활성 보정 카운트 배지 + 전체 초기화 버튼
// ──────────────────────────────────────────────────────────────
class _PanelHeader extends StatelessWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<UserCalibrationController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, color: _kAccent, size: 20),
          const SizedBox(width: 8),
          const Text(
            '수동 변수 보정 패널',
            style: TextStyle(
              color:      _kTextPrimary,
              fontSize:   14,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 8),
          // 활성 보정 수 배지
          if (ctrl.modifiedCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color:        _kAccent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${ctrl.modifiedCount}마 보정중',
                style: const TextStyle(
                  color: Color(0xFF1A0E00),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          const Spacer(),
          // 전체 초기화 버튼
          if (ctrl.panelEnabled && ctrl.modifiedCount > 0)
            GestureDetector(
              onTap: () => ctrl.resetAll(),
              child: const Text(
                '전체 초기화',
                style: TextStyle(
                  color:     _kTextSecondary,
                  fontSize:  11,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          if (!ctrl.panelEnabled)
            const Text(
              '경주 중 잠금',
              style: TextStyle(color: _kNegative, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  _HorseCalibTile — 마번 1개 전체 보정 행
//  [마번칩] [배당률입력] [기수슬라이더] [스퍼트드롭다운] [초기화]
// ──────────────────────────────────────────────────────────────
class _HorseCalibTile extends StatelessWidget {
  final HorseEntry entry;
  const _HorseCalibTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final ctrl  = context.watch<UserCalibrationController>();
    final calib = ctrl.calibrationFor(entry.gateNo);
    final isLocked = !ctrl.panelEnabled;

    return Container(
      margin:  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        calib.isDefault ? _kCardBg : const Color(0xFF111E38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: calib.isDefault
              ? const Color(0x15FFFFFF)
              : _kAccent.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 행: 마번칩 + 말이름 + 배당률 표시 + 초기화 아이콘
          Row(
            children: [
              _GateNoChip(gateNo: entry.gateNo),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.horseName,
                      style: const TextStyle(
                        color:      _kTextPrimary,
                        fontSize:   13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '배당 ${entry.odds.toStringAsFixed(1)}배 · ${entry.jockeyName}',
                      style: const TextStyle(
                        color:    _kTextSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (!calib.isDefault && !isLocked)
                GestureDetector(
                  onTap: () => ctrl.resetGate(entry.gateNo),
                  child: const Icon(
                    Icons.refresh_rounded,
                    color: _kTextSecondary,
                    size: 16,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // ① 배당률 가중치 입력창
          CalibrationOddsField(
            gateNo:  entry.gateNo,
            initial: calib.userOddsWeight,
            enabled: !isLocked,
          ),
          const SizedBox(height: 8),

          // ② 기수 멘탈 보정 슬라이더
          CalibrationJockeySlider(
            gateNo:  entry.gateNo,
            initial: calib.userJockeyBuff,
            enabled: !isLocked,
          ),
          const SizedBox(height: 8),

          // ③ 스퍼트 시점 드롭다운
          CalibrationSpurtDropdown(
            gateNo:  entry.gateNo,
            current: calib.spurtTiming,
            enabled: !isLocked,
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  _GateNoChip — 마번 번호 칩 (색상 순환)
// ──────────────────────────────────────────────────────────────
class _GateNoChip extends StatelessWidget {
  final int gateNo;
  const _GateNoChip({required this.gateNo});

  static const _colors = [
    Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFF43A047),
    Color(0xFFFB8C00), Color(0xFF8E24AA), Color(0xFF00ACC1),
    Color(0xFFD81B60), Color(0xFF6D4C41), Color(0xFF546E7A),
    Color(0xFFFFD700),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colors[(gateNo - 1) % _colors.length];
    return Container(
      width: 30, height: 30,
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.20),
        border:       Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        '$gateNo',
        style: TextStyle(
          color:      color,
          fontSize:   13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  CalibrationOddsField — 배당률 가중치 입력창
//
//  【UI 컴포넌트 명세】
//  - 위젯 타입: TextFormField (숫자 키보드)
//  - 입력 범위: -2.0 ~ +2.0 (소수점 1자리)
//  - 데이터 바인딩: onChanged → ctrl.setOddsWeight(gateNo, value)
//  - 실시간 색상: 양수=초록, 음수=빨강, 0=기본
//  - 물리 엔진 반영 경로:
//      userOddsWeight → oddsAdjFactor(gateNo) → baseSpeed ×= 0.97~1.03
// ──────────────────────────────────────────────────────────────
class CalibrationOddsField extends StatefulWidget {
  final int    gateNo;
  final double initial;
  final bool   enabled;

  const CalibrationOddsField({
    super.key,
    required this.gateNo,
    required this.initial,
    required this.enabled,
  });

  @override
  State<CalibrationOddsField> createState() => _CalibrationOddsFieldState();
}

class _CalibrationOddsFieldState extends State<CalibrationOddsField> {
  late final TextEditingController _textCtrl;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(
      text: widget.initial == 0.0 ? '' : widget.initial.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(CalibrationOddsField old) {
    super.didUpdateWidget(old);
    if (!_hasFocus && old.initial != widget.initial) {
      _textCtrl.text = widget.initial == 0.0
          ? ''
          : widget.initial.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _onSubmit(String raw, UserCalibrationController ctrl) {
    final v = double.tryParse(raw);
    if (v == null) {
      ctrl.setOddsWeight(widget.gateNo, 0.0);
      _textCtrl.text = '';
    } else {
      final clamped = v.clamp(kOddsWeightMin, kOddsWeightMax);
      ctrl.setOddsWeight(widget.gateNo, clamped);
      _textCtrl.text = clamped == 0.0 ? '' : clamped.toStringAsFixed(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl    = context.read<UserCalibrationController>();
    final calib   = context.watch<UserCalibrationController>()
                           .calibrationFor(widget.gateNo);
    final val     = calib.userOddsWeight;
    final valColor = val > 0 ? _kPositive : val < 0 ? _kNegative : _kTextSecondary;

    return Row(
      children: [
        const SizedBox(
          width: 80,
          child: Text(
            '배당 가중치',
            style: TextStyle(color: _kTextSecondary, fontSize: 11),
          ),
        ),
        Expanded(
          child: Focus(
            onFocusChange: (f) => setState(() => _hasFocus = f),
            child: TextFormField(
              controller: _textCtrl,
              enabled:    widget.enabled,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'^-?\d{0,1}\.?\d{0,1}$')),
              ],
              style: TextStyle(
                color:      valColor,
                fontSize:   13,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText:        '0.0',
                hintStyle:       const TextStyle(color: Color(0x44FFFFFF), fontSize: 12),
                suffixText:      val != 0.0
                    ? (val > 0 ? '+${val.toStringAsFixed(1)}' : val.toStringAsFixed(1))
                    : null,
                suffixStyle:     TextStyle(color: valColor, fontSize: 11),
                isDense:         true,
                contentPadding:  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled:          true,
                fillColor:       const Color(0x18FFFFFF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kAccent, width: 1),
                ),
              ),
              onChanged: (v) {
                final parsed = double.tryParse(v);
                if (parsed != null) ctrl.setOddsWeight(widget.gateNo, parsed);
              },
              onFieldSubmitted: (v) => _onSubmit(v, ctrl),
              onEditingComplete: () {
                _onSubmit(_textCtrl.text, ctrl);
                FocusScope.of(context).unfocus();
              },
            ),
          ),
        ),
        const SizedBox(width: 6),
        // 범위 표시
        Text(
          '±2.0',
          style: TextStyle(
            color:    _kTextSecondary.withValues(alpha: 0.5),
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  CalibrationJockeySlider — 기수 멘탈 보정 슬라이더
//
//  【UI 컴포넌트 명세】
//  - 위젯 타입: Slider (-1.0 ~ +1.0, divisions: 20)
//  - 데이터 바인딩: onChanged → ctrl.setJockeyBuff(gateNo, value)
//  - 왼쪽 레이블: 패널티(-) / 오른쪽 레이블: 버프(+)
//  - 물리 엔진 반영 경로:
//      userJockeyBuff → speedMultOverride(gateNo, afScale)
//      → Zone4 speedMult ×= 1.0 ± kJockeyBuffMaxDelta×afScale
// ──────────────────────────────────────────────────────────────
class CalibrationJockeySlider extends StatelessWidget {
  final int    gateNo;
  final double initial;
  final bool   enabled;

  const CalibrationJockeySlider({
    super.key,
    required this.gateNo,
    required this.initial,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl  = context.read<UserCalibrationController>();
    final val   = context.watch<UserCalibrationController>()
                         .calibrationFor(gateNo).userJockeyBuff;

    final trackColor = val > 0.05
        ? _kPositive
        : val < -0.05
            ? _kNegative
            : _kTextSecondary;

    return Row(
      children: [
        const SizedBox(
          width: 80,
          child: Text(
            '기수 멘탈',
            style: TextStyle(color: _kTextSecondary, fontSize: 11),
          ),
        ),
        // 왼쪽 레이블 (패널티)
        Text(
          '패널티',
          style: TextStyle(color: _kNegative.withValues(alpha: 0.6), fontSize: 9),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor:   trackColor,
              inactiveTrackColor: const Color(0x22FFFFFF),
              thumbColor:         trackColor,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape:       SliderComponentShape.noOverlay,
              trackHeight:        3,
            ),
            child: Slider(
              value:     val.clamp(kJockeyBuffMin, kJockeyBuffMax),
              min:       kJockeyBuffMin,
              max:       kJockeyBuffMax,
              divisions: 20,
              label:     val == 0.0
                  ? '기본'
                  : val > 0
                      ? '+${(val * 100).toStringAsFixed(0)}%'
                      : '${(val * 100).toStringAsFixed(0)}%',
              onChanged: enabled
                  ? (v) => ctrl.setJockeyBuff(gateNo, v)
                  : null,
            ),
          ),
        ),
        // 오른쪽 레이블 (버프)
        Text(
          '버프',
          style: TextStyle(color: _kPositive.withValues(alpha: 0.6), fontSize: 9),
        ),
        const SizedBox(width: 4),
        // 현재 값 수치 표시
        SizedBox(
          width: 36,
          child: Text(
            val == 0.0
                ? '기본'
                : '${val > 0 ? "+" : ""}${(val * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              color:      trackColor,
              fontSize:   10,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  CalibrationSpurtDropdown — 스퍼트 시점 드롭다운
//
//  【UI 컴포넌트 명세】
//  - 위젯 타입: DropdownButton<SpurtTimingSlot>
//  - 옵션: SpurtTimingSlot 4가지 (조기/표준/후기/극후기)
//  - 데이터 바인딩: onChanged → ctrl.setSpurtTiming(gateNo, slot)
//  - 물리 엔진 반영 경로:
//      spurtTiming.progOffset → spurtProgOffset(gateNo)
//      → _Horse 개별 _spurt100 동적 오프셋 적용
// ──────────────────────────────────────────────────────────────
class CalibrationSpurtDropdown extends StatelessWidget {
  final int             gateNo;
  final SpurtTimingSlot current;
  final bool            enabled;

  const CalibrationSpurtDropdown({
    super.key,
    required this.gateNo,
    required this.current,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<UserCalibrationController>();

    return Row(
      children: [
        const SizedBox(
          width: 80,
          child: Text(
            '스퍼트 시점',
            style: TextStyle(color: _kTextSecondary, fontSize: 11),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:        const Color(0x18FFFFFF),
              borderRadius: BorderRadius.circular(8),
              border: current != SpurtTimingSlot.standard
                  ? Border.all(color: _kAccent.withValues(alpha: 0.4), width: 1)
                  : null,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SpurtTimingSlot>(
                value:        current,
                isExpanded:   true,
                isDense:      true,
                dropdownColor: const Color(0xFF0E1E3A),
                style: const TextStyle(
                  color:      _kTextPrimary,
                  fontSize:   12,
                  fontWeight: FontWeight.w600,
                ),
                icon: const Icon(
                  Icons.arrow_drop_down_rounded,
                  color: _kTextSecondary,
                  size: 18,
                ),
                onChanged: enabled
                    ? (slot) {
                        if (slot != null) ctrl.setSpurtTiming(gateNo, slot);
                      }
                    : null,
                items: SpurtTimingSlot.values.map((slot) {
                  final isSelected = slot == current;
                  final offsetStr = slot.progOffset == 0.0
                      ? '기본'
                      : slot.progOffset > 0
                          ? '+${(slot.progOffset * 100).toStringAsFixed(0)}m 지연'
                          : '${(slot.progOffset * 100).toStringAsFixed(0)}m 당김';
                  return DropdownMenuItem<SpurtTimingSlot>(
                    value: slot,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          slot.label,
                          style: TextStyle(
                            color:      isSelected ? _kAccent : _kTextPrimary,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          offsetStr,
                          style: TextStyle(
                            color:    _kTextSecondary.withValues(alpha: 0.7),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  _PanelFooter — 마지막 업데이트 시각 + 적용 상태 확인
// ──────────────────────────────────────────────────────────────
class _PanelFooter extends StatelessWidget {
  const _PanelFooter();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<UserCalibrationController>();
    final t    = ctrl.lastUpdated;
    final timeStr =
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        children: [
          Icon(
            ctrl.panelEnabled ? Icons.check_circle_outline : Icons.lock_outline,
            color: ctrl.panelEnabled ? _kPositive : _kNegative,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            ctrl.panelEnabled
                ? (ctrl.modifiedCount > 0
                    ? '보정값 실시간 반영 중 · 마지막 업데이트 $timeStr'
                    : '보정값 없음 — 기본 물리 엔진 적용')
                : '경주 시작 후 보정 불가 — 잠금 상태',
            style: TextStyle(
              color:    ctrl.panelEnabled ? _kPositive : _kNegative,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
