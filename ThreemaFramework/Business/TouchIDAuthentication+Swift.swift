extension TouchIDAuthentication {
    public enum BiometricAuthenticationError: Error {
        /// Biometrics may have changed since the last successful authentication.
        /// `newPolicyDomainState` is the current `LAContext.evaluatedPolicyDomainState`
        /// that the caller should persist after the user re-authenticates with passcode.
        case biometricsChanged(newPolicyDomainState: Data)
        case underlying(Error)
    }

    public static func tryBiometricAuthentication() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            TouchIDAuthentication.tryTouchIDAuthentication { success, error, data in
                if let data {
                    continuation.resume(throwing: BiometricAuthenticationError.biometricsChanged(
                        newPolicyDomainState: data
                    ))
                }
                else if let error {
                    continuation.resume(throwing: BiometricAuthenticationError.underlying(error))
                }
                else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
