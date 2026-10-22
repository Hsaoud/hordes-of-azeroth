use anyhow::{Result, bail};
use data_encoding::BASE32_NOPAD;
use sha2::{Digest, Sha256};

pub fn encode(id: &[u8; 32], secret: &[u8; 16]) -> String {
    let mut bytes = Vec::from(id.as_slice());
    bytes.extend(secret);
    let checksum = Sha256::digest(&bytes);
    bytes.extend(&checksum[..2]);
    format!("HOA1-{}", BASE32_NOPAD.encode(&bytes))
}

pub fn decode(text: &str) -> Result<([u8; 32], [u8; 16])> {
    let normalized: String = text.chars().filter(|c| !c.is_whitespace() && *c != '-').collect::<String>().to_uppercase();
    let Some(encoded) = normalized.strip_prefix("HOA1") else { bail!("invalid-code") };
    if encoded.len() != 80 { bail!("invalid-code") }
    let bytes = BASE32_NOPAD.decode(encoded.as_bytes()).map_err(|_| anyhow::anyhow!("invalid-code"))?;
    if Sha256::digest(&bytes[..48])[..2] != bytes[48..] { bail!("invalid-code") }
    Ok((bytes[..32].try_into()?, bytes[32..48].try_into()?))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invitation_round_trip_and_paste() {
        let code = encode(&[42; 32], &[17; 16]);
        assert_eq!(decode(&format!("  {}\n", code.to_lowercase())).unwrap(), ([42; 32], [17; 16]));
        assert!(decode(&code.replace('K', "L")).is_err());
        assert!(decode("HOA1-hello").is_err());
        assert!(decode(&code.replace("HOA1", "HOA2")).is_err());
    }
}
