// ══════════════════════════════════════════════════════════════════════
// SandboxModeScreen — 과거 경주 재현 & 사용자 보정 시뮬레이터
//
// [화면 구성]
//   1. 아카이브된 과거 경주 선택 (날짜/경주장/경주번호)
//   2. 실제 배당률 열람 + 사용자 직접 변수 입력 패널
//      · 기수 피로도 감점 (-5.0 ~ 0.0)
//      · 배당률 가중치 보정 (-5.0 ~ +5.0)
//   3. [시뮬레이션 실행] → race_animation_screen 기동
//   4. 시뮬레이션 종료 후 정밀도 피드백 리포트 자동 표시
//      · 실제 착순(stOrd) vs 시뮬레이션 착순 교차 대조
//      · 예측 성공률 % 계산 + 분석 리포트 생성
// ══════════════════════════════════════════════════════════════════════
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/race_models.dart';
import '../providers/race_provider.dart';
import '../services/race_result_archive.dart';
import '../services/kra_api_service.dart';
import '../utils/app_theme.dart';
import '../utils/horse_cap_colors.dart';
import 'race_animation_screen.dart';

// ──────────────────────────────────────────────────────────────────────
// 사용자 보정 세팅 (세션 4 확장: userSpeedWeight + userStaminaWeight)
// ──────────────────────────────────────────────────────────────────────
class SandboxCalibration {
  final int gateNo;
  double jockeyFatigue;     // 기수 피로도 감점 (-5.0 ~ 0.0)
  double oddsWeight;        // 배당률 가중치 보정 (-5.0 ~ +5.0)

  // ── [NEW] 세션 4: 속도·지구력 가중치 슬라이더 (명세서 3절) ──────────
  /// 초반 속도 가중치 — finalSpeed = baseSpeed × userSpeedWeight
  /// 범위: 0.5 ~ 2.0 (기본 1.0 = 보정 없음)
  double userSpeedWeight;

  /// 후반 지구력 가중치 — finalStamina = baseStamina × userStaminaWeight
  /// 범위: 0.5 ~ 2.0 (기본 1.0 = 보정 없음)
  double userStaminaWeight;

  SandboxCalibration({
    required this.gateNo,
    this.jockeyFatigue    = 0.0,
    this.oddsWeight       = 0.0,
    this.userSpeedWeight   = 1.0,
    this.userStaminaWeight = 1.0,
  });

  /// 최종 보정값 (finalScore에 더할 총 보정치)
  double get totalAdjust => jockeyFatigue + oddsWeight;
}

// ══════════════════════════════════════════════════════════════════════
class SandboxModeScreen extends StatefulWidget {
  const SandboxModeScreen({super.key});

  @override
  State<SandboxModeScreen> createState() => _SandboxModeScreenState();
}

class _SandboxModeScreenState extends State<SandboxModeScreen> {
  // ── 상태 ──────────────────────────────────────────────────────────
  bool _isLoadingArchive = true;
  List<ArchivedRaceMeta> _archiveList = [];
  ArchivedRaceMeta? _selectedMeta;
  KraRaceResult? _selectedResult;
  bool _isLoadingResult = false;

  // 사용자 보정 세팅 (마번 → SandboxCalibration)
  final Map<int, SandboxCalibration> _calibrations = {};

  // 시뮬레이션 결과 (정밀도 리포트)
  AccuracyReport? _accuracyReport;

  // 수동 경주 추가 컨트롤러
  final _dateCtrl = TextEditingController(
      text: DateTime.now()
          .subtract(const Duration(days: 7))
          .toString()
          .substring(0, 10)
          .replaceAll('-', ''));
  final _raceNoCtrl  = TextEditingController(text: '1');
  String _manualVenue = '1'; // 서울=1, 부산경남=2, 제주=3

  @override
  void initState() {
    super.initState();
    _loadArchive();
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _raceNoCtrl.dispose();
    super.dispose();
  }

  // ── 아카이브 목록 로드 ──────────────────────────────────────────
  Future<void> _loadArchive() async {
    setState(() => _isLoadingArchive = true);
    final list = await RaceResultArchive.instance.listArchived();
    setState(() {
      _archiveList = list;
      _isLoadingArchive = false;
    });
  }

  // ── 경주 결과 로드 (아카이브 또는 실시간 API) ────────────────────
  Future<void> _selectRace(ArchivedRaceMeta meta) async {
    setState(() {
      _selectedMeta   = meta;
      _isLoadingResult = true;
      _accuracyReport = null;
      _calibrations.clear();
    });

    KraRaceResult? result =
        await RaceResultArchive.instance.loadResult(meta);

    // 아카이브에 없으면 실시간 API 호출
    if (result == null) {
      try {
        final date = _parseDateStr(meta.raceDate);
        if (date != null) {
          result = await KraApiService.fetchRaceResult(
              meta.venueCode, date, meta.raceNo);
          // 결과 아카이빙
          if (result != null) {
            await RaceResultArchive.instance.runBatchArchive(
              venueCode: meta.venueCode,
              date: date,
              raceNos: [meta.raceNo],
              forceRun: true,
            );
          }
        }
      } catch (_) {}
    }

    if (result != null) {
      // 각 말 기본 보정값 초기화
      for (final h in result.horses) {
        _calibrations[h.gateNo] = SandboxCalibration(gateNo: h.gateNo);
      }
    }

    setState(() {
      _selectedResult  = result;
      _isLoadingResult = false;
    });
  }

