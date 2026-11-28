use std::collections::HashSet;
use std::io::Cursor;
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use image::codecs::jpeg::JpegEncoder;
use reqwest::cookie::{CookieStore, Jar};
use reqwest::{Client, Method, RequestBuilder, StatusCode};
use serde_json::{json, Value};

use crate::config::JmClientConfig;
use crate::crypto::{decrypt_api_data, md5_hex};
use crate::error::{BackendError, BackendResult};
use crate::models::{JmApiResponse, SearchSort};

const APP_TOKEN_SECRET: &str = "18comicAPP";
const APP_TOKEN_SECRET_2: &str = "18comicAPPContent";
const IMAGE_SEARCH_URL: &str = "https://soutubot.moe/api/search";
const IMAGE_SEARCH_MAX_SOURCE_BYTES: u64 = 24 * 1024 * 1024;
const IMAGE_SEARCH_MAX_EDGE: u32 = 2000;
const IMAGE_SEARCH_JPEG_QUALITY: u8 = 92;
const IMAGE_SEARCH_RESULT_LIMIT: usize = 20;
const IMAGE_SEARCH_MIN_SIMILARITY: f64 = 30.0;
const IMAGE_SEARCH_JM_VERIFIED_SCORE: f64 = 45.0;

fn favorite_folder_form(
    action: &str,
    folder_name: Option<&str>,
    folder_id: Option<i64>,
    album_id: Option<i64>,
) -> Value {
    let mut form = serde_json::Map::new();
    form.insert("type".into(), json!(action));
    if let Some(folder_name) = folder_name {
        form.insert("folder_name".into(), json!(folder_name));
    }
    if let Some(folder_id) = folder_id {
        form.insert("folder_id".into(), json!(folder_id));
    }
    if let Some(album_id) = album_id {
        form.insert("aid".into(), json!(album_id));
    }
    Value::Object(form)
}

#[derive(Debug, Clone, Copy)]
enum ApiPath {
    Login,
    Search,
    Album,
    Chapter,
    Scramble,
    Categories,
    Comics,
    Favorite,
    FavoriteFolder,
    Daily,
    DailyCheck,
    Forum,
    Comment,
    CommentLike,
    WeeklyInfo,
    Weekly,
    Games,
}

impl ApiPath {
    fn as_str(self) -> &'static str {
        match self {
            Self::Login => "/login",
            Self::Search => "/search",
            Self::Album => "/album",
            Self::Chapter => "/chapter",
            Self::Scramble => "/chapter_view_template",
            Self::Categories => "/categories",
            Self::Comics => "/categories/filter",
            Self::Favorite => "/favorite",
            Self::FavoriteFolder => "/favorite_folder",
            Self::Daily => "/daily",
            Self::DailyCheck => "/daily_chk",
            Self::Forum => "/forum",
            Self::Comment => "/comment",
            Self::CommentLike => "/comment/like",
            Self::WeeklyInfo => "/week",
            Self::Weekly => "/week/filter",
            Self::Games => "/games",
        }
    }
}

struct Inner {
    config: JmClientConfig,
    client: Client,
    cookie_jar: Arc<Jar>,
}

#[derive(Clone)]
pub struct JmClient {
    inner: Arc<Inner>,
}

impl JmClient {
    pub fn new(config: JmClientConfig) -> BackendResult<Self> {
        let config = config.validated()?;
        let cookie_jar = Arc::new(Jar::default());
        let mut builder = Client::builder()
            .cookie_provider(cookie_jar.clone())
            .timeout(config.request_timeout)
            .connect_timeout(Duration::from_secs(10).min(config.request_timeout))
            .tcp_keepalive(Duration::from_secs(30))
            .pool_idle_timeout(Duration::from_secs(90))
            .pool_max_idle_per_host(16);
        if let Some(proxy_url) = config.proxy_url.as_deref() {
            let proxy = reqwest::Proxy::all(proxy_url).map_err(|error| {
                BackendError::Config(format!("invalid proxy `{proxy_url}`: {error}"))
            })?;
            builder = builder.proxy(proxy);
        } else {
            builder = builder.no_proxy();
        }
        let client = builder.build()?;
        Ok(Self {
            inner: Arc::new(Inner {
                config,
                client,
                cookie_jar,
            }),
        })
    }

    pub fn config(&self) -> &JmClientConfig {
        &self.inner.config
    }

    pub async fn login(&self, username: &str, password: &str) -> BackendResult<Value> {
        if username.trim().is_empty() || password.is_empty() {
            return Err(BackendError::Config(
                "username and password must not be empty".into(),
            ));
        }
        let value = self
            .api_json(
                Method::POST,
                ApiPath::Login,
                None,
                Some(json!({
                    "username": username,
                    "password": password,
                })),
            )
            .await?;
        Ok(normalize_self_info_value(value))
    }

    pub async fn user_profile(&self) -> BackendResult<Value> {
        let value = self
            .api_json(Method::POST, ApiPath::Login, None, None)
            .await?;
        Ok(normalize_self_info_value(value))
    }

    pub async fn search(&self, keyword: &str, page: u32, sort: SearchSort) -> BackendResult<Value> {
        self.api_json(
            Method::GET,
            ApiPath::Search,
            Some(json!({
                "main_tag": 0,
                "search_query": keyword,
                "page": page,
                "o": sort.as_str(),
            })),
            None,
        )
        .await
    }

    pub async fn image_search(&self, path: &Path) -> BackendResult<Value> {
        let source_path = path.to_path_buf();
        let image_bytes =
            tokio::task::spawn_blocking(move || prepare_image_search_upload(&source_path))
                .await
                .map_err(|error| {
                    BackendError::InvalidResponse(format!("image preprocessing failed: {error}"))
                })??;
        let file_part = reqwest::multipart::Part::bytes(image_bytes)
            .file_name("image.jpg")
            .mime_str("image/jpeg")?;
        let form = reqwest::multipart::Form::new()
            .part("file", file_part)
            .text("factor", "1.4")
            .text("metadata_mode", "display")
            .text("top_k", "40");
        let response = self
            .inner
            .client
            .post(IMAGE_SEARCH_URL)
            .header("Accept", "application/json")
            .header("Accept-Language", "zh-CN")
            .header("Origin", "https://soutubot.moe")
            .header("Referer", "https://soutubot.moe/")
            .header("X-Requested-With", "XMLHttpRequest")
            .header(
                "User-Agent",
                "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 \
                 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36",
            )
            .multipart(form)
            .send()
            .await?;
        let status = response.status();
        let body = response.text().await?;
        if !status.is_success() {
            return Err(BackendError::HttpStatus {
                status: status.as_u16(),
                body: body.chars().take(500).collect(),
            });
        }
        let payload: Value = serde_json::from_str(&body)?;
        Ok(normalize_image_search_response(payload))
    }

    pub async fn album(&self, album_id: i64) -> BackendResult<Value> {
        let value = self
            .api_json(
                Method::GET,
                ApiPath::Album,
                Some(json!({ "id": album_id })),
                None,
            )
            .await?;
        Ok(normalize_album_value(value))
    }

    pub async fn album_published_at(
        &self,
        album_id: i64,
        album_name: &str,
    ) -> BackendResult<String> {
        for query in album_published_search_queries(album_name) {
            let value = self.search(&query, 1, SearchSort::Latest).await?;
            let published_at = album_published_at_from_search(&value, album_id);
            if !published_at.is_empty() {
                return Ok(published_at);
            }
        }
        Ok(String::new())
    }

    pub async fn chapter(&self, chapter_id: i64) -> BackendResult<Value> {
        let value = self
            .api_json(
                Method::GET,
                ApiPath::Chapter,
                Some(json!({ "id": chapter_id })),
                None,
            )
            .await?;
        Ok(normalize_chapter_value(value))
    }

