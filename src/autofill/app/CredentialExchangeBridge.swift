import AppKit
import AuthenticationServices
import Foundation

// Credential Exchange is Swift only; CredentialExchange.mm declares this class by hand
@available(macOS 26.0, *)
@objc(KPXCCredentialExchangeBridge)
public final class CredentialExchangeBridge: NSObject {
  @objc(isCredentialExchangeActivity:)
  public static func isCredentialExchangeActivity(_ activity: NSUserActivity) -> Bool {
    return activity.activityType == ASCredentialExchangeActivity
  }

  // Replies with the exported credentials as Credential Exchange Format JSON
  @objc(importCredentialsFromActivity:completion:)
  public static func importCredentials(
    from activity: NSUserActivity,
    completion: @escaping @Sendable (Data?, Error?) -> Void
  ) {
    guard let token = activity.userInfo?[ASCredentialImportToken] as? UUID else {
      completion(nil, CocoaError(.coderValueNotFound))
      return
    }

    Task { @MainActor in
      do {
        let credentialData = try await ASCredentialImportManager().importCredentials(token: token)
        let encoder = JSONEncoder()
        // CXF timestamps are seconds since the Unix epoch
        encoder.dateEncodingStrategy = .secondsSince1970
        completion(try encoder.encode(credentialData), nil)
      } catch {
        completion(nil, error)
      }
    }
  }

  // Shows the system export UI and hands the CXF JSON to the app the user picks
  @MainActor
  @objc(exportCredentials:extensionBundleIdentifier:window:completion:)
  public static func exportCredentials(
    _ json: Data,
    extensionBundleIdentifier: String,
    window: NSWindow,
    completion: @escaping @Sendable (Error?) -> Void
  ) {
    Task { @MainActor in
      do {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let credentialData = try decoder.decode(ASExportedCredentialData.self, from: json)

        let manager = ASCredentialExportManager(presentationAnchor: window)
        let options = try await manager.requestExport(for: extensionBundleIdentifier)
        // Written in the format version the chosen importer asked for
        try await manager.exportCredentials(
          ASExportedCredentialData(
            accounts: credentialData.accounts,
            formatVersion: options.formatVersion,
            exporterRelyingPartyIdentifier: credentialData.exporterRelyingPartyIdentifier,
            exporterDisplayName: credentialData.exporterDisplayName,
            timestamp: credentialData.timestamp))
        completion(nil)
      } catch let error as DecodingError {
        completion(describe(error))
      } catch {
        completion(error)
      }
    }
  }

  // The localized decoding error doesn't say which field is wrong
  private static func describe(_ error: DecodingError) -> Error {
    let context: DecodingError.Context
    switch error {
    case .typeMismatch(_, let c), .valueNotFound(_, let c), .keyNotFound(_, let c), .dataCorrupted(let c):
      context = c
    @unknown default:
      return error
    }
    var path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
    if case .keyNotFound(let key, _) = error {
      path += ".\(key.stringValue)"
    }
    return NSError(
      domain: "KeePassXC.CredentialExchange", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "\(path.isEmpty ? "<root>" : path): \(context.debugDescription)"])
  }
}
