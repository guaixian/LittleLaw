#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#pragma comment(lib, "shell32.lib")

namespace {

using flutter::EncodableValue;

// 本机 SDK 的 shellapi.h 缺 DROPFILES/CF_HDROP 声明,按稳定 ABI 自行定义
// (结构布局自 Windows 95 起未变)。
static const UINT kCfHdrop = 15;
struct DropFilesLayout {
  DWORD pFiles;  // 结构体之后数据的偏移
  POINT pt;
  BOOL fNC;
  BOOL fWide;
};

// 文本写入剪贴板(CF_UNICODETEXT)。
bool CopyTextToClipboard(HWND hwnd, const std::wstring& text) {
  if (!OpenClipboard(hwnd)) return false;
  EmptyClipboard();
  const size_t bytes = (text.size() + 1) * sizeof(wchar_t);
  HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (!h) {
    CloseClipboard();
    return false;
  }
  memcpy(GlobalLock(h), text.c_str(), bytes);
  GlobalUnlock(h);
  const bool ok = SetClipboardData(CF_UNICODETEXT, h) != nullptr;
  CloseClipboard();
  return ok;
}

// 文件写入剪贴板(CF_HDROP):微信/QQ/飞书桌面版均支持直接粘贴。
bool CopyFileToClipboard(HWND hwnd, const std::wstring& path) {
  if (!OpenClipboard(hwnd)) return false;
  EmptyClipboard();
  const size_t dropBytes = sizeof(DropFilesLayout);
  const size_t pathBytes = (path.size() + 2) * sizeof(wchar_t);  // 双 NUL 结尾
  HGLOBAL h = GlobalAlloc(GHND, dropBytes + pathBytes);
  if (!h) {
    CloseClipboard();
    return false;
  }
  auto* df = static_cast<DropFilesLayout*>(GlobalLock(h));
  memset(df, 0, dropBytes);
  df->pFiles = sizeof(DropFilesLayout);
  df->fWide = TRUE;
  auto* dst =
      reinterpret_cast<wchar_t*>(reinterpret_cast<BYTE*>(df) + dropBytes);
  memcpy(dst, path.c_str(), (path.size() + 1) * sizeof(wchar_t));
  dst[path.size() + 1] = L'\0';
  GlobalUnlock(h);
  const bool ok = SetClipboardData(kCfHdrop, h) != nullptr;
  CloseClipboard();
  return ok;
}

// 剪贴板位图(CF_DIBV5/CF_DIB)→ BMP 文件(DIB 前补 BITMAPFILEHEADER 即可,
// 无需编码库;Flutter/Skia 可直接解码 BMP)。返回 UTF-8 路径,无图返回空。
std::string ClipboardImageToBmpFile(HWND hwnd) {
  UINT format = 0;
  if (IsClipboardFormatAvailable(CF_DIBV5)) {
    format = CF_DIBV5;
  } else if (IsClipboardFormatAvailable(CF_DIB)) {
    format = CF_DIB;
  } else {
    return "";
  }
  if (!OpenClipboard(hwnd)) return "";
  HGLOBAL h = GetClipboardData(format);
  if (!h) {
    CloseClipboard();
    return "";
  }
  void* data = GlobalLock(h);
  if (!data) {
    CloseClipboard();
    return "";
  }
  auto* bih = static_cast<BITMAPINFOHEADER*>(data);
  const DWORD palette =
      bih->biClrUsed ? bih->biClrUsed
                     : (bih->biBitCount <= 8 ? (1u << bih->biBitCount) : 0u);
  DWORD masks = 0;
  if ((bih->biBitCount == 16 || bih->biBitCount == 32) &&
      bih->biCompression == BI_BITFIELDS) {
    masks = 3;
  }
  const size_t headerSize = bih->biSize + (palette + masks) * sizeof(RGBQUAD);
  const size_t imageSize = bih->biSizeImage
                               ? bih->biSizeImage
                               : (bih->biHeight < 0 ? -bih->biHeight
                                                    : bih->biHeight) *
                                     ((((bih->biWidth * bih->biBitCount) +
                                        31) /
                                       32) *
                                      4);
  const size_t total = headerSize + imageSize;

  std::string outPath;
  {
    wchar_t dir[MAX_PATH + 1] = {0};
    GetTempPathW(MAX_PATH, dir);
    wchar_t file[MAX_PATH + 1] = {0};
    swprintf_s(file, L"%slittlelaw_paste_%lld.bmp", dir,
               static_cast<long long>(GetTickCount64()));

    BITMAPFILEHEADER fh{};
    fh.bfType = 0x4D42;  // "BM"
    fh.bfSize = static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + total);
    fh.bfOffBits = static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + headerSize);

