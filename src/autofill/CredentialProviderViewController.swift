import AuthenticationServices
import SwiftUI
import os

class CredentialProviderViewController: ASCredentialProviderViewController {
    private var logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CredentialProviderViewController.self)
    )

    override func provideCredentialWithoutUserInteraction(
        for credentialRequest: any ASCredentialRequest
    ) {
        switch credentialRequest.type {
        case .password:
            if let passwordCredentialIdentity = credentialRequest.credentialIdentity
                as? ASPasswordCredentialIdentity
            {
                handlePasswordCredentialRequest(passwordCredentialIdentity)
            } else {
                logger.error("Request was of type password but invalid credential identity type")
            }
        case .oneTimeCode:
            if let oneTimeCodeCredentialIdentity = credentialRequest.credentialIdentity
                as? ASOneTimeCodeCredentialIdentity
            {
                handleOneTimeCodeCredentialRequest(oneTimeCodeCredentialIdentity)
            } else {
                logger.error("Request was of type oneTimeCode but invalid credential identity type")
            }
        case .passkeyAssertion:
            logger.info("Passkey assertion is not implemented")
        default:
            logger.info(
                "Not able to handle credential request of type \(credentialRequest.type.rawValue)")
        }
    }

    func handlePasswordCredentialRequest(_ credentialIdentity: ASPasswordCredentialIdentity) {
        let passwordCredential = ASPasswordCredential(user: "halli", password: "hallo")
        self.extensionContext.completeRequest(withSelectedCredential: passwordCredential)

        logger.info("Handling password credential request")
    }

    func handleOneTimeCodeCredentialRequest(_ credentialIdentity: ASOneTimeCodeCredentialIdentity) {
        logger.info("Handling oneTimeCode credential request")
    }

    override func prepareInterfaceForExtensionConfiguration() {
        let configurationView = ConfigurationView()

        setupHostingView(rootView: configurationView)
    }

    private func setupHostingView<Content: View>(rootView: Content) {
        let contentView = NSHostingController(rootView: rootView)

        self.addChild(contentView)
        self.view.addSubview(contentView.view)

        contentView.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        contentView.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        contentView.view.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
        contentView.view.rightAnchor.constraint(equalTo: self.view.rightAnchor).isActive = true
    }
}

struct ConfigurationView: View {
    var body: some View {
        Button("Setup", action: setup)
    }

    func setup() {
        let identifier = ASCredentialServiceIdentifier(identifier: "fill.dev", type: .domain)
        let identity = ASPasswordCredentialIdentity(
            serviceIdentifier: identifier, user: "Test Autofill",
            recordIdentifier: "7d9f8ed66bf140be8cbf2e4c48fcf0c0")

        let identifier2 = ASCredentialServiceIdentifier(
            identifier: "authenticationtest.com", type: .domain)
        let identity2 = ASPasswordCredentialIdentity(
            serviceIdentifier: identifier2, user: "Authentication Challenge",
            recordIdentifier: "6406275ba956425384d14088c989db9c")

        let otp = ASOneTimeCodeCredentialIdentity(
            serviceIdentifier: identifier2, label: "Authentication Challenge",
            recordIdentifier: "6406275ba956425384d14088c989db9c")

        ASCredentialIdentityStore.shared.replaceCredentialIdentities([identity, identity2, otp])
    }
}
