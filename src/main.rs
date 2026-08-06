use std::{
    fs, io,
    path::PathBuf,
    process::Command,
    sync::mpsc::{self, Receiver},
    thread,
    time::{Duration, Instant},
};

use crossterm::{
    event::{
        self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEvent, KeyModifiers,
        MouseEventKind,
    },
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{
        Block, Borders, Cell, Clear, Gauge, List, ListItem, ListState, Paragraph, Row, Table, Tabs,
        Wrap,
    },
    Terminal,
};
use rusqlite::Connection;
use serde::Deserialize;

const CYAN: Color = Color::Rgb(0, 224, 255);
const BLUE: Color = Color::Rgb(15, 47, 84);
const NAVY: Color = Color::Rgb(5, 12, 27);
const GREEN: Color = Color::Rgb(66, 255, 125);
const ORANGE: Color = Color::Rgb(255, 184, 77);
const PINK: Color = Color::Rgb(255, 72, 126);
const MUTED: Color = Color::Rgb(112, 136, 164);
const MENU_COUNT: usize = 9;

#[derive(Clone)]
struct DbStats {
    installed: usize,
    total: usize,
    history: usize,
    cache_mb: f64,
    status: String,
}

impl Default for DbStats {
    fn default() -> Self {
        Self {
            installed: 0,
            total: 0,
            history: 0,
            cache_mb: 0.0,
            status: "DB: ожидание".into(),
        }
    }
}

#[derive(Clone)]
struct AurPackage {
    name: String,
    version: String,
    votes: i64,
    popularity: f64,
    description: String,
}

enum PendingAction {
    Update,
    Remove(String),
    Cleanup(String),
    Benchmark,
}

struct PasswordPrompt {
    action: PendingAction,
    password: String,
}

struct ActionResult {
    label: String,
    result: String,
}

struct ConfirmModal {
    title: String,
    message: String,
    action: PendingAction,
}

struct ProgressState {
    label: String,
    started: Instant,
    stage_duration: Duration,
    stage: usize,
    frame: usize,
}

struct PackageRecord {
    name: String,
    version: String,
    source: String,
}

#[derive(Deserialize)]
struct AurResponse {
    results: Vec<AurResult>,
}

#[derive(Deserialize)]
struct AurResult {
    #[serde(rename = "Name")]
    name: String,
    #[serde(rename = "Version")]
    version: String,
    #[serde(rename = "NumVotes", default)]
    votes: i64,
    #[serde(rename = "Popularity", default)]
    popularity: f64,
    #[serde(rename = "Description", default)]
    description: Option<String>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Screen {
    Menu,
    Packages,
    Search,
    Update,
    Remove,
    Benchmark,
    Stats,
    Cleanup,
    Shell,
}

impl Screen {
    fn title(self) -> &'static str {
        match self {
            Self::Menu => "OCTO 0.5.0",
            Self::Packages => "СПИСОК ПАКЕТОВ OCTO",
            Self::Search => "ПОИСК В AUR (ТЕНТАКЛИ)",
            Self::Update => "ОБНОВЛЕНИЕ СИСТЕМЫ",
            Self::Remove => "ОСВОБОЖДЕНИЕ ПАКЕТА",
            Self::Benchmark => "OCTO БЕНЧМАРК",
            Self::Stats => "СТАТИСТИКА И ПРЕДСКАЗАНИЯ OCTO",
            Self::Cleanup => "ОЧИСТКА КЭША И ОСВОБОЖДЕНИЕ ДИСКА",
            Self::Shell => "OCTO INTERACTIVE CLI SHELL",
        }
    }

    fn accent(self) -> Color {
        match self {
            Self::Remove => PINK,
            Self::Update | Self::Benchmark => ORANGE,
            Self::Cleanup => GREEN,
            _ => CYAN,
        }
    }
}

struct App {
    screen: Screen,
    selected: usize,
    input: String,
    notice: String,
    db: DbStats,
    aur_results: Vec<AurPackage>,
    aur_loading: bool,
    aur_receiver: Option<Receiver<Result<Vec<AurPackage>, String>>>,
    modal: Option<ConfirmModal>,
    password_prompt: Option<PasswordPrompt>,
    progress: Option<ProgressState>,
    action_receiver: Option<Receiver<ActionResult>>,
    action_result: String,
    shell_history: Vec<String>,
    shell_history_index: Option<usize>,
    shell_output: Vec<String>,
    shell_scroll: usize,
    running: bool,
}

impl Default for App {
    fn default() -> Self {
        Self {
            screen: Screen::Menu,
            selected: 0,
            input: String::new(),
            notice: "Система: OK".into(),
            db: load_db_stats(),
            aur_results: Vec::new(),
            aur_loading: false,
            aur_receiver: None,
            modal: None,
            password_prompt: None,
            progress: None,
            action_receiver: None,
            action_result: "Действие ещё не запускалось".into(),
            shell_history: load_command_history(),
            shell_history_index: None,
            shell_output: vec![
                "🐙 OCTO CLI SHELL v0.5.0 (x86_64 Arch Linux)".into(),
                "Команды backend: install, search, info, diagnostic, cache-stats и другие.".into(),
                "Введите 'help' для подсказки. Введите 'exit', чтобы вернуться в TUI.".into(),
            ],
            shell_scroll: usize::MAX,
            running: true,
        }
    }
}

fn octo_home() -> PathBuf {
    std::env::var("OCTO_HOME")
        .map(PathBuf::from)
        .or_else(|_| std::env::var("HOME").map(|home| PathBuf::from(home).join(".octo")))
        .unwrap_or_else(|_| PathBuf::from(".octo"))
}

fn load_db_stats() -> DbStats {
    let root = octo_home();
    let database_path = root.join("db/octo.sqlite3");
    let cache_path = root.join("cache");
    let (installed, history_count, connected) = Connection::open(database_path)
        .ok()
        .and_then(|connection| {
            let installed = connection
                .query_row("SELECT COUNT(*) FROM packages", [], |row| row.get(0))
                .ok()?;
            let history = connection
                .query_row("SELECT COUNT(*) FROM history", [], |row| row.get(0))
                .ok()?;
            Some((installed, history, true))
        })
        .unwrap_or((0, 0, false));
    let cache_mb = dir_size_bytes(&cache_path) as f64 / 1_048_576.0;
    let status = if connected {
        "DB: подключена"
    } else {
        "DB: нет данных"
    };

    DbStats {
        installed,
        total: installed,
        history: history_count,
        cache_mb,
        status: status.into(),
    }
}

fn dir_size_bytes(path: &PathBuf) -> u64 {
    let Ok(entries) = fs::read_dir(path) else {
        return 0;
    };
    entries
        .filter_map(Result::ok)
        .map(|entry| {
            let path = entry.path();
            if path.is_dir() {
                dir_size_bytes(&path)
            } else {
                entry.metadata().map(|meta| meta.len()).unwrap_or(0)
            }
        })
        .sum()
}

fn load_packages() -> Vec<PackageRecord> {
    let database_path = octo_home().join("db/octo.sqlite3");
    let Ok(connection) = Connection::open(database_path) else {
        return Vec::new();
    };
    let Ok(mut statement) = connection.prepare(
        "SELECT name, version, COALESCE(source, 'official') FROM packages ORDER BY name COLLATE NOCASE",
    )
    else {
        return Vec::new();
    };
    statement
        .query_map([], |row| {
            Ok(PackageRecord {
                name: row.get(0)?,
                version: row.get(1)?,
                source: row.get(2)?,
            })
        })
        .map(|rows| rows.filter_map(Result::ok).collect())
        .unwrap_or_default()
}

fn load_command_history() -> Vec<String> {
    let Ok(connection) = Connection::open(octo_home().join("db/octo.sqlite3")) else {
        return Vec::new();
    };
    let Ok(mut statement) = connection.prepare(
        "SELECT package_name FROM history WHERE action = 'command' ORDER BY id DESC LIMIT 100",
    ) else {
        return Vec::new();
    };
    let mut history: Vec<String> = statement
        .query_map([], |row| row.get(0))
        .map(|rows| rows.filter_map(Result::ok).collect())
        .unwrap_or_default();
    history.reverse();
    history
}

