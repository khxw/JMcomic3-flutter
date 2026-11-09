use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};

use image::{ImageFormat, RgbImage};
use tokio::sync::{Mutex as AsyncMutex, OnceCell};

use crate::client::JmClient;
use crate::crypto::md5_hex;
use crate::error::{BackendError, BackendResult};

const COVER_CACHE_MAX_BYTES: u64 = 48 * 1024 * 1024;
const COVER_CACHE_MAX_AGE: Duration = Duration::from_secs(30 * 24 * 60 * 60);
const COVER_PRUNE_INTERVAL: usize = 64;
const SCRAMBLE_ID_CACHE_MAX_ENTRIES: usize = 512;
const IMAGE_SIZE_CACHE_MAX_ENTRIES: usize = 2048;

#[derive(Clone, Copy)]
struct CachedImageSize {
    length: u64,
    modified: Option<SystemTime>,
    width: u32,
    height: u32,
}

pub struct MediaCache {
    root: PathBuf,
    covers: PathBuf,
    chapters: PathBuf,
    photos: PathBuf,
    cover_writes: AtomicUsize,
    fetch_locks: Mutex<HashMap<String, Arc<AsyncMutex<()>>>>,
    scramble_ids: Mutex<HashMap<i64, Arc<OnceCell<i64>>>>,
    image_sizes: Mutex<HashMap<String, CachedImageSize>>,
}

