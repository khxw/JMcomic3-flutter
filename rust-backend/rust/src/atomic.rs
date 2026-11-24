use std::fs;
use std::io;
use std::path::{Path, PathBuf};

fn backup_path(destination: &Path) -> PathBuf {
    let file_name = destination
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("data");
    destination.with_file_name(format!(".{file_name}.pre-replace"))
}

pub fn recover_file(destination: &Path) -> io::Result<()> {
    let backup = backup_path(destination);
    if !destination.exists() && backup.exists() {
        fs::rename(backup, destination)?;
    }
    Ok(())
}

pub fn replace_file(temporary: &Path, destination: &Path) -> io::Result<()> {
    match fs::rename(temporary, destination) {
        Ok(()) => Ok(()),
        Err(first_error) => {
            if !destination.exists() {
                return Err(first_error);
            }
            let previous = backup_path(destination);
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
    }
}
