use std::fs::{self, File};
use std::io::{self, BufWriter, Cursor, Write};
use std::path::{Path, PathBuf};

use image::codecs::jpeg::JpegEncoder;
use image::ImageReader;
use serde_json::json;

use crate::download::{
    album_dir, chapter_dir, DownloadAlbumRecord, DownloadChapterRecord, DownloadManager,
};
use crate::error::{BackendError, BackendResult};

#[derive(Debug, Clone, Copy)]
pub enum ExportFormat {
    Jpegs,
    JmZip,
    JpegsZip,
    Jmi,
    Cbz,
    Pdf,
    Epub,
}

impl ExportFormat {
    fn suffix(self) -> &'static str {
        match self {
            Self::Jpegs => "",
            Self::JmZip => ".jm.zip",
            Self::JpegsZip => ".jpegs.zip",
            Self::Jmi => ".jmi",
            Self::Cbz => ".cbzs.zip",
            Self::Pdf => ".pdf",
            Self::Epub => ".epub",
        }
    }
}

pub fn export_album(
    manager: &DownloadManager,
    album_id: i64,
    destination: &Path,
    rename: Option<&str>,
    format: ExportFormat,
    delete_exported: bool,
) -> BackendResult<PathBuf> {
    let record = manager
        .get(album_id)?
        .ok_or_else(|| BackendError::Config(format!("download album {album_id} not found")))?;
    fs::create_dir_all(destination)?;
    let base_name = safe_file_name(
        rename
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or(&record.name)
            .trim(),
        album_id,
    );
    let files = collect_album_files(manager, &record)?;
    if files.is_empty() {
        return Err(BackendError::Config(format!(
            "download album {album_id} has no exportable images"
        )));
    }

    let output = match format {
        ExportFormat::Jpegs => {
            let output = destination.join(&base_name);
            export_directory(manager, &record, &output)?;
            output
        }
        ExportFormat::JmZip | ExportFormat::JpegsZip | ExportFormat::Jmi => {
            let output = destination.join(format!("{base_name}{}", format.suffix()));
            write_album_zip(&record, &files, &output, format)?;
            output
        }
        ExportFormat::Cbz => {
            let output = destination.join(format!("{base_name}{}", format.suffix()));
            write_cbz_zip(&files, &output)?;
            output
        }
        ExportFormat::Pdf => {
            let output = destination.join(format!("{base_name}{}", format.suffix()));
            write_pdf(&files, &output)?;
            output
        }
        ExportFormat::Epub => {
            let output = destination.join(format!("{base_name}{}", format.suffix()));
            write_epub(&record, &files, &output)?;
            output
        }
    };

    if delete_exported {
        manager.delete(album_id)?;
    }
    Ok(output)
}

fn export_directory(
    manager: &DownloadManager,
    record: &DownloadAlbumRecord,
    destination: &Path,
) -> BackendResult<()> {
    let root = manager.root()?;
    fs::create_dir_all(destination)?;
    for chapter in &record.chapters {
        let source = chapter_dir(&root, record, chapter);
        let target = destination.join(chapter_folder(chapter));
        fs::create_dir_all(&target)?;
        for path in image_files(&source)? {
            let name = path
                .file_name()
                .ok_or_else(|| BackendError::Config("image has no file name".into()))?;
            fs::copy(&path, target.join(name))?;
        }
    }
    let source = album_dir(&root, record);
    if source.exists() {
        for entry in fs::read_dir(source)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_file() && is_cover(&path) {
                if let Some(name) = path.file_name() {
                    fs::copy(&path, destination.join(name))?;
                }
            }
        }
    }
    Ok(())
}

