//! AES-256-GCM encrypted on-disk containers (`history.bin`, `memory.bin`) with automatic
//! RAM key zeroization on screen lock or system sleep.

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use rand::RngCore;
use std::fs;
use std::path::Path;
use thiserror::Error;
use zeroize::{Zeroize, Zeroizing};

pub const MAGIC: &[u8; 4] = b"NXML";
pub const FORMAT_VERSION: u8 = 1;

#[derive(Debug, Error)]
pub enum CryptoError {
    #[error("store key is locked in memory")]
    Locked,
    #[error("invalid encrypted store header")]
    InvalidHeader,
    #[error("authenticated decryption failed")]
    AuthenticationFailed,
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}

pub struct EncryptedStore {
    key: Option<Zeroizing<[u8; 32]>>,
}

impl EncryptedStore {
    pub fn unlocked(raw_key: [u8; 32]) -> Self {
        Self {
            key: Some(Zeroizing::new(raw_key)),
        }
    }

    pub fn generate_key() -> [u8; 32] {
        let mut k = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut k);
        k
    }

    /// Drops and zeroizes the 256-bit key in RAM when the session locks or sleeps.
    pub fn lock(&mut self) {
        if let Some(mut k) = self.key.take() {
            k.zeroize();
        }
    }

    pub fn is_locked(&self) -> bool {
        self.key.is_none()
    }

    pub fn seal(&self, plaintext: &[u8]) -> Result<Vec<u8>, CryptoError> {
        let key_bytes = self.key.as_ref().ok_or(CryptoError::Locked)?;
        let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key_bytes.as_slice()));
        let mut nonce_bytes = [0u8; 12];
        rand::thread_rng().fill_bytes(&mut nonce_bytes);
        let ciphertext = cipher
            .encrypt(Nonce::from_slice(&nonce_bytes), plaintext)
            .map_err(|_| CryptoError::AuthenticationFailed)?;

        let mut out = Vec::with_capacity(4 + 1 + 12 + ciphertext.len());
        out.extend_from_slice(MAGIC);
        out.push(FORMAT_VERSION);
        out.extend_from_slice(&nonce_bytes);
        out.extend_from_slice(&ciphertext);
        Ok(out)
    }

    pub fn open(&self, blob: &[u8]) -> Result<Vec<u8>, CryptoError> {
        if blob.len() < 4 + 1 + 12 + 16 || &blob[..4] != MAGIC || blob[4] != FORMAT_VERSION {
            return Err(CryptoError::InvalidHeader);
        }
        let key_bytes = self.key.as_ref().ok_or(CryptoError::Locked)?;
        let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key_bytes.as_slice()));
        let nonce = Nonce::from_slice(&blob[5..17]);
        cipher
            .decrypt(nonce, &blob[17..])
            .map_err(|_| CryptoError::AuthenticationFailed)
    }

    pub fn write_encrypted(&self, path: &Path, plaintext: &[u8]) -> Result<(), CryptoError> {
        let sealed = self.seal(plaintext)?;
        fs::write(path, sealed)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o600));
        }
        Ok(())
    }

    pub fn read_encrypted(&self, path: &Path) -> Result<Vec<u8>, CryptoError> {
        let data = fs::read(path)?;
        self.open(&data)
    }
}