impl MediaCache {
    pub fn open(root: &Path) -> BackendResult<Self> {
        let covers = root.join("covers");
        let chapters = root.join("pages");
        let photos = root.join("photos");
        fs::create_dir_all(&covers)?;
        fs::create_dir_all(&chapters)?;
        fs::create_dir_all(&photos)?;
        Ok(Self {
            root: root.to_path_buf(),
            covers,
            chapters,
            photos,
            cover_writes: AtomicUsize::new(0),
            fetch_locks: Mutex::new(HashMap::new()),
            scramble_ids: Mutex::new(HashMap::new()),
            image_sizes: Mutex::new(HashMap::new()),
        })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn schedule_cover_prune(&self) {
        let covers = self.covers.clone();
        drop(
            std::thread::Builder::new()
                .name("cover-cache-prune".into())
                .spawn(move || {
                    let _ = prune_cover_cache(&covers, COVER_CACHE_MAX_BYTES, COVER_CACHE_MAX_AGE);
                }),
        );
    }

    pub async fn page_image(
        &self,
        client: &JmClient,
        chapter_id: i64,
        image_name: &str,
    ) -> BackendResult<String> {
        if chapter_id <= 0 || image_name.trim().is_empty() {
            return Err(BackendError::Config(
                "chapter id and image name must be valid".into(),
            ));
        }
        let safe_name = safe_component(image_name);
        if let Some(path) = self.cached_page_path(chapter_id, &safe_name) {
            return Ok(path);
        }
        let lock_key = format!("page:{chapter_id}:{safe_name}");
        let lock = self.fetch_lock(&lock_key)?;
        let guard = lock.lock().await;
        let result = self
            .page_image_uncached(client, chapter_id, image_name, &safe_name)
            .await;
        drop(guard);
        self.release_fetch_lock(&lock_key, &lock);
        result
    }

    async fn page_image_uncached(
        &self,
        client: &JmClient,
        chapter_id: i64,
        image_name: &str,
        safe_name: &str,
    ) -> BackendResult<String> {
        if let Some(path) = self.cached_page_path(chapter_id, safe_name) {
            return Ok(path);
        }
        let extension = extension_for_name(safe_name);
        let chapter_dir = self.chapters.join(chapter_id.to_string());
        fs::create_dir_all(&chapter_dir)?;
        let stem = Path::new(&safe_name)
            .file_stem()
            .and_then(|value| value.to_str())
            .unwrap_or("image");

        if extension == "gif" {
            let target = chapter_dir.join(format!("{stem}.gif"));
            if is_nonempty_file(&target) {
                return Ok(path_string(&target));
            }
            let bytes = client.page_image_bytes(chapter_id, image_name).await?;
            write_atomic(&target, &bytes)?;
            return Ok(path_string(&target));
        }

        let (scramble_id, bytes) = tokio::try_join!(
            self.scramble_id(client, chapter_id),
            client.page_image_bytes(chapter_id, image_name)
        )?;
        let block_num = calculate_block_num(scramble_id, chapter_id, stem);
        if block_num == 0 {
            let target = chapter_dir.join(safe_name);
            if is_nonempty_file(&target) {
                return Ok(path_string(&target));
            }
            write_atomic(&target, &bytes)?;
            return Ok(path_string(&target));
        }

        let target = chapter_dir.join(format!("{stem}.png"));
        if is_nonempty_file(&target) {
            return Ok(path_string(&target));
        }
        let decoded = decode_scrambled_image(bytes, block_num).await?;
        write_atomic(&target, &decoded)?;
        Ok(path_string(&target))
    }

    pub async fn cover_image(
        &self,
        client: &JmClient,
        album_id: i64,
        square: bool,
    ) -> BackendResult<String> {
        if album_id <= 0 {
            return Err(BackendError::Config("album id must be positive".into()));
        }
        let image_name = cover_image_name(album_id, square);
        let safe_name = safe_component(&image_name);
        let extension = extension_for_name(&safe_name);
        let suffix = if square { "square" } else { "3x4" };
        let target = self.covers.join(format!("{album_id}_{suffix}.{extension}"));
        if is_nonempty_file(&target) {
            return Ok(path_string(&target));
        }
        let lock_key = format!("cover:{album_id}:{suffix}");
        let lock = self.fetch_lock(&lock_key)?;
        let guard = lock.lock().await;
        let result = async {
            if is_nonempty_file(&target) {
                return Ok(path_string(&target));
            }
            let bytes = client.cover_image_bytes(&image_name).await?;
            write_atomic(&target, &bytes)?;
            let writes = self.cover_writes.fetch_add(1, Ordering::Relaxed) + 1;
            if writes.is_multiple_of(COVER_PRUNE_INTERVAL) {
                let covers = self.covers.clone();
                drop(tokio::task::spawn_blocking(move || {
                    prune_cover_cache(&covers, COVER_CACHE_MAX_BYTES, COVER_CACHE_MAX_AGE)
                }));
            }
            Ok(path_string(&target))
        }
        .await;
        drop(guard);
        self.release_fetch_lock(&lock_key, &lock);
        result
    }

    pub async fn photo_image(&self, client: &JmClient, image_name: &str) -> BackendResult<String> {
        if image_name.trim().is_empty() {
            return Err(BackendError::Config("photo image name is empty".into()));
        }
        let safe_name = safe_component(image_name);
        let target = self.photos.join(&safe_name);
        if is_nonempty_file(&target) {
            return Ok(path_string(&target));
        }
        let lock_key = format!("photo:{safe_name}");
        let lock = self.fetch_lock(&lock_key)?;
        let guard = lock.lock().await;
        let result = async {
            if is_nonempty_file(&target) {
                return Ok(path_string(&target));
            }
            let bytes = client.photo_image_bytes(image_name).await?;
            write_atomic(&target, &bytes)?;
            Ok(path_string(&target))
        }
        .await;
        drop(guard);
        self.release_fetch_lock(&lock_key, &lock);
        result
    }

    fn cached_page_path(&self, chapter_id: i64, safe_name: &str) -> Option<String> {
        let chapter_dir = self.chapters.join(chapter_id.to_string());
        let stem = Path::new(safe_name)
            .file_stem()
            .and_then(|value| value.to_str())
            .unwrap_or("image");
        let decoded = chapter_dir.join(format!("{stem}.png"));
        if is_nonempty_file(&decoded) {
            return Some(path_string(&decoded));
        }
        let original = chapter_dir.join(safe_name);
        if original != decoded && is_nonempty_file(&original) {
            return Some(path_string(&original));
        }
        None
    }

    fn fetch_lock(&self, key: &str) -> BackendResult<Arc<AsyncMutex<()>>> {
        let mut locks = self
            .fetch_locks
            .lock()
            .map_err(|_| BackendError::Config("media lock map poisoned".into()))?;
        Ok(locks
            .entry(key.to_string())
            .or_insert_with(|| Arc::new(AsyncMutex::new(())))
            .clone())
    }

    fn release_fetch_lock(&self, key: &str, lock: &Arc<AsyncMutex<()>>) {
        if Arc::strong_count(lock) != 2 {
            return;
        }
        let Ok(mut locks) = self.fetch_locks.lock() else {
            return;
        };
        if locks
            .get(key)
            .is_some_and(|current| Arc::ptr_eq(current, lock))
        {
            locks.remove(key);
        }
    }

    async fn scramble_id(&self, client: &JmClient, chapter_id: i64) -> BackendResult<i64> {
        let cell = {
            let mut cache = self
                .scramble_ids
                .lock()
                .map_err(|_| BackendError::Config("scramble cache poisoned".into()))?;
            if cache.len() >= SCRAMBLE_ID_CACHE_MAX_ENTRIES && !cache.contains_key(&chapter_id) {
                cache.clear();
            }
            cache
                .entry(chapter_id)
                .or_insert_with(|| Arc::new(OnceCell::new()))
                .clone()
        };
        let result = cell
            .get_or_try_init(|| async { client.scramble_id(chapter_id).await })
            .await
            .copied();
        if result.is_err() {
            if let Ok(mut cache) = self.scramble_ids.lock() {
                if cache
                    .get(&chapter_id)
                    .is_some_and(|current| Arc::ptr_eq(current, &cell))
                {
                    cache.remove(&chapter_id);
                }
            }
        }
        result
    }

    pub fn image_size(&self, path: &str) -> BackendResult<(u32, u32)> {
        if path.trim().is_empty() {
            return Err(BackendError::Config("image path is empty".into()));
        }
        let metadata = fs::metadata(path)?;
        let modified = metadata.modified().ok();
        {
            let cache = self
                .image_sizes
                .lock()
                .map_err(|_| BackendError::Config("image size cache poisoned".into()))?;
            if let Some(cached) = cache.get(path) {
                if cached.length == metadata.len() && cached.modified == modified {
                    return Ok((cached.width, cached.height));
                }
            }
        }
        let (width, height) = image::image_dimensions(path)
            .map_err(|error| BackendError::InvalidResponse(format!("image size: {error}")))?;
        let mut cache = self
            .image_sizes
            .lock()
            .map_err(|_| BackendError::Config("image size cache poisoned".into()))?;
        if cache.len() >= IMAGE_SIZE_CACHE_MAX_ENTRIES && !cache.contains_key(path) {
            cache.clear();
        }
        cache.insert(
            path.to_string(),
            CachedImageSize {
                length: metadata.len(),
                modified,
                width,
                height,
            },
        );
        Ok((width, height))
    }

    pub fn clear(&self) -> BackendResult<()> {
        for directory in [&self.covers, &self.chapters, &self.photos] {
            if directory.exists() {
                fs::remove_dir_all(directory)?;
            }
            fs::create_dir_all(directory)?;
        }
        self.fetch_locks
            .lock()
            .map_err(|_| BackendError::Config("media lock map poisoned".into()))?
            .clear();
        self.scramble_ids
            .lock()
            .map_err(|_| BackendError::Config("scramble cache poisoned".into()))?
            .clear();
        self.image_sizes
            .lock()
            .map_err(|_| BackendError::Config("image size cache poisoned".into()))?
            .clear();
        Ok(())
    }
}

fn cover_image_name(album_id: i64, square: bool) -> String {
    if square {
        format!("{album_id}.jpg")
    } else {
        format!("{album_id}_3x4.jpg")
    }
}

pub fn calculate_block_num(scramble_id: i64, chapter_id: i64, filename_stem: &str) -> u32 {
    if chapter_id < scramble_id {
        return 0;
    }
    if chapter_id < 268_850 {
        return 10;
    }
    let modulus = if chapter_id < 421_926 { 10 } else { 8 };
    let hash = md5_hex(&format!("{chapter_id}{filename_stem}"));
    let mut block_num = hash.chars().last().unwrap_or('0') as u32;
    block_num %= modulus;
    block_num * 2 + 2
}

async fn decode_scrambled_image(bytes: Vec<u8>, block_num: u32) -> BackendResult<Vec<u8>> {
    tokio::task::spawn_blocking(move || {
        let source = image::load_from_memory(&bytes)
            .map_err(|error| BackendError::InvalidResponse(format!("image decode: {error}")))?
            .to_rgb8();
        let stitched = stitch_image(&source, block_num);
        let mut output = Vec::new();
        stitched
            .write_to(&mut std::io::Cursor::new(&mut output), ImageFormat::Png)
            .map_err(|error| BackendError::InvalidResponse(format!("image encode: {error}")))?;
        Ok(output)
    })
    .await
    .map_err(|error| BackendError::InvalidResponse(format!("image worker: {error}")))?
}

pub fn stitch_image(source: &RgbImage, block_num: u32) -> RgbImage {
    if block_num <= 1 {
        return source.clone();
    }
    let (width, height) = source.dimensions();
    let row_bytes = width as usize * 3;
    let source_bytes = source.as_raw();
    let mut output = vec![0_u8; source_bytes.len()];
    let remainder_height = height % block_num;
    for index in 0..block_num {
        let mut block_height = height / block_num;
        let source_y_start = height - (block_height * (index + 1)) - remainder_height;
        let mut target_y_start = block_height * index;
        if index == 0 {
            block_height += remainder_height;
        } else {
            target_y_start += remainder_height;
        }
        for row in 0..block_height {
            let source_start = (source_y_start + row) as usize * row_bytes;
            let target_start = (target_y_start + row) as usize * row_bytes;
            output[target_start..target_start + row_bytes]
                .copy_from_slice(&source_bytes[source_start..source_start + row_bytes]);
        }
    }
    RgbImage::from_raw(width, height, output).expect("stitched RGB buffer must match dimensions")
}

fn is_nonempty_file(path: &Path) -> bool {
    fs::metadata(path)
        .map(|metadata| metadata.is_file() && metadata.len() > 0)
        .unwrap_or(false)
}

fn safe_component(value: &str) -> String {
    let cleaned: String = value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '.' | '-' | '_') {
                character
            } else {
                '_'
            }
        })
        .collect();
    if cleaned.trim_matches(['.', '_']).is_empty() {
        "image".into()
    } else {
        cleaned
    }
}