fn start_aur_search(app: &mut App) {
    let query = if app.input.trim().is_empty() {
        "neofetch".to_string()
    } else {
        app.input.trim().to_string()
    };
    let (sender, receiver) = mpsc::channel();
    app.aur_loading = true;
    app.aur_receiver = Some(receiver);
    app.progress = Some(ProgressState {
        label: "Поиск в океане AUR".into(),
        started: Instant::now(),
        stage_duration: Duration::from_millis(850),
        stage: 0,
        frame: 0,
    });
    app.notice = format!("Ищем в AUR: {query}");
    thread::spawn(move || {
        let result = fetch_aur_results(&query);
        let _ = sender.send(result);
    });
}

fn fetch_aur_results(query: &str) -> Result<Vec<AurPackage>, String> {
    let url = format!("https://aur.archlinux.org/rpc/v5/search?arg={query}");
    let response: AurResponse = ureq::get(&url)
        .timeout(Duration::from_secs(8))
        .call()
        .map_err(|error| format!("AUR недоступен: {error}"))?
        .into_json()
        .map_err(|error| format!("Ошибка JSON AUR: {error}"))?;
    Ok(response
        .results
        .into_iter()
        .take(8)
        .map(|item| AurPackage {
            name: item.name,
            version: item.version,
            votes: item.votes,
            popularity: item.popularity,
            description: item.description.unwrap_or_default(),
        })
        .collect())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;
    let result = run(&mut terminal);
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        DisableMouseCapture,
        LeaveAlternateScreen
    )?;
    terminal.show_cursor()?;
    result?;
    Ok(())
}

fn run(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>) -> io::Result<()> {
    let mut app = App::default();
    while app.running {
        app.tick();
        terminal.draw(|frame| draw(frame, &app))?;
        if event::poll(Duration::from_millis(100))? {
            match event::read()? {
                Event::Key(key) => handle_key(&mut app, key),
                Event::Mouse(mouse) if app.screen == Screen::Shell => match mouse.kind {
                    MouseEventKind::ScrollUp => scroll_shell(&mut app, -3),
                    MouseEventKind::ScrollDown => scroll_shell(&mut app, 3),
                    _ => {}
                },
                _ => {}
            }
        }
    }
    Ok(())
}

impl App {
    fn tick(&mut self) {
        if let Some(receiver) = &self.aur_receiver {
            if let Ok(result) = receiver.try_recv() {
                self.aur_loading = false;
                self.aur_receiver = None;
                if self.action_receiver.is_none() {
                    self.progress = None;
                }
                match result {
                    Ok(results) if !results.is_empty() => {
                        self.notice = format!("AUR: найдено пакетов: {}", results.len());
                        self.aur_results = results;
                    }
                    Ok(_) => self.notice = "AUR: ничего не найдено".into(),
                    Err(error) => self.notice = error,
                }
            }
        }
        if let Some(receiver) = &self.action_receiver {
            if let Ok(result) = receiver.try_recv() {
                self.action_receiver = None;
                self.action_result = result.result;
                self.db = load_db_stats();
                self.notice = if self.action_result.starts_with("[ OK ]") {
                    format!("{}: выполнено", result.label)
                } else {
                    format!("{}: завершено с ошибкой", result.label)
                };
                self.progress = None;
            }
        }
        if let Some(progress) = &mut self.progress {
            let elapsed = progress.started.elapsed();
            progress.stage =
                (elapsed.as_millis() / progress.stage_duration.as_millis().max(1)).min(3) as usize;
            progress.frame = (elapsed.as_millis() / 180 % 4) as usize;
        }
    }
}

fn scroll_shell(app: &mut App, delta: isize) {
    let visible = 8usize;
    let max_scroll = app.shell_output.len().saturating_sub(visible);
    let current = if app.shell_scroll == usize::MAX {
        max_scroll
    } else {
        app.shell_scroll.min(max_scroll)
    };
    app.shell_scroll = if delta.is_negative() {
        current.saturating_sub(delta.unsigned_abs())
    } else {
        current.saturating_add(delta as usize).min(max_scroll)
    };
}

fn handle_key(app: &mut App, key: KeyEvent) {
    if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
        app.running = false;
        return;
    }
    if app.password_prompt.is_some() {
        match key.code {
            KeyCode::Char(c) => {
                if let Some(prompt) = app.password_prompt.as_mut() {
                    prompt.password.push(c);
                }
            }
            KeyCode::Backspace => {
                if let Some(prompt) = app.password_prompt.as_mut() {
                    prompt.password.pop();
                }
            }
            KeyCode::Enter => submit_password(app),
            KeyCode::Esc => {
                app.password_prompt = None;
                app.notice = "Операция отменена: пароль не введён".into();
            }
            _ => {}
        }
        return;
    }
    if app.modal.is_some() {
        match key.code {
            KeyCode::Char('y') | KeyCode::Enter => confirm_modal(app),
            KeyCode::Char('n') | KeyCode::Esc => {
                app.modal = None;
                app.notice = "Действие отменено".into();
            }
            _ => {}
        }
        return;
    }
    match key.code {
        KeyCode::Esc if app.screen != Screen::Menu => {
            app.screen = Screen::Menu;
            app.selected = 0;
            app.input.clear();
        }
        KeyCode::Char('q') if app.screen == Screen::Menu => app.running = false,
        KeyCode::Up | KeyCode::Char('k') if app.screen == Screen::Menu => {
            app.selected = app.selected.saturating_sub(1)
        }
        KeyCode::Down | KeyCode::Char('j') if app.screen == Screen::Menu => {
            app.selected = (app.selected + 1).min(MENU_COUNT - 1)
        }
        KeyCode::Char(c) if app.screen == Screen::Menu && ('1'..='9').contains(&c) => {
            app.screen = match c {
                '1' => Screen::Search,
                '2' => Screen::Remove,
                '3' => Screen::Update,
                '4' => Screen::Packages,
                '5' => Screen::Search,
                '6' => Screen::Benchmark,
                '7' => Screen::Stats,
                '8' => Screen::Cleanup,
                '9' => Screen::Shell,
                _ => Screen::Menu,
            };
            app.selected = 0;
        }
        KeyCode::Enter if app.screen == Screen::Menu => {
            let key = (app.selected + 1).to_string();
            handle_key(
                app,
                KeyEvent::new(
                    KeyCode::Char(key.chars().next().unwrap()),
                    KeyModifiers::NONE,
                ),
            );
        }
        KeyCode::Char('l')
            if key.modifiers.contains(KeyModifiers::CONTROL) && app.screen == Screen::Shell =>
        {
            app.shell_output.clear();
            app.shell_scroll = usize::MAX;
        }
        KeyCode::PageUp if app.screen == Screen::Shell => {
            let visible = 8usize;
            let max_scroll = app.shell_output.len().saturating_sub(visible);
            let current = if app.shell_scroll == usize::MAX {
                max_scroll
            } else {
                app.shell_scroll.min(max_scroll)
            };
            app.shell_scroll = current.saturating_sub(visible);
        }
        KeyCode::PageDown if app.screen == Screen::Shell => {
            let visible = 8usize;
            let max_scroll = app.shell_output.len().saturating_sub(visible);
            let current = if app.shell_scroll == usize::MAX {
                max_scroll
            } else {
                app.shell_scroll.min(max_scroll)
            };
            app.shell_scroll = (current + visible).min(max_scroll);
        }
        KeyCode::Up if app.screen == Screen::Shell && !app.shell_history.is_empty() => {
            let next = app
                .shell_history_index
                .unwrap_or(app.shell_history.len())
                .saturating_sub(1);
            app.shell_history_index = Some(next);
            app.input = app.shell_history[next].clone();
        }
        KeyCode::Up if app.screen == Screen::Shell => {
            let visible = 8usize;
            let max_scroll = app.shell_output.len().saturating_sub(visible);
            let current = if app.shell_scroll == usize::MAX {
                max_scroll
            } else {
                app.shell_scroll.min(max_scroll)
            };
            app.shell_scroll = current.saturating_sub(1);
        }
        KeyCode::Down if app.screen == Screen::Shell && app.shell_history_index.is_some() => {
            match app.shell_history_index {
                Some(index) if index + 1 < app.shell_history.len() => {
                    app.shell_history_index = Some(index + 1);
                    app.input = app.shell_history[index + 1].clone();
                }
                Some(_) => {
                    app.shell_history_index = None;
                    app.input.clear();
                }
                None => {}
            }
        }
        KeyCode::Down if app.screen == Screen::Shell => {
            let visible = 8usize;
            let max_scroll = app.shell_output.len().saturating_sub(visible);
            let current = if app.shell_scroll == usize::MAX {
                max_scroll
            } else {
                app.shell_scroll.min(max_scroll)
            };
            app.shell_scroll = (current + 1).min(max_scroll);
        }
        KeyCode::Home if app.screen == Screen::Shell => {
            app.shell_scroll = 0;
        }
        KeyCode::End if app.screen == Screen::Shell => {
            app.shell_scroll = usize::MAX;
        }
        KeyCode::Tab if app.screen == Screen::Shell => complete_shell_input(app),
        KeyCode::Char(c)
            if matches!(app.screen, Screen::Search | Screen::Remove | Screen::Shell) =>
        {
            app.input.push(c)
        }
        KeyCode::Backspace
            if matches!(app.screen, Screen::Search | Screen::Remove | Screen::Shell) =>
        {
            app.input.pop();
        }
        KeyCode::Enter if app.screen == Screen::Search => {
            start_aur_search(app);
        }
        KeyCode::Enter if app.screen == Screen::Remove => {
            if app.input.trim().is_empty() {
                app.notice = "Укажите имя пакета перед удалением".into();
                return;
            }
            app.modal = Some(ConfirmModal {
                title: "Подтвердить удаление".into(),
                message: "Удаление пакета изменит систему. Продолжить?".into(),
                action: PendingAction::Remove(app.input.clone()),
            });
        }
        KeyCode::Enter if app.screen == Screen::Update => {
            app.modal = Some(ConfirmModal {
                title: "Подтвердить обновление".into(),
                message: "Будет подготовлен запуск backend-обновления pacman + AUR.".into(),
                action: PendingAction::Update,
            });
        }
        KeyCode::Enter if app.screen == Screen::Cleanup => {
            app.modal = Some(ConfirmModal {
                title: "Подтвердить очистку".into(),
                message: "Очистка может удалить кэш и старые сборки.".into(),
                action: PendingAction::Cleanup("cache".into()),
            });
        }
        KeyCode::Enter if app.screen == Screen::Benchmark => {
            app.modal = Some(ConfirmModal {
                title: "Запустить benchmark".into(),
                message: "Будет выполнен сетевой запрос к AUR API.".into(),
                action: PendingAction::Benchmark,
            });
        }
        KeyCode::Enter if app.screen == Screen::Shell => execute_shell_command(app),
        _ => {}
    }
}

