use aes::cipher::generic_array::GenericArray;
#[cfg(test)]
use aes::cipher::BlockEncrypt;
use aes::cipher::{BlockDecrypt, KeyInit};
use aes::Aes256;
use base64::engine::general_purpose;
use base64::Engine;

use crate::error::{BackendError, BackendResult};

const API_DATA_SECRET: &str = "185Hcomic3PAPP7R";

pub fn md5_hex(data: &str) -> String {
    format!("{:x}", md5::compute(data))
}

pub fn decrypt_api_data(timestamp: u64, payload: &str) -> BackendResult<String> {
    let encrypted = general_purpose::STANDARD
        .decode(payload)
        .map_err(|error| BackendError::Crypto(format!("base64: {error}")))?;
    decrypt_aes_ecb(timestamp, &encrypted)
}

fn decrypt_aes_ecb(timestamp: u64, encrypted: &[u8]) -> BackendResult<String> {
    if encrypted.is_empty() || encrypted.len() % 16 != 0 {
        return Err(BackendError::Crypto(
            "encrypted payload length is not a multiple of 16".into(),
        ));
    }
    let key = md5_hex(&format!("{timestamp}{API_DATA_SECRET}"));
    let cipher = Aes256::new(GenericArray::from_slice(key.as_bytes()));
    let mut decrypted = encrypted.to_vec();
    for block in decrypted.chunks_exact_mut(16) {
        cipher.decrypt_block(GenericArray::from_mut_slice(block));
    }
    let padding = *decrypted
        .last()
        .ok_or_else(|| BackendError::Crypto("empty decrypted payload".into()))?
        as usize;
    if !(1..=16).contains(&padding) || padding > decrypted.len() {
        return Err(BackendError::Crypto("invalid PKCS#7 padding".into()));
    }
    if decrypted[decrypted.len() - padding..]
        .iter()
        .any(|value| *value as usize != padding)
    {
        return Err(BackendError::Crypto("invalid PKCS#7 padding".into()));
    }
    decrypted.truncate(decrypted.len() - padding);
    String::from_utf8(decrypted).map_err(|error| BackendError::Crypto(format!("UTF-8: {error}")))
}

#[cfg(test)]
fn encrypt_api_data_for_test(timestamp: u64, payload: &str) -> String {
    let key = md5_hex(&format!("{timestamp}{API_DATA_SECRET}"));
    let cipher = Aes256::new(GenericArray::from_slice(key.as_bytes()));
    let mut bytes = payload.as_bytes().to_vec();
    let padding = 16 - (bytes.len() % 16);
    bytes.extend(std::iter::repeat_n(padding as u8, padding));
    for block in bytes.chunks_exact_mut(16) {
        cipher.encrypt_block(GenericArray::from_mut_slice(block));
    }
    general_purpose::STANDARD.encode(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decrypt_round_trip_rejects_bad_padding() {
        let payload = r#"{"id":7,"name":"fixture"}"#;
        let encrypted = encrypt_api_data_for_test(1_700_000_000, payload);
        assert_eq!(
            decrypt_api_data(1_700_000_000, &encrypted).unwrap(),
            payload
        );
        assert!(decrypt_api_data(1_700_000_000, "not-base64").is_err());
        assert!(decrypt_api_data(1_700_000_000, "AAAA").is_err());
    }
}
