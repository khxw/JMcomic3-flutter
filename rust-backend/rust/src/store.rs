use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::{Deserialize, Serialize};

use crate::error::{BackendError, BackendResult};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct StoreFile {
    #[serde(default)]
    properties: BTreeMap<String, String>,
}

pub struct PropertyStore {
    path: PathBuf,
    data: Mutex<StoreFile>,
}

impl PropertyStore {
    pub fn open(root: &Path) -> BackendResult<Self> {
        fs::create_dir_all(root)?;
        let path = root.join("properties.json");
        let data = if path.exists() {
            let raw = fs::read_to_string(&path)?;
            if raw.trim().is_empty() {
                StoreFile::default()
            } else {
                parse_properties(&raw)?
            }
        } else {
            StoreFile::default()
        };
        Ok(Self {
            path,
            data: Mutex::new(data),
        })
    }

    pub fn load(&self, key: &str) -> BackendResult<String> {
        if key.trim().is_empty() {
            return Err(BackendError::Config("property key is empty".into()));
        }
        let data = self
            .data
            .lock()
            .map_err(|_| BackendError::Config("property store lock poisoned".into()))?;
        Ok(data.properties.get(key).cloned().unwrap_or_default())
    }

    pub fn save(&self, key: &str, value: &str) -> BackendResult<()> {
        if key.trim().is_empty() {
            return Err(BackendError::Config("property key is empty".into()));
        }
        let mut data = self
            .data
            .lock()
            .map_err(|_| BackendError::Config("property store lock poisoned".into()))?;
        data.properties.insert(key.to_string(), value.to_string());
        let encoded = serde_json::to_vec_pretty(&*data)?;
        let temporary = self.path.with_extension("json.tmp");
        fs::write(&temporary, encoded)?;
        if self.path.exists() {
            fs::remove_file(&self.path)?;
        }
        fs::rename(temporary, &self.path)?;
        Ok(())
    }

    pub fn merge_missing_values(
        &self,
        values: &BTreeMap<String, serde_json::Value>,
    ) -> BackendResult<usize> {
        let mut data = self
            .data
            .lock()
            .map_err(|_| BackendError::Config("property store lock poisoned".into()))?;
        let mut inserted = 0;
        for (key, value) in values {
            if key.trim().is_empty() || data.properties.contains_key(key) {
                continue;
            }
            data.properties
                .insert(key.clone(), value_to_string(value.clone()));
            inserted += 1;
        }
        if inserted > 0 {
            let encoded = serde_json::to_vec_pretty(&*data)?;
            let temporary = self.path.with_extension("json.tmp");
            fs::write(&temporary, encoded)?;
            if self.path.exists() {
                fs::remove_file(&self.path)?;
            }
            fs::rename(temporary, &self.path)?;
        }
        Ok(inserted)
    }

    pub fn snapshot(&self) -> BackendResult<serde_json::Value> {
        let data = self
            .data
            .lock()
            .map_err(|_| BackendError::Config("property store lock poisoned".into()))?;
        Ok(serde_json::Value::Object(
            data.properties
                .iter()
                .filter(|(key, _)| !is_sensitive_property(key))
                .map(|(key, value)| (key.clone(), serde_json::Value::String(value.clone())))
                .collect(),
        ))
    }

    pub fn apply_snapshot(&self, snapshot: &serde_json::Value, replace: bool) -> BackendResult<()> {
        let incoming = snapshot
            .get("properties")
            .filter(|value| value.is_object())
            .unwrap_or(snapshot)
            .as_object()
            .ok_or_else(|| BackendError::Config("WebDAV properties are invalid".into()))?;
        let mut data = self
            .data
            .lock()
            .map_err(|_| BackendError::Config("property store lock poisoned".into()))?;
        if replace {
            data.properties.retain(|key, _| is_sensitive_property(key));
        }
        for (key, value) in incoming {
            if key.trim().is_empty() || is_sensitive_property(key) {
                continue;
            }
            data.properties
                .insert(key.clone(), value_to_string(value.clone()));
        }
        let encoded = serde_json::to_vec_pretty(&*data)?;
        let temporary = self.path.with_extension("json.tmp");
        fs::write(&temporary, encoded)?;
        if self.path.exists() {
            fs::remove_file(&self.path)?;
        }
        fs::rename(temporary, &self.path)?;
        Ok(())
    }
}

fn is_sensitive_property(key: &str) -> bool {
    let key = key.to_ascii_lowercase();
    [
        "cookie",
        "token",
        "password",
        "secret",
        "credential",
        "private",
        "proxy",
        "load_username",
        "last_login_username",
    ]
    .iter()
    .any(|marker| key.contains(marker))
}

fn parse_properties(raw: &str) -> BackendResult<StoreFile> {
    let decoded: serde_json::Value = serde_json::from_str(raw)?;
    let mut properties = BTreeMap::new();
    match decoded {
        serde_json::Value::Object(mut values) => {
            if let Some(serde_json::Value::Object(wrapped)) = values.remove("properties") {
                values = wrapped;
            }
            for (key, value) in values {
                if !key.trim().is_empty() {
                    properties.insert(key, value_to_string(value));
                }
            }
        }
        serde_json::Value::Array(values) => {
            for value in values {
                let Some(object) = value.as_object() else {
                    continue;
                };
                let key = object
                    .get("k")
                    .or_else(|| object.get("key"))
                    .and_then(|value| value.as_str())
                    .unwrap_or_default()
                    .trim();
                if key.is_empty() {
                    continue;
                }
                let value = object
                    .get("v")
                    .or_else(|| object.get("value"))
                    .cloned()
                    .unwrap_or(serde_json::Value::Null);
                properties.insert(key.to_string(), value_to_string(value));
            }
        }
        _ => {}
    }
    Ok(StoreFile { properties })
}

fn value_to_string(value: serde_json::Value) -> String {
    match value {
        serde_json::Value::String(value) => value,
        serde_json::Value::Null => String::new(),
        value => value.to_string(),
    }
}

impl From<std::io::Error> for BackendError {
    fn from(error: std::io::Error) -> Self {
        BackendError::Config(format!("filesystem: {error}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn properties_round_trip() {
        let root =
            std::env::temp_dir().join(format!("jmcomic3-backend-v2-store-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let store = PropertyStore::open(&root).unwrap();
        assert_eq!(store.load("missing").unwrap(), "");
        store.save("guest_mode", "true").unwrap();
        store.save("cookie", "secret-cookie").unwrap();
        assert_eq!(store.load("guest_mode").unwrap(), "true");
        let snapshot = store.snapshot().unwrap();
        assert!(snapshot.get("cookie").is_none());
        store
            .apply_snapshot(
                &serde_json::json!({"theme": "dark", "cookie": "remote-cookie"}),
                false,
            )
            .unwrap();
        assert_eq!(store.load("theme").unwrap(), "dark");
        assert_eq!(store.load("cookie").unwrap(), "secret-cookie");
        drop(store);

        let reopened = PropertyStore::open(&root).unwrap();
        assert_eq!(reopened.load("guest_mode").unwrap(), "true");
        fs::remove_dir_all(root).unwrap();
    }
}