fn shell_help() -> Vec<String> {
    vec![
        "Доступные команды OCTO:".into(),
        "  install <pkg> [--aur]   установить пакет".into(),
        "  remove <pkg>            удалить пакет".into(),
        "  update                  обновить систему".into(),
        "  search <query>          поиск в репозиториях и AUR".into(),
        "  info <pkg>              информация о пакете".into(),
        "  search --aur <query>    поиск только в AUR".into(),
        "  list                    список установленных пакетов".into(),
        "  stats                   статистика OCTO".into(),
        "  cache-stats             статистика кэша".into(),
        "  clean cache             очистить кэш".into(),
        "  benchmark               проверить производительность".into(),
        "  diagnostic              проверить зависимости".into(),
        "  monitor                 мониторинг системы".into(),
        "  backup / restore <file> бэкап и восстановление".into(),
        "  security <file>         проверить PKGBUILD".into(),
        "  catch/release <pkg>     AUR-операции".into(),
        "  tentacle/ink <value>    AUR-поиск и информация".into(),
        "  sandbox <pkg>           установка в sandbox-режиме".into(),
        "  army                    обновить установленные пакеты".into(),
        "  profile/predict <...>   мониторинг и прогноз".into(),
        "  logs                    показать последние ошибки".into(),
        "  market/matrix/pulse     дополнительные режимы OCTO".into(),
        "  clear                   очистить вывод shell".into(),
        "  exit                    вернуться в TUI".into(),
        "Для произвольных команд системы используйте обычный shell вне OCTO.".into(),
    ]
}

fn confirm_modal(app: &mut App) {
    if app.action_receiver.is_some() {
        return;
    }
    let Some(modal) = app.modal.take() else {
        return;
    };
    let needs_sudo = matches!(
        modal.action,
        PendingAction::Update | PendingAction::Remove(_) | PendingAction::Cleanup(_)
    );
    if needs_sudo {
        app.password_prompt = Some(PasswordPrompt {
            action: modal.action,
            password: String::new(),
        });
        return;
    }
    start_pending_action(app, modal.action, None);
}

fn submit_password(app: &mut App) {
    let Some(prompt) = app.password_prompt.take() else {
        return;
    };
    if prompt.password.is_empty() {
        app.action_result = "[ FAIL ] пароль не введён".into();
        app.notice = "Операция отменена".into();
        return;
    }
    start_pending_action(app, prompt.action, Some(prompt.password));
}

fn start_pending_action(app: &mut App, action: PendingAction, password: Option<String>) {
    if app.action_receiver.is_some() {
        return;
    }
    let (label, args) = match action {
        PendingAction::Update => ("Обновление системы".to_string(), vec!["update".to_string()]),
        PendingAction::Remove(package) => (
            format!("Удаление {package}"),
            vec!["remove".to_string(), package],
        ),
        PendingAction::Cleanup(target) => (
            format!("Очистка {target}"),
            vec!["clean".to_string(), target],
        ),
        PendingAction::Benchmark => ("Benchmark AUR".to_string(), vec!["benchmark".to_string()]),
    };
    let (sender, receiver) = mpsc::channel();
    let needs_sudo = password.is_some();
    let progress_label = label.clone();
    app.action_receiver = Some(receiver);
    app.progress = Some(ProgressState {
        label: progress_label.clone(),
        started: Instant::now(),
        stage_duration: Duration::from_secs(2),
        stage: 0,
        frame: 0,
    });
    app.action_result = if needs_sudo {
        "[ … ] пароль принят, проверяется sudo…".into()
    } else {
        "[ … ] запускается backend…".into()
    };
    app.notice = if needs_sudo {
        format!("{label}: проверка sudo и запуск backend…")
    } else {
        format!("{label}: запуск backend…")
    };
    thread::spawn(move || {
        let result = if let Some(password) = password {
            match validate_sudo_password(&password) {
                Ok(()) => {
                    drop(password);
                    run_backend_action(&args, true)
                }
                Err(error) => error,
            }
        } else {
            run_backend_action(&args, false)
        };
        let _ = sender.send(ActionResult { label, result });
    });
}

fn validate_sudo_password(password: &str) -> Result<(), String> {
    let result = Command::new("sudo")
        .args(["-S", "-p", "", "-v"])
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .and_then(|mut child| {
            if let Some(mut stdin) = child.stdin.take() {
                use std::io::Write;
                stdin.write_all(password.as_bytes())?;
                stdin.write_all(b"\n")?;
            }
            child.wait_with_output()
        });
    match result {
        Ok(output) if output.status.success() => Ok(()),
        Ok(output) => {
            let detail = String::from_utf8_lossy(&output.stderr).trim().to_string();
            if detail.is_empty() {
                Err("[ FAIL ] пароль sudo не принят".into())
            } else {
                Err(format!("[ FAIL ] пароль sudo не принят: {detail}"))
            }
        }
        Err(error) => Err(format!("[ FAIL ] не удалось проверить sudo: {error}")),
    }
}

