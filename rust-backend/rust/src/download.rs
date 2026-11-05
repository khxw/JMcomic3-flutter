use std::collections::HashMap;
use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::error::{BackendError, BackendResult};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadChapterRecord {
    pub id: i64,
    pub name: String,
    pub sort: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadAlbumRecord {
    pub id: i64,
    pub name: String,
    pub author: Vec<String>,
    pub tags: Vec<String>,
    pub works: Vec<String>,
    pub description: String,
    pub chapters: Vec<DownloadChapterRecord>,
    pub directory_name: String,
    #[serde(default)]
    pub dl_square_cover_status: i64,
    #[serde(default)]
    pub dl_3x4_cover_status: i64,
    #[serde(default)]
    pub dl_status: i64,
    #[serde(default)]
    pub image_count: i64,
    #[serde(default)]
    pub dled_image_count: i64,
    #[serde(default)]
    pub updated_at: i64,
}

pub struct DownloadControl {
    paused: AtomicBool,
    cancelled: AtomicBool,
}

impl DownloadControl {
    fn new() -> Self {
        Self {
            paused: AtomicBool::new(false),
            cancelled: AtomicBool::new(false),
        }
    }

    pub fn is_paused(&self) -> bool {
        self.paused.load(Ordering::Relaxed)
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Relaxed)
    }

    fn pause(&self) {
        self.paused.store(true, Ordering::Relaxed);
    }

    fn resume(&self) {
        self.paused.store(false, Ordering::Relaxed);
    }

    fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
        self.paused.store(false, Ordering::Relaxed);
    }
}

pub struct DownloadManager {
    index_path: PathBuf,
    root: Mutex<PathBuf>,
    records: Mutex<Vec<DownloadAlbumRecord>>,
    save_lock: Mutex<()>,
    legacy_backup_pending: Mutex<bool>,
    controls: Mutex<HashMap<i64, Arc<DownloadControl>>>,
}

impl DownloadManager {
    pub fn open(app_data_root: &Path, download_root: PathBuf) -> BackendResult<Self> {
        fs::create_dir_all(app_data_root)?;
        fs::create_dir_all(&download_root)?;
        let index_path = app_data_root.join("downloads.json");
        let (records, legacy_backup_pending) = if index_path.exists() {
            let raw = fs::read_to_string(&index_path)?;
            if raw.trim().is_empty() {
                (Vec::new(), false)
            } else {
                load_records(&raw, &download_root).map_err(|error| {
                    BackendError::Config(format!(
                        "unable to migrate {} without risking local download data: {error}",
                        index_path.display()
                    ))
                })?
            }
        } else {
            (Vec::new(), false)
        };
        Ok(Self {
            index_path,
            root: Mutex::new(download_root),
            records: Mutex::new(records),
            save_lock: Mutex::new(()),
            legacy_backup_pending: Mutex::new(legacy_backup_pending),
            controls: Mutex::new(HashMap::new()),
        })
    }

    pub fn root(&self) -> BackendResult<PathBuf> {
        self.root
            .lock()
            .map(|value| value.clone())
            .map_err(|_| BackendError::Config("download root lock poisoned".into()))
    }

    pub fn set_root(&self, root: PathBuf) -> BackendResult<()> {
        fs::create_dir_all(&root)?;
        *self
            .root
            .lock()
            .map_err(|_| BackendError::Config("download root lock poisoned".into()))? = root;
        Ok(())
    }

