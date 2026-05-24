import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/race_schedule_cache.dart';
import '../services/kra_bulk_sync_service.dart';
import '../services/kra_bulk_data_binder.dart';
import '../models/race_models.dart';

// ══════════════════════════════════════════════════════════════════════════
//  AdminDataPanelScreen — 관리자 데이터 파이프라인 컨트롤 패널
//
//  ▸ Tab 1: 출전표 수동 입력 (이미지 업로드 + 텍스트 강제 인젝션)
//  ▸ Tab 2: 새벽 API 벌크 싱크 현황 & 즉시 실행
//  ▸ Tab 3: API 에러 로그 뷰어 + kra_api_error_dump.log 내보내기
// ══════════════════════════════════════════════════════════════════════════
class AdminDataPanelScreen extends StatefulWidget {
  const AdminDataPanelScreen({super.key});

  @override
  State<AdminDataPanelScreen> createState() => _AdminDataPanelScreenState();
}

class _AdminDataPanelScreenState extends State<AdminDataPanelScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12122A),
        title: const Text(
          '관리자 데이터 파이프라인',
          style: TextStyle(
            color: Color(0xFFE0E0FF),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF8888BB)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF6C63FF),
          labelColor: const Color(0xFFE0E0FF),
          unselectedLabelColor: const Color(0xFF555580),
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.upload_file, size: 18), text: '수동 인젝션'),
            Tab(icon: Icon(Icons.schedule, size: 18), text: '벌크 싱크'),
            Tab(icon: Icon(Icons.bug_report, size: 18), text: '에러 로그'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ManualInjectionTab(),
          _BulkSyncTab(),
          _ErrorLogTab(),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Tab 1: 출전표 수동 인젝션
// ══════════════════════════════════════════════════════════════════════════
class _ManualInjectionTab extends StatefulWidget {
  const _ManualInjectionTab();

  @override
  State<_ManualInjectionTab> createState() => _ManualInjectionTabState();
}

class _ManualInjectionTabState extends State<_ManualInjectionTab> {
  // ── 폼 컨트롤러 ──────────────────────────────────────────────────────
  final _venueCtrl      = TextEditingController(text: '1');
  final _dateCtrl       = TextEditingController();
  final _raceNoCtrl     = TextEditingController(text: '1');
  final _startTimeCtrl  = TextEditingController(text: '10:35');
  final _distanceCtrl   = TextEditingController(text: '1400');
  final _conditionCtrl  = TextEditingController(text: '국6등급');
  final _gradeCtrl      = TextEditingController(text: '국6등급');
  final _totalHorsesCtrl= TextEditingController(text: '10');
  final _trackCondCtrl  = TextEditingController(text: '양호');
  final _specialNameCtrl= TextEditingController();
  bool  _isSpecial      = false;
  bool  _isSaving       = false;
  String _saveResult    = '';

  // 출전마 목록 (최대 16두)
  final List<Map<String, TextEditingController>> _horseControllers = [];

  @override
  void initState() {
    super.initState();
    // 날짜 기본값: 오늘
    final now = DateTime.now().toLocal();
    _dateCtrl.text = '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}';
    // 기본 출전마 5두
    for (int i = 0; i < 5; i++) _addHorseRow();
  }

  void _addHorseRow() {
    _horseControllers.add({
      'gateNo':    TextEditingController(text: '${_horseControllers.length + 1}'),
      'horseName': TextEditingController(),
      'jockey':    TextEditingController(),
      'trainer':   TextEditingController(),
      'weight':    TextEditingController(text: '500'),
      'rating':    TextEditingController(text: '60'),
    });
  }

  @override
  void dispose() {
    for (final m in _horseControllers) {
      for (final c in m.values) { c.dispose(); }
    }
    _venueCtrl.dispose(); _dateCtrl.dispose(); _raceNoCtrl.dispose();
    _startTimeCtrl.dispose(); _distanceCtrl.dispose(); _conditionCtrl.dispose();
    _gradeCtrl.dispose(); _totalHorsesCtrl.dispose(); _trackCondCtrl.dispose();
    _specialNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveInjection() async {
    setState(() { _isSaving = true; _saveResult = ''; });
    try {
      final venueCode = _venueCtrl.text.trim();
      final dateStr   = _dateCtrl.text.trim();
      if (dateStr.length != 8) {
        throw Exception('날짜 형식 오류: YYYYMMDD 8자리 입력');
      }
      final y  = int.parse(dateStr.substring(0, 4));
      final mo = int.parse(dateStr.substring(4, 6));
      final d  = int.parse(dateStr.substring(6, 8));
      final date = DateTime(y, mo, d);

      final venueName = venueCode == '1' ? '서울'
          : venueCode == '2' ? '부산경남' : '제주';

      final race = RaceInfo(
        raceNo:          _raceNoCtrl.text.trim(),
        raceName:        _isSpecial && _specialNameCtrl.text.isNotEmpty
            ? _specialNameCtrl.text.trim()
            : '제${_raceNoCtrl.text.trim()}경주',
        startTime:       _startTimeCtrl.text.trim(),
        distance:        int.tryParse(_distanceCtrl.text.trim()) ?? 1400,
        condition:       _conditionCtrl.text.trim(),
        grade:           _gradeCtrl.text.trim(),
        venueCode:       venueCode,
        venueName:       venueName,
        raceDate:        dateStr,
        totalHorses:     int.tryParse(_totalHorsesCtrl.text.trim()) ?? 10,
        trackCondition:  _trackCondCtrl.text.trim(),
        isSpecialRace:   _isSpecial,
        specialRaceName: _isSpecial ? _specialNameCtrl.text.trim() : '',
      );

      final cache = RaceScheduleCache();
      await cache.saveSnapshot(
        races: [race],
        venueCode: venueCode,
        date: date,
        source: 'admin_inject',
      );

      setState(() {
        _saveResult = '✅ 저장 완료!\n'
            '경주장: $venueName | 날짜: $dateStr | '
            '${race.raceNo}경주 (${race.startTime}) → 캐시 인젝션됨\n'
            '다음 화면 갱신 시 반영됩니다.';
      });
    } catch (e) {
      setState(() { _saveResult = '❌ 저장 실패: $e'; });
    } finally {
      setState(() { _isSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 설명 ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A3A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3A3A6A)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, color: Color(0xFF6C63FF), size: 16),
                  SizedBox(width: 6),
                  Text('Track 1 — 출전표 강제 인젝션',
                    style: TextStyle(color: Color(0xFF9090CC), fontSize: 13,
                        fontWeight: FontWeight.bold)),
                ]),
                SizedBox(height: 6),
                Text(
                  'KRA 공식 출전표를 직접 보고 아래 폼에 입력하면\n'
                  'RaceScheduleCache에 즉시 저장됩니다.\n'
                  '저장 후 앱 화면 새로고침 시 API 응답과 동일하게 반영됩니다.',
                  style: TextStyle(color: Color(0xFF7070AA), fontSize: 11,
                      height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 경주 기본 정보 ─────────────────────────────────────────
          _sectionTitle('경주 기본 정보'),
          _row2([
            _field('경주장 코드', _venueCtrl, hint: '1=서울 2=부경 3=제주'),
            _field('날짜 (YYYYMMDD)', _dateCtrl, hint: '20260524'),
          ]),
          _row2([
            _field('경주번호', _raceNoCtrl, hint: '1~12'),
            _field('출발시간 (HH:MM)', _startTimeCtrl, hint: '10:35'),
          ]),
          _row2([
            _field('거리(m)', _distanceCtrl, hint: '1200'),
            _field('출전두수', _totalHorsesCtrl, hint: '10'),
          ]),
          _row2([
            _field('경주조건', _conditionCtrl, hint: '국6등급'),
            _field('주로상태', _trackCondCtrl, hint: '양호'),
          ]),
          _field('등급', _gradeCtrl, hint: '국6등급', fullWidth: true),

          // ── 특별경주 토글 ──────────────────────────────────────────
          const SizedBox(height: 8),
          Row(children: [
            Switch(
              value: _isSpecial,
              onChanged: (v) => setState(() => _isSpecial = v),
              activeThumbColor: const Color(0xFF9C27B0),
            ),
            const Text('특별경주', style: TextStyle(color: Color(0xFFCE93D8))),
            if (_isSpecial) ...[
              const SizedBox(width: 12),
              Expanded(child: _field('특별경주명', _specialNameCtrl,
                  hint: '제21회 부산광역시장배 (GradeII)', fullWidth: true)),
            ],
          ]),

          const SizedBox(height: 16),

          // ── 저장 결과 ──────────────────────────────────────────────
          if (_saveResult.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _saveResult.startsWith('✅')
                    ? const Color(0xFF1A3A1A) : const Color(0xFF3A1A1A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _saveResult.startsWith('✅')
                      ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
                ),
              ),
              child: Text(_saveResult,
                style: TextStyle(
                  color: _saveResult.startsWith('✅')
                      ? const Color(0xFF81C784) : const Color(0xFFEF9A9A),
                  fontSize: 12, height: 1.5,
                )),
            ),

          // ── 저장 버튼 ──────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isSaving ? null : _saveInjection,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_alt),
              label: Text(_isSaving ? '저장 중...' : '캐시에 강제 저장 (인젝션)'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(
        color: Color(0xFF9090CC), fontSize: 13, fontWeight: FontWeight.bold)),
  );

  Widget _field(String label, TextEditingController ctrl,
      {String hint = '', bool fullWidth = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF7070AA), fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: Color(0xFFE0E0FF), fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF444466)),
            filled: true,
            fillColor: const Color(0xFF1A1A3A),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF3A3A6A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF3A3A6A)),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _row2(List<Widget> children) => Row(
    children: children.map((w) => Expanded(child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: w,
    ))).toList(),
  );
}

