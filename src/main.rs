use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::Command;

// Version from Cargo.toml
const VERSION: &str = env!("CARGO_PKG_VERSION");

// Colors
const GREEN: &str = "\x1b[32m";
const YELLOW: &str = "\x1b[33m";
const RED: &str = "\x1b[31m";
const BLUE: &str = "\x1b[34m";
const NC: &str = "\x1b[0m";

fn is_tty() -> bool {
    atty::is(atty::Stream::Stdout)
}

fn c(color: &str, text: &str) -> String {
    if is_tty() {
        format!("{}{}{}", color, text, NC)
    } else {
        text.to_string()
    }
}

macro_rules! say {
    (info, $fmt:expr) => { println!("{} {}", c(GREEN, "➜"), $fmt); };
    (info, $fmt:expr, $($arg:tt)*) => { println!("{} {}", c(GREEN, "➜"), format!($fmt, $($arg)*)); };
    (warn, $fmt:expr) => { eprintln!("{} {}", c(YELLOW, "⚠"), $fmt); };
    (warn, $fmt:expr, $($arg:tt)*) => { eprintln!("{} {}", c(YELLOW, "⚠"), format!($fmt, $($arg)*)); };
    (error, $fmt:expr) => { eprintln!("{} {}", c(RED, "✖"), $fmt); };
    (error, $fmt:expr, $($arg:tt)*) => { eprintln!("{} {}", c(RED, "✖"), format!($fmt, $($arg)*)); };
}

// ============ Data Types ============

#[derive(Debug, Deserialize, Serialize, Clone)]
#[serde(untagged)]
enum JsonValue {
    Null,
    Bool(bool),
    Number(f64),
    String(String),
    Array(Vec<JsonValue>),
    Object(HashMap<String, JsonValue>),
}

#[derive(Debug, Deserialize, Serialize, Default)]
struct Settings {
    #[serde(default)]
    env: HashMap<String, JsonValue>,
    #[serde(flatten)]
    other: HashMap<String, JsonValue>,
}

#[derive(Debug, Deserialize)]
struct Providers {
    providers: HashMap<String, ProviderConfig>,
}

#[derive(Debug, Deserialize)]
struct ProviderConfig {
    name: Option<String>,
    base_url: Option<String>,
    models: Option<ModelsConfig>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
struct ModelsConfig {
    haiku: Option<String>,
    sonnet: Option<String>,
    opus: Option<String>,
    default: Option<String>,
}

// ============ Settings ============

fn get_settings_path(scope: &str) -> PathBuf {
    if scope == "global" {
        dirs::home_dir()
            .map(|h| h.join(".claude/settings.json"))
            .unwrap_or_else(|| PathBuf::from(".claude/settings.json"))
    } else {
        PathBuf::from(".claude/settings.local.json")
    }
}

fn read_settings(path: &PathBuf) -> Settings {
    match fs::read_to_string(path) {
        Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
        Err(_) => Settings::default(),
    }
}

fn write_settings(path: &PathBuf, settings: &Settings) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let content = serde_json::to_string_pretty(settings)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    let mut file = fs::File::create(path)?;
    file.write_all(content.as_bytes())?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(path)?.permissions();
        perms.set_mode(0o600);
        fs::set_permissions(path, perms)?;
    }

    Ok(())
}

fn mask_token(token: &str) -> String {
    if token.is_empty() {
        "[not set]".to_string()
    } else if token.starts_with("${") {
        format!("[env: {}]", &token[2..token.len()-1])
    } else if token.len() <= 8 {
        "[set] ****".to_string()
    } else {
        format!("[set] {}...{}", &token[..4], &token[token.len()-4..])
    }
}

// ============ Platform ============

fn get_platform_suffix() -> String {
    match (env::consts::OS, env::consts::ARCH) {
        ("darwin", "aarch64") => "macos-arm64",
        ("darwin", "x86_64") => "macos-x86_64",
        ("linux", "x86_64") => "linux-x86_64",
        ("linux", "aarch64") => "linux-arm64",
        _ => "unknown",
    }.to_string()
}

fn get_current_exe_dir() -> Option<PathBuf> {
    env::current_exe().ok()?.parent().map(|p| p.to_path_buf())
}