    pub fn create(&self, create: &Value) -> BackendResult<DownloadAlbumRecord> {
        let album = create
            .get("album")
            .and_then(Value::as_object)
            .ok_or_else(|| BackendError::InvalidResponse("download album is missing".into()))?;
        let id = album.get("id").and_then(Value::as_i64).unwrap_or(0);
        if id <= 0 {
            return Err(BackendError::Config("download album id is invalid".into()));
        }
        let name = string(album.get("name"));
        let chapters = create
            .get("chapters")
            .and_then(Value::as_array)
            .map(|values| {
                values
                    .iter()
                    .filter_map(|value| {
                        let id = value.get("id")?.as_i64()?;
                        (id > 0).then(|| DownloadChapterRecord {
                            id,
                            name: string(value.get("name")),
                            sort: string(value.get("sort")),
                        })
                    })
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        if chapters.is_empty() {
            return Err(BackendError::Config("download has no chapters".into()));
        }
        let record = DownloadAlbumRecord {
            id,
            name: name.clone(),
            author: string_list(album.get("author")),
            tags: string_list(album.get("tags")),
            works: string_list(album.get("works")),
            description: string(album.get("description")),
            chapters,
            directory_name: format!("{id}_{}", safe_component(&name)),
            dl_square_cover_status: 0,
            dl_3x4_cover_status: 0,
            dl_status: 0,
            image_count: 0,
            dled_image_count: 0,
            updated_at: unix_timestamp(),
        };
        let root = self.root()?;
        for chapter in &record.chapters {
            fs::create_dir_all(chapter_dir(&root, &record, chapter))?;
        }
        fs::create_dir_all(root.join(&record.directory_name))?;
        let mut records = self.lock_records()?;
        records.retain(|item| item.id != id);
        records.push(record.clone());
        drop(records);
        self.save()?;
        Ok(record)
    }

    pub fn get(&self, album_id: i64) -> BackendResult<Option<DownloadAlbumRecord>> {
        Ok(self
            .lock_records()?
            .iter()
            .find(|item| item.id == album_id)
            .cloned())
    }

    pub fn new_task(&self, album_id: i64) -> BackendResult<Arc<DownloadControl>> {
        let control = Arc::new(DownloadControl::new());
        let mut controls = self
            .controls
            .lock()
            .map_err(|_| BackendError::Config("download control lock poisoned".into()))?;
        if let Some(previous) = controls.insert(album_id, control.clone()) {
            previous.cancel();
        }
        Ok(control)
    }

    pub fn current_task(&self, album_id: i64) -> BackendResult<Option<Arc<DownloadControl>>> {
        Ok(self
            .controls
            .lock()
            .map_err(|_| BackendError::Config("download control lock poisoned".into()))?
            .get(&album_id)
            .cloned())
    }

    pub fn pause_task(&self, album_id: i64) -> BackendResult<()> {
        let has_record = {
            let mut records = self.lock_records()?;
            let record = records
                .iter_mut()
                .find(|item| item.id == album_id)
                .ok_or_else(|| BackendError::Config("download album not found".into()))?;
            record.dl_status = 4;
            record.updated_at = unix_timestamp();
            true
        };
        if let Some(control) = self.current_task(album_id)? {
            control.pause();
        }
        if has_record {
            self.save()?;
        }
        Ok(())
    }

    pub fn resume_running_task(
        &self,
        album_id: i64,
    ) -> BackendResult<Option<Arc<DownloadControl>>> {
        let control = self.current_task(album_id)?;
        if let Some(control) = control.as_ref() {
            control.resume();
            if let Some(record) = self
                .lock_records()?
                .iter_mut()
                .find(|item| item.id == album_id)
            {
                record.dl_status = 0;
                record.updated_at = unix_timestamp();
            }
            self.save()?;
        }
        Ok(control)
    }

    pub fn finish_task(&self, album_id: i64, control: &Arc<DownloadControl>) {
        if let Ok(mut controls) = self.controls.lock() {
            if controls
                .get(&album_id)
                .is_some_and(|current| Arc::ptr_eq(current, control))
            {
                controls.remove(&album_id);
            }
        }
    }

    pub fn all_json(&self) -> BackendResult<Value> {
        let mut records = self.lock_records()?.clone();
        records.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
        Ok(Value::Array(
            records.iter().map(record_to_download_album).collect(),
        ))
    }

    pub fn album_json(&self, album_id: i64) -> BackendResult<Value> {
        Ok(self
            .get(album_id)?
            .map(|record| record_to_download_album(&record))
            .unwrap_or(Value::Null))
    }

    pub fn create_json(&self, album_id: i64) -> BackendResult<Value> {
        Ok(self
            .get(album_id)?
            .map(|record| {
                json!({
                    "album": {
                        "id": record.id,
                        "name": record.name,
                        "author": record.author,
                        "tags": record.tags,
                        "works": record.works,
                        "description": record.description,
                    },
                    "chapters": record.chapters.iter().map(|chapter| json!({
                        "id": chapter.id,
                        "name": chapter.name,
                        "sort": chapter.sort,
                    })).collect::<Vec<_>>(),
                })
            })
            .unwrap_or(Value::Null))
    }

    pub fn chapter_images_json(
        &self,
        chapter_id: i64,
        include_availability: bool,
    ) -> BackendResult<Value> {
        let record = self
            .lock_records()?
            .iter()
            .find(|item| item.chapters.iter().any(|chapter| chapter.id == chapter_id))
            .cloned()
            .ok_or_else(|| BackendError::Config("download chapter not found".into()))?;
        let chapter = record
            .chapters
            .iter()
            .find(|chapter| chapter.id == chapter_id)
            .ok_or_else(|| BackendError::Config("download chapter not found".into()))?;
        let root = self.root()?;
        let directory = chapter_dir(&root, &record, chapter);
        let mut files = fs::read_dir(directory)
            .map(|entries| {
                entries
                    .filter_map(Result::ok)
                    .map(|entry| entry.path())
                    .filter(|path| path.is_file())
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        files.sort();
        Ok(Value::Array(
            files
                .into_iter()
                .enumerate()
                .map(|(index, path)| {
                    let name = path
                        .file_name()
                        .and_then(|value| value.to_str())
                        .unwrap_or_default()
                        .to_string();
                    let (width, height) = image::image_dimensions(&path).unwrap_or((0, 0));
                    let mut value = json!({
                        "album_id": record.id,
                        "chapter_id": chapter_id,
                        "image_index": index,
                        "name": name,
                        "key": name,
                        "dl_status": 1,
                        "width": width,
                        "height": height,
                    });
                    if include_availability {
                        value["local_path"] = json!(path.to_string_lossy());
                        value["local_available"] = json!(path.is_file());
                        value["local_state"] = json!("available");
                    } else {
                        value["local_path"] = json!(path.to_string_lossy());
                    }
                    value
                })
                .collect(),
        ))
    }

    pub fn renew_all(&self) -> BackendResult<()> {
        let root = self.root()?;
        let task_states = self
            .controls
            .lock()
            .map_err(|_| BackendError::Config("download control lock poisoned".into()))?
            .iter()
            .filter(|(_, control)| !control.is_cancelled())
            .map(|(id, control)| (*id, control.is_paused()))
            .collect::<HashMap<_, _>>();
        let mut records = self.lock_records()?;
        for record in records.iter_mut() {
            let previous_status = record.dl_status;
            let task_state = task_states.get(&record.id).copied();
            let mut files_on_disk = 0_i64;
            let mut chapters_with_files = 0_usize;
            for chapter in &record.chapters {
                let mut chapter_files = 0_i64;
                for entry in fs::read_dir(chapter_dir(&root, record, chapter))
                    .into_iter()
                    .flatten()
                    .filter_map(Result::ok)
                {
                    if entry.path().is_file() {
                        files_on_disk += 1;
                        chapter_files += 1;
                    }
                }
                if chapter_files > 0 {
                    chapters_with_files += 1;
                }
            }
            let expected_images = record.image_count.max(files_on_disk);
            let all_chapters_have_files =
                !record.chapters.is_empty() && chapters_with_files == record.chapters.len();
            record.image_count = expected_images;
            record.dled_image_count = files_on_disk;

            // `files_on_disk` is only the number of existing files, never the
            // expected total. Preserve a completed task only when its recorded
            // image count is satisfied. A task that was still queued/downloading
            // must not become "downloaded" merely because some files exist.
            if let Some(paused) = task_state {
                record.dl_status = if paused { 4 } else { 0 };
            } else if previous_status == 4 {
                record.dl_status = 4;
            } else if previous_status == 1
                && files_on_disk > 0
                && all_chapters_have_files
                && (expected_images == 0 || files_on_disk >= expected_images)
            {
                record.dl_status = 1;
            } else if files_on_disk > 0 || previous_status == 1 {
                record.dl_status = 2;
            } else {
                record.dl_status = previous_status;
            }
            record.updated_at = unix_timestamp();
        }
        drop(records);
        self.save()
    }

    pub fn delete(&self, album_id: i64) -> BackendResult<()> {
        let root = self.root()?;
        if let Some(control) = self.current_task(album_id)? {
            control.cancel();
        }
        if let Ok(mut controls) = self.controls.lock() {
            controls.remove(&album_id);
        }
        let mut records = self.lock_records()?;
        let removed = records.iter().find(|item| item.id == album_id).cloned();
        records.retain(|item| item.id != album_id);
        drop(records);
        self.save()?;
        if let Some(record) = removed {
            let directory = root.join(record.directory_name);
            let resolved_root = root.canonicalize().unwrap_or(root);
            let resolved_dir = directory
                .canonicalize()
                .unwrap_or_else(|_| directory.clone());
            if resolved_dir.starts_with(&resolved_root) && resolved_dir.exists() {
                fs::remove_dir_all(resolved_dir)?;
            }
        }
        Ok(())
    }

    pub fn set_progress(
        &self,
        album_id: i64,
        image_count: i64,
        downloaded: i64,
        status: i64,
    ) -> BackendResult<()> {
        let mut records = self.lock_records()?;
        if let Some(record) = records.iter_mut().find(|item| item.id == album_id) {
            record.image_count = record.image_count.max(image_count);
            record.dled_image_count = downloaded;
            if status != 0 || record.dl_status != 4 {
                record.dl_status = status;
            }
            record.updated_at = unix_timestamp();
        }
        drop(records);
        self.save()
    }

    pub fn mark_running(
        &self,
        album_id: i64,
        image_count: i64,
        downloaded: i64,
    ) -> BackendResult<()> {
        let mut records = self.lock_records()?;
        if let Some(record) = records.iter_mut().find(|item| item.id == album_id) {
            record.image_count = record.image_count.max(image_count);
            record.dled_image_count = downloaded;
            record.dl_status = 0;
            record.updated_at = unix_timestamp();
        }
        drop(records);
        self.save()
    }

    pub fn mark_failed(&self, album_id: i64) -> BackendResult<()> {
        let mut records = self.lock_records()?;
        if let Some(record) = records.iter_mut().find(|item| item.id == album_id) {
            record.dl_status = 2;
            record.updated_at = unix_timestamp();
        }
        drop(records);
        self.save()
    }

    pub fn mark_covers_done(&self, album_id: i64) -> BackendResult<()> {
        let mut records = self.lock_records()?;
        if let Some(record) = records.iter_mut().find(|item| item.id == album_id) {
            record.dl_square_cover_status = 1;
            record.dl_3x4_cover_status = 1;
            record.updated_at = unix_timestamp();
        }
        drop(records);
        self.save()
    }

    pub fn snapshot(&self) -> BackendResult<Value> {
        Ok(serde_json::to_value(self.lock_records()?.clone())?)
    }

    pub fn apply_snapshot(&self, snapshot: &Value, replace: bool) -> BackendResult<()> {
        let raw = serde_json::to_string(snapshot)?;
        let root = self.root()?;
        let (incoming, _) = load_records(&raw, &root).map_err(BackendError::Config)?;
        let mut records = self.lock_records()?;
        if replace {
            *records = incoming;
        } else {
            for item in incoming {
                if let Some(existing) = records.iter_mut().find(|value| value.id == item.id) {
                    if item.updated_at >= existing.updated_at {
                        *existing = item;
                    }
                } else {
                    records.push(item);
                }
            }
        }
        drop(records);
        self.save()
    }

    fn lock_records(&self) -> BackendResult<std::sync::MutexGuard<'_, Vec<DownloadAlbumRecord>>> {
        self.records
            .lock()
            .map_err(|_| BackendError::Config("download index lock poisoned".into()))
    }

    fn save(&self) -> BackendResult<()> {
        let _save_guard = self
            .save_lock
            .lock()
            .map_err(|_| BackendError::Config("download index save lock poisoned".into()))?;
        let records = self.lock_records()?.clone();
        let backup_pending = *self
            .legacy_backup_pending
            .lock()
            .map_err(|_| BackendError::Config("download migration lock poisoned".into()))?;
        if backup_pending && self.index_path.exists() {
            let backup_path = self.index_path.with_extension("pre-v2.json");
            if !backup_path.exists() {
                fs::copy(&self.index_path, &backup_path)?;
            }
        }
        let temporary = self.index_path.with_extension("json.tmp");
        fs::write(&temporary, serde_json::to_vec_pretty(&records)?)?;
        if let Err(error) = replace_file(&temporary, &self.index_path) {
            let _ = fs::remove_file(&temporary);
            return Err(error.into());
        }
        if backup_pending {
            *self
                .legacy_backup_pending
                .lock()
                .map_err(|_| BackendError::Config("download migration lock poisoned".into()))? =
                false;
        }
        Ok(())
    }
}

fn load_records(
    raw: &str,
    download_root: &Path,
) -> Result<(Vec<DownloadAlbumRecord>, bool), String> {
    let value: Value =
        serde_json::from_str(raw).map_err(|error| format!("invalid downloads.json: {error}"))?;
    let (items, top_level_legacy) = match value {
        Value::Array(items) => (items, false),
        Value::Object(mut object) => {
            if let Some(Value::Array(items)) = object.remove("albums") {
                (items, true)
            } else {
                let mut items = Vec::new();
                for (key, value) in object {
                    let Value::Object(mut item) = value else {
                        return Err(format!("unsupported downloads.json object entry `{key}`"));
                    };
                    if !item.values().any(|value| {
                        value.as_i64().is_some_and(|value| value > 0)
                            || value
                                .as_str()
                                .and_then(|value| value.parse::<i64>().ok())
                                .is_some_and(|value| value > 0)
                    }) {
                        item.insert("id".into(), Value::String(key));
                    }
                    items.push(Value::Object(item));
                }
                (items, true)
            }
        }
        _ => return Err("downloads.json must contain an array or album map".into()),
    };

    let mut legacy = top_level_legacy;
    let mut records = Vec::with_capacity(items.len());
    for (position, item) in items.into_iter().enumerate() {
        let object = item
            .as_object()
            .ok_or_else(|| format!("downloads.json item {} is not an object", position + 1))?;
        let id = value_i64(object, &["id", "aid", "album_id", "albumId"])
            .ok_or_else(|| format!("downloads.json item {} has no valid album id", position + 1))?;
        if id <= 0 {
            return Err(format!(
                "downloads.json item {} has a non-positive album id",
                position + 1
            ));
        }
        let name = value_string(object, &["name", "title"]).unwrap_or_default();
        let mut chapters = parse_chapters(object.get("chapters"));
        let directory_name = value_string(object, &["directory_name", "directoryName", "folder"])
            .filter(|value| !value.trim().is_empty())
            .or_else(|| find_album_directory(download_root, id))
            .unwrap_or_else(|| format!("{id}_{}", safe_component(&name)));
        validate_component(&directory_name)?;
        if chapters.is_empty() {
            chapters = scan_chapter_directories(&download_root.join(&directory_name));
        }
        let had_modern_shape =
            object.contains_key("chapters") && object.contains_key("directory_name");
        legacy |= !had_modern_shape;
        records.push(DownloadAlbumRecord {
            id,
            name,
            author: metadata_list(object.get("author")),
            tags: metadata_list(object.get("tags")),
            works: metadata_list(object.get("works")),
            description: value_string(object, &["description"]).unwrap_or_default(),
            chapters,
            directory_name,
            dl_square_cover_status: value_i64(
                object,
                &["dl_square_cover_status", "dlSquareCoverStatus"],
            )
            .unwrap_or(0),
            dl_3x4_cover_status: value_i64(object, &["dl_3x4_cover_status", "dl_3x4CoverStatus"])
                .unwrap_or(0),
            dl_status: value_i64(object, &["dl_status", "dlStatus"]).unwrap_or(0),
            image_count: value_i64(object, &["image_count", "imageCount"]).unwrap_or(0),
            dled_image_count: value_i64(object, &["dled_image_count", "dledImageCount"])
                .unwrap_or(0),
            updated_at: value_i64(object, &["updated_at", "updatedAt"]).unwrap_or(0),
        });
    }
    Ok((records, legacy))
}

fn parse_chapters(value: Option<&Value>) -> Vec<DownloadChapterRecord> {
    let Some(values) = value.and_then(Value::as_array) else {
        return Vec::new();
    };
    let mut chapters = Vec::with_capacity(values.len());
    for value in values {
        let Some(object) = value.as_object() else {
            continue;
        };
        let Some(id) = value_i64(object, &["id", "chapter_id", "chapterId", "cid"]) else {
            continue;
        };
        if id <= 0
            || chapters
                .iter()
                .any(|chapter: &DownloadChapterRecord| chapter.id == id)
        {
            continue;
        }
        chapters.push(DownloadChapterRecord {
            id,
            name: value_string(object, &["name", "title"]).unwrap_or_default(),
            sort: value_string(object, &["sort", "index"]).unwrap_or_else(|| id.to_string()),
        });
    }
    chapters
}

fn value_i64(object: &serde_json::Map<String, Value>, keys: &[&str]) -> Option<i64> {
    keys.iter().find_map(|key| {
        let value = object.get(*key)?;
        value.as_i64().or_else(|| {
            value
                .as_str()
                .map(str::trim)
                .and_then(|value| value.parse::<i64>().ok())
        })
    })
}

fn value_string(object: &serde_json::Map<String, Value>, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| {
        let value = object.get(*key)?;
        if let Some(value) = value.as_str() {
            return Some(value.to_string());
        }
        if value.is_number() || value.is_boolean() {
            return Some(value.to_string());
        }
        None
    })
}

fn metadata_list(value: Option<&Value>) -> Vec<String> {
    fn append(value: &Value, depth: usize, output: &mut Vec<String>) {
        if depth > 4 {
            return;
        }
        match value {
            Value::Array(values) => {
                for value in values {
                    append(value, depth + 1, output);
                }
            }
            Value::String(value) => {
                let trimmed = value.trim();
                if trimmed.is_empty() {
                    return;
                }
                if let Ok(nested) = serde_json::from_str::<Value>(trimmed) {
                    if !matches!(nested, Value::String(_) if nested.as_str() == Some(trimmed)) {
                        append(&nested, depth + 1, output);
                        return;
                    }
                }
                output.push(trimmed.to_string());
            }
            Value::Number(_) | Value::Bool(_) => output.push(value.to_string()),
            Value::Null | Value::Object(_) => {}
        }
    }

    let mut output = Vec::new();
    if let Some(value) = value {
        append(value, 0, &mut output);
    }
    output
}

fn find_album_directory(root: &Path, album_id: i64) -> Option<String> {
    let mut candidates = fs::read_dir(root)
        .ok()?
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_ok_and(|kind| kind.is_dir()))
        .filter_map(|entry| entry.file_name().into_string().ok())
        .filter(|name| {
            name == album_id.to_string().as_str()
                || name.starts_with(&format!("{album_id}_"))
                || name.starts_with(&format!("{album_id}-"))
                || name.starts_with(&format!("album_{album_id}"))
                || name
                    .split(['_', '-'])
                    .any(|part| part == album_id.to_string())
        })
        .collect::<Vec<_>>();
    candidates.sort();
    candidates.into_iter().next()
}

fn scan_chapter_directories(album_root: &Path) -> Vec<DownloadChapterRecord> {
    let Ok(entries) = fs::read_dir(album_root) else {
        return Vec::new();
    };
    let mut chapters = entries
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_ok_and(|kind| kind.is_dir()))
        .enumerate()
        .filter_map(|(index, entry)| {
            let name = entry.file_name().into_string().ok()?;
            chapter_from_directory(&name, index + 1)
        })
        .collect::<Vec<_>>();
    chapters
        .sort_by(|left, right| compare_sort(&left.sort, &right.sort).then(left.id.cmp(&right.id)));
    chapters.dedup_by_key(|chapter| chapter.id);
    chapters
}