// ══════════════════════════════════════════════════════════════════════════
//  Tab 2: 새벽 API 벌크 싱크
// ══════════════════════════════════════════════════════════════════════════
class _BulkSyncTab extends StatefulWidget {
  const _BulkSyncTab();
  @override
  State<_BulkSyncTab> createState() => _BulkSyncTabState();
}

class _BulkSyncTabState extends State<_BulkSyncTab> {
  final _sync   = KraBulkSyncService();
  final _binder = KraBulkDataBinder();
  BulkSyncStatus?       _status;
  BulkSyncResult?       _lastResult;
  BulkDataBinderDiagnostic? _diagnostic;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _loadDiagnostic();
    // 진행 콜백 등록
    _sync.onProgress = (p) {
      if (mounted) setState(() {});
    };
  }

  Future<void> _loadStatus() async {
    final s = await _sync.getStatus();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _loadDiagnostic() async {
    final d = await _binder.getDiagnostic();
    if (mounted) setState(() => _diagnostic = d);
  }

  Future<void> _runNow() async {
    setState(() { _loading = true; _lastResult = null; });
    final result = await _sync.runBulkSyncNow();
    if (mounted) {
      setState(() {
        _loading = false;
        _lastResult = result;
      });
      await _loadStatus();
      await _loadDiagnostic(); // 바인딩 진단 갱신
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 설명 ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A3A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3A3A6A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.schedule, color: Color(0xFF6C63FF), size: 16),
                  SizedBox(width: 6),
                  Text('Track 2 — 새벽 API 벌크 싱크',
                    style: TextStyle(color: Color(0xFF9090CC), fontSize: 13,
                        fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 6),
                Text(
                  '매일 새벽 02:00~05:00 자동 실행\n'
                  '23개 공공데이터 API를 3~5초 딜레이로 순차 호출\n'
                  '수집 데이터는 7일간 로컬 캐시에 보존됩니다.',
                  style: const TextStyle(color: Color(0xFF7070AA),
                      fontSize: 11, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 현황 카드 ──────────────────────────────────────────────
          if (s != null) ...[
            _infoCard('마지막 실행', s.lastRunLabel, Icons.history),
            _infoCard('오늘 수집 완료',
              '${s.cachedApiCount} / ${s.totalApiCount}개 API',
              Icons.cloud_done),
            _infoCard('다음 수집 창',
              s.nextWindowLabel, Icons.access_time),
            if (s.lastCompletedCount > 0 || s.lastFailedCount > 0)
              _infoCard('최근 결과',
                '성공 ${s.lastCompletedCount}개 / 실패 ${s.lastFailedCount}개',
                Icons.bar_chart,
                color: s.lastFailedCount > 0
                    ? const Color(0xFFFF7043) : const Color(0xFF66BB6A)),
          ],

          // ── 진행 중 표시 ───────────────────────────────────────────
          if (_sync.isRunning) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D2A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2A5A3A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: Color(0xFF66BB6A))),
                    const SizedBox(width: 8),
                    Text('수집 중: ${_sync.currentApi}',
                      style: const TextStyle(color: Color(0xFF81C784), fontSize: 12)),
                  ]),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _sync.progress,
                    backgroundColor: const Color(0xFF1A3A2A),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF66BB6A)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_sync.completedApis} / ${_sync.totalApis}개 완료',
                    style: const TextStyle(color: Color(0xFF7070AA), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // ── 즉시 실행 버튼 ─────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E4A2A),
                foregroundColor: const Color(0xFF81C784),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                side: const BorderSide(color: Color(0xFF2E6A3A)),
              ),
              onPressed: (_loading || _sync.isRunning) ? null : _runNow,
              icon: (_loading || _sync.isRunning)
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF81C784)))
                  : const Icon(Icons.play_arrow),
              label: Text((_loading || _sync.isRunning)
                  ? '수집 중...' : '지금 즉시 수집 실행'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '* 새벽 시간대가 아닐 때 수동으로 수집을 트리거합니다.\n'
            '* 오늘 이미 수집된 API는 자동 스킵됩니다.',
            style: TextStyle(color: Color(0xFF555580), fontSize: 10, height: 1.5),
          ),

          // ── 결과 표시 ──────────────────────────────────────────────
          if (_lastResult != null) ...[
            const SizedBox(height: 16),
            _sectionTitle('수집 결과'),
            ..._lastResult!.details.map((r) => _resultRow(r)),
          ],

          // ── 물리 엔진 바인딩 진단 카드 ────────────────────────────
          if (_diagnostic != null) ...[const SizedBox(height: 16), _bindingDiagCard(_diagnostic!)],

          // ── API 목록 ───────────────────────────────────────────────
          const SizedBox(height: 16),
          _sectionTitle('수집 대상 23개 API'),
          ...KraBulkSyncService.apiTargets.asMap().entries.map((e) =>
            _apiListRow(e.key + 1, e.value),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _infoCard(String label, String value, IconData icon,
      {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A2A4A)),
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: color ?? const Color(0xFF6C63FF)),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(
            color: Color(0xFF7070AA), fontSize: 12)),
        Expanded(child: Text(value, style: TextStyle(
            color: color ?? const Color(0xFFE0E0FF),
            fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _resultRow(BulkApiResult r) => Container(
    margin: const EdgeInsets.only(bottom: 2),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: r.skipped ? const Color(0xFF12122A)
          : (r.success ? const Color(0xFF0D1A0D) : const Color(0xFF1A0D0D)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(children: [
      Text(r.statusIcon, style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 6),
      Expanded(child: Text('${r.apiId}: ${r.apiName}',
        style: const TextStyle(color: Color(0xFFB0B0CC), fontSize: 11))),
      Text(r.success ? '${r.recordCount}건' : r.message.substring(
          0, r.message.length.clamp(0, 30)),
        style: TextStyle(
          color: r.success ? const Color(0xFF81C784) : const Color(0xFFEF9A9A),
          fontSize: 10)),
    ]),
  );

  Widget _apiListRow(int idx, BulkApiTarget t) => Container(
    margin: const EdgeInsets.only(bottom: 2),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    child: Row(children: [
      Container(
        width: 22, height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A3A),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text('$idx', style: const TextStyle(
            color: Color(0xFF8888BB), fontSize: 10)),
      ),
      const SizedBox(width: 8),
      Text(t.id, style: const TextStyle(
          color: Color(0xFF6C63FF), fontSize: 11,
          fontFamily: 'monospace')),
      const SizedBox(width: 8),
      Expanded(child: Text(t.name, style: const TextStyle(
          color: Color(0xFF9090CC), fontSize: 11))),
      if (t.needsDate)
        const Text('날짜필요', style: TextStyle(
            color: Color(0xFF444466), fontSize: 9)),
    ]),
  );

  Widget _bindingDiagCard(BulkDataBinderDiagnostic d) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: d.bindingReady
            ? const Color(0xFF0D2A1A) : const Color(0xFF1A1A0D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: d.bindingReady
              ? const Color(0xFF2A5A3A) : const Color(0xFF4A4A1A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              d.bindingReady ? Icons.link : Icons.link_off,
              size: 15,
              color: d.bindingReady
                  ? const Color(0xFF66BB6A) : const Color(0xFFFFCC02),
            ),
            const SizedBox(width: 6),
            Text('물리 엔진 바인딩 진단',
              style: TextStyle(
                color: d.bindingReady
                    ? const Color(0xFF81C784) : const Color(0xFFFFCC02),
                fontSize: 12, fontWeight: FontWeight.bold,
              )),
          ]),
          const SizedBox(height: 6),
          Text(d.summary,
            style: TextStyle(
              color: d.bindingReady
                  ? const Color(0xFF66BB6A) : const Color(0xFFB0A030),
              fontSize: 11,
            )),
          if (d.availableApis.isNotEmpty) ...[const SizedBox(height: 4),
            Text('가용: ${d.availableApis.join(', ')}',
              style: const TextStyle(color: Color(0xFF4A7A5A), fontSize: 10)),
          ],
          if (d.missingApis.isNotEmpty) ...[const SizedBox(height: 2),
            Text('미수집: ${d.missingApis.join(', ')}',
              style: const TextStyle(color: Color(0xFF7A5A1A), fontSize: 10)),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(
        color: Color(0xFF9090CC), fontSize: 13,
        fontWeight: FontWeight.bold)),
  );
}