  // ── 수동 API 호출 (아카이브에 없는 과거 경주) ───────────────────
  Future<void> _fetchManually() async {
    final dateStr = _dateCtrl.text.trim();
    final raceNo  = _raceNoCtrl.text.trim();
    if (dateStr.length != 8 || raceNo.isEmpty) {
      _showSnack('날짜(YYYYMMDD) 8자리와 경주번호를 입력하세요.');
      return;
    }

    final date = _parseDateStr(dateStr);
    if (date == null) {
      _showSnack('날짜 형식이 올바르지 않습니다 (YYYYMMDD).');
      return;
    }

    setState(() => _isLoadingResult = true);

    try {
      final result = await KraApiService.fetchRaceResult(
          _manualVenue, date, raceNo);
      if (result == null || result.horses.isEmpty) {
        _showSnack('해당 경주 데이터를 찾을 수 없습니다.');
        setState(() => _isLoadingResult = false);
        return;
      }

      // 아카이빙
      await RaceResultArchive.instance.runBatchArchive(
        venueCode: _manualVenue,
        date: date,
        raceNos: [raceNo],
        forceRun: true,
      );

      final meta = ArchivedRaceMeta(
        key:        'kra_result_${dateStr}_${_manualVenue}_$raceNo',
        raceDate:   dateStr,
        raceNo:     raceNo,
        venueCode:  _manualVenue,
        venueName:  _venueLabel(_manualVenue),
        archivedAt: DateTime.now().toIso8601String(),
        horseCount: result.horses.length,
      );

      for (final h in result.horses) {
        _calibrations[h.gateNo] = SandboxCalibration(gateNo: h.gateNo);
      }

      setState(() {
        _selectedMeta   = meta;
        _selectedResult = result;
        _isLoadingResult = false;
        _accuracyReport = null;
      });

      // 아카이브 목록 갱신
      await _loadArchive();
    } catch (e) {
      _showSnack('API 오류: $e');
      setState(() => _isLoadingResult = false);
    }
  }

  // ── 시뮬레이션 실행 ─────────────────────────────────────────────
  Future<void> _runSimulation() async {
    final result = _selectedResult;
    if (result == null) return;

    // HorseEntry 리스트 생성 (실제 배당률 + 사용자 보정 적용)
    final entries = result.horses.where((h) => h.didStart).map((h) {
      final cal = _calibrations[h.gateNo] ??
          SandboxCalibration(gateNo: h.gateNo);

      // 기본 스탯 (실제 성적 기반 역산)
      final baseOdds = h.winOdds > 0 ? h.winOdds : 50.0;
      final oddsScore = (100.0 / baseOdds).clamp(1.0, 80.0);

      // 최종 점수 = 배당 역산점 + 사용자 보정
      final finalBase = (oddsScore + cal.totalAdjust).clamp(1.0, 100.0);

      // [NEW] 세션 4: userSpeedWeight/userStaminaWeight 곱연산 적용
      // finalSpeed    = baseSpeed    × userSpeedWeight
      // finalStamina  = baseStamina  × userStaminaWeight
      final finalSpeed   = (finalBase * 0.9  * cal.userSpeedWeight).clamp(1.0, 100.0);
      final finalStamina = (finalBase * 0.85 * cal.userStaminaWeight).clamp(1.0, 100.0);

      return HorseEntry(
        gateNo:            h.gateNo,
        horseName:         h.horseName,
        jockeyName:        h.jockeyName,
        trainerName:       h.trainerName,
        weight:            h.weight,
        weightChange:      h.weightDiff,
        rating:            finalBase,
        speedStat:         finalSpeed,
        staminaStat:       finalStamina,
        formStat:          finalBase * 0.8,
        trackFitStat:      finalBase * 0.75,
        baseScore:         finalBase,
        recentRecord:      h.raceTime,
        odds:              h.winOdds,
        plcOdds:           h.placeOdds,
        userBonus:         cal.totalAdjust,
        userSpeedWeight:   cal.userSpeedWeight,
        userStaminaWeight: cal.userStaminaWeight,
      );
    }).toList();

    if (entries.isEmpty) return;

    // RaceInfo 생성 (과거 경주 재현용)
    final raceInfo = RaceInfo(
      raceNo:         result.raceNo,
      raceName:       '과거재현 제${result.raceNo}경주',
      startTime:      '14:00',
      distance:       1400,
      condition:      '국6등급',
      grade:          '국6등급',
      venueCode:      result.venueCode,
      venueName:      result.venueName,
      raceDate:       result.raceDate,
      totalHorses:    entries.length,
      trackCondition: '양호',
      isFinished:     true,
    );

    // RaceProvider에 데이터 주입 후 애니메이션 화면으로 이동
    if (!mounted) return;
    final provider = context.read<RaceProvider>();
    await provider.injectSandboxData(raceInfo, entries);

    if (!mounted) return;
    final simResults = await Navigator.push<List<RaceResult>>(
      context,
      MaterialPageRoute(
        builder: (_) => RaceAnimationScreen(
          race:    raceInfo,
          horses:  entries,
          isSandbox: true,
        ),
      ),
    );

    if (simResults != null && mounted) {
      // 정밀도 분석
      final report = AccuracyReport.generate(
        actual:    result.horses.where((h) => h.didStart).toList(),
        simulated: simResults,
        raceDate:  result.raceDate,
        raceNo:    result.raceNo,
        venueName: result.venueName,
      );
      setState(() {
        _accuracyReport = report;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050D1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _accuracyReport != null
                  ? _buildAccuracyReport(_accuracyReport!)
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildManualFetchPanel(),
                          const SizedBox(height: 14),
                          _buildArchiveList(),
                          if (_selectedResult != null) ...[
                            const SizedBox(height: 14),
                            _buildSelectedRacePanel(),
                            const SizedBox(height: 14),
                            _buildCalibrationPanel(),
                            const SizedBox(height: 20),
                            _buildRunButton(),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ──────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      color: const Color(0xFF0A1628),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          // ── 이전 페이지 돌아가기 버튼 ────────────────────────────
          GestureDetector(
            onTap: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2A3A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF3A5A7A)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_ios_new_rounded,
                      color: Color(0xFF64B5F6), size: 14),
                  SizedBox(width: 3),
                  Text('이전',
                      style: TextStyle(
                          color: Color(0xFF64B5F6),
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2A1A5E), Color(0xFF1A0A3E)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF6A3ABA)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🧪', style: TextStyle(fontSize: 16)),
                SizedBox(width: 6),
                Text('샌드박스 모드',
                    style: TextStyle(
                        color: Color(0xFFB388FF),
                        fontSize: 15, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedMeta != null
                  ? '${_selectedMeta!.venueLabel} ${_selectedMeta!.displayDate} 제${_selectedMeta!.raceNo}경주'
                  : '과거 경주 재현 & 보정 시뮬레이터',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_accuracyReport != null)
            GestureDetector(
              onTap: () => setState(() => _accuracyReport = null),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3A5A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('← 결과닫기',
                    style: TextStyle(
                        color: Color(0xFF64B5F6), fontSize: 10)),
              ),
            ),
        ],
      ),
    );
  }

