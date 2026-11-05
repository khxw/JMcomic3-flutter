use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use reqwest::cookie::{CookieStore, Jar};
use reqwest::{Client, Method, RequestBuilder, StatusCode};
use serde_json::{json, Value};

use crate::config::JmClientConfig;
use crate::crypto::{decrypt_api_data, md5_hex};
use crate::error::{BackendError, BackendResult};
use crate::models::{JmApiResponse, SearchSort};

const APP_TOKEN_SECRET: &str = "18comicAPP";
const APP_TOKEN_SECRET_2: &str = "18comicAPPContent";

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
    AlbumComment,
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
            Self::AlbumComment => "/ajax/album_comment",
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
            .timeout(config.request_timeout);
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
        self.api_json(
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
        self.api_json(
            Method::POST,
            ApiPath::FavoriteFolder,
            None,
            Some(json!({ "folder_name": folder_name.trim() })),
        )
        .await
    }

    pub async fn delete_favorite_folder(&self, folder_id: i64) -> BackendResult<Value> {
        if folder_id <= 0 {
            return Err(BackendError::Config("folder id must be positive".into()));
        }
        self.api_json(
            Method::POST,
            ApiPath::FavoriteFolder,
            None,
            Some(json!({ "folder_id": folder_id })),
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
        self.api_json(
            Method::POST,
            ApiPath::FavoriteFolder,
            None,
            Some(json!({
                "folder_id": folder_id,
                "folder_name": folder_name.trim(),
            })),
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
        self.api_json(
            Method::POST,
            ApiPath::FavoriteFolder,
            None,
            Some(json!({
                "aid": comic_id,
                "folder_id": folder_id,
            })),
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
        self.api_json(
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
        let form = if let Some(comment_id) = parent_comment_id {
            json!({
                "video_id": album_id,
                "comment": comment,
                "comment_id": comment_id,
                "is_reply": 1,
                "forum_subject": 1,
            })
        } else {
            json!({
                "video_id": album_id,
                "comment": comment,
                "originator": "",
                "status": "true",
            })
        };
        self.api_json(Method::POST, ApiPath::AlbumComment, None, Some(form))
            .await
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

    pub async fn measure_image_host(&self, host: &str) -> BackendResult<u64> {
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
        let _ = response.bytes().await?;
        Ok(started.elapsed().as_millis().max(1) as u64)
    }

    pub async fn measure_api_host(&self, host: &str) -> BackendResult<u64> {
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
        let _ = response.bytes().await?;
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
                    let retryable =
                        status == StatusCode::TOO_MANY_REQUESTS || status.is_server_error();
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
    let encrypted = response
        .data
        .as_str()
        .ok_or_else(|| BackendError::InvalidResponse("API data is not a string".into()))?;
    let decrypted = decrypt_api_data(timestamp, encrypted)?;
    Ok(serde_json::from_str(&decrypted)?)
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
