use std::env;
use std::ffi::{CStr, CString};
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use jmcomic3_rust_backend_v2::config::{DEFAULT_API_HOST, DEFAULT_APP_VERSION, DEFAULT_IMAGE_HOST};
use jmcomic3_rust_backend_v2::ffi::{free_str_ffi, init_ffi, invoke_ffi};
use jmcomic3_rust_backend_v2::media::MediaCache;
use jmcomic3_rust_backend_v2::models::SearchSort;
use jmcomic3_rust_backend_v2::{JmClient, JmClientConfig};
use serde_json::Value;

#[tokio::main]
async fn main() -> Result<()> {
    let config = JmClientConfig {
        api_host: env::var("JM_API_HOST").unwrap_or_else(|_| DEFAULT_API_HOST.into()),
        image_host: env::var("JM_IMAGE_HOST").unwrap_or_else(|_| DEFAULT_IMAGE_HOST.into()),
        app_version: env::var("JM_APP_VERSION").unwrap_or_else(|_| DEFAULT_APP_VERSION.into()),
        proxy_url: env::var("JM_PROXY").ok(),
        ..Default::default()
    };
    let client = JmClient::new(config)?;
    let categories = client.categories().await?;
    let category_count = categories
        .get("categories")
        .and_then(|value| value.as_array())
        .map_or(0, Vec::len);
    let category_blocks = categories
        .get("blocks")
        .and_then(Value::as_array)
        .map_or(0, Vec::len);
    let category_tags = categories
        .get("blocks")
        .and_then(Value::as_array)
        .map(|blocks| {
            blocks
                .iter()
                .filter_map(|block| block.get("content").and_then(Value::as_array))
                .map(Vec::len)
                .sum::<usize>()
        })
        .unwrap_or(0);

    let query = env::var("JM_SMOKE_QUERY").unwrap_or_else(|_| "test".into());
    let search = client.search(&query, 1, SearchSort::Latest).await?;
    let latest_slug = categories
        .pointer("/categories/0/slug")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .unwrap_or("latest");
    let latest = client
        .comics(latest_slug, SearchSort::Latest.as_str(), 1)
        .await?;
    let search_total = search
        .get("total")
        .and_then(|value| {
            value
                .as_i64()
                .or_else(|| value.as_str()?.parse::<i64>().ok())
        })
        .unwrap_or(0);
    let search_items = search
        .get("content")
        .and_then(|value| value.as_array())
        .map_or(0, Vec::len);
    let week_info = client.weekly_info().await?;
    let week_categories = week_info
        .get("categories")
        .and_then(Value::as_array)
        .map_or(0, Vec::len);
    let week_types = week_info
        .get("type")
        .and_then(Value::as_array)
        .map_or(0, Vec::len);
    let games = client.games(1).await?;
    let api_latency = client.measure_api_host(DEFAULT_API_HOST).await.unwrap_or(0);
    let image_latency = client
        .measure_image_host(DEFAULT_IMAGE_HOST)
        .await
        .unwrap_or(0);

    println!("network_ok=true");
    println!("categories={category_count}");
    println!("category_blocks={category_blocks}");
    println!("category_tags={category_tags}");
    println!("search_total={search_total}");
    println!("search_items={search_items}");
    println!(
        "latest_ok={}",
        latest.get("content").and_then(Value::as_array).is_some()
    );
    println!(
        "latest_items={}",
        latest
            .get("content")
            .and_then(Value::as_array)
            .map_or(0, Vec::len)
    );
    println!("week_categories={week_categories}");
    println!("week_types={week_types}");
    println!(
        "games_ok={}",
        games.get("games").and_then(Value::as_array).is_some()
    );
    println!("api_ping_ok={}", api_latency > 0);
    println!("image_ping_ok={}", image_latency > 0);
    if let (Some(category_id), Some(type_id)) = (
        week_info
            .pointer("/categories/0/id")
            .and_then(Value::as_str),
        week_info.pointer("/type/0/id").and_then(Value::as_str),
    ) {
        let weekly = client.weekly(category_id, type_id).await?;
        println!(
            "week_filter_ok={}",
            weekly.get("list").and_then(Value::as_array).is_some()
        );
        println!(
            "week_filter_items={}",
            weekly
                .get("list")
                .and_then(Value::as_array)
                .map_or(0, Vec::len)
        );
    }

    if let Ok(album_id) = env::var("JM_SMOKE_ALBUM_ID") {
        let album_id = album_id
            .parse::<i64>()
            .context("invalid JM_SMOKE_ALBUM_ID")?;
        let album = client.album(album_id).await?;
        println!(
            "album_ok={}",
            album.is_object() && album.get("id").is_some()
        );
    }

    if let Ok(album_id) = env::var("JM_SMOKE_COVER_ID") {
        let album_id = album_id
            .parse::<i64>()
            .context("invalid JM_SMOKE_COVER_ID")?;
        let root = env::var_os("JM_SMOKE_DATA_DIR")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|| env::temp_dir().join("jmcomic3-backend-v2-smoke"));
        let media = MediaCache::open(&root)?;
        let cover = media.cover_image(&client, album_id, false).await?;
        let size = std::fs::metadata(&cover)?.len();
        println!("cover_ok={}", size > 0);
        println!("cover_bytes={size}");
    }

    if let Ok(album_id) = env::var("JM_SMOKE_FORUM_ALBUM_ID") {
        let album_id = album_id
            .parse::<i64>()
            .context("invalid JM_SMOKE_FORUM_ALBUM_ID")?;
        let forum = client.forum(Some("all"), Some(album_id), None, 1).await?;
        let comment_count = forum
            .get("list")
            .and_then(|value| value.as_array())
            .map_or(0, Vec::len);
        println!("forum_ok={}", forum.is_object());
        println!("forum_items={comment_count}");
    }

    if let Ok(chapter_id) = env::var("JM_SMOKE_CHAPTER_ID") {
        let chapter_id = chapter_id
            .parse::<i64>()
            .context("invalid JM_SMOKE_CHAPTER_ID")?;
        let chapter = client.chapter(chapter_id).await?;
        let images = chapter
            .get("images")
            .and_then(|value| value.as_array())
            .map(|values| {
                values
                    .iter()
                    .filter_map(|value| value.as_str())
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        println!("chapter_ok={}", chapter.get("id").is_some());
        println!("chapter_images={}", images.len());

        if env::var("JM_SMOKE_IMAGE").ok().as_deref() == Some("1") {
            let image_name = env::var("JM_SMOKE_IMAGE_NAME")
                .ok()
                .or_else(|| images.first().map(|value| (*value).to_string()))
                .context("chapter has no image")?;
            let root = env::var_os("JM_SMOKE_DATA_DIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|| env::temp_dir().join("jmcomic3-backend-v2-smoke"));
            let media = MediaCache::open(&root)?;
            media.page_image(&client, chapter_id, &image_name).await?;
            println!("image_ok=true");
        }
    }

    std::thread::spawn(ffi_smoke)
        .join()
        .map_err(|_| anyhow::anyhow!("FFI smoke thread panicked"))??;
    Ok(())
}

fn ffi_smoke() -> Result<()> {
    let root = env::var_os("JM_SMOKE_DATA_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(env::temp_dir)
        .join(format!("ffi-smoke-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let root = CString::new(root.to_string_lossy().replace('\0', ""))?;
    init_ffi(root.as_ptr());

    let ping = ffi_call(r#"{"method":"ping_backend","params":""}"#)?;
    ensure_ffi_success(&ping)?;
    let save = ffi_call(r#"{"method":"save_property","params":{"k":"smoke_probe","v":"ok"}}"#)?;
    ensure_ffi_success(&save)?;
    let load = ffi_call(r#"{"method":"load_property","params":"smoke_probe"}"#)?;
    ensure_ffi_success(&load)?;
    let save_api_host = ffi_call(&format!(
        r#"{{"method":"save_api_host","params":"{DEFAULT_API_HOST}"}}"#
    ))?;
    ensure_ffi_success(&save_api_host)?;
    let save_cdn_host = ffi_call(&format!(
        r#"{{"method":"save_cdn_host","params":"{DEFAULT_IMAGE_HOST}"}}"#
    ))?;
    ensure_ffi_success(&save_cdn_host)?;
    let api_host = ffi_call(r#"{"method":"load_api_host","params":""}"#)?;
    ensure_ffi_success(&api_host)?;
    let api_host_list = ffi_call(r#"{"method":"load_api_host_list","params":""}"#)?;
    ensure_ffi_success(&api_host_list)?;
    let set_thread = ffi_call(r#"{"method":"set_download_thread","params":"2"}"#)?;
    ensure_ffi_success(&set_thread)?;
    let get_thread = ffi_call(r#"{"method":"load_download_thread","params":""}"#)?;
    ensure_ffi_success(&get_thread)?;
    let home_dir = ffi_call(r#"{"method":"getHomeDir","params":""}"#)?;
    ensure_ffi_success(&home_dir)?;
    let is_pro = ffi_call(r#"{"method":"is_pro","params":""}"#)?;
    ensure_ffi_success(&is_pro)?;
    let pro_info = ffi_call(r#"{"method":"pro_info_all","params":""}"#)?;
    ensure_ffi_success(&pro_info)?;
    let pre_login = ffi_call(r#"{"method":"pre_login","params":""}"#)?;
    ensure_ffi_success(&pre_login)?;
    let pre_login_data: Value =
        serde_json::from_str(pre_login["response_data"].as_str().unwrap_or("{}"))?;
    let categories = ffi_call(r#"{"method":"categories","params":""}"#)?;
    ensure_ffi_success(&categories)?;
    let update_log = ffi_call(
        r#"{"method":"update_view_log","params":{"id":7,"last_view_chapter_id":8,"last_view_page":12}}"#,
    )?;
    ensure_ffi_success(&update_log)?;
    let find_log = ffi_call(r#"{"method":"find_view_log","params":7}"#)?;
    ensure_ffi_success(&find_log)?;
    let page_log = ffi_call(r#"{"method":"page_view_log","params":1}"#)?;
    ensure_ffi_success(&page_log)?;
    let search = ffi_call(
        r#"{"method":"comic_search","params":{"search_query":"test","sort_by":"mr","page":1}}"#,
    )?;
    ensure_ffi_success(&search)?;
    let search_history = ffi_call(r#"{"method":"last_search_histories","params":"5"}"#)?;
    ensure_ffi_success(&search_history)?;
    let downloads = ffi_call(r#"{"method":"all_downloads","params":""}"#)?;
    ensure_ffi_success(&downloads)?;
    let renew = ffi_call(r#"{"method":"renew_all_downloads","params":""}"#)?;
    ensure_ffi_success(&renew)?;
    let download_root = ffi_call(r#"{"method":"get_download_and_export_to","params":""}"#)?;
    ensure_ffi_success(&download_root)?;
    if let (Ok(album_id), Ok(chapter_id)) = (
        env::var("JM_SMOKE_DOWNLOAD_ALBUM_ID"),
        env::var("JM_SMOKE_DOWNLOAD_CHAPTER_ID"),
    ) {
        let album_id = album_id
            .parse::<i64>()
            .context("invalid JM_SMOKE_DOWNLOAD_ALBUM_ID")?;
        let chapter_id = chapter_id
            .parse::<i64>()
            .context("invalid JM_SMOKE_DOWNLOAD_CHAPTER_ID")?;
        let create = ffi_call(&format!(
            r#"{{"method":"create_download","params":{{"album":{{"id":{album_id},"name":"smoke","author":[],"tags":[],"works":[],"description":""}},"chapters":[{{"id":{chapter_id},"name":"chapter","sort":"1"}}]}}}}"#
        ))?;
        ensure_ffi_success(&create)?;
        let deadline = Instant::now() + Duration::from_secs(90);
        let mut final_status = 0;
        let mut final_downloaded = 0;
        let mut final_total = 0;
        while Instant::now() < deadline {
            let downloads = ffi_call(r#"{"method":"all_downloads","params":""}"#)?;
            ensure_ffi_success(&downloads)?;
            let data: Value =
                serde_json::from_str(downloads["response_data"].as_str().unwrap_or("[]"))?;
            let record = data
                .as_array()
                .and_then(|items| items.iter().find(|item| item["id"] == album_id));
            if let Some(record) = record {
                final_status = record["dl_status"].as_i64().unwrap_or(0);
                final_downloaded = record["dled_image_count"].as_i64().unwrap_or(0);
                final_total = record["image_count"].as_i64().unwrap_or(0);
                if final_status == 1 || final_status == 2 {
                    break;
                }
            }
            std::thread::sleep(Duration::from_millis(500));
        }
        println!("ffi_download_create_ok={}", final_status == 1);
        println!("ffi_download_status={final_status}");
        println!("ffi_download_total={final_total}");
        println!("ffi_downloaded={final_downloaded}");
        if final_status == 1 {
            let _ = ffi_call(&format!(
                r#"{{"method":"delete_download","params":{album_id}}}"#
            ));
        } else {
            anyhow::bail!(
                "download smoke did not finish successfully: status={final_status}, downloaded={final_downloaded}/{final_total}"
            );
        }
    }
    let reset_thread = ffi_call(r#"{"method":"set_download_thread","params":"1"}"#)?;
    ensure_ffi_success(&reset_thread)?;

    println!("ffi_ok=true");
    println!(
        "ffi_property_ok={}",
        load["response_data"].as_str() == Some("ok")
    );
    println!(
        "ffi_api_host_ok={}",
        api_host["response_data"].as_str() == Some(DEFAULT_API_HOST)
    );
    let api_hosts: Value =
        serde_json::from_str(api_host_list["response_data"].as_str().unwrap_or("[]"))?;
    println!(
        "ffi_api_host_list_ok={}",
        api_hosts.as_array().is_some_and(|values| values.len() >= 7)
    );
    println!(
        "ffi_download_thread_ok={}",
        get_thread["response_data"].as_str() == Some("2")
    );
    println!(
        "ffi_home_dir_ok={}",
        home_dir["response_data"]
            .as_str()
            .is_some_and(|value| !value.trim().is_empty())
    );
    let is_pro_data: Value =
        serde_json::from_str(is_pro["response_data"].as_str().unwrap_or("{}"))?;
    println!(
        "ffi_pro_ok={}",
        is_pro_data.get("is_pro").and_then(Value::as_bool) == Some(true)
    );
    let pro_info_data: Value =
        serde_json::from_str(pro_info["response_data"].as_str().unwrap_or("{}"))?;
    println!(
        "ffi_pro_info_ok={}",
        pro_info_data
            .get("pro_info_af")
            .and_then(|value| value.get("is_pro"))
            .and_then(Value::as_bool)
            == Some(true)
    );
    println!(
        "ffi_pre_login_clean={}",
        pre_login_data.get("pre_set").and_then(Value::as_bool) == Some(false)
    );
    let find_log_data: Value =
        serde_json::from_str(find_log["response_data"].as_str().unwrap_or("null"))?;
    println!(
        "ffi_view_log_ok={}",
        find_log_data.get("last_view_page").and_then(Value::as_i64) == Some(12)
    );
    let page_log_data: Value =
        serde_json::from_str(page_log["response_data"].as_str().unwrap_or("{}"))?;
    println!(
        "ffi_page_view_log_ok={}",
        page_log_data.get("total").and_then(Value::as_i64) == Some(1)
    );
    let search_history_data: Value =
        serde_json::from_str(search_history["response_data"].as_str().unwrap_or("[]"))?;
    println!(
        "ffi_search_history_ok={}",
        search_history_data
            .as_array()
            .is_some_and(|items| !items.is_empty())
    );
    let downloads_data: Value =
        serde_json::from_str(downloads["response_data"].as_str().unwrap_or("[]"))?;
    println!(
        "ffi_downloads_ok={}",
        downloads_data.as_array().is_some_and(Vec::is_empty)
    );
    println!(
        "ffi_download_path_ok={}",
        download_root["response_data"].as_str().is_some()
    );
    let _ = std::fs::remove_dir_all(root.to_string_lossy().as_ref());
    Ok(())
}

fn ffi_call(request: &str) -> Result<Value> {
    let request = CString::new(request.replace('\0', ""))?;
    let pointer = invoke_ffi(request.as_ptr());
    if pointer.is_null() {
        anyhow::bail!("FFI returned a null response");
    }
    let response = unsafe { CStr::from_ptr(pointer) }
        .to_string_lossy()
        .into_owned();
    unsafe { free_str_ffi(pointer) };
    Ok(serde_json::from_str(&response)?)
}

fn ensure_ffi_success(response: &Value) -> Result<()> {
    if response.get("error_message").and_then(Value::as_str) != Some("") {
        anyhow::bail!(
            "FFI request failed: {}",
            response
                .get("error_message")
                .and_then(Value::as_str)
                .unwrap_or("unknown error")
        );
    }
    Ok(())
}