// ══════════════════════════════════════════════════════════════════════════
//  Tab 3: API 에러 로그 뷰어 + Export
// ══════════════════════════════════════════════════════════════════════════
class _ErrorLogTab extends StatefulWidget {
  const _ErrorLogTab();
  @override
  State<_ErrorLogTab> createState() => _ErrorLogTabState();
}

// 화이트리스트 신청 대상 4대 핵심 API
const List<String> _whitelistTargetApis = [
  'API187',       // 경마경주정보
  'API26_2',      // 출전표 상세정보
  'API4_3',       // 경주기록 (RACE RESULT)
  'trnweekentry', // 조교사 차주 출전 예정마
];

class _ErrorLogTabState extends State<_ErrorLogTab> {
  List<ApiErrorLogEntry> _logs     = [];
  List<ApiErrorLogEntry> _filtered = [];
  bool    _loading            = true;
  String  _exportResult       = '';
  bool    _showWhitelistOnly  = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final logs = await RaceScheduleCache().getApiErrorLogs(limit: 100);
    if (mounted) {
      setState(() {
        _logs = logs;
        _applyFilter();
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    if (!_showWhitelistOnly) {
      _filtered = List.from(_logs);
    } else {
      _filtered = _logs.where((e) =>
        _whitelistTargetApis.any((id) => e.apiName.contains(id))
      ).toList();
    }
  }

  /// kra_api_error_dump.log CSV 내보내기 (클립보드)
  Future<void> _exportToCsv({bool whitelistOnly = false}) async {
    final allLogs = await RaceScheduleCache().getApiErrorLogs(limit: 100);
    final logs = whitelistOnly
        ? allLogs.where((e) =>
            _whitelistTargetApis.any((id) => e.apiName.contains(id))).toList()
        : allLogs;

    final buf = StringBuffer();
    buf.writeln('# KRA API Error Dump — kra_api_error_dump.log');
    buf.writeln('# Generated: ${DateTime.now().toIso8601String()}');
    if (whitelistOnly) {
      buf.writeln('# Mode: 화이트리스트 신청용 4대 핵심 API 필터');
      buf.writeln('# Target APIs: ${_whitelistTargetApis.join(", ")}');
    }
    buf.writeln('# Total: ${logs.length} entries');
    buf.writeln('#');
    buf.writeln('Timestamp,API,StatusCode,ErrorBody,RequestURL,KeyNote,EncodingNote');
    for (final e in logs) {
      final body = e.errorBody.replaceAll('"', "'");
      buf.writeln(
        '"${e.timestamp.toIso8601String()}",'
        '"${e.apiName}",'
        '"${e.statusCode}",'
        '"$body",'
        '"${e.requestUrl}",'
        '"${e.keyNote}",'
        '"${e.encodingNote}"',
      );
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      setState(() {
        _exportResult = '✅ ${logs.length}건 복사 완료.\n'
            '${whitelistOnly ? "[화이트리스트 필터] " : ""}'
            'kra_api_error_dump.log 저장 후 신청서에 첨부하세요.';
      });
    }
  }

  Future<void> _clearLogs() async {
    await RaceScheduleCache().clearApiErrorLogs();
    await _loadLogs();
    if (mounted) setState(() => _exportResult = '🗑️ 에러 로그 초기화 완료');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── 화이트리스트 신청용 배너 ──────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF1A0D2A),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.verified_user, size: 14, color: Color(0xFFCE93D8)),
                SizedBox(width: 6),
                Text('화이트리스트 신청 대상 4대 핵심 API',
                  style: TextStyle(color: Color(0xFFCE93D8), fontSize: 12,
                      fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 4),
              Row(children: _whitelistTargetApis.map((id) => Container(
                margin: const EdgeInsets.only(right: 6, bottom: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A1A4A),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF7B1FA2)),
                ),
                child: Text(id, style: const TextStyle(
                    color: Color(0xFFCE93D8), fontSize: 10,
                    fontFamily: 'monospace')),
              )).toList()),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFCE93D8),
                      side: const BorderSide(color: Color(0xFF7B1FA2)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () => _exportToCsv(whitelistOnly: true),
                    icon: const Icon(Icons.filter_alt, size: 14),
                    label: const Text('신청서 첨부용 로그만 내보내기', style: TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 8),
                // 화이트리스트 필터 토글
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showWhitelistOnly = !_showWhitelistOnly;
                      _applyFilter();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: _showWhitelistOnly
                          ? const Color(0xFF3A1A4A) : const Color(0xFF1A1A3A),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _showWhitelistOnly
                            ? const Color(0xFF7B1FA2) : const Color(0xFF3A3A6A),
                      ),
                    ),
                    child: Icon(
                      _showWhitelistOnly
                          ? Icons.filter_list_off : Icons.filter_list,
                      size: 18,
                      color: _showWhitelistOnly
                          ? const Color(0xFFCE93D8) : const Color(0xFF8888BB),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),

        // ── 상단 툴바 ─────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF12122A),
          child: Column(
            children: [
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A2A3A),
                      foregroundColor: const Color(0xFF64B5F6),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: _exportToCsv,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('전체 CSV 내보내기 (클립보드)'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFF8888BB)),
                  onPressed: _loadLogs,
                  tooltip: '새로고침',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFEF5350)),
                  onPressed: _clearLogs,
                  tooltip: '로그 초기화',
                ),
              ]),
              if (_exportResult.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _exportResult.startsWith('✅')
                        ? const Color(0xFF0D2A0D) : const Color(0xFF1A1A0D),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(_exportResult,
                    style: const TextStyle(
                        color: Color(0xFF81C784), fontSize: 11, height: 1.4)),
                ),
              ],
            ],
          ),
        ),

        // ── 로그 카운터 ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF0E0E20),
          child: Row(children: [
            Text(
              _showWhitelistOnly
                  ? '📋 화이트리스트 API ${_filtered.length}건'
                  : '에러 로그 ${_filtered.length}건 (최신 100건)',
              style: const TextStyle(color: Color(0xFF555580), fontSize: 11),
            ),
            const Spacer(),
            if (_showWhitelistOnly)
              const Text('핵심 4개 API만', style: TextStyle(
                  color: Color(0xFF7B1FA2), fontSize: 10,
                  fontWeight: FontWeight.bold))
            else
              const Text('최신순', style: TextStyle(
                  color: Color(0xFF444466), fontSize: 10)),
          ]),
        ),

        // ── 로그 목록 ─────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(
                  color: Color(0xFF6C63FF)))
              : _filtered.isEmpty
                  ? Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _showWhitelistOnly
                              ? Icons.check_circle_outline
                              : Icons.check_circle_outline,
                          color: const Color(0xFF66BB6A), size: 36),
                        SizedBox(height: 8),
                        Text(
                          _showWhitelistOnly
                              ? '4대 핵심 API 에러 없음 (양호)'
                              : '에러 로그 없음',
                          style: const TextStyle(
                              color: Color(0xFF555580), fontSize: 13)),
                      ],
                    ))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) => _logCard(_filtered[i]),
                    ),
        ),
      ],
    );
  }

  Widget _logCard(ApiErrorLogEntry e) {
    final isTimeout = e.isTimeout;
    final is500 = e.is500;
    final isWhitelistApi = _whitelistTargetApis.any(
        (id) => e.apiName.contains(id));
    final borderColor = is500
        ? const Color(0xFFEF5350)
        : (isTimeout ? const Color(0xFFFF9800)
            : (isWhitelistApi ? const Color(0xFF7B1FA2) : const Color(0xFF3A3A6A)));
    final statusColor = is500
        ? const Color(0xFFEF9A9A)
        : (isTimeout ? const Color(0xFFFFCC80) : const Color(0xFF9090CC));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(e.timeLabel,
              style: const TextStyle(color: Color(0xFF555580), fontSize: 10)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: borderColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(e.statusLabel,
                style: TextStyle(color: statusColor, fontSize: 10,
                    fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(e.apiName,
              style: const TextStyle(color: Color(0xFF8888BB), fontSize: 11),
              overflow: TextOverflow.ellipsis)),
            if (isWhitelistApi) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A1A4A),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFF7B1FA2)),
                ),
                child: const Text('WL', style: TextStyle(
                    color: Color(0xFFCE93D8), fontSize: 9,
                    fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
          const SizedBox(height: 4),
          Text(e.errorBody,
            style: const TextStyle(color: Color(0xFFAA7070), fontSize: 10,
                height: 1.4),
            maxLines: 2, overflow: TextOverflow.ellipsis),
          if (e.requestUrl.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(e.requestUrl,
              style: const TextStyle(color: Color(0xFF444466), fontSize: 9),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          if (e.encodingNote.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text('▸ ${e.encodingNote}',
              style: const TextStyle(color: Color(0xFF3A3A6A), fontSize: 9)),
          ],
        ],
      ),
    );
  }
}