    pub async fn categories(&self) -> BackendResult<Value> {
        match self
            .api_json(Method::GET, ApiPath::Categories, None, None)
            .await
        {
            Ok(value) => Ok(normalize_categories_value(value)),
            Err(_) => Ok(fallback_categories()),
        }
    }

    pub async fn comics(
        &self,
        category_slug: &str,
        sort_by: &str,
        page: u32,
    ) -> BackendResult<Value> {
        let slug = category_slug.trim();
        let slug = if slug.is_empty() { "latest" } else { slug };
        self.api_json(
            Method::GET,
            ApiPath::Comics,
            Some(json!({
                "page": page.max(1),
                "order": "",
                "c": slug,
                "o": sort_by.trim(),
            })),
            None,
        )
        .await
    }

    pub async fn favorite(
        &self,
        folder_id: i64,
        page: u32,
        sort: SearchSort,
    ) -> BackendResult<Value> {
        let value = self
            .api_json(
                Method::GET,
                ApiPath::Favorite,
                Some(json!({
                    "page": page,
                    "o": sort.as_str(),
                    "folder_id": folder_id,
                })),
                None,
            )
            .await?;
        Ok(normalize_favorite_value(value))
    }

    pub async fn toggle_favorite(&self, album_id: i64) -> BackendResult<Value> {
        self.api_write_json(
            Method::POST,
            ApiPath::Favorite,
            None,
            Some(json!({"aid": album_id})),
        )
        .await
    }

    pub async fn create_favorite_folder(&self, folder_name: &str) -> BackendResult<Value> {
        if folder_name.trim().is_empty() {
            return Err(BackendError::Config("folder name is empty".into()));
        }
        self.api_write_json(
            Method::POST,
            ApiPath::FavoriteFolder,
            None,
            Some(favorite_folder_form(
                "add",
                Some(folder_name.trim()),
                None,
                None,
            )),
        )
        .await
    }

    pub async fn delete_favorite_folder(&self, folder_id: i64) -> BackendResult<Value> {
        if folder_id <= 0 {
            return Err(BackendError::Config("folder id must be positive".into()));
        }
        self.api_write_json(
            Method::POST,
            ApiPath::FavoriteFolder,
            None,
            Some(favorite_folder_form("del", None, Some(folder_id), None)),
        )
        .await
    }

    pub async fn rename_favorite_folder(
        &self,
        folder_id: i64,
        folder_name: &str,
    ) -> BackendResult<Value> {
        if folder_id <= 0 || folder_name.trim().is_empty() {
            return Err(BackendError::Config(
                "folder id and name must be valid".into(),
            ));
        }
        self.api_write_json(
            Method::POST,
            ApiPath::FavoriteFolder,
            None,
            Some(favorite_folder_form(
                "edit",
                Some(folder_name.trim()),
                Some(folder_id),
                None,
            )),
        )
        .await
    }

    pub async fn move_comic_to_favorite_folder(
        &self,
        comic_id: i64,
        folder_id: i64,
    ) -> BackendResult<Value> {
        if comic_id <= 0 || folder_id < 0 {
            return Err(BackendError::Config(
                "comic id must be positive and folder id must not be negative".into(),
            ));
        }
        self.api_write_json(
            Method::POST,
            ApiPath::FavoriteFolder,
            None,
            Some(favorite_folder_form(
                "move",
                None,
                Some(folder_id),
                Some(comic_id),
            )),
        )
        .await
    }

    pub async fn daily(&self, user_id: i64) -> BackendResult<Value> {
        self.api_json(
            Method::GET,
            ApiPath::Daily,
            Some(json!({"user_id": user_id})),
            None,
        )
        .await
    }

    pub async fn daily_checkin(&self, user_id: i64) -> BackendResult<Value> {
        let daily = self.daily(user_id).await?;
        let daily_id = daily
            .get("daily_id")
            .and_then(|value| {
                value
                    .as_i64()
                    .map(|value| value.to_string())
                    .or_else(|| value.as_str().map(str::to_string))
            })
            .ok_or_else(|| {
                BackendError::InvalidResponse("daily response has no daily_id".into())
            })?;
        self.api_write_json(
            Method::POST,
            ApiPath::DailyCheck,
            None,
            Some(json!({
                "user_id": user_id,
                "daily_id": daily_id,
            })),
        )
        .await
    }

    pub async fn forum(
        &self,
        mode: Option<&str>,
        album_id: Option<i64>,
        user_id: Option<i64>,
        page: u32,
    ) -> BackendResult<Value> {
        let mut query = serde_json::Map::new();
        query.insert("mode".into(), json!(mode.unwrap_or("all")));
        query.insert("page".into(), json!(page.max(1)));
        if let Some(album_id) = album_id {
            query.insert("aid".into(), json!(album_id));
        }
        if let Some(user_id) = user_id {
            query.insert("uid".into(), json!(user_id));
        }
        let value = self
            .api_json(
                Method::GET,
                ApiPath::Forum,
                Some(Value::Object(query)),
                None,
            )
            .await?;
        Ok(normalize_forum_value(value))
    }

    pub async fn comment(
        &self,
        album_id: i64,
        comment: &str,
        parent_comment_id: Option<i64>,
    ) -> BackendResult<Value> {
        if comment.trim().is_empty() {
            return Err(BackendError::Config("comment is empty".into()));
        }
        self.api_write_json(
            Method::POST,
            ApiPath::Comment,
            None,
            Some(comment_form(album_id, comment, parent_comment_id)),
        )
        .await
    }

    pub async fn like_comment(&self, comment_id: i64) -> BackendResult<Value> {
        if comment_id <= 0 {
            return Err(BackendError::Config("comment id must be positive".into()));
        }
        match self
            .api_write_json(
                Method::POST,
                ApiPath::CommentLike,
                None,
                Some(json!({ "cid": comment_id })),
            )
            .await
        {
            Ok(value) => Ok(value),
            Err(BackendError::Api { message, .. })
                if is_comment_like_upstream_limited(&message) =>
            {
                Ok(json!({
                    "status": "ok",
                    "msg": message,
                    "upstream_limited": true,
                }))
            }
            Err(error) => Err(error),
        }
    }

    pub async fn weekly_info(&self) -> BackendResult<Value> {
        self.api_json(Method::GET, ApiPath::WeeklyInfo, None, None)
            .await
    }

    pub async fn weekly(&self, category_id: &str, type_id: &str) -> BackendResult<Value> {
        self.api_json(
            Method::GET,
            ApiPath::Weekly,
            Some(json!({
                "id": category_id,
                "type": type_id,
            })),
            None,
        )
        .await
    }

    pub async fn games(&self, page: u32) -> BackendResult<Value> {
        self.api_json(
            Method::GET,
            ApiPath::Games,
            Some(json!({ "page": page.max(1) })),
            None,
        )
        .await
    }

    pub async fn http_get_text(&self, url: &str) -> BackendResult<String> {
        let parsed = reqwest::Url::parse(url.trim())
            .map_err(|error| BackendError::Config(format!("invalid HTTP URL: {error}")))?;
        if !matches!(parsed.scheme(), "http" | "https") {
            return Err(BackendError::Config(
                "only http and https URLs are supported".into(),
            ));
        }
        let response = self
            .inner
            .client
            .get(parsed)
            .header(reqwest::header::USER_AGENT, &self.inner.config.user_agent)
            .send()
            .await?;
        let status = response.status();
        let body = response.text().await?;
        if !status.is_success() {
            return Err(BackendError::HttpStatus {
                status: status.as_u16(),
                body,
            });
        }
        Ok(body)
    }

