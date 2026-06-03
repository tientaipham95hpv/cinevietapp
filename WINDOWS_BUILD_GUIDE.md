# CineViet Windows Build Guide

Server hiện tại là Linux nên không build trực tiếp file `.exe` Windows được. Flutter Windows cần chạy trên **máy Windows** có Visual Studio C++ toolchain.

## 1) Chuẩn bị máy Windows

Cài:

1. **Flutter SDK**: https://docs.flutter.dev/get-started/install/windows
2. **Visual Studio 2022 Community**: https://visualstudio.microsoft.com/vs/community/
   - Chọn workload: **Desktop development with C++**
   - Cần MSVC, Windows SDK, CMake tools.
3. Git.

Kiểm tra:

```powershell
flutter doctor
flutter config --enable-windows-desktop
```

`flutter doctor` phải báo Windows toolchain OK.

## 2) Lấy source

```powershell
git clone https://github.com/tientaipham95hpv/cinevietapp.git
cd cinevietapp
```

Nếu đã có source rồi thì chỉ cần:

```powershell
git pull origin main
```

## 3) Build Windows release

Cách nhanh bằng script đã chuẩn bị:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\build_windows_release.ps1
```

Hoặc build thủ công:

```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter clean
flutter build windows --release
```

## 4) File output

Sau khi build xong:

```text
build\windows\x64\runner\Release\CineViet.exe
```

Lưu ý: Không chỉ gửi mỗi `.exe`; app Windows Flutter cần kèm thư mục `data/` và các file `.dll` bên cạnh.

Script sẽ đóng gói đầy đủ thành:

```text
build\windows\package\CineViet-Windows-1.0.1.zip
```

## 5) Đưa lên trang tải

Gửi file ZIP này cho Thảo hoặc upload lên server:

```text
/var/www/html/apk/cineviet-windows.zip
```

Public URL:

```text
https://cineviet.live/download/cineviet-windows.zip
```

Sau khi có file, đổi nút Windows trên `/tai-ung-dung` từ `Chưa có file EXE` sang tải file thật.

## 6) Nếu muốn installer `.exe`

Flutter mặc định xuất app portable folder. Nếu muốn installer `.exe`, dùng thêm Inno Setup hoặc MSIX.

Khuyến nghị đơn giản hiện tại:

- Build ra folder release.
- Zip folder release.
- Cho người dùng tải ZIP, giải nén và chạy `CineViet.exe`.

