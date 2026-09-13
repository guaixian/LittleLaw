#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <shlwapi.h>
#include <objbase.h>
#include <wincodec.h>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "windowscodecs.lib")

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

// HBITMAP → PNG 文件(WIC 编码)。失败返回 false(调用方回退 BMP)。
bool SaveHbitmapToPng(HBITMAP bmp, const wchar_t* path) {
  // COM 已初始化或并发模式不符均可继续使用 STA 工厂。
  HRESULT hrInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  bool ok = false;
  IWICImagingFactory* factory = nullptr;
  IWICBitmap* wicBmp = nullptr;
  IStream* fileStream = nullptr;
  IWICBitmapEncoder* encoder = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                 CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(&factory))) &&
      SUCCEEDED(factory->CreateBitmapFromHBITMAP(
          bmp, nullptr, WICBitmapIgnoreAlpha, &wicBmp)) &&
      SUCCEEDED(SHCreateStreamOnFileW(path, STGM_CREATE | STGM_WRITE,
                                      &fileStream)) &&
      SUCCEEDED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                       &encoder)) &&
      SUCCEEDED(encoder->Initialize(fileStream, WICBitmapEncoderNoCache))) {
    IWICBitmapFrameEncode* frame = nullptr;
    IPropertyBag2* props = nullptr;
    if (SUCCEEDED(encoder->CreateNewFrame(&frame, &props)) &&
        SUCCEEDED(frame->Initialize(props)) &&
        SUCCEEDED(frame->WriteSource(wicBmp, nullptr)) &&
        SUCCEEDED(frame->Commit()) && SUCCEEDED(encoder->Commit())) {
      ok = true;
    }
    if (props) props->Release();
    if (frame) frame->Release();
  }
  if (encoder) encoder->Release();
  if (fileStream) fileStream->Release();
  if (wicBmp) wicBmp->Release();
  if (factory) factory->Release();
  if (SUCCEEDED(hrInit)) CoUninitialize();
  return ok;
}

// 剪贴板位图(CF_DIBV5/CF_DIB)→ 图片文件。
// 首选 PNG(WIC,体积小);WIC 不可用时回退 BMP(直接拼文件头)。
// 返回 UTF-8 路径,无图返回空。
std::string ClipboardImageToFile(HWND hwnd) {
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

  HDC hdc = GetDC(nullptr);
  HBITMAP bmp = CreateDIBitmap(hdc, bih, CBM_INIT,
                               reinterpret_cast<const BYTE*>(data) + headerSize,
                               reinterpret_cast<BITMAPINFO*>(bih),
                               DIB_RGB_COLORS);
  ReleaseDC(nullptr, hdc);

  std::string outPath;
  if (bmp) {
    wchar_t dir[MAX_PATH + 1] = {0};
    GetTempPathW(MAX_PATH, dir);
    wchar_t pngFile[MAX_PATH + 1] = {0};
    wchar_t bmpFile[MAX_PATH + 1] = {0};
    const long long stamp = static_cast<long long>(GetTickCount64());
    swprintf_s(pngFile, L"%slittlelaw_paste_%lld.png", dir, stamp);
    swprintf_s(bmpFile, L"%slittlelaw_paste_%lld.bmp", dir, stamp);

    const wchar_t* chosen = nullptr;
    if (SaveHbitmapToPng(bmp, pngFile)) {
      chosen = pngFile;
    } else {
      // BMP 兜底:文件头 + 原始 DIB 直接落盘。
      BITMAPFILEHEADER fh{};
      fh.bfType = 0x4D42;  // "BM"
      fh.bfSize = static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + total);
      fh.bfOffBits =
          static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + headerSize);
      HANDLE out = CreateFileW(bmpFile, GENERIC_WRITE, 0, nullptr,
                               CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (out != INVALID_HANDLE_VALUE) {
        DWORD written = 0;
        WriteFile(out, &fh, sizeof(fh), &written, nullptr);
        WriteFile(out, data, static_cast<DWORD>(total), &written, nullptr);
        CloseHandle(out);
        chosen = bmpFile;
      }
    }
    DeleteObject(bmp);
    if (chosen) {
      int len = WideCharToMultiByte(CP_UTF8, 0, chosen, -1, nullptr, 0,
                                    nullptr, nullptr);
      outPath.resize(len > 0 ? len - 1 : 0);
      if (len > 0) {
        WideCharToMultiByte(CP_UTF8, 0, chosen, -1, outPath.data(), len,
                            nullptr, nullptr);
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
          const std::string path = ClipboardImageToFile(hwnd);
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