fn load_providers() -> Result<Providers, String> {
    // Try bundled providers.json (same dir as binary)
    if let Some(exe_dir) = get_current_exe_dir() {
        let bundle_path = exe_dir.join("providers.json");
        if bundle_path.exists() {
            let content = fs::read_to_string(&bundle_path)
                .map_err(|e| e.to_string())?;
            return serde_json::from_str(&content)
                .map_err(|e| e.to_string());
        }
    }

    // Fallback to current directory
    let local_path = PathBuf::from("providers.json");
    if local_path.exists() {
        let content = fs::read_to_string(&local_path)
            .map_err(|e| e.to_string())?;
        return serde_json::from_str(&content)
            .map_err(|e| e.to_string());
    }

    Err("providers.json not found".to_string())
}

// ============ Commands ============

fn cmd_list() -> Result<(), String> {
    let providers = load_providers()?;

    println!("{}", c(BLUE, "Available Providers:"));
    println!();

    let mut names: Vec<_> = providers.providers.keys().collect();
    names.sort();

    for name in names {
        if let Some(config) = providers.providers.get(name) {
            print!("  {} {}", c(GREEN, &format!("{:12}", name)), config.name.as_deref().unwrap_or(name));

            if let Some(url) = &config.base_url {
                println!("\n               URL: {}", url);
            }

            if let Some(models) = &config.models {
                let mut parts = vec![];
                if let Some(v) = &models.haiku { parts.push(format!("haiku={}", v)); }
                if let Some(v) = &models.sonnet { parts.push(format!("sonnet={}", v)); }
                if let Some(v) = &models.opus { parts.push(format!("opus={}", v)); }
                if let Some(v) = &models.default { parts.push(format!("default={}", v)); }

                if !parts.is_empty() {
                    println!("\n               Models: {}", parts.join(" "));
                }
            }
            println!();
        }
    }

    Ok(())
}

fn cmd_status(scope: &str) -> Result<(), String> {
    let path = get_settings_path(scope);

    if !path.exists() {
        say!(warn, "No ccswitcher configuration found");
        println!();
        println!("Switch to a provider:");
        println!("  ccswitcher -g -p zai      # Global");
        println!("  ccswitcher -p minimax    # Project");
        return Ok(());
    }

    let settings = read_settings(&path);
    let label = if scope == "global" { "Global" } else { "Project" };

    println!("{}: {}", c(if scope == "global" { GREEN } else { BLUE }, label), path.display());

    if let Some(JsonValue::String(url)) = settings.env.get("ANTHROPIC_BASE_URL") {
        println!("   BASE_URL: {}", url);
    }

    if let Some(JsonValue::String(m)) = settings.env.get("ANTHROPIC_MODEL") {
        println!("   MODEL: {}", m);
    }

    if let Some(JsonValue::String(t)) = settings.env.get("ANTHROPIC_AUTH_TOKEN") {
        println!("   AUTH_TOKEN: {}", mask_token(t));
    }

    for key in ["ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL"] {
        if let Some(JsonValue::String(v)) = settings.env.get(key) {
            println!("   {}: {}", key.replace("ANTHROPIC_DEFAULT_", ""), v);
        }
    }

    Ok(())
}

fn cmd_apply(provider: &str, scope: &str) -> Result<(), String> {
    let providers = load_providers()?;

    let config = providers.providers.get(provider)
        .ok_or_else(|| format!("Provider '{}' not found", provider))?;

    let path = get_settings_path(scope);
    let mut settings = read_settings(&path);

    // Set base_url
    if let Some(base_url) = &config.base_url {
        settings.env.insert("ANTHROPIC_BASE_URL".into(), JsonValue::String(base_url.clone()));
    }

    // Handle token
    let token_key = "ANTHROPIC_AUTH_TOKEN";
    let token = settings.env.get(token_key)
        .and_then(|v| if let JsonValue::String(s) = v { Some(s.clone()) } else { None });

    let token = if let Some(t) = token {
        t
    } else {
        print!("{} {} ", c(YELLOW, "Enter API Token:"), "");
        io::stdout().flush().map_err(|e| e.to_string())?;
        let mut input = String::new();
        io::stdin().read_line(&mut input).map_err(|e| e.to_string())?;
        input.trim().to_string()
    };

    if !token.is_empty() {
        settings.env.insert(token_key.into(), JsonValue::String(token));
    }

    // Set models
    if let Some(models) = &config.models {
        if let Some(v) = &models.default {
            settings.env.insert("ANTHROPIC_MODEL".into(), JsonValue::String(v.clone()));
            settings.env.insert("CLAUDE_CODE_SUBAGENT_MODEL".into(), JsonValue::String(v.clone()));
        }
        if let Some(v) = &models.haiku {
            settings.env.insert("ANTHROPIC_DEFAULT_HAIKU_MODEL".into(), JsonValue::String(v.clone()));
        }
        if let Some(v) = &models.sonnet {
            settings.env.insert("ANTHROPIC_DEFAULT_SONNET_MODEL".into(), JsonValue::String(v.clone()));
        }
        if let Some(v) = &models.opus {
            settings.env.insert("ANTHROPIC_DEFAULT_OPUS_MODEL".into(), JsonValue::String(v.clone()));
        }
    }

    write_settings(&path, &settings).map_err(|e| e.to_string())?;

    say!(info, "Switched to {} ({})", c(GREEN, provider), scope);
    say!(info, "Settings: {}", path.display());

    Ok(())
}

