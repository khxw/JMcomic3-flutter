use std::ffi::{CStr, CString};
use std::ptr;

use jni::objects::{JClass, JString};
use jni::sys::jstring;
use jni::JNIEnv;

use crate::ffi::{free_str_ffi, init_ffi, invoke_ffi};

#[no_mangle]
pub extern "system" fn Java_opensource_jenny_Jni_init(
    mut env: JNIEnv,
    _class: JClass,
    path: JString,
) {
    let path = match env.get_string(&path) {
        Ok(value) => value.to_string_lossy().into_owned(),
        Err(error) => {
            let _ = env.throw_new("java/lang/IllegalArgumentException", error.to_string());
            return;
        }
    };
    let path = match CString::new(path.replace('\0', "")) {
        Ok(path) => path,
        Err(error) => {
            let _ = env.throw_new("java/lang/IllegalArgumentException", error.to_string());
            return;
        }
    };
    init_ffi(path.as_ptr());
}

#[no_mangle]
pub extern "system" fn Java_opensource_jenny_Jni_invoke(
    mut env: JNIEnv,
    _class: JClass,
    request: JString,
) -> jstring {
    let request = match env.get_string(&request) {
        Ok(value) => value.to_string_lossy().into_owned(),
        Err(error) => {
            let _ = env.throw_new("java/lang/IllegalArgumentException", error.to_string());
            return ptr::null_mut();
        }
    };
    let request = match CString::new(request.replace('\0', "")) {
        Ok(request) => request,
        Err(error) => {
            let _ = env.throw_new("java/lang/IllegalArgumentException", error.to_string());
            return ptr::null_mut();
        }
    };

    let response_pointer = invoke_ffi(request.as_ptr());
    if response_pointer.is_null() {
        let _ = env.throw_new(
            "java/lang/IllegalStateException",
            "backend returned no response",
        );
        return ptr::null_mut();
    }
    let response = unsafe { CStr::from_ptr(response_pointer) }
        .to_string_lossy()
        .into_owned();
    unsafe { free_str_ffi(response_pointer) };
    match env.new_string(response) {
        Ok(value) => value.into_raw(),
        Err(error) => {
            let _ = env.throw_new("java/lang/IllegalStateException", error.to_string());
            ptr::null_mut()
        }
    }
}
