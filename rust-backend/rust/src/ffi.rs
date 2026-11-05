use std::collections::{BTreeSet, HashSet};
use std::ffi::{c_char, CStr, CString};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

use serde_json::{json, Value};
use tokio::runtime::Runtime;

use crate::contract::{InvokeRequest, InvokeResponse};
use crate::download::{album_dir, chapter_dir, manager_shared, DownloadControl, DownloadManager};
use crate::export::{export_album, ExportFormat};
use crate::history::HistoryStore;
use crate::import::{import_album_archive, import_album_directory};
use crate::media::MediaCache;
use crate::models::SearchSort;
use crate::store::PropertyStore;
use crate::{BackendResult, JmClient, JmClientConfig};

static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static STATE: OnceLock<Mutex<Option<BackendState>>> = OnceLock::new();
const FALLBACK_API_HOSTS: &[&str] = &[
    "www.cdnhjk.net",
    "www.cdngwc.club",
    "www.cdngwc.net",
    "www.cdngwc.cc",
    "www.cdnbea.net",
    "www.cdnhth.net",
    "www.cdnhth.club",
];
const API_HOST_LIST_URLS: &[&str] = &[
    "https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt",
    "https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt",
    "https://rup4a04-c03.tos-cn-beijing.bytepluses.com.cn/newsvr-2025.txt",
];

#[derive(Clone)]
struct BackendState {
    client: JmClient,
    store: Arc<PropertyStore>,
    history: Arc<HistoryStore>,
    media: Arc<MediaCache>,
    downloads: Arc<DownloadManager>,
}

impl BackendState {
    fn open(root: &Path) -> BackendResult<Self> {
        std::fs::create_dir_all(root)?;
        let store = Arc::new(PropertyStore::open(root)?);
        let custom_download_root = stored_download_root(&store)?;
        let download_root = if custom_download_root.trim().is_empty() {
            root.join("downloads")
        } else {
            PathBuf::from(custom_download_root.trim())
        };
        let client = client_from_store(&store)?;
        Ok(Self {
            client,
            store,
            history: Arc::new(HistoryStore::open(root)?),
            media: Arc::new(MediaCache::open(&root.join("image_cache"))?),
            downloads: manager_shared(root, download_root)?,
        })
    }
}

fn runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("failed to initialize backend runtime")
    })
}

fn state_slot() -> &'static Mutex<Option<BackendState>> {
    STATE.get_or_init(|| Mutex::new(None))
}

fn initialize_state(root: &Path) -> Result<(), String> {
    let state = BackendState::open(root).map_err(|error| error.to_string())?;
    let mut slot = state_slot()
        .lock()
        .map_err(|_| "backend state lock poisoned".to_string())?;
    *slot = Some(state);
    Ok(())
}

fn state() -> Result<BackendState, String> {
    let mut slot = state_slot()
        .lock()
        .map_err(|_| "backend state lock poisoned".to_string())?;
    if slot.is_none() {
        let root = std::env::var_os("JMCOMIC3_BACKEND_DATA_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                std::env::current_dir()
                    .unwrap_or_else(|_| PathBuf::from("."))
                    .join("jmcomic3-backend-data")
            });
        *slot = Some(BackendState::open(&root).map_err(|error| error.to_string())?);
    }
    slot.as_ref()
        .cloned()
        .ok_or_else(|| "backend state unavailable".to_string())
}

fn reset_client() -> Result<(), String> {
    let mut slot = state_slot()
        .lock()
        .map_err(|_| "backend state lock poisoned".to_string())?;
    if slot.is_none() {
        let root = std::env::var_os("JMCOMIC3_BACKEND_DATA_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                std::env::current_dir()
                    .unwrap_or_else(|_| PathBuf::from("."))
                    .join("jmcomic3-backend-data")
            });
        *slot = Some(BackendState::open(&root).map_err(|error| error.to_string())?);
    }
    let state = slot
        .as_mut()
        .ok_or_else(|| "backend state unavailable".to_string())?;
    state.client = client_from_store(&state.store).map_err(|error| error.to_string())?;
    Ok(())
}

fn client_from_store(store: &PropertyStore) -> BackendResult<JmClient> {
    let mut config = JmClientConfig::default();
    let api_host = store.load("api_host")?;
    if !api_host.trim().is_empty() {
        config.api_host = api_host;
    }
    let cdn_host = store.load("cdn_host")?;
    if !cdn_host.trim().is_empty() {
        config.image_host = cdn_host;
    }
    let proxy = store.load("proxy")?;
    if !proxy.trim().is_empty() {
        config.proxy_url = Some(proxy);
    }
    let client = JmClient::new(config)?;
    let cookie = store.load("cookie")?;
    if !cookie.trim().is_empty() {
        client.add_cookie_header(&cookie, &client.api_base_url());
    }
    Ok(client)
}

fn stored_download_root(store: &PropertyStore) -> BackendResult<String> {
    let current = store.load("download_root")?;
    if !current.trim().is_empty() {
        return Ok(current);
    }
    store.load("download_and_export_to")
}

#[no_mangle]
pub extern "C" fn init_ffi(path: *const c_char) {
    let root = if path.is_null() {
        None
    } else {
        Some(
            unsafe { CStr::from_ptr(path) }
                .to_string_lossy()
                .into_owned(),
        )
    };
    let root = root
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    if let Err(error) = initialize_state(&root) {
        tracing::error!(%error, "backend state initialization failed");
    }
}

