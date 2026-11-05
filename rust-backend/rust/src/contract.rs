use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Deserialize)]
pub struct InvokeRequest {
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

impl InvokeRequest {
    pub fn decoded_params(&self) -> Value {
        match self.params.as_str() {
            Some(raw) if !raw.trim().is_empty() => {
                serde_json::from_str(raw).unwrap_or_else(|_| self.params.clone())
            }
            _ => self.params.clone(),
        }
    }
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct InvokeResponse {
    pub error_message: String,
    pub response_data: String,
}

impl InvokeResponse {
    pub fn success_value(value: &Value) -> Self {
        Self {
            error_message: String::new(),
            response_data: serde_json::to_string(value).unwrap_or_else(|_| "null".to_string()),
        }
    }

    pub fn success_text(value: impl Into<String>) -> Self {
        Self {
            error_message: String::new(),
            response_data: value.into(),
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            error_message: message.into(),
            response_data: String::new(),
        }
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| {
            r#"{"error_message":"response serialization failed","response_data":""}"#.to_string()
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn envelope_matches_flutter_method_channel_contract() {
        let response = InvokeResponse::success_value(&serde_json::json!({"id": 7}));
        let decoded: Value = serde_json::from_str(&response.to_json()).unwrap();
        assert_eq!(decoded["error_message"], "");
        assert_eq!(decoded["response_data"], r#"{"id":7}"#);
    }

    #[test]
    fn bridge_string_params_are_decoded_once() {
        let request = InvokeRequest {
            method: "album".into(),
            params: Value::String(r#"{"id":7}"#.into()),
        };
        assert_eq!(request.decoded_params()["id"], 7);
    }
}
