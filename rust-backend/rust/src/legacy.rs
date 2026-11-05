use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{json, Map, Value};

use crate::error::{BackendError, BackendResult};
use crate::history::HistoryStore;
use crate::store::PropertyStore;

const LEGACY_DIR: &str = "jmcomic3";
const LEGACY_COMBINED_FILE: &str = "frb_store.json";
const LEGACY_PARTS_DIR: &str = "frb_store_parts";
const MIGRATION_MARKER: &str = "v2_legacy_migration.json";

#[derive(Debug, Default)]
pub struct MigrationReport {
    pub migrated: bool,
    pub properties: usize,
    pub view_logs: usize,
    pub search_histories: usize,
}

#[derive(Debug, Default)]
struct LegacySnapshot {
    properties: BTreeMap<String, Value>,
    view_logs: Vec<Value>,
    search_histories: Vec<Value>,
}

pub fn migrate_if_needed(
    root: &Path,
    store: &PropertyStore,
    history: &HistoryStore,
) -> BackendResult<MigrationReport> {
    let legacy_root = root.join(LEGACY_DIR);
    let marker = legacy_root.join(MIGRATION_MARKER);
    if marker.is_file() {
        return Ok(MigrationReport::default());
    }

    let snapshot = load_legacy_snapshot(&legacy_root)?;
    if snapshot.properties.is_empty()
        && snapshot.view_logs.is_empty()
        && snapshot.search_histories.is_empty()
    {
        return Ok(MigrationReport::default());
    }

    let inserted_properties = store.merge_missing_values(&snapshot.properties)?;
    if !snapshot.view_logs.is_empty() || !snapshot.search_histories.is_empty() {
        history.apply_snapshot(
            &json!({
                "view_logs": snapshot.view_logs,
                "search_histories": snapshot.search_histories,
            }),
            false,
        )?;
    }

    write_marker(&marker)?;
    Ok(MigrationReport {
        migrated: true,
        properties: inserted_properties,
        view_logs: snapshot.view_logs.len(),
        search_histories: snapshot.search_histories.len(),
    })
}

fn load_legacy_snapshot(legacy_root: &Path) -> BackendResult<LegacySnapshot> {
    let combined = read_json(&legacy_root.join(LEGACY_COMBINED_FILE))?;
    let mut snapshot = LegacySnapshot::default();

    if let Some(value) = combined.as_ref().and_then(Value::as_object) {
        if let Some(properties) = value.get("properties").and_then(Value::as_object) {
            merge_value_map(&mut snapshot.properties, properties);
        }
        merge_network_fields(&mut snapshot.properties, value);
        snapshot.view_logs = normalize_records(value.get("view_logs"), "id");
        snapshot.search_histories =
            normalize_records(value.get("search_histories"), "search_query");
    }

    let parts_root = legacy_root.join(LEGACY_PARTS_DIR);
    if let Some(properties) = read_json(&parts_root.join("properties.json"))?
        .as_ref()
        .and_then(Value::as_object)
    {
        merge_value_map(&mut snapshot.properties, properties);
    }
    if let Some(network) = read_json(&parts_root.join("network.json"))?
        .as_ref()
        .and_then(Value::as_object)
    {
        merge_network_fields(&mut snapshot.properties, network);
    }
    if snapshot.view_logs.is_empty() {
        if let Some(value) = read_json(&parts_root.join("view_logs.json"))? {
            snapshot.view_logs = normalize_records(Some(&value), "id");
        }
    }
    if snapshot.search_histories.is_empty() {
        if let Some(value) = read_json(&parts_root.join("search_histories.json"))? {
            snapshot.search_histories = normalize_records(Some(&value), "search_query");
        }
    }

    add_login_aliases(&mut snapshot.properties);
    Ok(snapshot)
}

fn read_json(path: &Path) -> BackendResult<Option<Value>> {
    if !path.is_file() {
        return Ok(None);
    }
    let raw = fs::read_to_string(path)?;
    if raw.trim().is_empty() {
        return Ok(None);
    }
    serde_json::from_str(&raw).map(Some).map_err(|error| {
        BackendError::Config(format!("legacy store parse {}: {error}", path.display()))
    })
}

fn merge_value_map(target: &mut BTreeMap<String, Value>, source: &Map<String, Value>) {
    for (key, value) in source {
        if key.trim().is_empty() || is_empty_value(value) {
            continue;
        }
        target.entry(key.clone()).or_insert_with(|| value.clone());
    }
}

fn merge_network_fields(target: &mut BTreeMap<String, Value>, source: &Map<String, Value>) {
    const NETWORK_FIELDS: &[&str] = &[
        "api_host",
        "cdn_host",
        "proxy",
        "cookie",
        "auth_token",
        "username",
        "password",
        "last_login_username",
        "config_links",
        "app_config",
    ];
    for key in NETWORK_FIELDS {
        if let Some(value) = source.get(*key) {
            if !is_empty_value(value) {
                target
                    .entry((*key).to_string())
                    .or_insert_with(|| value.clone());
            }
        }
    }
}

