import Cocoa
import CoreSpotlight
import FlutterMacOS
import UniformTypeIdentifiers

/// Carries `mewsic://` links into the Flutter side of the app.
///
/// A link can come from anywhere that opens URLs (Raycast, Shortcuts, the
/// `open` command) or from a Spotlight result, whose identifier is itself a
/// link. On a cold launch the link arrives before Dart is listening, so it is
/// held until Dart says it is ready and then handed over.
final class LinkRouter: NSObject, FlutterAppLifecycleDelegate {
  static let shared = LinkRouter()

  private var channel: FlutterMethodChannel?
  private var pending: [String] = []
  private var dartReady = false

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.jinwei.custom_music_player/links",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "ready":
        // Whatever arrived before Dart was listening, oldest first.
        self.dartReady = true
        result(self.pending)
        self.pending.removeAll()
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func open(_ url: URL) {
    guard url.scheme?.lowercased() == "mewsic" else { return }
    let link = url.absoluteString
    if dartReady, let channel {
      channel.invokeMethod("open", arguments: link)
    } else {
      pending.append(link)
    }
  }

  // MARK: FlutterAppLifecycleDelegate

  func handleOpen(_ urls: [URL]) -> Bool {
    let ours = urls.filter { $0.scheme?.lowercased() == "mewsic" }
    ours.forEach(open)
    return !ours.isEmpty
  }
}

/// Puts the library's albums into Spotlight.
///
/// Dart decides what changed and sends only that; this side just turns each
/// album into a searchable item. An item's identifier is the album's
/// `mewsic://` link, so picking the result needs no lookup: the identifier is
/// opened as a link.
final class SpotlightIndexer {
  static let shared = SpotlightIndexer()

  /// Every item belongs to this domain, so dropping it clears them all.
  private static let domain = "album"

  private let index = CSSearchableIndex.default()

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.jinwei.custom_music_player/spotlight",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "isAvailable":
        result(CSSearchableIndex.isIndexingAvailable())
      case "index":
        let albums = call.arguments as? [[String: Any]] ?? []
        self.index(albums, result: result)
      case "delete":
        let ids = call.arguments as? [String] ?? []
        self.index.deleteSearchableItems(withIdentifiers: ids) {
          Self.finish(result, $0)
        }
      case "deleteAll":
        self.index.deleteSearchableItems(withDomainIdentifiers: [Self.domain]) {
          Self.finish(result, $0)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func index(_ albums: [[String: Any]], result: @escaping FlutterResult) {
    let items = albums.compactMap(Self.item)
    index.indexSearchableItems(items) { Self.finish(result, $0) }
  }

  private static func item(_ album: [String: Any]) -> CSSearchableItem? {
    guard let id = album["id"] as? String,
      let title = album["title"] as? String
    else { return nil }
    let artist = album["artist"] as? String
    let year = album["year"] as? String
    let songs = album["songs"] as? Int ?? 0

    let attrs = CSSearchableItemAttributeSet(contentType: .audio)
    attrs.title = title
    attrs.displayName = title
    attrs.album = title
    if let artist {
      attrs.artist = artist
      attrs.authorNames = [artist]
    }
    // The line under the title: "Album · NAYEON · 2024 · 7 songs".
    attrs.contentDescription = ["Album", artist, year, songs == 1 ? "1 song" : "\(songs) songs"]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
    attrs.keywords = ["album", title, artist].compactMap { $0 }
    if let seconds = album["seconds"] as? Int, seconds > 0 {
      attrs.duration = NSNumber(value: seconds)
    }
    if let cover = album["cover"] as? FlutterStandardTypedData {
      attrs.thumbnailData = cover.data
    }

    let item = CSSearchableItem(
      uniqueIdentifier: id,
      domainIdentifier: domain,
      attributeSet: attrs
    )
    // The default is a month, after which an album nobody re-indexed would
    // drop out of Spotlight while still in the library.
    item.expirationDate = .distantFuture
    return item
  }

  private static func finish(_ result: @escaping FlutterResult, _ error: Error?) {
    DispatchQueue.main.async {
      if let error {
        result(FlutterError(code: "spotlight", message: error.localizedDescription, details: nil))
      } else {
        result(nil)
      }
    }
  }
}

/// Names the folder the app shares its album list in, for the Raycast
/// extension: ~/Library/Application Support/Mewsic in the user's real home.
/// Dart cannot work that out itself, because inside the sandbox HOME points
/// at the app's container. The entitlements let the app write there.
enum CatalogLocation {
  static func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.jinwei.custom_music_player/catalog",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "directory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else {
        result(nil)
        return
      }
      result(String(cString: home) + "/Library/Application Support/Mewsic")
    }
  }
}
