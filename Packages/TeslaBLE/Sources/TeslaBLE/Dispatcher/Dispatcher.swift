import CryptoKit
import Foundation
import Security

/// Actor that owns per-domain `VehicleSession` state on top of a `MessageTransport`,
/// serializing in-flight requests through `RequestTable` for sign/verify + timeout.
/// Framing and BLE connection lifecycle are the transport's concern, not ours.
///
/// ## Routing model (per-domain)
///
/// Mirrors `internal/dispatcher/dispatcher.go` in the Go reference. Outbound
/// requests and inbound response matching both branch on domain:
///
/// - **VCSEC:** every outbound message uses a fresh random 16-byte
///   `fromDestination.routingAddress`, and the request continuation is
///   registered under THAT address. Inbound VCSEC responses are matched
///   back by `toDestination.routingAddress` — VCSEC responses do not
///   reliably echo `request_uuid`, so Go ignores the UUID for this domain
///   (see `dispatcher.go:259`).
///
/// - **Infotainment / other:** every outbound message uses a stable,
///   per-Dispatcher random `fromDestination.routingAddress` (chosen once
///   at construction), and the continuation is registered under the
///   message `uuid`. Inbound responses are matched back by `requestUuid`.
///
/// This asymmetry is what the protocol actually needs — single-flight
/// per VCSEC domain, multi-flight per Infotainment with uuid disambiguation.
actor Dispatcher {
    enum Error: Swift.Error, Equatable {
        case notStarted
        case alreadyStarted
        case notConnected
        case noSessionForDomain(UniversalMessage_Domain)
        case timeout
        case shutdown
        case encodingFailed(String)
        case decodingFailed(String)
        case unexpectedResponse(String)
    }

    private let transport: MessageTransport
    private let log: Log

    /// Stable 16-byte routing address used by every Infotainment outbound
    /// message. Chosen once at construction. Mirrors `d.address` in Go.
    private let infotainmentAddress: Data

    private var vcsecSession: VehicleSession?
    private var infotainmentSession: VehicleSession?
    private var requestTable = RequestTable()
    private var inboundTask: Task<Void, Never>?
    private var started = false
    /// Set once the inbound loop dies while running. Every later request
    /// fails as a consequence, so those failures are traced at debug instead
    /// of repeating the already-logged root cause at poll rate.
    private var inboundTerminated = false

    init(transport: MessageTransport, logger: (any TeslaBLELogger)? = nil) {
        self.transport = transport
        log = Log(logger, category: .dispatcher)
        infotainmentAddress = Self.newRoutingAddress()
    }

    // MARK: - Lifecycle

    func start() throws {
        guard !started else { throw Error.alreadyStarted }
        started = true
        inboundTask = Task { [weak self] in
            await self?.inboundLoop()
        }
    }

    func stop() async {
        log.info("stopped: pending=\(requestTable.count)")
        started = false
        inboundTask?.cancel()
        inboundTask = nil
        requestTable.cancelAll(error: Error.shutdown)
    }

    /// Installs or replaces a `VehicleSession` for the given domain. Typically
    /// called after a successful `negotiate(domain:...)`.
    func installSession(_ session: VehicleSession, forDomain domain: UniversalMessage_Domain) {
        switch domain {
        case .vehicleSecurity: vcsecSession = session
        case .infotainment: infotainmentSession = session
        default: return
        }
        log.info("session installed: domain=\(domain)")
    }

    // MARK: - Outbound

    /// Signed send: wraps `plaintext` in the domain's `VehicleSession` envelope,
    /// awaits the matching response, and returns the verified response plaintext.
    /// Requires an installed session; throws `.noSessionForDomain` otherwise.
    /// For the unsigned bootstrap path used by `addKey`, see `sendUnsigned(_:domain:)`.
    func send(
        _ plaintext: Data,
        domain: UniversalMessage_Domain,
        timeout: Duration = .seconds(10),
    ) async throws -> Data {
        guard started else { throw Error.notStarted }
        let session = try requireSession(for: domain)

        // Pick routing address per domain: VCSEC uses a fresh random addr;
        // Infotainment reuses the stable per-dispatcher address.
        let fromAddress = routingAddress(forDomain: domain)

        var request = UniversalMessage_RoutableMessage()
        var dst = UniversalMessage_Destination()
        dst.domain = domain
        request.toDestination = dst
        var fromDst = UniversalMessage_Destination()
        fromDst.routingAddress = fromAddress
        request.fromDestination = fromDst
        let requestUUID = Self.newUUIDBytes()
        request.uuid = requestUUID
        // Match Go's DefaultFlags (vehicle.go:22). 2024.38+ firmware
        // rejects getVehicleData with MESSAGEFAULT_ERROR_REQUIRES_RESPONSE_ENCRYPTION
        // unless FLAG_ENCRYPT_RESPONSE is set.
        request.flags = Self.defaultOutboundFlags

        // Sign (actor hop into VehicleSession).
        try await session.sign(plaintext: plaintext, into: &request, expiresIn: Self.defaultExpiresIn)

        // Compute requestID for response matching.
        guard let responseMatchID = InboundVerifier.requestID(forSignedRequest: request) else {
            throw Error.encodingFailed("failed to compute requestID from signed message")
        }

        let token = routeToken(forDomain: domain, uuid: requestUUID, routingAddress: fromAddress)

        // Freeze the request before capturing in the Sendable closure.
        let frozenRequest = request

        // Register and transmit.
        let response = try await withRegisteredRequest(token: token, domain: domain, timeout: timeout) { [self] in
            try await transmit(message: frozenRequest)
        }

        // Protocol-layer fault check. Vehicles return errors as a bare
        // `signedMessageStatus` with no `signatureData`, so we must surface
        // the fault here — otherwise the verifier below throws the opaque
        // `missingSignatureData`. Mirrors `protocol.GetError` in Go.
        if response.hasSignedMessageStatus {
            let status = response.signedMessageStatus
            if status.signedMessageFault != .rrorNone {
                log.warning("protocol fault: domain=\(domain) fault=\(status.signedMessageFault)")
                let name = String(describing: status.signedMessageFault)
                throw Error.decodingFailed("protocol fault on domain \(domain): \(name)")
            }
            if status.operationStatus == .rror {
                log.warning("operation error: domain=\(domain)")
                throw Error.decodingFailed("operation error on domain \(domain)")
            }
        }

        // Verify response.
        do {
            return try await session.verify(response: response, requestID: responseMatchID)
        } catch {
            log.warning("response verify failed: domain=\(domain) error=\(error)")
            throw Error.decodingFailed(String(describing: error))
        }
    }

    /// Unsigned send: used ONLY for the `addKey` pairing bootstrap, where the
    /// vehicle accepts a plaintext request without an established session.
    /// Returns the raw `protobufMessageAsBytes` payload from the response
    /// (typically a `VCSEC_FromVCSECMessage`); no session verify is performed.
    func sendUnsigned(
        _ plaintext: Data,
        domain: UniversalMessage_Domain,
        timeout: Duration = .seconds(60),
    ) async throws -> Data {
        guard started else { throw Error.notStarted }

        let fromAddress = routingAddress(forDomain: domain)

        var request = UniversalMessage_RoutableMessage()
        var dst = UniversalMessage_Destination()
        dst.domain = domain
        request.toDestination = dst
        var fromDst = UniversalMessage_Destination()
        fromDst.routingAddress = fromAddress
        request.fromDestination = fromDst
        let requestUUID = Self.newUUIDBytes()
        request.uuid = requestUUID
        request.payload = .protobufMessageAsBytes(plaintext)
        // No subSigData — unsigned.

        let token = routeToken(forDomain: domain, uuid: requestUUID, routingAddress: fromAddress)
        let frozenRequest = request

        let response = try await withRegisteredRequest(token: token, domain: domain, timeout: timeout) { [self] in
            try await transmit(message: frozenRequest)
        }

        // Return the raw response payload bytes. No session verify since
        // the request wasn't signed.
        guard case let .protobufMessageAsBytes(payload)? = response.payload else {
            throw Error.decodingFailed("unsigned response missing protobufMessageAsBytes payload")
        }
        return payload
    }

    /// One-way unsigned send used by the BLE pairing bootstrap.
    ///
    /// Unlike `sendUnsigned(_:domain:timeout:)`, this method only guarantees
    /// that the request was serialized and handed to the transport. It does
    /// not wait for a terminal VCSEC response because real vehicles may keep
    /// the whitelist operation pending until the user authorizes on the center
    /// console and may never emit a matching response for the original uuid.
    func sendUnsignedNoReply(
        _ plaintext: Data,
        domain: UniversalMessage_Domain,
    ) async throws {
        guard started else { throw Error.notStarted }

        var request = UniversalMessage_RoutableMessage()
        var dst = UniversalMessage_Destination()
        dst.domain = domain
        request.toDestination = dst
        var fromDst = UniversalMessage_Destination()
        fromDst.routingAddress = routingAddress(forDomain: domain)
        request.fromDestination = fromDst
        request.uuid = Self.newUUIDBytes()
        request.payload = .protobufMessageAsBytes(plaintext)

        try await transmit(message: request)
    }

    // MARK: - Handshake

    /// Runs a SessionInfoRequest/SessionInfo handshake and returns the decoded
    /// `SessionInfo` together with the derived `SessionKey`.
    ///
    /// ECDH is performed inline here — not by the caller — because the response's
    /// HMAC tag is keyed by the session key, which in turn is derived from the
    /// vehicle public key embedded inside that same response. That circular
    /// dependency can only be resolved by decoding the response, doing ECDH
    /// against `info.publicKey` on the spot, and then verifying the HMAC with
    /// the freshly-derived key.
    func negotiate(
        domain: UniversalMessage_Domain,
        localPrivateKey: P256.KeyAgreement.PrivateKey,
        verifierName: Data,
        timeout: Duration = .seconds(10),
    ) async throws -> (sessionInfo: Signatures_SessionInfo, sessionKey: SessionKey) {
        guard started else { throw Error.notStarted }
        return try await negotiateOnce(
            domain: domain,
            localPrivateKey: localPrivateKey,
            verifierName: verifierName,
            timeout: timeout,
        )
    }

    private func negotiateOnce(
        domain: UniversalMessage_Domain,
        localPrivateKey: P256.KeyAgreement.PrivateKey,
        verifierName: Data,
        timeout: Duration,
    ) async throws -> (sessionInfo: Signatures_SessionInfo, sessionKey: SessionKey) {
        // Local public key in uncompressed SEC1 form (0x04 || X || Y, 65 bytes).
        let localPublicKey = localPrivateKey.publicKey.x963Representation

        // The vehicle keys the SessionInfo HMAC on the RoutableMessage.uuid of
        // the request (echoed back in the response as `request_uuid`). See
        // `internal/dispatcher/dispatcher.go:219` — `processHello` is called
        // with `message.GetRequestUuid()` as the challenge. The HMAC challenge
        // is always the uuid regardless of which token (address or uuid) is
        // used for inbound routing matching.
        let requestUUID = Self.newUUIDBytes()
        let fromAddress = routingAddress(forDomain: domain)
        let request = SessionNegotiator.buildRequest(
            domain: domain,
            publicKey: localPublicKey,
            uuid: requestUUID,
            fromRoutingAddress: fromAddress,
        )
        let challenge = requestUUID
        let token = routeToken(forDomain: domain, uuid: requestUUID, routingAddress: fromAddress)

        let response: UniversalMessage_RoutableMessage = try await withRegisteredRequest(
            token: token,
            domain: domain,
            timeout: timeout,
        ) { [self] in
            try await transmit(message: request)
        }

        // Extract encodedInfo and tag from response.
        guard case let .sessionInfo(encodedInfo)? = response.payload else {
            // A refusing vehicle answers with a bare status; its fault code
            // is the only diagnosis.
            let fault = response.signedMessageStatus.signedMessageFault
            log.warning("handshake rejected: domain=\(domain) reason=missingSessionInfo fault=\(fault)")
            throw Error.unexpectedResponse("negotiate response missing sessionInfo payload")
        }
        // Checked before any signature verification, like Go's
        // `protocol.GetError`: a vehicle that does not know the key may not
        // produce a verifiable tag, and the status is the actual diagnosis.
        // The handshake result itself is unaffected.
        if let status = try? Signatures_SessionInfo(serializedBytes: encodedInfo).status, status != .ok {
            log.warning("session status: domain=\(domain) status=\(status)")
        }
        guard case let .signatureData(sigData)? = response.subSigData else {
            log.warning("handshake rejected: domain=\(domain) reason=missingSignature")
            throw Error.unexpectedResponse("negotiate response missing signature data")
        }
        guard case let .sessionInfoTag(hmacSig)? = sigData.sigType else {
            log.warning("handshake rejected: domain=\(domain) reason=wrongSignatureType")
            throw Error.unexpectedResponse("negotiate response has wrong signature type")
        }
        let expectedTag = hmacSig.tag

        // Decode SessionInfo to get vehicle public key.
        let info: Signatures_SessionInfo
        do {
            info = try Signatures_SessionInfo(serializedBytes: encodedInfo)
        } catch {
            log.warning("handshake rejected: domain=\(domain) reason=sessionInfoDecode error=\(error)")
            throw Error.decodingFailed("SessionInfo: \(error)")
        }

        // ECDH: localPrivateKey × info.publicKey → sharedSecret → SessionKey
        let sharedSecret: Data
        do {
            sharedSecret = try P256ECDH.sharedSecret(
                localScalar: localPrivateKey.rawRepresentation,
                peerPublicUncompressed: info.publicKey,
            )
        } catch {
            log.warning("handshake rejected: domain=\(domain) reason=ecdh error=\(error)")
            throw Error.decodingFailed("ECDH: \(error)")
        }
        let sessionKey = SessionKey.derive(fromSharedSecret: sharedSecret)

        // Verify the HMAC tag using the newly-derived session key.
        let computedTag = try SessionNegotiator.computeSessionInfoTag(
            sessionKey: sessionKey,
            verifierName: verifierName,
            challenge: challenge,
            encodedInfo: encodedInfo,
        )
        guard Self.constantTimeEqual(computedTag, expectedTag) else {
            log.warning("handshake rejected: domain=\(domain) reason=hmacMismatch")
            throw Error.unexpectedResponse("SessionInfo HMAC tag mismatch")
        }

        return (info, sessionKey)
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0 ..< a.count {
            diff |= a[a.index(a.startIndex, offsetBy: i)] ^ b[b.index(b.startIndex, offsetBy: i)]
        }
        return diff == 0
    }

    // MARK: - Internals

    private func requireSession(for domain: UniversalMessage_Domain) throws -> VehicleSession {
        switch domain {
        case .vehicleSecurity:
            guard let s = vcsecSession else { throw Error.noSessionForDomain(domain) }
            return s
        case .infotainment:
            guard let s = infotainmentSession else { throw Error.noSessionForDomain(domain) }
            return s
        default:
            throw Error.noSessionForDomain(domain)
        }
    }

    private func session(forDomain domain: UniversalMessage_Domain) -> VehicleSession? {
        switch domain {
        case .vehicleSecurity: vcsecSession
        case .infotainment: infotainmentSession
        default: nil
        }
    }

    /// Pick the outbound routing address for a domain. VCSEC gets a fresh
    /// random 16-byte address per message; every other domain reuses the
    /// stable per-dispatcher `infotainmentAddress`.
    private func routingAddress(forDomain domain: UniversalMessage_Domain) -> Data {
        switch domain {
        case .vehicleSecurity: Self.newRoutingAddress()
        default: infotainmentAddress
        }
    }

    /// Pick the request-table lookup key for a domain. VCSEC is keyed by
    /// the random per-message routing address; every other domain is keyed
    /// by the message `uuid`.
    private func routeToken(
        forDomain domain: UniversalMessage_Domain,
        uuid: Data,
        routingAddress: Data,
    ) -> Data {
        switch domain {
        case .vehicleSecurity: routingAddress
        default: uuid
        }
    }

    /// Extract the request-table lookup key from an inbound message, based
    /// on its `fromDestination.domain`. Mirrors how Go's `dispatcher.go:259`
    /// decides whether to include the UUID in the lookup key.
    private func inboundToken(for message: UniversalMessage_RoutableMessage) -> Data? {
        let fromDomain = message.hasFromDestination ? message.fromDestination.domain : .broadcast
        switch fromDomain {
        case .vehicleSecurity:
            // VCSEC: match by the routing address the vehicle echoes back
            // in toDestination. No UUID check.
            guard message.hasToDestination else { return nil }
            guard case let .routingAddress(addr)? = message.toDestination.subDestination else {
                return nil
            }
            return addr.isEmpty ? nil : addr
        default:
            // Infotainment / other: match by echoed request_uuid.
            let uuid = message.requestUuid
            return uuid.isEmpty ? nil : uuid
        }
    }

    private func transmit(message: UniversalMessage_RoutableMessage) async throws {
        let bytes: Data
        do {
            bytes = try message.serializedData()
        } catch {
            throw Error.encodingFailed(String(describing: error))
        }
        try await transport.sendMessage(bytes)
    }

    /// Registers a continuation before firing `transmit` so that an early
    /// response cannot arrive at an unregistered token. Completion races
    /// the inbound loop, the timeout task, and `stop()` / `cancelAll`.
    private func withRegisteredRequest(
        token: Data,
        domain: UniversalMessage_Domain,
        timeout: Duration,
        transmit: @Sendable @escaping () async throws -> Void,
    ) async throws -> UniversalMessage_RoutableMessage {
        let start = ContinuousClock.now
        let response = try await withCheckedThrowingContinuation { (cont: RequestTable.Continuation) in
            do {
                try requestTable.register(token: token, continuation: cont)
            } catch {
                cont.resume(throwing: error)
                return
            }
            log.debug("request: domain=\(domain) token=\(token: token) timeout=\(timeout)")

            Task { [weak self] in
                // Transmit outside the register-or-throw critical section so
                // an early response finds a registered continuation.
                do {
                    try await transmit()
                } catch {
                    await self?.abortRequest(token: token, domain: domain, error: error)
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: Self.durationToNanoseconds(timeout))
                    await self?.expireRequest(token: token, domain: domain, timeout: timeout)
                } catch {
                    // Task cancelled — the continuation may already have been
                    // completed by the inbound loop; attempt to fail is a
                    // no-op if the token is already unregistered.
                    await self?.failRequest(token: token, error: CancellationError())
                }
            }
        }
        log.debug("response: domain=\(domain) token=\(token: token) latency=\(ContinuousClock.now - start)")
        return response
    }

    private func failRequest(token: Data, error: Swift.Error) {
        _ = requestTable.fail(token: token, error: error)
    }

    /// Only logs when the request was still pending; a response that won the
    /// race already unregistered the token.
    private func expireRequest(token: Data, domain: UniversalMessage_Domain, timeout: Duration) {
        guard requestTable.fail(token: token, error: Error.timeout) else { return }
        logRequestFailure("request timeout: domain=\(domain) token=\(token: token) after=\(timeout)")
    }

    private func abortRequest(token: Data, domain: UniversalMessage_Domain, error: Swift.Error) {
        guard requestTable.fail(token: token, error: error) else { return }
        logRequestFailure("transmit failed: domain=\(domain) token=\(token: token) error=\(error)")
    }

    private func logRequestFailure(_ message: @autoclosure () -> LogMessage) {
        if inboundTerminated {
            log.debug(message())
        } else {
            log.warning(message())
        }
    }

    // MARK: - Inbound loop

    private func inboundLoop() async {
        while !Task.isCancelled {
            let bytes: Data
            do {
                bytes = try await transport.receiveMessage()
            } catch {
                let pending = requestTable.count
                requestTable.cancelAll(error: Error.shutdown)
                // After stop() the loop is expected to unwind; while running,
                // losing it means no response can ever be matched again.
                if started {
                    inboundTerminated = true
                    log.error("inbound loop terminated: pending=\(pending) error=\(error)")
                } else {
                    log.debug("inbound loop stopped")
                }
                return
            }

            let message: UniversalMessage_RoutableMessage
            do {
                message = try UniversalMessage_RoutableMessage(serializedBytes: bytes)
            } catch {
                log.warning("dropping undecodable frame: bytes=\(bytes.count) error=\(error)")
                continue
            }

            // Proactive / fault-triggered session resync. Vehicles may attach
            // a fresh (HMAC-signed) SessionInfo to any response if they think
            // the session is desynced — typically alongside a MessageFault —
            // so the client can recover without a full re-handshake. See
            // `internal/dispatcher/dispatcher.go:182` `checkForSessionUpdate`.
            // We only act on this when an established session exists for the
            // inbound domain; the initial `negotiate()` path handles its own
            // HMAC verification and installs the session itself.
            await maybeResyncFromInbound(message)

            guard let token = inboundToken(for: message) else {
                log.debug("dropping unroutable message: no token")
                continue
            }
            let routed = requestTable.complete(token: token, with: message)
            if !routed {
                let fromDomain = message.hasFromDestination ? message.fromDestination.domain : .broadcast
                log.warning("dropping unmatched response: domain=\(fromDomain) token=\(token: token)")
            }
        }
    }

    /// Verify and apply a vehicle-sent session-info update attached to an
    /// inbound response. Silently returns if the message has no sessionInfo
    /// payload, no session is installed for the domain, or the HMAC does
    /// not match.
    private func maybeResyncFromInbound(_ message: UniversalMessage_RoutableMessage) async {
        guard case let .sessionInfo(encodedInfo)? = message.payload else { return }
        guard case let .signatureData(sigData)? = message.subSigData else { return }
        guard case let .sessionInfoTag(hmacSig)? = sigData.sigType else { return }

        let fromDomain = message.hasFromDestination ? message.fromDestination.domain : .broadcast
        guard let targetSession = session(forDomain: fromDomain) else { return }

        // HMAC challenge is the request uuid echoed back on the response.
        // For VCSEC responses this is the only place Swift uses the field.
        let challenge = message.requestUuid
        guard !challenge.isEmpty else {
            log.warning("session resync skipped: domain=\(fromDomain) reason=emptyRequestUuid")
            return
        }

        let info: Signatures_SessionInfo
        do {
            info = try Signatures_SessionInfo(serializedBytes: encodedInfo)
        } catch {
            log.warning("session resync skipped: domain=\(fromDomain) decode error=\(error)")
            return
        }

        let verifierName = targetSession.verifierName
        let sessionKey = targetSession.sessionKey

        let computedTag: Data
        do {
            computedTag = try SessionNegotiator.computeSessionInfoTag(
                sessionKey: sessionKey,
                verifierName: verifierName,
                challenge: challenge,
                encodedInfo: encodedInfo,
            )
        } catch {
            log.warning("session resync skipped: domain=\(fromDomain) hmac error=\(error)")
            return
        }
        guard Self.constantTimeEqual(computedTag, hmacSig.tag) else {
            log.warning("session resync rejected: domain=\(fromDomain) reason=hmacMismatch")
            return
        }

        await targetSession.resync(fromSessionInfo: info)
        log.info("session resynced: domain=\(fromDomain) counter=\(info.counter)")
    }

    // MARK: - Constants & helpers

    /// Default relative TTL for signed commands. Matches Go's
    /// `defaultExpiration = 5 * time.Second` in `internal/dispatcher/session.go`.
    /// The absolute `expiresAt` on the wire is computed by `VehicleSession`
    /// relative to `sessionStart`, not written as a raw constant here.
    private static let defaultExpiresIn: TimeInterval = 5

    /// Default flag mask applied to every signed outbound request. Mirrors
    /// `pkg/vehicle/vehicle.go DefaultFlags = 1 << FLAG_ENCRYPT_RESPONSE`.
    /// Required by 2024.38+ firmware for `getVehicleData`; older firmware
    /// ignores it.
    private static let defaultOutboundFlags: UInt32 = 1 << UInt32(UniversalMessage_Flags.flagEncryptResponse.rawValue)

    private static func newUUIDBytes() -> Data {
        var uuid = UUID().uuid
        return withUnsafeBytes(of: &uuid) { Data($0) }
    }

    /// 16-byte random "from" address. Vehicles fold
    /// `fromDestination.routingAddress` into the session-info HMAC metadata
    /// and echo it on the reply in `toDestination.routingAddress` —
    /// messages without one get answered with an unsigned SessionInfo
    /// broadcast that can never complete a handshake.
    static func newRoutingAddress() -> Data {
        var bytes = Data(count: 16)
        let count = bytes.count
        bytes.withUnsafeMutableBytes { buf in
            _ = SecRandomCopyBytes(kSecRandomDefault, count, buf.baseAddress!)
        }
        return bytes
    }

    /// Uses the `nanoseconds:` form of `Task.sleep` because `sleep(for:)`
    /// requires macOS 13+ / iOS 16+ but this package's macOS floor is 11.
    private static func durationToNanoseconds(_ duration: Duration) -> UInt64 {
        let components = duration.components
        let seconds = UInt64(max(0, components.seconds))
        // `attoseconds` range is 0..<1e18; 1 nano = 1e9 atto.
        let fractionalNanos = UInt64(max(0, components.attoseconds)) / 1_000_000_000
        return seconds * 1_000_000_000 + fractionalNanos
    }
}
