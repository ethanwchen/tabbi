//! The one error shape every service command returns, so the UI can branch on
//! a stable `code` and show its own designed message instead of a raw dump.

use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct HostError {
    /// Stable and camelCase, mirrored by `HostErrorCode` in `src/host/host.ts`.
    pub code: &'static str,
    /// For logs and developers; never holds a secret, a token or typed text.
    pub message: String,
}

impl HostError {
    pub fn new(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }
}

pub type HostResult<T> = Result<T, HostError>;
