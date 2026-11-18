//
// This source file is part of the One Sec Stanford Study open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
import Foundation
import GroveFHIRContract
import GroveHealthKitFHIR
import GroveKeychainStorage


/// The secret that keys every identifier in the exported records.
///
/// It lives in the synchronizable keychain, so it survives a reinstall and, where iCloud Keychain is enabled,
/// reaches the participant's other devices. A sample then gets the same source-record identifier on each of them.
/// Two devices that each created an identity before synchronizing keep one of the two; records exported under
/// the other keep their identifiers, and the backend matches them by participant and HealthKit UUID.
@available(iOS 18, *)
struct HealthExportIdentity: Codable, Sendable, Equatable {
    enum LoadingError: Error {
        /// The keychain entry exists but does not decode.
        case corruptKeychainEntry
    }

    private static let deploymentRoot = "https://schmiedmayerlab.stanford.edu/fhir/onesec"
    private static let keychainTag = CredentialsTag.genericPassword(
        forService: "edu.stanford.OneSecStanfordStudy.healthExportIdentity",
        storage: .keychainSynchronizable
    )
    private static let keychainUsername = "identity"

    let key: Data
    let storeID: UUID
    let epoch: UInt64

    init() {
        self.key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        self.storeID = UUID()
        self.epoch = 1
    }

    /// Loads the identity from the keychain, creating and storing it on first use.
    static func load(from keychain: KeychainStorage = KeychainStorage()) throws -> Self {
        if let stored = try stored(in: keychain) {
            return stored
        }
        let identity = Self()
        do {
            try keychain.store(
                Credentials(username: keychainUsername, password: try JSONEncoder().encode(identity).base64EncodedString()),
                for: keychainTag,
                replaceDuplicates: false
            )
            return identity
        } catch {
            // A concurrent first use stored its identity first. Replacing it would orphan every identifier
            // it already produced, so adopt it instead.
            guard let winner = try? stored(in: keychain) else {
                throw error
            }
            return winner
        }
    }

    private static func stored(in keychain: KeychainStorage) throws -> Self? {
        guard let credentials = try keychain.retrieveCredentials(withUsername: keychainUsername, for: keychainTag) else {
            return nil
        }
        guard let data = Data(base64Encoded: credentials.password),
              let identity = try? JSONDecoder().decode(Self.self, from: data) else {
            throw LoadingError.corruptKeychainEntry
        }
        return identity
    }

    /// The exporter that states `participantID` as the subject of every record.
    ///
    /// The repository scope combines the synchronized store with the participant, so two participants
    /// who share an Apple Account get different identifiers for the same sample.
    func exporter(participantID: String, application: ApplicationDevice) throws -> HealthKitFHIRExporter {
        let root = Self.deploymentRoot
        let participant = try BusinessIdentifier(
            system: IdentifierSystem("\(root)/identifiers/participant"),
            value: participantID
        )
        let key = SymmetricKey(data: key)
        let identityScope = try OpaqueIdentityScope(
            root: IdentifierSystem(root),
            keyID: OpaqueIdentityScope.recommendedKeyID(prefix: "s", key: key, subject: participant),
            epoch: KeyEpoch(epoch),
            key: key
        )
        // Names a person gave a device, serial numbers and device identifiers stay on the phone.
        var options = HealthKitFHIRExporter.Options.nonIdentifying
        // `HKDevice.localIdentifier` is not verified to name one physical unit for the study's sources.
        options.unitToken = .none
        // The backend deduplicates repeated batches by participant and HealthKit UUID.
        options.nativeIdentifier = .authorized
        return try HealthKitFHIRExporter(
            producer: ExchangeProducer(identityScope: identityScope, subject: .logical(participant), application: application),
            repositoryScope: BusinessIdentifier(
                system: IdentifierSystem("\(root)/identifiers/repository"),
                value: "healthkit:\(storeID.uuidString.lowercased()):\(participantID)"
            ),
            options: options
        )
    }
}