fn write_album_zip(
    record: &DownloadAlbumRecord,
    files: &[(String, PathBuf)],
    output: &Path,
    format: ExportFormat,
) -> BackendResult<()> {
    let temporary = temporary_path(output);
    let file = File::create(&temporary)?;
    let mut zip = ZipStoreWriter::new(BufWriter::new(file));
    let mut chapter_values = Vec::new();
    for chapter in &record.chapters {
        let directory = chapter_folder(chapter);
        let images = files
            .iter()
            .filter(|(name, _)| name.starts_with(&format!("{directory}/")))
            .map(|(name, _)| json!(name))
            .collect::<Vec<_>>();
        chapter_values.push(json!({
            "id": chapter.id,
            "name": chapter.name,
            "sort": chapter.sort,
            "directory_name": directory,
            "images": images,
        }));
    }
    for (name, path) in files {
        zip.add_file(name, path)?;
    }
    let manifest = json!({
        "format": "jmcomic3-mod-export",
        "version": 1,
        "task": "album",
        "kind": match format {
            ExportFormat::JmZip => "jm_zip",
            ExportFormat::JpegsZip => "jpegs_zip",
            ExportFormat::Jmi => "jmi",
            _ => "archive",
        },
        "album": {
            "id": record.id,
            "name": record.name,
            "author": record.author,
            "tags": record.tags,
            "works": record.works,
            "description": record.description,
            "directory_name": record.directory_name,
        },
        "chapters": chapter_values,
    });
    zip.add_bytes(
        "jmcomic3_manifest.json",
        &serde_json::to_vec_pretty(&manifest)?,
    )?;
    zip.finish()?;
    replace_file(&temporary, output)?;
    Ok(())
}

fn write_cbz_zip(files: &[(String, PathBuf)], output: &Path) -> BackendResult<()> {
    let temporary = temporary_path(output);
    let file = File::create(&temporary)?;
    let mut zip = ZipStoreWriter::new(BufWriter::new(file));
    for (index, (_, path)) in files.iter().enumerate() {
        let extension = path
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or("jpg");
        zip.add_file(
            &format!("{:05}.{}", index + 1, extension.to_ascii_lowercase()),
            path,
        )?;
    }
    zip.add_bytes(
        "ComicInfo.xml",
        br#"<?xml version="1.0" encoding="utf-8"?><ComicInfo></ComicInfo>"#,
    )?;
    zip.finish()?;
    replace_file(&temporary, output)?;
    Ok(())
}

fn write_pdf(files: &[(String, PathBuf)], output: &Path) -> BackendResult<()> {
    let mut images = Vec::new();
    for (_, path) in files.iter().filter(|(_, path)| !is_cover(path)) {
        let decoded = ImageReader::open(path)
            .map_err(|error| {
                BackendError::InvalidResponse(format!("open PDF image {}: {error}", path.display()))
            })?
            .decode()
            .map_err(|error| {
                BackendError::InvalidResponse(format!(
                    "decode PDF image {}: {error}",
                    path.display()
                ))
            })?
            .to_rgb8();
        let (width, height) = decoded.dimensions();
        let mut jpeg = Vec::new();
        JpegEncoder::new_with_quality(&mut Cursor::new(&mut jpeg), 88)
            .encode_image(&decoded)
            .map_err(|error| BackendError::InvalidResponse(format!("encode PDF image: {error}")))?;
        images.push((width, height, jpeg));
    }
    if images.is_empty() {
        return Err(BackendError::Config("PDF export has no images".into()));
    }

    let page_ids = (0..images.len())
        .map(|index| (3 + index * 3, 4 + index * 3, 5 + index * 3))
        .collect::<Vec<_>>();
    let kids = page_ids
        .iter()
        .map(|(page, _, _)| format!("{page} 0 R"))
        .collect::<Vec<_>>()
        .join(" ");
    let mut objects = Vec::new();
    objects.push((1, b"<< /Type /Catalog /Pages 2 0 R >>".to_vec()));
    objects.push((
        2,
        format!("<< /Type /Pages /Kids [{kids}] /Count {} >>", images.len()).into_bytes(),
    ));
    for ((page_id, content_id, image_id), (width, height, jpeg)) in
        page_ids.iter().zip(images.iter())
    {
        objects.push((
            *page_id,
            format!(
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] /Resources << /XObject << /Im0 {image_id} 0 R >> >> /Contents {content_id} 0 R >>"
            )
            .into_bytes(),
        ));
        let content = format!("q\n{width} 0 0 {height} 0 0 cm\n/Im0 Do\nQ");
        objects.push((
            *content_id,
            format!(
                "<< /Length {} >>\nstream\n{}\nendstream",
                content.len(),
                content
            )
            .into_bytes(),
        ));
        let mut image_object = format!(
            "<< /Type /XObject /Subtype /Image /Width {width} /Height {height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length {} >>\nstream\n",
            jpeg.len()
        )
        .into_bytes();
        image_object.extend_from_slice(jpeg);
        image_object.extend_from_slice(b"\nendstream");
        objects.push((*image_id, image_object));
    }
    objects.sort_by_key(|(id, _)| *id);

    let mut pdf = Vec::new();
    pdf.extend_from_slice(b"%PDF-1.4\n%\xE2\xE3\xCF\xD3\n");
    let max_id = objects.last().map_or(0, |(id, _)| *id);
    let mut offsets = vec![0_usize; max_id + 1];
    for (id, body) in &objects {
        offsets[*id] = pdf.len();
        pdf.extend_from_slice(format!("{id} 0 obj\n").as_bytes());
        pdf.extend_from_slice(body);
        pdf.extend_from_slice(b"\nendobj\n");
    }
    let xref_offset = pdf.len();
    pdf.extend_from_slice(format!("xref\n0 {}\n", max_id + 1).as_bytes());
    pdf.extend_from_slice(b"0000000000 65535 f \n");
    for offset in offsets.iter().skip(1) {
        pdf.extend_from_slice(format!("{offset:010} 00000 n \n").as_bytes());
    }
    pdf.extend_from_slice(
        format!(
            "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF\n",
            max_id + 1
        )
        .as_bytes(),
    );
    let temporary = temporary_path(output);
    fs::write(&temporary, pdf)?;
    replace_file(&temporary, output)?;
    Ok(())
}

