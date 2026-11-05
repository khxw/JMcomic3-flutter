use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::error::{BackendError, BackendResult};

const PAGE_SIZE: usize = 80;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LocalViewLog {
    id: i64,
    #[serde(default)]
    author: String,
    #[serde(default)]
    description: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    last_view_time: i64,
    #[serde(default)]
    last_view_chapter_id: i64,
    #[serde(default)]
    last_view_page: i64,
}

impl LocalViewLog {
    fn to_view_log_json(&self) -> Value {
        json!({
            "id": self.id,
            "author": self.author,
            "description": self.description,
            "name": self.name,
            "last_view_time": self.last_view_time,
            "last_view_chapter_id": self.last_view_chapter_id,
            "last_view_page": self.last_view_page,
        })
    }

    fn to_comic_json(&self) -> Value {
        json!({
            "id": self.id,
            "author": self.author,
            "description": self.description,
            "name": self.name,
            "image": "",
            "update_at": Value::Null,
            "addtime": Value::Null,
            "category": {"id": Value::Null, "title": Value::Null},
            "category_sub": {"id": Value::Null, "title": Value::Null},
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LocalSearchHistory {
    search_query: String,
    last_search_time: i64,
}

pub struct HistoryStore {
    view_logs_path: PathBuf,
    search_history_path: PathBuf,
    view_logs: Mutex<Vec<LocalViewLog>>,
    search_history: Mutex<Vec<LocalSearchHistory>>,
}

impl HistoryStore {
    pub fn open(root: &Path) -> BackendResult<Self> {
        fs::create_dir_all(root)?;
        let view_logs_path = root.join("view_logs.json");
        let search_history_path = root.join("search_histories.json");
        let view_logs = read_view_logs(&view_logs_path)?;
        let search_history = read_search_history(&search_history_path)?;
        Ok(Self {
            view_logs_path,
            search_history_path,
            view_logs: Mutex::new(view_logs),
            search_history: Mutex::new(search_history),
        })
    }

    pub fn find_view_log(&self, comic_id: i64) -> BackendResult<Option<Value>> {
        let logs = self.lock_view_logs()?;
        Ok(logs
            .iter()
            .find(|item| item.id == comic_id)
            .map(LocalViewLog::to_view_log_json))
    }

    pub fn page_view_log(&self, page: u32) -> BackendResult<Value> {
        let logs = self.lock_view_logs()?;
        let mut sorted = logs.clone();
        drop(logs);
        sorted.sort_by(|left, right| {
            right
                .last_view_time
                .cmp(&left.last_view_time)
                .then_with(|| right.id.cmp(&left.id))
        });
        let page = page.max(1) as usize;
        let start = (page - 1) * PAGE_SIZE;
        let content = sorted
            .iter()
            .skip(start)
            .take(PAGE_SIZE)
            .map(LocalViewLog::to_comic_json)
            .collect::<Vec<_>>();
        Ok(json!({
            "search_query": "",
            "total": sorted.len(),
            "redirect_aid": Value::Null,
            "page_size": PAGE_SIZE,
            "content": content,
        }))
    }

    pub fn update_view_log(
        &self,
        comic_id: i64,
        chapter_id: i64,
        page: i64,
        album: Option<&Value>,
    ) -> BackendResult<()> {
        self.update_view_log_at(comic_id, chapter_id, page, album, None)
    }

    pub fn update_view_log_at(
        &self,
        comic_id: i64,
        chapter_id: i64,
        page: i64,
        album: Option<&Value>,
        viewed_at: Option<i64>,
    ) -> BackendResult<()> {
        if comic_id <= 0 || chapter_id <= 0 || page < 0 {
            return Err(BackendError::Config("invalid view log values".into()));
        }
        let mut logs = self.lock_view_logs()?;
        let now = viewed_at
            .filter(|value| *value > 0)
            .unwrap_or_else(unix_timestamp);
        if let Some(existing) = logs.iter_mut().find(|item| item.id == comic_id) {
            existing.last_view_time = now;
            existing.last_view_chapter_id = chapter_id;
            existing.last_view_page = page;
        } else {
            let metadata = ViewMetadata::from_album(album);
            logs.push(LocalViewLog {
                id: comic_id,
                author: metadata.author,
                description: metadata.description,
                name: metadata.name,
                last_view_time: now,
                last_view_chapter_id: chapter_id,
                last_view_page: page,
            });
        }
        drop(logs);
        self.save_view_logs()
    }

    pub fn delete_view_log(&self, comic_id: i64) -> BackendResult<()> {
        let mut logs = self.lock_view_logs()?;
        logs.retain(|item| item.id != comic_id);
        drop(logs);
        self.save_view_logs()
    }

    pub fn clear_view_logs(&self) -> BackendResult<()> {
        self.lock_view_logs()?.clear();
        self.save_view_logs()
    }

    pub fn record_search(&self, query: &str) -> BackendResult<()> {
        let query = query.trim();
        if query.is_empty() {
            return Ok(());
        }
        let mut history = self.lock_search_history()?;
        let now = unix_timestamp();
        if let Some(existing) = history
            .iter_mut()
            .find(|item| item.search_query.eq_ignore_ascii_case(query))
        {
            existing.search_query = query.to_string();
            existing.last_search_time = now;
        } else {
            history.push(LocalSearchHistory {
                search_query: query.to_string(),
                last_search_time: now,
            });
        }
        history.sort_by(|left, right| right.last_search_time.cmp(&left.last_search_time));
        history.truncate(100);
        drop(history);
        self.save_search_history()
    }

    pub fn last_search_history(&self, count: usize) -> BackendResult<Vec<Value>> {
        let history = self.lock_search_history()?;
        let mut values = history.clone();
        drop(history);
        values.sort_by(|left, right| right.last_search_time.cmp(&left.last_search_time));
        Ok(values
            .into_iter()
            .take(count)
            .map(|item| {
                json!({
                    "search_query": item.search_query,
                    "last_search_time": item.last_search_time,
                })
            })
            .collect())
    }

    pub fn clear_all_search_history(&self) -> BackendResult<()> {
        self.lock_search_history()?.clear();
        self.save_search_history()
    }

    pub fn clear_search_history(&self, query: &str) -> BackendResult<()> {
        let mut history = self.lock_search_history()?;
        history.retain(|item| !item.search_query.eq_ignore_ascii_case(query.trim()));
        drop(history);
        self.save_search_history()
    }

    pub fn snapshot(&self) -> BackendResult<Value> {
        let view_logs = self
            .lock_view_logs()?
            .iter()
            .map(LocalViewLog::to_view_log_json)
            .collect::<Vec<_>>();
        let search_histories = self
            .lock_search_history()?
            .iter()
            .map(|item| {
                json!({
                    "search_query": item.search_query,
                    "last_search_time": item.last_search_time,
                })
            })
            .collect::<Vec<_>>();
        Ok(json!({
            "view_logs": view_logs,
            "search_histories": search_histories,
        }))
    }

    pub fn apply_snapshot(&self, snapshot: &Value, replace: bool) -> BackendResult<()> {
        let incoming_view_logs = snapshot
            .get("view_logs")
            .and_then(Value::as_array)
            .map(|values| {
                values
                    .iter()
                    .filter_map(|value| serde_json::from_value(value.clone()).ok())
                    .filter(|item: &LocalViewLog| item.id > 0)
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let incoming_searches = snapshot
            .get("search_histories")
            .and_then(Value::as_array)
            .map(|values| {
                values
                    .iter()
                    .filter_map(|value| serde_json::from_value(value.clone()).ok())
                    .filter(|item: &LocalSearchHistory| !item.search_query.trim().is_empty())
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();

        {
            let mut logs = self.lock_view_logs()?;
            if replace {
                *logs = incoming_view_logs;
            } else {
                for incoming in incoming_view_logs {
                    if let Some(existing) = logs.iter_mut().find(|item| item.id == incoming.id) {
                        if incoming.last_view_time >= existing.last_view_time {
                            *existing = incoming;
                        }
                    } else {
                        logs.push(incoming);
                    }
                }
            }
        }
        {
            let mut history = self.lock_search_history()?;
            if replace {
                *history = incoming_searches;
            } else {
                for incoming in incoming_searches {
                    if let Some(existing) = history.iter_mut().find(|item| {
                        item.search_query
                            .eq_ignore_ascii_case(&incoming.search_query)
                    }) {
                        if incoming.last_search_time >= existing.last_search_time {
                            *existing = incoming;
                        }
                    } else {
                        history.push(incoming);
                    }
                }
            }
            history.sort_by(|left, right| right.last_search_time.cmp(&left.last_search_time));
            history.truncate(100);
        }
        self.save_view_logs()?;
        self.save_search_history()
    }

    fn lock_view_logs(&self) -> BackendResult<std::sync::MutexGuard<'_, Vec<LocalViewLog>>> {
        self.view_logs
            .lock()
            .map_err(|_| BackendError::Config("view log lock poisoned".into()))
    }

    fn lock_search_history(
        &self,
    ) -> BackendResult<std::sync::MutexGuard<'_, Vec<LocalSearchHistory>>> {
        self.search_history
            .lock()
            .map_err(|_| BackendError::Config("search history lock poisoned".into()))
    }

    fn save_view_logs(&self) -> BackendResult<()> {
        let values = self.lock_view_logs()?.clone();
        write_json_atomic(&self.view_logs_path, &values)
    }

    fn save_search_history(&self) -> BackendResult<()> {
        let values = self.lock_search_history()?.clone();
        write_json_atomic(&self.search_history_path, &values)
    }
}

struct ViewMetadata {
    author: String,
    description: String,
    name: String,
}

impl ViewMetadata {
    fn from_album(album: Option<&Value>) -> Self {
        let album = album.and_then(Value::as_object);
        let author = album
            .and_then(|value| value.get("author"))
            .map(join_author)
            .unwrap_or_default();
        let description = album
            .and_then(|value| value.get("description"))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        let name = album
            .and_then(|value| value.get("name"))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        Self {
            author,
            description,
            name,
        }
    }
}

fn join_author(value: &Value) -> String {
    if let Some(value) = value.as_str() {
        return value.to_string();
    }
    value
        .as_array()
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .collect::<Vec<_>>()
                .join(" / ")
        })
        .unwrap_or_default()
}

fn read_view_logs(path: &Path) -> BackendResult<Vec<LocalViewLog>> {
    if !path.exists() {
        return Ok(Vec::new());
    }
    let raw = fs::read_to_string(path)?;
    if raw.trim().is_empty() {
        return Ok(Vec::new());
    }
    let decoded: Value = serde_json::from_str(&raw)?;
    let values = decoded
        .as_array()
        .cloned()
        .or_else(|| decoded.get("view_logs").and_then(Value::as_array).cloned())
        .unwrap_or_default();
    Ok(values
        .into_iter()
        .filter_map(|value| serde_json::from_value(value).ok())
        .filter(|item: &LocalViewLog| item.id > 0)
        .collect())
}

fn read_search_history(path: &Path) -> BackendResult<Vec<LocalSearchHistory>> {
    if !path.exists() {
        return Ok(Vec::new());
    }
    let raw = fs::read_to_string(path)?;
    if raw.trim().is_empty() {
        return Ok(Vec::new());
    }
    let decoded: Value = serde_json::from_str(&raw)?;
    let values = decoded
        .as_array()
        .cloned()
        .or_else(|| {
            decoded
                .get("search_histories")
                .and_then(Value::as_array)
                .cloned()
        })
        .unwrap_or_default();
    Ok(values
        .into_iter()
        .filter_map(|value| serde_json::from_value(value).ok())
        .filter(|item: &LocalSearchHistory| !item.search_query.trim().is_empty())
        .collect())
}

fn write_json_atomic(path: &Path, value: &impl Serialize) -> BackendResult<()> {
    let parent = path
        .parent()
        .ok_or_else(|| BackendError::Config("history path has no parent".into()))?;
    fs::create_dir_all(parent)?;
    let temporary = path.with_extension("json.tmp");
    fs::write(&temporary, serde_json::to_vec_pretty(value)?)?;
    if path.exists() {
        fs::remove_file(path)?;
    }
    fs::rename(temporary, path)?;
    Ok(())
}

fn unix_timestamp() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn view_logs_and_searches_round_trip() {
        let root = std::env::temp_dir().join(format!(
            "jmcomic3-backend-v2-history-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        let store = HistoryStore::open(&root).unwrap();
        store
            .update_view_log(
                7,
                8,
                12,
                Some(&json!({"name":"fixture","author":["a","b"],"description":"d"})),
            )
            .unwrap();
        store.record_search("alpha").unwrap();
        store.record_search("beta").unwrap();
        store
            .update_view_log_at(8, 9, 3, None, Some(1_700_000_000))
            .unwrap();
        let snapshot = store.snapshot().unwrap();
        assert_eq!(snapshot["view_logs"].as_array().unwrap().len(), 2);
        assert_eq!(
            store.find_view_log(8).unwrap().unwrap()["last_view_time"],
            1_700_000_000
        );
        assert_eq!(
            store.find_view_log(7).unwrap().unwrap()["last_view_page"],
            12
        );
        assert_eq!(store.page_view_log(1).unwrap()["total"], 2);
        assert_eq!(store.last_search_history(2).unwrap().len(), 2);
        store
            .apply_snapshot(
                &json!({
                    "view_logs": [{
                        "id": 9,
                        "author": "remote",
                        "description": "",
                        "name": "remote",
                        "last_view_time": 1,
                        "last_view_chapter_id": 10,
                        "last_view_page": 2
                    }],
                    "search_histories": [{
                        "search_query": "remote",
                        "last_search_time": 2
                    }]
                }),
                false,
            )
            .unwrap();
        assert!(store.find_view_log(9).unwrap().is_some());
        drop(store);

        let reopened = HistoryStore::open(&root).unwrap();
        assert!(reopened.find_view_log(7).unwrap().is_some());
        reopened.clear_view_logs().unwrap();
        reopened.clear_all_search_history().unwrap();
        fs::remove_dir_all(root).unwrap();
    }
}