fn run_backend_action(args: &[String], confirmed: bool) -> String {
    let path = octo_backend_path();
    let mut command = Command::new(path);
    command.args(args);
    command.env("OCTO_TUI", "1");
    if confirmed {
        command.env("OCTO_CONFIRMED", "1");
    }
    match command.output() {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let stderr = String::from_utf8_lossy(&output.stderr);
            let mut lines = stdout
                .lines()
                .map(str::to_owned)
                .chain(stderr.lines().map(|line| format!("stderr: {line}")))
                .collect::<Vec<_>>();
            const MAX_ACTION_LINES: usize = 20;
            if lines.len() > MAX_ACTION_LINES {
                lines.truncate(MAX_ACTION_LINES);
                lines.push("… вывод сокращён; подробный результат доступен в CLI SHELL".into());
            }
            let result = lines.join("\n");
            if output.status.success() {
                format!("[ OK ]\n{result}")
            } else {
                format!("[ FAIL ] код выхода: {}\n{result}", output.status)
            }
        }
        Err(error) => format!("[ FAIL ] ошибка запуска backend: {error}"),
    }
}

fn execute_shell_command(app: &mut App) {
    let command_line = app.input.trim().to_string();
    app.input.clear();
    app.shell_history_index = None;
    if command_line.is_empty() {
        return;
    }
    app.shell_history.push(command_line.clone());
    record_command_history(&command_line);
    app.shell_output
        .push(format!("octo@arch :~$ {command_line}"));

    let tokens: Vec<&str> = command_line.split_whitespace().collect();
    let command = tokens.first().copied().unwrap_or_default();
    if command == "exit" || command == "quit" {
        app.screen = Screen::Menu;
        return;
    }
    if command == "clear" {
        app.shell_output.clear();
        app.shell_scroll = usize::MAX;
        return;
    }
    if command == "help" || (command == "octo" && tokens.get(1) == Some(&"help")) {
        app.shell_output.extend(shell_help());
        return;
    }

    let args = match normalize_shell_args(&tokens) {
        Ok(args) => args,
        Err(message) => {
            app.shell_output.push(format!("ошибка: {message}"));
            return;
        }
    };
    let path = octo_backend_path();
    let result = Command::new(path).args(&args).output();
    app.shell_scroll = usize::MAX;
    match result {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let stderr = String::from_utf8_lossy(&output.stderr);
            app.shell_output.extend(stdout.lines().map(str::to_owned));
            app.shell_output
                .extend(stderr.lines().map(|line| format!("stderr: {line}")));
            if output.status.success() {
                app.shell_output.push("[ OK ] команда завершена".into());
            } else {
                app.shell_output
                    .push(format!("[ FAIL ] код выхода: {}", output.status));
            }
        }
        Err(error) => app
            .shell_output
            .push(format!("ошибка запуска backend: {error}")),
    }
}

fn record_command_history(command_line: &str) {
    let Ok(connection) = Connection::open(octo_home().join("db/octo.sqlite3")) else {
        return;
    };
    let _ = connection.execute(
        "INSERT INTO history(action, package_name, version) VALUES('command', ?1, 'unknown')",
        [command_line],
    );
}

fn shell_commands() -> &'static [&'static str] {
    &[
        "help",
        "install",
        "установить",
        "remove",
        "удалить",
        "update",
        "обновить",
        "search",
        "поиск",
        "info",
        "инфо",
        "deps",
        "dependencies",
        "зависимости",
        "list",
        "stats",
        "cache-stats",
        "size",
        "размер",
        "popularity",
        "популярность",
        "clean",
        "очистить",
        "benchmark",
        "diagnostic",
        "monitor",
        "backup",
        "бэкап",
        "restore",
        "восстановить",
        "security",
        "безопасность",
        "army",
        "logs",
        "history",
        "version",
        "версия",
        "alias",
        "config",
        "настройки",
        "алиас",
        "поймать",
        "catch",
        "отпустить",
        "release",
        "щупальца",
        "tentacle",
        "чернила",
        "статистика",
        "очистка",
        "бэкап",
        "восстановить",
        "exit",
    ]
}

fn complete_shell_input(app: &mut App) {
    let prefix = app.input.clone();
    if prefix.split_whitespace().count() <= 1 {
        if let Some(command) = shell_commands()
            .iter()
            .find(|command| command.starts_with(prefix.as_str()))
        {
            app.input = (*command).to_string();
        }
        return;
    }
    let tokens: Vec<&str> = prefix.split_whitespace().collect();
    if matches!(tokens.first().copied(), Some("restore" | "security")) && tokens.len() == 2 {
        let argument = tokens[1];
        let path = PathBuf::from(argument);
        let directory = path.parent().unwrap_or_else(|| std::path::Path::new("."));
        let file_prefix = path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or_default();
        if let Ok(entries) = fs::read_dir(directory) {
            if let Some(candidate) = entries
                .filter_map(Result::ok)
                .map(|entry| entry.path())
                .filter(|candidate| {
                    candidate
                        .file_name()
                        .and_then(|name| name.to_str())
                        .is_some_and(|name| name.starts_with(file_prefix))
                })
                .min_by(|left, right| left.to_string_lossy().cmp(&right.to_string_lossy()))
            {
                let candidate = candidate.to_string_lossy();
                app.input = format!("{} {}", tokens[0], candidate);
            }
        }
        return;
    }
    if !matches!(
        tokens.first().copied(),
        Some(
            "remove"
                | "info"
                | "ink"
                | "deps"
                | "dependencies"
                | "зависимости"
                | "security"
                | "restore"
                | "чернила"
                | "отпустить",
        )
    ) {
        return;
    }
    let package_prefix = tokens.last().copied().unwrap_or_default();
    if let Some(package) = load_packages()
        .into_iter()
        .map(|package| package.name)
        .find(|name| name.starts_with(package_prefix))
    {
        let command = tokens[..tokens.len() - 1].join(" ");
        app.input = format!("{command} {package}");
    }
}

