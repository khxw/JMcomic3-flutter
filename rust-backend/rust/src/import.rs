use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

use flate2::read::DeflateDecoder;
use serde_json::{json, Value};

use crate::download::{album_dir, chapter_dir, DownloadChapterRecord, DownloadManager};
use crate::error::{BackendError, BackendResult};

pub fn import_album_archive(manager: &DownloadManager, path: &Path) -> BackendResult<i64> {
    let mut archive = ZipArchive::open(path)?;
    let manifest_entry = archive
        .entries()
        .iter()
        .find(|entry| {
            entry
                .name
                .rsplit('/')
                .next()
                .is_some_and(|name| name == "jmcomic3_manifest.json")
        })
        .cloned()
        .ok_or_else(|| {
            BackendError::Config(format!(
                "{} does not contain jmcomic3_manifest.json",
                path.display()
            ))
        })?;
    let manifest: Value = serde_json::from_slice(&archive.read(&manifest_entry)?)?;
    let album = manifest
        .get("album")
        .and_then(Value::as_object)
        .ok_or_else(|| BackendError::Config("import manifest has no album".into()))?;
    let album_id = value_i64(album.get("id"))
        .filter(|id| *id > 0)
        .ok_or_else(|| BackendError::Config("import manifest has no valid album id".into()))?;
    let album_name = value_string(album.get("name")).unwrap_or_else(|| album_id.to_string());
    let chapters = manifest
        .get("chapters")
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(|value| import_chapter(&mut archive, value, album_id))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    if chapters.is_empty() || chapters.iter().any(|chapter| chapter.images.is_empty()) {
        return Err(BackendError::Config(
            "import manifest has no readable chapters".into(),
        ));
    }

    let create = json!({
        "album": {
            "id": album_id,
            "name": album_name,
            "author": string_list(album.get("author")),
            "tags": string_list(album.get("tags")),
            "works": string_list(album.get("works")),
            "description": value_string(album.get("description")).unwrap_or_default(),
        },
        "chapters": chapters.iter().map(|chapter| json!({
            "id": chapter.record.id,
            "name": chapter.record.name,
            "sort": chapter.record.sort,
        })).collect::<Vec<_>>(),
    });
    let record = manager.create(&create)?;
    let result = (|| -> BackendResult<()> {
        let root = manager.root()?;
        let mut total = 0_i64;
        for chapter in &chapters {
            let target = chapter_dir(&root, &record, &chapter.record);
            fs::create_dir_all(&target)?;
            for image_name in &chapter.images {
                let entry = archive
                    .entries()
                    .iter()
                    .find(|entry| entry.name == *image_name)
                    .cloned()
                    .ok_or_else(|| {
                        BackendError::Config(format!("archive entry is missing: {image_name}"))
                    })?;
                let file_name = safe_file_name(&entry.name)?;
                let bytes = archive.read(&entry)?;
                fs::write(target.join(file_name), bytes)?;
                total += 1;
            }
        }
        if let Some(cover) = archive
            .entries()
            .iter()
            .find(|entry| {
                entry
                    .name
                    .rsplit('/')
                    .next()
                    .is_some_and(|name| name.to_ascii_lowercase().starts_with("cover."))
            })
            .cloned()
        {
            let target = album_dir(&root, &record);
            fs::create_dir_all(&target)?;
            let bytes = archive.read(&cover)?;
            fs::write(target.join(safe_file_name(&cover.name)?), bytes)?;
            let _ = manager.mark_covers_done(record.id);
        }
        manager.set_progress(record.id, total, total, 1)
    })();
    if let Err(error) = result {
        let _ = manager.mark_failed(record.id);
        return Err(error);
    }
    Ok(record.id)
}

pub fn import_album_directory(manager: &DownloadManager, directory: &Path) -> BackendResult<usize> {
    if !directory.is_dir() {
        return Err(BackendError::Config(format!(
            "import path is not a directory: {}",
            directory.display()
        )));
    }
    let mut archives = fs::read_dir(directory)?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            let name = path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .to_ascii_lowercase();
            path.is_file() && (name.ends_with(".jm.zip") || name.ends_with(".jmi"))
        })
        .collect::<Vec<_>>();
    archives.sort();
    if archives.is_empty() {
        return Err(BackendError::Config(
            "directory contains no .jm.zip or .jmi files".into(),
        ));
    }
    for archive in &archives {
        import_album_archive(manager, archive)?;
    }
    Ok(archives.len())
}

struct ImportChapter {
    record: DownloadChapterRecord,
    images: Vec<String>,
}