fn extension_for_name(name: &str) -> String {
    Path::new(name)
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("jpg")
        .to_ascii_lowercase()
}

fn write_atomic(path: &Path, bytes: &[u8]) -> BackendResult<()> {
    let parent = path
        .parent()
        .ok_or_else(|| BackendError::Config("image target has no parent".into()))?;
    fs::create_dir_all(parent)?;
    let temporary = parent.join(format!(
        ".{}.{}.tmp",
        path.file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("image"),
        std::process::id()
    ));
    fs::write(&temporary, bytes)?;
    if path.exists() {
        fs::remove_file(path)?;
    }
    fs::rename(temporary, path)?;
    Ok(())
}

fn prune_cover_cache(directory: &Path, max_bytes: u64, max_age: Duration) -> BackendResult<u64> {
    let now = SystemTime::now();
    let mut files = Vec::new();
    let mut total_bytes = 0_u64;
    for entry in fs::read_dir(directory)?.filter_map(Result::ok) {
        let path = entry.path();
        let metadata = match entry.metadata() {
            Ok(metadata) if metadata.is_file() => metadata,
            _ => continue,
        };
        let modified = metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH);
        let age = now.duration_since(modified).unwrap_or(Duration::ZERO);
        let file_name = entry.file_name().to_string_lossy().to_string();
        if file_name.starts_with('.') && file_name.ends_with(".tmp") {
            if age >= Duration::from_secs(24 * 60 * 60) {
                let _ = fs::remove_file(&path);
            }
            continue;
        }
        if age > max_age {
            let _ = fs::remove_file(&path);
            continue;
        }
        total_bytes = total_bytes.saturating_add(metadata.len());
        files.push((modified, path, metadata.len()));
    }
    if total_bytes <= max_bytes {
        return Ok(total_bytes);
    }
    files.sort_by(|left, right| {
        left.0
            .cmp(&right.0)
            .then_with(|| left.1.as_os_str().cmp(right.1.as_os_str()))
    });
    for (_, path, size) in files {
        if total_bytes <= max_bytes {
            break;
        }
        if fs::remove_file(path).is_ok() {
            total_bytes = total_bytes.saturating_sub(size);
        }
    }
    Ok(total_bytes)
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgb;

    #[test]
    fn scramble_boundaries_match_protocol() {
        assert_eq!(calculate_block_num(220_980, 220_979, "1"), 0);
        assert_eq!(calculate_block_num(220_980, 220_980, "1"), 10);
        assert_eq!(calculate_block_num(220_980, 300_000, "1"), 4);
        assert!(calculate_block_num(220_980, 500_000, "1") % 2 == 0);
    }

    #[test]
    fn album_cover_names_match_jm_routes() {
        assert_eq!(cover_image_name(123, false), "123_3x4.jpg");
        assert_eq!(cover_image_name(123, true), "123.jpg");
    }

    #[test]
    fn cached_pages_are_resolved_before_any_network_request() {
        let root = std::env::temp_dir().join(format!(
            "jmcomic3-media-cache-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap_or(Duration::ZERO)
                .as_nanos()
        ));
        let cache = MediaCache::open(&root).unwrap();
        let chapter = cache.chapters.join("123");
        fs::create_dir_all(&chapter).unwrap();
        fs::write(chapter.join("00001.png"), b"decoded").unwrap();

        let cached = cache
            .cached_page_path(123, "00001.webp")
            .expect("decoded page should be a cache hit");
        assert!(cached.ends_with("00001.png"));
        assert!(cache.cached_page_path(123, "00002.webp").is_none());

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn media_fetch_locks_are_shared_and_released() {
        let root = std::env::temp_dir().join(format!(
            "jmcomic3-media-locks-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap_or(Duration::ZERO)
                .as_nanos()
        ));
        let cache = MediaCache::open(&root).unwrap();
        let first = cache.fetch_lock("page:1:image.webp").unwrap();
        let second = cache.fetch_lock("page:1:image.webp").unwrap();
        assert!(Arc::ptr_eq(&first, &second));

        drop(second);
        cache.release_fetch_lock("page:1:image.webp", &first);
        assert!(cache.fetch_locks.lock().unwrap().is_empty());

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn image_dimensions_are_cached_and_invalidated_after_replacement() {
        let root = std::env::temp_dir().join(format!(
            "jmcomic3-image-size-cache-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap_or(Duration::ZERO)
                .as_nanos()
        ));
        let cache = MediaCache::open(&root).unwrap();
        let path = root.join("size.png");
        RgbImage::from_pixel(2, 3, Rgb([1, 2, 3]))
            .save(&path)
            .unwrap();
        assert_eq!(cache.image_size(path.to_str().unwrap()).unwrap(), (2, 3));
        assert_eq!(cache.image_size(path.to_str().unwrap()).unwrap(), (2, 3));

        RgbImage::from_pixel(4, 5, Rgb([4, 5, 6]))
            .save(&path)
            .unwrap();
        assert_eq!(cache.image_size(path.to_str().unwrap()).unwrap(), (4, 5));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn stitching_reassembles_reversed_vertical_blocks() {
        let source = RgbImage::from_fn(2, 6, |_, y| Rgb([y as u8, 0, 0]));
        let stitched = stitch_image(&source, 3);
        assert_eq!(stitched.get_pixel(0, 0), &Rgb([4, 0, 0]));
        assert_eq!(stitched.get_pixel(0, 2), &Rgb([2, 0, 0]));
        assert_eq!(stitched.get_pixel(0, 4), &Rgb([0, 0, 0]));
    }

    #[test]
    fn cover_cache_pruning_keeps_the_size_bounded_without_touching_pages() {
        let root = std::env::temp_dir().join(format!(
            "jmcomic3-cover-prune-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap_or(Duration::ZERO)
                .as_nanos()
        ));
        let covers = root.join("covers");
        let pages = root.join("pages");
        fs::create_dir_all(&covers).unwrap();
        fs::create_dir_all(&pages).unwrap();
        for (name, size) in [
            ("100_3x4.jpg", 2 * 1024 * 1024_u64),
            ("200_3x4.jpg", 3 * 1024 * 1024_u64),
            ("300_3x4.jpg", 4 * 1024 * 1024_u64),
        ] {
            fs::File::create(covers.join(name))
                .unwrap()
                .set_len(size)
                .unwrap();
        }
        fs::write(pages.join("reader.png"), b"reader-cache").unwrap();

        let remaining =
            prune_cover_cache(&covers, 5 * 1024 * 1024, Duration::from_secs(3600)).unwrap();
        assert!(remaining <= 5 * 1024 * 1024);
        assert!(pages.join("reader.png").is_file());
        fs::remove_dir_all(root).unwrap();
    }
}