fn normalize_shell_args(tokens: &[&str]) -> Result<Vec<String>, String> {
    let command = tokens.first().copied().unwrap_or_default();
    let args = &tokens[1..];
    let mut normalized = Vec::new();
    if tokens.iter().any(|token| {
        token.chars().any(|character| {
            matches!(
                character,
                ';' | '|' | '&' | '`' | '$' | '>' | '<' | '(' | ')' | '{' | '}' | '\n' | '\r'
            )
        })
    }) {
        return Err("команда содержит запрещённые shell-символы".into());
    }
    let command = match command {
        "поймать" => "catch",
        "установить" | "инсталл" => "install",
        "отпустить" => "release",
        "удалить" => "remove",
        "щупальца" => "tentacle",
        "чернила" | "инфо" => "ink",
        "зависимости" | "dependencies" => "deps",
        "армия" => "army",
        "ракушка" => "shell",
        "статистика" => "stats",
        "очистка" => "clean",
        "очистить" => "clean",
        "бэкап" => "backup",
        "восстановить" => "restore",
        "история" => "history",
        "алиас" => "алиас",
        "настройки" => "настройки",
        "alias" => "алиас",
        "config" => "настройки",
        "поиск" => "search",
        "найти" => "search",
        "обновить" => "update",
        "помощь" => "help",
        "журнал" => "logs",
        "список" => "list",
        "кэш" => "cache-stats",
        "диагностика" => "diagnostic",
        "монитор" => "monitor",
        "тест" => "benchmark",
        "безопасность" => "security",
        "версия" => "version",
        "размер" => "size",
        "популярность" => "popularity",
        other => other,
    };
    match command {
        "help" => normalized.push("help".into()),
        "install" | "i" => {
            if args.iter().filter(|arg| !arg.starts_with('-')).count() != 1 {
                return Err("укажите один пакет: install <pkg>".into());
            }
            let package = args
                .iter()
                .find(|arg| !arg.starts_with('-'))
                .ok_or("укажите пакет: install <pkg>")?;
            normalized.push("install".into());
            if args.contains(&"--aur") || args.contains(&"-a") {
                normalized.push("--aur".into());
            }
            normalized.push((*package).into());
        }
        "remove" | "uninstall" | "r" => {
            if args.len() != 1 {
                return Err("укажите один пакет: remove <pkg>".into());
            }
            let package = args.first().ok_or("укажите пакет: remove <pkg>")?;
            normalized = vec!["remove".into(), (*package).into()];
        }
        "update" | "upgrade" => normalized.push("update".into()),
        "search" | "find" => {
            if args.iter().filter(|arg| !arg.starts_with('-')).count() != 1 {
                return Err("укажите один запрос: search <query>".into());
            }
            let query = args
                .iter()
                .find(|arg| !arg.starts_with('-'))
                .ok_or("укажите запрос: search <query>")?;
            normalized.push("search".into());
            if args.contains(&"--aur") || args.contains(&"-a") {
                normalized.push("--aur".into());
            }
            normalized.push((*query).into());
        }
        "list" | "ls" | "shell" => normalized.push("list".into()),
        "stats" => normalized.push("stats".into()),
        "cache-stats" => normalized.push("cache-stats".into()),
        "size" | "popularity" => {
            if args.len() != 1 {
                return Err(format!("укажите пакет: {command} <pkg>"));
            }
            normalized = vec![command.into(), args[0].into()];
        }
        "benchmark" | "bench" => normalized.push("benchmark".into()),
        "diagnostic" | "diag" => normalized.push("diagnostic".into()),
        "monitor" => normalized.push("monitor".into()),
        "version" | "-v" => normalized.push("version".into()),
        "backup" => normalized.push("backup".into()),
        "army" => normalized.push("army".into()),
        "logs" => normalized.push("logs".into()),
        "history" => {
            if args.len() > 1 {
                return Err("history не принимает аргументы; используйте clean history".into());
            }
            normalized.push("history".into());
        }
        "алиас" => {
            if args.len() > 3 {
                return Err("алиас: список | добавить <имя> <команда> | удалить <имя>".into());
            }
            normalized.push("алиас".into());
            normalized.extend(args.iter().map(|arg| (*arg).into()));
        }
        "настройки" => {
            if args.len() > 2 {
                return Err("настройки: настройки тема океан|классическая".into());
            }
            normalized.push("настройки".into());
            normalized.extend(args.iter().map(|arg| (*arg).into()));
        }
        "info" | "ink" | "deps" | "security" | "catch" | "release" | "tentacle" => {
            if args.len() != 1 {
                return Err(format!("укажите аргумент: {command} <value>"));
            }
            normalized.push(command.into());
            normalized.push(args[0].into());
        }
        "restore" => {
            if args.len() != 1 {
                return Err("укажите файл: restore <backup>".into());
            }
            normalized = vec!["restore".into(), args[0].into()];
        }
        "clean" => {
            let target = args
                .first()
                .copied()
                .ok_or("укажите область: clean cache|backups|all")?;
            let target = match target {
                "кэш" => "cache",
                "бэкапы" => "backups",
                "историю" | "история" => "history",
                "всё" => "all",
                value if matches!(value, "cache" | "backups" | "history" | "all") => value,
                _ => {
                    return Err(
                        "доступно: cache|кэш, backups|бэкапы, history|историю, all|всё".into(),
                    )
                }
            };
            normalized = vec!["clean".into(), target.into()];
        }
        _ => return Err("неизвестная команда. Введите help".into()),
    }
    Ok(normalized)
}

fn octo_backend_path() -> PathBuf {
    if let Ok(path) = std::env::var("OCTO_BACKEND") {
        return PathBuf::from(path);
    }
    let current = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let local = current.join("octo");
    if local.exists() {
        return local;
    }
    current.join("../octo")
}

fn draw(frame: &mut ratatui::Frame, app: &App) {
    let area = frame.area();
    frame.render_widget(Block::default().style(Style::default().bg(NAVY)), area);
    let outer = centered(area, 0.96, 0.92);
    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(5),
            Constraint::Length(3),
        ])
        .split(outer);
    draw_header(frame, layout[0], app.screen);
    draw_content(frame, layout[1], app);
    draw_footer(frame, layout[2], app.screen);
    if let Some(progress) = &app.progress {
        draw_progress(frame, layout[1], progress);
    }
    if let Some(modal) = &app.modal {
        draw_modal(frame, area, modal);
    }
    if let Some(prompt) = &app.password_prompt {
        draw_password_prompt(frame, area, prompt);
    }
}

fn centered(area: Rect, width_ratio: f32, height_ratio: f32) -> Rect {
    let width = ((area.width as f32) * width_ratio) as u16;
    let height = ((area.height as f32) * height_ratio) as u16;
    Rect {
        x: area.x + area.width.saturating_sub(width) / 2,
        y: area.y + area.height.saturating_sub(height) / 2,
        width,
        height,
    }
}

fn draw_header(frame: &mut ratatui::Frame, area: Rect, screen: Screen) {
    let title = format!(" 🐙 {} — ТВОЙ ОСЬМИНОГ В МИРЕ ARCH LINUX ", screen.title());
    let header = Paragraph::new(Line::from(vec![
        Span::styled(" ARCH_OCTO_CORE ", Style::default().fg(PINK)),
        Span::styled(
            "│ CPU/RAM: см. monitor │ backend: C++17",
            Style::default().fg(CYAN),
        ),
        Span::styled(
            "  [ Ocean Blue ] [ 🔊 ЗВУК ON ] [ CRT: ON ]",
            Style::default().fg(MUTED),
        ),
    ]))
    .block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(CYAN)),
    );
    frame.render_widget(header, area);
    let title_area = Rect {
        x: area.x + 2,
        y: area.y + 1,
        width: area.width.saturating_sub(4),
        height: 1,
    };
    frame.render_widget(
        Paragraph::new(title)
            .alignment(ratatui::layout::Alignment::Center)
            .style(
                Style::default()
                    .fg(screen.accent())
                    .add_modifier(Modifier::BOLD),
            ),
        title_area,
    );
}

fn draw_footer(frame: &mut ratatui::Frame, area: Rect, screen: Screen) {
    let line = if screen == Screen::Shell {
        Line::from(vec![
            Span::styled(" help ", Style::default().fg(CYAN)),
            Span::styled("команды   ", Style::default().fg(MUTED)),
            Span::styled("Enter", Style::default().fg(CYAN)),
            Span::styled(" выполнить   ", Style::default().fg(MUTED)),
            Span::styled("Ctrl+L", Style::default().fg(CYAN)),
            Span::styled(" очистить   ", Style::default().fg(MUTED)),
            Span::styled("exit", Style::default().fg(CYAN)),
            Span::styled(" вернуться", Style::default().fg(MUTED)),
        ])
    } else {
        Line::from(vec![
            Span::styled(" ↑↓/j/k ", Style::default().fg(CYAN)),
            Span::styled("навигация   ", Style::default().fg(MUTED)),
            Span::styled("Enter", Style::default().fg(CYAN)),
            Span::styled(" выбор   ", Style::default().fg(MUTED)),
            Span::styled("1-9", Style::default().fg(CYAN)),
            Span::styled(" быстрые действия   ", Style::default().fg(MUTED)),
            Span::styled("Esc", Style::default().fg(CYAN)),
            Span::styled(" назад   ", Style::default().fg(MUTED)),
            Span::styled("q", Style::default().fg(CYAN)),
            Span::styled(" выход", Style::default().fg(MUTED)),
        ])
    };
    let footer = Paragraph::new(line).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(BLUE)),
    );
    frame.render_widget(footer, area);
}