#[no_mangle]
pub extern "C" fn invoke_ffi(request: *const c_char) -> *mut c_char {
    let response = std::panic::catch_unwind(|| {
        if request.is_null() {
            return InvokeResponse::error("request pointer is null");
        }
        let request = unsafe { CStr::from_ptr(request) }
            .to_string_lossy()
            .into_owned();
        let request = match serde_json::from_str::<InvokeRequest>(&request) {
            Ok(request) => request,
            Err(error) => {
                return InvokeResponse::error(format!("invalid request JSON: {error}"));
            }
        };
        runtime().block_on(dispatch(request))
    })
    .unwrap_or_else(|_| InvokeResponse::error("backend request panicked"));

    let sanitized = response.to_json().replace('\0', "");
    match CString::new(sanitized) {
        Ok(value) => value.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn free_str_ffi(pointer: *mut c_char) {
    if !pointer.is_null() {
        drop(CString::from_raw(pointer));
    }
}

async fn dispatch(request: InvokeRequest) -> InvokeResponse {
    let state = match state() {
        Ok(state) => state,
        Err(error) => return InvokeResponse::error(error),
    };
    let params = request.decoded_params();
    match request.method.as_str() {
        "init_dart" => InvokeResponse::success_text(""),
        "ping_backend" => InvokeResponse::success_value(&json!({"ok": true})),
        "load_property" => {
            let key = string_value(&params).unwrap_or_default();
            match state.store.load(&key) {
                Ok(value) => InvokeResponse::success_text(value),
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        "save_property" => {
            let key = string_param(&params, "k").unwrap_or_default();
            let value = string_param(&params, "v").unwrap_or_default();
            match state.store.save(&key, &value) {
                Ok(()) => InvokeResponse::success_text(""),
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        "config_links" => property_json_response(&state, "config_links"),
        "app_config" => property_json_response(&state, "app_config"),
        "categories" => result_value(state.client.categories().await),
        "games" => {
            let page = int_param(&params, "page").unwrap_or(1).max(1) as u32;
            result_value(state.client.games(page).await)
        }
        "load_api_host" => {
            property_response_with_default(&state, "api_host", &state.client.config().api_host)
        }
        "load_cdn_host" => {
            property_response_with_default(&state, "cdn_host", &state.client.config().image_host)
        }
        "load_api_host_list" => match cached_api_host_list(&state) {
            Ok(hosts) => InvokeResponse::success_value(&json!(hosts)),
            Err(error) => InvokeResponse::error(error),
        },
        "refresh_api_host_list" => refresh_api_host_list(&state).await,
        "save_api_host" => {
            let host = string_value(&params).unwrap_or_default();
            let config = JmClientConfig {
                api_host: host,
                ..JmClientConfig::default()
            }
            .validated();
            match config {
                Ok(config) => match state.store.save("api_host", &config.api_host) {
                    Ok(()) => match reset_client() {
                        Ok(()) => InvokeResponse::success_text(""),
                        Err(error) => InvokeResponse::error(error),
                    },
                    Err(error) => InvokeResponse::error(error.to_string()),
                },
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        "save_cdn_host" => {
            let host = string_value(&params).unwrap_or_default();
            let config = JmClientConfig {
                image_host: host,
                ..JmClientConfig::default()
            }
            .validated();
            match config {
                Ok(config) => match state.store.save("cdn_host", &config.image_host) {
                    Ok(()) => match reset_client() {
                        Ok(()) => InvokeResponse::success_text(""),
                        Err(error) => InvokeResponse::error(error),
                    },
                    Err(error) => InvokeResponse::error(error.to_string()),
                },
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        "set_proxy" => {
            let proxy = string_value(&params).unwrap_or_default();
            let config = JmClientConfig {
                proxy_url: (!proxy.trim().is_empty()).then_some(proxy.clone()),
                ..JmClientConfig::default()
            };
            match JmClient::new(config) {
                Ok(_) => match state.store.save("proxy", proxy.trim()) {
                    Ok(()) => match reset_client() {
                        Ok(()) => InvokeResponse::success_text(""),
                        Err(error) => InvokeResponse::error(error),
                    },
                    Err(error) => InvokeResponse::error(error.to_string()),
                },
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        "get_proxy" => property_response(&state, "proxy"),
        "ping_server" => {
            let host = string_value(&params)
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_else(|| state.client.config().api_host.clone());
            result_text(
                state
                    .client
                    .measure_api_host(&host)
                    .await
                    .map(|value| value.to_string()),
            )
        }
        "ping_cdn" => {
            let host = string_value(&params)
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_else(|| state.client.config().image_host.clone());
            result_text(
                state
                    .client
                    .measure_image_host(&host)
                    .await
                    .map(|value| value.to_string()),
            )
        }
        "http_get" => {
            let url = string_value(&params).unwrap_or_default();
            result_text(state.client.http_get_text(&url).await)
        }
        "clean_all_cache" => match state.media.clear() {
            Ok(()) => InvokeResponse::success_text(""),
            Err(error) => InvokeResponse::error(error.to_string()),
        },
        "getHomeDir" => InvokeResponse::success_text(path_text(
            state.media.root().parent().unwrap_or(state.media.root()),
        )),
        "mkdirs" => {
            let path = string_value(&params).unwrap_or_default();
            if path.trim().is_empty() {
                InvokeResponse::error("mkdirs path is empty")
            } else {
                match std::fs::create_dir_all(path.trim()) {
                    Ok(()) => InvokeResponse::success_text(""),
                    Err(error) => InvokeResponse::error(format!("create directory: {error}")),
                }
            }
        }
        "get_pro_server_name" => property_response(&state, "pro_server_name"),
        "set_pro_server_name" => {
            let name = string_value(&params).unwrap_or_default();
            match state.store.save("pro_server_name", name.trim()) {
                Ok(()) => InvokeResponse::success_text(""),
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        "is_pro" => InvokeResponse::success_value(&pro_info()),
        "pro_info_all" => InvokeResponse::success_value(&json!({
            "pro_info_af": pro_info(),
            "pro_info_pat": {
                "is_pro": true,
                "pat_id": "",
                "bind_uid": "",
                "request_delete": 0,
                "re_bind": 0,
                "error_type": 0,
                "error_msg": "",
                "access_key": ""
            }
        })),
        "reload_pro" | "reload_pat_account" | "clear_pat" => InvokeResponse::success_text(""),
        "input_cd_key" => {
            let key = string_value(&params).unwrap_or_default();
            if key.trim().is_empty() {
                InvokeResponse::error("CD key is empty")
            } else {
                InvokeResponse::success_text("")
            }
        }
        "check_pat" => {
            let access_key = string_value(&params).unwrap_or_default();
            if access_key.trim().is_empty() {
                InvokeResponse::error("PAT access key is empty")
            } else {
                InvokeResponse::success_text(
                    json!({
                        "email": "",
                        "bind_user": "",
                        "fd": true,
                        "re_bind": 0
                    })
                    .to_string(),
                )
            }
        }
        "bind_pat" => {
            let access_key = string_param(&params, "access_key").unwrap_or_default();
            let username = string_param(&params, "username").unwrap_or_default();
            if access_key.trim().is_empty() || username.trim().is_empty() {
                InvokeResponse::error("PAT access key and username are required")
            } else {
                InvokeResponse::success_text("")
            }
        }
        "load_download_thread" => {
            let count = state
                .store
                .load("download_thread")
                .ok()
                .and_then(|value| value.parse::<i64>().ok())
                .unwrap_or(3)
                .clamp(1, 8);
            InvokeResponse::success_text(count.to_string())
        }
        "set_download_thread" => {
            let count = match &params {
                Value::String(value) => value.trim().parse::<i64>().unwrap_or(0),
                Value::Number(value) => value.as_i64().unwrap_or(0),
                Value::Object(_) => int_param(&params, "count").unwrap_or(0),
                _ => 0,
            };
            if !(1..=8).contains(&count) {
                InvokeResponse::error("download thread count must be between 1 and 8")
            } else {
                match state.store.save("download_thread", &count.to_string()) {
                    Ok(()) => InvokeResponse::success_text(""),
                    Err(error) => InvokeResponse::error(error.to_string()),
                }
            }
        }
        "comics" => {
            let slug = string_param(&params, "categories_slug").unwrap_or_default();
            let sort = string_param(&params, "sort_by").unwrap_or_default();
            let page = int_param(&params, "page").unwrap_or(1).max(1) as u32;
            result_value(state.client.comics(&slug, &sort, page).await)
        }
        "album" => match int_param(&params, "id") {
            Ok(id) => result_value(state.client.album(id).await),
            Err(error) => InvokeResponse::error(error),
        },
        "chapter" => match int_param(&params, "id") {
            Ok(id) => result_value(state.client.chapter(id).await),
            Err(error) => InvokeResponse::error(error),
        },
        "comic_search" => {
            let keyword = string_param(&params, "search_query").unwrap_or_default();
            if keyword.trim().is_empty() {
                return InvokeResponse::error("search_query is required");
            }
            let page = int_param(&params, "page").unwrap_or(1).max(1) as u32;
            let sort = string_param(&params, "sort_by")
                .and_then(|value| value.parse::<SearchSort>().ok())
                .unwrap_or(SearchSort::Latest);
            match state.client.search(&keyword, page, sort).await {
                Ok(value) => {
                    let _ = state.history.record_search(&keyword);
                    InvokeResponse::success_value(&value)
                }
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        "week" => result_value(state.client.weekly_info().await),
        "week_filter" => {
            let category_id = string_param(&params, "category_id").unwrap_or_default();
            let type_id = string_param(&params, "type_id").unwrap_or_default();
            if category_id.trim().is_empty() || type_id.trim().is_empty() {
                InvokeResponse::error("week_filter requires category_id and type_id")
            } else {
                result_value(state.client.weekly(&category_id, &type_id).await)
            }
        }
        "pre_login" => pre_login_response(&state).await,
        "login" => {
            let username = string_param(&params, "username").unwrap_or_default();
            let password = string_param(&params, "password").unwrap_or_default();
            login_response(&state, &username, &password).await
        }
        "logout" => {
            for key in ["cookie", "last_login_username", "load_username"] {
                let _ = state.store.save(key, "");
            }
            match reset_client() {
                Ok(()) => InvokeResponse::success_text(""),
                Err(error) => InvokeResponse::error(error),
            }
        }
        "load_username" => property_response(&state, "load_username"),
        "loadLastLoginUsername" => property_response(&state, "last_login_username"),
        "load_password" => property_response(&state, "load_password"),
        "favorite" | "favorites" => {
            let folder_id = int_param(&params, "folder_id").unwrap_or(0);
            let page = int_param(&params, "page").unwrap_or(1).max(1) as u32;
            let sort = string_param(&params, "o")
                .and_then(|value| value.parse::<SearchSort>().ok())
                .unwrap_or(SearchSort::Latest);
            result_value(state.client.favorite(folder_id, page, sort).await)
        }
        "set_favorite" => match int_param(&params, "id") {
            Ok(id) => result_value(state.client.toggle_favorite(id).await),
            Err(error) => InvokeResponse::error(error),
        },
        "create_favorite_folder" => {
            let name = value_or_param_string(&params, "folder_name").unwrap_or_default();
            result_value(state.client.create_favorite_folder(&name).await)
        }
        "delete_favorite_folder" => {
            let folder_id = value_or_param_int(&params, "folder_id").unwrap_or(0);
            result_value(state.client.delete_favorite_folder(folder_id).await)
        }
        "rename_favorite_folder" => {
            let (folder_id, name) = match &params {
                Value::Array(values) if values.len() >= 2 => (
                    value_int(&values[0]).unwrap_or(0),
                    string_value(&values[1]).unwrap_or_default(),
                ),
                Value::Object(_) => (
                    value_or_param_int(&params, "folder_id").unwrap_or(0),
                    value_or_param_string(&params, "folder_name").unwrap_or_default(),
                ),
                _ => (0, String::new()),
            };
            result_value(state.client.rename_favorite_folder(folder_id, &name).await)
        }
        "comic_favorite_folder_move" => {
            let (comic_id, folder_id) = match &params {
                Value::Array(values) if values.len() >= 2 => (
                    value_int(&values[0]).unwrap_or(0),
                    value_int(&values[1]).unwrap_or(-1),
                ),
                Value::Object(_) => (
                    value_or_param_int(&params, "comic_id")
                        .or_else(|| value_or_param_int(&params, "aid"))
                        .unwrap_or(0),
                    value_or_param_int(&params, "folder_id").unwrap_or(-1),
                ),
                _ => (0, -1),
            };
            result_value(
                state
                    .client
                    .move_comic_to_favorite_folder(comic_id, folder_id)
                    .await,
            )
        }
        "forum" => {
            let mode = string_param(&params, "mode");
            let album_id = optional_int_param(&params, "aid");
            let user_id = optional_int_param(&params, "uid");
            let page = int_param(&params, "page").unwrap_or(1).max(1) as u32;
            result_value(
                state
                    .client
                    .forum(mode.as_deref(), album_id, user_id, page)
                    .await,
            )
        }
        "comment" | "child_comment" => {
            let album_id = match int_param(&params, "aid") {
                Ok(id) => id,
                Err(error) => return InvokeResponse::error(error),
            };
            let comment = string_param(&params, "comment").unwrap_or_default();
            let parent = optional_int_param(&params, "comment_id");
            result_value(state.client.comment(album_id, &comment, parent).await)
        }
        "find_view_log" => match int_param(&params, "id") {
            Ok(id) => match state.history.find_view_log(id) {
                Ok(value) => InvokeResponse::success_value(&value.unwrap_or(Value::Null)),
                Err(error) => InvokeResponse::error(error.to_string()),
            },
            Err(error) => InvokeResponse::error(error),
        },
        "update_view_log" => {
            let id = match int_param(&params, "id") {
                Ok(id) => id,
                Err(error) => return InvokeResponse::error(error),
            };
            let chapter_id = match int_param(&params, "last_view_chapter_id") {
                Ok(id) => id,
                Err(error) => return InvokeResponse::error(error),
            };
            let page = int_param(&params, "last_view_page").unwrap_or(0);
            let viewed_at = int_param(&params, "viewed_at").ok().map(|value| {
                if value > 10_000_000_000 {
                    value / 1000
                } else {
                    value
                }
            });
            let album = match state.history.find_view_log(id) {
                Ok(Some(_)) => None,
                Ok(None) => state.client.album(id).await.ok(),
                Err(error) => return InvokeResponse::error(error.to_string()),
            };
            match state
                .history
                .update_view_log_at(id, chapter_id, page, album.as_ref(), viewed_at)
            {
                Ok(()) => InvokeResponse::success_text(""),
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        "page_view_log" => {
            let page = int_param(&params, "page").unwrap_or(1).max(1) as u32;
            match state.history.page_view_log(page) {
                Ok(value) => InvokeResponse::success_value(&value),
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        "delete_view_log_by_comic_id" => {
            match int_param(&params, "comic_id").or_else(|_| int_param(&params, "id")) {
                Ok(id) => match state.history.delete_view_log(id) {
                    Ok(()) => InvokeResponse::success_text(""),
                    Err(error) => InvokeResponse::error(error.to_string()),
                },
                Err(error) => InvokeResponse::error(error),
            }
        }
        "clear_view_log" => match state.history.clear_view_logs() {
            Ok(()) => InvokeResponse::success_text(""),
            Err(error) => InvokeResponse::error(error.to_string()),
        },
        "last_search_histories" => {
            let count = int_param(&params, "count")
                .or_else(|_| int_param(&params, "limit"))
                .unwrap_or(20)
                .max(0) as usize;
            match state.history.last_search_history(count) {
                Ok(values) => InvokeResponse::success_value(&Value::Array(values)),
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        "clear_all_search_log" => match state.history.clear_all_search_history() {
            Ok(()) => InvokeResponse::success_text(""),
            Err(error) => InvokeResponse::error(error.to_string()),
        },
        "clear_a_search_log" => {
            let query = string_value(&params).unwrap_or_default();
            match state.history.clear_search_history(&query) {
                Ok(()) => InvokeResponse::success_text(""),
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }

        "daily" => {
            let user_id = match int_param(&params, "uid").or_else(|_| int_param(&params, "user_id"))
            {
                Ok(id) => id,
                Err(error) => return InvokeResponse::error(error),
            };
            match state.client.daily_checkin(user_id).await {
                Ok(value) => {
                    let message = value.get("msg").and_then(Value::as_str).unwrap_or("已签到");
                    InvokeResponse::success_text(message)
                }
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        "all_downloads" => match state.downloads.all_json() {
            Ok(value) => InvokeResponse::success_value(&value),
            Err(error) => InvokeResponse::error(error.to_string()),
        },
        "download_album_by_id" => match int_param(&params, "id") {
            Ok(id) => match state.downloads.album_json(id) {
                Ok(value) => InvokeResponse::success_value(&value),
                Err(error) => InvokeResponse::error(error.to_string()),
            },
            Err(error) => InvokeResponse::error(error),
        },
        "download_by_id" => match int_param(&params, "id") {
            Ok(id) => match state.downloads.create_json(id) {
                Ok(value) => InvokeResponse::success_value(&value),
                Err(error) => InvokeResponse::error(error.to_string()),
            },
            Err(error) => InvokeResponse::error(error),
        },
        "create_download" => match state.downloads.create(&params) {
            Ok(record) => {
                let control = match state.downloads.new_task(record.id) {
                    Ok(control) => control,
                    Err(error) => return InvokeResponse::error(error.to_string()),
                };
                let task_state = state.clone();
                tokio::spawn(async move {
                    let result =
                        download_album(task_state.clone(), record.clone(), control.clone()).await;
                    task_state.downloads.finish_task(record.id, &control);
                    if let Err(error) = result {
                        let _ = task_state.downloads.mark_failed(record.id);
                        tracing::error!(album_id = record.id, %error, "download failed");
                    }
                });
                InvokeResponse::success_text("")
            }
            Err(error) => InvokeResponse::error(error.to_string()),
        },
        "pause_download" => match int_param(&params, "id") {
            Ok(id) => match state.downloads.pause_task(id) {
                Ok(()) => InvokeResponse::success_text(""),
                Err(error) => InvokeResponse::error(error.to_string()),
            },
            Err(error) => InvokeResponse::error(error),
        },
        "resume_download" => match int_param(&params, "id") {
            Ok(id) => {
                let record = match state.downloads.get(id) {
                    Ok(Some(record)) => record,
                    Ok(None) => return InvokeResponse::error("download album not found"),
                    Err(error) => return InvokeResponse::error(error.to_string()),
                };
                if record.dl_status == 1 {
                    return InvokeResponse::success_text("");
                }
                if let Ok(Some(_)) = state.downloads.current_task(id) {
                    return match state.downloads.resume_running_task(id) {
                        Ok(_) => InvokeResponse::success_text(""),
                        Err(error) => InvokeResponse::error(error.to_string()),
                    };
                }
                let control = match state.downloads.new_task(id) {
                    Ok(control) => control,
                    Err(error) => return InvokeResponse::error(error.to_string()),
                };
                if let Err(error) =
                    state
                        .downloads
                        .mark_running(id, record.image_count, record.dled_image_count)
                {
                    state.downloads.finish_task(id, &control);
                    return InvokeResponse::error(error.to_string());
                }
                let task_state = state.clone();
                tokio::spawn(async move {
                    let result =
                        download_album(task_state.clone(), record.clone(), control.clone()).await;
                    task_state.downloads.finish_task(record.id, &control);
                    if let Err(error) = result {
                        let _ = task_state.downloads.mark_failed(record.id);
                        tracing::error!(album_id = record.id, %error, "resumed download failed");
                    }
                });
                InvokeResponse::success_text("")
            }
            Err(error) => InvokeResponse::error(error),
        },
        "dl_image_by_chapter_id" => match int_param(&params, "id") {
            Ok(id) => match state.downloads.chapter_images_json(id, false) {
                Ok(value) => InvokeResponse::success_value(&value),
                Err(error) => InvokeResponse::error(error.to_string()),
            },
            Err(error) => InvokeResponse::error(error),
        },
        "dl_image_local_availability" => match int_param(&params, "id") {
            Ok(id) => match state.downloads.chapter_images_json(id, true) {
                Ok(value) => InvokeResponse::success_value(&value),
                Err(error) => InvokeResponse::error(error.to_string()),
            },
            Err(error) => InvokeResponse::error(error),
        },
        "delete_download" => match int_param(&params, "id") {
            Ok(id) => match state.downloads.delete(id) {
                Ok(()) => InvokeResponse::success_text(""),
                Err(error) => InvokeResponse::error(error.to_string()),
            },
            Err(error) => InvokeResponse::error(error),
        },
        "renew_all_downloads" => match state.downloads.renew_all() {
            Ok(()) => InvokeResponse::success_text(""),
            Err(error) => InvokeResponse::error(error.to_string()),
        },
        "get_download_and_export_to" => match state.store.load("download_root") {
            Ok(value) if !value.trim().is_empty() => InvokeResponse::success_text(value),
            Ok(_) => property_response(&state, "download_and_export_to"),
            Err(error) => InvokeResponse::error(error.to_string()),
        },
        "set_download_and_export_to" => {
            let path = string_value(&params).unwrap_or_default();
            let root = if path.trim().is_empty() {
                let root = state.media.root().parent().map(Path::to_path_buf);
                root.map(|root| root.join("downloads"))
            } else {
                Some(PathBuf::from(path.trim()))
            };
            match root {
                Some(root) => match state.downloads.set_root(root) {
                    Ok(()) => {
                        let current = state.store.save("download_root", path.trim());
                        let legacy = state.store.save("download_and_export_to", path.trim());
                        match (current, legacy) {
                            (Ok(()), Ok(())) => InvokeResponse::success_text(""),
                            (Err(error), _) | (_, Err(error)) => {
                                InvokeResponse::error(error.to_string())
                            }
                        }
                    }
                    Err(error) => InvokeResponse::error(error.to_string()),
                },
                None => InvokeResponse::error("unable to resolve default download root"),
            }
        }
        "jm_3x4_cover" => match int_param(&params, "id") {
            Ok(id) => result_text(state.media.cover_image(&state.client, id, false).await),
            Err(error) => InvokeResponse::error(error),
        },
        "jm_square_cover" => match int_param(&params, "id") {
            Ok(id) => result_text(state.media.cover_image(&state.client, id, true).await),
            Err(error) => InvokeResponse::error(error),
        },
        "jm_page_image" => {
            let id = match int_param(&params, "id") {
                Ok(id) => id,
                Err(error) => return InvokeResponse::error(error),
            };
            let image_name = string_param(&params, "image_name").unwrap_or_default();
            result_text(state.media.page_image(&state.client, id, &image_name).await)
        }
        "jm_photo_image" => {
            let image_name = string_value(&params).unwrap_or_default();
            result_text(state.media.photo_image(&state.client, &image_name).await)
        }
        "jm_page_image_batch" => page_image_batch(&state, &params).await,
        "image_size" => {
            let path = string_value(&params).unwrap_or_default();
            match state.media.image_size(&path) {
                Ok((width, height)) => {
                    InvokeResponse::success_value(&json!({"w": width, "h": height}))
                }
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        "export_jm_jpegs" => export_response(&state, &params, ExportFormat::Jpegs, false).await,
        "export_jm_zip" => export_response(&state, &params, ExportFormat::JmZip, false).await,
        "export_jm_zip_single" => export_response(&state, &params, ExportFormat::JmZip, true).await,
        "export_jm_jpegs_zip_single" => {
            export_response(&state, &params, ExportFormat::JpegsZip, true).await
        }
        "export_jm_jmi" => export_response(&state, &params, ExportFormat::Jmi, false).await,
        "export_jm_jmi_single" => export_response(&state, &params, ExportFormat::Jmi, true).await,
        "export_cbzs_zip_single" => export_response(&state, &params, ExportFormat::Cbz, true).await,
        "export_jm_pdf" | "export_jm_pdf2" => {
            export_response(&state, &params, ExportFormat::Pdf, false).await
        }
        "export_jm_epub" => export_response(&state, &params, ExportFormat::Epub, false).await,
        "export_jm_epub_single" => export_response(&state, &params, ExportFormat::Epub, true).await,
        "import_jm_zip" | "import_jm_jmi" => import_response(&state, &params, false).await,
        "import_jm_dir" => import_response(&state, &params, true).await,
        "sync_webdav" => webdav_response(&state, &params).await,
        other => InvokeResponse::error(format!("unsupported backend method: {other}")),
    }
}

async fn download_album(
    state: BackendState,
    record: crate::download::DownloadAlbumRecord,
    control: Arc<DownloadControl>,
) -> Result<(), String> {
    let root = state.downloads.root().map_err(|error| error.to_string())?;
    let album_directory = album_dir(&root, &record);
    std::fs::create_dir_all(&album_directory).map_err(|error| error.to_string())?;
    if !wait_for_download(&control).await {
        return Ok(());
    }
    if let Ok(cover) = state
        .media
        .cover_image(&state.client, record.id, false)
        .await
    {
        let source = PathBuf::from(cover);
        let extension = source
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or("jpg");
        let destination = album_directory.join(format!("cover.{extension}"));
        std::fs::copy(source, destination).map_err(|error| error.to_string())?;
        let _ = state.downloads.mark_covers_done(record.id);
    }

    let mut total = 0_i64;
    let mut downloaded = 0_i64;
    let download_threads = state
        .store
        .load("download_thread")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(3)
        .clamp(1, 8);

    // Resolve every selected chapter before writing progress. This makes
    // image_count the complete expected size of the task, so interrupted
    // downloads cannot look complete after a refresh.
    let mut chapter_payloads = Vec::with_capacity(record.chapters.len());
    for (chunk_index, chapters) in record.chapters.chunks(download_threads).enumerate() {
        if !wait_for_download(&control).await {
            return Ok(());
        }
        let mut tasks = tokio::task::JoinSet::new();
        let offset = chunk_index * download_threads;
        for (local_index, chapter) in chapters.iter().cloned().enumerate() {
            let client = state.client.clone();
            tasks.spawn(async move {
                let payload = client
                    .chapter(chapter.id)
                    .await
                    .map_err(|error| error.to_string())?;
                let images = payload
                    .get("images")
                    .and_then(Value::as_array)
                    .map(|values| {
                        values
                            .iter()
                            .filter_map(Value::as_str)
                            .map(str::to_string)
                            .collect::<Vec<_>>()
                    })
                    .unwrap_or_default();
                Ok::<_, String>((offset + local_index, chapter, images))
            });
        }
        while let Some(result) = tasks.join_next().await {
            if control.is_cancelled() {
                return Ok(());
            }
            let (index, chapter, images) = result
                .map_err(|error| format!("chapter metadata worker: {error}"))?
                .map_err(|error| error.to_string())?;
            total += images.len() as i64;
            chapter_payloads.push((index, chapter, images));
        }
    }
    chapter_payloads.sort_by_key(|(index, _, _)| *index);
    state
        .downloads
        .set_progress(record.id, total, 0, 0)
        .map_err(|error| error.to_string())?;

    for (_, chapter, images) in chapter_payloads {
        if !wait_for_download(&control).await {
            return Ok(());
        }
        let destination_dir = chapter_dir(&root, &record, &chapter);
        std::fs::create_dir_all(&destination_dir).map_err(|error| error.to_string())?;
        let existing_stems = downloaded_image_stems(&destination_dir);
        let mut pending_images = Vec::with_capacity(images.len());
        for image in images {
            let stem = Path::new(&image)
                .file_stem()
                .and_then(|value| value.to_str())
                .unwrap_or_default();
            if existing_stems.contains(stem) {
                downloaded += 1;
            } else {
                pending_images.push(image);
            }
        }
        state
            .downloads
            .set_progress(record.id, total, downloaded, 0)
            .map_err(|error| error.to_string())?;
        for chunk in pending_images.chunks(download_threads) {
            if !wait_for_download(&control).await {
                return Ok(());
            }
            let mut tasks = tokio::task::JoinSet::new();
            for image in chunk {
                let client = state.client.clone();
                let media = state.media.clone();
                let chapter_id = chapter.id;
                let image = image.clone();
                tasks.spawn(async move {
                    media
                        .page_image(&client, chapter_id, &image)
                        .await
                        .map_err(|error| error.to_string())
                });
            }
            while let Some(result) = tasks.join_next().await {
                if control.is_cancelled() {
                    return Ok(());
                }
                let source = result
                    .map_err(|error| format!("download worker: {error}"))?
                    .map_err(|error| error.to_string())?;
                let source = PathBuf::from(source);
                let file_name = source
                    .file_name()
                    .and_then(|value| value.to_str())
                    .ok_or_else(|| "downloaded image has no file name".to_string())?;
                let destination = destination_dir.join(file_name);
                std::fs::copy(source, destination).map_err(|error| error.to_string())?;
                downloaded += 1;
                state
                    .downloads
                    .set_progress(record.id, total, downloaded, 0)
                    .map_err(|error| error.to_string())?;
            }
        }
    }
    if !wait_for_download(&control).await {
        return Ok(());
    }
    if downloaded < total {
        return Err(format!(
            "download incomplete: {downloaded}/{total} images available"
        ));
    }
    state
        .downloads
        .set_progress(record.id, total, downloaded, 1)
        .map_err(|error| error.to_string())?;
    Ok(())
}

async fn wait_for_download(control: &DownloadControl) -> bool {
    loop {
        if control.is_cancelled() {
            return false;
        }
        if !control.is_paused() {
            return true;
        }
        tokio::time::sleep(std::time::Duration::from_millis(180)).await;
    }
}

fn downloaded_image_stems(directory: &Path) -> HashSet<String> {
    fs::read_dir(directory)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let metadata = entry.metadata().ok()?;
            if !metadata.is_file() || metadata.len() == 0 {
                return None;
            }
            entry
                .path()
                .file_stem()
                .and_then(|value| value.to_str())
                .map(str::to_string)
        })
        .collect()
}

async fn export_response(
    state: &BackendState,
    params: &Value,
    format: ExportFormat,
    single: bool,
) -> InvokeResponse {
    let destination = string_param(params, "folder")
        .or_else(|| string_param(params, "dir"))
        .unwrap_or_default();
    if destination.trim().is_empty() {
        return InvokeResponse::error("export destination is empty");
    }
    let ids = if single {
        vec![value_or_param_int(params, "id").unwrap_or(0)]
    } else {
        match params.get("comic_id") {
            Some(Value::Array(values)) => values.iter().filter_map(value_int).collect(),
            Some(value) => value_int(value).into_iter().collect(),
            None => value_or_param_int(params, "id").into_iter().collect(),
        }
    };
    if ids.is_empty() || ids.iter().any(|id| *id <= 0) {
        return InvokeResponse::error("export album ids are invalid");
    }
    let rename = string_param(params, "rename");
    let delete_exported = params
        .get("delete_exported")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let destination = PathBuf::from(destination.trim());
    for id in ids {
        let downloads = state.downloads.clone();
        let destination = destination.clone();
        let rename = rename.clone();
        let result = tokio::task::spawn_blocking(move || {
            export_album(
                &downloads,
                id,
                &destination,
                rename.as_deref(),
                format,
                delete_exported,
            )
        })
        .await;
        match result {
            Ok(Ok(_)) => {}
            Ok(Err(error)) => return InvokeResponse::error(error.to_string()),
            Err(error) => return InvokeResponse::error(format!("export worker: {error}")),
        }
    }
    InvokeResponse::success_text("")
}

async fn import_response(state: &BackendState, params: &Value, directory: bool) -> InvokeResponse {
    let path = string_value(params).unwrap_or_default();
    if path.trim().is_empty() {
        return InvokeResponse::error("import path is empty");
    }
    let path = PathBuf::from(path.trim());
    let downloads = state.downloads.clone();
    let result = tokio::task::spawn_blocking(move || {
        if directory {
            import_album_directory(&downloads, &path).map(|count| count.to_string())
        } else {
            import_album_archive(&downloads, &path).map(|id| id.to_string())
        }
    })
    .await;
    match result {
        Ok(Ok(value)) => InvokeResponse::success_text(value),
        Ok(Err(error)) => InvokeResponse::error(error.to_string()),
        Err(error) => InvokeResponse::error(format!("import worker: {error}")),
    }
}

async fn webdav_response(state: &BackendState, params: &Value) -> InvokeResponse {
    let url = string_param(params, "url").unwrap_or_default();
    let username = string_param(params, "username").unwrap_or_default();
    let password = string_param(params, "password").unwrap_or_default();
    let direction = string_param(params, "direction").unwrap_or_else(|| "Merge".into());
    let remote_url = match webdav_snapshot_url(&url) {
        Ok(url) => url,
        Err(error) => return InvokeResponse::error(error),
    };
    let local = match webdav_snapshot(state) {
        Ok(value) => value,
        Err(error) => return InvokeResponse::error(error.to_string()),
    };
    match direction.trim().to_ascii_lowercase().as_str() {
        "upload" => match state
            .client
            .webdav_put(&remote_url, &username, &password, &local)
            .await
        {
            Ok(()) => InvokeResponse::success_text(""),
            Err(error) => InvokeResponse::error(error.to_string()),
        },
        "download" => {
            let remote = match state
                .client
                .webdav_get_text(&remote_url, &username, &password)
                .await
            {
                Ok(Some(remote)) => remote,
                Ok(None) => return InvokeResponse::error("WebDAV snapshot does not exist"),
                Err(error) => return InvokeResponse::error(error.to_string()),
            };
            let snapshot = match parse_webdav_snapshot(&remote) {
                Ok(value) => value,
                Err(error) => return InvokeResponse::error(error.to_string()),
            };
            match apply_webdav_snapshot(state, &snapshot, true) {
                Ok(()) => InvokeResponse::success_text(""),
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        "merge" => {
            let remote = match state
                .client
                .webdav_get_text(&remote_url, &username, &password)
                .await
            {
                Ok(Some(remote)) => Some(remote),
                Ok(None) => None,
                Err(error) => return InvokeResponse::error(error.to_string()),
            };
            if let Some(remote) = remote {
                let snapshot = match parse_webdav_snapshot(&remote) {
                    Ok(value) => value,
                    Err(error) => return InvokeResponse::error(error.to_string()),
                };
                if let Err(error) = apply_webdav_snapshot(state, &snapshot, false) {
                    return InvokeResponse::error(error.to_string());
                }
            }
            let merged = match webdav_snapshot(state) {
                Ok(value) => value,
                Err(error) => return InvokeResponse::error(error.to_string()),
            };
            match state
                .client
                .webdav_put(&remote_url, &username, &password, &merged)
                .await
            {
                Ok(()) => InvokeResponse::success_text(""),
                Err(error) => InvokeResponse::error(error.to_string()),
            }
        }
        _ => InvokeResponse::error("WebDAV direction must be Merge, Upload, or Download"),
    }
}

fn webdav_snapshot(state: &BackendState) -> BackendResult<Value> {
    let history = state.history.snapshot()?;
    Ok(json!({
        "format": "jmcomic3-mod",
        "version": 2,
        "task": "webdav_sync",
        "created_at": std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|value| value.as_secs())
            .unwrap_or(0),
        "properties": state.store.snapshot()?,
        "view_logs": history.get("view_logs").cloned().unwrap_or(Value::Array(Vec::new())),
        "search_histories": history.get("search_histories").cloned().unwrap_or(Value::Array(Vec::new())),
        "downloads": state.downloads.snapshot()?,
    }))
}

fn parse_webdav_snapshot(raw: &str) -> BackendResult<Value> {
    let value: Value = serde_json::from_str(raw)?;
    if !value.is_object() {
        return Err(crate::error::BackendError::Config(
            "WebDAV snapshot must be an object".into(),
        ));
    }
    Ok(value.get("manifest").cloned().unwrap_or(value))
}

fn apply_webdav_snapshot(
    state: &BackendState,
    snapshot: &Value,
    replace: bool,
) -> BackendResult<()> {
    state.history.apply_snapshot(snapshot, replace)?;
    if let Some(downloads) = snapshot.get("downloads") {
        if !downloads.is_null() {
            state.downloads.apply_snapshot(downloads, replace)?;
        }
    }
    if let Some(properties) = snapshot.get("properties") {
        state.store.apply_snapshot(properties, replace)?;
    }
    Ok(())
}

fn webdav_snapshot_url(raw: &str) -> Result<String, String> {
    let raw = raw.trim();
    if raw.is_empty() {
        return Err("WebDAV URL is empty".into());
    }
    let parsed =
        reqwest::Url::parse(raw).map_err(|error| format!("invalid WebDAV URL: {error}"))?;
    if !matches!(parsed.scheme(), "http" | "https") || parsed.host_str().is_none() {
        return Err("WebDAV URL must use http or https".into());
    }
    if raw.to_ascii_lowercase().ends_with(".json") {
        return Ok(raw.to_string());
    }
    Ok(format!(
        "{}/webdav_sync_snapshot.json",
        raw.trim_end_matches('/')
    ))
}

async fn pre_login_response(state: &BackendState) -> InvokeResponse {
    let cookie = state.store.load("cookie").unwrap_or_default();
    let username =
        first_non_empty_property(&state.store, &["remember_login_username", "load_username"]);
    let password =
        first_non_empty_property(&state.store, &["remember_login_password", "load_password"]);
    let pre_set =
        !cookie.trim().is_empty() || !username.trim().is_empty() || !password.trim().is_empty();
    if !pre_set {
        return InvokeResponse::success_value(&json!({
            "pre_set": false,
            "pre_login": false,
            "message": "",
            "self_info": null,
        }));
    }
    if !cookie.trim().is_empty() {
        state
            .client
            .add_cookie_header(&cookie, &state.client.api_base_url());
    }
    let profile_error = match state.client.user_profile().await {
        Ok(self_info) => {
            return InvokeResponse::success_value(&json!({
                "pre_set": true,
                "pre_login": true,
                "message": "",
                "self_info": self_info,
            }));
        }
        Err(error) => error.to_string(),
    };
    if username.trim().is_empty() || password.is_empty() {
        clear_rejected_session(state, &profile_error);
        return InvokeResponse::success_value(&json!({
            "pre_set": true,
            "pre_login": false,
            "message": profile_error,
            "self_info": null,
        }));
    }
    match state.client.login(&username, &password).await {
        Ok(self_info) => {
            preserve_login_credentials(state, &username);
            InvokeResponse::success_value(&json!({
                "pre_set": true,
                "pre_login": true,
                "message": "",
                "self_info": self_info,
            }))
        }
        Err(error) => {
            let message = error.to_string();
            clear_rejected_session(state, &message);
            InvokeResponse::success_value(&json!({
                "pre_set": true,
                "pre_login": false,
                "message": message,
                "self_info": null,
            }))
        }
    }
}

fn first_non_empty_property(store: &PropertyStore, keys: &[&str]) -> String {
    keys.iter()
        .find_map(|key| {
            store
                .load(key)
                .ok()
                .filter(|value| !value.trim().is_empty())
        })
        .unwrap_or_default()
}

fn preserve_login_credentials(state: &BackendState, username: &str) {
    let api_url = state.client.api_base_url();
    if let Some(cookie) = state
        .client
        .cookie_header_for(&api_url)
        .filter(|value| !value.trim().is_empty())
    {
        let _ = state.store.save("cookie", &cookie);
    }
    let _ = state.store.save("load_username", username);
    let _ = state.store.save("last_login_username", username);
}

fn clear_rejected_session(state: &BackendState, message: &str) {
    let rejected = message.contains("401")
        || message.to_ascii_lowercase().contains("unauthorized")
        || message.contains("请先登录");
    if rejected {
        let _ = state.store.save("cookie", "");
        let _ = reset_client();
    }
}

async fn login_response(state: &BackendState, username: &str, password: &str) -> InvokeResponse {
    match state.client.login(username, password).await {
        Ok(self_info) => {
            let api_url = state.client.api_base_url();
            let cookie = state
                .client
                .cookie_header_for(&api_url)
                .filter(|value| !value.trim().is_empty())
                .or_else(|| {
                    self_info
                        .get("s")
                        .and_then(Value::as_str)
                        .filter(|value| !value.trim().is_empty())
                        .map(|value| format!("AVS={value}"))
                })
                .unwrap_or_default();
            let _ = state.store.save("cookie", &cookie);
            let _ = state.store.save("load_username", username);
            let _ = state.store.save("last_login_username", username);
            InvokeResponse::success_value(&self_info)
        }
        Err(error) => InvokeResponse::error(error.to_string()),
    }
}

fn property_response(state: &BackendState, key: &str) -> InvokeResponse {
    match state.store.load(key) {
        Ok(value) => InvokeResponse::success_text(value),
        Err(error) => InvokeResponse::error(error.to_string()),
    }
}

async fn page_image_batch(state: &BackendState, params: &Value) -> InvokeResponse {
    let pages = params
        .as_object()
        .and_then(|value| value.get("pages"))
        .and_then(Value::as_array);
    let Some(pages) = pages else {
        return InvokeResponse::error("pages must be an array");
    };
    let mut items = Vec::with_capacity(pages.len());
    for page in pages {
        let id = int_param(page, "id").unwrap_or(0);
        let image_name = string_param(page, "image_name").unwrap_or_default();
        if id <= 0 || image_name.trim().is_empty() {
            items.push(json!({"id": id.max(1), "error": "invalid_request"}));
            continue;
        }
        match state.media.page_image(&state.client, id, &image_name).await {
            Ok(path) => match state.media.image_size(&path) {
                Ok((width, height)) => items.push(json!({
                    "id": id,
                    "path": path,
                    "width": width,
                    "height": height,
                })),
                Err(error) => items.push(json!({
                    "id": id,
                    "error": error.to_string(),
                })),
            },
            Err(error) => items.push(json!({
                "id": id,
                "error": error.to_string(),
            })),
        }
    }
    InvokeResponse::success_value(&json!({
        "version": 1,
        "items": items,
    }))
}

fn property_json_response(state: &BackendState, key: &str) -> InvokeResponse {
    match state.store.load(key) {
        Ok(raw) if raw.trim().is_empty() => InvokeResponse::success_value(&json!({})),
        Ok(raw) => match serde_json::from_str::<Value>(&raw) {
            Ok(value) => InvokeResponse::success_value(&value),
            Err(error) => InvokeResponse::error(format!("stored {key} is invalid: {error}")),
        },
        Err(error) => InvokeResponse::error(error.to_string()),
    }
}

fn result_value(result: BackendResult<Value>) -> InvokeResponse {
    match result {
        Ok(value) => InvokeResponse::success_value(&value),
        Err(error) => InvokeResponse::error(error.to_string()),
    }
}

fn property_response_with_default(
    state: &BackendState,
    key: &str,
    fallback: &str,
) -> InvokeResponse {
    match state.store.load(key) {
        Ok(value) if value.trim().is_empty() => InvokeResponse::success_text(fallback),
        Ok(value) => InvokeResponse::success_text(value),
        Err(error) => InvokeResponse::error(error.to_string()),
    }
}

fn path_text(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn pro_info() -> Value {
    json!({
        "is_pro": true,
        "expire": 4_102_444_800_i64
    })
}

fn cached_api_host_list(state: &BackendState) -> Result<Vec<String>, String> {
    let cached = state
        .store
        .load("api_host_list")
        .map_err(|error| error.to_string())?;
    Ok(merge_api_hosts(
        FALLBACK_API_HOSTS.iter().copied(),
        parse_api_hosts(&cached)
            .into_iter()
            .chain([state.client.config().api_host.clone()]),
    ))
}

async fn refresh_api_host_list(state: &BackendState) -> InvokeResponse {
    let mut refreshed = Vec::new();
    for url in API_HOST_LIST_URLS {
        let fetched = tokio::time::timeout(
            std::time::Duration::from_secs(5),
            state.client.http_get_text(url),
        )
        .await;
        if let Ok(Ok(body)) = fetched {
            let hosts = parse_api_hosts(&body);
            if !hosts.is_empty() {
                refreshed = hosts;
                break;
            }
        }
    }
    if refreshed.is_empty() {
        return InvokeResponse::error("unable to refresh API host list");
    }
    let hosts = merge_api_hosts(
        FALLBACK_API_HOSTS.iter().copied(),
        refreshed
            .into_iter()
            .chain([state.client.config().api_host.clone()]),
    );
    match state.store.save(
        "api_host_list",
        &serde_json::to_string(&hosts).unwrap_or_default(),
    ) {
        Ok(()) => InvokeResponse::success_value(&json!(hosts)),
        Err(error) => InvokeResponse::error(error.to_string()),
    }
}

fn parse_api_hosts(raw: &str) -> Vec<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Vec::new();
    }
    if let Ok(value) = serde_json::from_str::<Value>(trimmed) {
        let mut values = Vec::new();
        collect_host_strings(&value, 0, &mut values);
        return normalize_api_hosts(values);
    }
    normalize_api_hosts(
        trimmed
            .split(|character: char| character.is_whitespace() || matches!(character, ',' | ';'))
            .map(str::to_string),
    )
}

fn collect_host_strings(value: &Value, depth: usize, output: &mut Vec<String>) {
    if depth > 4 {
        return;
    }
    match value {
        Value::String(value) => output.push(value.clone()),
        Value::Array(values) => {
            for value in values {
                collect_host_strings(value, depth + 1, output);
            }
        }
        Value::Object(values) => {
            for value in values.values() {
                collect_host_strings(value, depth + 1, output);
            }
        }
        Value::Null | Value::Bool(_) | Value::Number(_) => {}
    }
}

fn normalize_api_hosts(values: impl IntoIterator<Item = String>) -> Vec<String> {
    let mut hosts = Vec::new();
    for value in values {
        let candidate = value.trim();
        if candidate.is_empty() || candidate.chars().any(char::is_whitespace) {
            continue;
        }
        let config = JmClientConfig {
            api_host: candidate.to_string(),
            ..JmClientConfig::default()
        }
        .validated();
        if let Ok(config) = config {
            if !hosts.contains(&config.api_host) {
                hosts.push(config.api_host);
            }
        }
    }
    hosts
}

fn merge_api_hosts(
    fallback: impl IntoIterator<Item = &'static str>,
    values: impl IntoIterator<Item = String>,
) -> Vec<String> {
    let mut seen = BTreeSet::new();
    let mut hosts = Vec::new();
    for host in fallback
        .into_iter()
        .map(str::to_string)
        .chain(values.into_iter())
    {
        let normalized = normalize_api_hosts([host]);
        for host in normalized {
            if seen.insert(host.to_ascii_lowercase()) {
                hosts.push(host);
            }
        }
    }
    hosts
}

fn result_text(result: BackendResult<String>) -> InvokeResponse {
    match result {
        Ok(value) => InvokeResponse::success_text(value),
        Err(error) => InvokeResponse::error(error.to_string()),
    }
}

fn string_value(params: &Value) -> Option<String> {
    match params {
        Value::String(value) => Some(value.clone()),
        _ => None,
    }
}

fn value_int(value: &Value) -> Option<i64> {
    value
        .as_i64()
        .or_else(|| value.as_str()?.trim().parse::<i64>().ok())
}

fn value_or_param_string(params: &Value, key: &str) -> Option<String> {
    match params {
        Value::String(value) => Some(value.clone()),
        Value::Object(_) => string_param(params, key),
        _ => None,
    }
}

fn value_or_param_int(params: &Value, key: &str) -> Option<i64> {
    match params {
        Value::Number(_) | Value::String(_) => value_int(params),
        Value::Object(_) => params.as_object()?.get(key).and_then(value_int),
        _ => None,
    }
}

fn int_param(params: &Value, key: &str) -> Result<i64, String> {
    match params {
        Value::Number(value) => value
            .as_i64()
            .ok_or_else(|| "numeric parameter is not an integer".to_string()),
        Value::Object(map) => map
            .get(key)
            .and_then(|value| {
                value
                    .as_i64()
                    .or_else(|| value.as_str()?.parse::<i64>().ok())
            })
            .ok_or_else(|| format!("missing or invalid parameter: {key}")),
        _ => Err("parameters must be an object or number".into()),
    }
}

fn optional_int_param(params: &Value, key: &str) -> Option<i64> {
    int_param(params, key).ok()
}

fn string_param(params: &Value, key: &str) -> Option<String> {
    params
        .as_object()?
        .get(key)
        .and_then(Value::as_str)
        .map(str::to_string)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn api_host_lists_accept_json_plain_text_and_duplicates() {
        let json = parse_api_hosts(
            r#"{"servers":[" https://api.example.com/path ","api.example.com","bad host"]}"#,
        );
        assert_eq!(json, ["api.example.com"]);

        let plain =
            parse_api_hosts("https://one.example.com/a\n//two.example.com:8443\none.example.com");
        assert_eq!(plain, ["one.example.com", "two.example.com:8443"]);

        let merged = merge_api_hosts(
            ["default.example.com"],
            [
                "DEFAULT.example.com".to_string(),
                "cdn.example.com".to_string(),
            ],
        );
        assert_eq!(merged, ["default.example.com", "cdn.example.com"]);
    }

    #[test]
    fn webdav_urls_and_nested_snapshots_are_normalized() {
        assert_eq!(
            webdav_snapshot_url("https://dav.example.com/comics").unwrap(),
            "https://dav.example.com/comics/webdav_sync_snapshot.json"
        );
        assert_eq!(
            webdav_snapshot_url("https://dav.example.com/snapshot.json").unwrap(),
            "https://dav.example.com/snapshot.json"
        );
        let snapshot =
            parse_webdav_snapshot(r#"{"manifest":{"task":"webdav_sync","view_logs":[]}}"#).unwrap();
        assert_eq!(snapshot["task"], "webdav_sync");
    }

    #[test]
    fn legacy_download_root_property_is_used_as_fallback() {
        let root = std::env::temp_dir().join(format!(
            "jmcomic3-backend-v2-root-property-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let store = PropertyStore::open(&root).unwrap();
        store
            .save("download_and_export_to", "/storage/emulated/0/JM")
            .unwrap();
        assert_eq!(
            stored_download_root(&store).unwrap(),
            "/storage/emulated/0/JM"
        );
        store.save("download_root", "/new/path").unwrap();
        assert_eq!(stored_download_root(&store).unwrap(), "/new/path");
        std::fs::remove_dir_all(root).unwrap();
    }
}
