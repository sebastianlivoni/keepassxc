//
//  CredentialProviderViewController.h
//  CredentialProviderViewController
//
//  Created by Sebastian Livoni on 27/01/2025.
//

import AuthenticationServices

class CredentialProviderViewController: ASCredentialProviderViewController {

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    }

    override func provideCredentialWithoutUserInteraction(
        for credentialRequest: any ASCredentialRequest
    ) {
        let passwordCredential = ASPasswordCredential(user: "username", password: "password")

        extensionContext.completeRequest(
            withSelectedCredential: passwordCredential, completionHandler: nil)
    }
}