fn add_login_aliases(properties: &mut BTreeMap<String, Value>) {
    alias_value(
        properties,
        "username",
        &["remember_login_username", "load_username"],
    );
    alias_value(
        properties,
        "password",
        &["remember_login_password", "load_password"],
    );
    alias_value(properties, "remember_login_username", &["load_username"]);
    alias_value(properties, "remember_login_password", &["load_password"]);
    alias_value(properties, "last_login_username", &["load_username"]);
}

fn alias_value(properties: &mut BTreeMap<String, Value>, source: &str, targets: &[&str]) {
    let Some(value) = properties.get(source).cloned() else {
        return;
    };
    for target in targets {
        properties
            .entry((*target).to_string())
            .or_insert_with(|| value.clone());
    }
}

fn normalize_records(value: Option<&Value>, id_field: &str) -> Vec<Value> {
    let Some(value) = value else {
        return Vec::new();
    };
    if let Some(values) = value.as_array() {
        return values
            .iter()
            .filter(|item| item.as_object().is_some())
            .cloned()
            .collect();
    }
    let Some(values) = value.as_object() else {
        return Vec::new();
    };
    if let Some(values) = values.get("content").and_then(Value::as_array) {
        return values
            .iter()
            .filter(|item| item.as_object().is_some())
            .cloned()
            .collect();
    }
    let mut records = Vec::new();
    for (key, value) in values {
        let Some(mut object) = value.as_object().cloned() else {
            continue;
        };
        if !object.contains_key(id_field) {
            if let Ok(id) = key.parse::<i64>() {
                object.insert(id_field.to_string(), json!(id));
            }
        }
        if !object.contains_key(id_field) {
            continue;
        }
        records.push(Value::Object(object));
    }
    records
}

fn is_empty_value(value: &Value) -> bool {
    match value {
        Value::Null => true,
        Value::String(value) => value.trim().is_empty(),
        Value::Array(values) => values.is_empty(),
        Value::Object(values) => values.is_empty(),
        _ => false,
    }
}

fn write_marker(path: &Path) -> BackendResult<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let migrated_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs())
        .unwrap_or(0);
    let temporary = path.with_extension("json.tmp");
    fs::write(
        &temporary,
        serde_json::to_vec_pretty(&json!({
            "version": 1,
            "migrated_at": migrated_at,
        }))?,
    )?;
    if path.exists() {
        fs::remove_file(path)?;
    }
    fs::rename(temporary, path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn test_root(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "jmcomic3-legacy-migration-{name}-{}",
            std::process::id()
        ))
    }

    #[test]
    fn legacy_combined_store_restores_properties_login_and_history_once() {
        let root = test_root("combined");
        let _ = fs::remove_dir_all(&root);
        let legacy = root.join(LEGACY_DIR);
        fs::create_dir_all(&legacy).unwrap();
        fs::write(
            legacy.join(LEGACY_COMBINED_FILE),
            serde_json::to_vec(&json!({
                "properties": {
                    "local_bookshelf_v1": "[{\"id\":7}]",
                    "remember_login_username": "reader",
                    "remember_login_password": "secret"
                },
                "api_host": "api.example.com",
                "cookie": "",
                "view_logs": {
                    "7": {
                        "name": "fixture",
                        "last_view_chapter_id": 8,
                        "last_view_page": 3,
                        "last_view_time": 100
                    }
                },
                "search_histories": [{
                    "search_query": "alpha",
                    "last_search_time": 101
                }]
            }))
            .unwrap(),
        )
        .unwrap();

        let store = PropertyStore::open(&root).unwrap();
        let history = HistoryStore::open(&root).unwrap();
        let report = migrate_if_needed(&root, &store, &history).unwrap();
        assert!(report.migrated);
        assert_eq!(store.load("api_host").unwrap(), "api.example.com");
        assert_eq!(store.load("remember_login_username").unwrap(), "reader");
        assert_eq!(store.load("load_username").unwrap(), "reader");
        assert_eq!(store.load("local_bookshelf_v1").unwrap(), "[{\"id\":7}]");
        assert_eq!(
            history.find_view_log(7).unwrap().unwrap()["last_view_page"],
            3
        );
        assert_eq!(history.last_search_history(2).unwrap().len(), 1);
        assert!(legacy.join(MIGRATION_MARKER).is_file());

        fs::write(
            legacy.join(LEGACY_COMBINED_FILE),
            serde_json::to_vec(&json!({
                "view_logs": {
                    "9": {
                        "name": "late",
                        "last_view_chapter_id": 9,
                        "last_view_page": 1,
                        "last_view_time": 200
                    }
                }
            }))
            .unwrap(),
        )
        .unwrap();
        let repeated = migrate_if_needed(&root, &store, &history).unwrap();
        assert!(!repeated.migrated);
        assert!(history.find_view_log(9).unwrap().is_none());
        fs::remove_dir_all(root).unwrap();
    }
}