fn import_chapter(archive: &mut ZipArchive, value: &Value, album_id: i64) -> Option<ImportChapter> {
    let object = value.as_object()?;
    let id = value_i64(object.get("id"))
        .or_else(|| value_i64(object.get("chapter_id")))
        .filter(|id| *id > 0)?;
    let name = value_string(object.get("name")).unwrap_or_else(|| format!("chapter {id}"));
    let sort = value_string(object.get("sort")).unwrap_or_else(|| id.to_string());
    let directory = value_string(object.get("directory_name"))
        .or_else(|| value_string(object.get("directory")))
        .unwrap_or_else(|| chapter_folder(&sort, id, &name));
    let mut images: Vec<String> = object
        .get("images")
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default();
    if images.is_empty() {
        let prefix = directory.replace('\\', "/");
        images = archive
            .entries()
            .iter()
            .filter(|entry| entry.name.starts_with(&format!("{prefix}/")))
            .filter(|entry| is_image_name(&entry.name))
            .map(|entry| entry.name.clone())
            .collect();
    }
    images.sort();
    if name.trim().is_empty() && album_id <= 0 {
        return None;
    }
    Some(ImportChapter {
        record: DownloadChapterRecord { id, name, sort },
        images,
    })
}

#[derive(Clone)]
struct ZipEntry {
    name: String,
    method: u16,
    crc: u32,
    compressed_size: usize,
    uncompressed_size: usize,
    local_offset: u64,
}

struct ZipArchive {
    path: PathBuf,
    entries: Vec<ZipEntry>,
}

impl ZipArchive {
    fn open(path: &Path) -> BackendResult<Self> {
        let mut file = File::open(path)?;
        let length = file.metadata()?.len();
        if length < 22 {
            return Err(BackendError::Config("ZIP archive is too small".into()));
        }
        let tail_length = length.min(65_557);
        file.seek(SeekFrom::Start(length - tail_length))?;
        let mut tail = vec![0_u8; tail_length as usize];
        file.read_exact(&mut tail)?;
        let eocd_position = tail
            .windows(4)
            .rposition(|window| window == [0x50, 0x4b, 0x05, 0x06])
            .ok_or_else(|| BackendError::Config("ZIP end record not found".into()))?;
        let eocd = &tail[eocd_position..];
        if eocd.len() < 22 {
            return Err(BackendError::Config("invalid ZIP end record".into()));
        }
        let entries_count = read_u16(eocd, 10)? as usize;
        let central_size = read_u32(eocd, 12)? as usize;
        let central_offset = read_u32(eocd, 16)? as u64;
        if central_offset.saturating_add(central_size as u64) > length {
            return Err(BackendError::Config(
                "ZIP central directory is out of range".into(),
            ));
        }
        file.seek(SeekFrom::Start(central_offset))?;
        let mut central = vec![0_u8; central_size];
        file.read_exact(&mut central)?;
        let mut entries = Vec::with_capacity(entries_count);
        let mut position = 0_usize;
        while position + 46 <= central.len() {
            if &central[position..position + 4] != [0x50, 0x4b, 0x01, 0x02] {
                break;
            }
            let method = read_u16(&central, position + 10)?;
            let crc = read_u32(&central, position + 16)?;
            let compressed_size = read_u32(&central, position + 20)? as usize;
            let uncompressed_size = read_u32(&central, position + 24)? as usize;
            let name_length = read_u16(&central, position + 28)? as usize;
            let extra_length = read_u16(&central, position + 30)? as usize;
            let comment_length = read_u16(&central, position + 32)? as usize;
            let local_offset = read_u32(&central, position + 42)? as u64;
            let name_start = position + 46;
            let name_end = name_start.saturating_add(name_length);
            if name_end > central.len() {
                return Err(BackendError::Config("invalid ZIP entry name".into()));
            }
            let name = String::from_utf8_lossy(&central[name_start..name_end]).into_owned();
            if !name.ends_with('/') {
                entries.push(ZipEntry {
                    name,
                    method,
                    crc,
                    compressed_size,
                    uncompressed_size,
                    local_offset,
                });
            }
            position = name_end
                .saturating_add(extra_length)
                .saturating_add(comment_length);
        }
        Ok(Self {
            path: path.to_path_buf(),
            entries,
        })
    }

    fn entries(&self) -> &[ZipEntry] {
        &self.entries
    }

    fn read(&mut self, entry: &ZipEntry) -> BackendResult<Vec<u8>> {
        let mut file = File::open(&self.path)?;
        file.seek(SeekFrom::Start(entry.local_offset))?;
        let mut local = [0_u8; 30];
        file.read_exact(&mut local)?;
        if &local[..4] != [0x50, 0x4b, 0x03, 0x04] {
            return Err(BackendError::Config("invalid ZIP local header".into()));
        }
        let name_length = read_u16(&local, 26)? as u64;
        let extra_length = read_u16(&local, 28)? as u64;
        file.seek(SeekFrom::Current((name_length + extra_length) as i64))?;
        let mut compressed = vec![0_u8; entry.compressed_size];
        file.read_exact(&mut compressed)?;
        let output = match entry.method {
            0 => compressed,
            8 => {
                let mut decoder = DeflateDecoder::new(compressed.as_slice());
                let mut output = Vec::with_capacity(entry.uncompressed_size);
                decoder.read_to_end(&mut output)?;
                output
            }
            method => {
                return Err(BackendError::Config(format!(
                    "unsupported ZIP compression method: {method}"
                )));
            }
        };
        if output.len() != entry.uncompressed_size {
            return Err(BackendError::Config(
                "ZIP entry size verification failed".into(),
            ));
        }
        if crc32(&output) != entry.crc {
            return Err(BackendError::Config(
                "ZIP entry CRC verification failed".into(),
            ));
        }
        Ok(output)
    }
}

