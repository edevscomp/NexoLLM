//! Windows DPAPI (`CryptProtectData` / `CryptUnprotectData`) per-user wrapping for the
//! 256-bit AES-GCM store key (`history.bin` and `memory.bin`).

use thiserror::Error;

#[derive(Debug, Error)]
pub enum DpapiError {
    #[error("DPAPI key protection failed")]
    ProtectionFailed,
    #[error("unsupported platform")]
    Unsupported,
}

pub fn protect_user_secret(secret: &[u8]) -> Result<Vec<u8>, DpapiError> {
    #[cfg(target_os = "windows")]
    {
        use windows::Win32::Foundation::LocalFree;
        use windows::Win32::Security::Cryptography::{
            CryptProtectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
        };
        unsafe {
            let in_blob = CRYPT_INTEGER_BLOB {
                cbData: secret.len() as u32,
                pbData: secret.as_ptr() as *mut u8,
            };
            let mut out_blob = CRYPT_INTEGER_BLOB::default();
            CryptProtectData(&in_blob, None, None, None, None, CRYPTPROTECT_UI_FORBIDDEN, &mut out_blob)
                .map_err(|_| DpapiError::ProtectionFailed)?;
            let slice = std::slice::from_raw_parts(out_blob.pbData, out_blob.cbData as usize).to_vec();
            let _ = LocalFree(windows::Win32::Foundation::HLOCAL(out_blob.pbData as *mut _));
            return Ok(slice);
        }
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = secret;
        Err(DpapiError::Unsupported)
    }
}

pub fn unprotect_user_secret(blob: &[u8]) -> Result<Vec<u8>, DpapiError> {
    #[cfg(target_os = "windows")]
    {
        use windows::Win32::Foundation::LocalFree;
        use windows::Win32::Security::Cryptography::{
            CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
        };
        unsafe {
            let in_blob = CRYPT_INTEGER_BLOB {
                cbData: blob.len() as u32,
                pbData: blob.as_ptr() as *mut u8,
            };
            let mut out_blob = CRYPT_INTEGER_BLOB::default();
            CryptUnprotectData(&in_blob, None, None, None, None, CRYPTPROTECT_UI_FORBIDDEN, &mut out_blob)
                .map_err(|_| DpapiError::ProtectionFailed)?;
            let slice = std::slice::from_raw_parts(out_blob.pbData, out_blob.cbData as usize).to_vec();
            let _ = LocalFree(windows::Win32::Foundation::HLOCAL(out_blob.pbData as *mut _));
            return Ok(slice);
        }
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = blob;
        Err(DpapiError::Unsupported)
    }
}
