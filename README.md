# 栞间 / 第三方拷贝漫画客户端


## 功能
反馈请加Q群：1104352977
- **书架**：继续阅读、更新提醒（新 N 话），可按连载状态筛选、按阅读或更新时间排序
- **发现**：题材筛选、今日更新、日 / 周 / 月 / 总排行
- **搜索**：作品名和作者一起搜，关键词高亮
- **作品详情**：多分组章节、按百话分段浏览、一键定位到在读那一话
- **阅读器**：单页或条漫、左右翻页方向、双击缩放、省流画质、页面亮度，话末自动接上下一话
- **应用内更新**：自动检查本仓库的 Releases

## 下载

在 [Releases](https://github.com/luminacry/-kan-JIAN/releases) 下载：

- **Android**：`kanjian-vX.Y.Z.apk`，需要 Android 7.0 及以上。
- **iOS**：`kanjian-vX.Y.Z-unsigned.ipa`，需要 iOS 26 及以上。安装包未签名，用 Sideloadly、AltStore 等工具以自己的 Apple ID 签名后安装。

## 构建

需要 Flutter 3.47 及以上。

```bash
flutter pub get
flutter run
flutter test
flutter build apk --release
```

Android 正式版签名读取 `android/key.properties`，这个文件不在仓库里；没有它时会用 debug 签名打包。

iOS 安装包由 GitHub Actions 在 macOS 上构建（`.github/workflows/ios-ipa.yml`），也可以在本机用 `flutter build ios --release --no-codesign` 构建。

发布新版本：先修改 `pubspec.yaml` 的 `version`，再新建 tag 为 `vX.Y.Z` 的 Release 并附上 APK；工作流会自动把 IPA 附到同一个 Release。应用会据此提示用户更新。

## 声明

栞间只是一个阅读器：不内置任何账号，不绕过付费或会员限制，也不提供批量下载。作品内容实时来自第三方源站，版权归原作者和权利人所有。
