//! luaurun — Lune 이 없는 환경에서 순수 Luau 테스트를 돌리기 위한 최소 실행기.
//!
//!   luaurun <file.luau>            파일 실행 (상대 경로 require 지원)
//!   luaurun --check <files...>     문법 검사만 (컴파일)
//!
//! Lune 과 같은 규칙으로 require 를 풀어 준다: 요청한 파일 기준 상대 경로,
//! 확장자 생략 가능(.luau / .lua), 폴더면 init.luau.

use mlua::{Lua, MultiValue, Value};
use std::cell::RefCell;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::rc::Rc;

thread_local! {
    static STACK: RefCell<Vec<PathBuf>> = RefCell::new(Vec::new());
}

fn resolve(base_dir: &Path, req: &str) -> Option<PathBuf> {
    let joined = base_dir.join(req);
    let candidates = [
        joined.clone(),
        PathBuf::from(format!("{}.luau", joined.display())),
        PathBuf::from(format!("{}.lua", joined.display())),
        joined.join("init.luau"),
        joined.join("init.lua"),
    ];
    candidates
        .into_iter()
        .find(|c| c.is_file())
        .and_then(|c| std::fs::canonicalize(c).ok())
}

fn check(files: &[String]) -> ! {
    let lua = Lua::new();
    let mut bad = 0;
    for f in files {
        let src = std::fs::read_to_string(f).expect("read failed");
        if let Err(e) = lua.load(&src).set_name(f.as_str()).into_function() {
            bad += 1;
            eprintln!("SYNTAX ERROR in {f}:\n{e}");
        }
    }
    if bad > 0 {
        eprintln!("{bad} file(s) failed to compile");
        std::process::exit(1);
    }
    println!("compiled {} file(s) OK", files.len());
    std::process::exit(0);
}

fn main() -> mlua::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: luaurun <file.luau> | luaurun --check <files...>");
        std::process::exit(2);
    }
    if args[1] == "--check" {
        check(&args[2..]);
    }

    let entry = std::fs::canonicalize(&args[1]).expect("entry file not found");
    let lua = Lua::new();
    let cache: Rc<RefCell<HashMap<PathBuf, Value>>> = Rc::new(RefCell::new(HashMap::new()));

    let lua2 = lua.clone();
    let cache2 = cache.clone();
    let require = lua.create_function(move |_, req: String| {
        let base = STACK.with(|s| {
            s.borrow()
                .last()
                .map(|p| p.parent().unwrap().to_path_buf())
                .unwrap_or_else(|| std::env::current_dir().unwrap())
        });
        let path = resolve(&base, &req).ok_or_else(|| {
            mlua::Error::runtime(format!("module not found: {} (from {})", req, base.display()))
        })?;
        if let Some(v) = cache2.borrow().get(&path) {
            return Ok(v.clone());
        }
        let src = std::fs::read_to_string(&path)?;
        STACK.with(|s| s.borrow_mut().push(path.clone()));
        let result = lua2
            .load(&src)
            .set_name(path.to_string_lossy().as_ref())
            .eval::<Value>();
        STACK.with(|s| {
            s.borrow_mut().pop();
        });
        let value = result?;
        cache2.borrow_mut().insert(path, value.clone());
        Ok(value)
    })?;
    lua.globals().set("require", require)?;

    let src = std::fs::read_to_string(&entry)?;
    STACK.with(|s| s.borrow_mut().push(entry.clone()));
    match lua
        .load(&src)
        .set_name(entry.to_string_lossy().as_ref())
        .eval::<MultiValue>()
    {
        Ok(_) => Ok(()),
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(1);
        }
    }
}
