import SwiftUI
import UIKit

/// Entry point Kodi loads at run time (TVOSAppleMode.mm):
///   rpc     runs one JSON-RPC request inside Kodi and calls back with the reply
///   command asks the host for something only it can do ("kodi": Kodi mode)
@objc(DexAppleUI)
public final class DexAppleUI: NSObject {
    @MainActor private static var kodi: Kodi?

    @objc(makeRootWithRPC:command:)
    @MainActor
    public static func makeRoot(rpc: @escaping (String, @escaping (String) -> Void) -> Void,
                                command: @escaping (String) -> Void) -> UIViewController {
        let kodi = Kodi(rpc: rpc, command: command)
        self.kodi = kodi
        let controller = UIHostingController(rootView: RootView(kodi: kodi))
        controller.view.backgroundColor = UIColor(Theme.ground)
        return controller
    }

    /// API revision the host checks before loading this module.
    @objc public static let apiVersion = 1
}