fn draw_content(frame: &mut ratatui::Frame, area: Rect, app: &App) {
    match app.screen {
        Screen::Menu => draw_menu(frame, area, app),
        Screen::Packages => draw_packages(frame, area, app),
        Screen::Search => draw_search(frame, area, app),
        Screen::Stats => draw_stats(frame, area, app),
        Screen::Cleanup => draw_cleanup(frame, area, app),
        Screen::Update => draw_action(
            frame,
            area,
            Screen::Update,
            app,
            "Нажмите Enter для запуска реального pacman -Syu",
            &[
                "Backend выполнит pacman -Syu с запросом подтверждения.",
                "AUR-пакеты автоматически не обновляются этой кнопкой.",
            ],
        ),
        Screen::Remove => draw_action(
            frame,
            area,
            Screen::Remove,
            app,
            "Освобождение пакета требует подтверждения backend-командой",
            &[
                "Введите имя пакета в поле ниже и нажмите Enter.",
                "Backend запросит подтверждение перед удалением.",
            ],
        ),
        Screen::Benchmark => draw_action(
            frame,
            area,
            Screen::Benchmark,
            app,
            "Нажмите Enter для реального запроса к AUR API",
            &["Benchmark измеряет DNS, TCP, TLS, TTFB и total через curl."],
        ),
        Screen::Shell => draw_shell(frame, area, app),
    }
}

fn panel<'a>(title: &'a str, color: Color) -> Block<'a> {
    Block::default()
        .title(Span::styled(
            title,
            Style::default().fg(color).add_modifier(Modifier::BOLD),
        ))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(color))
}

fn draw_progress(frame: &mut ratatui::Frame, area: Rect, progress: &ProgressState) {
    let elapsed = progress.started.elapsed().as_secs_f64();
    let stage_total = progress.stage_duration.as_secs_f64().max(0.1);
    let stage_ratio = (elapsed / stage_total).fract();
    let ratio = ((progress.stage as f64 + stage_ratio) / 4.0).clamp(0.0, 0.99);
    let progress_area = Rect {
        x: area.x + area.width / 4,
        y: area.y + area.height.saturating_sub(4),
        width: area.width / 2,
        height: 5,
    };
    let stages = [
        "🌊 Океан поиска…",
        "🐙 Щупальца тянутся к источнику…",
        "🦑 Проверка зависимостей…",
        "🐙 Выполнение операции…",
    ];
    let octopus_count = ((ratio * 10.0) as usize).clamp(1, 10);
    let moving_octopus = ["🐙", "🦑", "🐙", "🦑"][progress.frame];
    let octopus_bar = format!(
        "{}{}{}",
        "🐙".repeat(octopus_count.saturating_sub(1)),
        moving_octopus,
        "·".repeat(10usize.saturating_sub(octopus_count))
    );
    let label = format!(
        "{}  {}  {}%",
        stages[progress.stage.min(stages.len() - 1)],
        octopus_bar,
        (ratio * 100.0) as u16
    );
    frame.render_widget(
        Gauge::default()
            .block(panel(label.as_str(), ORANGE))
            .gauge_style(
                Style::default()
                    .fg(ORANGE)
                    .bg(BLUE)
                    .add_modifier(Modifier::BOLD),
            )
            .ratio(ratio)
            .label(format!("🐙 {}", progress.label)),
        progress_area,
    );
}

fn draw_modal(frame: &mut ratatui::Frame, area: Rect, modal: &ConfirmModal) {
    let modal_area = centered(area, 0.48, 0.28);
    frame.render_widget(Clear, modal_area);
    frame.render_widget(
        Paragraph::new(vec![
            Line::from(Span::styled(
                modal.message.as_str(),
                Style::default().fg(Color::White),
            )),
            Line::from(""),
            Line::from(vec![
                Span::styled(
                    "Enter/Y",
                    Style::default().fg(GREEN).add_modifier(Modifier::BOLD),
                ),
                Span::styled(" подтвердить     ", Style::default().fg(MUTED)),
                Span::styled(
                    "Esc/N",
                    Style::default().fg(PINK).add_modifier(Modifier::BOLD),
                ),
                Span::styled(" отменить", Style::default().fg(MUTED)),
            ]),
        ])
        .wrap(Wrap { trim: false })
        .block(panel(modal.title.as_str(), ORANGE)),
        modal_area,
    );
}

fn draw_password_prompt(frame: &mut ratatui::Frame, area: Rect, prompt: &PasswordPrompt) {
    let modal_area = centered(area, 0.52, 0.30);
    let masked = "*".repeat(prompt.password.chars().count());
    frame.render_widget(Clear, modal_area);
    frame.render_widget(
        Paragraph::new(vec![
            Line::from("Для выполнения операции нужны права администратора."),
            Line::from("Пароль не сохраняется и не отображается."),
            Line::from(""),
            Line::from(vec![
                Span::styled("Пароль: ", Style::default().fg(CYAN)),
                Span::styled(masked, Style::default().fg(Color::White)),
                Span::styled("█", Style::default().fg(CYAN)),
            ]),
            Line::from(""),
            Line::from(vec![
                Span::styled("Enter", Style::default().fg(GREEN)),
                Span::styled(" подтвердить   ", Style::default().fg(MUTED)),
                Span::styled("Esc", Style::default().fg(PINK)),
                Span::styled(" отменить", Style::default().fg(MUTED)),
            ]),
        ])
        .block(panel("ПАРОЛЬ SUDO", ORANGE)),
        modal_area,
    );
}

fn draw_menu(frame: &mut ratatui::Frame, area: Rect, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(5),
            Constraint::Length(5),
            Constraint::Min(12),
            Constraint::Length(3),
        ])
        .split(area);

    let cards = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(25),
            Constraint::Percentage(25),
            Constraint::Percentage(25),
            Constraint::Percentage(25),
        ])
        .split(chunks[0]);
    frame.render_widget(
        metric_card(
            "📦 Пакеты",
            app.db.total.to_string(),
            format!("{} установлено", app.db.installed),
            CYAN,
        ),
        cards[0],
    );
    frame.render_widget(
        metric_card("🔄 Обновления", "—", "проверьте через update", ORANGE),
        cards[1],
    );
    frame.render_widget(
        metric_card("⚡ AUR latency", "—", "запустите benchmark", GREEN),
        cards[2],
    );
    frame.render_widget(
        metric_card("🛡 Система", "OK", app.db.status.as_str(), GREEN),
        cards[3],
    );

    frame.render_widget(
        Paragraph::new(vec![
            Line::from(vec![
                Span::styled(
                    "Добро пожаловать в OCTO. ",
                    Style::default().fg(CYAN).add_modifier(Modifier::BOLD),
                ),
                Span::styled(
                    "Выберите действие слева или откройте привычный CLI SHELL.",
                    Style::default().fg(Color::White),
                ),
            ]),
            Line::from(Span::styled(
                "Совет: пункт 9 открывает CLI SHELL с реальными backend-командами.",
                Style::default().fg(MUTED),
            )),
        ])
        .block(panel("🐙 БЫСТРЫЙ СТАРТ", CYAN)),
        chunks[1],
    );

    let body = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(62), Constraint::Percentage(38)])
        .split(chunks[2]);
    let menu = menu_items();
    let items = menu.iter().enumerate().map(|(index, item)| {
        ListItem::new(vec![
            Line::from(vec![
                Span::styled(format!(" {}. ", index + 1), Style::default().fg(CYAN)),
                Span::styled(
                    item.title,
                    Style::default()
                        .fg(Color::White)
                        .add_modifier(Modifier::BOLD),
                ),
                Span::styled("   ", Style::default()),
                Span::styled(item.hotkey, Style::default().fg(MUTED)),
            ]),
            Line::from(Span::styled(
                format!("     {}", item.description),
                Style::default().fg(MUTED),
            )),
        ])
    });
    let mut state = ListState::default();
    state.select(Some(app.selected.min(MENU_COUNT - 1)));
    frame.render_stateful_widget(
        List::new(items)
            .block(panel("ГЛАВНОЕ МЕНЮ", CYAN))
            .highlight_symbol("▶ ")
            .highlight_style(Style::default().bg(BLUE).fg(Color::White)),
        body[0],
        &mut state,
    );

    let selected = &menu[app.selected.min(MENU_COUNT - 1)];
    frame.render_widget(
        Paragraph::new(vec![
            Line::from(Span::styled("Выбрано", Style::default().fg(MUTED))),
            Line::from(Span::styled(
                selected.title,
                Style::default()
                    .fg(selected.color)
                    .add_modifier(Modifier::BOLD),
            )),
            Line::from(""),
            Line::from(selected.description),
            Line::from(""),
            Line::from(Span::styled("Enter — открыть", Style::default().fg(CYAN))),
            Line::from(Span::styled("Esc/q — выход", Style::default().fg(MUTED))),
        ])
        .wrap(Wrap { trim: false })
        .block(panel("КОНТЕКСТ", selected.color)),
        body[1],
    );
    frame.render_widget(
        Paragraph::new(format!("🐙 {}", app.notice))
            .style(Style::default().fg(MUTED))
            .block(
                Block::default()
                    .borders(Borders::TOP)
                    .border_style(Style::default().fg(BLUE)),
            ),
        chunks[3],
    );
}