fn write_epub(
    record: &DownloadAlbumRecord,
    files: &[(String, PathBuf)],
    output: &Path,
) -> BackendResult<()> {
    let images = files
        .iter()
        .filter(|(_, path)| is_image(path) && !is_cover(path))
        .collect::<Vec<_>>();
    if images.is_empty() {
        return Err(BackendError::Config("EPUB export has no images".into()));
    }
    let temporary = temporary_path(output);
    let file = File::create(&temporary)?;
    let mut zip = ZipStoreWriter::new(BufWriter::new(file));
    zip.add_bytes("mimetype", b"application/epub+zip")?;
    zip.add_bytes(
        "META-INF/container.xml",
        br#"<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>"#,
    )?;
    let mut manifest = Vec::new();
    let mut spine = Vec::new();
    let mut nav_items = Vec::new();
    for (index, (_, path)) in images.iter().enumerate() {
        let number = index + 1;
        let extension = path
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or("jpg")
            .to_ascii_lowercase();
        let image_name = format!("images/{number:05}.{extension}");
        zip.add_file(&format!("OEBPS/{image_name}"), path)?;
        let page_name = format!("page-{number:05}.xhtml");
        let page = format!(
            r#"<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Page {number}</title></head>
<body style="margin:0;text-align:center;"><img src="{image_name}" alt="Page {number}" style="max-width:100%;max-height:100%;"/></body></html>"#
        );
        zip.add_bytes(&format!("OEBPS/{page_name}"), page.as_bytes())?;
        manifest.push(format!(
            r#"<item id="image-{number}" href="{image_name}" media-type="{}"/>"#,
            image_media_type(&extension)
        ));
        manifest.push(format!(
            r#"<item id="page-{number}" href="{page_name}" media-type="application/xhtml+xml"/>"#
        ));
        spine.push(format!(r#"<itemref idref="page-{number}"/>"#));
        nav_items.push(format!(
            r#"<li><a href="{page_name}">Page {number}</a></li>"#
        ));
    }
    let title = escape_xml(&record.name);
    let content = format!(
        r#"<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="book-id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>{title}</dc:title><dc:identifier id="book-id">jmcomic3-{}</dc:identifier><dc:language>zh</dc:language>
</metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml"/>{}</manifest>
<spine>{}</spine></package>"#,
        record.id,
        manifest.join(""),
        spine.join("")
    );
    zip.add_bytes("OEBPS/content.opf", content.as_bytes())?;
    let nav = format!(
        r#"<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml"><head><title>{title}</title></head><body><h1>{title}</h1><ol>{}</ol></body></html>"#,
        nav_items.join("")
    );
    zip.add_bytes("OEBPS/nav.xhtml", nav.as_bytes())?;
    zip.finish()?;
    replace_file(&temporary, output)?;
    Ok(())
}

fn image_media_type(extension: &str) -> &'static str {
    match extension {
        "png" => "image/png",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "bmp" => "image/bmp",
        _ => "image/jpeg",
    }
}

fn escape_xml(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

fn collect_album_files(
    manager: &DownloadManager,
    record: &DownloadAlbumRecord,
) -> BackendResult<Vec<(String, PathBuf)>> {
    let root = manager.root()?;
    let mut files = Vec::new();
    let album_root = album_dir(&root, record);
    if album_root.exists() {
        for entry in fs::read_dir(&album_root)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_file() && is_cover(&path) {
                if let Some(name) = path.file_name().and_then(|value| value.to_str()) {
                    files.push((name.to_string(), path));
                }
            }
        }
    }
    for chapter in &record.chapters {
        let directory = chapter_folder(chapter);
        for path in image_files(&chapter_dir(&root, record, chapter))? {
            let name = path
                .file_name()
                .and_then(|value| value.to_str())
                .ok_or_else(|| BackendError::Config("image has no file name".into()))?;
            files.push((format!("{directory}/{name}"), path));
        }
    }
    files.sort_by(|left, right| left.0.cmp(&right.0));
    Ok(files)
}

fn image_files(directory: &Path) -> BackendResult<Vec<PathBuf>> {
    if !directory.exists() {
        return Ok(Vec::new());
    }
    let mut files = fs::read_dir(directory)?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.is_file() && is_image(path))
        .collect::<Vec<_>>();
    files.sort_by(|left, right| left.file_name().cmp(&right.file_name()));
    Ok(files)
}

