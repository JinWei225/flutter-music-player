#include "link_router.h"

#include <flutter/standard_method_codec.h>

namespace mewsic {

namespace {

// Must match kWindowClassName in win32_window.cpp and the title main.cpp
// gives the window; together they find a running Mewsic.
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kWindowTitle[] = L"Mewsic";

constexpr char kScheme[] = "mewsic://";

bool StartsWith(const std::string& text, const char* prefix) {
  return text.rfind(prefix, 0) == 0;
}

void SetRegistryString(const wchar_t* key, const wchar_t* name,
                       const std::wstring& value) {
  ::RegSetKeyValueW(HKEY_CURRENT_USER, key, name, REG_SZ, value.c_str(),
                    static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
}

// Records where Mewsic.exe is in %USERPROFILE%\.mewsic\app.txt. Raycast is a
// packaged app and may not see the URL handler registered below, so its
// extension starts this executable directly, finding it from this file.
void WriteExecutablePath(const wchar_t* exe) {
  wchar_t profile[MAX_PATH];
  const DWORD length = ::GetEnvironmentVariableW(L"USERPROFILE", profile, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return;
  const std::wstring folder = std::wstring(profile) + L"\\.mewsic";
  ::CreateDirectoryW(folder.c_str(), nullptr);

  const int size = ::WideCharToMultiByte(CP_UTF8, 0, exe, -1, nullptr, 0,
                                         nullptr, nullptr);
  if (size <= 1) return;
  std::string utf8(size - 1, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, exe, -1, utf8.data(), size, nullptr,
                        nullptr);

  HANDLE file = ::CreateFileW((folder + L"\\app.txt").c_str(), GENERIC_WRITE,
                              FILE_SHARE_READ, nullptr, CREATE_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  ::WriteFile(file, utf8.data(), static_cast<DWORD>(utf8.size()), &written,
              nullptr);
  ::CloseHandle(file);
}

}  // namespace

void RegisterUrlProtocol() {
  wchar_t exe[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return;

  WriteExecutablePath(exe);

  SetRegistryString(L"Software\\Classes\\mewsic", nullptr, L"URL:Mewsic");
  SetRegistryString(L"Software\\Classes\\mewsic", L"URL Protocol", L"");
  SetRegistryString(L"Software\\Classes\\mewsic\\shell\\open\\command", nullptr,
                    std::wstring(L"\"") + exe + L"\" \"%1\"");
}

std::string FindLink(const std::vector<std::string>& arguments) {
  for (const auto& argument : arguments) {
    if (StartsWith(argument, kScheme)) return argument;
  }
  return std::string();
}

bool WantsForeground(const std::string& link) {
  if (link.empty()) return true;
  if (StartsWith(link, "mewsic://search")) return true;
  // An album link with no action just opens the album's page.
  if (StartsWith(link, "mewsic://album") &&
      link.find("action=") == std::string::npos) {
    return true;
  }
  return false;
}

void RaiseWindow(HWND window) {
  if (::IsIconic(window)) ::ShowWindow(window, SW_RESTORE);
  ::SetForegroundWindow(window);
}

bool ForwardToRunningInstance(const std::string& link) {
  HWND running = ::FindWindowW(kWindowClassName, kWindowTitle);
  if (running == nullptr) return false;

  // We were just started by whatever the user was using, so we may let the
  // running app take the foreground on our behalf.
  ::AllowSetForegroundWindow(ASFW_ANY);

  COPYDATASTRUCT data;
  data.dwData = kLinkMagic;
  data.cbData = static_cast<DWORD>(link.size());
  data.lpData = const_cast<char*>(link.data());
  DWORD_PTR ignored = 0;
  return ::SendMessageTimeoutW(running, WM_COPYDATA, 0,
                               reinterpret_cast<LPARAM>(&data),
                               SMTO_ABORTIFHUNG, 5000, &ignored) != 0;
}

void LinkRouter::Attach(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.jinwei.custom_music_player/links",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "ready") {
          // Whatever arrived before Dart was listening, oldest first.
          dart_ready_ = true;
          flutter::EncodableList early;
          for (const auto& link : pending_) early.emplace_back(link);
          pending_.clear();
          result->Success(flutter::EncodableValue(early));
        } else {
          result->NotImplemented();
        }
      });
}

void LinkRouter::Open(const std::string& link) {
  if (dart_ready_ && channel_) {
    channel_->InvokeMethod(
        "open", std::make_unique<flutter::EncodableValue>(link));
  } else {
    pending_.push_back(link);
  }
}

}  // namespace mewsic