fn read_u16(bytes: &[u8], offset: usize) -> Result<u16, BackendError> {
    let value = bytes
        .get(offset..offset + 2)
        .ok_or_else(|| BackendError::Config("truncated ZIP metadata".into()))?;
    Ok(u16::from_le_bytes([value[0], value[1]]))
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32, BackendError> {
    let value = bytes
        .get(offset..offset + 4)
        .ok_or_else(|| BackendError::Config("truncated ZIP metadata".into()))?;
    Ok(u32::from_le_bytes([value[0], value[1], value[2], value[3]]))
}

fn value_i64(value: Option<&Value>) -> Option<i64> {
    let value = value?;
    value
        .as_i64()
        .or_else(|| value.as_str()?.trim().parse::<i64>().ok())
}

fn value_string(value: Option<&Value>) -> Option<String> {
    value.and_then(Value::as_str).map(str::to_string)
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

fn safe_file_name(entry: &str) -> BackendResult<String> {
    let name = entry.rsplit('/').next().unwrap_or_default().trim();
    if name.is_empty() || name == "." || name == ".." || name.contains(['/', '\\', '\0']) {
        return Err(BackendError::Config(format!(
            "unsafe archive image path: {entry}"
        )));
    }
    Ok(name.to_string())
}

fn is_image_name(name: &str) -> bool {
    Path::new(name)
        .extension()
        .and_then(|value| value.to_str())
        .map(str::to_ascii_lowercase)
        .is_some_and(|value| {
            matches!(
                value.as_str(),
                "jpg" | "jpeg" | "png" | "gif" | "webp" | "bmp" | "avif"
            )
        })
}

fn chapter_folder(sort: &str, id: i64, name: &str) -> String {
    format!(
        "{}_{}_{}",
        sanitize_component(sort),
        id,
        sanitize_component(name)
    )
}

fn sanitize_component(value: &str) -> String {
    let cleaned = value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.') {
                character
            } else {
                '_'
            }
        })
        .collect::<String>();
    let cleaned = cleaned.trim_matches(['.', '_']);
    if cleaned.is_empty() {
        "item".into()
    } else {
        cleaned.chars().take(80).collect()
    }
}

fn crc32(bytes: &[u8]) -> u32 {
    let mut crc = u32::MAX;
    for byte in bytes {
        crc ^= u32::from(*byte);
        for _ in 0..8 {
            let mask = 0u32.wrapping_sub(crc & 1);
            crc = (crc >> 1) ^ (0xedb8_8320 & mask);
        }
    }
    !crc
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::export::{export_album, ExportFormat};

    #[test]
    fn exported_archive_round_trips_through_import() {
        let root =
            std::env::temp_dir().join(format!("jmcomic3-backend-v2-import-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let source =
            DownloadManager::open(&root.join("source-app"), root.join("source-files")).unwrap();
        let record = source
            .create(&json!({
                "album": {
                    "id": 501,
                    "name": "round trip",
                    "author": ["alice"],
                    "tags": ["tag"],
                    "works": [],
                    "description": "fixture",
                },
                "chapters": [{"id": 502, "name": "episode", "sort": "2"}],
            }))
            .unwrap();
        let source_files = chapter_dir(&source.root().unwrap(), &record, &record.chapters[0]);
        fs::create_dir_all(&source_files).unwrap();
        fs::write(source_files.join("00001.jpg"), b"first").unwrap();
        fs::write(source_files.join("00002.jpg"), b"second").unwrap();
        let target = root.join("export");
        let archive =
            export_album(&source, 501, &target, None, ExportFormat::JmZip, false).unwrap();

        let destination =
            DownloadManager::open(&root.join("target-app"), root.join("target-files")).unwrap();
        assert_eq!(import_album_archive(&destination, &archive).unwrap(), 501);
        let imported = destination.get(501).unwrap().unwrap();
        assert_eq!(imported.dl_status, 1);
        assert_eq!(imported.dled_image_count, 2);
        let imported_files = chapter_dir(
            &destination.root().unwrap(),
            &imported,
            &imported.chapters[0],
        );
        assert_eq!(fs::read_dir(imported_files).unwrap().count(), 2);
        fs::remove_dir_all(root).unwrap();
    }
}