    HANDLE out = CreateFileW(file, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                             FILE_ATTRIBUTE_NORMAL, nullptr);
    if (out != INVALID_HANDLE_VALUE) {
      DWORD written = 0;
      WriteFile(out, &fh, sizeof(fh), &written, nullptr);
      WriteFile(out, data, static_cast<DWORD>(total), &written, nullptr);
      CloseHandle(out);
      int len =
          WideCharToMultiByte(CP_UTF8, 0, file, -1, nullptr, 0, nullptr, nullptr);
      outPath.resize(len > 0 ? len - 1 : 0);
      if (len > 0) {
        WideCharToMultiByte(CP_UTF8, 0, file, -1, outPath.data(), len, nullptr,
                            nullptr);
      }
    }
  }
  GlobalUnlock(h);
  CloseClipboard();
  return outPath;
}

std::string ToUtf8(const std::wstring& w) {
  if (w.empty()) return "";
  int len =
      WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string out(len > 0 ? len - 1 : 0, '\0');
  if (len > 0) {
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, out.data(), len, nullptr,
                        nullptr);
  }
  return out;
}

std::wstring FromUtf8(const std::string& s) {
  if (s.empty()) return L"";
  int len = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring out(len > 0 ? len - 1 : 0, L'\0');
  if (len > 0) {
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, out.data(), len);
  }
  return out;
}

// 本版 EncodableValue 无 IsMap/MapValue 便捷方法,直接用 variant API。
const flutter::EncodableMap* ArgMap(const EncodableValue* v) {
  if (v == nullptr) return nullptr;
  if (!std::holds_alternative<flutter::EncodableMap>(*v)) return nullptr;
  return &std::get<flutter::EncodableMap>(*v);
}

std::string MapString(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(std::string(key)));
  if (it == map.end()) return "";
  if (!std::holds_alternative<std::string>(it->second)) return "";
  return std::get<std::string>(it->second);
}

}  // namespace

void FlutterWindow::RegisterShareChannel() {
  const std::string channelName("dev.littlelaw/share");
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      flutter_controller_->engine()->messenger(), channelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const std::string& method = call.method_name();
        const auto* args = call.arguments();
        HWND hwnd = GetHandle();
        if (method == "shareText") {
          const auto* map = ArgMap(args);
          const std::string text = map ? MapString(*map, "text") : "";
          if (text.empty()) {
            result->Error("ARG", "text required");
          } else {
            const bool ok =
                CopyTextToClipboard(hwnd, FromUtf8(text));
            result->Success(EncodableValue(ok ? "clipboard" : "failed"));
          }
        } else if (method == "shareFile") {
          const auto* map = ArgMap(args);
          const std::string path = map ? MapString(*map, "path") : "";
          if (path.empty()) {
            result->Error("ARG", "path required");
          } else {
            const bool ok =
                CopyFileToClipboard(hwnd, FromUtf8(path));
            result->Success(EncodableValue(ok ? "clipboard" : "failed"));
          }
        } else if (method == "readClipboardImage") {
          const std::string path = ClipboardImageToBmpFile(hwnd);
          if (path.empty()) {
            result->Success(EncodableValue());
          } else {
            result->Success(EncodableValue(path));
          }
        } else {
          result->NotImplemented();
        }
      });
  share_channel_ = std::move(channel);
}