fn chapter_from_directory(directory: &str, fallback_sort: usize) -> Option<DownloadChapterRecord> {
    let parts = directory
        .split('_')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>();
    if parts.is_empty() {
        return None;
    }
    let id_position = parts
        .iter()
        .enumerate()
        .filter_map(|(position, part)| {
            part.parse::<i64>()
                .ok()
                .filter(|value| *value > 0)
                .map(|value| (position, value))
        })
        .max_by_key(|(_, value)| *value)?;
    let id = id_position.1;
    let sort = parts
        .first()
        .and_then(|part| part.parse::<i64>().ok())
        .filter(|value| *value > 0 && *value != id)
        .map(|value| value.to_string())
        .unwrap_or_else(|| fallback_sort.to_string());
    let name = parts
        .iter()
        .enumerate()
        .filter(|(position, part)| {
            *position != id_position.0
                && !(*position == 0 && part.parse::<i64>().ok() == sort.parse::<i64>().ok())
        })
        .map(|(_, part)| *part)
        .collect::<Vec<_>>()
        .join("_");
    Some(DownloadChapterRecord {
        id,
        name: if name.trim().is_empty() {
            format!("chapter {sort}")
        } else {
            name
        },
        sort,
    })
}

fn compare_sort(left: &str, right: &str) -> std::cmp::Ordering {
    match (left.parse::<f64>(), right.parse::<f64>()) {
        (Ok(left), Ok(right)) => left
            .partial_cmp(&right)
            .unwrap_or(std::cmp::Ordering::Equal),
        _ => left.cmp(right),
    }
}

