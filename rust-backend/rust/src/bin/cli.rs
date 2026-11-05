use std::env;
use std::process::ExitCode;

use anyhow::{anyhow, Context, Result};
use jmcomic3_rust_backend_v2::config::{DEFAULT_API_HOST, DEFAULT_IMAGE_HOST};
use jmcomic3_rust_backend_v2::models::SearchSort;
use jmcomic3_rust_backend_v2::{JmClient, JmClientConfig};

#[tokio::main]
async fn main() -> ExitCode {
    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("error: {error:#}");
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<()> {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() {
        print_usage();
        return Ok(());
    }
    let config = JmClientConfig {
        api_host: env::var("JM_API_HOST").unwrap_or_else(|_| DEFAULT_API_HOST.into()),
        image_host: env::var("JM_IMAGE_HOST").unwrap_or_else(|_| DEFAULT_IMAGE_HOST.into()),
        app_version: env::var("JM_APP_VERSION").unwrap_or_else(|_| "2.0.13".into()),
        proxy_url: env::var("JM_PROXY").ok(),
        ..Default::default()
    };
    let client = JmClient::new(config)?;

    match args[0].as_str() {
        "search" => {
            let keyword = args.get(1).context("search requires a keyword")?;
            let page = args
                .get(2)
                .map(|value| value.parse::<u32>())
                .transpose()?
                .unwrap_or(1);
            let sort = args
                .get(3)
                .map(|value| value.parse::<SearchSort>())
                .transpose()
                .map_err(|error| anyhow!(error))?
                .unwrap_or(SearchSort::Latest);
            print_json(&client.search(keyword, page, sort).await?)?;
        }
        "album" => {
            let id = args
                .get(1)
                .context("album requires an id")?
                .parse::<i64>()?;
            print_json(&client.album(id).await?)?;
        }
        "chapter" => {
            let id = args
                .get(1)
                .context("chapter requires an id")?
                .parse::<i64>()?;
            print_json(&client.chapter(id).await?)?;
        }
        "scramble" => {
            let id = args
                .get(1)
                .context("scramble requires a chapter id")?
                .parse::<i64>()?;
            println!("{}", client.scramble_id(id).await?);
        }
        "weekly-info" => print_json(&client.weekly_info().await?)?,
        "weekly" => {
            let category = args.get(1).context("weekly requires category id")?;
            let kind = args.get(2).context("weekly requires type id")?;
            print_json(&client.weekly(category, kind).await?)?;
        }
        "login-info" => {
            let username = env::var("JM_USERNAME").context("JM_USERNAME is not configured")?;
            let password = env::var("JM_PASSWORD").context("JM_PASSWORD is not configured")?;
            print_json(&client.login(&username, &password).await?)?;
        }
        "help" | "--help" | "-h" => print_usage(),
        other => return Err(anyhow!("unknown command: {other}")),
    }
    Ok(())
}

fn print_json(value: &serde_json::Value) -> Result<()> {
    println!("{}", serde_json::to_string_pretty(value)?);
    Ok(())
}

fn print_usage() {
    eprintln!(
        "Usage: jmcomic3-backend-cli <command>\n\
         Commands:\n\
           search <keyword> [page] [mr|mv|mp|tf]\n\
           album <id>\n\
           chapter <id>\n\
           scramble <chapter-id>\n\
           weekly-info\n\
           weekly <category-id> <type-id>\n\
           login-info    (reads JM_USERNAME and JM_PASSWORD)\n\
         Environment: JM_API_HOST, JM_IMAGE_HOST, JM_APP_VERSION, JM_PROXY"
    );
}
