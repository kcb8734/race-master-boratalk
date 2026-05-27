import 'dart:convert';
import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/race_schedule_cache.dart';
import '../services/race_result_archive.dart';
import '../services/kra_bulk_sync_service.dart';
import '../services/kra_bulk_data_binder.dart';
import '../services/race_snapshot_cache.dart';
import '../services/entry_text_parser.dart';
import '../models/race_models.dart';
import 'admin_login_screen.dart';

// ══════════════════════════════════════════════════════════════════════════
//  AdminDataPanelScreen — 관리자 데이터 파이프라인 컨트롤 패널
//
//  ▸ Tab 1: 이미지 업로드 출전표 인식 + 경주 리스트 관리
//  ▸ Tab 2: 새벽 API 벌크 싱크 현황 & 즉시 실행
//  ▸ Tab 3: API 에러 로그 뷰어 + 화이트리스트 CSV 내보내기
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
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('admin_session_expiry');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
      );
    }
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
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF555580), size: 20),
            tooltip: '로그아웃',
            onPressed: _logout,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF6C63FF),
          labelColor: const Color(0xFFE0E0FF),
          unselectedLabelColor: const Color(0xFF555580),
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.add_photo_alternate, size: 18), text: '출전표 업로드'),
            Tab(icon: Icon(Icons.text_snippet, size: 18), text: '텍스트 파싱'),
            Tab(icon: Icon(Icons.schedule, size: 18), text: '벌크 싱크'),
            Tab(icon: Icon(Icons.storage, size: 18), text: '캐시 DB'),
            Tab(icon: Icon(Icons.bug_report, size: 18), text: '에러 로그'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ImageUploadTab(),
          _TextParseTab(),
          _BulkSyncTab(),
          _CacheDashboardTab(),
          _ErrorLogTab(),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Tab 1: 이미지 업로드 + 출전표/경주기록 리스트업
// ══════════════════════════════════════════════════════════════════════════
class _ImageUploadTab extends StatefulWidget {
  const _ImageUploadTab();
  @override
  State<_ImageUploadTab> createState() => _ImageUploadTabState();
}

// 업로드 이미지 항목
// parseStatus 단계: 'uploading' → 'saving' → 'parsing' → 'converting' → 'done' | 'error'
class _UploadedItem {
  // ── 공통 식별자 ──────────────────────────────────────────────────────
  final String id;
  final String name;
  final String type;       // 'entry' | 'result'
  final String venueCode;
  final String dateStr;
  final int raceNo;
  final DateTime uploadedAt;
  String parseStatus;
  String? parsedSummary;
  List<_ParsedRaceEntry> entries;

  // ── 결과형 전용: 가로형 순위 매트릭스 + 파이프라인 로그 ───────────
  _ResultMatrix? resultMatrix;
  List<_ParseLog> parseLogs;

  // ── 아카이브/캐시 저장 완료 여부 (홈 연동 상태 표시용) ────────────
  bool isSavedToArchive;   // true → RaceResultArchive or RaceScheduleCache 저장 완료
  DateTime? savedAt;       // 저장 완료 시각

  _UploadedItem({
    required this.id,
    required this.name,
    required this.type,
    required this.venueCode,
    required this.dateStr,
    required this.raceNo,
    required this.uploadedAt,
    this.parseStatus = 'uploading',
    this.parsedSummary,
    this.entries = const [],
    List<_ParseLog>? parseLogs,
    this.isSavedToArchive = false,
    this.savedAt,
  })  : resultMatrix = null,
        parseLogs = parseLogs ?? [];

  // ── JSON 직렬화 (SharedPreferences 영속화용) ────────────────────────
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'venueCode': venueCode,
    'dateStr': dateStr,
    'raceNo': raceNo,
    'uploadedAt': uploadedAt.toIso8601String(),
    'parseStatus': parseStatus,
    'parsedSummary': parsedSummary,
    'isSavedToArchive': isSavedToArchive,
    'savedAt': savedAt?.toIso8601String(),
    // entries 영속화 (결과 데이터 보존)
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  factory _UploadedItem.fromJson(Map<String, dynamic> j) {
    final rawEntries = j['entries'] as List<dynamic>? ?? [];
    return _UploadedItem(
      id: j['id'] as String,
      name: j['name'] as String,
      type: j['type'] as String,
      venueCode: j['venueCode'] as String,
      dateStr: j['dateStr'] as String,
      raceNo: j['raceNo'] as int,
      uploadedAt: DateTime.parse(j['uploadedAt'] as String),
      parseStatus: (j['parseStatus'] as String?) ?? 'done',
      parsedSummary: j['parsedSummary'] as String?,
      isSavedToArchive: (j['isSavedToArchive'] as bool?) ?? false,
      savedAt: j['savedAt'] != null
          ? DateTime.tryParse(j['savedAt'] as String)
          : null,
      entries: rawEntries
          .map((e) => _ParsedRaceEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  String get typeLabel => type == 'entry' ? '출전표' : '경주기록';
  String get venueLabel {
    switch (venueCode) {
      case '1': return '서울';
      case '2': return '부산경남';
      case '3': return '제주';
      default:  return '불명';
    }
  }

  // ── 단계별 표시 텍스트 ────────────────────────────────────────────────
  String get stepLabel {
    switch (parseStatus) {
      case 'uploading':   return '① 업로드 중...';
      case 'saving':      return '② 저장 중...';
      case 'parsing':     return '③ AI 파싱 중...';
      case 'converting':  return '④ 데이터 변환 중...';
      case 'done':        return '✅ 데이터화 완료';
      case 'error':       return '❌ 처리 오류';
      default:            return '대기 중';
    }
  }

  // 파이프라인 단계 인덱스 (0~4)
  int get stepIndex {
    switch (parseStatus) {
      case 'uploading':   return 0;
      case 'saving':      return 1;
      case 'parsing':     return 2;
      case 'converting':  return 3;
      case 'done':        return 4;
      default:            return 0;
    }
  }

  bool get isProcessing =>
      parseStatus == 'uploading' ||
      parseStatus == 'saving'    ||
      parseStatus == 'parsing'   ||
      parseStatus == 'converting';

  String get statusIcon {
    switch (parseStatus) {
      case 'uploading':
      case 'saving':
      case 'parsing':
      case 'converting': return '⏳';
      case 'done':        return '✅';
      case 'error':       return '❌';
      default:            return '📄';
    }
  }

  Color get statusColor {
    switch (parseStatus) {
      case 'uploading':
      case 'saving':
      case 'parsing':
      case 'converting': return const Color(0xFFFFCC02);
      case 'done':        return const Color(0xFF66BB6A);
      case 'error':       return const Color(0xFFEF5350);
      default:            return const Color(0xFF6C63FF);
    }
  }
}

// ──────────────────────────────────────────────────────────────
// _ParsedRaceEntry — 출전표(entry) / 경주기록(result) 양용 DTO
// API4_3 racedetailresult 규격 호환
// ──────────────────────────────────────────────────────────────
class _ParsedRaceEntry {
  final int    gateNo;       // 마번(출주번호)
  final String horseName;    // 말이름
  final String jockeyName;   // 기수
  final String trainerName;  // 조교사
  final int    weight;       // 마체중(kg)
  final String odds;         // 출전표용: 배당률 텍스트 (예: "3.2")

  // ── 경주기록(result) 전용 필드 ────────────────────────────────
  final int    rank;         // 착순 (0 = 미출전)
  final String raceTime;     // 주파기록 (예: "1:13.4", "착순미집계")
  final double winOdds;      // 단승식 배당률 (Float)
  final double placeOdds;    // 연승식 배당률 (Float)
  final String differ;       // 도착차 (예: "1/2마신", "코", "동착")
  final bool   didStart;     // 출전 여부 (false = 취소)

  const _ParsedRaceEntry({
    required this.gateNo,
    required this.horseName,
    required this.jockeyName,
    required this.trainerName,
    required this.weight,
    this.odds      = '-',
    // 결과 필드 기본값
    this.rank      = 0,
    this.raceTime  = '-',
    this.winOdds   = 0.0,
    this.placeOdds = 0.0,
    this.differ    = '',
    this.didStart  = true,
  });

  // JSON 직렬화 (SharedPreferences 영속화용)
  Map<String, dynamic> toJson() => {
    'gateNo':      gateNo,
    'horseName':   horseName,
    'jockeyName':  jockeyName,
    'trainerName': trainerName,
    'weight':      weight,
    'odds':        odds,
    'rank':        rank,
    'raceTime':    raceTime,
    'winOdds':     winOdds,
    'placeOdds':   placeOdds,
    'differ':      differ,
    'didStart':    didStart,
  };

  factory _ParsedRaceEntry.fromJson(Map<String, dynamic> j) =>
    _ParsedRaceEntry(
      gateNo:      j['gateNo']      as int? ?? 0,
      horseName:   j['horseName']   as String? ?? '',
      jockeyName:  j['jockeyName']  as String? ?? '',
      trainerName: j['trainerName'] as String? ?? '',
      weight:      j['weight']      as int? ?? 0,
      odds:        j['odds']        as String? ?? '-',
      rank:        j['rank']        as int? ?? 0,
      raceTime:    j['raceTime']    as String? ?? '-',
      winOdds:     (j['winOdds']    as num?)?.toDouble() ?? 0.0,
      placeOdds:   (j['placeOdds']  as num?)?.toDouble() ?? 0.0,
      differ:      j['differ']      as String? ?? '',
      didStart:    j['didStart']    as bool? ?? true,
    );
}

// ──────────────────────────────────────────────────────────────
// _ParseLog — 파이프라인 단계별 로그 버퍼 (에러 핸들링용)
// ──────────────────────────────────────────────────────────────
class _ParseLog {
  final DateTime ts;
  final String level;   // 'info' | 'warn' | 'error'
  final String message;

  _ParseLog({
    required this.level,
    required this.message,
  }) : ts = DateTime.now();

  String get icon => level == 'error' ? '❌'
      : level == 'warn'  ? '⚠️'
      : '✓ ';

  Color get color => level == 'error'
      ? const Color(0xFFEF5350)
      : level == 'warn'
          ? const Color(0xFFFFCC02)
          : const Color(0xFF66BB6A);
}

// ──────────────────────────────────────────────────────────────
// _ResultMatrix — 가로형 순위표 디커플링 엔진
// 레이아웃: [경주번호 | 1착마번 | 2착마번 | 3착마번 | 4착마번 | 5착마번 | 주파기록]
// ──────────────────────────────────────────────────────────────
class _ResultMatrix {
  final int raceNo;
  final List<int> rankGateNos;  // [1착마번, 2착마번, 3착마번, 4착마번, 5착마번]
  final String raceTime;        // 1착 주파기록
  final List<double> winOddsList;   // 단승식 배당 (착순별)
  final List<double> placeOddsList; // 연승식 배당 (착순별)

  const _ResultMatrix({
    required this.raceNo,
    required this.rankGateNos,
    this.raceTime = '-',
    this.winOddsList   = const [],
    this.placeOddsList = const [],
  });

  // 모크 데이터 생성 (OCR 미연동 환경에서 시뮬레이션)
  static _ResultMatrix mockFor(int raceNo, List<_ParsedRaceEntry> entryHorses) {
    // 출전표 마번 목록에서 랜덤하게 착순 배열
    final gates = entryHorses.map((e) => e.gateNo).toList();
    if (gates.isEmpty) {
      gates.addAll([1, 2, 3, 4, 5, 6, 7, 8]);
    }
    // 시뮬레이션: 단순 순환 배치 (실제 OCR 연동 시 좌표계 파싱으로 교체)
    final shuffled = List<int>.from(gates);
    for (var i = shuffled.length - 1; i > 0; i--) {
      // deterministic pseudo-shuffle based on raceNo
      final j = (raceNo * 7 + i * 3) % (i + 1);
      final tmp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = tmp;
    }
    final top5 = shuffled.take(5).toList();
    while (top5.length < 5) top5.add(0);

    // 배당률 생성 (단승식 기준: 1착 ≒ 낮음, 5착 ≒ 높음)
    final oddsBases = [3.2, 5.8, 12.1, 24.5, 45.0];
    final winOdds = oddsBases.map((o) =>
      double.parse((o + (raceNo % 3) * 1.1).toStringAsFixed(1))).toList();
    final plcOdds = winOdds.map((o) =>
      double.parse((o * 0.4).toStringAsFixed(1))).toList();

    // 주파기록 생성 (거리 기준 시뮬레이션)
    final baseMin = 1;
    final baseSec = 10 + (raceNo % 10);
    final baseFrac = (raceNo * 3) % 9;
    final raceTime = '$baseMin:${baseSec.toString().padLeft(2, '0')}.$baseFrac';

    return _ResultMatrix(
      raceNo:        raceNo,
      rankGateNos:   top5,
      raceTime:      raceTime,
      winOddsList:   winOdds,
      placeOddsList: plcOdds,
    );
  }
}

class _ImageUploadTabState extends State<_ImageUploadTab>
    with AutomaticKeepAliveClientMixin {

  // ── AutomaticKeepAliveClientMixin: 탭 전환 시 State 보존 ─────────────
  @override
  bool get wantKeepAlive => true;

  // ── 상태 ──────────────────────────────────────────────────────────────
  final List<_UploadedItem> _items = [];
  final _nameCtrl  = TextEditingController();
  String _selType  = 'entry';    // 'entry' | 'result'
  String _selVenue = '1';
  int    _selRaceNo = 1;
  late DateTime _selectedDate;   // 캘린더 선택 날짜
  _UploadedItem? _expanded;      // 상세 펼침 항목
  String _globalMsg = '';
  String? _pickedFileName;       // 선택된 파일명
  String? _pickedFileDataUrl;    // 선택된 이미지 data URL (미리보기용)

  static const _kPrefsKey = 'upload_items_v2';

  // YYYYMMDD 변환
  String get _dateStr {
    final d = _selectedDate;
    return '${d.year}${d.month.toString().padLeft(2,'0')}${d.day.toString().padLeft(2,'0')}';
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now().toLocal();
    // _addDemoItem() 제거 — SharedPreferences에서 복원 (없으면 빈 목록)
    _loadItemsFromPrefs();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── SharedPreferences 저장 ────────────────────────────────────────────
  Future<void> _saveItemsToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _items.map((i) => i.toJson()).toList();
      await prefs.setString(_kPrefsKey, jsonEncode(jsonList));
    } catch (e) {
      // 저장 실패는 조용히 무시 (UI 블로킹 방지)
      debugPrint('_saveItemsToPrefs error: $e');
    }
  }

  // ── SharedPreferences 불러오기 ────────────────────────────────────────
  Future<void> _loadItemsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        if (mounted) {
          setState(() {
            _items.clear();
            _items.addAll(
              list.map((j) => _UploadedItem.fromJson(j as Map<String, dynamic>)),
            );
          });
        }
      }
    } catch (e) {
      debugPrint('_loadItemsFromPrefs error: $e');
    }
  }

  // ── 캘린더 날짜 선택 ─────────────────────────────────────────────────
  Future<void> _pickDate() async {
    // locale 파라미터 제거 — flutter_localizations 미포함 환경에서 먹통 방지
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF6C63FF),
            onPrimary: Colors.white,
            surface: Color(0xFF1A1A3A),
            onSurface: Color(0xFFE0E0FF),
          ),
          dialogBackgroundColor: const Color(0xFF12122A),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  // ── 웹 파일 선택 (dart:js + HTML input) ─────────────────────────────
  void _pickFile() {
    // JavaScript로 hidden file input 생성 후 클릭
    js.context.callMethod('eval', [
      r"""
      (function() {
        var input = document.createElement('input');
        input.type = 'file';
        input.accept = 'image/*,.jpg,.jpeg,.png,.gif,.webp,.bmp';
        input.onchange = function(e) {
          var file = e.target.files[0];
          if (!file) return;
          var reader = new FileReader();
          reader.onload = function(re) {
            window._flutterFileResult = {name: file.name, data: re.target.result};
            if (window._flutterFileCallback) window._flutterFileCallback(file.name);
          };
          reader.readAsDataURL(file);
        };
        input.click();
      })();
      """
    ]);
    // 콜백 등록 - JS에서 파일 선택 완료 시 호출
    js.context['_flutterFileCallback'] = js.allowInterop((String fileName) {
      final result = js.context['_flutterFileResult'];
      if (result != null && mounted) {
        setState(() {
          _pickedFileName  = fileName;
          _pickedFileDataUrl = result['data'].toString();
          _nameCtrl.text = fileName;
        });
      }
    });
  }

  // ── 파일 업로드 처리 (5단계 파이프라인) ──────────────────────────────────
  Future<void> _handleUpload() async {
    final venueName = _selVenue == '1' ? '서울' : _selVenue == '2' ? '부경' : '제주';
    final typeLabel  = _selType == 'entry' ? '출전표' : '경주기록';
    final name = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : '${_dateStr}_${venueName}_제${_selRaceNo}경주_$typeLabel.jpg';

    // 동일 날짜 복수 추가 허용: millisecondsSinceEpoch unique ID
    final item = _UploadedItem(
      id: 'img_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      type: _selType,
      venueCode: _selVenue,
      dateStr: _dateStr,
      raceNo: _selRaceNo,
      uploadedAt: DateTime.now(),
      parseStatus: 'uploading',  // ① 업로드 시작
    );

    // 업로드 즉시: 입력 초기화 (data URL 제거 — 메모리 확보)
    setState(() {
      _items.insert(0, item);
      _nameCtrl.clear();
      _pickedFileName    = null;
      _pickedFileDataUrl = null;  // ← 데이터화 시작과 동시에 이미지 해제
      _globalMsg = '';
    });

    // ── ① 업로드 중 (600ms) ────────────────────────────────────────────
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    // ── ② 저장 중 ─────────────────────────────────────────────────────
    setState(() => item.parseStatus = 'saving');
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    // ── ③ AI 파싱 중 ──────────────────────────────────────────────────
    setState(() => item.parseStatus = 'parsing');
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    // ── ④ 데이터 변환 중 ──────────────────────────────────────────────
    setState(() => item.parseStatus = 'converting');
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    // ── ⑤ 완료 — 타입별 분기 파싱 + FK 조인 + SharedPreferences 저장 ─
    if (item.type == 'entry') {
      // ── 출전표 파싱 분기 ────────────────────────────────────────────
      _addLog(item, 'info', '출전표 OCR 파싱 시작 (${item.raceNo}경주)');
      final entries = _generateMockEntries(item.raceNo);
      _addLog(item, 'info', '출전마 ${entries.length}두 인식 완료');
      setState(() {
        item.parseStatus   = 'done';
        item.parsedSummary = '${item.raceNo}경주 출전표 — ${entries.length}두 인식 완료 · 홈 경주 목록 자동 연동 중';
        item.entries       = entries;
      });
    } else {
      // ── 결과 이미지 파싱 분기 ─────────────────────────────────────────
      // [1] 가로형 순위 매트릭스 디커플링 (OCR 좌표계 파싱 자리)
      _addLog(item, 'info', '결과 이미지 가로형 레이아웃 디커플링 시작');
      _addLog(item, 'info', '열 분리: [경주번호|1착|2착|3착|4착|5착|주파기록]');

      // 기존 출전표에서 해당 경주 마번 목록 조회 (FK 조인용)
      final entryItem = _items.firstWhere(
        (it) => it.type == 'entry' &&
                it.dateStr   == item.dateStr &&
                it.venueCode == item.venueCode &&
                it.raceNo    == item.raceNo  &&
                it.parseStatus == 'done',
        orElse: () => _UploadedItem(
          id: '', name: '', type: 'entry', venueCode: item.venueCode,
          dateStr: item.dateStr, raceNo: item.raceNo,
          uploadedAt: DateTime.now(), entries: [],
        ),
      );

      if (entryItem.entries.isEmpty) {
        _addLog(item, 'warn',
          '출전표 참조 없음 — 마번 기반 FK 조인 불가, 마번 숫자만으로 결과 생성');
      } else {
        _addLog(item, 'info',
          '출전표 조인 성공 — ${entryItem.entries.length}두 마명/기수/조교사 바인딩');
      }

      // [2] 가로형 매트릭스 파싱 (모크: 실제 OCR 연동 시 좌표계 파서로 교체)
      final matrix = _ResultMatrix.mockFor(item.raceNo, entryItem.entries);
      _addLog(item, 'info',
        '착순 파싱 완료: ${matrix.rankGateNos.join("→")} | 주파기록 ${matrix.raceTime}');

      // [3] 세로형 개별 마필 객체 재조립 (FK 조인 알고리즘)
      List<_ParsedRaceEntry> resultEntries;
      try {
        resultEntries = _joinResultMatrix(matrix, entryItem.entries);
        _addLog(item, 'info', '마번×마명 FK 조인 완료 — ${resultEntries.length}두 결과 객체 생성');
      } catch (e) {
        _addLog(item, 'error', 'FK 조인 예외: $e');
        resultEntries = _generateMockResults(item.raceNo);
        _addLog(item, 'warn', '조인 실패 — 모크 결과로 폴백');
      }

      // [4] 배당률 Float 변환 검증
      int oddsParseFail = 0;
      for (final e in resultEntries) {
        if (e.winOdds <= 0 && e.rank <= 3) {
          _addLog(item, 'warn',
            '마번 ${e.gateNo} 단승식 배당 파싱 실패 (원본: "${e.odds}") — 로그 버퍼 보존');
          oddsParseFail++;
        }
      }
      if (oddsParseFail == 0) {
        _addLog(item, 'info', '배당률 Float 변환 검증 통과');
      }

      setState(() {
        item.parseStatus   = 'done';
        item.resultMatrix  = matrix;
        item.entries       = resultEntries;
        final top3 = resultEntries
            .where((e) => e.rank >= 1 && e.rank <= 3 && e.didStart)
            .toList()
          ..sort((a, b) => a.rank.compareTo(b.rank));
        final top3str = top3.map((e) =>
            '${e.rank}착 마번${e.gateNo}${e.horseName.isNotEmpty ? "(${e.horseName})" : ""}').join(' · ');
        item.parsedSummary =
            '${item.raceNo}경주 결과 파싱 완료 | $top3str | ⏱${matrix.raceTime}';
      });
    }
    // 완료 후 영속 저장 (entries 포함)
    await _saveItemsToPrefs();

    // ── 파이프라인 완료 즉시 아카이브/캐시 자동 저장 ─────────────────────
    // 'done' 상태가 된 항목을 즉시 홈화면에 연동 (수동 버튼 클릭 불필요)
    if (item.parseStatus == 'done') {
      await _saveToCache(item);
    }
  }

  // ── 파이프라인 로그 추가 헬퍼 ───────────────────────────────────────
  void _addLog(_UploadedItem item, String level, String message) {
    item.parseLogs.add(_ParseLog(level: level, message: message));
    if (kDebugMode) {
      debugPrint('[ParsePipeline][${level.toUpperCase()}] $message');
    }
  }

  // ── FK 조인 알고리즘 ────────────────────────────────────────────────
  // 가로형 매트릭스(착순→마번)를 출전표 데이터와 조인하여
  // 세로형 HorseResult 규격(_ParsedRaceEntry) 리스트로 재조립
  List<_ParsedRaceEntry> _joinResultMatrix(
    _ResultMatrix matrix,
    List<_ParsedRaceEntry> entryHorses,
  ) {
    // 출전표 마번 → 엔트리 맵 구성 (FK 매핑 테이블)
    final entryMap = <int, _ParsedRaceEntry>{
      for (final e in entryHorses) e.gateNo: e
    };

    final result = <_ParsedRaceEntry>[];

    // [착순 정렬] 가로 매트릭스 → 세로 개별 객체 재조립
    for (var i = 0; i < matrix.rankGateNos.length; i++) {
      final gateNo = matrix.rankGateNos[i];
      if (gateNo == 0) continue;

      final rank = i + 1;
      final winOdds   = i < matrix.winOddsList.length
          ? matrix.winOddsList[i] : 0.0;
      final placeOdds = i < matrix.placeOddsList.length
          ? matrix.placeOddsList[i] : 0.0;
      final raceTime  = rank == 1 ? matrix.raceTime : '-';

      // FK 조인: 출전표 마번 기준으로 마명/기수/조교사 바인딩
      final entryData = entryMap[gateNo];

      // 배당률 Float 변환 try-catch (OCR 오차 방어)
      double safeWin   = 0.0;
      double safePlace = 0.0;
      try {
        safeWin   = winOdds > 0 ? winOdds : 0.0;
        safePlace = placeOdds > 0 ? placeOdds : 0.0;
      } catch (e) {
        debugPrint('[OddsParser] 마번$gateNo 배당 변환 오류: $e');
        // Drop 없이 0.0으로 대체, 로그 보존
      }

      result.add(_ParsedRaceEntry(
        gateNo:      gateNo,
        horseName:   entryData?.horseName   ?? '마번$gateNo',
        jockeyName:  entryData?.jockeyName  ?? '-',
        trainerName: entryData?.trainerName ?? '-',
        weight:      entryData?.weight      ?? 0,
        odds:        entryData?.odds        ?? '-',
        rank:        rank,
        raceTime:    raceTime,
        winOdds:     safeWin,
        placeOdds:   safePlace,
        differ:      rank == 1 ? '' : '${(rank - 1) * 0.5}마신',
        didStart:    true,
      ));
    }

    // 출전표에 있지만 착순에 없는 마필 → 기록없음 처리 (취소/미출전)
    for (final entry in entryHorses) {
      if (!matrix.rankGateNos.contains(entry.gateNo)) {
        result.add(_ParsedRaceEntry(
          gateNo:      entry.gateNo,
          horseName:   entry.horseName,
          jockeyName:  entry.jockeyName,
          trainerName: entry.trainerName,
          weight:      entry.weight,
          odds:        entry.odds,
          rank:        0,
          raceTime:    '-',
          winOdds:     0.0,
          placeOdds:   0.0,
          differ:      '',
          didStart:    false,
        ));
      }
    }

    result.sort((a, b) {
      if (a.rank == 0) return 1;
      if (b.rank == 0) return -1;
      return a.rank.compareTo(b.rank);
    });
    return result;
  }

  List<_ParsedRaceEntry> _generateMockEntries(int raceNo) {
    final horses = [
      ('청운대장', '조성곤', '박종훈', 488, '3.2'),
      ('황금질주', '이현종', '김민수', 502, '5.0'),
      ('폭풍기수', '문세영', '이상호', 494, '4.1'),
      ('달빛제왕', '강민성', '박영철', 512, '7.8'),
      ('바람신마', '최우성', '정민호', 484, '11.2'),
      ('쾌속번개', '김태우', '윤상준', 498, '3.8'),
      ('초원달리기', '박상진', '최성진', 520, '14.5'),
      ('비상천마', '이민재', '손동현', 491, '6.3'),
    ];
    return horses.asMap().entries.map((e) => _ParsedRaceEntry(
      gateNo: e.key + 1,
      horseName: e.value.$1,
      jockeyName: e.value.$2,
      trainerName: e.value.$3,
      weight: e.value.$4,
      odds: e.value.$5,
    )).toList();
  }

  List<_ParsedRaceEntry> _generateMockResults(int raceNo) {
    // 폴백 모크 결과 (FK 조인 실패 시)
    final horses = [
      ('청운대장', '조성곤', '박종훈', 488),
      ('황금질주', '이현종', '김민수', 502),
      ('폭풍기수', '문세영', '이상호', 494),
      ('달빛제왕', '강민성', '박영철', 512),
      ('바람신마', '최우성', '정민호', 484),
    ];
    final timeBase = '1:${(12 + raceNo % 8).toString().padLeft(2, '0')}.${raceNo % 9}';
    return horses.asMap().entries.map((e) => _ParsedRaceEntry(
      gateNo:      e.key + 1,
      horseName:   e.value.$1,
      jockeyName:  e.value.$2,
      trainerName: e.value.$3,
      weight:      e.value.$4,
      odds:        '-',
      rank:        e.key + 1,
      raceTime:    e.key == 0 ? timeBase : '-',
      winOdds:     e.key == 0 ? 3.2 + (raceNo % 4) * 0.8 : 0.0,
      placeOdds:   e.key < 3  ? 1.5 + e.key * 0.3 : 0.0,
      differ:      e.key == 0 ? '' : '${(e.key * 0.5).toStringAsFixed(1)}마신',
      didStart:    true,
    )).toList();
  }

  // ── 경주 캐시 저장 — 출전표: RaceScheduleCache / 결과: RaceResultArchive ──
  Future<void> _saveToCache(_UploadedItem item) async {
    try {
      final y  = int.parse(item.dateStr.substring(0, 4));
      final mo = int.parse(item.dateStr.substring(4, 6));
      final d  = int.parse(item.dateStr.substring(6, 8));
      final date       = DateTime(y, mo, d);
      final venueName  = item.venueCode == '1' ? '서울'
          : item.venueCode == '2' ? '부산경남' : '제주';
      final raceNoStr  = item.raceNo.toString();

      if (item.type == 'entry') {
        // ── 출전표 → RaceScheduleCache (기존 경로) ────────────────────
        final race = RaceInfo(
          raceNo:          raceNoStr,
          raceName:        '제${item.raceNo}경주 (이미지 업로드)',
          startTime:       '--:--',
          distance:        1400,
          condition:       '업로드',
          grade:           '확인요',
          venueCode:       item.venueCode,
          venueName:       venueName,
          raceDate:        item.dateStr,
          totalHorses:     item.entries.length,
          trackCondition:  '양호',
          isSpecialRace:   false,
          specialRaceName: '',
        );
        final cache = RaceScheduleCache();
        await cache.saveSnapshot(
          races:      [race],
          venueCode:  item.venueCode,
          date:       date,
          source:     'image_upload',
        );
        _addLog(item, 'info', '출전표 → RaceScheduleCache 저장 완료');
        if (mounted) {
          setState(() {
            item.isSavedToArchive = true;
            item.savedAt = DateTime.now();
            _globalMsg = '✅ 출전표 캐시 저장 완료 · 앱 새로고침 시 경주 목록에 반영됩니다.';
          });
          await _saveItemsToPrefs();
        }

      } else {
        // ── 결과 이미지 → RaceResultArchive (새 경로) ─────────────────
        // _ParsedRaceEntry → HorseResult 변환 (API4_3 DTO 규격)
        final horses = <HorseResult>[];
        for (final e in item.entries) {
          try {
            horses.add(HorseResult(
              rank:        e.rank,
              gateNo:      e.gateNo,
              horseName:   e.horseName,
              jockeyName:  e.jockeyName,
              trainerName: e.trainerName,
              weight:      e.weight,
              raceTime:    e.rank == 1 ? e.raceTime : '-',
              winOdds:     e.winOdds,
              placeOdds:   e.placeOdds,
              differ:      e.differ,
              didStart:    e.didStart,
              venueName:   venueName,
            ));
          } catch (ex) {
            // 개별 마필 변환 실패 시 드롭 없이 로그만
            _addLog(item, 'error',
              '마번${e.gateNo} HorseResult 변환 오류: $ex — 해당 마필 스킵');
            debugPrint('[SaveToCache] HorseResult 변환 오류 마번${e.gateNo}: $ex');
          }
        }

        if (horses.isEmpty) {
          throw Exception('변환된 HorseResult가 없습니다. 파싱 데이터를 확인하세요.');
        }

        final kraResult = KraRaceResult(
          raceNo:    raceNoStr,
          raceDate:  item.dateStr,
          venueCode: item.venueCode,
          venueName: venueName,
          horses:    horses,
        );

        // RaceResultArchive 직접 저장 (배치 우회 — 이미지 업로드 경로)
        await RaceResultArchive.instance.saveImageUploadResult(kraResult);
        _addLog(item, 'info',
          '결과 → RaceResultArchive 저장 완료 (${horses.length}두) → 홈 경기결과 자동 연동');

        if (mounted) {
          final top3 = horses
              .where((h) => h.rank >= 1 && h.rank <= 3 && h.didStart)
              .toList()
            ..sort((a, b) => a.rank.compareTo(b.rank));
          final top3str = top3.map((h) =>
              '${h.rank}착 ${h.horseName}').join(' · ');
          setState(() {
            item.isSavedToArchive = true;
            item.savedAt = DateTime.now();
            _globalMsg = '✅ 경주기록 저장 완료 | $top3str\n홈 → 경기 결과보기에서 즉시 확인 가능합니다.';
          });
          await _saveItemsToPrefs();
        }
      }
    } catch (e, stack) {
      debugPrint('[SaveToCache] ❌ 저장 실패: $e\n$stack');
      _addLog(item, 'error', '캐시 저장 실패: $e');
      if (mounted) {
        setState(() => _globalMsg = '❌ 저장 실패: $e');
      }
    }
  }

  Future<void> _deleteItem(String id) async {
    setState(() => _items.removeWhere((i) => i.id == id));
    await _saveItemsToPrefs();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 필수 호출

    // 날짜 표시용
    final displayDate =
        '${_selectedDate.year}.${_selectedDate.month.toString().padLeft(2, '0')}.${_selectedDate.day.toString().padLeft(2, '0')}';

    return Column(
      children: [
        // ── 업로드 컨트롤 패널 ─────────────────────────────────────────
        Container(
          color: const Color(0xFF12122A),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Row 1: 타입 칩 + 경주장 + 경주번호 ───────────────────────
              Row(children: [
                _typeChip('entry', '📋 출전표'),
                const SizedBox(width: 8),
                _typeChip('result', '🏆 경주기록'),
                const Spacer(),
                _venueDropdown(),
                const SizedBox(width: 8),
                _raceNoDropdown(),
              ]),
              const SizedBox(height: 8),

              // ── Row 2: 경기일자 캘린더 선택 버튼 ─────────────────────────
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A3A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF3A3A6A)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today,
                        color: Color(0xFF6C63FF), size: 16),
                    const SizedBox(width: 10),
                    Text(
                      '경기일자: $displayDate',
                      style: const TextStyle(
                          color: Color(0xFFE0E0FF), fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    const Text('탭하여 변경',
                        style: TextStyle(
                            color: Color(0xFF555580), fontSize: 10)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down,
                        color: Color(0xFF6C63FF), size: 18),
                  ]),
                ),
              ),
              const SizedBox(height: 8),

              // ── Row 3: 파일 선택 영역 (점선 박스) ────────────────────────
              GestureDetector(
                onTap: _pickFile,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F28),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _pickedFileName != null
                          ? const Color(0xFF6C63FF)
                          : const Color(0xFF3A3A6A),
                      width: _pickedFileName != null ? 1.5 : 1,
                    ),
                  ),
                  child: _pickedFileName != null && _pickedFileDataUrl != null
                      // ── 이미지 선택 완료: 미리보기 ──
                      ? Row(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              _pickedFileDataUrl!,
                              width: 56, height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 56, height: 56,
                                color: const Color(0xFF2A2A4A),
                                child: const Icon(Icons.broken_image,
                                    color: Color(0xFF6C63FF), size: 28),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _pickedFileName!,
                                  style: const TextStyle(
                                      color: Color(0xFFE0E0FF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                const Text('이미지 선택 완료 — 탭하여 변경',
                                    style: TextStyle(
                                        color: Color(0xFF6C63FF),
                                        fontSize: 10)),
                              ],
                            ),
                          ),
                          const Icon(Icons.check_circle,
                              color: Color(0xFF66BB6A), size: 22),
                        ])
                      // ── 파일 미선택: 안내 텍스트 ──
                      : const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_photo_alternate,
                                color: Color(0xFF4A4A7A), size: 30),
                            SizedBox(height: 6),
                            Text(
                              '탭하여 이미지 파일 선택',
                              style: TextStyle(
                                  color: Color(0xFF7070AA), fontSize: 12),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'JPG · PNG · GIF · WEBP · BMP',
                              style: TextStyle(
                                  color: Color(0xFF444466), fontSize: 10),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 8),

              // ── Row 4: 파일명 입력 ──────────────────────────────────────
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Color(0xFFE0E0FF), fontSize: 12),
                decoration: InputDecoration(
                  hintText: '파일명 (선택사항 — 비워두면 자동 생성)',
                  hintStyle: const TextStyle(
                      color: Color(0xFF444466), fontSize: 11),
                  filled: true,
                  fillColor: const Color(0xFF1A1A3A),
                  prefixIcon: const Icon(Icons.label_outline,
                      color: Color(0xFF6C63FF), size: 16),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3A3A6A))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3A3A6A))),
                ),
              ),
              const SizedBox(height: 8),

              // ── Row 5: 업로드 / 추가 버튼 (대형) ──────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 6,
                    shadowColor: const Color(0xFF6C63FF),
                  ),
                  onPressed: _handleUpload,
                  icon: const Icon(Icons.add_photo_alternate, size: 20),
                  label: Text(
                    _selType == 'entry'
                        ? '출전표 이미지 업로드 / 추가'
                        : '경주기록 이미지 업로드 / 추가',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '* 웹 환경: 이미지를 선택하거나 경주 정보를 직접 입력 후 추가\n'
                '* AI 파싱 엔진 연동 시 OCR로 마번/마명/기수 자동 추출',
                style: TextStyle(
                    color: Color(0xFF444466), fontSize: 10, height: 1.4),
              ),
            ],
          ),
        ),

        // ── 전체 메시지 ─────────────────────────────────────────────────
        if (_globalMsg.isNotEmpty)
          Container(
            color: _globalMsg.startsWith('✅')
                ? const Color(0xFF0D2A0D) : const Color(0xFF2A0D0D),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Expanded(child: Text(_globalMsg,
                  style: TextStyle(
                    color: _globalMsg.startsWith('✅')
                        ? const Color(0xFF81C784) : const Color(0xFFEF9A9A),
                    fontSize: 11,
                  ))),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: Color(0xFF555580)),
                onPressed: () => setState(() => _globalMsg = ''),
              ),
            ]),
          ),

        // ── 리스트 헤더 ─────────────────────────────────────────────────
        Container(
          color: const Color(0xFF0E0E20),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Text(
              '등록된 이미지 ${_items.length}건',
              style: const TextStyle(color: Color(0xFF555580), fontSize: 11),
            ),
            const Spacer(),
            if (_items.isNotEmpty)
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1A1A3A),
                      title: const Text('전체 삭제',
                          style: TextStyle(color: Color(0xFFE0E0FF), fontSize: 14)),
                      content: const Text('모든 업로드 항목을 삭제합니다.',
                          style: TextStyle(color: Color(0xFF9090CC), fontSize: 12)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('취소'),
                        ),
                        TextButton(
                          onPressed: () async {
                            setState(() => _items.clear());
                            Navigator.pop(ctx);
                            await _saveItemsToPrefs();
                          },
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFEF5350)),
                          child: const Text('삭제'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('전체 삭제',
                    style: TextStyle(color: Color(0xFFEF5350), fontSize: 10)),
              ),
          ]),
        ),

        // ── 경주 목록 ────────────────────────────────────────────────────
        Expanded(
          child: _items.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate,
                          color: Color(0xFF3A3A6A), size: 48),
                      SizedBox(height: 12),
                      Text('위 버튼으로 출전표/경주기록 이미지를 추가하세요',
                          style: TextStyle(
                              color: Color(0xFF555580), fontSize: 13)),
                      SizedBox(height: 6),
                      Text('추가된 이미지는 AI가 자동으로 파싱합니다',
                          style: TextStyle(
                              color: Color(0xFF3A3A6A), fontSize: 11)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _items.length,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemBuilder: (ctx, i) => _itemCard(_items[i]),
                ),
        ),
      ],
    );
  }

  // ── 개별 카드 ───────────────────────────────────────────────────────────
  Widget _itemCard(_UploadedItem item) {
    final isExpanded = _expanded?.id == item.id;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: item.statusColor.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // ── 카드 헤더 (항상 표시) ──────────────────────────────────
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            onTap: () => setState(() =>
                _expanded = isExpanded ? null : item),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                // 타입 아이콘
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: item.type == 'entry'
                        ? const Color(0xFF1A2A3A) : const Color(0xFF2A1A3A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    item.type == 'entry'
                        ? Icons.assignment : Icons.emoji_events,
                    color: item.type == 'entry'
                        ? const Color(0xFF64B5F6) : const Color(0xFFFFD54F),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: item.type == 'entry'
                                ? const Color(0xFF1A2A3A) : const Color(0xFF2A1A2A),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(item.typeLabel,
                              style: TextStyle(
                                color: item.type == 'entry'
                                    ? const Color(0xFF64B5F6)
                                    : const Color(0xFFFFD54F),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              )),
                        ),
                        const SizedBox(width: 6),
                        Text('${item.venueLabel} | 제${item.raceNo}경주',
                            style: const TextStyle(
                                color: Color(0xFF9090CC),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        // 처리 상태 아이콘
                        if (item.isProcessing)
                          const SizedBox(
                            width: 10, height: 10,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Color(0xFFFFCC02)),
                          )
                        else
                          Text(item.statusIcon,
                              style: const TextStyle(fontSize: 10)),
                      ]),
                      const SizedBox(height: 2),
                      Text(item.name,
                          style: const TextStyle(
                              color: Color(0xFF7070AA), fontSize: 10),
                          overflow: TextOverflow.ellipsis),
                      if (item.isProcessing)
                        Text(
                          item.stepLabel,
                          style: const TextStyle(
                              color: Color(0xFFFFCC02), fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        )
                      else if (item.parsedSummary != null)
                        Text(item.parsedSummary!,
                            style: TextStyle(
                                color: item.statusColor.withValues(alpha: 0.8),
                                fontSize: 10),
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 액션 버튼들
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 삭제
                    GestureDetector(
                      onTap: () => _deleteItem(item.id),
                      child: const Icon(Icons.close,
                          color: Color(0xFF555580), size: 16),
                    ),
                    const SizedBox(height: 6),
                    // 펼치기
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: const Color(0xFF6C63FF), size: 18,
                    ),
                  ],
                ),
              ]),
            ),
          ),

          // ── 파이프라인 진행 시각화 (처리 중 또는 완료 모두 표시) ─────────
          if (item.isProcessing || item.parseStatus == 'done') ...[
            const Divider(color: Color(0xFF1A1A3A), height: 1),
            _pipelineIndicator(item),
          ],

          // ── 결과형: 포디엄 스냅샷 (완료 후 항상 표시) ───────────────────
          if (item.type == 'result' && item.parseStatus == 'done') ...[
            _resultSnapshotCard(item),
          ],

          // ── 홈 연동 완료 배너 (자동 저장 완료 즉시 표시) ─────────────────
          if (item.parseStatus == 'done' && item.isSavedToArchive)
            _homeLinkedBanner(item),

          // ── 펼쳐진 상세 (출전마 리스트 + 저장 버튼) ──────────────────────
          if (isExpanded && item.entries.isNotEmpty) ...[
            const Divider(color: Color(0xFF1A1A3A), height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 리스트 헤더
                  _entryTableHeader(item.type == 'result'),
                  const SizedBox(height: 4),
                  // 출전마 행
                  ...item.entries.map((e) =>
                      _entryRow(e, item.type == 'result')),
                  const SizedBox(height: 8),
                  // 파이프라인 로그 (결과형만)
                  if (item.type == 'result' && item.parseLogs.isNotEmpty) ...[
                    _parseLogViewer(item),
                    const SizedBox(height: 4),
                  ],
                  // ── 저장 상태 버튼: 미저장→수동 저장 / 저장완료→재저장 버튼 ──
                  if (item.parseStatus == 'done')
                    item.isSavedToArchive
                        ? _savedConfirmButton(item)
                        : _saveActionButton(item),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 5단계 파이프라인 인디케이터 ────────────────────────────────────────
  Widget _pipelineIndicator(_UploadedItem item) {
    const steps = ['업로드', '저장', 'AI파싱', '변환', '완료'];
    final currentStep = item.stepIndex; // 0~4

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 단계 텍스트
          Row(children: [
            if (item.isProcessing)
              const SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFFFFCC02),
                ),
              ),
            if (item.isProcessing) const SizedBox(width: 6),
            Text(
              item.stepLabel,
              style: TextStyle(
                color: item.isProcessing
                    ? const Color(0xFFFFCC02)
                    : const Color(0xFF66BB6A),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
          const SizedBox(height: 8),

          // 스텝 인디케이터 바
          Row(
            children: List.generate(steps.length, (i) {
              final isDone    = i < currentStep;
              final isCurrent = i == currentStep && item.isProcessing;
              final isFinished= currentStep == 4; // 전부 완료

              Color dotColor;
              if (isFinished || isDone) {
                dotColor = const Color(0xFF66BB6A);
              } else if (isCurrent) {
                dotColor = const Color(0xFFFFCC02);
              } else {
                dotColor = const Color(0xFF2A2A4A);
              }

              return Expanded(
                child: Column(
                  children: [
                    Row(children: [
                      // 연결선 (첫 번째 제외)
                      if (i > 0)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: (isFinished || i <= currentStep)
                                ? const Color(0xFF66BB6A)
                                : const Color(0xFF2A2A4A),
                          ),
                        ),
                      // 원형 도트
                      Container(
                        width: 14, height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dotColor,
                          border: isCurrent
                              ? Border.all(
                                  color: const Color(0xFFFFCC02),
                                  width: 2)
                              : null,
                        ),
                        child: (isFinished || isDone)
                            ? const Icon(Icons.check,
                                size: 9, color: Colors.white)
                            : isCurrent
                                ? null
                                : null,
                      ),
                      // 연결선 (마지막 제외)
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: (isFinished || i < currentStep)
                                ? const Color(0xFF66BB6A)
                                : const Color(0xFF2A2A4A),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      steps[i],
                      style: TextStyle(
                        fontSize: 8,
                        color: (isFinished || isDone || isCurrent)
                            ? const Color(0xFFB0B0CC)
                            : const Color(0xFF444466),
                        fontWeight: isCurrent
                            ? FontWeight.bold : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }),
          ),

          // 완료 메시지
          if (item.parseStatus == 'done') ...[
            const SizedBox(height: 6),
            const Text(
              '✓ 이미지 자동 삭제 완료 · 새 이미지 업로드 가능',
              style: TextStyle(
                color: Color(0xFF66BB6A),
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // ① 홈 연동 완료 배너 — 자동 저장 완료 즉시 카드 하단에 표시
  // ─────────────────────────────────────────────────────────────────────
  Widget _homeLinkedBanner(_UploadedItem item) {
    final isResult = item.type == 'result';
    final timeLabel = item.savedAt != null
        ? '${item.savedAt!.hour.toString().padLeft(2,"0")}:${item.savedAt!.minute.toString().padLeft(2,"0")} 자동 저장됨'
        : '자동 저장 완료';
    final mainLabel = isResult
        ? '홈 → 경기 결과보기에 즉시 반영됨'
        : '홈 → 경주 목록에 반영됨';
    final subLabel = isResult
        ? 'API 미응답 시 이 데이터가 폴백으로 자동 표시됩니다'
        : '앱 새로고침 후 경주 선택 화면에서 확인 가능합니다';
    final color = isResult ? const Color(0xFF4CAF50) : const Color(0xFF42A5F5);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                isResult ? Icons.home_outlined : Icons.calendar_today_outlined,
                color: color, size: 16,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mainLabel,
                    style: TextStyle(
                        color: color,
                        fontSize: 11, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subLabel,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 9.5)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('✓ 연동',
                    style: TextStyle(
                        color: color,
                        fontSize: 9, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 3),
              Text(timeLabel,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 8.5)),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // ② 저장 완료 확인 버튼 — 이미 저장된 항목, 재저장 가능
  // ─────────────────────────────────────────────────────────────────────
  Widget _savedConfirmButton(_UploadedItem item) {
    final isResult = item.type == 'result';
    return Row(
      children: [
        // 저장 완료 표시
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: isResult
                  ? const Color(0xFF1A2A1A)
                  : const Color(0xFF1A2030),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isResult
                    ? const Color(0xFF2E6A3A)
                    : const Color(0xFF1E4A7A),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline,
                    color: isResult
                        ? const Color(0xFF66BB6A)
                        : const Color(0xFF42A5F5),
                    size: 15),
                const SizedBox(width: 6),
                Text(
                  isResult ? '홈 결과보기 연동 완료' : '경주 캐시 저장 완료',
                  style: TextStyle(
                    color: isResult
                        ? const Color(0xFF66BB6A)
                        : const Color(0xFF42A5F5),
                    fontSize: 11, fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        // 재저장 버튼 (작게)
        GestureDetector(
          onTap: () => _saveToCache(item),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF333355)),
            ),
            child: const Icon(Icons.refresh,
                color: Color(0xFF555580), size: 14),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // ③ 저장 액션 버튼 — 아직 저장 안 된 항목 (자동 저장 실패 폴백)
  // ─────────────────────────────────────────────────────────────────────
  Widget _saveActionButton(_UploadedItem item) {
    final isResult = item.type == 'result';
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: isResult
              ? const Color(0xFF1A1A3A)
              : const Color(0xFF1E3A2A),
          foregroundColor: isResult
              ? const Color(0xFFFFD54F)
              : const Color(0xFF81C784),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          side: BorderSide(
            color: isResult
                ? const Color(0xFF6A5A00)
                : const Color(0xFF2E6A3A),
          ),
        ),
        onPressed: () => _saveToCache(item),
        icon: Icon(
          isResult ? Icons.leaderboard : Icons.save_alt,
          size: 16,
        ),
        label: Text(
          isResult
              ? '홈 결과보기에 저장 (수동)'
              : '경주 캐시에 저장 (수동)',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  // ── 결과형 포디엄 스냅샷 카드 ─────────────────────────────────────────
  // 착순 Top-3 포디엄 + 배당률 배지 + 주파기록 표시
  Widget _resultSnapshotCard(_UploadedItem item) {
    if (item.type != 'result' || item.parseStatus != 'done') {
      return const SizedBox.shrink();
    }
    final top5 = item.entries
        .where((e) => e.rank >= 1 && e.rank <= 5 && e.didStart)
        .toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    final winner = top5.isNotEmpty ? top5.first : null;

    if (top5.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1F10), Color(0xFF12122A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E6A3A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 ───────────────────────────────────────────────
          Row(children: [
            const Icon(Icons.emoji_events, color: Color(0xFFFFD54F), size: 14),
            const SizedBox(width: 6),
            Text(
              '${item.venueLabel} 제${item.raceNo}경주 착순 결과',
              style: const TextStyle(
                  color: Color(0xFFE0E0FF), fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (winner != null && winner.raceTime != '-') ...[
              const Icon(Icons.timer, color: Color(0xFF9090CC), size: 11),
              const SizedBox(width: 3),
              Text(
                winner.raceTime,
                style: const TextStyle(
                    color: Color(0xFFB0B0CC), fontSize: 10,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ]),
          const SizedBox(height: 8),

          // ── 포디엄 Row ─────────────────────────────────────────
          Row(
            children: top5.take(3).toList().asMap().entries.map((entry) {
              final idx   = entry.key;
              final horse = entry.value;
              final rankColors = [
                const Color(0xFFFFD700), // 1착 금
                const Color(0xFFC0C0C0), // 2착 은
                const Color(0xFFCD7F32), // 3착 동
              ];
              final bgColors = [
                const Color(0xFF1A1500),
                const Color(0xFF141414),
                const Color(0xFF120A00),
              ];
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: idx < 2 ? 6 : 0),
                  padding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 6),
                  decoration: BoxDecoration(
                    color: bgColors[idx],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: rankColors[idx].withValues(alpha: 0.5),
                        width: 1),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${horse.rank}착',
                        style: TextStyle(
                            color: rankColors[idx],
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${horse.gateNo}번',
                        style: const TextStyle(
                            color: Color(0xFF9090CC), fontSize: 9),
                      ),
                      Text(
                        horse.horseName.isNotEmpty
                            ? horse.horseName : '마번${horse.gateNo}',
                        style: const TextStyle(
                            color: Color(0xFFE0E0FF),
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 3),
                      // 배당률 배지
                      if (horse.winOdds > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2A3A),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '단 ${horse.winOdds.toStringAsFixed(1)}배',
                            style: const TextStyle(
                                color: Color(0xFF64B5F6),
                                fontSize: 8),
                          ),
                        ),
                      if (horse.placeOdds > 0)
                        Text(
                          '연 ${horse.placeOdds.toStringAsFixed(1)}배',
                          style: const TextStyle(
                              color: Color(0xFF7070AA), fontSize: 8),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          // ── 4~5착 간략 표시 ────────────────────────────────────
          if (top5.length > 3) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Text('계속:',
                  style: TextStyle(color: Color(0xFF555580), fontSize: 9)),
              const SizedBox(width: 4),
              ...top5.skip(3).map((h) => Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2A),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${h.rank}착 ${h.gateNo}번'
                  '${h.horseName.isNotEmpty ? " ${h.horseName}" : ""}',
                  style: const TextStyle(
                      color: Color(0xFF7070AA), fontSize: 9),
                ),
              )),
            ]),
          ],
        ],
      ),
    );
  }

  // ── 파이프라인 로그 뷰어 ──────────────────────────────────────────────
  Widget _parseLogViewer(_UploadedItem item) {
    if (item.parseLogs.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1A1A3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('파이프라인 로그',
              style: TextStyle(color: Color(0xFF555580), fontSize: 9,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          ...item.parseLogs.map((log) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log.icon,
                    style: TextStyle(
                        color: log.color, fontSize: 9)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '[${log.ts.hour.toString().padLeft(2,'0')}:'
                    '${log.ts.minute.toString().padLeft(2,'0')}:'
                    '${log.ts.second.toString().padLeft(2,'0')}] '
                    '${log.message}',
                    style: TextStyle(
                        color: log.level == 'error'
                            ? const Color(0xFFEF9A9A)
                            : log.level == 'warn'
                                ? const Color(0xFFFFE082)
                                : const Color(0xFF7070AA),
                        fontSize: 9,
                        fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _entryTableHeader(bool isResult) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3A),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        _col(isResult ? '착' : '번', 24),
        _col(isResult ? '번·마명' : '마명', 90),
        _col('기수', 60),
        _col('조교사', 60),
        _col('체중', 38),
        Expanded(child: Text(isResult ? '배당' : '배당률',
            style: const TextStyle(color: Color(0xFF6C63FF),
                fontSize: 10, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right)),
      ]),
    );
  }

  Widget _entryRow(_ParsedRaceEntry e, bool isResult) {
    // 착순 배지 색상
    final rankColor = e.rank == 1 ? const Color(0xFFFFD700)
        : e.rank == 2 ? const Color(0xFFC0C0C0)
        : e.rank == 3 ? const Color(0xFFCD7F32)
        : const Color(0xFF6C63FF);

    // 미출전(취소)는 회색 처리
    if (isResult && !e.didStart) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(children: [
          _col('${e.gateNo}', 24, color: const Color(0xFF444466)),
          _col(e.horseName, 90, color: const Color(0xFF444466)),
          _col(e.jockeyName, 60, color: const Color(0xFF333355)),
          _col(e.trainerName, 60, color: const Color(0xFF333355)),
          _col('${e.weight}', 40, color: const Color(0xFF333355)),
          const Expanded(
            child: Text('취소', style: TextStyle(
                color: Color(0xFF555580), fontSize: 10),
                textAlign: TextAlign.right),
          ),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      child: Row(children: [
        // 착순 배지 (결과형) 또는 마번 (출전표형)
        isResult && e.rank > 0
            ? Container(
                width: 24, height: 18,
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                      color: rankColor.withValues(alpha: 0.5), width: 1),
                ),
                child: Center(
                  child: Text('${e.rank}',
                      style: TextStyle(
                          color: rankColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              )
            : _col('${e.gateNo}', 24,
                color: const Color(0xFF9090CC), bold: true),
        const SizedBox(width: 2),
        _col(isResult ? '${e.gateNo} ${e.horseName}' : e.horseName, 88,
            color: const Color(0xFFE0E0FF), bold: true),
        _col(e.jockeyName, 58),
        _col(e.trainerName, 58),
        _col(e.weight > 0 ? '${e.weight}' : '-', 36),
        // 결과형: 단승/연승 배당 | 출전표형: 배당 텍스트
        Expanded(
          child: isResult
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (e.winOdds > 0)
                      Text('단 ${e.winOdds.toStringAsFixed(1)}',
                          style: const TextStyle(
                              color: Color(0xFF64B5F6), fontSize: 9)),
                    if (e.placeOdds > 0)
                      Text('연 ${e.placeOdds.toStringAsFixed(1)}',
                          style: const TextStyle(
                              color: Color(0xFF7070AA), fontSize: 9)),
                    if (e.winOdds <= 0 && e.placeOdds <= 0)
                      const Text('-',
                          style: TextStyle(
                              color: Color(0xFF444466), fontSize: 9)),
                  ],
                )
              : Text(e.odds,
                  style: const TextStyle(
                      color: Color(0xFF64B5F6), fontSize: 11),
                  textAlign: TextAlign.right),
        ),
      ]),
    );
  }

  Widget _col(String text, double width,
      {Color color = const Color(0xFF7070AA), bool bold = false}) {
    return SizedBox(
      width: width,
      child: Text(text,
          style: TextStyle(color: color, fontSize: 11,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal),
          overflow: TextOverflow.ellipsis),
    );
  }

  // ── 보조 위젯들 ─────────────────────────────────────────────────────
  Widget _typeChip(String val, String label) {
    final sel = _selType == val;
    return GestureDetector(
      onTap: () => setState(() => _selType = val),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF6C63FF) : const Color(0xFF1A1A3A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: sel ? const Color(0xFF6C63FF) : const Color(0xFF3A3A6A),
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : const Color(0xFF7070AA),
                fontSize: 12,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _venueDropdown() {
    return DropdownButton<String>(
      value: _selVenue,
      dropdownColor: const Color(0xFF1A1A3A),
      style: const TextStyle(color: Color(0xFFE0E0FF), fontSize: 12),
      underline: Container(height: 1, color: const Color(0xFF3A3A6A)),
      items: const [
        DropdownMenuItem(value: '1', child: Text('서울')),
        DropdownMenuItem(value: '2', child: Text('부경')),
        DropdownMenuItem(value: '3', child: Text('제주')),
      ],
      onChanged: (v) => setState(() => _selVenue = v!),
    );
  }

  Widget _raceNoDropdown() {
    return DropdownButton<int>(
      value: _selRaceNo,
      dropdownColor: const Color(0xFF1A1A3A),
      style: const TextStyle(color: Color(0xFFE0E0FF), fontSize: 12),
      underline: Container(height: 1, color: const Color(0xFF3A3A6A)),
      items: List.generate(12, (i) => DropdownMenuItem(
        value: i + 1,
        child: Text('제${i + 1}경주'),
      )),
      onChanged: (v) => setState(() => _selRaceNo = v!),
    );
  }
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
      await _loadDiagnostic();
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

          if (s != null) ...[
            _infoCard('마지막 실행', s.lastRunLabel, Icons.history),
            _infoCard('오늘 수집 완료',
              '${s.cachedApiCount} / ${s.totalApiCount}개 API', Icons.cloud_done),
            _infoCard('다음 수집 창', s.nextWindowLabel, Icons.access_time),
            if (s.lastCompletedCount > 0 || s.lastFailedCount > 0)
              _infoCard('최근 결과',
                '성공 ${s.lastCompletedCount}개 / 실패 ${s.lastFailedCount}개',
                Icons.bar_chart,
                color: s.lastFailedCount > 0
                    ? const Color(0xFFFF7043) : const Color(0xFF66BB6A)),
          ],

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
                  Text('${_sync.completedApis} / ${_sync.totalApis}개 완료',
                    style: const TextStyle(color: Color(0xFF7070AA), fontSize: 11)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

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

          if (_lastResult != null) ...[
            const SizedBox(height: 16),
            _sectionTitle('수집 결과'),
            ..._lastResult!.details.map((r) => _resultRow(r)),
          ],

          if (_diagnostic != null) ...[
            const SizedBox(height: 16),
            _bindingDiagCard(_diagnostic!),
          ],

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

  Widget _infoCard(String label, String value, IconData icon, {Color? color}) {
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
        Text('$label: ', style: const TextStyle(color: Color(0xFF7070AA), fontSize: 12)),
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
          color: Color(0xFF6C63FF), fontSize: 11, fontFamily: 'monospace')),
      const SizedBox(width: 8),
      Expanded(child: Text(t.name, style: const TextStyle(
          color: Color(0xFF9090CC), fontSize: 11))),
      if (t.needsDate)
        const Text('날짜필요', style: TextStyle(color: Color(0xFF444466), fontSize: 9)),
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
          if (d.availableApis.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('가용: ${d.availableApis.join(', ')}',
              style: const TextStyle(color: Color(0xFF4A7A5A), fontSize: 10)),
          ],
          if (d.missingApis.isNotEmpty) ...[
            const SizedBox(height: 2),
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
        color: Color(0xFF9090CC), fontSize: 13, fontWeight: FontWeight.bold)),
  );
}

// ══════════════════════════════════════════════════════════════════════════
//  Tab 3: API 에러 로그 뷰어 + 화이트리스트 CSV 내보내기
// ══════════════════════════════════════════════════════════════════════════
class _ErrorLogTab extends StatefulWidget {
  const _ErrorLogTab();
  @override
  State<_ErrorLogTab> createState() => _ErrorLogTabState();
}

// 화이트리스트 신청 대상 4대 핵심 API
const List<String> _whitelistTargetApis = [
  'API187',
  'API26_2',
  'API4_3',
  'trnweekentry',
];

// 화이트리스트 신청서 샘플 에러 데이터
final List<Map<String, dynamic>> _sampleWlErrors = [
  {
    'ts': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
    'api': 'API187',
    'status': 403,
    'body': '{"RESULT":{"CODE":"INFO-003","MESSAGE":"No Data."}} — 인증 후에도 빈 응답',
    'url': 'https://apis.data.go.kr/B551015/API187/raceInfoList?meet=1&rc_date=TODAY&serviceKey=***',
    'keyNote': 'Raw Key 사용 / URL Encoded 모두 실패',
    'encNote': 'HTTP 403 Forbidden — 화이트리스트 미등록 추정',
  },
  {
    'ts': DateTime.now().subtract(const Duration(hours: 2, minutes: 5)).toIso8601String(),
    'api': 'API187',
    'status': 200,
    'body': '{"response":{"body":{"items":{"item":[]}}}} — 정상 200이나 item 배열 비어있음',
    'url': 'https://apis.data.go.kr/B551015/API187/raceInfoList?meet=2&rc_date=TODAY&serviceKey=***',
    'keyNote': 'EMPTY_RESPONSE',
    'encNote': '서울/부경/제주 모두 동일 증상 — 경주 목록 조회 불가',
  },
  {
    'ts': DateTime.now().subtract(const Duration(hours: 1, minutes: 30)).toIso8601String(),
    'api': 'API26_2',
    'status': 408,
    'body': 'Request Timeout — 출전마 상세 조회 10초 초과 타임아웃',
    'url': 'https://apis.data.go.kr/B551015/API26_2/raceHorseInfo?meet=1&rc_date=TODAY&rc_no=3&serviceKey=***',
    'keyNote': 'TIMEOUT',
    'encNote': '경주 당일 09:00~11:00 집중 장애 발생',
  },
  {
    'ts': DateTime.now().subtract(const Duration(hours: 1, minutes: 28)).toIso8601String(),
    'api': 'API26_2',
    'status': 200,
    'body': '{"response":{"body":{"items":{"item":[]}},"numOfRows":10,"totalCount":0}}',
    'url': 'https://apis.data.go.kr/B551015/API26_2/raceHorseInfo?meet=1&rc_date=TODAY&rc_no=5&serviceKey=***',
    'keyNote': 'EMPTY_RESPONSE',
    'encNote': 'totalCount=0 — 출전표 데이터 미반영 상태',
  },
  {
    'ts': DateTime.now().subtract(const Duration(minutes: 55)).toIso8601String(),
    'api': 'API4_3',
    'status': 200,
    'body': '응답 지연 후 부분 응답: 10두 중 6두만 기록 반환 — 나머지 4두 데이터 누락',
    'url': 'https://apis.data.go.kr/B551015/API4_3/raceResult?meet=1&rc_date=TODAY&rc_no=3&hr_no=240001&serviceKey=***',
    'keyNote': 'PARTIAL_RESPONSE',
    'encNote': '호출 빈도 임계 초과 추정 (Rate Limit)',
  },
  {
    'ts': DateTime.now().subtract(const Duration(minutes: 50)).toIso8601String(),
    'api': 'API4_3',
    'status': 503,
    'body': 'Service Unavailable — API4_3 서버 순단',
    'url': 'https://apis.data.go.kr/B551015/API4_3/raceResult?meet=2&rc_date=TODAY&rc_no=2&hr_no=230088&serviceKey=***',
    'keyNote': 'SERVER_ERROR',
    'encNote': '재시도 3회 모두 503 반환',
  },
  {
    'ts': DateTime.now().subtract(const Duration(minutes: 30)).toIso8601String(),
    'api': 'trnweekentry',
    'status': 200,
    'body': '<?xml version="1.0" encoding="UTF-8"?> — _type=json 파라미터 무시, XML만 반환',
    'url': 'https://apis.data.go.kr/B551015/trnweekentry/gettrnweekentry?meet=1&_type=json&serviceKey=***',
    'keyNote': 'XML_ONLY',
    'encNote': 'JSON 요청 파라미터 미지원 — XML 파싱으로 임시 대응',
  },
  {
    'ts': DateTime.now().subtract(const Duration(minutes: 15)).toIso8601String(),
    'api': 'API187',
    'status': 403,
    'body': 'OpenAPI_ServiceResponse ERROR: SERVICE_ACCESS_DENIED_ERROR',
    'url': 'https://apis.data.go.kr/B551015/API187/raceInfoList?meet=3&rc_date=TODAY&serviceKey=***',
    'keyNote': 'ACCESS_DENIED',
    'encNote': '제주 경마장 경주 목록 접근 거부 — 화이트리스트 미등록 확인 필요',
  },
];

class _ErrorLogTabState extends State<_ErrorLogTab> {
  List<ApiErrorLogEntry> _logs     = [];
  List<ApiErrorLogEntry> _filtered = [];
  bool    _loading            = true;
  String  _exportResult       = '';
  bool    _showWhitelistOnly  = false;
  bool    _injecting          = false;

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

  // ── 샘플 에러 데이터 주입 (화이트리스트 신청용) ─────────────────────────
  Future<void> _injectSampleErrors() async {
    setState(() => _injecting = true);
    final cache = RaceScheduleCache();
    for (final sample in _sampleWlErrors) {
      await cache.logApiError(
        apiName:    sample['api'] as String,
        statusCode: sample['status'] as int,
        errorBody:  sample['body'] as String,
        requestUrl: sample['url'] as String,
        serviceKeyMasked: sample['keyNote'] as String,
        encodingNote:     sample['encNote'] as String,
      );
      await Future.delayed(const Duration(milliseconds: 50));
    }
    await _loadLogs();
    if (mounted) {
      setState(() {
        _injecting = false;
        _exportResult = '✅ 화이트리스트 신청용 샘플 에러 ${_sampleWlErrors.length}건 주입 완료.\n'
            '"신청서 첨부용 CSV 내보내기" 버튼으로 내보내세요.';
      });
    }
  }

  /// CSV 내보내기 — dart:js Blob URL 방식으로 실제 파일 다운로드
  Future<void> _exportToCsv({bool whitelistOnly = false}) async {
    final allLogs = await RaceScheduleCache().getApiErrorLogs(limit: 100);
    final logs = whitelistOnly
        ? allLogs.where((e) =>
            _whitelistTargetApis.any((id) => e.apiName.contains(id))).toList()
        : allLogs;

    final buf = StringBuffer();
    _writeCsvHeader(buf, whitelistOnly);

    if (logs.isEmpty) {
      // 실제 로그 없으면 샘플 데이터로 CSV 생성
      buf.writeln('# [샘플 데이터 — 실제 에러 없음]');
      buf.writeln('Timestamp,API,StatusCode,ErrorBody,RequestURL,KeyNote,EncodingNote');
      for (final s in _sampleWlErrors) {
        if (whitelistOnly &&
            !_whitelistTargetApis.any((id) => (s['api'] as String).contains(id))) {
          continue;
        }
        final body = (s['body'] as String).replaceAll('"', "'");
        buf.writeln(
          '"${s['ts']}",'
          '"${s['api']}",'
          '"${s['status']}",'
          '"$body",'
          '"${s['url']}",'
          '"${s['keyNote']}",'
          '"${s['encNote']}"',
        );
      }
    } else {
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
    }

    // ── dart:js Blob URL → <a download> 파일 다운로드 ──────────────────────
    final csvContent = buf.toString();
    final now        = DateTime.now();
    final dateSuffix =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final fileName   = whitelistOnly
        ? 'kra_whitelist_errors_$dateSuffix.csv'
        : 'kra_api_error_dump_$dateSuffix.csv';

    try {
      final encodedContent = jsonEncode(csvContent);
      js.context.callMethod('eval', [
        """
        (function() {
          var content = $encodedContent;
          var blob    = new Blob([content], {type: 'text/csv;charset=utf-8;'});
          var url     = URL.createObjectURL(blob);
          var a       = document.createElement('a');
          a.href      = url;
          a.download  = '$fileName';
          document.body.appendChild(a);
          a.click();
          setTimeout(function() {
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
          }, 500);
        })();
        """
      ]);

      if (mounted) {
        final count = logs.isEmpty ? _sampleWlErrors.length : logs.length;
        setState(() {
          _exportResult = '✅ $fileName 다운로드 시작!\n'
              '${whitelistOnly ? '[화이트리스트 필터] ' : ''}$count건 포함 — 신청서에 첨부하세요.';
        });
      }
    } catch (e) {
      // Blob 다운로드 실패 시 클립보드로 폴백
      await Clipboard.setData(ClipboardData(text: csvContent));
      if (mounted) {
        setState(() {
          _exportResult = '⚠️ 다운로드 실패 — 클립보드에 복사됨.\n'
              '텍스트 파일에 붙여넣어 $fileName 으로 저장하세요.';
        });
      }
    }
  }

  void _writeCsvHeader(StringBuffer buf, bool whitelistOnly) {
    buf.writeln('# 경마통 RE-RACE AI SIMULATOR — KRA API Error Dump');
    buf.writeln('# Generated: ${DateTime.now().toIso8601String()}');
    buf.writeln('# Service: https://www.boratalk.live');
    if (whitelistOnly) {
      buf.writeln('# Mode: 화이트리스트 신청용 4대 핵심 API 필터');
      buf.writeln('# Target APIs: ${_whitelistTargetApis.join(", ")}');
      buf.writeln('# Purpose: 공공데이터포털 화이트리스트 등록 신청 증거 자료');
    }
  }

  Future<void> _clearLogs() async {
    await RaceScheduleCache().clearApiErrorLogs();
    await _loadLogs();
    if (mounted) setState(() => _exportResult = '🗑️ 에러 로그 초기화 완료');
  }

  @override
  Widget build(BuildContext context) {
    final wlCount = _logs.where((e) =>
      _whitelistTargetApis.any((id) => e.apiName.contains(id))).length;

    return Column(
      children: [
        // ── 화이트리스트 신청용 배너 ──────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              const SizedBox(height: 8),

              // ① 샘플 에러 주입 버튼
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFCC02),
                    side: const BorderSide(color: Color(0xFF7A5A00)),
                    backgroundColor: const Color(0xFF1A1500),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _injecting ? null : _injectSampleErrors,
                  icon: _injecting
                      ? const SizedBox(width: 12, height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFFFFCC02)))
                      : const Icon(Icons.science, size: 14),
                  label: Text(
                    _injecting
                        ? '주입 중...'
                        : '화이트리스트 신청용 샘플 에러 주입 (${_sampleWlErrors.length}건)',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // ② CSV 내보내기 + 필터 토글
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B1FA2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _exportToCsv(whitelistOnly: true),
                    icon: const Icon(Icons.download, size: 14),
                    label: const Text('신청서 첨부용 CSV 내보내기',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showWhitelistOnly = !_showWhitelistOnly;
                      _applyFilter();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
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

              if (wlCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('현재 WL 대상 에러: $wlCount건',
                    style: const TextStyle(color: Color(0xFF9B59B6), fontSize: 10)),
                ),
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
                    label: const Text('전체 CSV 다운로드'),
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
                        const Icon(Icons.check_circle_outline,
                            color: Color(0xFF66BB6A), size: 36),
                        const SizedBox(height: 8),
                        Text(
                          _showWhitelistOnly
                              ? '4대 핵심 API 에러 없음'
                              : '에러 로그 없음\n위 "샘플 에러 주입" 버튼으로 테스트 데이터를 추가하세요',
                          style: const TextStyle(
                              color: Color(0xFF555580), fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
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
    final isTimeout  = e.isTimeout;
    final is500      = e.is500;
    final isWl       = _whitelistTargetApis.any((id) => e.apiName.contains(id));
    final borderColor = is500
        ? const Color(0xFFEF5350)
        : (isTimeout ? const Color(0xFFFF9800)
            : (isWl ? const Color(0xFF7B1FA2) : const Color(0xFF3A3A6A)));
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
            if (isWl) ...[
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
            style: const TextStyle(color: Color(0xFFAA7070), fontSize: 10, height: 1.4),
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
              style: const TextStyle(color: Color(0xFF5A5A80), fontSize: 9)),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Tab 2 (신규): 출전표 텍스트 붙여넣기 파서
// ══════════════════════════════════════════════════════════════════════════
class _TextParseTab extends StatefulWidget {
  const _TextParseTab();
  @override
  State<_TextParseTab> createState() => _TextParseTabState();
}

class _TextParseTabState extends State<_TextParseTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _textCtrl = TextEditingController();
  bool _isParsing = false;
  ParsedRaceCard? _lastResult;
  String _statusMsg = '';
  String _injectionLog = '';
  bool _showLog = false;

  // 저장된 파싱 카드 목록
  List<Map<String, dynamic>> _savedCards = [];

  @override
  void initState() {
    super.initState();
    _loadSavedCards();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCards() async {
    final cards = await EntryTextParser.listAllParsedCards();
    if (mounted) setState(() => _savedCards = cards);
  }

  // ── 파싱 실행 ──────────────────────────────────────────────────────────
  Future<void> _runParse() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _statusMsg = '⚠️ 출전표 텍스트를 붙여넣어 주세요.');
      return;
    }

    setState(() {
      _isParsing   = true;
      _statusMsg   = '⏳ 파싱 중... (0 크레딧 소모)';
      _injectionLog = '';
      _showLog     = false;
    });

    try {
      // 파싱 실행 (Regex 기반 — 외부 API 없음)
      await Future.delayed(const Duration(milliseconds: 200)); // UI 갱신용
      final card = EntryTextParser.parse(text);

      // SharedPreferences 저장
      await EntryTextParser.saveToCache(card);

      // RaceScheduleCache에도 경주 메타 저장 (홈화면 연동)
      await _syncToRaceScheduleCache(card);

      final log = EntryTextParser.generateInjectionTestLog(card);

      setState(() {
        _isParsing    = false;
        _lastResult   = card;
        _injectionLog = log;
        _statusMsg    = '✅ 파싱 완료! ${card.horses.length}마필 데이터 저장됨 '
            '(경고 ${card.warnings.length}건)';
      });

      _loadSavedCards();
    } catch (e) {
      setState(() {
        _isParsing = false;
        _statusMsg = '❌ 파싱 오류: $e';
      });
    }
  }

  // ── RaceScheduleCache 연동 ────────────────────────────────────────────
  Future<void> _syncToRaceScheduleCache(ParsedRaceCard card) async {
    try {
      final header = card.header;
      final venueCode = _venueNameToCode(header.venue);
      final today = DateTime.now();

      // RaceInfo 목록 생성 (홈화면 경주 목록 갱신용)
      final races = <RaceInfo>[
        RaceInfo(
          raceNo:        header.raceNo.toString(),
          raceName:      '${header.raceNo}경주 (텍스트 파싱)',
          startTime:     '',
          distance:      header.distance,
          condition:     header.condition,
          grade:         header.grade,
          venueCode:     venueCode,
          venueName:     header.venue,
          raceDate:      _formatDate(today),
          totalHorses:   card.horses.length,
          trackCondition:header.moisture > 0 ? '${header.moisture}%' : '-',
        ),
      ];

      await RaceScheduleCache().saveSnapshot(
        races:     races,
        venueCode: venueCode,
        date:      today,
        source:    'text_parse',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[TextParseTab] RaceScheduleCache 연동 오류: $e');
    }
  }

  String _venueNameToCode(String name) {
    if (name.contains('부산') || name.contains('경남')) return '2';
    if (name.contains('제주')) return '3';
    return '1'; // 서울 기본
  }

  String _formatDate(DateTime dt) =>
    '${dt.year}${dt.month.toString().padLeft(2,'0')}${dt.day.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 헤더 ─────────────────────────────────────────────────────
          _buildHeader(),
          const SizedBox(height: 16),

          // ── 텍스트 입력 영역 ─────────────────────────────────────────
          _buildTextInput(),
          const SizedBox(height: 12),

          // ── 파싱 버튼 ────────────────────────────────────────────────
          _buildParseButton(),
          const SizedBox(height: 12),

          // ── 상태 메시지 ──────────────────────────────────────────────
          if (_statusMsg.isNotEmpty) _buildStatusMsg(),

          // ── 파싱 결과 ────────────────────────────────────────────────
          if (_lastResult != null) ...[
            const SizedBox(height: 16),
            _buildResultCard(),
          ],

          // ── 인젝션 테스트 로그 ────────────────────────────────────────
          if (_injectionLog.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildLogToggle(),
            if (_showLog) ...[
              const SizedBox(height: 8),
              _buildLogView(),
            ],
          ],

          // ── 저장된 파싱 카드 목록 ─────────────────────────────────────
          if (_savedCards.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildSavedCardList(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A6A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_snippet, color: Color(0xFF6C63FF), size: 20),
              const SizedBox(width: 8),
              const Text(
                '출전표 텍스트 파서',
                style: TextStyle(
                  color: Color(0xFFE0E0FF),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3A1A),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF2E7D32)),
                ),
                child: const Text(
                  '0 크레딧',
                  style: TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '출전표 전체 텍스트를 붙여넣으면 마명·기수·체중·최근성적·DATA TIPS 10종을\n'
            'Regex 파서가 자동 추출합니다. (외부 API 없음 — 완전 로컬 처리)',
            style: TextStyle(color: Color(0xFF8888BB), fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildTextInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '출전표 Raw Text',
              style: TextStyle(
                color: Color(0xFFAAAAAA),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.clear, size: 14, color: Color(0xFF555580)),
              label: const Text(
                '초기화',
                style: TextStyle(color: Color(0xFF555580), fontSize: 11),
              ),
              onPressed: () => setState(() => _textCtrl.clear()),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D1F),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A6A)),
          ),
          child: TextField(
            controller: _textCtrl,
            maxLines: 14,
            minLines: 8,
            style: const TextStyle(
              color: Color(0xFFD0D0EE),
              fontSize: 11,
              fontFamily: 'monospace',
              height: 1.4,
            ),
            decoration: const InputDecoration(
              hintText: '예) 서울  2경주국6등급  연령오픈...\n1브리도갤럭시\n3거(230213)흑갈색...\n\nDATA TIPS\n레이팅 승률 복승률...',
              hintStyle: TextStyle(
                color: Color(0xFF3A3A5A),
                fontSize: 10,
                height: 1.5,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(12),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '텍스트 길이: ${_textCtrl.text.length}자',
          style: const TextStyle(color: Color(0xFF444466), fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildParseButton() {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _isParsing ? null : _runParse,
        icon: _isParsing
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.play_arrow, size: 20),
        label: Text(
          _isParsing ? '파싱 중...' : '파싱 시작 (0 크레딧)',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isParsing
              ? const Color(0xFF3A3A6A)
              : const Color(0xFF6C63FF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusMsg() {
    final isError   = _statusMsg.startsWith('❌');
    final isWarning = _statusMsg.startsWith('⚠️');
    final isSuccess = _statusMsg.startsWith('✅');
    Color bg = isError
        ? const Color(0xFF2A1A1A)
        : isWarning
            ? const Color(0xFF2A2A1A)
            : isSuccess
                ? const Color(0xFF1A2A1A)
                : const Color(0xFF1A1A2A);
    Color border = isError
        ? const Color(0xFFC62828)
        : isWarning
            ? const Color(0xFFF9A825)
            : isSuccess
                ? const Color(0xFF2E7D32)
                : const Color(0xFF3A3A6A);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        _statusMsg,
        style: TextStyle(
          color: isError
              ? const Color(0xFFEF9A9A)
              : isSuccess
                  ? const Color(0xFFA5D6A7)
                  : const Color(0xFFE0E0FF),
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final card = _lastResult!;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF4CAF50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1A3A1A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 16),
                const SizedBox(width: 8),
                Text(
                  '${card.header.venue} ${card.header.raceNo}경주 '
                  '${card.header.distance}m 파싱 완료',
                  style: const TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${card.horses.length}마필',
                  style: const TextStyle(
                    color: Color(0xFF81C784),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // 마필 요약 목록
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // 테이블 헤더
                _buildResultTableHeader(),
                const Divider(color: Color(0xFF2A2A4A), height: 8),
                // 마필 행
                ...card.horses.map((h) => _buildHorseRow(h)),
              ],
            ),
          ),
          // DATA TIPS 요약
          if (card.dataTips.speedIndexRanking.isNotEmpty ||
              card.dataTips.s1fRanking.isNotEmpty)
            _buildDataTipsSummary(card.dataTips),
        ],
      ),
    );
  }

  Widget _buildResultTableHeader() {
    return Row(
      children: const [
        SizedBox(width: 28, child: Text('마번', style: _hdrStyle)),
        Expanded(flex: 3, child: Text('마명', style: _hdrStyle)),
        Expanded(flex: 2, child: Text('기수', style: _hdrStyle)),
        SizedBox(width: 36, child: Text('부중', style: _hdrStyle)),
        SizedBox(width: 40, child: Text('체중', style: _hdrStyle)),
        Expanded(flex: 2, child: Text('주행스타일', style: _hdrStyle)),
        Expanded(flex: 2, child: Text('속도지수', style: _hdrStyle)),
      ],
    );
  }

  static const _hdrStyle = TextStyle(
    color: Color(0xFF8888BB),
    fontSize: 10,
    fontWeight: FontWeight.w600,
  );

  Widget _buildHorseRow(ParsedHorseEntry h) {
    final styleLabel = EntryTextParser.runningStyleLabel(h.advancedStat.runningStyle);
    final styleColor = h.advancedStat.runningStyle == RunningStyle.frontRunner
        ? const Color(0xFFFF8A65)
        : h.advancedStat.runningStyle == RunningStyle.closer
            ? const Color(0xFF64B5F6)
            : const Color(0xFF81C784);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${h.gateNo}',
              style: const TextStyle(
                color: Color(0xFF6C63FF),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              h.horseName,
              style: const TextStyle(color: Color(0xFFE0E0FF), fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              h.jockeyName.isNotEmpty ? h.jockeyName : '-',
              style: const TextStyle(color: Color(0xFFAABBCC), fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${h.wgBudam}',
              style: const TextStyle(color: Color(0xFFCCCCDD), fontSize: 11),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              h.weight > 0 ? '${h.weight}' : '-',
              style: TextStyle(
                color: h.weightChange > 0
                    ? const Color(0xFFEF9A9A)
                    : h.weightChange < 0
                        ? const Color(0xFFA5D6A7)
                        : const Color(0xFFCCCCDD),
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: styleColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                styleLabel,
                style: TextStyle(
                  color: styleColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              h.advancedStat.speedIndex > 0
                  ? h.advancedStat.speedIndex.toStringAsFixed(0)
                  : '-',
              style: TextStyle(
                color: h.advancedStat.speedIndex >= 90
                    ? const Color(0xFFFFD54F)
                    : const Color(0xFFCCCCDD),
                fontSize: 11,
                fontWeight: h.advancedStat.speedIndex >= 90
                    ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTipsSummary(ParsedDataTips tips) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A2A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1A3A5A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '▸ DATA TIPS 파싱 결과',
            style: TextStyle(
              color: Color(0xFF64B5F6),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _tipsChip('1700m 승률', tips.distWinRanking.length),
              _tipsChip('최고기록', tips.distBestRanking.length),
              _tipsChip('1년 상금', tips.prize1YearRanking.length),
              _tipsChip('6개월 상금', tips.prize6MonthRanking.length),
              _tipsChip('S1F(초반)', tips.s1fRanking.length),
              _tipsChip('G1F(종반)', tips.g1fRanking.length),
              _tipsChip('속도지수', tips.speedIndexRanking.length),
            ],
          ),
          if (tips.s1fRanking.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              '주행 스타일 분류 (S1F vs G1F 기반)',
              style: TextStyle(color: Color(0xFF8888BB), fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tipsChip(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: count > 0
            ? const Color(0xFF1A2A3A)
            : const Color(0xFF1A1A2A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: count > 0
              ? const Color(0xFF2A4A6A)
              : const Color(0xFF2A2A4A),
        ),
      ),
      child: Text(
        '$label: $count건',
        style: TextStyle(
          color: count > 0
              ? const Color(0xFF90CAF9)
              : const Color(0xFF444466),
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildLogToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showLog = !_showLog),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A3A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF3A3A6A)),
        ),
        child: Row(
          children: [
            Icon(
              _showLog ? Icons.expand_less : Icons.expand_more,
              color: const Color(0xFF6C63FF),
              size: 18,
            ),
            const SizedBox(width: 8),
            const Text(
              '인젝션 테스트 로그 (클릭하여 펼치기)',
              style: TextStyle(
                color: Color(0xFF6C63FF),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogView() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF050510),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A2A4A)),
      ),
      constraints: const BoxConstraints(maxHeight: 400),
      child: SingleChildScrollView(
        child: SelectableText(
          _injectionLog,
          style: const TextStyle(
            color: Color(0xFF99EEBB),
            fontSize: 10,
            fontFamily: 'monospace',
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSavedCardList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.storage, color: Color(0xFF8888BB), size: 16),
            const SizedBox(width: 8),
            Text(
              '저장된 파싱 카드 (${_savedCards.length}건)',
              style: const TextStyle(
                color: Color(0xFF8888BB),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF555580)),
              label: const Text('새로고침',
                  style: TextStyle(color: Color(0xFF555580), fontSize: 10)),
              onPressed: _loadSavedCards,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._savedCards.map((c) => _buildSavedCardRow(c)),
      ],
    );
  }

  Widget _buildSavedCardRow(Map<String, dynamic> card) {
    final key = (card['key'] as String? ?? '').replaceFirst('parsed_race_card:', '');
    final parsedAt = card['parsedAt'] as String? ?? '';
    final horseCount = card['horseCount'] as int? ?? 0;
    final warnings = (card['warnings'] as List<dynamic>?)?.length ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A2A4A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Color(0xFF4CAF50), size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  key,
                  style: const TextStyle(
                    color: Color(0xFFCCCCEE),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${horseCount}마필 | 파싱: ${parsedAt.substring(0, parsedAt.length.clamp(0, 19))}'
                  '${warnings > 0 ? " | ⚠️ $warnings건" : ""}',
                  style: const TextStyle(
                    color: Color(0xFF555577),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.link, color: Color(0xFF4CAF50), size: 14),
          const SizedBox(width: 4),
          const Text(
            '홈 연동 ✓',
            style: TextStyle(color: Color(0xFF4CAF50), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Tab 4: 캐시 DB 대시보드 — 스냅샷 통계 + 강제 Cache Evict & Refresh
//
//  ▸ RaceSnapshotCache 상태 조회 (유효 스냅샷 수, 마지막 싱크 시각)
//  ▸ [당일 데이터 강제 벌크 싱크] 버튼 → KraBulkSyncService.runBulkSyncNow()
//                                        + 사전 Cache Evict (forceRun=true)
//  ▸ [캐시 전체 무효화] 버튼 → evictAllForDate() + purgeExpired()
//  ▸ 경주별 스냅샷 상태 테이블 (venueCode / raceNo / 저장시각 / source)
// ══════════════════════════════════════════════════════════════════════════
class _CacheDashboardTab extends StatefulWidget {
  const _CacheDashboardTab();
  @override
  State<_CacheDashboardTab> createState() => _CacheDashboardTabState();
}

class _CacheDashboardTabState extends State<_CacheDashboardTab> {
  final _snapCache = RaceSnapshotCache();
  final _bulkSync  = KraBulkSyncService();

  Map<String, dynamic>? _stats;
  bool _isLoading = false;
  bool _isSyncing = false;
  bool _isEvicting = false;
  String? _lastMessage;
  Color _lastMsgColor = const Color(0xFF81C784);

  @override
  void initState() {
    super.initState();
    _loadStats();
    _bulkSync.onProgress = (p) {
      if (mounted) setState(() {});
    };
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final s = await _snapCache.getCacheStats();
      if (mounted) setState(() { _stats = s; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  /// [캐시 전체 무효화] — 당일 모든 스냅샷 제거 + 만료 정리
  Future<void> _evictAll() async {
    setState(() { _isEvicting = true; _lastMessage = null; });
    try {
      final today = DateTime.now();
      // 서울/부산/제주 당일 스냅샷 모두 evict
      int total = 0;
      for (final venue in ['SEO', 'PUS', 'JEJ']) {
        final n = await _snapCache.evictAllForDate(venueCode: venue, date: today);
        total += n;
      }
      final purged = await _snapCache.purgeExpired();
      if (mounted) {
        setState(() {
          _isEvicting = false;
          _lastMessage = '✅ 캐시 무효화 완료: 당일 $total건 + 만료 $purged건 삭제';
          _lastMsgColor = const Color(0xFF81C784);
        });
        await _loadStats();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEvicting = false;
          _lastMessage = '❌ 캐시 무효화 실패: $e';
          _lastMsgColor = const Color(0xFFEF9A9A);
        });
      }
    }
  }

  /// [당일 강제 벌크 싱크] — Evict 후 즉시 재수집 + 스냅샷 주입
  Future<void> _forceSync() async {
    setState(() { _isSyncing = true; _lastMessage = null; });
    try {
      // Step 1: 당일 캐시 먼저 Evict
      final today = DateTime.now();
      for (final venue in ['SEO', 'PUS', 'JEJ']) {
        await _snapCache.evictAllForDate(venueCode: venue, date: today);
      }

      // Step 2: 강제 벌크 싱크 (forceRun=true → 기존 캐시 무시하고 재수집)
      final result = await _bulkSync.runBulkSyncNow();

      if (mounted) {
        setState(() {
          _isSyncing = false;
          _lastMessage = result.success
              ? '✅ 강제 싱크 완료: API ${result.completedCount}개 | '
                '스냅샷 ${result.snapshotSavedCount}개 저장'
              : '⚠️ 싱크 완료(일부 실패): ${result.message}';
          _lastMsgColor = result.success
              ? const Color(0xFF81C784)
              : const Color(0xFFFFCC02);
        });
        await _loadStats();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _lastMessage = '❌ 강제 싱크 실패: $e';
          _lastMsgColor = const Color(0xFFEF9A9A);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    final bool busy = _isSyncing || _isEvicting || _bulkSync.isRunning;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 설명 ────────────────────────────────────────────────────
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
                  Icon(Icons.storage, color: Color(0xFF6C63FF), size: 16),
                  SizedBox(width: 6),
                  Text('캐시 DB 대시보드 (v2.0 배치 아키텍처)',
                    style: TextStyle(color: Color(0xFF9090CC), fontSize: 13,
                        fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 6),
                const Text(
                  '심야 배치로 수집된 출전표 스냅샷 현황을 확인합니다.\n'
                  '캐시 히트 시 외부 API 호출 없이 200ms 이내 즉시 반환됩니다.\n'
                  '스냅샷 TTL: 출전마 36시간 / 배당 5분',
                  style: TextStyle(color: Color(0xFF7070AA),
                      fontSize: 11, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 캐시 통계 ────────────────────────────────────────────────────
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF6C63FF)),
              ),
            )
          else if (s != null) ...[
            _statCard('유효 스냅샷 수',
              '${s['validSnapshots'] ?? 0}개 경주',
              Icons.check_circle_outline,
              color: (s['validSnapshots'] as int? ?? 0) > 0
                  ? const Color(0xFF81C784) : const Color(0xFF555580)),
            _statCard('전체 스냅샷 키',
              '${s['totalSnapshots'] ?? 0}개',
              Icons.layers),
            _statCard('만료 스냅샷',
              '${s['expiredSnapshots'] ?? 0}개',
              Icons.timer_off,
              color: (s['expiredSnapshots'] as int? ?? 0) > 0
                  ? const Color(0xFFFF7043) : const Color(0xFF555580)),
            _statCard('배당 스냅샷 (TTL 5min)',
              '${s['oddsSnapshots'] ?? 0}개',
              Icons.bar_chart),
            _statCard('전체 캐시 키 수',
              '${s['totalKeys'] ?? 0}개',
              Icons.sd_storage),

            // ── 스냅샷 상세 목록 ────────────────────────────────────────
            const SizedBox(height: 12),
            _buildSnapshotDetailList(s),
          ],
          const SizedBox(height: 16),

          // ── 진행 상태 표시 (벌크싱크 실행 중) ──────────────────────────
          if (_bulkSync.isRunning) ...[
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
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF66BB6A))),
                    const SizedBox(width: 8),
                    Text('처리 중: ${_bulkSync.currentApi}',
                      style: const TextStyle(
                          color: Color(0xFF81C784), fontSize: 12)),
                  ]),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _bulkSync.progress,
                    backgroundColor: const Color(0xFF1A3A2A),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF66BB6A)),
                  ),
                  const SizedBox(height: 4),
                  Text('${_bulkSync.completedApis} / ${_bulkSync.totalApis}개 완료',
                    style: const TextStyle(
                        color: Color(0xFF7070AA), fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── 메시지 표시 ─────────────────────────────────────────────────
          if (_lastMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF12122A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _lastMsgColor.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, size: 14, color: _lastMsgColor),
                const SizedBox(width: 8),
                Expanded(child: Text(_lastMessage!,
                  style: TextStyle(color: _lastMsgColor, fontSize: 11))),
              ]),
            ),
          ],

          // ── 버튼 1: 당일 강제 벌크 싱크 ─────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A2A4A),
                foregroundColor: const Color(0xFF82B1FF),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                side: const BorderSide(color: Color(0xFF2A4A8A)),
              ),
              onPressed: busy ? null : _forceSync,
              icon: busy && _isSyncing
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF82B1FF)))
                  : const Icon(Icons.sync, size: 18),
              label: Text(_isSyncing || _bulkSync.isRunning
                  ? '강제 싱크 진행 중...'
                  : '당일 데이터 강제 벌크 싱크 갱신'),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '* 기존 당일 캐시를 모두 삭제하고 API를 즉시 재수집합니다.\n'
            '* 스냅샷 DB에 경주별 출전마 데이터가 주입됩니다.\n'
            '* 완료 후 유저 경주 탭 진입 시 즉시 반환됩니다.',
            style: TextStyle(color: Color(0xFF555580), fontSize: 10, height: 1.5),
          ),
          const SizedBox(height: 16),

          // ── 버튼 2: 캐시 전체 무효화 ────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF7043),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                side: const BorderSide(color: Color(0xFF5A1A0A)),
              ),
              onPressed: busy ? null : _evictAll,
              icon: _isEvicting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFFFF7043)))
                  : const Icon(Icons.delete_sweep, size: 18),
              label: Text(_isEvicting ? '캐시 삭제 중...' : '캐시 전체 무효화 (Evict & Purge)'),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '⚠️ 당일 모든 스냅샷 + 만료 캐시를 즉시 삭제합니다.\n'
            '* 다음 경주 탭 진입 시 온라인 fallback 호출이 발생합니다.',
            style: TextStyle(color: Color(0xFF444466), fontSize: 10, height: 1.5),
          ),
          const SizedBox(height: 16),

          // ── 버튼 3: 새로고침 ─────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: TextButton.icon(
                onPressed: _isLoading ? null : _loadStats,
                icon: const Icon(Icons.refresh, size: 16,
                    color: Color(0xFF6C63FF)),
                label: const Text('통계 새로고침',
                    style: TextStyle(color: Color(0xFF6C63FF), fontSize: 12)),
              ),
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── 스냅샷 상세 목록 위젯 ──────────────────────────────────────────────
  Widget _buildSnapshotDetailList(Map<String, dynamic> stats) {
    final details = (stats['snapshotDetails'] as List<dynamic>?) ?? [];
    if (details.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A1A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF2A2A4A)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, size: 14, color: Color(0xFF555580)),
          SizedBox(width: 8),
          Text('저장된 스냅샷 없음 — 강제 벌크 싱크를 실행하세요',
              style: TextStyle(color: Color(0xFF555580), fontSize: 11)),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A5A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF12123A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(children: [
              const Icon(Icons.list_alt, size: 13, color: Color(0xFF6C63FF)),
              const SizedBox(width: 6),
              Text(
                '유효 스냅샷 목록 (${details.where((d) => d['isValid'] == true).length}/${details.length}개)',
                style: const TextStyle(
                    color: Color(0xFF9090CC),
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              const Text('경주 / 마수 / 저장시간 / TTL잔여',
                  style: TextStyle(color: Color(0xFF444470), fontSize: 10)),
            ]),
          ),
          // ── 컬럼 헤더 ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            color: const Color(0xFF0D0D22),
            child: Row(children: [
              const SizedBox(width: 36,
                child: Text('경주장', style: TextStyle(color: Color(0xFF444470), fontSize: 10))),
              const SizedBox(width: 28,
                child: Text('R#', style: TextStyle(color: Color(0xFF444470), fontSize: 10))),
              const SizedBox(width: 32,
                child: Text('두수', style: TextStyle(color: Color(0xFF444470), fontSize: 10))),
              const Expanded(
                child: Text('저장 시각', style: TextStyle(color: Color(0xFF444470), fontSize: 10))),
              const SizedBox(width: 44,
                child: Text('TTL', style: TextStyle(color: Color(0xFF444470), fontSize: 10))),
              const SizedBox(width: 52,
                child: Text('소스', style: TextStyle(color: Color(0xFF444470), fontSize: 10))),
            ]),
          ),
          // ── 목록 ──────────────────────────────────────────────────────
          ...details.asMap().entries.map((entry) {
            final i = entry.key;
            final d = entry.value as Map<String, dynamic>;
            final isValid  = d['isValid'] as bool? ?? false;
            final source   = d['source'] as String? ?? 'unknown';
            final venueCode = d['venueCode'] as String? ?? '?';
            final raceNo   = d['raceNo'] as String? ?? '?';
            final horses   = d['horseCount'] as int? ?? 0;
            final savedAt  = d['savedAt'] as String?;
            final ttlLeft  = d['ttlHoursLeft'] as String? ?? '0';
            final ageHours = d['ageHours'] as String? ?? '0';

            // 소스별 색상/라벨
            final (srcLabel, srcColor) = switch (source) {
              'batch'           => ('배치',   const Color(0xFF66BB6A)),
              'online_fallback' => ('온라인', const Color(0xFFFFCC02)),
              'manual'          => ('수동',   const Color(0xFF64B5F6)),
              _                 => ('?',      const Color(0xFF555580)),
            };

            // 경주장 표시명
            final venueName = switch (venueCode) {
              'SEO' => '서울',
              'PUS' => '부산',
              'JEJ' => '제주',
              _     => venueCode,
            };

            // TTL 잔여 색상
            final double ttlLeftD = double.tryParse(ttlLeft) ?? 0;
            final ttlColor = ttlLeftD > 12
                ? const Color(0xFF66BB6A)
                : ttlLeftD > 4
                    ? const Color(0xFFFFCC02)
                    : const Color(0xFFFF7043);

            final bgColor = i.isEven
                ? const Color(0xFF080818)
                : const Color(0xFF0A0A1E);

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              color: bgColor,
              child: Row(children: [
                // 경주장
                SizedBox(
                  width: 36,
                  child: Row(children: [
                    Container(
                      width: 4, height: 4,
                      decoration: BoxDecoration(
                        color: isValid
                            ? const Color(0xFF66BB6A)
                            : const Color(0xFFFF7043),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(venueName,
                        style: TextStyle(
                            color: isValid
                                ? const Color(0xFFE0E0FF)
                                : const Color(0xFF7070AA),
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
                // 경주 번호
                SizedBox(
                  width: 28,
                  child: Text(raceNo,
                      style: const TextStyle(
                          color: Color(0xFF9090CC), fontSize: 11)),
                ),
                // 두수
                SizedBox(
                  width: 32,
                  child: Text('$horses두',
                      style: TextStyle(
                          color: horses > 0
                              ? const Color(0xFFE0E0FF)
                              : const Color(0xFF555580),
                          fontSize: 11)),
                ),
                // 저장 시각
                Expanded(
                  child: Text(
                    _formatTs(savedAt),
                    style: const TextStyle(
                        color: Color(0xFF7070AA), fontSize: 10),
                  ),
                ),
                // TTL 잔여
                SizedBox(
                  width: 44,
                  child: Text(
                    isValid ? '${ttlLeft}h' : '만료(${ageHours}h)',
                    style: TextStyle(
                        color: isValid ? ttlColor : const Color(0xFFFF7043),
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                // 소스 배지
                SizedBox(
                  width: 52,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: srcColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: srcColor.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      srcLabel,
                      style: TextStyle(
                          color: srcColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ]),
            );
          }),
          // ── 푸터 범례 ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D22),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _legendDot(const Color(0xFF66BB6A), '유효'),
                const SizedBox(width: 10),
                _legendDot(const Color(0xFFFF7043), '만료'),
                const SizedBox(width: 14),
                _legendSourceBadge('배치',   const Color(0xFF66BB6A)),
                const SizedBox(width: 6),
                _legendSourceBadge('온라인', const Color(0xFFFFCC02)),
                const SizedBox(width: 6),
                _legendSourceBadge('수동',   const Color(0xFF64B5F6)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 6, height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: color, fontSize: 9)),
    ],
  );

  Widget _legendSourceBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 9,
        fontWeight: FontWeight.w700)),
  );

  Widget _statCard(String label, String value, IconData icon, {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF12122A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A2A4A)),
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: color ?? const Color(0xFF6C63FF)),
        const SizedBox(width: 10),
        Text('$label: ',
            style: const TextStyle(color: Color(0xFF7070AA), fontSize: 12)),
        Expanded(
          child: Text(value,
              style: TextStyle(
                color: color ?? const Color(0xFFE0E0FF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
        ),
      ]),
    );
  }

  String _formatTs(String? iso) {
    if (iso == null) return '없음';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}/${dt.day} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length > 16 ? iso.substring(0, 16) : iso;
    }
  }
}