  // ── 캘린더 모달 ───────────────────────────────────────────────────
  Future<void> _showCalendarModal() async {
    // _dateCtrl.text(YYYYMMDD) → DateTime 파싱
    DateTime initialDate = DateTime.now().subtract(const Duration(days: 7));
    if (_dateCtrl.text.length == 8) {
      final y = int.tryParse(_dateCtrl.text.substring(0, 4));
      final m = int.tryParse(_dateCtrl.text.substring(4, 6));
      final d = int.tryParse(_dateCtrl.text.substring(6, 8));
      if (y != null && m != null && d != null) {
        try { initialDate = DateTime(y, m, d); } catch (_) {}
      }
    }
    final firstDate = DateTime(2020, 1, 1);
    final lastDate  = DateTime.now().subtract(const Duration(days: 1));
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(lastDate))   initialDate = lastDate;

    final picked = await showDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => _CalendarModal(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      ),
    );
    if (picked != null) {
      final y = picked.year.toString().padLeft(4, '0');
      final m = picked.month.toString().padLeft(2, '0');
      final d = picked.day.toString().padLeft(2, '0');
      setState(() => _dateCtrl.text = '$y$m$d');
    }
  }

  // ── 경주번호 숫자패드 모달 ─────────────────────────────────────────
  Future<void> _showRaceNoPicker() async {
    final current = int.tryParse(_raceNoCtrl.text.trim()) ?? 1;
    final picked = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => _RaceNoPickerModal(current: current),
    );
    if (picked != null) {
      setState(() => _raceNoCtrl.text = picked.toString());
    }
  }

  // ── 수동 API 호출 패널 ────────────────────────────────────────────
  Widget _buildManualFetchPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1A3A6A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('🔍 과거 경주 직접 조회'),
          const SizedBox(height: 12),
          Row(
            children: [
              // 경주장 선택
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: _manualVenue,
                  dropdownColor: const Color(0xFF0C1A2E),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: _inputDeco('경주장'),
                  items: const [
                    DropdownMenuItem(value: '1', child: Text('서울')),
                    DropdownMenuItem(value: '2', child: Text('부산경남')),
                    DropdownMenuItem(value: '3', child: Text('제주')),
                  ],
                  onChanged: (v) => setState(() => _manualVenue = v!),
                ),
              ),
              const SizedBox(width: 8),
              // ── 날짜 — 탭 시 캘린더 모달 ──────────────────────────
              Expanded(
                flex: 4,
                child: GestureDetector(
                  onTap: _showCalendarModal,
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _dateCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      readOnly: true,
                      decoration: _inputDeco('날짜').copyWith(
                        prefixIcon: const Icon(
                          Icons.calendar_today_rounded,
                          color: Color(0xFF64B5F6), size: 15),
                        hintText: 'YYYYMMDD',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // ── 경주번호 — 탭 시 숫자패드 모달 ───────────────────
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _showRaceNoPicker,
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _raceNoCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      readOnly: true,
                      decoration: _inputDeco('경주번호').copyWith(
                        prefixIcon: const Icon(
                          Icons.tag_rounded,
                          color: Color(0xFF64B5F6), size: 15),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoadingResult ? null : _fetchManually,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A3A6A),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: _isLoadingResult
                  ? const SizedBox(
                      height: 16, width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('경주 데이터 조회',
                      style: TextStyle(
                          color: Color(0xFF64B5F6),
                          fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 아카이브 목록 ─────────────────────────────────────────────────
  Widget _buildArchiveList() {
    if (_isLoadingArchive) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionTitle('📦 아카이브된 경주'),
            const Spacer(),
            Text('${_archiveList.length}건',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11)),
          ],
        ),
        const SizedBox(height: 8),
        if (_archiveList.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1A2E),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text('아카이브된 경주가 없습니다.\n위에서 과거 경주를 조회하세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12)),
            ),
          )
        else
          SizedBox(
            height: 110,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _archiveList.length,
              itemBuilder: (_, i) {
                final meta = _archiveList[i];
                final isSelected = _selectedMeta?.key == meta.key;
                return GestureDetector(
                  onTap: () => _selectRace(meta),
                  child: Container(
                    width: 120,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1A2A5E)
                          : const Color(0xFF0C1A2E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF6A8ADA)
                            : const Color(0xFF1A2A3A),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(meta.venueLabel,
                            style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF64B5F6)
                                    : Colors.white.withValues(alpha: 0.7),
                                fontSize: 11, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(meta.displayDate,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 10)),
                        Text('제${meta.raceNo}경주',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13, fontWeight: FontWeight.w900)),
                        const Spacer(),
                        Text('${meta.horseCount}두 출전',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 9.5)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // ── 선택된 경주 결과 패널 ─────────────────────────────────────────
  Widget _buildSelectedRacePanel() {
    final result = _selectedResult!;
    final winner = result.winner;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('🏁 실제 경주 결과 (racedetailresult)'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1A2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1A2A3A)),
          ),
          child: Column(
            children: [
              // 우승마 하이라이트
              if (winner != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Text('🏆', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(winner.horseName,
                                style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 14, fontWeight: FontWeight.w900)),
                            Text(
                                '${winner.jockeyName} 기수  '
                                '주파기록: ${winner.raceTime}',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 10.5)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                              winner.winOdds > 0
                                  ? '단승 ${winner.winOdds.toStringAsFixed(1)}배'
                                  : '배당 미발매',
                              style: const TextStyle(
                                  color: Color(0xFFFF7043),
                                  fontSize: 12, fontWeight: FontWeight.w800)),
                          Text(
                              winner.placeOdds > 0
                                  ? '연승 ${winner.placeOdds.toStringAsFixed(1)}배'
                                  : '',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),

              // 착순 테이블 (출전마 상위 5착)
              ...result.starters.take(5).map((h) {
                final cd = HorseCapColors.getCapData(h.gateNo);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text('${h.rank}착',
                            style: TextStyle(
                                color: h.rank == 1
                                    ? const Color(0xFFFFD700)
                                    : Colors.white.withValues(alpha: 0.7),
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                      Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                            color: cd.bg, shape: BoxShape.circle),
                        child: Center(
                          child: Text('${h.gateNo}',
                              style: TextStyle(
                                  color: cd.text,
                                  fontSize: 9.5, fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(h.horseName,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11.5)),
                      ),
                      if (h.differ.isNotEmpty)
                        Text(h.differ,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 10)),
                      const SizedBox(width: 8),
                      Text(
                          h.winOdds > 0
                              ? '${h.winOdds.toStringAsFixed(1)}배'
                              : '—',
                          style: TextStyle(
                              color: h.winOdds > 20
                                  ? const Color(0xFFFF5722)
                                  : const Color(0xFFFFD700),
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // ── 사용자 보정 패널 (세션 4 재구성) ────────────────────────────────
  // 명세서 3절: 실시간 배당현황판 + 초반속도/후반지구력 이중 슬라이더
  Widget _buildCalibrationPanel() {
    final result   = _selectedResult!;
    final starters = result.horses.where((h) => h.didStart).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ━━ 실시간 배당 현황판 (명세서 UI 테이블) ━━━━━━━━━━━━━━━━━━━━━━━
        _sectionTitle('📊 실시간 배당 현황판'),
        const SizedBox(height: 8),
        _buildOddsBoard(starters),
        const SizedBox(height: 14),

        // ━━ 사용자 수동 보정 슬라이더 패널 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        _sectionTitle('🎛️ 사용자 보정 변수 입력'),
        const SizedBox(height: 6),
        Text(
          '초반 속도(×)와 후반 지구력(×) 가중치를 조정하세요. (1.0 = 기본값)',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45), fontSize: 10.5),
        ),
        const SizedBox(height: 10),
        ...starters.map((h) {
          final cal = _calibrations[h.gateNo] ??
              SandboxCalibration(gateNo: h.gateNo);
          final cd = HorseCapColors.getCapData(h.gateNo);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1A2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1A2A3A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 마번 + 마명 + 단승식/복승식 배당 ─────────────────
                Row(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(color: cd.bg, shape: BoxShape.circle),
                      child: Center(
                        child: Text('${h.gateNo}',
                            style: TextStyle(
                                color: cd.text,
                                fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.horseName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12, fontWeight: FontWeight.w800)),
                          Text(h.jockeyName,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 10)),
                        ],
                      ),
                    ),
                    // 단승식 배당
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (h.winOdds > 0)
                          Text('단 ${h.winOdds.toStringAsFixed(1)}배',
                              style: TextStyle(
                                  color: _oddsColor(h.winOdds),
                                  fontSize: 11, fontWeight: FontWeight.w800))
                        else
                          Text('배당없음',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  fontSize: 10)),
                        if (h.placeOdds > 0)
                          Text('복 ${h.placeOdds.toStringAsFixed(1)}배',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 9.5)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── ① 초반 속도 가중치 슬라이더 ─────────────────────
                // finalSpeed = baseSpeed × userSpeedWeight (명세서 3절)
                _buildWeightSlider(
                  label:    '⚡ 초반 속도',
                  value:    cal.userSpeedWeight,
                  color:    const Color(0xFF64B5F6),
                  onChanged: (v) => setState(() => cal.userSpeedWeight = v),
                ),
                const SizedBox(height: 4),

                // ── ② 후반 지구력 가중치 슬라이더 ──────────────────
                // finalStamina = baseStamina × userStaminaWeight
                _buildWeightSlider(
                  label:    '🏃 후반 지구력',
                  value:    cal.userStaminaWeight,
                  color:    const Color(0xFF81C784),
                  onChanged: (v) => setState(() => cal.userStaminaWeight = v),
                ),
                const SizedBox(height: 4),

                // ── ③ 기수 피로도 (기존 유지) ─────────────────────
                _buildFatigueSlider(cal),

                // ── 가중치 요약 표시 ─────────────────────────────
                if (cal.userSpeedWeight != 1.0 || cal.userStaminaWeight != 1.0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _weightBadge('속도 ×${cal.userSpeedWeight.toStringAsFixed(2)}',
                            const Color(0xFF64B5F6)),
                        const SizedBox(width: 6),
                        _weightBadge('지구력 ×${cal.userStaminaWeight.toStringAsFixed(2)}',
                            const Color(0xFF81C784)),
                      ],
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ── 실시간 배당 현황판 (명세서 UI: 마번/마명/단승식/복승식/조교태세) ──
  Widget _buildOddsBoard(List<HorseResult> starters) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF071220),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1A3A6A)),
      ),
      child: Column(
        children: [
          // 컬럼 헤더
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _boardHeader('마번', 36),
                _boardHeader('마명', 0, flex: true),
                _boardHeader('단승식', 52),
                _boardHeader('복승식', 52),
                _boardHeader('조교태세', 70),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1A3A6A), height: 1),
          const SizedBox(height: 6),
          ...starters.map((h) => _buildOddsBoardRow(h)),
        ],
      ),
    );
  }

  // 배당현황판 개별 행
  Widget _buildOddsBoardRow(HorseResult h) {
    final cd       = HorseCapColors.getCapData(h.gateNo);
    final winColor = _oddsColor(h.winOdds);
    // TrainerFocus 태세 표시 (현재 샌드박스에서는 임시 표시)
    // race_stat_engine에서 enrichHorseStats 후에는 실제 Focus 데이터 사용
    final trainerStatus = _getTrainerFocusLabel(h.gateNo);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // 마번 원형 칩
          SizedBox(
            width: 36,
            child: Center(
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(color: cd.bg, shape: BoxShape.circle),
                child: Center(
                  child: Text('${h.gateNo}',
                      style: TextStyle(
                          color: cd.text,
                          fontSize: 10, fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ),
          // 마명
          Expanded(
            child: Text(h.horseName,
                style: const TextStyle(color: Colors.white, fontSize: 11.5),
                overflow: TextOverflow.ellipsis),
          ),
          // 단승식
          SizedBox(
            width: 52,
            child: Text(
              h.winOdds > 0 ? h.winOdds.toStringAsFixed(1) : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: winColor,
                  fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          // 복승식
          SizedBox(
            width: 52,
            child: Text(
              h.placeOdds > 0 ? h.placeOdds.toStringAsFixed(1) : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11),
            ),
          ),
          // 조교태세
          SizedBox(
            width: 70,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: trainerStatus.bgColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: trainerStatus.bgColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                trainerStatus.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: trainerStatus.bgColor,
                    fontSize: 9.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 조교태세 레이블/색상 (TrainerFocus 실데이터 없을 때 중립 표시)
  _FocusStatus _getTrainerFocusLabel(int gateNo) {
    // 실제 TrainerFocus 데이터가 있으면 해당 데이터 사용
    // 현재는 샌드박스 기본값 (과거 데이터에는 trnweekentry 없음)
    return _FocusStatus(label: '✅ 보통', bgColor: const Color(0xFF78909C));
  }

  // 배당 색상 (manual_calibration_panel과 동일)
  Color _oddsColor(double odds) {
    if (odds <= 3.0)  return const Color(0xFF4CAF50);
    if (odds <= 6.0)  return const Color(0xFF8BC34A);
    if (odds <= 10.0) return const Color(0xFFFFD700);
    if (odds <= 20.0) return const Color(0xFFFF9800);
    return const Color(0xFFEF5350);
  }

  // 배당현황판 헤더 셀
  Widget _boardHeader(String text, double width, {bool flex = false}) {
    final cell = Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 9.5, fontWeight: FontWeight.w600));
    if (flex) return Expanded(child: cell);
    return SizedBox(width: width, child: cell);
  }

  // 가중치 슬라이더 빌더 (초반속도 / 후반지구력 공통)
  Widget _buildWeightSlider({
    required String label,
    required double value,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    final pct = ((value - 1.0) * 100).round();
    final pctStr = pct >= 0 ? '+$pct%' : '$pct%';

    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65), fontSize: 10)),
        ),
        Text('0.5',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25), fontSize: 9)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: color,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value,
              min: 0.5, max: 2.0, divisions: 30,
              onChanged: onChanged,
            ),
          ),
        ),
        Text('2.0',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25), fontSize: 9)),
        const SizedBox(width: 4),
        Container(
          width: 42,
          alignment: Alignment.center,
          child: Text(pctStr,
              style: TextStyle(
                  color: value > 1.0
                      ? color
                      : value < 1.0
                          ? const Color(0xFFFF5252)
                          : Colors.white.withValues(alpha: 0.4),
                  fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  // 기수 피로도 슬라이더 (기존 유지)
  Widget _buildFatigueSlider(SandboxCalibration cal) {
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text('😴 피로도',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55), fontSize: 10)),
        ),
        Text('-5',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25), fontSize: 9)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: const Color(0xFFFF5252),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: const Color(0xFFFF5252),
              overlayColor: const Color(0x22FF5252),
            ),
            child: Slider(
              value: cal.jockeyFatigue,
              min: -5.0, max: 0.0, divisions: 10,
              onChanged: (v) => setState(() => cal.jockeyFatigue = v),
            ),
          ),
        ),
        Text('0',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25), fontSize: 9)),
        const SizedBox(width: 4),
        Container(
          width: 42,
          alignment: Alignment.center,
          child: Text(cal.jockeyFatigue.toStringAsFixed(1),
              style: TextStyle(
                  color: cal.jockeyFatigue < 0
                      ? const Color(0xFFFF5252)
                      : Colors.white.withValues(alpha: 0.4),
                  fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  // 가중치 뱃지
  Widget _weightBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 9.5, fontWeight: FontWeight.w700)),
    );
  }

  // ── 시뮬레이션 실행 버튼 ─────────────────────────────────────────
  Widget _buildRunButton() {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5C35C0), Color(0xFF8B5CF6)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
            blurRadius: 16, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _runSimulation,
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🚀', style: TextStyle(fontSize: 20)),
                SizedBox(width: 10),
                Text('시뮬레이션 실행',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 정밀도 피드백 리포트 ─────────────────────────────────────────
  Widget _buildAccuracyReport(AccuracyReport report) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 메인 리포트 카드
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  report.accuracyPct >= 70
                      ? const Color(0xFF1A3A1A)
                      : const Color(0xFF1A1A3A),
                  const Color(0xFF0C0C1E),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: report.accuracyPct >= 70
                    ? const Color(0xFF4CAF50).withValues(alpha: 0.5)
                    : const Color(0xFF6A5ACD).withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 타이틀
                Row(
                  children: [
                    Text(
                      report.accuracyPct >= 70 ? '🎯' : '📊',
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('시뮬레이션 정밀도 리포트',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 정밀도 수치
                Center(
                  child: Column(
                    children: [
                      Text('${report.accuracyPct.toStringAsFixed(1)}%',
                          style: TextStyle(
                              color: report.accuracyPct >= 70
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFB388FF),
                              fontSize: 52, fontWeight: FontWeight.w900)),
                      Text('예측 정확도',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 분석 메시지
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(report.message,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13, height: 1.6)),
                ),

                const SizedBox(height: 14),

                // 세부 지표
                _reportDetailRow('1착마 예측',
                    report.winnerCorrect ? '✅ 성공' : '❌ 실패',
                    report.winnerCorrect
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFFF5252)),
                _reportDetailRow('3착 이내 예측',
                    '${report.top3Correct}마 / 3마 정확',
                    const Color(0xFF64B5F6)),
                _reportDetailRow('경주일시',
                    '${report.venueName} ${report.displayDate} 제${report.raceNo}경주',
                    Colors.white.withValues(alpha: 0.5)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 착순 대조표
          _sectionTitle('📋 착순 교차 대조표'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1A2A3A)),
            ),
            child: Column(
              children: [
                // 헤더
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const SizedBox(width: 30),
                      Expanded(
                        child: Text('말이름',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 10)),
                      ),
                      SizedBox(
                        width: 50,
                        child: Text('실제',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: const Color(0xFFFFD700).withValues(alpha: 0.7),
                                fontSize: 10)),
                      ),
                      SizedBox(
                        width: 50,
                        child: Text('예측',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: const Color(0xFF64B5F6).withValues(alpha: 0.7),
                                fontSize: 10)),
                      ),
                      const SizedBox(width: 24),
                    ],
                  ),
                ),
                ...report.comparison.map((c) {
                  final cd = HorseCapColors.getCapData(c.gateNo);
                  final diff = (c.actualRank - c.simRank).abs();
                  final isExact = diff == 0;
                  final isClose = diff <= 1;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                              color: cd.bg, shape: BoxShape.circle),
                          child: Center(
                            child: Text('${c.gateNo}',
                                style: TextStyle(
                                    color: cd.text,
                                    fontSize: 9.5, fontWeight: FontWeight.w900)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(c.horseName,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                              overflow: TextOverflow.ellipsis),
                        ),
                        SizedBox(
                          width: 50,
                          child: Text('${c.actualRank}착',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 12, fontWeight: FontWeight.w800)),
                        ),
                        SizedBox(
                          width: 50,
                          child: Text('${c.simRank}착',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: isExact
                                      ? const Color(0xFF4CAF50)
                                      : isClose
                                          ? const Color(0xFFFFD700)
                                          : const Color(0xFFFF5252),
                                  fontSize: 12, fontWeight: FontWeight.w800)),
                        ),
                        SizedBox(
                          width: 24,
                          child: Text(
                              isExact ? '🎯' : isClose ? '🟡' : '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 20),
          // 재시도 버튼
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => setState(() {
                _accuracyReport = null;
              }),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF6A5ACD)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('보정 값 조정 후 재시뮬레이션',
                  style: TextStyle(
                      color: Color(0xFFB388FF),
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportDetailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ── 유틸 ──────────────────────────────────────────────────────────
  Widget _sectionTitle(String text) {
    return Row(
      children: [
        Container(
          width: 3, height: 16,
          decoration: BoxDecoration(
            gradient: AppTheme.goldGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                color: AppTheme.textWhite,
                fontSize: 13, fontWeight: FontWeight.w800)),
      ],
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
        filled: true,
        fillColor: const Color(0xFF071220),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1A3A5A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1A3A5A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3A6ABA)),
        ),
      );

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: const Color(0xFF1A2A3A)));
  }

  String _venueLabel(String code) {
    switch (code) {
      case '1': return '서울';
      case '2': return '부산경남';
      case '3': return '제주';
      default:  return code;
    }
  }

  DateTime? _parseDateStr(String s) {
    if (s.length != 8) return null;
    try {
      return DateTime(
          int.parse(s.substring(0, 4)),
          int.parse(s.substring(4, 6)),
          int.parse(s.substring(6, 8)));
    } catch (_) {
      return null;
    }
  }
}

