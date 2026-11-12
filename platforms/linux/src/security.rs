//! `org.freedesktop.secrets` (`libsecret` / GNOME Keyring / KWallet) storage for the
//! 256-bit AES-GCM local store key.

pub const SECRET_SCHEMA_NAME: &str = "org.edevs.NexoLLM.StoreKey";
pub const SECRET_ATTRIBUTE_ACCOUNT: &str = "local-aes256-gcm-v1";
