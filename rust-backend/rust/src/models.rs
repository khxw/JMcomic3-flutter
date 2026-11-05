use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Deserialize)]
pub struct JmApiResponse {
    pub code: i64,
    pub data: Value,
    #[serde(default, alias = "errorMsg")]
    pub error_msg: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SearchSort {
    #[serde(rename = "mr")]
    Latest,
    #[serde(rename = "mv")]
    View,
    #[serde(rename = "mp")]
    Picture,
    #[serde(rename = "tf")]
    Like,
}

impl SearchSort {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Latest => "mr",
            Self::View => "mv",
            Self::Picture => "mp",
            Self::Like => "tf",
        }
    }
}

impl std::str::FromStr for SearchSort {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value.trim().to_ascii_lowercase().as_str() {
            "mr" | "latest" => Ok(Self::Latest),
            "mv" | "view" => Ok(Self::View),
            "mp" | "picture" => Ok(Self::Picture),
            "tf" | "like" => Ok(Self::Like),
            other => Err(format!("unsupported search sort: {other}")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn search_sort_accepts_api_and_readable_names() {
        assert_eq!("mr".parse::<SearchSort>().unwrap(), SearchSort::Latest);
        assert_eq!(
            "picture".parse::<SearchSort>().unwrap(),
            SearchSort::Picture
        );
        assert!("unknown".parse::<SearchSort>().is_err());
    }
}