    pub async fn webdav_get_text(
        &self,
        url: &str,
        username: &str,
        password: &str,
    ) -> BackendResult<Option<String>> {
        let parsed = parse_web_url(url)?;
        let mut request = self
            .inner
            .client
            .get(parsed)
            .header(reqwest::header::USER_AGENT, &self.inner.config.user_agent);
        if !username.trim().is_empty() || !password.is_empty() {
            request = request.basic_auth(username, Some(password));
        }
        let response = request.send().await?;
        if response.status() == StatusCode::NOT_FOUND {
            return Ok(None);
        }
        let status = response.status();
        let body = response.text().await?;
        if !status.is_success() {
            return Err(BackendError::HttpStatus {
                status: status.as_u16(),
                body,
            });
        }
        Ok(Some(body))
    }

    pub async fn webdav_put(
        &self,
        url: &str,
        username: &str,
        password: &str,
        body: &Value,
    ) -> BackendResult<()> {
        let parsed = parse_web_url(url)?;
        let mut request = self
            .inner
            .client
            .put(parsed)
            .header(reqwest::header::USER_AGENT, &self.inner.config.user_agent)
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(serde_json::to_string(body)?);
        if !username.trim().is_empty() || !password.is_empty() {
            request = request.basic_auth(username, Some(password));
        }
        let response = request.send().await?;
        let status = response.status();
        let response_body = response.text().await?;
        if !status.is_success() {
            return Err(BackendError::HttpStatus {
                status: status.as_u16(),
                body: response_body,
            });
        }
        Ok(())
    }

    pub async fn measure_host(&self, host: &str, path: &str) -> BackendResult<u64> {
        let config = JmClientConfig {
            api_host: host.to_string(),
            ..JmClientConfig::default()
        }
        .validated()?;
        let url = format!("https://{}{}", config.api_host, path);
        let started = std::time::Instant::now();
        let response = self
            .inner
            .client
            .get(url)
            .header(reqwest::header::USER_AGENT, &self.inner.config.user_agent)
            .send()
            .await?;
        if !response.status().is_success() {
            return Err(BackendError::HttpStatus {
                status: response.status().as_u16(),
                body: String::new(),
            });
        }
        let _ = response.bytes().await?;
        Ok(started.elapsed().as_millis().max(1) as u64)
    }

    pub async fn measure_image_host(&self, host: &str, timeout: Duration) -> BackendResult<u64> {
        tokio::time::timeout(timeout, self.measure_image_host_inner(host))
            .await
            .map_err(|_| BackendError::InvalidResponse("CDN probe timed out".into()))?
    }

    async fn measure_image_host_inner(&self, host: &str) -> BackendResult<u64> {
        let config = JmClientConfig {
            api_host: host.to_string(),
            ..JmClientConfig::default()
        }
        .validated()?;
        let url = format!("https://{}/media/albums/blank.jpg", config.api_host);
        let started = std::time::Instant::now();
        let response = self
            .inner
            .client
            .get(url)
            .header(reqwest::header::USER_AGENT, &self.inner.config.user_agent)
            .send()
            .await?;
        let status = response.status();
        if !status.is_success() {
            return Err(BackendError::HttpStatus {
                status: status.as_u16(),
                body: String::new(),
            });
        }
        let is_image = response
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .is_some_and(|value| value.to_ascii_lowercase().starts_with("image/"));
        if !is_image {
            return Err(BackendError::InvalidResponse(
                "CDN probe did not return an image".into(),
            ));
        }
        Ok(started.elapsed().as_millis().max(1) as u64)
    }

    pub async fn measure_api_host(&self, host: &str, timeout: Duration) -> BackendResult<u64> {
        tokio::time::timeout(timeout, self.measure_api_host_inner(host))
            .await
            .map_err(|_| BackendError::InvalidResponse("API probe timed out".into()))?
    }

    async fn measure_api_host_inner(&self, host: &str) -> BackendResult<u64> {
        let config = JmClientConfig {
            api_host: host.to_string(),
            ..JmClientConfig::default()
        }
        .validated()?;
        let timestamp = unix_timestamp()?;
        let token = md5_hex(&format!("{timestamp}{APP_TOKEN_SECRET}"));
        let tokenparam = format!("{timestamp},{}", self.inner.config.app_version);
        let url = format!("https://{}{}", config.api_host, ApiPath::Comics.as_str());
        let started = std::time::Instant::now();
        let response = self
            .inner
            .client
            .get(url)
            .query(&json!({
                "page": 1,
                "order": "",
                "c": "latest",
                "o": SearchSort::Latest.as_str(),
            }))
            .header("token", token)
            .header("tokenparam", tokenparam)
            .header(reqwest::header::USER_AGENT, &self.inner.config.user_agent)
            .send()
            .await?;
        let status = response.status();
        if !status.is_success() {
            return Err(BackendError::HttpStatus {
                status: status.as_u16(),
                body: String::new(),
            });
        }
        Ok(started.elapsed().as_millis().max(1) as u64)
    }

    pub async fn scramble_id(&self, chapter_id: i64) -> BackendResult<i64> {
        let timestamp = unix_timestamp()?;
        let request = self
            .request(Method::GET, ApiPath::Scramble, timestamp)?
            .query(&json!({
                "id": chapter_id,
                "v": timestamp,
                "mode": "vertical",
                "page": 0,
                "app_img_shunt": 1,
                "express": "off",
            }));
        let response = request.send().await?;
        let status = response.status();
        let body = response.text().await?;
        if !status.is_success() {
            return Err(BackendError::HttpStatus {
                status: status.as_u16(),
                body,
            });
        }
        Ok(body
            .split("var scramble_id = ")
            .nth(1)
            .and_then(|value| value.split(';').next())
            .and_then(|value| value.trim().parse::<i64>().ok())
            .unwrap_or(220_980))
    }

    pub async fn page_image_bytes(
        &self,
        chapter_id: i64,
        image_name: &str,
    ) -> BackendResult<Vec<u8>> {
        let url = format!(
            "https://{}/media/photos/{chapter_id}/{}",
            self.inner.config.image_host, image_name
        );
        self.fetch_image(&url, false).await
    }

    pub async fn photo_image_bytes(&self, image_name: &str) -> BackendResult<Vec<u8>> {
        if image_name.trim().is_empty() {
            return Err(BackendError::Config("photo image name is empty".into()));
        }
        let url = format!(
            "https://{}/media/users/{}",
            self.inner.config.image_host, image_name
        );
        self.fetch_image(&url, false).await
    }

    pub async fn cover_image_bytes(&self, image_name: &str) -> BackendResult<Vec<u8>> {
        let url = format!(
            "https://{}/media/albums/{}",
            self.inner.config.image_host, image_name
        );
        self.fetch_image(&url, false).await
    }

    pub fn cookie_header_for(&self, url: &str) -> Option<String> {
        let url = reqwest::Url::parse(url).ok()?;
        let cookies = self.inner.cookie_jar.cookies(&url)?;
        cookies.to_str().ok().map(str::to_string)
    }

    pub fn add_cookie_header(&self, header: &str, url: &str) {
        if !header.trim().is_empty() {
            if let Ok(url) = reqwest::Url::parse(url) {
                self.inner.cookie_jar.add_cookie_str(header, &url);
            }
        }
    }

    pub fn api_base_url(&self) -> String {
        format!("https://{}", self.inner.config.api_host)
    }

    async fn fetch_image(&self, url: &str, retry_with_timestamp: bool) -> BackendResult<Vec<u8>> {
        let mut request = self
            .inner
            .client
            .get(url)
            .header(reqwest::header::USER_AGENT, &self.inner.config.user_agent)
            .header(
                reqwest::header::ACCEPT,
                "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
            )
            .header("X-Requested-With", "com.JMComic3.app")
            .header(
                reqwest::header::REFERER,
                format!("https://{}", self.inner.config.api_host),
            )
            .header(
                reqwest::header::ACCEPT_LANGUAGE,
                "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7",
            );
        if retry_with_timestamp {
            request = request.query(&json!({ "ts": unix_timestamp()? }));
        }
        let response = request.send().await?;
        let status = response.status();
        let bytes = response.bytes().await?;
        if !status.is_success() {
            return Err(BackendError::HttpStatus {
                status: status.as_u16(),
                body: String::from_utf8_lossy(&bytes).into_owned(),
            });
        }
        if bytes.is_empty() && !retry_with_timestamp {
            return Box::pin(self.fetch_image(url, true)).await;
        }
        Ok(bytes.to_vec())
    }