fn is_image(path: &Path) -> bool {
    path.extension()
        .and_then(|value| value.to_str())
        .map(str::to_ascii_lowercase)
        .is_some_and(|value| {
            matches!(
                value.as_str(),
                "jpg" | "jpeg" | "png" | "gif" | "webp" | "bmp" | "avif"
            )
        })
}

fn is_cover(path: &Path) -> bool {
    path.file_stem()
        .and_then(|value| value.to_str())
        .is_some_and(|value| value.eq_ignore_ascii_case("cover"))
        && is_image(path)
}

fn chapter_folder(chapter: &DownloadChapterRecord) -> String {
    format!(
        "{}_{}_{}",
        sanitize_component(&chapter.sort),
        chapter.id,
        sanitize_component(&chapter.name)
    )
}

fn sanitize_component(value: &str) -> String {
    let mut output = String::new();
    for character in value.chars() {
        if character.is_control()
            || matches!(
                character,
                '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|'
            )
        {
            output.push('_');
        } else {
            output.push(character);
        }
    }
    let output = output.trim_matches([' ', '.', '_']);
    if output.is_empty() {
        "item".into()
    } else {
        output.chars().take(80).collect()
    }
}

fn safe_file_name(value: &str, fallback_id: i64) -> String {
    let cleaned = sanitize_component(value);
    if cleaned == "item" {
        fallback_id.to_string()
    } else {
        cleaned
    }
}

