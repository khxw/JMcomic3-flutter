use std::net::{Ipv4Addr, Ipv6Addr};
use std::time::Duration;

use crate::error::{BackendError, BackendResult};

pub const DEFAULT_API_HOST: &str = "www.cdngwc.club";
pub const DEFAULT_IMAGE_HOST: &str = "cdn-msp3.jmapiproxy1.cc";
pub const DEFAULT_APP_VERSION: &str = "2.1.718";
pub const DEFAULT_USER_AGENT: &str = concat!(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ",
    "AppleWebKit/537.36 (KHTML, like Gecko) ",
    "Chrome/128.0.0.0 Safari/537.36"
);

#[derive(Debug, Clone)]
pub struct JmClientConfig {
    pub api_host: String,
    pub image_host: String,
    pub app_version: String,
    pub user_agent: String,
    pub request_timeout: Duration,
    pub max_retries: usize,
    pub proxy_url: Option<String>,
}

impl Default for JmClientConfig {
    fn default() -> Self {
        Self {
            api_host: DEFAULT_API_HOST.to_string(),
            image_host: DEFAULT_IMAGE_HOST.to_string(),
            app_version: DEFAULT_APP_VERSION.to_string(),
            user_agent: DEFAULT_USER_AGENT.to_string(),
            request_timeout: Duration::from_secs(15),
            max_retries: 2,
            proxy_url: None,
        }
    }
}

impl JmClientConfig {
    pub fn validated(mut self) -> BackendResult<Self> {
        self.api_host = normalize_host(&self.api_host)?;
        self.image_host = normalize_host(&self.image_host)?;
        if self.app_version.trim().is_empty() {
            return Err(BackendError::Config("app version is empty".into()));
        }
        if self.request_timeout.is_zero() {
            return Err(BackendError::Config(
                "request timeout must be greater than zero".into(),
            ));
        }
        Ok(self)
    }
}

pub(crate) fn normalize_host(raw: &str) -> BackendResult<String> {
    let mut value = raw.trim();
    if let Some(index) = value.find("://") {
        value = &value[index + 3..];
    } else if let Some(rest) = value.strip_prefix("//") {
        value = rest;
    }
    if let Some(index) = value.find(|character| matches!(character, '/' | '?' | '#')) {
        value = &value[..index];
    }
    if let Some(index) = value.rfind('@') {
        value = &value[index + 1..];
    }
    let value = value.trim();
    if !is_valid_host_authority(value) {
        return Err(BackendError::Config("invalid host".into()));
    }
    Ok(value.to_string())
}

fn is_valid_host_authority(value: &str) -> bool {
    if value.is_empty() || value.len() > 260 {
        return false;
    }
    let (host, port) = if let Some(rest) = value.strip_prefix('[') {
        let Some(end) = rest.find(']') else {
            return false;
        };
        let host = &rest[..end];
        let suffix = &rest[end + 1..];
        if suffix.is_empty() {
            (host, None)
        } else if let Some(port) = suffix.strip_prefix(':') {
            (host, Some(port))
        } else {
            return false;
        }
    } else if let Some((host, port)) = value.rsplit_once(':') {
        if host.contains(':') {
            return false;
        }
        (host, Some(port))
    } else {
        (value, None)
    };
    if let Some(port) = port {
        if port.is_empty()
            || !port.chars().all(|character| character.is_ascii_digit())
            || port.parse::<u16>().is_err()
        {
            return false;
        }
    }
    if host.eq_ignore_ascii_case("localhost")
        || host.parse::<Ipv4Addr>().is_ok()
        || host.parse::<Ipv6Addr>().is_ok()
    {
        return true;
    }
    if !host.contains('.') || host.len() > 253 {
        return false;
    }
    host.split('.').all(|label| {
        !label.is_empty()
            && label.len() <= 63
            && label
                .chars()
                .all(|character| character.is_ascii_alphanumeric() || character == '-')
            && label
                .chars()
                .next()
                .is_some_and(|character| character.is_ascii_alphanumeric())
            && label
                .chars()
                .last()
                .is_some_and(|character| character.is_ascii_alphanumeric())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_normalization_matches_bridge_contract() {
        let config = JmClientConfig {
            api_host: " https://user:pass@api.example.com:9443/path?q=1 ".into(),
            image_host: "//cdn.example.com/a".into(),
            ..Default::default()
        }
        .validated()
        .unwrap();

        assert_eq!(config.api_host, "api.example.com:9443");
        assert_eq!(config.image_host, "cdn.example.com");
    }

    #[test]
    fn host_validation_rejects_tokens_and_invalid_ports() {
        let malformed = format!(
            "X+{}",
            "bnzYIcwF6C7Rd3T7njPErjfPO12gw6b1UQbMx53J7eJnjoOOhKBOjz085QJ2PESutvUIqkJ3UVzPW4o7WbmCbSsN2AQANumvn8tOnTbM0EvvHfFaiMo0ZgXsDGe4QytJpsAZ"
        );
        assert!(normalize_host(&malformed).is_err());
        assert!(normalize_host("api.example.com:70000").is_err());
        assert_eq!(
            normalize_host("api.example.com:9443").unwrap(),
            "api.example.com:9443"
        );
    }
}
