use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::Command;

// Version from git tag at build time
const VERSION: &str = env!("CARGO_PKG_VERSION");

// ANSI colors
const RED: &str = "\x1b[31m";
const GREEN: &str = "\x1b[32m";
const YELLOW: &str = "\x1b[33m";
const BLUE: &str = "\x1b[34m";
const NC: &str = "\x1b[0m";

fn colorize(color: &str, text: &str) -> String {
    if atty::is(atty::Stream::Stdout) {
        format!("{}{}{}", color, text, NC)
    } else {
        text.to_string()
    }
}

macro_rules! log_info {
    ($($arg:tt)*) => { println!("{}==>{} {}", GREEN, NC, format!($($arg)*)) };
}

macro_rules! log_warn {
    ($($arg:tt)*) => { eprintln!("{}Warning:{} {}", YELLOW, NC, format!($($arg)*)) };
}

macro_rules! log_error {
    ($($arg:tt)*) => { eprintln!("{}Error:{} {}", RED, NC, format!($($arg)*)) };
}

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

fn get_platform_suffix() -> String {
    let os = env::consts::OS;
    let arch = env::consts::ARCH;

    match (os, arch) {
        ("darwin", "aarch64") => "apple-darwin-arm64",
        ("darwin", "x86_64") => "apple-darwin-x86_64",
        ("linux", "x86_64") => "unknown-linux-gnu",
        ("linux", "aarch64") => "unknown-linux-gnu",
        _ => "unknown",
    }.to_string()
}

fn get_current_exe_path() -> Result<PathBuf, String> {
    env::current_exe().map_err(|e| e.to_string())
}

fn get_current_exe_dir() -> Result<PathBuf, String> {
    get_current_exe_path()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()).ok_or_else(|| "No parent dir".to_string()))
}

fn load_providers() -> Result<Providers, String> {
    // Try to load from bundled providers.json first (same dir as binary)
    if let Ok(exe_dir) = get_current_exe_dir() {
        let bundle_path = exe_dir.join("providers.json");
        if bundle_path.exists() {
            let content = fs::read_to_string(&bundle_path)
                .map_err(|e| e.to_string())?;
            return serde_json::from_str(&content)
                .map_err(|e| e.to_string());
        }
    }

    // Fallback to looking in current directory
    let local_path = PathBuf::from("providers.json");
    if local_path.exists() {
        let content = fs::read_to_string(&local_path)
            .map_err(|e| e.to_string())?;
        return serde_json::from_str(&content)
            .map_err(|e| e.to_string());
    }

    Err("providers.json not found".to_string())
}

fn list_providers() -> Result<(), String> {
    let providers = load_providers()?;

    println!("{}", colorize(BLUE, "Available Providers:"));
    println!("");

    let mut provider_names: Vec<_> = providers.providers.keys().collect();
    provider_names.sort();

    for name in provider_names {
        if let Some(config) = providers.providers.get(name) {
            print!("  {} {}", colorize(GREEN, &format!("{:12}", name)), config.name.as_deref().unwrap_or(name));

            if let Some(base_url) = &config.base_url {
                println!("\n               URL: {}", base_url);
            }

            if let Some(models) = &config.models {
                let mut model_strs = vec![];
                if let Some(v) = &models.haiku { model_strs.push(format!("haiku={}", v)); }
                if let Some(v) = &models.sonnet { model_strs.push(format!("sonnet={}", v)); }
                if let Some(v) = &models.opus { model_strs.push(format!("opus={}", v)); }
                if let Some(v) = &models.default { model_strs.push(format!("default={}", v)); }

                if !model_strs.is_empty() {
                    println!("\n               Models: {}", model_strs.join(" "));
                }
            }
            println!("");
        }
    }

    Ok(())
}

fn show_status(scope: &str) -> Result<(), String> {
    let path = get_settings_path(scope);

    if !path.exists() {
        log_warn!("No ccswitcher configuration found");
        println!("");
        println!("Switch to a provider:");
        println!("  ccswitcher -g -p zai      # Global");
        println!("  ccswitcher -p minimax     # Project");
        return Ok(());
    }

    let settings = read_settings(&path);

    let scope_label = if scope == "global" { "Global" } else { "Project" };
    println!("{}: {}", colorize(if scope == "global" { GREEN } else { BLUE }, scope_label), path.display());

    if let Some(base_url) = settings.env.get("ANTHROPIC_BASE_URL") {
        if let JsonValue::String(url) = base_url {
            println!("   BASE_URL: {}", url);
        }
    }

    if let Some(model) = settings.env.get("ANTHROPIC_MODEL") {
        if let JsonValue::String(m) = model {
            println!("   MODEL: {}", m);
        }
    }

    if let Some(token) = settings.env.get("ANTHROPIC_AUTH_TOKEN") {
        if let JsonValue::String(t) = token {
            println!("   AUTH_TOKEN: {}", mask_token(t));
        }
    }

    for key in ["ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL"] {
        if let Some(val) = settings.env.get(key) {
            if let JsonValue::String(v) = val {
                let short_key = key.replace("ANTHROPIC_DEFAULT_", "");
                println!("   {}: {}", short_key, v);
            }
        }
    }

    Ok(())
}