// ──────────────────────────────────────────────────────────────────────
// _FocusStatus — 조교태세 레이블/색상 래퍼 (배당현황판 조교태세 컬럼용)
// ──────────────────────────────────────────────────────────────────────
class _FocusStatus {
  final String label;
  final Color bgColor;
  const _FocusStatus({required this.label, required this.bgColor});
}

// ══════════════════════════════════════════════════════════════════════
// AccuracyReport — 시뮬레이션 vs 실제 착순 정밀도 분석
// ══════════════════════════════════════════════════════════════════════
class RankComparison {
  final int gateNo;
  final String horseName;
  final int actualRank;  // 실제 착순 (racedetailresult)
  final int simRank;     // 시뮬레이션 착순

  const RankComparison({
    required this.gateNo,
    required this.horseName,
    required this.actualRank,
    required this.simRank,
  });
}

class AccuracyReport {
  final double accuracyPct;    // 예측 정확도 (%)
  final bool winnerCorrect;    // 1착마 정확 여부
  final int top3Correct;       // 3착 이내 정확 수
  final String message;        // 분석 리포트 메시지
  final List<RankComparison> comparison; // 착순 대조표
  final String raceDate;
  final String raceNo;
  final String venueName;

  const AccuracyReport({
    required this.accuracyPct,
    required this.winnerCorrect,
    required this.top3Correct,
    required this.message,
    required this.comparison,
    required this.raceDate,
    required this.raceNo,
    required this.venueName,
  });