    async fn api_json(
        &self,
        method: Method,
        path: ApiPath,
        query: Option<Value>,
        form: Option<Value>,
    ) -> BackendResult<Value> {
        let timestamp = unix_timestamp()?;
        let body = self
            .send_with_retry(method, path, query, form, timestamp)
            .await?;
        decode_api_body(timestamp, body)
    }

    async fn api_write_json(
        &self,
        method: Method,
        path: ApiPath,
        query: Option<Value>,
        form: Option<Value>,
    ) -> BackendResult<Value> {
        let value = self.api_json(method, path, query, form).await?;
        ensure_write_action_succeeded(value)
    }

    async fn send_with_retry(
        &self,
        method: Method,
        path: ApiPath,
        query: Option<Value>,
        form: Option<Value>,
        timestamp: u64,
    ) -> BackendResult<String> {
        let mut last_error = None;
        for attempt in 0..=self.inner.config.max_retries {
            let mut request = self.request(method.clone(), path, timestamp)?;
            if let Some(query) = query.as_ref() {
                request = request.query(query);
            }
            if let Some(form) = form.as_ref() {
                request = request.form(form);
            }
            match request.send().await {
                Ok(response) => {
                    let status = response.status();
                    let body = response.text().await?;
                    if status.is_success() {
                        return Ok(body);
                    }
                    let retryable = status == StatusCode::TOO_MANY_REQUESTS
                        || (method == Method::GET && status.is_server_error());
                    if !retryable || attempt == self.inner.config.max_retries {
                        return Err(BackendError::HttpStatus {
                            status: status.as_u16(),
                            body,
                        });
                    }
                    last_error = Some(BackendError::HttpStatus {
                        status: status.as_u16(),
                        body,
                    });
                }
                Err(error) => {
                    if error.is_connect() || error.is_timeout() {
                        return Err(BackendError::Http(error));
                    }
                    if attempt == self.inner.config.max_retries {
                        return Err(BackendError::Http(error));
                    }
                    last_error = Some(BackendError::Http(error));
                }
            }
            tokio::time::sleep(Duration::from_millis(200 * (attempt as u64 + 1))).await;
        }
        Err(last_error.unwrap_or_else(|| {
            BackendError::InvalidResponse("request retry loop ended unexpectedly".into())
        }))
    }

    fn request(
        &self,
        method: Method,
        path: ApiPath,
        timestamp: u64,
    ) -> BackendResult<RequestBuilder> {
        let tokenparam = format!("{timestamp},{}", self.inner.config.app_version);
        let secret = if matches!(path, ApiPath::Scramble) {
            APP_TOKEN_SECRET_2
        } else {
            APP_TOKEN_SECRET
        };
        let token = md5_hex(&format!("{timestamp}{secret}"));
        let url = format!("https://{}{}", self.inner.config.api_host, path.as_str());
        Ok(self
            .inner
            .client
            .request(method, url)
            .header("token", token)
            .header("tokenparam", tokenparam)
            .header(reqwest::header::USER_AGENT, &self.inner.config.user_agent))
    }
}

fn comment_form(album_id: i64, comment: &str, parent_comment_id: Option<i64>) -> Value {
    let mut form = serde_json::Map::new();
    form.insert("aid".into(), json!(album_id));
    form.insert("comment".into(), json!(comment));
    if let Some(comment_id) = parent_comment_id {
        form.insert("comment_id".into(), json!(comment_id));
    }
    Value::Object(form)
}

fn ensure_write_action_succeeded(value: Value) -> BackendResult<Value> {
    let Some(object) = value.as_object() else {
        return Ok(value);
    };
    let status = object
        .get("status")
        .map(value_wire_string)
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase();
    if !matches!(status.as_str(), "fail" | "error" | "false" | "0") {
        return Ok(value);
    }
    let message = ["msg", "error_msg", "message"]
        .iter()
        .find_map(|key| object.get(*key).map(value_wire_string))
        .filter(|message| !message.trim().is_empty())
        .unwrap_or_else(|| "write operation failed".into());
    Err(BackendError::Api { code: 0, message })
}

fn is_comment_like_upstream_limited(message: &str) -> bool {
    let compact: String = message.chars().filter(|ch| !ch.is_whitespace()).collect();
    [
        "勿短時間重複留言",
        "勿短时间重复留言",
        "勿重複留言",
        "勿重复留言",
    ]
    .iter()
    .any(|marker| compact.contains(marker))
}

fn decode_api_body(timestamp: u64, body: String) -> BackendResult<Value> {
    let response: JmApiResponse = serde_json::from_str(&body)?;
    if response.code != 200 {
        return Err(BackendError::Api {
            code: response.code,
            message: if response.error_msg.is_empty() {
                "request rejected".into()
            } else {
                response.error_msg
            },
        });
    }
    let Some(payload) = response.data.as_str() else {
        // Some endpoints, including daily check-in, return their result as a
        // direct JSON object or array instead of an encrypted string.
        return Ok(response.data);
    };
    match decrypt_api_data(timestamp, payload) {
        Ok(decrypted) => match serde_json::from_str(&decrypted) {
            Ok(value) => Ok(value),
            Err(_) => Ok(Value::String(decrypted)),
        },
        Err(_) => match serde_json::from_str(payload) {
            Ok(value) => Ok(value),
            Err(_) => Ok(Value::String(payload.to_string())),
        },
    }
}

fn prepare_image_search_upload(path: &Path) -> BackendResult<Vec<u8>> {
    let metadata = std::fs::metadata(path)?;
    if !metadata.is_file() {
        return Err(BackendError::Config("image path is not a file".into()));
    }
    if metadata.len() == 0 {
        return Err(BackendError::Config("selected image is empty".into()));
    }
    if metadata.len() > IMAGE_SEARCH_MAX_SOURCE_BYTES {
        return Err(BackendError::Config(
            "selected image is larger than 24 MB".into(),
        ));
    }

    let source = std::fs::read(path)?;
    let image = image::load_from_memory(&source)
        .map_err(|error| BackendError::InvalidResponse(format!("unsupported image: {error}")))?;
    let image = if image.width() > IMAGE_SEARCH_MAX_EDGE || image.height() > IMAGE_SEARCH_MAX_EDGE {
        image.resize(
            IMAGE_SEARCH_MAX_EDGE,
            IMAGE_SEARCH_MAX_EDGE,
            image::imageops::FilterType::Lanczos3,
        )
    } else {
        image
    };
    let rgb = image.to_rgb8();
    let mut output = Vec::new();
    JpegEncoder::new_with_quality(&mut Cursor::new(&mut output), IMAGE_SEARCH_JPEG_QUALITY)
        .encode_image(&rgb)
        .map_err(|error| {
            BackendError::InvalidResponse(format!("image encoding failed: {error}"))
        })?;
    Ok(output)
}

