# 🏇 경마통 Race Master

> **AI 기반 경마 시뮬레이터** — 서울·부산경남·제주 경마장 실제 도면 기반 모의레이스 엔진

[![Deploy to Cloudflare Pages](https://github.com/YOUR_GITHUB_ID/race-master/actions/workflows/deploy.yml/badge.svg)](https://github.com/YOUR_GITHUB_ID/race-master/actions/workflows/deploy.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.35.4-blue?logo=flutter)](https://flutter.dev)
[![Live](https://img.shields.io/badge/Live-www.boratalk.live-brightgreen)](https://www.boratalk.live)

---

## 🌐 라이브 서비스

**https://www.boratalk.live**

---

## 🏟️ 지원 경마장

| 경마장 | 진행 방향 | 지원 거리 | 트랙 특징 |
|--------|-----------|-----------|-----------|
| 🏟️ **서울** | CCW | 1200~2300m | 2단 트랙 (내측/외측 레인) |
| 🏟️ **부산경남** | CCW | 1200~2300m | 2단 트랙 (내측/외측 레인) |
| 🏟️ **제주** | CCW | 800~1610m | 세로형 오벌, 1400m 1주 |

---

## 🎮 주요 기능

- **AI 모의 레이스** — 실제 경마 물리 법칙 기반 시뮬레이션
- **3단계 경마 물리**
  - 1단계 코너: 감속 + 병목 클러스터 현상
  - 2단계 직선 400~200m: 가점 부스터 풀가속 + 추월 이펙트
  - 3단계 스퍼트 100m~GOAL: 스테미나 연산 → 막판 역전극
- **실시간 순위판** — 6두 실시간 진행률 표시
- **결과 전광판** — 시상식 스타일 포디엄 애니메이션
- **KRA API 연동** — 실제 경주 데이터 조회

---

## 🏗️ 기술 스택

```
Flutter 3.35.4 / Dart 3.9.2
├── 게임루프: Ticker (60fps, Web 완전 호환)
├── 렌더링: CustomPainter (Canvas API)
├── 상태관리: StatefulWidget + TickerProviderStateMixin
├── 트랙 기하학: 실제 도면 기반 CCW 오벌 (toPoint/toAngle)
├── 격자 엔진: _GridRailEngine (Zone1~4 레인 관리)
└── 배포: Cloudflare Pages (자동 CI/CD)
```

---

## 🚀 로컬 실행

```bash
# 의존성 설치
flutter pub get

# 웹 개발 서버 실행
flutter run -d chrome

# 릴리즈 빌드
flutter build web --release

# 로컬 프리뷰 서버 (포트 5060)
cd build/web && python3 -m http.server 5060
```

---

## 📦 CI/CD 파이프라인

```
git push origin main
       ↓
GitHub Actions (ubuntu-latest)
  ├── Flutter 3.35.4 설치
  ├── flutter pub get
  ├── flutter analyze --no-fatal-infos
  ├── flutter build web --release
  └── Cloudflare Pages 배포 (build/web → www.boratalk.live)
```

### 필요한 GitHub Secrets

| Secret 이름 | 설명 | 취득 방법 |
|-------------|------|-----------|
| `CF_API_TOKEN` | Cloudflare API 토큰 | Cloudflare → My Profile → API Tokens |
| `CF_ACCOUNT_ID` | Cloudflare 계정 ID | Cloudflare → 우측 사이드바 Account ID |

---

## 📁 프로젝트 구조

```
lib/
├── main.dart                     # 앱 진입점
├── models/
│   └── race_models.dart          # HorseEntry, RaceInfo 모델
├── screens/
│   ├── home_screen.dart          # 홈 (4탭 네비게이션)
│   ├── race_animation_screen.dart # 모의레이스 메인 (핵심 엔진)
│   └── ai_analysis_screen.dart   # AI 분석 화면
├── services/
│   ├── kra_api_service.dart      # KRA 실제 API
│   └── kra_mock_service.dart     # 목 데이터 서비스
└── utils/
    └── horse_cap_colors.dart     # 마번 색상 팔레트
```

---

## 📄 저작권

© 2025 경마통 Race Master. All rights reserved.  
본 소프트웨어는 저작권법의 보호를 받습니다.
