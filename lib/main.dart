import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/race_provider.dart';
import 'services/kra_server_status.dart';
import 'services/kra_bulk_sync_service.dart';
import 'services/race_snapshot_cache.dart'; // [v2.0] 심야 배치 캐시 퍼지
import 'screens/home_screen.dart';
import 'utils/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const RaceMasterApp());
}

class RaceMasterApp extends StatelessWidget {
  const RaceMasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ★ KraServerStatus: API 서버 장애 감지 전역 싱글톤
        ChangeNotifierProvider<KraServerStatus>(
          create: (_) {
            final status = KraServerStatus();
            // 앱 시작 시 즉시 1회 헬스체크 (비동기, UI 블로킹 없음)
            Future.microtask(() async {
              await status.initialCheck();
              // ★ BulkSync 스케줄러 시작 (새벽 02:00~05:00 자동 수집)
              KraBulkSyncService().startScheduler();
              // ★ [v2.0] 만료 스냅샷 정리 (TTL 36h 초과분 자동 삭제)
              //    앱 시작 시 1회 실행 — 저장 공간 효율 유지
              await RaceSnapshotCache().purgeExpired();
            });
            return status;
          },
        ),
        ChangeNotifierProvider(create: (_) => RaceProvider()),
      ],
      child: MaterialApp(
        title: '경마통',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: const HomeScreen(),
      ),
    );
  }
}