struct MenuItem {
    title: &'static str,
    description: &'static str,
    hotkey: &'static str,
    color: Color,
}

fn menu_items() -> [MenuItem; MENU_COUNT] {
    [
        MenuItem {
            title: "📦 Установить пакет",
            description: "Найти пакет и подготовить установку из репозитория или AUR.",
            hotkey: "1",
            color: GREEN,
        },
        MenuItem {
            title: "🗑 Удалить пакет",
            description: "Посмотреть установленные пакеты и безопасно освободить выбранный.",
            hotkey: "2",
            color: PINK,
        },
        MenuItem {
            title: "🔄 Обновить систему",
            description: "Проверить pacman, AUR и подготовить общий план обновления.",
            hotkey: "3",
            color: ORANGE,
        },
        MenuItem {
            title: "📋 Список пакетов",
            description: "Открыть таблицу пакетов, статусов, версий и размеров.",
            hotkey: "4",
            color: GREEN,
        },
        MenuItem {
            title: "🐙 Поиск в AUR",
            description: "Найти пакеты по рейтингу, голосам и популярности.",
            hotkey: "5",
            color: PINK,
        },
        MenuItem {
            title: "⚡ Бенчмарк",
            description: "Оценить скорость AUR API, парсинга и backend-операций.",
            hotkey: "6",
            color: ORANGE,
        },
        MenuItem {
            title: "📊 Статистика",
            description: "Посмотреть состояние OCTO, кэш, историю и распределение места.",
            hotkey: "7",
            color: CYAN,
        },
        MenuItem {
            title: "🧹 Очистка",
            description: "Освободить кэш, старые сборки и потенциальные orphan-пакеты.",
            hotkey: "8",
            color: GREEN,
        },
        MenuItem {
            title: "⌨ CLI SHELL",
            description: "Ввести привычные команды: install, search, remove, update, clean.",
            hotkey: "9",
            color: CYAN,
        },
    ]
}

fn metric_card(
    title: impl Into<String>,
    value: impl Into<String>,
    hint: impl Into<String>,
    color: Color,
) -> Paragraph<'static> {
    let title = title.into();
    let value = value.into();
    let hint = hint.into();
    Paragraph::new(vec![
        Line::from(Span::styled(title, Style::default().fg(MUTED))),
        Line::from(Span::styled(
            value,
            Style::default().fg(color).add_modifier(Modifier::BOLD),
        )),
        Line::from(Span::styled(hint, Style::default().fg(MUTED))),
    ])
    .block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(color)),
    )
}

fn draw_packages(frame: &mut ratatui::Frame, area: Rect, _app: &App) {
    let tabs = Tabs::new([
        "Все",
        "Установленные",
        "Обновления",
        "Официальные",
        "AUR",
        "Сироты (Orphans)",
    ])
    .select(0)
    .style(Style::default().fg(MUTED))
    .highlight_style(Style::default().fg(GREEN).add_modifier(Modifier::BOLD));
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(6)])
        .split(area);
    frame.render_widget(tabs, chunks[0]);
    let packages = load_packages();
    let rows: Vec<Row> = packages
        .iter()
        .map(|package| {
            Row::new([
                Cell::from(if package.source == "aur" {
                    "AUR"
                } else {
                    "офиц."
                }),
                Cell::from(package.name.clone()),
                Cell::from(if package.version.is_empty() {
                    "unknown".into()
                } else {
                    package.version.clone()
                }),
                Cell::from("Установлен"),
            ])
        })
        .collect();
    let table = Table::new(
        rows,
        [
            Constraint::Length(10),
            Constraint::Length(28),
            Constraint::Length(20),
            Constraint::Length(20),
        ],
    )
    .header(
        Row::new(["Репо", "Пакет", "Версия", "Размер / статус"])
            .style(Style::default().fg(CYAN).add_modifier(Modifier::BOLD)),
    )
    .block(panel("📋 ПАКЕТЫ OCTO", GREEN))
    .row_highlight_style(Style::default().bg(BLUE));
    if packages.is_empty() {
        frame.render_widget(
            Paragraph::new("В локальной базе OCTO пока нет пакетов.")
                .block(panel("📋 ПАКЕТЫ OCTO", GREEN)),
            chunks[1],
        );
    } else {
        frame.render_widget(table, chunks[1]);
    }
}

fn draw_search(frame: &mut ratatui::Frame, area: Rect, app: &App) {
    let rows: Vec<Row> = app
        .aur_results
        .iter()
        .enumerate()
        .map(|(index, pkg)| {
            Row::new([
                (index + 1).to_string(),
                pkg.name.clone(),
                pkg.version.clone(),
                format!("★ {}", pkg.votes),
                format!("{:.2}", pkg.popularity),
            ])
        })
        .collect();
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(7),
            Constraint::Length(2),
        ])
        .split(area);
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled(
                if app.aur_loading { "⟳ " } else { "🔍 " },
                Style::default().fg(CYAN),
            ),
            Span::raw(if app.input.is_empty() {
                "neofetch"
            } else {
                &app.input
            }),
            Span::styled("   Enter — асинхронный поиск", Style::default().fg(MUTED)),
        ]))
        .block(panel("ПОИСК В AUR", PINK)),
        chunks[0],
    );
    frame.render_widget(
        Table::new(
            rows,
            [
                Constraint::Length(5),
                Constraint::Length(28),
                Constraint::Length(22),
                Constraint::Length(16),
                Constraint::Length(16),
            ],
        )
        .header(
            Row::new(["#", "Пакет", "Версия", "Голоса", "Популярность"])
                .style(Style::default().fg(CYAN)),
        )
        .block(panel(
            if app.aur_loading {
                "Ищем в AUR..."
            } else {
                "Результаты AUR"
            },
            CYAN,
        )),
        chunks[1],
    );
    frame.render_widget(
        Paragraph::new(
            app.aur_results
                .first()
                .map(|pkg| format!("{} — {}", pkg.name, pkg.description))
                .unwrap_or_else(|| {
                    "[ 🔍 ДЕТАЛЬНЕЕ ]    [ 📦 УСТАНОВИТЬ ]    [ 📋 ВСЕ ПАКЕТЫ ]".into()
                }),
        )
        .style(Style::default().fg(CYAN)),
        chunks[2],
    );
}

