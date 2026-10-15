//! Secrets in Windows Credential Manager, as generic credentials under a
//! `Tabbi/` target prefix: `Tabbi/party` holds the Party token and
//! `Tabbi/ai/<provider>` an AI provider's API key. They never go in a file or
//! in settings, and no value is ever logged or put in an error message.
//!
//! Credentials persist per user on this PC (`CRED_PERSIST_LOCAL_MACHINE`), so
//! a key does not roam to other machines with the profile. The secret is
//! stored as its UTF-8 bytes.

use crate::error::{HostError, HostResult};
use windows::Win32::Foundation::ERROR_NOT_FOUND;
use windows::Win32::Security::Credentials::{
    CRED_MAX_CREDENTIAL_BLOB_SIZE, CRED_PERSIST_LOCAL_MACHINE, CRED_TYPE_GENERIC, CREDENTIALW,
    CredDeleteW, CredFree, CredReadW, CredWriteW,
};
use windows::core::{PCWSTR, PWSTR};

pub const PREFIX: &str = "Tabbi/";
const MAX_PROVIDER: usize = 32;

/// The Credential Manager target for a name the UI uses: `party`, or
/// `ai/<provider>` with a provider id of 1 to 32 of `a-z 0-9 -` (the Mac's
/// `AIProviderID` raw values, such as `anthropic`, `openai` and `gemini`).
pub fn target(name: &str) -> HostResult<String> {
    let valid = match name.strip_prefix("ai/") {
        Some(provider) => {
            !provider.is_empty()
                && provider.len() <= MAX_PROVIDER
                && provider.starts_with(|c: char| c.is_ascii_lowercase() || c.is_ascii_digit())
                && provider
                    .bytes()
                    .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
        }
        None => name == "party",
    };
    if valid {
        Ok(format!("{PREFIX}{name}"))
    } else {
        Err(HostError::new(
            "invalidName",
            format!("\"{name}\" is not a credential name (party or ai/<provider>)"),
        ))
    }
}

/// A secret Credential Manager can hold: not empty, at most 2560 bytes.
pub fn check_secret(secret: &str) -> HostResult<()> {
    if secret.is_empty() {
        return Err(HostError::new("invalid", "the secret is empty"));
    }
    if secret.len() > CRED_MAX_CREDENTIAL_BLOB_SIZE as usize {
        return Err(HostError::new(
            "tooLarge",
            format!("the secret is longer than {CRED_MAX_CREDENTIAL_BLOB_SIZE} bytes"),
        ));
    }
    Ok(())
}

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

fn failure(action: &str, error: &windows::core::Error) -> HostError {
    /* The Win32 error alone, never the target's value. */
    HostError::new(
        "credential",
        format!("could not {action} the credential: {}", error.code()),
    )
}

fn is_not_found(error: &windows::core::Error) -> bool {
    error.code() == ERROR_NOT_FOUND.to_hresult()
}

pub fn read(name: &str) -> HostResult<Option<String>> {
    let target = wide(&target(name)?);
    let mut credential: *mut CREDENTIALW = std::ptr::null_mut();
    match unsafe {
        CredReadW(
            PCWSTR(target.as_ptr()),
            CRED_TYPE_GENERIC,
            None,
            &mut credential,
        )
    } {
        Ok(()) => {
            let secret = unsafe {
                let c = &*credential;
                let bytes = if c.CredentialBlob.is_null() {
                    &[][..]
                } else {
                    std::slice::from_raw_parts(c.CredentialBlob, c.CredentialBlobSize as usize)
                };
                let secret = String::from_utf8(bytes.to_vec());
                CredFree(credential as *const core::ffi::c_void);
                secret
            };
            secret
                .map(Some)
                .map_err(|_| HostError::new("corrupt", "the stored credential is not UTF-8 text"))
        }
        Err(error) if is_not_found(&error) => Ok(None),
        Err(error) => Err(failure("read", &error)),
    }
}

