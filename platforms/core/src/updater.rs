//! Offline Ed25519 asymmetric update verification (`NexoLLM-release-v1:<version>:<sha256>`),
//! semantic anti-downgrade check, and HTTPS host allowlists (TLS 1.3, zero cookies, no `offlineMode`).

use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use sha2::{Digest, Sha256};
use std::fs::File;
use std::io::Read;
use std::path::Path;

/// Embedded Ed25519 release public key shared across macOS, Windows and Linux builds.
pub const PUBLIC_KEY_BASE64: &str = "AUq3fVygMR4hxBPj8avt5+pd3BYGUCdFQVA4QhTfBIo=";

pub const GITHUB_ALLOWED_HOSTS: &[&str] = &[
    "api.github.com",
    "github.com",
    "objects.githubusercontent.com",
    "release-assets.githubusercontent.com",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VerifyVerdict {
    Valid,
    BadSignature,
    NotNewer,
    Malformed,
}

pub fn signed_message(version: &str, sha256_hex: &str) -> Vec<u8> {
    format!("NexoLLM-release-v1:{version}:{}", sha256_hex.to_ascii_lowercase()).into_bytes()
}

pub fn sha256_hex(path: &Path) -> std::io::Result<String> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hasher.finalize().iter().map(|b| format!("{b:02x}")).collect())
}

pub fn is_newer_version(candidate: &str, installed: &str) -> bool {
    fn parse(v: &str) -> Vec<u64> {
        v.trim_start_matches('v')
            .split('.')
            .map(|p| p.parse::<u64>().unwrap_or(0))
            .collect()
    }
    let a = parse(candidate);
    let b = parse(installed);
    let len = a.len().max(b.len());
    for i in 0..len {
        let av = *a.get(i).unwrap_or(&0);
        let bv = *b.get(i).unwrap_or(&0);
        if av != bv {
            return av > bv;
        }
    }
    false
}

pub fn verify_release_file(
    file: &Path,
    signature_bytes: &[u8],
    version: &str,
    installed_version: &str,
    public_key_b64: &str,
) -> VerifyVerdict {
    let Ok(pub_raw) = BASE64.decode(public_key_b64.trim()) else {
        return VerifyVerdict::Malformed;
    };
    let Ok(pub_arr): Result<[u8; 32], _> = pub_raw.try_into() else {
        return VerifyVerdict::Malformed;
    };
    let Ok(verifying_key) = VerifyingKey::from_bytes(&pub_arr) else {
        return VerifyVerdict::Malformed;
    };
    let Ok(sig_arr): Result<[u8; 64], _> = signature_bytes.try_into() else {
        return VerifyVerdict::Malformed;
    };
    let sig = Signature::from_bytes(&sig_arr);
    let Ok(sha) = sha256_hex(file) else {
        return VerifyVerdict::Malformed;
    };
    let msg = signed_message(version, &sha);
    if verifying_key.verify(&msg, &sig).is_err() {
        return VerifyVerdict::BadSignature;
    }
    if !is_newer_version(version, installed_version) {
        return VerifyVerdict::NotNewer;
    }
    VerifyVerdict::Valid
}

pub fn is_allowed_https_url(url: &str, allowed_hosts: &[&str]) -> bool {
    let Some(rest) = url.strip_prefix("https://") else {
        return false;
    };
    let host = rest.split(['/', ':', '?']).next().unwrap_or("").to_ascii_lowercase();
    allowed_hosts.iter().any(|h| *h == host)
}

pub fn is_huggingface_host(host: &str) -> bool {
    let h = host.to_ascii_lowercase();
    h == "huggingface.co" || h.ends_with(".huggingface.co") || h.ends_with(".hf.co")
}
