# Build iOS CineViet bằng Codemagic

## Thông tin bản iOS hiện tại

- Flutter version trong app: `1.0.1+5054`
- iOS Bundle ID: `live.cineviet.cinevietios`
- Firebase iOS plist: `ios/Runner/GoogleService-Info.plist`
- GA4 iOS: `IS_ANALYTICS_ENABLED = true`
- Codemagic config: `codemagic.yaml`
- Workflow: `ios-release`

## Kiểm tra đã chuẩn bị trong source

Đã cập nhật các file:

```text
ios/Runner.xcodeproj/project.pbxproj
ios/Runner/GoogleService-Info.plist
codemagic.yaml
pubspec.yaml
```

Bundle ID trong Xcode project và Codemagic:

```text
live.cineviet.cinevietios
```

Firebase plist đang bật Analytics:

```xml
<key>IS_ANALYTICS_ENABLED</key>
<true></true>
```

## Cách build trên Codemagic

### 1. Push source lên Git

Codemagic cần lấy source từ GitHub/GitLab/Bitbucket. Push thư mục app:

```text
/var/www/cinevietapp
```

lên repository đang kết nối với Codemagic.

### 2. Vào Codemagic

1. Mở https://codemagic.io/apps
2. Chọn app/repository CineViet.
3. Chọn workflow:

```text
ios-release
```

4. Bấm **Start new build**.

### 3. Nếu chỉ cần file IPA unsigned để kiểm tra build

Workflow hiện tại đang chạy:

```bash
flutter build ipa --release --no-codesign
```

Artifact sau build:

```text
build/ios/ipa/*.ipa
build/ios/archive/*.xcarchive
```

Lưu ý: IPA `--no-codesign` dùng để kiểm tra build/archive, chưa cài được lên iPhone và chưa upload TestFlight.

### 4. Nếu muốn upload TestFlight/App Store

Cần cấu hình iOS signing trong Codemagic:

- Apple Developer account.
- App Store Connect API key hoặc Apple ID integration.
- App identifier đúng:

```text
live.cineviet.cinevietios
```

- iOS Distribution certificate.
- Provisioning profile cho bundle ID trên.

Sau đó đổi bước build từ:

```bash
flutter build ipa --release --no-codesign
```

sang build có signing, ví dụ:

```bash
flutter build ipa --release \
  --export-options-plist=/Users/builder/export_options.plist
```

hoặc dùng iOS code signing tự động của Codemagic theo hướng dẫn trong UI.

## Kiểm tra sau khi build xong

Trong Codemagic artifacts, tải:

```text
*.ipa
*.xcarchive
```

Nếu build fail, xem log ở:

```text
/tmp/xcodebuild_logs/*.log
```

## Ghi chú

Host hiện tại là Linux nên không thể build iOS trực tiếp tại server này. iOS cần macOS/Xcode, vì vậy phải build qua Codemagic hoặc máy Mac.