  String get displayDate {
    if (raceDate.length < 8) return raceDate;
    return '${raceDate.substring(0, 4)}.'
        '${raceDate.substring(4, 6)}.'
        '${raceDate.substring(6, 8)}';
  }

  // ── 정밀도 리포트 생성 ───────────────────────────────────────────
  static AccuracyReport generate({
    required List<HorseResult> actual,   // racedetailresult 실제 결과
    required List<RaceResult> simulated, // 시뮬레이션 결과
    required String raceDate,
    required String raceNo,
    required String venueName,
  }) {
    // 착순 대조표 생성
    final comparison = <RankComparison>[];
    for (final a in actual) {
      final s = simulated.firstWhere(
          (r) => r.gateNo == a.gateNo,
          orElse: () => RaceResult(
              rank: 99, gateNo: a.gateNo,
              horseName: a.horseName, jockeyName: a.jockeyName,
              finalScore: 0));
      comparison.add(RankComparison(
        gateNo:    a.gateNo,
        horseName: a.horseName,
        actualRank: a.rank,
        simRank:    s.rank,
      ));
    }
    comparison.sort((a, b) => a.actualRank.compareTo(b.actualRank));

    // 정확도 지표 계산
    final winner = actual.firstWhere(
        (h) => h.rank == 1, orElse: () => actual.first);
    final simWinner = simulated.isNotEmpty ? simulated[0] : null;

    final winnerCorrect = simWinner?.gateNo == winner.gateNo;

    // 3착 이내 정확 수 (교집합)
    final actualTop3  = actual.where((h) => h.rank <= 3).map((h) => h.gateNo).toSet();
    final simTop3     = simulated.take(3).map((r) => r.gateNo).toSet();
    final top3Correct = actualTop3.intersection(simTop3).length;

    // 전체 정확도: 착순 차이 최소화 점수
    double totalScore = 0;
    int count = 0;
    for (final c in comparison) {
      final diff = (c.actualRank - c.simRank).abs();
      final score = math.max(0.0, 1.0 - (diff / actual.length));
      totalScore += score;
      count++;
    }
    final accuracyPct = count > 0 ? (totalScore / count * 100) : 0.0;

    // 리포트 메시지 생성
    final msg = _generateMessage(
        winner: winner,
        simWinner: simWinner,
        winnerCorrect: winnerCorrect,
        top3Correct: top3Correct,
        accuracyPct: accuracyPct,
        venueName: venueName,
        raceDate: raceDate,
        raceNo: raceNo);

    return AccuracyReport(
      accuracyPct:  accuracyPct,
      winnerCorrect: winnerCorrect,
      top3Correct:  top3Correct,
      message:      msg,
      comparison:   comparison,
      raceDate:     raceDate,
      raceNo:       raceNo,
      venueName:    venueName,
    );
  }

