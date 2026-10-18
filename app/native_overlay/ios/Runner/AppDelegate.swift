import Flutter
import UIKit
import MultipeerConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var multipeer: MultipeerPlugin?
  private var privacyCover: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let controller = window?.rootViewController as! FlutterViewController
    let messenger = controller.binaryMessenger

    multipeer = MultipeerPlugin(messenger: messenger)

    // Android uses a foreground service; on iOS this is a no-op (Apple does not allow
    // indefinite background sockets). Calls keep running via the `audio` background mode.
    FlutterMethodChannel(name: "privchat/background", binaryMessenger: messenger)
      .setMethodCallHandler { _, result in result(true) }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Hide chat content in the app switcher snapshot.
  override func applicationWillResignActive(_ application: UIApplication) {
    guard let w = window, privacyCover == nil else { return }
    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    blur.frame = w.bounds
    blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    w.addSubview(blur)
    privacyCover = blur
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}

// ============================================================================
// Multipeer Connectivity transport (kept in this file so no Xcode project edits are needed)
// ============================================================================

/// iPhone ↔ iPhone transport with NO router: Apple Multipeer Connectivity
/// (Bluetooth + peer-to-peer Wi-Fi). Carries PrivChat's already-encrypted frames;
/// MCSession encryption is enabled too as defence-in-depth.
/// Peer authenticity is NOT trusted here — the PrivChat handshake (Ed25519) does that.
final class MultipeerPlugin: NSObject, FlutterStreamHandler {
  static let serviceType = "privchat-mp"   // ≤15 chars, must match Info.plist NSBonjourServices

  private let method: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var sink: FlutterEventSink?

  private var myPeer: MCPeerID?
  private var advertiser: MCNearbyServiceAdvertiser?
  private var browser: MCNearbyServiceBrowser?
  private var sessions: [String: MCSession] = [:]   // userId -> session
  private var peersById: [String: MCPeerID] = [:]   // userId -> peer
  private var names: [String: String] = [:]
  private let q = DispatchQueue(label: "privchat.multipeer")

  init(messenger: FlutterBinaryMessenger) {
    method = FlutterMethodChannel(name: "privchat/multipeer", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "privchat/multipeer/events", binaryMessenger: messenger)
    super.init()
    events.setStreamHandler(self)
    method.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
  }

  // MARK: Flutter
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events; return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }

  private func emit(_ m: [String: Any]) {
    DispatchQueue.main.async { self.sink?(m) }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "start":
      guard let uid = args["userId"] as? String, let name = args["name"] as? String else {
        result(FlutterError(code: "ARGS", message: "userId/name required", details: nil)); return
      }
      start(uid: uid, name: name); result(true)
    case "stop":
      stop(); result(true)
    case "invite":
      guard let uid = args["userId"] as? String, let peer = peersById[uid], let b = browser else { result(false); return }
      b.invitePeer(peer, to: session(for: uid, peer: peer), withContext: nil, timeout: 20)
      result(true)
    case "send":
      guard let uid = args["userId"] as? String,
            let data = (args["data"] as? FlutterStandardTypedData)?.data,
            let s = sessions[uid], let peer = peersById[uid] else { result(false); return }
      q.async {
        do { try s.send(data, toPeers: [peer], with: .reliable); DispatchQueue.main.async { result(true) } }
        catch { DispatchQueue.main.async { result(false) } }
      }
    case "disconnect":
      if let uid = args["userId"] as? String { sessions.removeValue(forKey: uid)?.disconnect() }
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: lifecycle
  private func start(uid: String, name: String) {
    stop()
    let me = MCPeerID(displayName: uid)   // user_id only: no device name / no PII leaks
    myPeer = me
    let info = ["uid": uid, "name": String(name.prefix(40))]
    advertiser = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: info, serviceType: Self.serviceType)
    advertiser?.delegate = self
    advertiser?.startAdvertisingPeer()
    browser = MCNearbyServiceBrowser(peer: me, serviceType: Self.serviceType)
    browser?.delegate = self
    browser?.startBrowsingForPeers()
  }

  private func stop() {
    advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
    sessions.values.forEach { $0.disconnect() }
    sessions.removeAll(); peersById.removeAll()
    advertiser = nil; browser = nil
  }

  private func session(for uid: String, peer: MCPeerID) -> MCSession {
    if let s = sessions[uid] { return s }
    let s = MCSession(peer: myPeer!, securityIdentity: nil, encryptionPreference: .required)
    s.delegate = self
    sessions[uid] = s
    peersById[uid] = peer
    return s
  }

  private func uid(of peer: MCPeerID) -> String { peer.displayName }
}

// MARK: - Advertiser
extension MultipeerPlugin: MCNearbyServiceAdvertiserDelegate {
  func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                  withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
    DispatchQueue.main.async {
      let id = self.uid(of: peerID)
      invitationHandler(true, self.session(for: id, peer: peerID))
    }
  }
  func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
    emit(["type": "error", "message": error.localizedDescription])
  }
}

// MARK: - Browser
extension MultipeerPlugin: MCNearbyServiceBrowserDelegate {
  func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
    DispatchQueue.main.async {
      let id = info?["uid"] ?? self.uid(of: peerID)
      self.peersById[id] = peerID
      self.names[id] = info?["name"] ?? "iPhone"
      self.emit(["type": "found", "userId": id, "name": self.names[id]!])
    }
  }
  func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    emit(["type": "lost", "userId": uid(of: peerID)])
  }
  func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
    emit(["type": "error", "message": error.localizedDescription])
  }
}

// MARK: - Session
extension MultipeerPlugin: MCSessionDelegate {
  func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
    let id = uid(of: peerID)
    switch state {
    case .connected: emit(["type": "connected", "userId": id, "name": names[id] ?? ""])
    case .notConnected:
      DispatchQueue.main.async { if self.sessions[id] === session { self.sessions.removeValue(forKey: id) } }
      emit(["type": "disconnected", "userId": id])
    default: break
    }
  }
  func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
    emit(["type": "data", "userId": uid(of: peerID), "data": FlutterStandardTypedData(bytes: data)])
  }
  func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
  func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
  func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