fn normalize_image_search_response(value: Value) -> Value {
    let mut hits = Vec::new();

    if let Some(results) = value.get("results").and_then(Value::as_array) {
        for result in results {
            let score = result
                .get("score")
                .and_then(image_search_f64)
                .unwrap_or(0.0);
            let segments = result
                .get("path_segments")
                .and_then(Value::as_array)
                .map(Vec::as_slice)
                .unwrap_or_default();
            for segment in segments {
                if let Some(hit) = normalize_image_search_segment(segment, score) {
                    hits.push(hit);
                }
            }
        }
    }

    if hits.is_empty() {
        if let Some(legacy_results) = value.get("data").and_then(Value::as_array) {
            for result in legacy_results {
                let score = result
                    .get("similarity")
                    .and_then(image_search_f64)
                    .unwrap_or(0.0);
                if let Some(hit) = normalize_legacy_image_search_result(result, score) {
                    hits.push(hit);
                }
            }
        }
    }

    hits.retain(|hit| {
        hit["similarity"]
            .as_f64()
            .is_some_and(|score| score >= IMAGE_SEARCH_MIN_SIMILARITY)
    });
    hits.sort_by(|left, right| {
        image_search_rank(right)
            .partial_cmp(&image_search_rank(left))
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    let mut seen = HashSet::new();
    hits.retain(|hit| {
        let source = hit["source"].as_str().unwrap_or_default();
        let external_id = hit["external_id"].as_str().unwrap_or_default();
        let title = hit["title"].as_str().unwrap_or_default().to_lowercase();
        let key = if !external_id.is_empty() {
            format!("{source}:{external_id}")
        } else {
            format!("{source}:{title}")
        };
        seen.insert(key)
    });
    hits.truncate(IMAGE_SEARCH_RESULT_LIMIT);

    json!({
        "result_id": value.get("result_id").or_else(|| value.get("id")).cloned().unwrap_or(Value::Null),
        "status": value.get("status").cloned().unwrap_or(Value::String(String::new())),
        "partial": value.get("partial").and_then(Value::as_bool).unwrap_or(false),
        "elapsed_ms": value.pointer("/timing/total_ms").and_then(Value::as_u64).unwrap_or(0),
        "warnings": value.get("warnings").cloned().unwrap_or(Value::Array(Vec::new())),
        "hits": hits,
    })
}

fn image_search_rank(hit: &Value) -> f64 {
    let score = hit["similarity"].as_f64().unwrap_or(0.0);
    if hit["source"].as_str() == Some("jmcomic") && score >= IMAGE_SEARCH_JM_VERIFIED_SCORE {
        score + 8.0
    } else {
        score
    }
}

fn normalize_image_search_segment(segment: &Value, score: f64) -> Option<Value> {
    let source = image_search_text_at(segment, &["source_key"])
        .or_else(|| image_search_text_at(segment, &["metadata", "source", "key"]))
        .or_else(|| image_search_text_at(segment, &["metadata", "post", "source_key"]))
        .unwrap_or_else(|| "unknown".into())
        .to_ascii_lowercase();
    let external_id = image_search_text_at(segment, &["external_id"])
        .or_else(|| image_search_text_at(segment, &["metadata", "source", "id"]))
        .or_else(|| image_search_text_at(segment, &["metadata", "post", "post_id"]))
        .unwrap_or_default();
    let title = image_search_text_at(segment, &["metadata", "title", "primary"])
        .or_else(|| image_search_text_at(segment, &["metadata", "title"]))
        .or_else(|| image_search_text_at(segment, &["metadata", "work_title"]))
        .or_else(|| image_search_text_at(segment, &["title"]))
        .unwrap_or_default();
    if title.is_empty() && external_id.is_empty() {
        return None;
    }
    let title_alt = image_search_text_at(segment, &["metadata", "title", "japanese_or_alias"])
        .unwrap_or_default();
    let language = image_search_text_at(segment, &["language"])
        .or_else(|| image_search_text_at(segment, &["metadata", "facts", "language"]))
        .unwrap_or_default();
    let page = segment
        .get("page_no")
        .and_then(image_search_i64)
        .unwrap_or(0);
    let url = image_search_text_at(segment, &["source_url"])
        .or_else(|| image_search_text_at(segment, &["page_url"]))
        .or_else(|| image_search_text_at(segment, &["chapter_url"]))
        .unwrap_or_default();
    let thumbnail_url = image_search_text_at(segment, &["thumbnail_url"]).unwrap_or_default();

    Some(json!({
        "source": source,
        "external_id": external_id,
        "title": title,
        "title_alt": title_alt,
        "language": normalize_image_search_language(&language),
        "page": page,
        "similarity": score.clamp(0.0, 100.0),
        "url": url,
        "thumbnail_url": thumbnail_url,
    }))
}

fn normalize_legacy_image_search_result(result: &Value, score: f64) -> Option<Value> {
    let source = image_search_text_at(result, &["source"])
        .unwrap_or_else(|| "unknown".into())
        .to_ascii_lowercase();
    let title = image_search_text_at(result, &["title"]).unwrap_or_default();
    let path = image_search_text_at(result, &["subjectPath"]).unwrap_or_default();
    if title.is_empty() {
        return None;
    }
    let external_id = path
        .split('/')
        .filter(|part| !part.is_empty())
        .next_back()
        .unwrap_or_default()
        .to_string();
    Some(json!({
        "source": source,
        "external_id": external_id,
        "title": title,
        "title_alt": "",
        "language": normalize_image_search_language(
            &image_search_text_at(result, &["language"]).unwrap_or_default()
        ),
        "page": result.get("page").and_then(image_search_i64).unwrap_or(0),
        "similarity": score.clamp(0.0, 100.0),
        "url": path,
        "thumbnail_url": image_search_text_at(result, &["previewImageUrl"]).unwrap_or_default(),
    }))
}

fn image_search_text_at(value: &Value, path: &[&str]) -> Option<String> {
    let mut current = value;
    for key in path {
        current = current.get(*key)?;
    }
    match current {
        Value::String(value) => {
            let value = value.trim();
            (!value.is_empty()).then(|| value.to_string())
        }
        Value::Number(value) => Some(value.to_string()),
        _ => None,
    }
}

fn image_search_f64(value: &Value) -> Option<f64> {
    value
        .as_f64()
        .or_else(|| value.as_str()?.trim().parse::<f64>().ok())
}

fn image_search_i64(value: &Value) -> Option<i64> {
    value
        .as_i64()
        .or_else(|| value.as_str()?.trim().parse::<i64>().ok())
}

fn normalize_image_search_language(value: &str) -> String {
    match value.trim().to_ascii_lowercase().as_str() {
        "chinese" | "zh" | "cn" => "zh",
        "japanese" | "ja" | "jp" => "ja",
        "english" | "en" | "gb" => "en",
        "korean" | "ko" | "kr" => "ko",
        other => other,
    }
    .to_string()
}

fn normalize_album_value(mut value: Value) -> Value {
    let Some(album) = value.as_object_mut() else {
        return value;
    };
    for key in [
        "id",
        "series_id",
        "total_views",
        "likes",
        "comment_total",
        "update_at",
        "addtime",
    ] {
        if let Some(normalized) = album.get(key).and_then(value_i64) {
            album.insert(key.to_string(), json!(normalized));
        } else if matches!(
            key,
            "id" | "series_id" | "total_views" | "likes" | "comment_total"
        ) {
            album.insert(key.to_string(), json!(0));
        }
    }
    for key in [
        "author",
        "images",
        "series",
        "tags",
        "works",
        "related_list",
    ] {
        if !album.get(key).is_some_and(Value::is_array) {
            album.insert(key.to_string(), Value::Array(Vec::new()));
        }
    }
    for key in ["liked", "is_favorite"] {
        let normalized = album.get(key).is_some_and(value_bool);
        album.insert(key.to_string(), json!(normalized));
    }
    value
}

fn album_published_at_from_search(value: &Value, album_id: i64) -> String {
    value
        .get("content")
        .and_then(Value::as_array)
        .and_then(|items| {
            items.iter().find(|item| {
                item.get("id")
                    .and_then(value_i64)
                    .is_some_and(|id| id == album_id)
            })
        })
        .and_then(|item| item.get("adddate"))
        .map(value_wire_string)
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn album_published_search_queries(album_name: &str) -> Vec<String> {
    let full = album_name.trim();
    if full.is_empty() {
        return Vec::new();
    }

    let without_prefix = strip_leading_bracketed_prefix(full);
    let title_part = without_prefix
        .split(|character| matches!(character, '/' | '|' | '｜'))
        .map(str::trim)
        .filter(|value| value.chars().count() >= 2)
        .max_by_key(|value| value.chars().count())
        .unwrap_or(without_prefix);
    let primary_title = if title_part.chars().count() > 80 {
        title_part.chars().take(80).collect::<String>()
    } else {
        title_part.to_string()
    };

    let mut queries = Vec::new();
    for candidate in [primary_title.as_str(), full] {
        let candidate = candidate.trim();
        if !candidate.is_empty() && !queries.iter().any(|value| value == candidate) {
            queries.push(candidate.to_string());
        }
    }
    queries
}

fn strip_leading_bracketed_prefix(value: &str) -> &str {
    let mut result = value.trim();
    loop {
        let Some(first) = result.chars().next() else {
            return result;
        };
        let close = match first {
            '[' => ']',
            '(' => ')',
            '（' => '）',
            '【' => '】',
            _ => return result,
        };
        let Some((close_index, _)) = result
            .char_indices()
            .skip(1)
            .find(|(_, character)| *character == close)
        else {
            return result;
        };
        result = result[close_index + close.len_utf8()..].trim_start();
    }
}

fn normalize_categories_value(mut value: Value) -> Value {
    let Some(root) = value.as_object_mut() else {
        return fallback_categories();
    };
    if let Some(categories) = root.get_mut("categories").and_then(Value::as_array_mut) {
        for category in categories {
            let Some(category) = category.as_object_mut() else {
                continue;
            };
            for key in ["id", "total_albums"] {
                let normalized = category.get(key).and_then(value_i64).unwrap_or(0);
                category.insert(key.to_string(), json!(normalized));
            }
            for key in ["name", "slug"] {
                let normalized = category.get(key).map(value_wire_string).unwrap_or_default();
                category.insert(key.to_string(), Value::String(normalized));
            }
            if category
                .get("slug")
                .and_then(Value::as_str)
                .is_some_and(|slug| slug.trim().is_empty())
            {
                let id = category.get("id").and_then(Value::as_i64).unwrap_or(0);
                let slug = if id == 0 {
                    "latest".to_string()
                } else {
                    id.to_string()
                };
                category.insert("slug".into(), Value::String(slug));
            }
        }
    } else {
        root.insert("categories".into(), Value::Array(Vec::new()));
    }
    if let Some(blocks) = root.get_mut("blocks").and_then(Value::as_array_mut) {
        for block in blocks {
            let Some(block) = block.as_object_mut() else {
                continue;
            };
            let title = block
                .get("title")
                .map(value_wire_string)
                .unwrap_or_default();
            block.insert("title".into(), Value::String(title));
            let values = block
                .get("content")
                .or_else(|| block.get("values"))
                .or_else(|| block.get("items"))
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            let content = values
                .iter()
                .filter_map(|value| match value {
                    Value::String(value) => Some(value.clone()),
                    Value::Object(value) => value
                        .get("slug")
                        .or_else(|| value.get("value"))
                        .or_else(|| value.get("id"))
                        .map(value_wire_string),
                    Value::Number(_) | Value::Bool(_) => Some(value.to_string()),
                    Value::Null | Value::Array(_) => None,
                })
                .filter(|value| !value.trim().is_empty())
                .collect::<Vec<_>>();
            block.insert("content".into(), json!(content));
        }
    } else {
        root.insert("blocks".into(), Value::Array(Vec::new()));
    }
    value
}

fn fallback_categories() -> Value {
    json!({
        "categories": [
            {"id": 0, "name": "最新A漫", "slug": "latest", "total_albums": 0},
            {"id": 1, "name": "同人", "slug": "doujin", "total_albums": 0},
            {"id": 2, "name": "单本", "slug": "single", "total_albums": 0},
            {"id": 3, "name": "短篇", "slug": "short", "total_albums": 0},
            {"id": 4, "name": "其他", "slug": "another", "total_albums": 0},
            {"id": 5, "name": "韩漫", "slug": "hanman", "total_albums": 0},
            {"id": 6, "name": "美漫", "slug": "meiman", "total_albums": 0},
            {"id": 7, "name": "Cosplay", "slug": "doujin_cosplay", "total_albums": 0},
            {"id": 8, "name": "3D", "slug": "3D", "total_albums": 0},
            {"id": 9, "name": "英文站", "slug": "english_site", "total_albums": 0}
        ],
        "blocks": [{
            "title": "分类",
            "content": [
                "latest", "doujin", "single", "short", "another",
                "hanman", "meiman", "doujin_cosplay", "3D", "english_site"
            ]
        }]
    })
}

fn normalize_chapter_value(mut value: Value) -> Value {
    let Some(chapter) = value.as_object_mut() else {
        return value;
    };
    for key in ["id", "series_id"] {
        let normalized = chapter.get(key).and_then(value_i64).unwrap_or(0);
        chapter.insert(key.to_string(), json!(normalized));
    }
    for key in ["series", "images"] {
        if !chapter.get(key).is_some_and(Value::is_array) {
            chapter.insert(key.to_string(), Value::Array(Vec::new()));
        }
    }
    for key in ["liked", "is_favorite"] {
        let normalized = chapter.get(key).is_some_and(value_bool);
        chapter.insert(key.to_string(), json!(normalized));
    }
    for key in ["tags", "name"] {
        if !chapter.get(key).is_some_and(Value::is_string) {
            chapter.insert(key.to_string(), Value::String(String::new()));
        }
    }
    value
}

fn normalize_self_info_value(mut value: Value) -> Value {
    let Some(profile) = value.as_object_mut() else {
        return value;
    };
    for key in [
        "uid",
        "coin",
        "album_favorites",
        "level",
        "nextLevelExp",
        "album_favorites_max",
    ] {
        let normalized = profile.get(key).and_then(value_i64).unwrap_or(0);
        profile.insert(key.to_string(), json!(normalized));
    }
    if let Some(percent) = profile.get("expPercent").and_then(value_f64) {
        profile.insert("expPercent".into(), json!(percent));
    } else {
        profile.insert("expPercent".into(), json!(0.0));
    }
    for key in [
        "username",
        "email",
        "emailverified",
        "photo",
        "fname",
        "gender",
        "message",
        "s",
        "level_name",
        "exp",
    ] {
        let normalized = profile.get(key).map(value_wire_string).unwrap_or_default();
        profile.insert(key.to_string(), Value::String(normalized));
    }
    if !profile.get("badges").is_some_and(Value::is_array) {
        profile.insert("badges".into(), Value::Array(Vec::new()));
    }
    value
}

fn normalize_forum_value(mut value: Value) -> Value {
    let Some(forum) = value.as_object_mut() else {
        return value;
    };
    let total = forum.get("total").and_then(value_i64).unwrap_or(0);
    forum.insert("total".into(), json!(total));
    if let Some(comments) = forum.get_mut("list").and_then(Value::as_array_mut) {
        for comment in comments {
            normalize_comment_value(comment);
        }
    } else {
        forum.insert("list".into(), Value::Array(Vec::new()));
    }
    value
}

fn normalize_favorite_value(mut value: Value) -> Value {
    let Some(favorite) = value.as_object_mut() else {
        return value;
    };
    let total = favorite.get("total").and_then(value_i64).unwrap_or(0);
    favorite.insert("total".into(), json!(total));
    if !favorite.get("list").is_some_and(Value::is_array) {
        favorite.insert("list".into(), Value::Array(Vec::new()));
    }
    if let Some(folders) = favorite
        .get_mut("folder_list")
        .and_then(Value::as_array_mut)
    {
        for folder in folders {
            let Some(folder) = folder.as_object_mut() else {
                continue;
            };
            for key in ["FID", "UID"] {
                let normalized = folder.get(key).and_then(value_i64).unwrap_or(0);
                folder.insert(key.to_string(), json!(normalized));
            }
            let name = folder
                .get("name")
                .map(value_wire_string)
                .unwrap_or_default();
            folder.insert("name".into(), Value::String(name));
        }
    } else {
        favorite.insert("folder_list".into(), Value::Array(Vec::new()));
    }
    value
}

fn normalize_comment_value(value: &mut Value) {
    let Some(comment) = value.as_object_mut() else {
        return;
    };
    for key in ["CID", "UID", "likes", "parent_CID", "spoiler"] {
        let normalized = comment.get(key).and_then(value_i64).unwrap_or(0);
        comment.insert(key.to_string(), json!(normalized));
    }
    if comment.get("AID").is_some_and(|value| !value.is_null()) {
        let aid = comment.get("AID").and_then(value_i64).unwrap_or(0);
        comment.insert("AID".into(), json!(aid));
    }
    for key in [
        "username",
        "nickname",
        "gender",
        "update_at",
        "addtime",
        "name",
        "content",
        "photo",
    ] {
        let normalized = comment.get(key).map(value_wire_string).unwrap_or_default();
        comment.insert(key.to_string(), Value::String(normalized));
    }
    let is_liked = comment
        .get("is_liked")
        .or_else(|| comment.get("liked"))
        .is_some_and(value_bool);
    comment.insert("is_liked".into(), json!(is_liked));
    let expinfo = comment
        .entry("expinfo")
        .or_insert_with(|| Value::Object(serde_json::Map::new()));
    if let Some(exp) = expinfo.as_object_mut() {
        for key in ["level", "nextLevelExp", "uid"] {
            let normalized = exp.get(key).and_then(value_i64).unwrap_or(0);
            exp.insert(key.to_string(), json!(normalized));
        }
        let percent = exp.get("expPercent").and_then(value_f64).unwrap_or(0.0);
        exp.insert("expPercent".into(), json!(percent));
        for key in ["level_name", "exp"] {
            let normalized = exp.get(key).map(value_wire_string).unwrap_or_default();
            exp.insert(key.to_string(), Value::String(normalized));
        }
        if !exp.get("badges").is_some_and(Value::is_array) {
            exp.insert("badges".into(), Value::Array(Vec::new()));
        }
    }
    if let Some(replies) = comment.get_mut("replys").and_then(Value::as_array_mut) {
        for reply in replies {
            normalize_comment_value(reply);
        }
    } else {
        comment.insert("replys".into(), Value::Array(Vec::new()));
    }
}

fn value_i64(value: &Value) -> Option<i64> {
    value
        .as_i64()
        .or_else(|| value.as_str()?.trim().parse::<i64>().ok())
}

fn value_f64(value: &Value) -> Option<f64> {
    value
        .as_f64()
        .or_else(|| value.as_str()?.trim().parse::<f64>().ok())
}

fn value_wire_string(value: &Value) -> String {
    match value {
        Value::String(value) => value.clone(),
        Value::Null => String::new(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        Value::Array(_) | Value::Object(_) => value.to_string(),
    }
}

fn value_bool(value: &Value) -> bool {
    value.as_bool().unwrap_or_else(|| {
        value.as_i64().is_some_and(|value| value != 0)
            || value
                .as_str()
                .is_some_and(|value| matches!(value.trim(), "1" | "true"))
    })
}

fn parse_web_url(url: &str) -> BackendResult<reqwest::Url> {
    let parsed = reqwest::Url::parse(url.trim())
        .map_err(|error| BackendError::Config(format!("invalid WebDAV URL: {error}")))?;
    if !matches!(parsed.scheme(), "http" | "https") || parsed.host_str().is_none() {
        return Err(BackendError::Config(
            "WebDAV URL must use http or https".into(),
        ));
    }
    Ok(parsed)
}

fn unix_timestamp() -> BackendResult<u64> {
    Ok(SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| BackendError::Config(format!("system clock: {error}")))?
        .as_secs())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn api_errors_are_not_reported_as_valid_payloads() {
        let error = decode_api_body(
            1,
            r#"{"code":403,"data":"","error_msg":"forbidden"}"#.into(),
        )
        .unwrap_err();
        assert!(matches!(
            error,
            BackendError::Api {
                code: 403,
                ref message
            } if message == "forbidden"
        ));
    }

    #[test]
    fn api_body_accepts_direct_json_and_plaintext_data() {
        let direct = decode_api_body(
            1,
            r#"{"code":200,"data":{"status":"ok"},"error_msg":""}"#.into(),
        )
        .unwrap();
        assert_eq!(direct["status"], "ok");

        let plaintext =
            decode_api_body(1, r#"{"code":200,"data":"签到成功","error_msg":""}"#.into()).unwrap();
        assert_eq!(plaintext, "签到成功");
    }

    #[test]
    fn album_json_is_normalized_for_flutter_entities() {
        let album = normalize_album_value(json!({
            "id": 7,
            "name": "fixture",
            "series_id": "0",
            "total_views": "12",
            "liked": 1,
            "is_favorite": "false",
            "author": [],
            "images": [],
            "series": [],
            "tags": [],
            "works": [],
            "related_list": []
        }));
        assert_eq!(album["series_id"], 0);
        assert_eq!(album["total_views"], 12);
        assert_eq!(album["likes"], 0);
        assert_eq!(album["comment_total"], 0);
        assert_eq!(album["liked"], true);
        assert_eq!(album["is_favorite"], false);
    }

    #[test]
    fn chapter_json_is_normalized_for_flutter_entities() {
        let chapter = normalize_chapter_value(json!({
            "id": "8",
            "series_id": "7",
            "series": [],
            "images": ["00001.jpg"],
            "tags": null,
            "name": null,
            "liked": "1",
            "is_favorite": 0
        }));
        assert_eq!(chapter["id"], 8);
        assert_eq!(chapter["series_id"], 7);
        assert_eq!(chapter["tags"], "");
        assert_eq!(chapter["name"], "");
        assert_eq!(chapter["liked"], true);
        assert_eq!(chapter["is_favorite"], false);
    }

    #[test]
    fn self_info_and_comments_are_normalized_for_flutter_entities() {
        let profile = normalize_self_info_value(json!({
            "uid": "12",
            "coin": "3",
            "album_favorites": "4",
            "level": "5",
            "nextLevelExp": "600",
            "album_favorites_max": "20",
            "expPercent": "12.5",
            "badges": []
        }));
        assert_eq!(profile["uid"], 12);
        assert_eq!(profile["nextLevelExp"], 600);
        assert_eq!(profile["expPercent"], 12.5);

        let forum = normalize_forum_value(json!({
            "total": "1",
            "list": [{
                "AID": "7",
                "CID": "8",
                "UID": "9",
                "likes": "2",
                "parent_CID": "0",
                "spoiler": "0",
                "update_at": 123,
                "expinfo": {
                    "level": "3",
                    "nextLevelExp": "400",
                    "uid": "9",
                    "expPercent": "8.5",
                    "badges": []
                },
                "replys": [{
                    "CID": "10",
                    "UID": "11",
                    "likes": "1",
                    "parent_CID": "8",
                    "spoiler": "0",
                    "expinfo": {}
                }]
            }]
        }));
        assert_eq!(forum["total"], 1);
        assert_eq!(forum["list"][0]["CID"], 8);
        assert_eq!(forum["list"][0]["AID"], 7);
        assert_eq!(forum["list"][0]["update_at"], "123");
        assert_eq!(forum["list"][0]["expinfo"]["level"], 3);
        assert_eq!(forum["list"][0]["replys"][0]["CID"], 10);
    }

    #[test]
    fn favorite_json_is_normalized_for_flutter_folder_items() {
        let favorite = normalize_favorite_value(json!({
            "total": "2",
            "list": [],
            "folder_list": [{
                "FID": "8",
                "UID": "9",
                "name": "folder"
            }]
        }));
        assert_eq!(favorite["total"], 2);
        assert_eq!(favorite["folder_list"][0]["FID"], 8);
        assert_eq!(favorite["folder_list"][0]["UID"], 9);
    }

    #[test]
    fn favorite_folder_forms_include_required_action_type() {
        assert_eq!(
            favorite_folder_form("add", Some("new folder"), None, None),
            json!({"type": "add", "folder_name": "new folder"})
        );
        assert_eq!(
            favorite_folder_form("edit", Some("renamed"), Some(8), None),
            json!({"type": "edit", "folder_name": "renamed", "folder_id": 8})
        );
        assert_eq!(
            favorite_folder_form("del", None, Some(8), None),
            json!({"type": "del", "folder_id": 8})
        );
        assert_eq!(
            favorite_folder_form("move", None, Some(8), Some(7)),
            json!({"type": "move", "folder_id": 8, "aid": 7})
        );
    }

    #[test]
    fn comment_forms_match_the_mobile_api_contract() {
        assert_eq!(
            comment_form(42, "hello", None),
            json!({"aid": 42, "comment": "hello"})
        );
        assert_eq!(
            comment_form(42, "reply", Some(7)),
            json!({"aid": 42, "comment": "reply", "comment_id": 7})
        );
    }

    #[test]
    fn write_responses_expose_api_failures() {
        assert!(ensure_write_action_succeeded(json!({"status": "ok", "msg": ""})).is_ok());
        let error = ensure_write_action_succeeded(json!({
            "status": "fail",
            "msg": "not logged in"
        }))
        .unwrap_err();
        assert!(matches!(
            error,
            BackendError::Api {
                code: 0,
                ref message
            } if message == "not logged in"
        ));
    }

    #[test]
    fn comment_like_upstream_limit_is_detected() {
        assert!(is_comment_like_upstream_limited(
            "勿短時間重複留言，請重新確認留言內容。"
        ));
        assert!(is_comment_like_upstream_limited(
            "勿短时间重复留言，请重新确认留言内容。"
        ));
        assert!(!is_comment_like_upstream_limited("网络连接失败"));
    }

    #[test]
    fn album_published_queries_remove_leading_labels_and_try_title_parts() {
        let queries = album_published_search_queries("[作者] (C105) 豚小屋 / Oyster House");

        assert_eq!(queries[0], "Oyster House");
        assert_eq!(queries[1], "[作者] (C105) 豚小屋 / Oyster House");
        assert!(queries.len() <= 2);
        assert!(queries
            .iter()
            .any(|query| query == "豚小屋" || query == "Oyster House"));
    }

    #[test]
    fn album_published_date_uses_the_matching_search_result() {
        let value = json!({
            "content": [
                {"id": "42", "adddate": "2024-01-01"},
                {"id": 1214196, "adddate": "2025-09-12"},
                {"id": "1214197", "adddate": "2025-09-13"}
            ]
        });

        assert_eq!(
            album_published_at_from_search(&value, 1214196),
            "2025-09-12"
        );
        assert_eq!(album_published_at_from_search(&value, 999), "");
    }

    #[test]
    fn image_search_normalizes_schema_2_2_results() {
        let value = normalize_image_search_response(json!({
            "schema_version": "2.2",
            "status": "complete",
            "result_id": "abc",
            "timing": {"total_ms": 1234},
            "results": [{
                "score": 93.5,
                "path_segments": [{
                    "source_key": "jmcomic",
                    "external_id": "1214196",
                    "language": "chinese",
                    "page_no": 12,
                    "source_url": "https://example.test/photo/1214196",
                    "thumbnail_url": "https://example.test/thumb.jpg",
                    "metadata": {
                        "title": {
                            "primary": "Fixture Comic",
                            "japanese_or_alias": "Fixture Alias"
                        },
                        "source": {
                            "key": "jmcomic",
                            "id": "1214196"
                        }
                    }
                }]
            }]
        }));

        assert_eq!(value["result_id"], "abc");
        assert_eq!(value["elapsed_ms"], 1234);
        assert_eq!(value["hits"][0]["source"], "jmcomic");
        assert_eq!(value["hits"][0]["external_id"], "1214196");
        assert_eq!(value["hits"][0]["title"], "Fixture Comic");
        assert_eq!(value["hits"][0]["title_alt"], "Fixture Alias");
        assert_eq!(value["hits"][0]["language"], "zh");
        assert_eq!(value["hits"][0]["similarity"], 93.5);
    }

    #[test]
    fn image_search_accepts_legacy_data_results() {
        let value = normalize_image_search_response(json!({
            "id": "legacy",
            "data": [{
                "source": "jmcomic",
                "title": "Legacy Comic",
                "language": "cn",
                "page": 7,
                "subjectPath": "/photo/7654321",
                "previewImageUrl": "https://example.test/legacy.jpg",
                "similarity": 88.0
            }]
        }));

        assert_eq!(value["result_id"], "legacy");
        assert_eq!(value["hits"][0]["source"], "jmcomic");
        assert_eq!(value["hits"][0]["external_id"], "7654321");
        assert_eq!(value["hits"][0]["title"], "Legacy Comic");
        assert_eq!(value["hits"][0]["similarity"], 88.0);
    }

    #[test]
    fn image_search_filters_low_confidence_and_prefers_verified_jm_results() {
        let value = normalize_image_search_response(json!({
            "results": [
                {
                    "score": 60.0,
                    "path_segments": [{
                        "source_key": "nhentai",
                        "external_id": "99",
                        "metadata": {"title": {"primary": "Other source"}}
                    }]
                },
                {
                    "score": 55.0,
                    "path_segments": [{
                        "source_key": "jmcomic",
                        "external_id": "1214196",
                        "metadata": {"title": {"primary": "JM match"}}
                    }]
                },
                {
                    "score": 12.0,
                    "path_segments": [{
                        "source_key": "nhentai",
                        "external_id": "100",
                        "metadata": {"title": {"primary": "Low confidence"}}
                    }]
                }
            ]
        }));

        assert_eq!(value["hits"].as_array().unwrap().len(), 2);
        assert_eq!(value["hits"][0]["source"], "jmcomic");
        assert_eq!(value["hits"][1]["source"], "nhentai");
    }

    #[test]
    fn image_search_upload_is_resized_before_upload() {
        let source = image::RgbImage::from_fn(2400, 1200, |x, y| {
            image::Rgb([(x % 255) as u8, (y % 255) as u8, 96])
        });
        let mut encoded = Vec::new();
        image::DynamicImage::ImageRgb8(source)
            .write_to(&mut Cursor::new(&mut encoded), image::ImageFormat::Png)
            .unwrap();
        let root = std::env::temp_dir().join(format!(
            "jmcomic3-image-search-upload-{}",
            std::process::id()
        ));
        std::fs::create_dir_all(&root).unwrap();
        let path = root.join("large.png");
        std::fs::write(&path, encoded).unwrap();

        let prepared = prepare_image_search_upload(&path).unwrap();
        let decoded = image::load_from_memory(&prepared).unwrap();
        assert!(decoded.width() <= IMAGE_SEARCH_MAX_EDGE);
        assert!(decoded.height() <= IMAGE_SEARCH_MAX_EDGE);

        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn categories_json_is_normalized_for_search_filters() {
        let categories = normalize_categories_value(json!({
            "categories": [{
                "id": "3",
                "name": 4,
                "slug": null,
                "total_albums": "12"
            }],
            "blocks": [{
                "title": 5,
                "items": ["tag", {"slug": "tag-2"}]
            }]
        }));
        assert_eq!(categories["categories"][0]["id"], 3);
        assert_eq!(categories["categories"][0]["name"], "4");
        assert_eq!(categories["categories"][0]["slug"], "3");
        assert_eq!(categories["categories"][0]["total_albums"], 12);
        assert_eq!(categories["blocks"][0]["title"], "5");
        assert_eq!(categories["blocks"][0]["content"][0], "tag");
        assert_eq!(categories["blocks"][0]["content"][1], "tag-2");
    }
}