  static String _generateMessage({
    required HorseResult winner,
    required RaceResult? simWinner,
    required bool winnerCorrect,
    required int top3Correct,
    required double accuracyPct,
    required String venueName,
    required String raceDate,
    required String raceNo,
  }) {
    final displayDate = raceDate.length >= 8
        ? '${raceDate.substring(0, 4)}년 ${raceDate.substring(4, 6)}월 '
          '${raceDate.substring(6, 8)}일'
        : raceDate;

    final oddsStr = winner.winOdds > 0
        ? '단승 배당 ${winner.winOdds.toStringAsFixed(1)}배'
        : '배당 미발매';

    final winnerOddsType = winner.winOdds > 30
        ? '대역전극(고배당)'
        : winner.winOdds > 10
            ? '중배당 이변'
            : '1~2인기 순위 결과';

    if (winnerCorrect) {
      return '유저님이 입력하신 보정 변수 기반 시뮬레이션 결과,\n'
          '$displayDate $venueName 제${raceNo}경주에서 '
          '실제 우승마(${winner.horseName}, $oddsStr)를 '
          '${accuracyPct.toStringAsFixed(1)}%의 정확도로 예측했습니다!\n\n'
          '3착 이내 예측 성공 $top3Correct/3마 · $winnerOddsType\n'
          '보정 변수를 더 세밀하게 조정하면 예측 정밀도를 높일 수 있습니다.';
    } else {
      final actualWinnerStr =
          '${winner.horseName}(${oddsStr})';
      final simWinnerStr = simWinner != null
          ? simWinner.horseName
          : '미예측';
      return '이번 시뮬레이션에서 실제 우승마($actualWinnerStr)를 '
          '예측하지 못했습니다.\n'
          '시뮬레이터가 예측한 우승마는 $simWinnerStr였습니다.\n\n'
          '3착 이내 예측 $top3Correct/3마 성공 · 전체 정확도 ${accuracyPct.toStringAsFixed(1)}%\n'
          '기수 피로도 감점 또는 배당 가중치를 재조정하고 '
          '다시 시도해 보세요.';
    }
  }
}