fn apply_provider(provider: &str, scope: &str) -> Result<(), String> {
    let providers = load_providers()?;

    let config = providers.providers.get(provider)
        .ok_or_else(|| format!("Provider '{}' not found", provider))?;

    let path = get_settings_path(scope);
    let mut settings = read_settings(&path);

    // Add base_url
    if let Some(base_url) = &config.base_url {
        settings.env.insert("ANTHROPIC_BASE_URL".to_string(), JsonValue::String(base_url.clone()));
    }

    // Handle auth token
    let token_key = "ANTHROPIC_AUTH_TOKEN".to_string();
    let token = settings.env.get(&token_key)
        .and_then(|v| {
            if let JsonValue::String(s) = v { Some(s.clone()) } else { None }
        });

    let token = if let Some(t) = token {
        t
    } else {
        print!("{}Enter your API Token:{}", YELLOW, NC);
        io::stdout().flush().map_err(|e| e.to_string())?;
        let mut input = String::new();
        io::stdin().read_line(&mut input).map_err(|e| e.to_string())?;
        input.trim().to_string()
    };

    if !token.is_empty() {
        settings.env.insert(token_key, JsonValue::String(token));
    }

    // Add models
    if let Some(models) = &config.models {
        if let Some(v) = &models.default {
            settings.env.insert("ANTHROPIC_MODEL".to_string(), JsonValue::String(v.clone()));
            settings.env.insert("CLAUDE_CODE_SUBAGENT_MODEL".to_string(), JsonValue::String(v.clone()));
        }
        if let Some(v) = &models.haiku {
            settings.env.insert("ANTHROPIC_DEFAULT_HAIKU_MODEL".to_string(), JsonValue::String(v.clone()));
        }
        if let Some(v) = &models.sonnet {
            settings.env.insert("ANTHROPIC_DEFAULT_SONNET_MODEL".to_string(), JsonValue::String(v.clone()));
        }
        if let Some(v) = &models.opus {
            settings.env.insert("ANTHROPIC_DEFAULT_OPUS_MODEL".to_string(), JsonValue::String(v.clone()));
        }
    }

    write_settings(&path, &settings).map_err(|e| e.to_string())?;

    log_info!("Switched to {}{}{} ({})", colorize(GREEN, provider), NC, "", scope);
    log_info!("Settings: {}", path.display());

    Ok(())
}

fn get_latest_version() -> Result<String, String> {
    let output = Command::new("curl")
        .args(["-fsSL", "https://api.github.com/repos/atom2ueki/cc-switcher/releases/latest"])
        .output()
        .map_err(|e| format!("Failed to fetch releases: {}", e))?;

    if !output.status.success() {
        return Err("Failed to fetch latest release".to_string());
    }

    let json_str = String::from_utf8_lossy(&output.stdout);

    // Parse tag_name from JSON
    let tag = json_str
        .split("\"tag_name\":\"")
        .nth(1)
        .and_then(|s| s.split('"').next())
        .map(|s| s.to_string())
        .ok_or_else(|| "Could not parse tag_name".to_string())?;

    Ok(tag)
}

fn upgrade_self() -> Result<(), String> {
    log_info!("Checking for updates...");

    // Get current version
    let current_version = VERSION;
    log_info!("Current version: v{}", current_version);

    // Get latest version from GitHub
    let latest_version = get_latest_version()?;
    log_info!("Latest version: v{}", latest_version);

    // Compare versions
    if latest_version == current_version {
        log_info!("Already at the latest version v{}", current_version);
        return Ok(());
    }

    log_info!("Upgrading from v{} to v{}...", current_version, latest_version);

    // Get platform suffix
    let platform = get_platform_suffix();
    let binary_name = format!("ccswitcher-{}", platform);

    // Download new binary to temp location
    let temp_dir = env::temp_dir();
    let temp_binary = temp_dir.join(&binary_name);

    let url = format!(
        "https://github.com/atom2ueki/cc-switcher/releases/download/{}/{}",
        latest_version, binary_name
    );

    log_info!("Downloading from: {}", url);

    let output = Command::new("curl")
        .args(["-fsSL", "-o", temp_binary.to_str().unwrap(), &url])
        .output()
        .map_err(|e| format!("Failed to download: {}", e))?;

    if !output.status.success() {
        return Err("Failed to download new binary".to_string());
    }

    // Make it executable
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&temp_binary).map_err(|e| e.to_string())?.permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&temp_binary, perms).map_err(|e| e.to_string())?;
    }

    // Get current binary path
    let current_binary = get_current_exe_path()?;

    // Backup current binary
    let backup = temp_dir.join("ccswitcher-backup");
    fs::copy(&current_binary, &backup)
        .map_err(|e| format!("Failed to backup: {}", e))?;

    // Replace current binary
    fs::copy(&temp_binary, &current_binary)
        .map_err(|e| format!("Failed to replace binary: {}", e))?;

    // Clean up temp files
    let _ = fs::remove_file(&temp_binary);
    let _ = fs::remove_file(&backup);

    log_info!("Upgrade complete! New version: v{}", latest_version);
    log_info!("Run 'ccswitcher --version' to verify");

    Ok(())
}

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
        if let Err(e) = apply_provider(&provider, scope) {
            log_error!("{}", e);
            std::process::exit(1);
        }
        return;
    }

    // Handle commands
    match &cli.command {
        Some(Commands::Status) => {
            let scope = if cli.global { "global" } else { "project" };
            if let Err(e) = show_status(scope) {
                log_error!("{}", e);
                std::process::exit(1);
            }
        }
        Some(Commands::List) => {
            if let Err(e) = list_providers() {
                log_error!("{}", e);
                std::process::exit(1);
            }
        }
        Some(Commands::Upgrade) => {
            if let Err(e) = upgrade_self() {
                log_error!("{}", e);
                std::process::exit(1);
            }
        }
        Some(Commands::Version) | None => {
            println!("CC-Switcher v{}", VERSION);
        }
    }
}