fn get_remote_version() -> Result<String, String> {
    let output = Command::new("curl")
        .args(["-fsSL", "https://api.github.com/repos/atom2ueki/cc-switcher/releases/latest"])
        .output()
        .map_err(|e| format!("curl failed: {}", e))?;

    if !output.status.success() {
        return Err("Failed to fetch releases".to_string());
    }

    let json = String::from_utf8_lossy(&output.stdout);
    json.split("\"tag_name\": \"")
        .nth(1)
        .and_then(|s| s.split('"').next())
        .map(|s| s.to_string())
        .ok_or_else(|| "Could not parse version".to_string())
}

fn cmd_upgrade() -> Result<(), String> {
    say!(info, "Checking for updates...");

    let current = VERSION;
    let latest = get_remote_version()?;

    say!(info, "Current: {}", current);
    say!(info, "Latest:  {}", latest);

    if latest == current {
        say!(info, "Already at latest version {}", current);
        return Ok(());
    }

    say!(info, "Upgrading from {} to {}...", current, latest);

    let platform = get_platform_suffix();
    let binary = format!("ccswitcher-{}", platform);

    let url = format!(
        "https://github.com/atom2ueki/cc-switcher/releases/download/{}/{}",
        latest, binary
    );

    say!(info, "Downloading...");

    let temp_dir = env::temp_dir();
    let temp_binary = temp_dir.join(&binary);

    let output = Command::new("curl")
        .args(["-fsSL", "-o", temp_binary.to_str().unwrap(), &url])
        .output()
        .map_err(|e| format!("Download failed: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Failed to download binary from {}: {}", url, stderr));
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&temp_binary)
            .map_err(|e| e.to_string())?
            .permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&temp_binary, perms)
            .map_err(|e| e.to_string())?;
    }

    let current_binary = env::current_exe().map_err(|e| e.to_string())?;
    fs::copy(&temp_binary, &current_binary)
        .map_err(|e| format!("Failed to replace: {}", e))?;

    let _ = fs::remove_file(&temp_binary);

    say!(info, "Upgraded to {}", latest);
    say!(info, "Run 'ccswitcher --version' to verify");

    Ok(())
}

// ============ CLI ============

#[derive(Parser)]
#[command(name = "ccswitcher")]
#[command(version = VERSION)]
#[command(about = "Switch between AI providers for Claude Code", long_about = None)]
struct Cli {
    #[arg(short, long, global = true)]
    global: bool,

    #[arg(short = 'p', long = "provider", global = true)]
    provider: Option<String>,

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Show current configuration
    Status,
    /// List available providers
    List,
    /// Upgrade to latest version
    Upgrade,
    /// Show version
    Version,
}

fn main() {
    let cli = Cli::parse();

    // Handle -p flag
    if let Some(provider) = cli.provider {
        let scope = if cli.global { "global" } else { "project" };
        if let Err(e) = cmd_apply(&provider, scope) {
            say!(error, "{}", e);
            std::process::exit(1);
        }
        return;
    }

    // Handle commands
    match &cli.command {
        Some(Commands::Status) => {
            let scope = if cli.global { "global" } else { "project" };
            if let Err(e) = cmd_status(scope) {
                say!(error, "{}", e);
                std::process::exit(1);
            }
        }
        Some(Commands::List) => {
            if let Err(e) = cmd_list() {
                say!(error, "{}", e);
                std::process::exit(1);
            }
        }
        Some(Commands::Upgrade) => {
            if let Err(e) = cmd_upgrade() {
                say!(error, "{}", e);
                std::process::exit(1);
            }
        }
        Some(Commands::Version) | None => {
            println!("CC-Switcher {}", VERSION);
        }
    }
}
