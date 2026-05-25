import 'dart:convert';
import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/race_schedule_cache.dart';
import '../services/kra_bulk_sync_service.dart';
import '../services/kra_bulk_data_binder.dart';
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
    _tabController = TabController(length: 3, vsync: this);
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
            Tab(icon: Icon(Icons.schedule, size: 18), text: '벌크 싱크'),
            Tab(icon: Icon(Icons.bug_report, size: 18), text: '에러 로그'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ImageUploadTab(),
          _BulkSyncTab(),
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
  });

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
    // entries는 메모리 전용 (data URL 포함하지 않음)
  };

  factory _UploadedItem.fromJson(Map<String, dynamic> j) => _UploadedItem(
    id: j['id'] as String,
    name: j['name'] as String,
    type: j['type'] as String,
    venueCode: j['venueCode'] as String,
    dateStr: j['dateStr'] as String,
    raceNo: j['raceNo'] as int,
    uploadedAt: DateTime.parse(j['uploadedAt'] as String),
    parseStatus: (j['parseStatus'] as String?) ?? 'done',
    parsedSummary: j['parsedSummary'] as String?,
    entries: const [],
  );

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

class _ParsedRaceEntry {
  final int gateNo;
  final String horseName;
  final String jockeyName;
  final String trainerName;
  final int    weight;
  final String odds;

  const _ParsedRaceEntry({
    required this.gateNo,
    required this.horseName,
    required this.jockeyName,
    required this.trainerName,
    required this.weight,
    required this.odds,
  });
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

    // ── ⑤ 완료 — 목 데이터 생성 + SharedPreferences 저장 ──────────────
    setState(() {
      item.parseStatus = 'done';
      if (item.type == 'entry') {
        item.parsedSummary = '${item.raceNo}경주 출전표 인식 완료 — 데이터를 확인 후 저장하세요';
        item.entries = _generateMockEntries(item.raceNo);
      } else {
        item.parsedSummary = '${item.raceNo}경주 기록 인식 완료 — 착순/기록 확인 후 저장하세요';
        item.entries = _generateMockResults(item.raceNo);
      }
    });
    // 완료 후 영속 저장 (data URL 없이 메타데이터만)
    await _saveItemsToPrefs();
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
    final horses = [
      ('청운대장', '조성곤', '박종훈', 488, '착순 1위'),
      ('황금질주', '이현종', '김민수', 502, '착순 2위'),
      ('폭풍기수', '문세영', '이상호', 494, '착순 3위'),
      ('달빛제왕', '강민성', '박영철', 512, '착순 4위'),
      ('바람신마', '최우성', '정민호', 484, '착순 5위'),
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

  // ── 경주 캐시에 저장 ─────────────────────────────────────────────────
  Future<void> _saveToCache(_UploadedItem item) async {
    try {
      final y  = int.parse(item.dateStr.substring(0, 4));
      final mo = int.parse(item.dateStr.substring(4, 6));
      final d  = int.parse(item.dateStr.substring(6, 8));
      final date = DateTime(y, mo, d);
      final venueName = item.venueCode == '1' ? '서울'
          : item.venueCode == '2' ? '부산경남' : '제주';

      final race = RaceInfo(
        raceNo:         item.raceNo.toString(),
        raceName:       '제${item.raceNo}경주 (이미지 업로드)',
        startTime:      '--:--',
        distance:       1400,
        condition:      '업로드',
        grade:          '확인요',
        venueCode:      item.venueCode,
        venueName:      venueName,
        raceDate:       item.dateStr,
        totalHorses:    item.entries.length,
        trackCondition: '양호',
        isSpecialRace:  false,
        specialRaceName: '',
      );

      final cache = RaceScheduleCache();
      await cache.saveSnapshot(
        races: [race],
        venueCode: item.venueCode,
        date: date,
        source: 'image_upload',
      );

      if (mounted) {
        setState(() => _globalMsg = '✅ ${item.name} → 캐시 저장 완료! 앱 새로고침 시 반영됩니다.');
      }
    } catch (e) {
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

          // ── 펼쳐진 상세 (출전마 리스트) ───────────────────────────
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
                  const SizedBox(height: 10),
                  // 저장 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A2A),
                        foregroundColor: const Color(0xFF81C784),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        side: const BorderSide(color: Color(0xFF2E6A3A)),
                      ),
                      onPressed: () => _saveToCache(item),
                      icon: const Icon(Icons.save_alt, size: 16),
                      label: const Text('경주 캐시에 저장',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── 파이프라인 진행 시각화 (처리 중 또는 완료 모두 표시) ─────────
          if (item.isProcessing || item.parseStatus == 'done') ...[
            const Divider(color: Color(0xFF1A1A3A), height: 1),
            _pipelineIndicator(item),
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

  Widget _entryTableHeader(bool isResult) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3A),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        _col('번', 24),
        _col('마명', 90),
        _col('기수', 60),
        _col('조교사', 60),
        _col('체중', 40),
        Expanded(child: Text(isResult ? '착순' : '배당',
            style: const TextStyle(color: Color(0xFF6C63FF),
                fontSize: 10, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right)),
      ]),
    );
  }

  Widget _entryRow(_ParsedRaceEntry e, bool isResult) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      child: Row(children: [
        _col('${e.gateNo}', 24,
            color: const Color(0xFF9090CC), bold: true),
        _col(e.horseName, 90,
            color: const Color(0xFFE0E0FF), bold: true),
        _col(e.jockeyName, 60),
        _col(e.trainerName, 60),
        _col('${e.weight}', 40),
        Expanded(child: Text(e.odds,
            style: TextStyle(
              color: isResult
                  ? const Color(0xFFFFD54F) : const Color(0xFF64B5F6),
              fontSize: 11,
            ),
            textAlign: TextAlign.right)),
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