fn draw_stats(frame: &mut ratatui::Frame, area: Rect, app: &App) {
    let db_ratio = if app.db.total == 0 {
        0.0
    } else {
        (app.db.installed as f64 / app.db.total.max(1) as f64).clamp(0.0, 1.0)
    };
    let cache_ratio = (app.db.cache_mb / 1024.0).clamp(0.0, 1.0);
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(7),
            Constraint::Length(4),
            Constraint::Length(4),
            Constraint::Min(3),
        ])
        .split(area);
    let text = vec![
        Line::from(format!(
            "Установлено: {} пакетов       Всего в DB: {}",
            app.db.installed, app.db.total
        )),
        Line::from(format!(
            "История операций: {}        Размер кэша: {:.1} MB",
            app.db.history, app.db.cache_mb
        )),
        Line::from(""),
        Line::from(Span::styled(
            app.db.status.as_str(),
            Style::default().fg(GREEN),
        )),
    ];
    frame.render_widget(
        Paragraph::new(text)
            .wrap(Wrap { trim: false })
            .block(panel("📊 ОБЩАЯ СТАТИСТИКА", CYAN)),
        chunks[0],
    );
    frame.render_widget(
        Gauge::default()
            .block(panel("Заполненность DB", CYAN))
            .gauge_style(Style::default().fg(CYAN).bg(BLUE))
            .ratio(db_ratio),
        chunks[1],
    );
    frame.render_widget(
        Gauge::default()
            .block(panel("Кэш OCTO / 1GB", PINK))
            .gauge_style(Style::default().fg(PINK).bg(BLUE))
            .ratio(cache_ratio),
        chunks[2],
    );
    frame.render_widget(
        Paragraph::new("Данные читаются из SQLite ~/.octo/db/octo.sqlite3. Обновите backend, чтобы статистика стала точнее.").style(Style::default().fg(MUTED)),
        chunks[3],
    );
}

fn draw_cleanup(frame: &mut ratatui::Frame, area: Rect, app: &App) {
    let text = vec![
        Line::from(format!(
            "Кэш OCTO: {:.1} MB       Бэкапы: читаются backend-командой",
            app.db.cache_mb
        )),
        Line::from("Кэш сборки AUR: отдельный размер не измеряется"),
        Line::from(""),
        Line::from("📋 Состояние последнего действия:"),
        Line::from(app.action_result.as_str()),
        Line::from(""),
        Line::from("Enter запускает очистку cache после подтверждения."),
    ];
    frame.render_widget(
        Paragraph::new(text).block(panel("🧹 ОСВОБОЖДЕНИЕ ДИСКА OCTO", GREEN)),
        area,
    );
}

fn draw_action(
    frame: &mut ratatui::Frame,
    area: Rect,
    screen: Screen,
    app: &App,
    subtitle: &str,
    lines: &[&str],
) {
    let mut text = vec![
        Line::from(Span::styled(
            subtitle,
            Style::default()
                .fg(screen.accent())
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
    ];
    text.extend(lines.iter().map(|line| Line::from(*line)));
    if screen == Screen::Remove {
        text.push(Line::from(format!(
            "Пакет: {}",
            if app.input.is_empty() {
                "не выбран"
            } else {
                &app.input
            }
        )));
    }
    text.extend(app.action_result.lines().map(Line::from));
    text.push(Line::from(""));
    text.push(Line::from("[ ENTER — продолжить ]       [ ESC — отмена ]"));
    frame.render_widget(
        Paragraph::new(text)
            .wrap(Wrap { trim: false })
            .block(panel(screen.title(), screen.accent())),
        area,
    );
}

fn draw_shell(frame: &mut ratatui::Frame, area: Rect, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(8), Constraint::Length(6)])
        .split(area);
    let lines: Vec<Line> = app
        .shell_output
        .iter()
        .map(|line| Line::from(line.as_str()))
        .collect();
    let visible = usize::from(chunks[0].height.saturating_sub(2));
    let max_scroll = lines.len().saturating_sub(visible);
    let scroll = if app.shell_scroll == usize::MAX {
        max_scroll
    } else {
        app.shell_scroll.min(max_scroll)
    };
    frame.render_widget(
        Paragraph::new(lines)
            .wrap(Wrap { trim: false })
            .scroll((scroll.min(u16::MAX as usize) as u16, 0))
            .block(panel("OCTO INTERACTIVE CLI SHELL [tty1]", CYAN)),
        chunks[0],
    );
    frame.render_widget(
        Paragraph::new(vec![
            Line::from(vec![
                Span::styled(
                    "octo@arch",
                    Style::default().fg(GREEN).add_modifier(Modifier::BOLD),
                ),
                Span::styled(" :~$ ", Style::default().fg(MUTED)),
                Span::styled(app.input.as_str(), Style::default().fg(CYAN)),
                Span::styled("█", Style::default().fg(CYAN)),
            ]),
            Line::from(""),
            Line::from(Span::styled(
                "Примеры: install neofetch --aur  •  search firefox  •  clean cache  •  help",
                Style::default().fg(MUTED),
            )),
            Line::from(Span::styled(
                "Прокрутка: ↑/↓, PageUp/PageDown, Home/End",
                Style::default().fg(MUTED),
            )),
        ])
        .block(panel("КОМАНДА", CYAN)),
        chunks[1],
    );
}

#[cfg(test)]
mod tests {
    use super::{normalize_shell_args, scroll_shell, App};

    #[test]
    fn normalizes_common_install_command() {
        assert_eq!(
            normalize_shell_args(&["install", "neofetch", "--aur"]).unwrap(),
            vec!["install", "--aur", "neofetch"]
        );
    }

    #[test]
    fn supports_familiar_aliases() {
        assert_eq!(
            normalize_shell_args(&["i", "ripgrep"]).unwrap(),
            vec!["install", "ripgrep"]
        );
        assert_eq!(normalize_shell_args(&["ls"]).unwrap(), vec!["list"]);
        assert_eq!(normalize_shell_args(&["bench"]).unwrap(), vec!["benchmark"]);
        assert_eq!(
            normalize_shell_args(&["статистика"]).unwrap(),
            vec!["stats"]
        );
        assert_eq!(normalize_shell_args(&["ракушка"]).unwrap(), vec!["list"]);
        assert_eq!(
            normalize_shell_args(&["diagnostic"]).unwrap(),
            vec!["diagnostic"]
        );
        assert_eq!(
            normalize_shell_args(&["cache-stats"]).unwrap(),
            vec!["cache-stats"]
        );
        assert_eq!(
            normalize_shell_args(&["размер", "ripgrep"]).unwrap(),
            vec!["size", "ripgrep"]
        );
        assert_eq!(
            normalize_shell_args(&["popularity", "ripgrep"]).unwrap(),
            vec!["popularity", "ripgrep"]
        );
    }

    #[test]
    fn supports_backend_commands_with_arguments() {
        assert_eq!(
            normalize_shell_args(&["info", "ripgrep"]).unwrap(),
            vec!["info", "ripgrep"]
        );
        assert_eq!(
            normalize_shell_args(&["зависимости", "demo"]).unwrap(),
            vec!["deps", "demo"]
        );
        assert_eq!(
            normalize_shell_args(&["установить", "google-chrome", "--aur"]).unwrap(),
            vec!["install", "--aur", "google-chrome"]
        );
        assert_eq!(
            normalize_shell_args(&["config"]).unwrap(),
            vec!["настройки"]
        );
        assert_eq!(normalize_shell_args(&["version"]).unwrap(), vec!["version"]);
        assert_eq!(normalize_shell_args(&["версия"]).unwrap(), vec!["version"]);
        assert_eq!(normalize_shell_args(&["список"]).unwrap(), vec!["list"]);
        assert_eq!(normalize_shell_args(&["кэш"]).unwrap(), vec!["cache-stats"]);
        assert_eq!(normalize_shell_args(&["тест"]).unwrap(), vec!["benchmark"]);
    }

    #[test]
    fn scrolls_shell_output_with_bounded_positions() {
        let mut app = App::default();
        app.shell_output = (0..20).map(|line| line.to_string()).collect();

        scroll_shell(&mut app, -3);
        assert_eq!(app.shell_scroll, 9);
        scroll_shell(&mut app, 100);
        assert_eq!(app.shell_scroll, 12);
        scroll_shell(&mut app, -100);
        assert_eq!(app.shell_scroll, 0);
    }

    #[test]
    fn rejects_unknown_commands_and_shell_syntax() {
        assert!(normalize_shell_args(&["echo", "hello"]).is_err());
        assert!(normalize_shell_args(&["install", "pkg;", "rm", "-rf", "/"]).is_err());
        assert!(normalize_shell_args(&["size"]).is_err());
        assert_eq!(
            normalize_shell_args(&["clean", "history"]).unwrap(),
            vec!["clean", "history"]
        );
    }
}