// ══════════════════════════════════════════════════════════════════════
// 캘린더 모달 위젯
// ══════════════════════════════════════════════════════════════════════
class _CalendarModal extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  const _CalendarModal({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_CalendarModal> createState() => _CalendarModalState();
}

class _CalendarModalState extends State<_CalendarModal> {
  late DateTime _focusedMonth;
  late DateTime _selected;

  static const List<String> _weekDayLabels = ['월','화','수','목','금','토','일'];
  static const List<String> _monthNames = [
    '1월','2월','3월','4월','5월','6월',
    '7월','8월','9월','10월','11월','12월',
  ];

  @override
  void initState() {
    super.initState();
    _selected     = widget.initialDate;
    _focusedMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  void _prevMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  void _nextMonth() {
    final next = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    final limit = DateTime(widget.lastDate.year, widget.lastDate.month);
    if (next.isAfter(limit)) return;
    setState(() => _focusedMonth = next);
  }

  List<DateTime?> _buildCalendarDays() {
    final firstOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    // 월요일=0 기준 offset
    final startOffset = (firstOfMonth.weekday - 1) % 7;
    final daysInMonth = DateUtils.getDaysInMonth(
        _focusedMonth.year, _focusedMonth.month);
    final cells = <DateTime?>[];
    for (int i = 0; i < startOffset; i++) cells.add(null);
    for (int d = 1; d <= daysInMonth; d++) {
      cells.add(DateTime(_focusedMonth.year, _focusedMonth.month, d));
    }
    while (cells.length % 7 != 0) cells.add(null);
    return cells;
  }

  bool _isSelectable(DateTime day) {
    return !day.isBefore(widget.firstDate) && !day.isAfter(widget.lastDate);
  }

  @override
  Widget build(BuildContext context) {
    final days = _buildCalendarDays();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0C1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1A3A6A)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2979FF).withValues(alpha: 0.2),
              blurRadius: 24, spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 헤더 ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A3A6A), Color(0xFF0C1A2E)],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Text('📅', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  const Text('날짜 선택',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close_rounded,
                        color: Color(0xFF64B5F6), size: 20),
                  ),
                ],
              ),
            ),

            // ── 월 네비게이터 ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: _prevMonth,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A3A5A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('‹',
                          style: TextStyle(
                            color: Color(0xFF64B5F6),
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          )),
                    ),
                  ),
                  Text(
                    '${_focusedMonth.year}년 ${_monthNames[_focusedMonth.month - 1]}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  GestureDetector(
                    onTap: _nextMonth,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A3A5A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('›',
                          style: TextStyle(
                            color: Color(0xFF64B5F6),
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          )),
                    ),
                  ),
                ],
              ),
            ),

            // ── 요일 헤더 ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: _weekDayLabels.map((w) {
                  final isSat = w == '토';
                  final isSun = w == '일';
                  return Expanded(
                    child: Center(
                      child: Text(w,
                          style: TextStyle(
                            color: isSun
                                ? const Color(0xFFFF5252)
                                : isSat
                                    ? const Color(0xFF64B5F6)
                                    : const Color(0xFF8A9ABB),
                            fontSize: 11, fontWeight: FontWeight.w700,
                          )),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 4),

            // ── 날짜 그리드 ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 4, crossAxisSpacing: 4,
                  childAspectRatio: 1.1,
                ),
                itemCount: days.length,
                itemBuilder: (_, i) {
                  final day = days[i];
                  if (day == null) return const SizedBox();
                  final isSelected = day.year == _selected.year &&
                      day.month == _selected.month &&
                      day.day == _selected.day;
                  final isToday = day.year == DateTime.now().year &&
                      day.month == DateTime.now().month &&
                      day.day == DateTime.now().day;
                  final selectable = _isSelectable(day);
                  final colIdx = i % 7;
                  final isSat = colIdx == 5;
                  final isSun = colIdx == 6;

                  return GestureDetector(
                    onTap: selectable ? () => setState(() => _selected = day) : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [Color(0xFF2979FF), Color(0xFF1565C0)])
                            : null,
                        color: isSelected
                            ? null
                            : isToday
                                ? const Color(0xFF1A3A5A)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isToday && !isSelected
                            ? Border.all(
                                color: const Color(0xFF2979FF).withValues(alpha: 0.5))
                            : null,
                        boxShadow: isSelected
                            ? [BoxShadow(
                                color: const Color(0xFF2979FF).withValues(alpha: 0.4),
                                blurRadius: 6)]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : !selectable
                                    ? const Color(0xFF3A4A5A)
                                    : isSun
                                        ? const Color(0xFFFF5252)
                                        : isSat
                                            ? const Color(0xFF64B5F6)
                                            : Colors.white,
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w900
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── 선택 확인 버튼 ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2A3A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF3A5A7A)),
                        ),
                        child: const Center(
                          child: Text('취소',
                              style: TextStyle(
                                  color: Color(0xFF8A9ABB),
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, _selected),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2979FF), Color(0xFF1565C0)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2979FF).withValues(alpha: 0.4),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${_selected.year}.${_selected.month.toString().padLeft(2,'0')}.${_selected.day.toString().padLeft(2,'0')} 선택',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 경주번호 숫자패드 모달 위젯
// ══════════════════════════════════════════════════════════════════════
class _RaceNoPickerModal extends StatefulWidget {
  final int current;
  const _RaceNoPickerModal({required this.current});