fn validate_component(value: &str) -> Result<(), String> {
    let path = Path::new(value);
    let mut components = path.components();
    if value.contains('\0')
        || !matches!(components.next(), Some(Component::Normal(_)))
        || components.next().is_some()
    {
        return Err(format!(
            "download directory name is not a single safe path component: {value:?}"
        ));
    }
    Ok(())
}

fn replace_file(temporary: &Path, destination: &Path) -> io::Result<()> {
    match fs::rename(temporary, destination) {
        Ok(()) => Ok(()),
        Err(first_error) => {
            if !destination.exists() {
                return Err(first_error);
            }
            #[cfg(windows)]
            {
                let previous = destination.with_extension("json.pre-replace");
                if previous.exists() {
                    fs::remove_file(&previous)?;
                }
                fs::rename(destination, &previous)?;
                match fs::rename(temporary, destination) {
                    Ok(()) => {
                        let _ = fs::remove_file(previous);
                        Ok(())
                    }
                    Err(error) => {
                        let _ = fs::rename(previous, destination);
                        Err(error)
                    }
                }
            }
            #[cfg(not(windows))]
            {
                Err(first_error)
            }
        }
    }
}

pub fn chapter_dir(
    root: &Path,
    album: &DownloadAlbumRecord,
    chapter: &DownloadChapterRecord,
) -> PathBuf {
    root.join(&album.directory_name).join(format!(
        "{}_{}_{}",
        safe_component(&chapter.sort),
        chapter.id,
        safe_component(&chapter.name)
    ))
}