pub fn write(name: &str, secret: &str) -> HostResult<()> {
    check_secret(secret)?;
    let mut target = wide(&target(name)?);
    let mut user = wide("Tabbi");
    let mut blob = secret.as_bytes().to_vec();
    let credential = CREDENTIALW {
        Type: CRED_TYPE_GENERIC,
        TargetName: PWSTR(target.as_mut_ptr()),
        CredentialBlobSize: blob.len() as u32,
        CredentialBlob: blob.as_mut_ptr(),
        Persist: CRED_PERSIST_LOCAL_MACHINE,
        UserName: PWSTR(user.as_mut_ptr()),
        ..Default::default()
    };
    let result = unsafe { CredWriteW(&credential, 0) };
    /* Clear the copy of the secret before the buffer is freed. */
    blob.iter_mut().for_each(|b| *b = 0);
    result.map_err(|error| failure("save", &error))
}

/// Removes a credential; false when there was none.
pub fn delete(name: &str) -> HostResult<bool> {
    let target = wide(&target(name)?);
    match unsafe { CredDeleteW(PCWSTR(target.as_ptr()), CRED_TYPE_GENERIC, None) } {
        Ok(()) => Ok(true),
        Err(error) if is_not_found(&error) => Ok(false),
        Err(error) => Err(failure("delete", &error)),
    }
}

#[tauri::command(async)]
pub fn credential_get(name: String) -> HostResult<Option<String>> {
    read(&name)
}

#[tauri::command(async)]
pub fn credential_set(name: String, secret: String) -> HostResult<()> {
    write(&name, &secret)
}

#[tauri::command(async)]
pub fn credential_delete(name: String) -> HostResult<bool> {
    delete(&name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_map_to_targets_under_the_tabbi_prefix() {
        assert_eq!(target("party").unwrap(), "Tabbi/party");
        assert_eq!(target("ai/anthropic").unwrap(), "Tabbi/ai/anthropic");
        assert_eq!(target("ai/openai").unwrap(), "Tabbi/ai/openai");
        assert_eq!(target("ai/claude-cli").unwrap(), "Tabbi/ai/claude-cli");
        assert_eq!(target(&format!("ai/{}", "a".repeat(32))).unwrap().len(), 41);
    }

    #[test]
    fn anything_else_is_rejected() {
        for bad in [
            "",
            "Party",
            "party/x",
            "ai",
            "ai/",
            "ai/OpenAI",
            "ai/-x",
            "ai/a/b",
            "ai/a b",
            "ai/../party",
            "ai/key\0",
            "Tabbi/party",
            "/party",
            &format!("ai/{}", "a".repeat(33)),
        ] {
            let error = target(bad).unwrap_err();
            assert_eq!(error.code, "invalidName", "{bad:?}");
        }
    }

    #[test]
    fn secrets_must_fit_a_generic_credential_and_errors_never_echo_them() {
        assert!(check_secret("sk-ant-123").is_ok());
        assert!(check_secret(&"x".repeat(2560)).is_ok());
        let long = "y".repeat(2561);
        let error = check_secret(&long).unwrap_err();
        assert_eq!(error.code, "tooLarge");
        assert!(!error.message.contains("yyyy"));
        assert_eq!(check_secret("").unwrap_err().code, "invalid");
    }

    /// Writes, reads and deletes a real credential. Run on a Windows desktop
    /// with `cargo test -- --ignored`.
    #[test]
    #[ignore = "touches the real Credential Manager"]
    fn live_round_trip() {
        let name = "ai/tabbi-test";
        let _ = delete(name);
        assert_eq!(read(name).unwrap(), None);
        write(name, "first").unwrap();
        write(name, "second \u{e9}").unwrap();
        assert_eq!(read(name).unwrap().as_deref(), Some("second \u{e9}"));
        assert!(delete(name).unwrap());
        assert!(!delete(name).unwrap());
        assert_eq!(read(name).unwrap(), None);
    }
}
