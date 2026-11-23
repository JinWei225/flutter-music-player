#ifndef RUNNER_LINK_ROUTER_H_
#define RUNNER_LINK_ROUTER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>
#include <vector>

// Carries `mewsic://` links (from Raycast, a shortcut, `start mewsic://...`)
// into the Flutter side of the app, the way LinkRouter does on macOS.
//
// Windows starts a new process for every link, so a second Mewsic hands its
// link to the one already running (as a WM_COPYDATA message) and exits.
namespace mewsic {

// Marks a WM_COPYDATA message as a link rather than somebody else's data.
constexpr ULONG_PTR kLinkMagic = 0x4d455753;

// Points the `mewsic:` URL scheme at this executable, for the current user
// only (HKCU), so no administrator rights are needed. Done on every launch,
// so moving the folder just takes one run to repair.
void RegisterUrlProtocol();

// The first `mewsic://` argument, or an empty string when there is none.
std::string FindLink(const std::vector<std::string>& arguments);

// Whether [link] should bring the window forward. Playing, queueing and
// player controls leave whatever you were doing alone; opening an album or
// the search prompt shows the window. An empty link (a plain second launch)
// shows it too.
bool WantsForeground(const std::string& link);

// Brings [window] to the front, restoring it if minimised.
void RaiseWindow(HWND window);

// Hands [link] to a Mewsic that is already running. Returns false when there
// is none, in which case this process should carry on and be the app.
bool ForwardToRunningInstance(const std::string& link);

// The Dart end of the links channel.
class LinkRouter {
 public:
  void Attach(flutter::BinaryMessenger* messenger);

  // Delivers [link] now, or holds it until Dart says it is listening.
  void Open(const std::string& link);

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::vector<std::string> pending_;
  bool dart_ready_ = false;
};

}  // namespace mewsic

#endif  // RUNNER_LINK_ROUTER_H_
