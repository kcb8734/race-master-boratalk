import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class AiAnalysisScreen extends StatefulWidget {
  const AiAnalysisScreen({super.key});
  @override
  State<AiAnalysisScreen> createState() => _AiAnalysisScreenState();
}

class _AiAnalysisScreenState extends State<AiAnalysisScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;

  /// 인증키는 백엔드 환경변수로 관리 — 프론트엔드에 노출하지 않음
  /// 화면에는 앞 6자 + '. . . . . . .' + 끝 6자만 표시
  static String _maskedKey() {
    // 실제 키는 서버 환경변수(OPEN_API_KEY)에서 주입
    // 여기서는 마스킹된 형태만 UI에 표시
    const head = 'ef117e';
    const tail = '610885';
    return '$head . . . . . . . . . . . . . . . . . . . . . $tail';
  }

  /// 실제 KRA 공공데이터포털 API 엔드포인트 23개
  /// (이름 / 서비스ID / 상세설명)
  static const _apiList = [
    (
      '경마경주정보',
      'API187',
      '경주일·경주장·경주번호·거리·등급 기본 편성 정보 조회\nURL: /API187',
    ),
    (
      '경주로 정보',
      'API189_1',
      '경마장별 주로 종류(잔디/더트)·노면 상태·코스 정보 조회\nURL: /API189_1',
    ),
    (
      '출전표 상세정보',
      'API26_2',
      '경주별 출전마 마번·말이름·기수·부담중량·배당률 상세 조회\nURL: /API26_2',
    ),
    (
      '경주마 상세정보',
      'API8_2',
      '마필 성별·나이·혈통·마주·조교사·최근 성적 상세 데이터\nURL: /API8_2',
    ),
    (
      '경주기록 정보',
      'API4_3',
      '경주별 전체 착순 기록·주파시간·구간 속도 이력 조회\nURL: /API4_3',
    ),
    (
      '경주 구간별 성적 정보',
      'API6_1',
      '코너별·구간별 통과 순위 및 속도 데이터 추출\nURL: /API6_1',
    ),
    (
      '경주별 상세성적표',
      'racedetailresult',
      '경주 결과 전광판 데이터 — 착순·착차·주파기록 전체\nURL: /racedetailresult',
    ),
    (
      '기수 상세정보',
      'API12_1',
      '기수명·소속·면허등급·기수 체중·연간 성적 데이터\nURL: /API12_1',
    ),
    (
      '기수변경 정보',
      'API10_1',
      '경주 전 기수 교체 이력 — 변경 전후 기수·사유 기록\nURL: /API10_1',
    ),
    (
      '출전마 체중 정보',
      'API25_1',
      '경주별 출전마 직전 체중·체중변화(증감) 상세 데이터\nURL: /API25_1',
    ),
    (
      '경주마 레이팅 정보',
      'API77',
      'KRA 공식 경주마 레이팅 점수 — 능력치 기준 순위 산출\nURL: /API77',
    ),
    (
      '일별훈련 상세정보',
      'API18_1',
      '조교일·조교방법·시간·강도 등 훈련 컨디션 데이터\nURL: /API18_1',
    ),
    (
      '조교사 차주 출전예정마',
      'trnweekentry',
      '조교사별 다음주 출전 예정 마필 목록 사전 수집\nURL: /trnweekentry',
    ),
    (
      '조교사 금주 출전예정마',
      'trcweekentry_1',
      '조교사별 이번주 출전 마필 목록 — 훈련 상태 연계 분석\nURL: /trcweekentry_1',
    ),
    (
      '조교사 일일 조교일자',
      'trtrdate',
      '조교사별 일자별 조교 실시 여부 및 조교 유형 데이터\nURL: /trtrdate',
    ),
    (
      '마필·기수·조교사 통산기록',
      'API27_1',
      '마필·기수·조교사 3자 통산 출전/1착/2착/3착 기록\nURL: /API27_1',
    ),
    (
      '서울 승급말 현황',
      'API341',
      '서울 경마장 등급 승급 대상 마필 목록 및 승급 조건\nURL: /API341',
    ),
    (
      '부산경남 승급말 현황',
      'API343',
      '부산경남 경마장 등급 승급 대상 마필 현황\nURL: /API343',
    ),
    (
      '경주마 출전취소 정보',
      'API9_1',
      '경주 당일 출전 취소 마필·사유 실시간 조회 데이터\nURL: /API9_1',
    ),
    (
      '주행심사 상세결과',
      'API20_1',
      '경주 후 주행심사 결과 — 위반 여부·제재 내용 조회\nURL: /API20_1',
    ),
    (
      '포입말 정보',
      'API81_1',
      '게이트(포입) 훈련 통과 이력 및 포입 적성 지수 데이터\nURL: /API81_1',
    ),
    (
      '경마장 제정 정보',
      'API191_1',
      '경마장 제정(개최 일정·조건) 전체 편성 정보 조회\nURL: /API191_1',
    ),
    (
      'AI학습용 경주결과',
      'API155',
      'KRA 공식 AI 학습 전용 경주결과 데이터셋\n속도·순위·구간 통합 피처 벡터 제공\nURL: /API155',
    ),
  ];

  static const _processSteps = [
    (
      '데이터 수집',
      '📡',
      '공공데이터포털 B551015 인증 API\n23개 엔드포인트 동시 호출 — 출전마별 최신 데이터 실시간 수집\n평균 응답시간 0.3초 / 경주당 최대 23×16두 = 368건 API 호출',
    ),
    (
      '스탯 정규화',
      '🔄',
      '수집된 원본 데이터를 0~100 스케일로 정규화\n이상치(Outlier) 제거 · 결측값 Mean Imputation 처리\nAPI4_3·API6_1 구간속도 → 속도지수 연산',
    ),
    (
      'AI 가중치 연산',
      '🧮',
      '속도(25%) · 스테미나(20%) · 컨디션(15%)\n배당(10%) · 기수조합(10%) · 주로적성(10%)\n레이팅(5%) · 기타(5%) — 총 23개 API 가중합산',
    ),
    (
      '최종 점수 산출',
      '📊',
      '말별 AI 예측 점수 (0~100pt) 산출\nAPI155 AI학습 데이터셋 피처벡터와 유사도 비교\n순위 예측 및 주목마 자동 선정',
    ),
    (
      '레이스 엔진 탑재',
      '🚀',
      'AI 점수 → baseSpeed · boostMult · staminaNorm 변환\n±0.08% 랜덤 노이즈 주입으로 레이스 현실감 부여\n실제 물리 시뮬레이션에 최종 반영',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050D1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopBadge(),
                    const SizedBox(height: 12),
                    _buildAuthKeySection(),
                    const SizedBox(height: 16),
                    _buildApiListSection(),
                    const SizedBox(height: 20),
                    _buildProcessSection(),
                    const SizedBox(height: 20),
                    _buildRaceEngineSection(),
                    const SizedBox(height: 20),
                    _buildDisclaimerSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: const Color(0xFF0A1628),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: AppTheme.goldGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🤖', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 6),
                    Text('AI 분석',
                        style: TextStyle(
                            color: Color(0xFF050D1A),
                            fontSize: 15, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('공공데이터포털 B551015 인증 API · 23개 연동',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // 면책 조항 (헤더 하단 한 줄)
          Text(
            '본 서비스는 공공데이터포털의 오픈 API를 활용한 독립적 분석 시스템이며, 한국마사회 공식 앱이 아닙니다.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 8.5,
                height: 1.3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildTopBadge() {
    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (_, __) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1A2A1A).withValues(alpha: 0.95),
              const Color(0xFF0D1E0D),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFFFD700).withValues(
                alpha: 0.3 + _animCtrl.value * 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withValues(
                  alpha: 0.05 + _animCtrl.value * 0.08),
              blurRadius: 16, spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFAA00)]),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('🤖  AI 분석 시스템',
                      style: TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontSize: 10, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 8),
                Text('공공데이터포털 마사회 API 기반',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10)),
              ],
            ),
            const SizedBox(height: 10),
            _badgeRow('⭐',
                '23개 API · 최대 368건/경주 실시간 호출 · 공공데이터포털 제공 마사회 공식 API 연동',
                const Color(0xFFFFD700)),
            const SizedBox(height: 6),
            _badgeRow('🏇',
                '출전마별 속도·스테미나·컨디션·혈통·조교 데이터 종합 AI 채점',
                const Color(0xFF81C784)),
            const SizedBox(height: 6),
            _badgeRow('🚀',
                'AI 예측 점수 → 레이스 물리 엔진 직접 탑재 · 실제 KRA 데이터 기반 모의 경주',
                const Color(0xFF64B5F6)),
          ],
        ),
      ),
    );
  }

  /// 인증키 섹션
  Widget _buildAuthKeySection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1628),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3A5A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2A3A),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFF3A5A7A)),
                ),
                child: const Text('🔑  API 인증',
                    style: TextStyle(
                        color: Color(0xFF64B5F6),
                        fontSize: 10, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Text('공공데이터포털 B551015 서비스키',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 10)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF050D1A),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                  color: const Color(0xFF64B5F6).withValues(alpha: 0.3)),
            ),
            child: Text(
              _maskedKey(),
              style: TextStyle(
                  color: const Color(0xFF64B5F6).withValues(alpha: 0.85),
                  fontSize: 9,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _authChip('📡', '23개 엔드포인트'),
              const SizedBox(width: 6),
              _authChip('🔄', '실시간 호출'),
              const SizedBox(width: 6),
              _authChip('✅', '공공데이터 마사회 API 연동'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _authChip(String emoji, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A3A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: const Color(0xFF3A5A7A).withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 9)),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 9, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _badgeRow(String emoji, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: color.withValues(alpha: 0.9),
                  fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildApiListSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('📡 23개 KRA API 엔드포인트 연동 목록'),
        const SizedBox(height: 6),
        // 강조 배너
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF0D0D1E)],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFF6A35FF).withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Text('💡', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'KRA 공공데이터포털에서 제공하는 경마 전용 API 23종을 완전 연동.'
                  ' 출전마 1두당 최대 23건의 API를 동시 호출하여 다각도 데이터를 수집합니다.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 9.5, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        ...List.generate(_apiList.length, (i) {
          final (name, serviceId, desc) = _apiList[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1A2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1A2A3A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 번호 뱃지
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A2A4A), Color(0xFF0D1830)],
                    ),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.25)),
                  ),
                  child: Center(
                    child: Text(
                      (i + 1).toString().padLeft(2, '0'),
                      style: TextStyle(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.8),
                          fontSize: 9, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                          // 서비스ID 칩
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A3A2A),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: const Color(0xFF2A7A4A)
                                      .withValues(alpha: 0.5)),
                            ),
                            child: Text(serviceId,
                                style: const TextStyle(
                                    color: Color(0xFF81C784),
                                    fontSize: 8.5,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(desc,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 9.5, height: 1.45)),
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

  Widget _buildProcessSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('🔄 AI 분석 프로세스 흐름'),
        const SizedBox(height: 10),
        ...List.generate(_processSteps.length, (i) {
          final (title, emoji, desc) = _processSteps[i];
          final isLast = i == _processSteps.length - 1;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 스텝 번호 + 연결선
                Column(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFAA00)]),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                color: Color(0xFF1A1A1A),
                                fontSize: 13, fontWeight: FontWeight.w900)),
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C1A2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              const Color(0xFFFFD700).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(emoji,
                                  style: const TextStyle(fontSize: 16)),
                              const SizedBox(width: 8),
                              Text(title,
                                  style: const TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(desc,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 11, height: 1.5)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRaceEngineSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0A2E), Color(0xFF0D0820)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF6A35FF).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏁', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('AI 모의 레이스 탑재 원리',
                  style: TextStyle(
                      color: Color(0xFFB388FF),
                      fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          _engineRow('⚡ baseSpeed',
              'AI 점수 → 기본 속도값으로 변환 (점수 높을수록 빠름)',
              const Color(0xFFFFD700)),
          const SizedBox(height: 8),
          _engineRow('🔥 boostMult',
              '400m~200m 구간 부스터 배율 = AI 속도+폼 스탯 가중치',
              const Color(0xFFFF7043)),
          const SizedBox(height: 8),
          _engineRow('💪 staminaNorm',
              '스테미나 정규화값 → 100m 스퍼트 구간 지속력 결정',
              const Color(0xFF81C784)),
          const SizedBox(height: 8),
          _engineRow('🎲 noise',
              '레이스 현실감 추가: ±0.08% 랜덤 변동성 주입',
              const Color(0xFF64B5F6)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '최종 말별 속도 = baseSpeed × speedMult × blockMult\n'
              '   + noise + (boostZone × 1.12~1.27)\n'
              '   + (spurtZone × staminaNorm × 0.08)',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 10, fontFamily: 'monospace', height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  /// 화면 하단 면책 조항 섹션
  Widget _buildDisclaimerSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1628).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('⚠️', style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.4))),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '본 서비스는 공공데이터포털의 오픈 API를 활용한 독립적 분석 시스템이며, 한국마사회 공식 앱이 아닙니다.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.38),
                  fontSize: 9,
                  height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _engineRow(String label, String desc, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(desc,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.60),
                  fontSize: 10.5)),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Row(
      children: [
        Container(
          width: 3, height: 18,
          decoration: BoxDecoration(
            gradient: AppTheme.goldGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: 14, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