fn temporary_path(output: &Path) -> PathBuf {
    output.with_extension(format!(
        "{}.{}.tmp",
        output
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or("out"),
        std::process::id()
    ))
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
                let previous = destination.with_extension("pre-export");
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

struct ZipEntry {
    name: Vec<u8>,
    crc: u32,
    size: u32,
    offset: u32,
}

struct ZipStoreWriter<W: Write> {
    writer: W,
    offset: u32,
    entries: Vec<ZipEntry>,
}

impl<W: Write> ZipStoreWriter<W> {
    fn new(writer: W) -> Self {
        Self {
            writer,
            offset: 0,
            entries: Vec::new(),
        }
    }

    fn add_file(&mut self, name: &str, path: &Path) -> BackendResult<()> {
        let data = fs::read(path)?;
        self.add_bytes(name, &data)
    }

    fn add_bytes(&mut self, name: &str, data: &[u8]) -> BackendResult<()> {
        let name = name.replace('\\', "/").into_bytes();
        if name.is_empty() || name.len() > u16::MAX as usize || data.len() > u32::MAX as usize {
            return Err(BackendError::Config("invalid ZIP entry".into()));
        }
        let crc = crc32(data);
        let size = data.len() as u32;
        let offset = self.offset;
        self.write_u32(0x0403_4b50)?;
        self.write_u16(20)?;
        self.write_u16(0x0800)?;
        self.write_u16(0)?;
        self.write_u16(0)?;
        self.write_u16(0x0021)?;
        self.write_u32(crc)?;
        self.write_u32(size)?;
        self.write_u32(size)?;
        self.write_u16(name.len().min(u16::MAX as usize) as u16)?;
        self.write_u16(0)?;
        self.writer.write_all(&name)?;
        self.offset = self.offset.saturating_add(name.len() as u32);
        self.writer.write_all(data)?;
        self.offset = self.offset.saturating_add(size);
        self.entries.push(ZipEntry {
            name,
            crc,
            size,
            offset,
        });
        Ok(())
    }

    fn finish(mut self) -> BackendResult<()> {
        let central_offset = self.offset;
        let entries = std::mem::take(&mut self.entries);
        for entry in &entries {
            self.write_u32(0x0201_4b50)?;
            self.write_u16(20)?;
            self.write_u16(20)?;
            self.write_u16(0x0800)?;
            self.write_u16(0)?;
            self.write_u16(0)?;
            self.write_u16(0x0021)?;
            self.write_u32(entry.crc)?;
            self.write_u32(entry.size)?;
            self.write_u32(entry.size)?;
            self.write_u16(entry.name.len().min(u16::MAX as usize) as u16)?;
            self.write_u16(0)?;
            self.write_u16(0)?;
            self.write_u16(0)?;
            self.write_u16(0)?;
            self.write_u32(0)?;
            self.write_u32(entry.offset)?;
            self.writer.write_all(&entry.name)?;
            self.offset = self.offset.saturating_add(entry.name.len() as u32);
        }
        let central_size = self.offset.saturating_sub(central_offset);
        self.write_u32(0x0605_4b50)?;
        self.write_u16(0)?;
        self.write_u16(0)?;
        self.write_u16(entries.len().min(u16::MAX as usize) as u16)?;
        self.write_u16(entries.len().min(u16::MAX as usize) as u16)?;
        self.write_u32(central_size)?;
        self.write_u32(central_offset)?;
        self.write_u16(0)?;
        self.writer.flush()?;
        Ok(())
    }

    fn write_u16(&mut self, value: u16) -> io::Result<()> {
        self.writer.write_all(&value.to_le_bytes())?;
        self.offset = self.offset.saturating_add(2);
        Ok(())
    }

    fn write_u32(&mut self, value: u32) -> io::Result<()> {
        self.writer.write_all(&value.to_le_bytes())?;
        self.offset = self.offset.saturating_add(4);
        Ok(())
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
    use image::{Rgb, RgbImage};

    #[test]
    fn crc32_matches_standard_fixture() {
        assert_eq!(crc32(b"123456789"), 0xcbf4_3926);
    }

    #[test]
    fn exports_folder_zip_jmi_and_cbz_archives() {
        let root =
            std::env::temp_dir().join(format!("jmcomic3-backend-v2-export-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let app_data = root.join("app");
        let downloads_root = root.join("downloads");
        let target = root.join("target");
        let manager = DownloadManager::open(&app_data, downloads_root.clone()).unwrap();
        let record = manager
            .create(&json!({
                "album": {
                    "id": 90,
                    "name": "fixture",
                    "author": ["alice"],
                    "tags": [],
                    "works": [],
                    "description": "",
                },
                "chapters": [{"id": 91, "name": "chapter", "sort": "1"}],
            }))
            .unwrap();
        let images = chapter_dir(&downloads_root, &record, &record.chapters[0]);
        RgbImage::from_pixel(2, 2, Rgb([255, 0, 0]))
            .save(images.join("00001.png"))
            .unwrap();
        RgbImage::from_pixel(2, 2, Rgb([0, 255, 0]))
            .save(images.join("00002.png"))
            .unwrap();
        RgbImage::from_pixel(2, 2, Rgb([0, 0, 255]))
            .save(album_dir(&downloads_root, &record).join("cover.jpg"))
            .unwrap();

        for format in [
            ExportFormat::Jpegs,
            ExportFormat::JmZip,
            ExportFormat::JpegsZip,
            ExportFormat::Jmi,
            ExportFormat::Cbz,
            ExportFormat::Pdf,
            ExportFormat::Epub,
        ] {
            let output =
                export_album(&manager, 90, &target, Some("renamed"), format, false).unwrap();
            assert!(output.exists());
            if matches!(
                format,
                ExportFormat::JmZip | ExportFormat::JpegsZip | ExportFormat::Jmi
            ) {
                let bytes = fs::read(output).unwrap();
                assert!(bytes.starts_with(b"PK\x03\x04"));
                assert!(bytes
                    .windows(b"jmcomic3_manifest.json".len())
                    .any(|window| window == b"jmcomic3_manifest.json"));
            }
        }
        fs::remove_dir_all(root).unwrap();
    }
}