pub fn album_dir(root: &Path, album: &DownloadAlbumRecord) -> PathBuf {
    root.join(&album.directory_name)
}

fn record_to_download_album(record: &DownloadAlbumRecord) -> Value {
    json!({
        "id": record.id,
        "name": record.name,
        "author": record.author,
        "tags": record.tags,
        "works": record.works,
        "description": record.description,
        "dl_square_cover_status": record.dl_square_cover_status,
        "dl_3x4_cover_status": record.dl_3x4_cover_status,
        "dl_status": record.dl_status,
        "image_count": record.image_count,
        "dled_image_count": record.dled_image_count,
        "updated_at": record.updated_at,
    })
}

fn string(value: Option<&Value>) -> String {
    value
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn string_list(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

fn safe_component(value: &str) -> String {
    let cleaned: String = value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric()
                || character == '-'
                || character == '_'
                || character == '.'
            {
                character
            } else {
                '_'
            }
        })
        .collect();
    let trimmed = cleaned.trim_matches(['.', '_']);
    if trimmed.is_empty() {
        "item".into()
    } else {
        trimmed.chars().take(80).collect()
    }
}

fn unix_timestamp() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs() as i64)
        .unwrap_or(0)
}

pub fn manager_shared(
    app_data_root: &Path,
    download_root: PathBuf,
) -> BackendResult<Arc<DownloadManager>> {
    Ok(Arc::new(DownloadManager::open(
        app_data_root,
        download_root,
    )?))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_root(name: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!(
            "jmcomic3-backend-v2-{name}-{}-{}",
            std::process::id(),
            unix_timestamp()
        ));
        let _ = fs::remove_dir_all(&root);
        root
    }

    #[test]
    fn download_index_round_trip_and_image_scan() {
        let root = test_root("download");
        let app_data = root.join("app");
        let files = root.join("files");
        let manager = DownloadManager::open(&app_data, files.clone()).unwrap();
        let record = manager
            .create(&json!({
                "album": {
                    "id": 10,
                    "name": "fixture",
                    "author": ["a"],
                    "tags": [],
                    "works": [],
                    "description": "",
                },
                "chapters": [{"id": 11, "name": "chapter", "sort": "1"}],
            }))
            .unwrap();
        let dir = chapter_dir(&files, &record, &record.chapters[0]);
        fs::write(dir.join("001.jpg"), b"fixture").unwrap();
        manager.set_progress(10, 1, 1, 1).unwrap();
        assert_eq!(manager.all_json().unwrap().as_array().unwrap().len(), 1);
        assert_eq!(
            manager
                .chapter_images_json(11, true)
                .unwrap()
                .as_array()
                .unwrap()
                .len(),
            1
        );
        let snapshot = manager.snapshot().unwrap();
        let mirrored =
            DownloadManager::open(&root.join("mirror-app"), root.join("mirror-files")).unwrap();
        mirrored.apply_snapshot(&snapshot, false).unwrap();
        assert_eq!(mirrored.get(10).unwrap().unwrap().chapters[0].id, 11);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn renew_all_never_marks_a_partial_download_complete() {
        let root = test_root("renew-partial");
        let app_data = root.join("app");
        let files = root.join("files");
        let manager = DownloadManager::open(&app_data, files.clone()).unwrap();
        let record = manager
            .create(&json!({
                "album": {
                    "id": 20,
                    "name": "partial",
                    "author": [],
                    "tags": [],
                    "works": [],
                    "description": "",
                },
                "chapters": [{"id": 21, "name": "chapter", "sort": "1"}],
            }))
            .unwrap();
        let dir = chapter_dir(&files, &record, &record.chapters[0]);
        fs::write(dir.join("001.jpg"), b"fixture").unwrap();
        manager.set_progress(20, 4, 1, 0).unwrap();

        manager.renew_all().unwrap();
        let refreshed = manager.get(20).unwrap().unwrap();
        assert_eq!(refreshed.dl_status, 2);
        assert_eq!(refreshed.image_count, 4);
        assert_eq!(refreshed.dled_image_count, 1);

        for name in ["002.jpg", "003.jpg", "004.jpg"] {
            fs::write(dir.join(name), b"fixture").unwrap();
        }
        manager.set_progress(20, 4, 4, 1).unwrap();
        manager.renew_all().unwrap();
        let completed = manager.get(20).unwrap().unwrap();
        assert_eq!(completed.dl_status, 1);
        assert_eq!(completed.image_count, 4);
        assert_eq!(completed.dled_image_count, 4);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn paused_download_keeps_state_across_progress_updates_and_renew() {
        let root = test_root("download-pause");
        let app_data = root.join("app");
        let files = root.join("files");
        let manager = DownloadManager::open(&app_data, files.clone()).unwrap();
        let record = manager
            .create(&json!({
                "album": {
                    "id": 30,
                    "name": "paused",
                    "author": [],
                    "tags": [],
                    "works": [],
                    "description": "",
                },
                "chapters": [{"id": 31, "name": "chapter", "sort": "1"}],
            }))
            .unwrap();
        let dir = chapter_dir(&files, &record, &record.chapters[0]);
        fs::write(dir.join("001.jpg"), b"fixture").unwrap();
        let control = manager.new_task(30).unwrap();
        manager.pause_task(30).unwrap();
        assert!(control.is_paused());

        manager.set_progress(30, 4, 1, 0).unwrap();
        manager.renew_all().unwrap();
        let paused = manager.get(30).unwrap().unwrap();
        assert_eq!(paused.dl_status, 4);
        assert_eq!(paused.dled_image_count, 1);

        assert!(manager.resume_running_task(30).unwrap().is_some());
        assert!(!control.is_paused());
        assert_eq!(manager.get(30).unwrap().unwrap().dl_status, 0);
        manager.finish_task(30, &control);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn renew_all_keeps_an_active_download_in_progress() {
        let root = test_root("download-active-renew");
        let app_data = root.join("app");
        let files = root.join("files");
        let manager = DownloadManager::open(&app_data, files.clone()).unwrap();
        let record = manager
            .create(&json!({
                "album": {
                    "id": 35,
                    "name": "active",
                    "author": [],
                    "tags": [],
                    "works": [],
                    "description": "",
                },
                "chapters": [{"id": 36, "name": "chapter", "sort": "1"}],
            }))
            .unwrap();
        let dir = chapter_dir(&files, &record, &record.chapters[0]);
        fs::write(dir.join("001.jpg"), b"fixture").unwrap();
        let control = manager.new_task(35).unwrap();
        manager.set_progress(35, 4, 1, 0).unwrap();

        manager.renew_all().unwrap();
        let refreshed = manager.get(35).unwrap().unwrap();
        assert_eq!(refreshed.dl_status, 0);
        assert_eq!(refreshed.image_count, 4);
        assert_eq!(refreshed.dled_image_count, 1);
        manager.finish_task(35, &control);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn renew_all_rejects_a_false_completed_state_with_empty_chapters() {
        let root = test_root("renew-false-complete");
        let app_data = root.join("app");
        let files = root.join("files");
        let manager = DownloadManager::open(&app_data, files.clone()).unwrap();
        let record = manager
            .create(&json!({
                "album": {
                    "id": 40,
                    "name": "interrupted",
                    "author": [],
                    "tags": [],
                    "works": [],
                    "description": "",
                },
                "chapters": [
                    {"id": 41, "name": "chapter one", "sort": "1"},
                    {"id": 42, "name": "chapter two", "sort": "2"}
                ],
            }))
            .unwrap();
        let dir = chapter_dir(&files, &record, &record.chapters[0]);
        fs::write(dir.join("001.jpg"), b"fixture").unwrap();
        manager.set_progress(40, 1, 1, 1).unwrap();

        manager.renew_all().unwrap();
        let refreshed = manager.get(40).unwrap().unwrap();
        assert_eq!(refreshed.dl_status, 2);
        assert_eq!(refreshed.image_count, 1);
        assert_eq!(refreshed.dled_image_count, 1);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn legacy_download_index_is_migrated_with_backup() {
        let root = test_root("legacy-download");
        let app_data = root.join("app");
        let files = root.join("files");
        let chapter_dir = files.join("77_legacy").join("2_9002_episode_two");
        fs::create_dir_all(&chapter_dir).unwrap();
        fs::write(chapter_dir.join("00001.png"), b"fixture").unwrap();
        fs::create_dir_all(&app_data).unwrap();
        let original = r#"[
          {
            "id": 77,
            "name": "legacy",
            "author": "[\"alice\"]",
            "tags": "tag",
            "works": ["series"],
            "description": "old download",
            "dl_square_cover_status": 1,
            "dl_3x4_cover_status": 1,
            "dl_status": 0,
            "image_count": 1,
            "dled_image_count": 1
          }
        ]"#;
        fs::write(app_data.join("downloads.json"), original).unwrap();

        let manager = DownloadManager::open(&app_data, files).unwrap();
        let record = manager.get(77).unwrap().unwrap();
        assert_eq!(record.directory_name, "77_legacy");
        assert_eq!(record.author, ["alice"]);
        assert_eq!(record.chapters.len(), 1);
        assert_eq!(record.chapters[0].id, 9002);
        assert_eq!(record.chapters[0].sort, "2");
        assert_eq!(record.chapters[0].name, "episode_two");

        manager.set_progress(77, 1, 1, 1).unwrap();
        let backup = app_data.join("downloads.pre-v2.json");
        assert_eq!(fs::read_to_string(backup).unwrap(), original);
        let reopened = DownloadManager::open(&app_data, manager.root().unwrap()).unwrap();
        assert_eq!(reopened.get(77).unwrap().unwrap().dl_status, 1);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn invalid_legacy_download_index_is_never_overwritten() {
        let root = test_root("invalid-download");
        let app_data = root.join("app");
        let files = root.join("files");
        fs::create_dir_all(&app_data).unwrap();
        fs::create_dir_all(&files).unwrap();
        let original = r#"[{"name":"missing album id"}]"#;
        let index = app_data.join("downloads.json");
        fs::write(&index, original).unwrap();

        let error = match DownloadManager::open(&app_data, files) {
            Ok(_) => panic!("invalid download index unexpectedly opened"),
            Err(error) => error,
        };
        assert!(error.to_string().contains("no valid album id"));
        assert_eq!(fs::read_to_string(index).unwrap(), original);
        fs::remove_dir_all(root).unwrap();
    }
}