  @override
  State<_RaceNoPickerModal> createState() => _RaceNoPickerModalState();
}

class _RaceNoPickerModalState extends State<_RaceNoPickerModal> {
  late int _selected;

  // KRA 경주 최대번호 통상 12경주
  static const int _maxRace = 12;

  @override
  void initState() {
    super.initState();
    _selected = widget.current.clamp(1, _maxRace);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 100),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0C1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1A3A6A)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6A3ABA).withValues(alpha: 0.25),
              blurRadius: 24, spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 헤더 ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2A1A5E), Color(0xFF0C1A2E)],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tag_rounded, color: Color(0xFFB388FF), size: 22),
                  const SizedBox(width: 8),
                  const Text('경주번호 선택',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close_rounded,
                        color: Color(0xFFB388FF), size: 20),
                  ),
                ],
              ),
            ),

            // ── 선택된 번호 표시 ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Container(
                  key: ValueKey(_selected),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2A1A5E), Color(0xFF1A0A3E)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: const Color(0xFF6A3ABA).withValues(alpha: 0.7)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6A3ABA).withValues(alpha: 0.3),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Text(
                    '제 $_selected 경주',
                    style: const TextStyle(
                        color: Color(0xFFB388FF),
                        fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),

            // ── 숫자 그리드 (1~12) ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8, crossAxisSpacing: 8,
                  childAspectRatio: 1.4,
                ),
                itemCount: _maxRace,
                itemBuilder: (_, i) {
                  final num = i + 1;
                  final isSel = num == _selected;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = num),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        gradient: isSel
                            ? const LinearGradient(
                                colors: [Color(0xFF6A3ABA), Color(0xFF3A1A7E)])
                            : null,
                        color: isSel ? null : const Color(0xFF1A2A3A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSel
                              ? const Color(0xFF6A3ABA)
                              : const Color(0xFF2A3A4A),
                        ),
                        boxShadow: isSel
                            ? [BoxShadow(
                                color: const Color(0xFF6A3ABA).withValues(alpha: 0.4),
                                blurRadius: 8)]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '$num',
                          style: TextStyle(
                            color: isSel
                                ? Colors.white
                                : const Color(0xFF8A9ABB),
                            fontSize: 16,
                            fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── 확인 버튼 ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2A3A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF3A5A7A)),
                        ),
                        child: const Center(
                          child: Text('취소',
                              style: TextStyle(
                                  color: Color(0xFF8A9ABB),
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, _selected),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6A3ABA), Color(0xFF3A1A7E)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6A3ABA).withValues(alpha: 0.4),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text('선택 완료',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
