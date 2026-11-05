use thiserror::Error;

pub type BackendResult<T> = Result<T, BackendError>;

#[derive(Debug, Error)]
pub enum BackendError {
    #[error("invalid configuration: {0}")]
    Config(String),
    #[error("HTTP request failed: {0}")]
    Http(#[from] reqwest::Error),
    #[error("HTTP {status}: {body}")]
    HttpStatus { status: u16, body: String },
    #[error("JM API error {code}: {message}")]
    Api { code: i64, message: String },
    #[error("invalid API response: {0}")]
    InvalidResponse(String),
    #[error("decryption failed: {0}")]
    Crypto(String),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}
