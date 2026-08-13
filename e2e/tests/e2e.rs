//! Drive the packed python-env component through `act run --mcp` with a real
//! MCP client (rmcp), replacing the python fastmcp suite (root hermetic
//! directory: no grants — install fails cleanly without wasi:http, and
//! exec's stdlib needs none).
//!
//! Sessions are opened explicitly through the virtual `open_session` tool
//! (not session-of-1 — the old hurl flow kept it that way). `exec`/`reset`
//! address the session through the ARGUMENT channel: `_meta` is a key inside
//! the arguments, and `std:session-id` keeps its `std:` spelling there
//! (ACT-MCP §3.2 exempts the argument channel from the `dev.actcore/`
//! respelling that governs transport-level `_meta`).
//!
//! Env: ACT — the act invocation (whitespace-split), WASM — packed component.

use std::path::PathBuf;
use std::sync::Arc;

use rmcp::{
    ServiceExt,
    model::CallToolRequestParams,
    transport::{TokioChildProcess, ConfigureCommandExt},
};
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::Mutex as AsyncMutex;

/// `().serve(transport)` hands back the client-role service running over the
/// child process: role first, the unit client handler second.
type Client = rmcp::service::RunningService<rmcp::service::RoleClient, ()>;

fn act_argv() -> Vec<String> {
    std::env::var("ACT")
        .unwrap_or_else(|_| "act".into())
        .split_whitespace()
        .map(str::to_string)
        .collect()
}

fn wasm_path() -> PathBuf {
    PathBuf::from(std::env::var("WASM").unwrap_or_else(|_| {
        concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../target/wasm32-wasip2/release/python_env.wasm"
        )
        .into()
    }))
}

async fn connect() -> Client {
    let argv = act_argv();
    let mut cmd = tokio::process::Command::new(&argv[0]);
    cmd.args(&argv[1..]);
    // No grant: every assertion in this suite is hermetic.
    cmd.arg("run").arg(wasm_path()).arg("--mcp");
    let transport =
        TokioChildProcess::new(cmd.configure(|_| {})).expect("spawn act run --mcp");
    ().serve(transport)
        .await
        .expect("rmcp handshake with act run --mcp")
}

fn first_text(result: &rmcp::model::CallToolResult) -> String {
    result
        .content
        .iter()
        .filter_map(|b| match b {
            rmcp::model::ContentBlock::Text(t) => Some(t.text.clone()),
            _ => None,
        })
        .next()
        .unwrap_or_default()
}

/// The `session` fixture: a per-test session, opened through the virtual
/// tool.
async fn open_session(client: &Client) -> String {
    let opened = client
        .call_tool(CallToolRequestParams::new("open_session".to_string()))
        .await
        .expect("open_session");
    serde_json::from_str::<Value>(&{
        opened
            .content
            .iter()
            .filter_map(|b| match b {
                rmcp::model::ContentBlock::Text(t) => Some(t.text.clone()),
                _ => None,
            })
            .next()
            .unwrap_or_default()
    })
    .expect("open_session reply is JSON")["id"]
    .as_str()
    .expect("reply carries an id")
    .to_string()
}

/// The `exec_meta` fixture: `_meta` as a key INSIDE the arguments — the
/// argument channel, where `std:session-id` keeps its `std:` spelling.
fn exec_args(code: &str, session: &str) -> serde_json::Map<String, Value> {
    json!({ "code": code, "_meta": { "std:session-id": session } })
        .as_object()
        .unwrap()
        .clone()
}

async fn exec(client: &Client, session: &str, code: &str) -> rmcp::model::CallToolResult {
    client
        .call_tool(
            CallToolRequestParams::new("exec".to_string()).with_arguments(exec_args(code, session)),
        )
        .await
        .expect("exec")
}

// ---------------------------------------------------------------------------
// test_info.py
// ---------------------------------------------------------------------------

#[test]
fn manifest_reports_name_and_version() {
    let argv = act_argv();
    let out = {
        let mut cmd = std::process::Command::new(&argv[0]);
        cmd.args(&argv[1..]);
        cmd.args(["inspect", "component-manifest"])
            .arg(wasm_path())
            .output()
            .expect("run act inspect component-manifest")
    };
    assert!(out.status.success(), "inspect failed");
    let manifest: Value = serde_json::from_slice(&out.stdout).expect("manifest is JSON");
    assert_eq!(manifest["std"]["name"], "python-env");
    assert!(manifest["std"]["version"].is_string());
}

// ---------------------------------------------------------------------------
// test_tools.py
// ---------------------------------------------------------------------------

#[tokio::test]
async fn component_exposes_its_tools() {
    let client = connect().await;
    let tools = client.list_all_tools().await.expect("list_all_tools");
    assert!(tools.len() >= 2);
    client.cancel().await.ok();
}

// ---------------------------------------------------------------------------
// test_exec.py
// ---------------------------------------------------------------------------

#[tokio::test]
async fn exec_arithmetic_and_stdlib() {
    let client = connect().await;
    let session = open_session(&client).await;
    for (code, expected) in [
        ("2 + 2", "4"),
        // stdlib import + statement then expression
        ("import math\nmath.factorial(5)", "120"),
    ] {
        let result = exec(&client, &session, code).await;
        assert_eq!(first_text(&result), expected, "code: {code}");
    }
    client.cancel().await.ok();
}

