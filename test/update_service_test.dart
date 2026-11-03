import 'package:flutter_test/flutter_test.dart';
import 'package:pastemangax/core/update_service.dart';
import 'package:pastemangax/pages/update_dialog.dart';

Map<String, dynamic> release({String tag = 'v0.3.0', List<Map<String, dynamic>>? assets, String body = '## 更新\n- 书架排序\n- **省流**画质'}) => {
      'tag_name': tag,
      'name': '栞间 $tag',
      'body': body,
      'html_url': 'https://github.com/luminacry/-kan-JIAN/releases/tag/$tag',
      'published_at': '2026-11-05T08:00:00Z',
      'assets': assets ??
          [
            {'name': 'checksums.txt', 'size': 120, 'browser_download_url': 'https://example.com/checksums.txt'},
            {'name': 'kanjian-arm64-v8a.apk', 'size': 12000000, 'browser_download_url': 'https://example.com/arm64.apk'},
            {'name': 'kanjian-0.3.0.apk', 'size': 19293798, 'browser_download_url': 'https://example.com/universal.apk'},
          ],
    };

void main() {
  group('版本号', () {
    test('从 tag 里取出版本号', () {
      expect(normalizeVersion('v0.3.0'), '0.3.0');
      expect(normalizeVersion('0.3'), '0.3.0');
      expect(normalizeVersion('release-1.2.0'), '1.2.0');
      expect(normalizeVersion('v1.0.0-beta.2'), '1.0.0');
      expect(normalizeVersion('latest'), isNull);
    });

    test('按数字比较，不按字符串', () {
      expect(compareVersions('0.3.0', '0.2.0'), greaterThan(0));
      expect(compareVersions('v0.2', '0.2.0'), 0);
      expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('0.2.0+5', '0.2.0'), 0);
      expect(compareVersions('0.1.9', '0.2.0'), lessThan(0));
    });
  });

  group('GitHub 响应', () {
    test('仓库还没有发布版本（404）', () {
      final r = UpdateService.resolve(404, {'message': 'Not Found'}, '0.2.0');
      expect(r.status, UpdateStatus.noRelease);
      expect(r.message, contains('还没有发布'));
    });

    test('限流（403）不当作没有更新', () {
      expect(UpdateService.resolve(403, {'message': 'API rate limit exceeded'}, '0.2.0').status, UpdateStatus.failed);
    });

    test('有新版本：优先选通用 APK，带大小和发布日期', () {
      final r = UpdateService.resolve(200, release(), '0.2.0');
      expect(r.status, UpdateStatus.available);
      expect(r.release!.version, '0.3.0');
      expect(r.release!.apkUrl, 'https://example.com/universal.apk');
      expect(r.release!.apkSize, 19293798);
      expect(r.release!.publishedAt!.toUtc(), DateTime.utc(2026, 11, 5, 8));
    });

    test('版本相同或更旧：已是最新', () {
      expect(UpdateService.resolve(200, release(tag: 'v0.2.0'), '0.2.0').status, UpdateStatus.upToDate);
      expect(UpdateService.resolve(200, release(tag: 'v0.1.0'), '0.2.0').status, UpdateStatus.upToDate);
    });

    test('没有 APK 附件时下载地址退回 Release 页面', () {
      final r = UpdateService.resolve(200, release(assets: const []), '0.2.0');
      expect(r.release!.apkUrl, isNull);
      expect(r.release!.downloadUrl, contains('/releases/tag/v0.3.0'));
    });

    test('标签不是版本号时报错', () {
      expect(UpdateService.resolve(200, release(tag: 'nightly'), '0.2.0').status, UpdateStatus.failed);
    });

    test('其他状态码报错并带上状态码', () {
      final r = UpdateService.resolve(400, null, '0.2.0');
      expect(r.status, UpdateStatus.failed);
      expect(r.message, contains('400'));
    });
  });

  test('Release 说明去掉 Markdown 记号', () {
    expect(plainNotes('## 更新\n- 书架排序\n* **省流**画质\n\n\n\n`fix`'), '更新\n• 书架排序\n• 省流画质\n\nfix');
  });
}