// ---------------------------------------------------------------------------
// test_session.py
// ---------------------------------------------------------------------------

#[tokio::test]
async fn state_persists_across_calls_in_one_session() {
    let client = connect().await;
    let session = open_session(&client).await;
    // A variable in one call, a function in another, both used in a third —
    // all three must see the same namespace.
    exec(&client, &session, "counter = 100").await;
    exec(
        &client,
        &session,
        "def bump():\n    global counter\n    counter += 1\n    return counter",
    )
    .await;
    let result = exec(&client, &session, "bump(); bump(); counter").await;
    assert_eq!(first_text(&result), "102");
    client.cancel().await.ok();
}

// ---------------------------------------------------------------------------
// test_libs.py
// ---------------------------------------------------------------------------

#[tokio::test]
async fn all_bundled_pure_python_libraries_import_in_one_session() {
    let client = connect().await;
    let session = open_session(&client).await;
    let code = "import jinja2, markdown, bs4, rich, tabulate, slugify, yaml, dateutil, \
                attr, more_itertools, sortedcontainers, mpmath\nprint('all imported')";
    let result = exec(&client, &session, code).await;
    assert!(first_text(&result).contains("all imported"));
    client.cancel().await.ok();
}

// ---------------------------------------------------------------------------
// test_install_denied.py
// ---------------------------------------------------------------------------

#[tokio::test]
async fn install_denied_without_a_grant() {
    // Capability gate: without a wasi:http grant, install is denied (no
    // network egress happens — the host policy blocks the request).
    // Hermetic. `install` is not session-bound.
    let client = connect().await;
    let result = client
        .call_tool(
            CallToolRequestParams::new("install".to_string()).with_arguments(
                json!({"package": "six"}).as_object().unwrap().clone(),
            ),
        )
        .await
        .expect("install");
    assert!(first_text(&result).contains("install failed"));
    client.cancel().await.ok();
}

// ---------------------------------------------------------------------------
// test_show.py — exec can emit binary/image content as extra content parts
// alongside the text result. An `image/*` part becomes a native MCP
// ImageContent; a non-image mime stays a TextContent whose text is the
// base64 payload, mime in _meta["dev.actcore/mime-type"].
// ---------------------------------------------------------------------------

#[tokio::test]
async fn png_part_alongside_the_text_result() {
    // Hermetic (raw bytes, no Pillow) — the mime is sniffed from the leading
    // bytes (PNG magic here).
    let client = connect().await;
    let session = open_session(&client).await;
    let result = exec(
        &client,
        &session,
        r"show(b'\x89PNG\r\n\x1a\nFAKE'); 'img made'",
    )
    .await;
    assert_eq!(result.content.len(), 2);
    let (text_part, image_part) = match (result.content.first(), result.content.get(1)) {
        (
            Some(rmcp::model::ContentBlock::Text(t)),
            Some(rmcp::model::ContentBlock::Image(i)),
        ) => (t, i),
        other => panic!("expected text + image parts, got: {other:?}"),
    };
    assert_eq!(
        text_part
            .meta
            .as_ref()
            .and_then(|m| m.0.get("dev.actcore/mime-type"))
            .and_then(|v| v.as_str()),
        Some("text/plain")
    );
    assert!(text_part.text.contains("img made"));
    assert_eq!(image_part.mime_type, "image/png");
    assert_eq!(image_part.data, "iVBORw0KGgpGQUtF");
    client.cancel().await.ok();
}

#[tokio::test]
async fn explicit_mime_overrides_sniffing() {
    let client = connect().await;
    let session = open_session(&client).await;
    let result = exec(
        &client,
        &session,
        "show(b'hello', 'application/octet-stream'); None",
    )
    .await;
    assert_eq!(result.content.len(), 1);
    let block = match result.content.first() {
        Some(rmcp::model::ContentBlock::Text(t)) => t,
        other => panic!("expected a text block, got {other:?}"),
    };
    assert_eq!(
        block
            .meta
            .as_ref()
            .and_then(|m| m.0.get("dev.actcore/mime-type"))
            .and_then(|v| v.as_str()),
        Some("application/octet-stream")
    );
    client.cancel().await.ok();
}

// ---------------------------------------------------------------------------
// test_sqlite.py
// ---------------------------------------------------------------------------

#[tokio::test]
async fn sqlite3_in_memory_database_needs_no_capability() {
    // sqlite3 is built into the wasm CPython. An in-memory database needs NO
    // capabilities — in-process SQL alongside the Python namespace.
    let client = connect().await;
    let session = open_session(&client).await;
    let code = "import sqlite3\n\
                con = sqlite3.connect(':memory:')\n\
                con.execute('create table t(n int, s text)')\n\
                con.executemany('insert into t values (?,?)', [(1,'a'),(2,'b'),(3,'c')])\n\
                con.execute('select count(*), sum(n) from t where n > 1').fetchone()";
    let result = exec(&client, &session, code).await;
    assert_eq!(first_text(&result), "(2, 5)");
    client.cancel().await.ok();
}
