#include <algorithm>
#include <atomic>
#include <chrono>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <map>
#include <regex>
#include <sstream>
#include <sqlite3.h>
#include <string>
#include <set>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>
#include <vector>

namespace fs = std::filesystem;

namespace {

constexpr const char *CYAN = "\033[36m";
constexpr const char *GREEN = "\033[32m";
constexpr const char *YELLOW = "\033[33m";
constexpr const char *RED = "\033[31m";
constexpr const char *MAGENTA = "\033[35m";
constexpr const char *RESET = "\033[0m";

struct Result { int code; std::string output; };

fs::path home() {
    const char *value = std::getenv("HOME");
    return value ? fs::path(value) : fs::current_path();
}
fs::path root() {
    if (const char *value = std::getenv("OCTO_HOME")) return fs::path(value);
    return home() / ".octo";
}
fs::path db() { return root() / "db"; }
fs::path sqlite_db() { return db() / "octo.sqlite3"; }
fs::path packages_json() { return db() / "packages.json"; }
fs::path history_json() { return db() / "history.json"; }
fs::path cache() { return root() / "cache"; }
fs::path backups() { return root() / "backups"; }
fs::path logs() { return root() / "logs"; }
fs::path command_history_file() { return root() / "history"; }
fs::path action_log(const std::string &action) { return logs() / (action + ".log"); }
constexpr std::chrono::seconds AUR_CACHE_TTL{300};

std::string read(const fs::path &path);

bool tui_mode() {
    const char *value = std::getenv("OCTO_TUI");
    return value && std::string(value) == "1";
}

std::vector<std::string> sudo_pacman(std::initializer_list<std::string> arguments) {
    std::vector<std::string> command{"sudo"};
    if (tui_mode()) command.push_back("-n");
    command.push_back("pacman");
    if (tui_mode()) command.push_back("--noconfirm");
    command.insert(command.end(), arguments.begin(), arguments.end());
    return command;
}

bool sql_exec(sqlite3 *database, const char *sql) {
    char *error = nullptr;
    const bool ok = sqlite3_exec(database, sql, nullptr, nullptr, &error) == SQLITE_OK;
    sqlite3_free(error);
    return ok;
}

void log_action(const std::string &action, const std::string &message) {
    std::ofstream file(action_log(action), std::ios::app);
    if (!file) return;
    const auto stamp = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    file << std::put_time(std::localtime(&stamp), "%Y-%m-%d %H:%M:%S")
         << " " << message << '\n';
}

void log_error(const std::string &message) { log_action("errors", message); }

sqlite3 *open_db();
bool yes(const std::string &question);

std::string join_arguments(const std::vector<std::string> &arguments) {
    std::ostringstream result;
    for (size_t index = 0; index < arguments.size(); ++index) {
        if (index) result << ' ';
        result << arguments[index];
    }
    return result.str();
}

void record_command(const std::vector<std::string> &arguments) {
    std::ofstream file(command_history_file(), std::ios::app);
    if (!file) return;
    const auto stamp = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    file << std::put_time(std::localtime(&stamp), "%Y-%m-%d %H:%M:%S")
         << " " << join_arguments(arguments) << '\n';
}

int clear_command_history() {
    if (!yes("Очистить историю команд?")) return 0;
    std::error_code error;
    fs::remove(command_history_file(), error);
    sqlite3 *database = open_db();
    if (database) {
        sql_exec(database, "DELETE FROM history WHERE action = 'command';");
        sqlite3_close(database);
    }
    std::cout << GREEN << "✅ История команд очищена" << RESET << '\n';
    return error ? 1 : 0;
}

bool valid(const std::string &value);
int backup();

bool valid_alias(const std::string &value) {
    return !value.empty() && value.size() <= 64 &&
        value.find_first_of(";|&`$><(){}\n\r") == std::string::npos;
}

bool set_config(const std::string &key, const std::string &value) {
    sqlite3 *database = open_db();
    if (!database) return false;
    sqlite3_stmt *statement = nullptr;
    const bool prepared = sqlite3_prepare_v2(database,
        "INSERT INTO config(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        -1, &statement, nullptr) == SQLITE_OK;
    if (prepared) {
        sqlite3_bind_text(statement, 1, key.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 2, value.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_step(statement);
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return prepared;
}

std::string get_config(const std::string &key) {
    sqlite3 *database = open_db();
    if (!database) return {};
    sqlite3_stmt *statement = nullptr;
    std::string value;
    if (sqlite3_prepare_v2(database, "SELECT value FROM config WHERE key = ?", -1, &statement, nullptr) == SQLITE_OK) {
        sqlite3_bind_text(statement, 1, key.c_str(), -1, SQLITE_TRANSIENT);
        if (sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_text(statement, 0))
            value = reinterpret_cast<const char *>(sqlite3_column_text(statement, 0));
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return value;
}

int aliases_command(const std::vector<std::string> &args) {
    if (args.size() == 1 || args[1] == "список" || args[1] == "list") {
        sqlite3 *database = open_db();
        if (!database) return 1;
        sqlite3_stmt *statement = nullptr;
        sqlite3_prepare_v2(database, "SELECT key, value FROM config WHERE key LIKE 'alias.%' ORDER BY key", -1, &statement, nullptr);
        while (statement && sqlite3_step(statement) == SQLITE_ROW)
            std::cout << "  " << reinterpret_cast<const char *>(sqlite3_column_text(statement, 0)) + 6
                      << " -> " << sqlite3_column_text(statement, 1) << '\n';
        sqlite3_finalize(statement);
        sqlite3_close(database);
        return 0;
    }
    if (args[1] == "добавить" || args[1] == "add") {
        if (args.size() != 4 || !valid_alias(args[2]) || !valid_alias(args[3])) return 2;
        return set_config("alias." + args[2], args[3]) ? 0 : 1;
    }
    if (args[1] == "удалить" || args[1] == "remove") {
        if (args.size() != 3) return 2;
        sqlite3 *database = open_db();
        if (!database) return 1;
        sqlite3_stmt *statement = nullptr;
        sqlite3_prepare_v2(database, "DELETE FROM config WHERE key = ?", -1, &statement, nullptr);
        sqlite3_bind_text(statement, 1, ("alias." + args[2]).c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_step(statement);
        sqlite3_finalize(statement);
        sqlite3_close(database);
        return 0;
    }
    return 2;
}

sqlite3 *open_db() {
    sqlite3 *database = nullptr;
    if (sqlite3_open(sqlite_db().c_str(), &database) != SQLITE_OK) {
        sqlite3_close(database);
        return nullptr;
    }
    sqlite3_busy_timeout(database, 3000);
    if (!sql_exec(database, "PRAGMA journal_mode=WAL;")) {
        sqlite3_close(database);
        return nullptr;
    }
    return database;
}

void migrate_json(sqlite3 *database) {
    sqlite3_stmt *count = nullptr;
    if (sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM packages", -1, &count, nullptr) != SQLITE_OK)
        return;
    const bool empty = sqlite3_step(count) == SQLITE_ROW && sqlite3_column_int(count, 0) == 0;
    sqlite3_finalize(count);
    if (!empty || !fs::exists(packages_json())) return;

    const std::string packages = read(packages_json());
    const std::regex package(R"regex("name"\s*:\s*"([^"]+)"\s*,\s*"version"\s*:\s*"([^"]*)")regex");
    sql_exec(database, "BEGIN;");
    sqlite3_stmt *insert = nullptr;
    sqlite3_prepare_v2(database,
        "INSERT OR IGNORE INTO packages(name, version, installed_at) VALUES(?, ?, ?)",
        -1, &insert, nullptr);
    for (std::sregex_iterator it(packages.begin(), packages.end(), package), end; it != end; ++it) {
        sqlite3_bind_text(insert, 1, (*it)[1].str().c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(insert, 2, (*it)[2].str().c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(insert, 3, "unknown", -1, SQLITE_STATIC);
        sqlite3_step(insert);
        sqlite3_reset(insert);
        sqlite3_clear_bindings(insert);
    }
    sqlite3_finalize(insert);
    sql_exec(database, "COMMIT;");
    const auto packages_backup = packages_json().string() + ".bak";
    if (!fs::exists(packages_backup)) fs::rename(packages_json(), packages_backup);

    if (!fs::exists(history_json())) return;
    const std::string history_data = read(history_json());
    const std::regex event(R"regex("action"\s*:\s*"([^"]+)"\s*,\s*"name"\s*:\s*"([^"]+)")regex");
    sql_exec(database, "BEGIN;");
    sqlite3_prepare_v2(database,
        "INSERT INTO history(action, package_name, version, timestamp) VALUES(?, ?, ?, ?)",
        -1, &insert, nullptr);
    for (std::sregex_iterator it(history_data.begin(), history_data.end(), event), end; it != end; ++it) {
        sqlite3_bind_text(insert, 1, (*it)[1].str().c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(insert, 2, (*it)[2].str().c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(insert, 3, "unknown", -1, SQLITE_STATIC);
        sqlite3_bind_text(insert, 4, "unknown", -1, SQLITE_STATIC);
        sqlite3_step(insert);
        sqlite3_reset(insert);
        sqlite3_clear_bindings(insert);
    }
    sqlite3_finalize(insert);
    sql_exec(database, "COMMIT;");
    const auto history_backup = history_json().string() + ".bak";
    if (!fs::exists(history_backup)) fs::rename(history_json(), history_backup);
}

void init() {
    for (const auto &path : {db(), root() / "pkgs", logs(), backups(), cache()})
        fs::create_directories(path);
    sqlite3 *database = open_db();
    if (!database) return;
    sql_exec(database, "CREATE TABLE IF NOT EXISTS packages (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, version TEXT NOT NULL DEFAULT 'unknown', description TEXT, url TEXT, maintainer TEXT, votes INTEGER DEFAULT 0, popularity REAL DEFAULT 0.0, installed_at DATETIME DEFAULT CURRENT_TIMESTAMP, source TEXT CHECK(source IN ('official', 'aur')), size INTEGER DEFAULT 0);");
    sql_exec(database, "CREATE INDEX IF NOT EXISTS idx_packages_name ON packages(name);");
    sql_exec(database, "CREATE TABLE IF NOT EXISTS history (id INTEGER PRIMARY KEY AUTOINCREMENT, action TEXT NOT NULL, package_id INTEGER, package_name TEXT NOT NULL, version TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(package_id) REFERENCES packages(id));");
    sql_exec(database, "CREATE INDEX IF NOT EXISTS idx_history_timestamp ON history(timestamp);");
    sql_exec(database, "CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, value TEXT NOT NULL);");
    for (const auto *column : {
        "ALTER TABLE packages ADD COLUMN description TEXT", "ALTER TABLE packages ADD COLUMN url TEXT",
        "ALTER TABLE packages ADD COLUMN maintainer TEXT", "ALTER TABLE packages ADD COLUMN votes INTEGER DEFAULT 0",
        "ALTER TABLE packages ADD COLUMN popularity REAL DEFAULT 0.0", "ALTER TABLE packages ADD COLUMN source TEXT",
        "ALTER TABLE packages ADD COLUMN size INTEGER DEFAULT 0"}) sql_exec(database, column);
    sql_exec(database, "ALTER TABLE history ADD COLUMN package_id INTEGER");
    sql_exec(database, "ALTER TABLE history ADD COLUMN timestamp DATETIME");
    migrate_json(database);
    sqlite3_close(database);
}

std::string read(const fs::path &path) {
    std::ifstream file(path);
    std::ostringstream content;
    content << file.rdbuf();
    return content.str();
}

void write(const fs::path &path, const std::string &content) {
    const auto temporary = path.string() + ".tmp";
    std::ofstream(temporary) << content;
    fs::rename(temporary, path);
}

Result exec(const std::vector<std::string> &args, bool capture = false,
            const fs::path &directory = {}) {
    if (args.empty()) return {1, {}};
    int pipefd[2] = {-1, -1};
    if (capture && pipe(pipefd) != 0) return {1, {}};
    const pid_t pid = fork();
    if (pid < 0) return {1, {}};
    if (pid == 0) {
        if (!directory.empty() && chdir(directory.c_str()) != 0) _exit(126);
        if (capture) {
            dup2(pipefd[1], STDOUT_FILENO);
            dup2(pipefd[1], STDERR_FILENO);
            close(pipefd[0]);
            close(pipefd[1]);
        }
        std::vector<char *> argv;
        for (const auto &arg : args) argv.push_back(const_cast<char *>(arg.c_str()));
        argv.push_back(nullptr);
        execvp(argv[0], argv.data());
        _exit(127);
    }
    if (capture) close(pipefd[1]);
    std::string output;
    if (capture) {
        char buffer[4096];
        ssize_t length;
        while ((length = ::read(pipefd[0], buffer, sizeof(buffer))) > 0)
            output.append(buffer, static_cast<size_t>(length));
        close(pipefd[0]);
    }
    int status = 0;
    waitpid(pid, &status, 0);
    return {WIFEXITED(status) ? WEXITSTATUS(status) : 1, output};
}

bool interactive_output() {
    return isatty(STDOUT_FILENO) == 1 && !tui_mode();
}

Result exec_with_spinner(const std::vector<std::string> &args, const std::string &label,
                         bool capture = false, const fs::path &directory = {}) {
    if (!interactive_output()) return exec(args, capture, directory);
    Result result{1, {}};
    std::atomic<bool> finished{false};
    std::thread worker([&] {
        result = exec(args, capture, directory);
        finished = true;
    });
    constexpr const char *frames[] = {"🐙", "🦑", "🐙", "🦑"};
    size_t frame = 0;
    while (!finished) {
        std::cout << '\r' << CYAN << frames[frame++ % 4] << ' ' << label
                  << "...   " << RESET << std::flush;
        std::this_thread::sleep_for(std::chrono::milliseconds(180));
    }
    worker.join();
    std::cout << '\r' << std::string(64, ' ') << '\r' << std::flush;
    return result;
}

bool valid(const std::string &value) {
    return !value.empty() && value.size() <= 256 &&
        std::all_of(value.begin(), value.end(), [](unsigned char c) {
            return std::isalnum(c) || std::string("@._+:/-=").find(c) != std::string::npos;
        });
}

bool yes(const std::string &question) {
    const char *confirmed = std::getenv("OCTO_CONFIRMED");
    if (confirmed && std::string(confirmed) == "1") return true;
    std::cout << YELLOW << question << " [да/нет] " << RESET << std::flush;
    std::string answer;
    if (!std::getline(std::cin, answer)) return false;
    return answer == "да" || answer == "Да" || answer == "y" ||
           answer == "Y" || answer == "yes" || answer == "Yes" || answer == "ок";
}

size_t files(const fs::path &path) {
    if (!fs::exists(path)) return 0;
    return static_cast<size_t>(std::distance(fs::directory_iterator(path), fs::directory_iterator{}));
}

void package_add(const std::string &name, bool aur) {
    sqlite3 *database = open_db();
    if (!database) return;
    sql_exec(database, "BEGIN;");
    sqlite3_stmt *statement = nullptr;
    sqlite3_prepare_v2(database,
        "INSERT OR IGNORE INTO packages(name, version, source) VALUES(?, ?, ?)",
        -1, &statement, nullptr);
    sqlite3_bind_text(statement, 1, name.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, "unknown", -1, SQLITE_STATIC);
    sqlite3_bind_text(statement, 3, aur ? "aur" : "official", -1, SQLITE_STATIC);
    const bool changed = sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(database) > 0;
    sqlite3_finalize(statement);
    if (changed) {
        sqlite3_prepare_v2(database,
            "INSERT INTO history(action, package_name, version) VALUES('install', ?, 'unknown')",
            -1, &statement, nullptr);
        sqlite3_bind_text(statement, 1, name.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_step(statement);
        sqlite3_finalize(statement);
    }
    sql_exec(database, "COMMIT;");
    sqlite3_close(database);
}

void package_remove(const std::string &name) {
    sqlite3 *database = open_db();
    if (!database) return;
    sql_exec(database, "BEGIN;");
    sqlite3_stmt *statement = nullptr;
    sqlite3_prepare_v2(database, "DELETE FROM packages WHERE name = ?", -1, &statement, nullptr);
    sqlite3_bind_text(statement, 1, name.c_str(), -1, SQLITE_TRANSIENT);
    const bool changed = sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(database) > 0;
    sqlite3_finalize(statement);
    if (changed) {
        sqlite3_prepare_v2(database,
            "INSERT INTO history(action, package_name, version) VALUES('remove', ?, 'unknown')",
            -1, &statement, nullptr);
        sqlite3_bind_text(statement, 1, name.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_step(statement);
        sqlite3_finalize(statement);
    }
    sql_exec(database, "COMMIT;");
    sqlite3_close(database);
}

int list_packages() {
    const auto installed = exec({"pacman", "-Q"}, true);
    if (installed.code != 0) {
        sqlite3 *database = open_db();
        if (!database) return installed.code;
        sqlite3_stmt *statement = nullptr;
        sqlite3_prepare_v2(database,
            "SELECT name, version, COALESCE(source, 'official') FROM packages ORDER BY name COLLATE NOCASE",
            -1, &statement, nullptr);
        while (statement && sqlite3_step(statement) == SQLITE_ROW)
            std::cout << (std::string(reinterpret_cast<const char *>(sqlite3_column_text(statement, 2))) == "aur" ? "[AUR] " : "[офиц.] ")
                      << sqlite3_column_text(statement, 0) << " " << sqlite3_column_text(statement, 1) << '\n';
        sqlite3_finalize(statement);
        sqlite3_close(database);
        return 0;
    }

    std::set<std::string> aur_packages;
    const auto aur = exec({"pacman", "-Qm"}, true);
    if (!aur.code) {
        std::istringstream input(aur.output);
        std::string name, version;
        while (input >> name >> version) aur_packages.insert(name);
    }

    sqlite3 *database = open_db();
    sqlite3_stmt *upsert = nullptr;
    if (database) sqlite3_prepare_v2(database,
        "INSERT INTO packages(name, version, source) VALUES(?, ?, ?) "
        "ON CONFLICT(name) DO UPDATE SET version=excluded.version, source=excluded.source",
        -1, &upsert, nullptr);

    std::istringstream input(installed.output);
    std::string name, version;
    while (input >> name >> version) {
        const bool is_aur = aur_packages.count(name) != 0;
        std::cout << (is_aur ? "[AUR] " : "[офиц.] ") << name << " " << version << '\n';
        if (upsert) {
            sqlite3_bind_text(upsert, 1, name.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(upsert, 2, version.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(upsert, 3, is_aur ? "aur" : "official", -1, SQLITE_STATIC);
            sqlite3_step(upsert);
            sqlite3_reset(upsert);
            sqlite3_clear_bindings(upsert);
        }
    }
    sqlite3_finalize(upsert);
    if (database) sqlite3_close(database);
    return 0;
}

std::string encode(const std::string &value) {
    std::ostringstream result;
    result << std::hex << std::uppercase;
    for (unsigned char c : value) {
        if (std::isalnum(c) || c == '-' || c == '_' || c == '.') result << c;
        else result << '%' << std::setw(2) << static_cast<int>(c);
    }
    return result.str();
}

fs::path aur_cache_file(const std::string &query) {
    std::ostringstream key;
    key << std::hex << std::hash<std::string>{}(query);
    return cache() / ("aur-search-" + key.str() + ".json");
}

bool cache_is_fresh(const fs::path &path) {
    if (!fs::is_regular_file(path)) return false;
    const auto modified = fs::last_write_time(path);
    const auto now = fs::file_time_type::clock::now();
    return now - modified < AUR_CACHE_TTL;
}

Result aur_request(const std::string &url) {
    return exec_with_spinner({"curl", "-fsSL", "--compressed", "--retry", "2",
                              "--retry-delay", "1", "--retry-connrefused",
                              "--connect-timeout", "3", "--max-time", "8", url},
                             "Щупальца тянутся к AUR", true);
}

std::vector<std::string> pkgbuild_array(const std::string &text, const std::string &name) {
    const std::regex assignment("(^|\\n)\\s*" + name + "\\s*=\\s*\\(([^)]*)\\)",
                                std::regex_constants::icase);
    std::smatch match;
    if (!std::regex_search(text, match, assignment)) return {};
    std::vector<std::string> values;
    const std::regex token("[A-Za-z0-9@%+._:<>!=/-]+");
    for (std::sregex_iterator it(match[2].first, match[2].second, token), end; it != end; ++it)
        values.push_back(it->str());
    return values;
}

std::string dependency_name(const std::string &dependency) {
    const auto position = dependency.find_first_of("<>=:");
    return dependency.substr(0, position);
}

Result load_pkgbuild(const std::string &package) {
    if (const char *path = std::getenv("OCTO_PKGBUILD"); path && fs::is_regular_file(path))
        return {0, read(path)};
    return aur_request("https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=" + encode(package));
}

int dependencies_command(const std::string &package) {
    if (!valid(package)) return 2;
    const auto result = load_pkgbuild(package);
    if (result.code != 0 || result.output.empty()) {
        std::cerr << RED << "❌ Не удалось получить PKGBUILD для " << package << RESET << '\n';
        return 1;
    }
    const auto depends = pkgbuild_array(result.output, "depends");
    const auto makedepends = pkgbuild_array(result.output, "makedepends");
    const auto conflicts = pkgbuild_array(result.output, "conflicts");
    std::vector<std::string> all_dependencies = depends;
    all_dependencies.insert(all_dependencies.end(), makedepends.begin(), makedepends.end());
    std::vector<std::string> names;
    for (const auto &dependency : all_dependencies) {
        const auto name = dependency_name(dependency);
        if (!name.empty() && std::find(names.begin(), names.end(), name) == names.end()) names.push_back(name);
    }
    std::cout << CYAN << "📦 Зависимости " << package << RESET << '\n';
    if (names.empty()) std::cout << "  нет зависимостей, указанных в PKGBUILD\n";
    else {
        std::vector<std::string> check_command{"pacman", "-T"};
        check_command.insert(check_command.end(), names.begin(), names.end());
        const auto check = exec(check_command, true);
        if (check.code == 127) {
            std::cout << "  ⚠️ pacman недоступен: проверить зависимости не удалось\n";
        } else for (const auto &name : names) {
            const bool missing = check.output.find(name) != std::string::npos;
            std::cout << (missing ? "  ⚠️ " : "  ✅ ") << name
                      << (missing ? " (НЕ УСТАНОВЛЕН)" : " (установлен)") << '\n';
        }
    }
    std::cout << "  runtime: " << depends.size() << ", build: " << makedepends.size() << '\n';
    if (conflicts.empty()) std::cout << "⚔️ Конфликты: не указаны\n";
    else {
        std::cout << "⚔️ Конфликты в PKGBUILD:\n";
        for (const auto &conflict : conflicts) {
            const auto name = dependency_name(conflict);
            const auto check = exec({"pacman", "-Q", name}, true);
            if (check.code == 127) std::cout << "  ⚠️ " << conflict << " (проверка недоступна)\n";
            else {
                const auto installed = check.code == 0;
                std::cout << (installed ? "  ⚠️ " : "  ✅ ") << conflict
                          << (installed ? " (установлен)" : " (не обнаружен)") << '\n';
            }
        }
    }
    return 0;
}

int aur_search(const std::string &query) {
    if (!valid(query)) return 2;
    std::cout << CYAN << "🐙 ОСЬМИНОГ ЛОВИТ ПАКЕТЫ..." << RESET << '\n'
              << "🌊 Океан поиска...\n"
              << "🐙 Щупальца тянутся к AUR: " << query << '\n';
    const auto cached = aur_cache_file(query);
    Result result;
    if (cache_is_fresh(cached)) {
        result = {0, read(cached)};
        std::cout << YELLOW << "⚡ Результат из кэша (TTL 300с)" << RESET << '\n';
    } else {
        result = aur_request("https://aur.archlinux.org/rpc/v5/search?arg=" + encode(query));
        if (!result.code && !result.output.empty()) write(cached, result.output);
    }
    if (result.code != 0) {
        std::cerr << RED << "❌ AUR недоступен" << RESET << '\n';
        log_error("AUR search failed: " + query);
        return 1;
    }
    const std::regex item("\"Name\"\\s*:\\s*\"([^\"]+)\".*?\"Version\"\\s*:\\s*\"([^\"]+)\".*?\"Description\"\\s*:\\s*(?:\"([^\"]*)\"|null)");
    size_t found = 0;
    for (std::sregex_iterator it(result.output.begin(), result.output.end(), item), end; it != end && found < 20; ++it, ++found)
        std::cout << "  " << GREEN << (*it)[1] << RESET << " v" << YELLOW << (*it)[2] << RESET
                  << "\n    " << (*it)[3] << '\n';
    if (!found) std::cout << YELLOW << "⚠️ Ничего не найдено" << RESET << '\n';
    else std::cout << GREEN << "✅ Щупальца нашли: " << found << " пакетов" << RESET << '\n';
    return 0;
}

std::string json_field(const std::string &json, const std::string &field) {
    const std::regex pattern("\\\"" + field + "\\\"\\s*:\\s*(?:\\\"([^\\\"]*)\\\"|([0-9]+(?:\\.[0-9]+)?))");
    std::smatch match;
    if (!std::regex_search(json, match, pattern)) return {};
    return match[1].matched ? match[1].str() : match[2].str();
}

int aur_info(const std::string &package) {
    if (!valid(package)) return 2;
    const auto result = aur_request("https://aur.archlinux.org/rpc/v5/info?arg=" + encode(package));
    if (result.code != 0 || result.output.empty()) {
        std::cerr << RED << "❌ AUR недоступен" << RESET << '\n';
        return 1;
    }
    const auto name = json_field(result.output, "Name");
    if (name.empty()) {
        std::cout << YELLOW << "⚠️ Пакет не найден в AUR: " << package << RESET << '\n';
        return 1;
    }
    std::cout << CYAN << "📋 Информация о пакете [AUR]" << RESET << '\n'
              << "  Название: " << name << '\n'
              << "  Версия: " << json_field(result.output, "Version") << '\n'
              << "  Описание: " << json_field(result.output, "Description") << '\n'
              << "  Голоса: " << json_field(result.output, "NumVotes") << '\n'
              << "  Популярность: " << json_field(result.output, "Popularity") << '\n'
              << "  URL: https://aur.archlinux.org/packages/" << name << '\n';
    return 0;
}

int package_size(const std::string &package) {
    if (!valid(package)) return 2;
    const auto installed = exec({"pacman", "-Qi", package}, true);
    if (!installed.code) {
        const std::regex size_pattern("Installed Size\\s*:\\s*(.+)");
        std::smatch match;
        if (std::regex_search(installed.output, match, size_pattern)) {
            std::cout << "📦 " << package << ": " << match[1].str() << '\n';
            return 0;
        }
    }
    const auto aur = aur_request("https://aur.archlinux.org/rpc/v5/info?arg=" + encode(package));
    if (!json_field(aur.output, "Name").empty()) {
        std::cout << "📦 " << package << ": размер исходников не предоставляется AUR API\n";
        return 0;
    }
    std::cerr << RED << "❌ Пакет не найден: " << package << RESET << '\n';
    return 1;
}

int package_popularity(const std::string &package) {
    if (!valid(package)) return 2;
    const auto result = aur_request("https://aur.archlinux.org/rpc/v5/info?arg=" + encode(package));
    const auto popularity = json_field(result.output, "Popularity");
    if (result.code || popularity.empty()) {
        std::cerr << RED << "❌ Пакет не найден в AUR: " << package << RESET << '\n';
        return 1;
    }
    std::cout << "⭐ Популярность " << package << ": " << popularity << '\n';
    return 0;
}

int install_package(const std::string &name, bool aur) {
    if (!valid(name)) return 2;
    std::cout << CYAN << "🐙 ОСЬМИНОГ ЛОВИТ ПАКЕТЫ..." << RESET << '\n'
              << "🌊 Океан установки...\n"
              << "📦 Пакет: " << name << (aur ? " [AUR]" : " [офиц.]") << '\n';
    if (!yes("Продолжить?")) return 0;
    if (backup() != 0) {
        log_error("automatic backup failed before install: " + name);
        return 1;
    }
    Result result;
    if (!aur) {
        std::cout << "🐙 Щупальца тянутся к официальному репозиторию...\n";
        result = exec_with_spinner(sudo_pacman({"-S", "--noconfirm", name}),
                                   "Осьминог устанавливает пакет", true);
    } else {
        const fs::path directory = fs::path("/tmp") / ("octo-" + name);
        fs::remove_all(directory);
        std::cout << "🐙 Загрузка исходников из AUR...\n";
        result = exec_with_spinner({"git", "clone", "https://aur.archlinux.org/" + name + ".git", directory.string()},
                                   "Загрузка исходников", true);
        if (!result.code) {
            std::cout << "🦑 Проверка зависимостей и сборка пакета...\n";
            result = exec_with_spinner({"makepkg", "-si", "--noconfirm"},
                                       "Сборка и установка", true, directory);
        }
        fs::remove_all(directory);
    }
    if (!result.output.empty()) std::cout << result.output;
    if (!result.code) {
        package_add(name, aur);
        log_action(aur ? "install" : "install", "installed " + name + (aur ? " from AUR" : " from official repository"));
        std::cout << GREEN << "✅ Пакет пойман! 🎉\n🐙 " << name << " установлен!" << RESET << '\n';
    } else log_error("install failed: " + name);
    return result.code;
}

int remove_package(const std::string &name, bool dependencies) {
    if (!valid(name)) return 2;
    if (!yes("🐙 Отпустить пакет " + name + "?")) return 0;
    if (backup() != 0) {
        log_error("automatic backup failed before remove: " + name);
        return 1;
    }
    const auto result = exec_with_spinner(
        sudo_pacman({dependencies ? "-Rsc" : "-R", name}),
        "Осьминог отпускает пакет", true);
    if (!result.output.empty()) std::cout << result.output;
    if (!result.code) {
        package_remove(name);
        log_action("remove", "removed " + name);
        std::cout << GREEN << "✅ Удалено" << RESET << '\n';
    } else log_error("remove failed: " + name);
    return result.code;
}

int clean(const std::string &target) {
    fs::path directory;
    if (target == "cache") directory = cache();
    else if (target == "backups") directory = backups();
    else if (target == "all") { clean("cache"); return clean("backups"); }
    else return 2;
    if (!yes("Очистить " + target + "?")) return 0;
    for (const auto &entry : fs::directory_iterator(directory)) fs::remove_all(entry.path());
    log_action("clean", "cleaned " + target);
    std::cout << GREEN << "✅ Очищено" << RESET << '\n';
    return 0;
}

int backup() {
    const auto stamp = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    const auto list = backups() / ("system_" + std::to_string(stamp) + ".txt");
    std::ofstream file(list);
    file << "# OCTO system backup\n\n## Official packages\n";
    auto official = exec({"pacman", "-Qe"}, true);
    file << official.output << "\n## AUR packages\n" << exec({"pacman", "-Qm"}, true).output;
    std::cout << GREEN << "✅ Бэкап создан: " << list << RESET << '\n';
    return 0;
}

int security_scan(const std::string &path) {
    if (!fs::is_regular_file(path)) {
        std::cerr << RED << "PKGBUILD не найден: " << path << RESET << '\n';
        return 1;
    }
    const std::string text = read(path);
    const std::vector<std::pair<std::string, std::string>> threats = {
        {"rm -rf /", "опасное удаление"}, {"sudo", "использование sudo"},
        {"chmod 777", "небезопасные права"}, {"curl.*|.*sh", "запуск загруженного скрипта"},
        {"wget.*|.*sh", "запуск загруженного скрипта"}, {"curl.*-k", "отключение TLS"},
        {"eval", "произвольное выполнение кода"}, {"bit\\.ly|tinyurl|t\\.co", "короткая ссылка"}
    };
    size_t issues = 0;
    for (const auto &[pattern, label] : threats) {
        if (std::regex_search(text, std::regex(pattern))) {
            std::cout << RED << "⚠️ " << label << RESET << '\n';
            ++issues;
        }
    }
    std::cout << (issues ? RED : GREEN) << (issues ? "❌ Найдены потенциальные угрозы: " : "✅ PKGBUILD прошёл проверку")
              << (issues ? std::to_string(issues) : "") << RESET << '\n';
    return issues ? 1 : 0;
}

int restore_backup(const fs::path &backup_file) {
    if (!fs::is_regular_file(backup_file)) {
        std::cerr << RED << "Бэкап не найден: " << backup_file << RESET << '\n';
        return 1;
    }
    if (!yes("Восстановить пакеты из бэкапа?")) return 0;
    std::ifstream input(backup_file);
    std::string line;
    int result = 0;
    while (std::getline(input, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream fields(line);
        std::string package;
        fields >> package;
        if (!valid(package)) continue;
        if (exec({"pacman", "-Q", package}, true).code != 0)
            result = std::max(result, exec(sudo_pacman({"-S", "--noconfirm", package}), tui_mode()).code);
    }
    return result;
}

int security_command(const std::string &package) {
    if (fs::is_regular_file(package)) return security_scan(package);
    std::cout << CYAN << "🛡️ Проверка пакета " << package << RESET << '\n';
    const auto result = exec({"pacman", "-Qi", package}, true);
    if (result.code) {
        std::cout << YELLOW << "Пакет не установлен локально; укажите путь к PKGBUILD для полного сканирования." << RESET << '\n';
        return result.code;
    }
    std::cout << GREEN << "✅ Пакет найден в локальной базе pacman" << RESET << '\n';
    return 0;
}

int diagnostic() {
    std::cout << CYAN << "🔬 Диагностика OCTO" << RESET << '\n';
    for (const auto &tool : {"g++", "curl", "git", "pacman", "makepkg", "sudo", "gpg"}) {
        const auto result = exec({"which", tool}, true);
        std::cout << (result.code ? RED : GREEN) << (result.code ? "❌ " : "✅ ") << tool << RESET << '\n';
    }
    std::cout << "📁 OCTO home: " << root() << '\n';
    std::cout << "📦 SQLite DB: " << (fs::exists(sqlite_db()) ? "OK" : "missing") << '\n';
    return 0;
}

int monitor() {
    std::cout << CYAN << "📊 Мониторинг системы" << RESET << '\n';
    for (const auto &command : {std::vector<std::string>{"uptime"}, std::vector<std::string>{"free", "-h"}, std::vector<std::string>{"df", "-h", "/"}})
        if (const auto result = exec(command, true); !result.code) std::cout << result.output;
    std::cout << "OCTO cache files: " << files(cache()) << "\nOCTO backups: " << files(backups()) << '\n';
    return 0;
}

int stats() {
    sqlite3 *database = open_db();
    int package_count = 0;
    int history_count = 0;
    if (database) {
        sqlite3_stmt *statement = nullptr;
        if (sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM packages", -1, &statement, nullptr) == SQLITE_OK) {
            if (sqlite3_step(statement) == SQLITE_ROW) package_count = sqlite3_column_int(statement, 0);
            sqlite3_finalize(statement);
        }
        if (sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM history", -1, &statement, nullptr) == SQLITE_OK) {
            if (sqlite3_step(statement) == SQLITE_ROW) history_count = sqlite3_column_int(statement, 0);
            sqlite3_finalize(statement);
        }
        sqlite3_close(database);
    }
    std::cout << CYAN << "📊 Статистика OCTO" << RESET << '\n'
              << GREEN << "🐙 Установлено: " << package_count << RESET << '\n'
              << YELLOW << "📜 История: " << history_count << RESET << '\n'
              << "💾 Бэкапов: " << files(backups()) << "\n📋 Логов: " << files(logs()) << '\n';
    return 0;
}

void help() {
    std::cout << CYAN << "🐙 OCTO C++ backend 0.5.0" << RESET << R"(

  install|-S <pkg> [--aur]   установить пакет
  remove|-R <pkg> [-d]        удалить пакет
  update|-Syu                 обновить систему
  search|-Ss <query>          поиск в репозиториях и AUR
  info|-Si <pkg>              информация о пакете
  size <pkg>                  установленный размер пакета
  popularity <pkg>            популярность пакета в AUR
  deps|зависимости <pkg>      зависимости и конфликты PKGBUILD
  list|-Q, shell              список пакетов
  catch, release, tentacle    AUR-совместимые команды
  army                        обновить установленные пакеты
  stats, cache-stats          статистика
  clean cache|backups|history|all очистка
  benchmark, profile          производительность
  monitor, diagnostic, market диагностика и мониторинг
  security <PKGBUILD>         проверка безопасности
  backup, restore <file>      бэкап и восстановление
  matrix, pulse, interactive  демонстрационные текстовые режимы
  version|-v                  версия backend
)";
}

int dispatch(const std::vector<std::string> &a) {
    init();
    if (a.empty()) { help(); return 0; }
    record_command(a);
    std::vector<std::string> args = a;
    const std::map<std::string, std::string> aliases = {
        {"поймать", "catch"}, {"установить", "install"}, {"инсталл", "install"},
        {"отпустить", "release"}, {"удалить", "remove"}, {"щупальца", "tentacle"},
        {"чернила", "ink"}, {"армия", "army"}, {"ракушка", "shell"},
        {"статистика", "stats"}, {"очистка", "clean"}, {"бэкап", "backup"},
        {"восстановить", "restore"}, {"инфо", "info"}, {"поиск", "search"}, {"найти", "search"},
        {"обновить", "update"}, {"помощь", "help"}, {"журнал", "logs"},
        {"размер", "size"}, {"популярность", "popularity"}
    };
    if (const auto it = aliases.find(args[0]); it != aliases.end()) args[0] = it->second;
    if (const auto custom = get_config("alias." + args[0]); !custom.empty()) args[0] = custom;
    if (args[0] == "help" || args[0] == "-h" || args[0] == "--help") { help(); return 0; }
    if (args[0] == "version" || args[0] == "-v") { std::cout << "OCTO C++ backend 0.5.0\n"; return 0; }
    if (args[0] == "install" || args[0] == "-S" || args[0] == "catch") {
        const bool aur = args[0] == "catch" || std::any_of(args.begin() + 1, args.end(),
            [](const std::string &arg) { return arg == "--aur" || arg == "-a"; });
        if (args[0] == "catch") return args.size() > 1 ? install_package(args[1], true) : 2;
        const auto package = std::find_if(args.begin() + 1, args.end(),
            [](const std::string &arg) { return arg != "--aur" && arg != "-a"; });
        return package != args.end() ? install_package(*package, aur) : 2;
    }
    if (args[0] == "алиас" || args[0] == "alias") return aliases_command(args);
    if (args[0] == "настройки" || args[0] == "config") {
        if (args.size() == 1) {
            const auto theme = get_config("theme");
            std::cout << "🐙 Тема: " << (theme.empty() ? "океан" : theme) << '\n';
            return 0;
        }
        if (args.size() == 3 && (args[1] == "тема" || args[1] == "theme"))
            return (args[2] == "океан" || args[2] == "ocean" || args[2] == "классическая" || args[2] == "classic")
                ? (set_config("theme", args[2]) ? 0 : 1) : 2;
        return 2;
    }
    if (args[0] == "update" || args[0] == "-Syu") {
        if (backup() != 0) {
            log_error("automatic backup failed before update");
            return 1;
        }
        const auto result = exec_with_spinner(sudo_pacman({"-Syu"}),
                                              "Осьминог обновляет систему", true);
        if (tui_mode() && !result.output.empty()) std::cout << result.output;
        if (result.code) log_error("update failed"); else log_action("update", "system updated");
        return result.code;
    }
    if (args[0] == "remove" || args[0] == "release" || args[0] == "-R") {
        const bool deps = args.size() > 1 && (args[1] == "--deps" || args[1] == "-d");
        const size_t index = deps ? 2 : 1;
        return args.size() > index ? remove_package(args[index], deps) : 2;
    }
    if (args[0] == "search" || args[0] == "-Ss" || args[0] == "tentacle") {
        const size_t index = (args.size() > 1 && (args[1] == "--aur" || args[1] == "-a")) ? 2 : 1;
        if (args.size() <= index) return 2;
        if (index == 1) exec({"pacman", "-Ss", args[index]});
        return aur_search(args[index]);
    }
    if (args[0] == "info" || args[0] == "-Si" || args[0] == "ink") {
        if (args.size() <= 1) return 2;
        const auto official = exec({"pacman", "-Si", args[1]}, true);
        if (!official.code) {
            std::cout << "[офиц.]\n" << official.output;
            return 0;
        }
        return aur_info(args[1]);
    }
    if (args[0] == "size") return args.size() == 2 ? package_size(args[1]) : 2;
    if (args[0] == "popularity") return args.size() == 2 ? package_popularity(args[1]) : 2;
    if (args[0] == "deps" || args[0] == "dependencies" || args[0] == "зависимости")
        return args.size() == 2 ? dependencies_command(args[1]) : 2;
    if (args[0] == "list" || args[0] == "-Q" || args[0] == "shell") return list_packages();
    if (args[0] == "stats") return stats();
    if (args[0] == "cache-stats") return std::cout << "📦 Кэш: " << files(cache()) << " файлов\n", 0;
    if (args[0] == "clean") {
        if (args.size() == 2 && (args[1] == "history" || args[1] == "история")) return clear_command_history();
        return args.size() > 1 ? clean(args[1]) : 2;
    }
    if (args[0] == "backup") return backup();
    if (args[0] == "restore") {
        if (args.size() <= 1) return 2;
        fs::path backup_file = args[1];
        if (!backup_file.is_absolute() && !fs::is_regular_file(backup_file)) backup_file = backups() / backup_file;
        return restore_backup(backup_file);
    }
    if (args[0] == "security") return args.size() > 1 ? security_command(args[1]) : 2;
    if (args[0] == "sandbox") {
        std::cout << YELLOW << "sandbox: сборка выполняется в отдельном временном каталоге" << RESET << '\n';
        return args.size() > 1 ? install_package(args[1], true) : 2;
    }
    if (args[0] == "diagnostic" || args[0] == "diag") return diagnostic();
    if (args[0] == "monitor") return monitor();
    if (args[0] == "benchmark") {
        const auto start = std::chrono::steady_clock::now();
        const auto result = exec({"curl", "-sS", "--compressed", "--connect-timeout", "3",
            "--max-time", "10", "-o", "/dev/null", "-w",
            "dns=%{time_namelookup} connect=%{time_connect} tls=%{time_appconnect} "
            "ttfb=%{time_starttransfer} total=%{time_total}",
            "https://aur.archlinux.org/rpc/v5/info?arg=neofetch"}, true);
        const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
        if (!result.code) {
            std::cout << "AUR API: total " << result.output << " (wall " << ms << "ms)\n";
        } else {
            std::cout << "AUR API: недоступен (wall " << ms << "ms)\n";
        }
        return result.code;
    }
    if (args[0] == "profile") {
        std::cout << YELLOW << "profile: пока доступен только общий мониторинг системы" << RESET << '\n';
        return monitor();
    }
    if (args[0] == "predict") {
        std::cout << YELLOW << "predict: экспериментальная оценка, не измерение времени установки" << RESET << '\n'
                  << "Прогноз: 30–60 секунд для " << (args.size() > 1 ? args[1] : "пакета") << '\n';
        return 0;
    }
    if (args[0] == "logs") {
        const auto error_log = logs() / "errors.log";
        if (!fs::is_regular_file(error_log)) {
            std::cout << "Лог ошибок пока пуст.\n";
            return 0;
        }
        return exec({"tail", "-n", "50", error_log.string()}).code;
    }
    if (args[0] == "history" || args[0] == "история") {
        if (args.size() > 1 && (args[1] == "clear" || args[1] == "очистить")) return clear_command_history();
        if (fs::is_regular_file(command_history_file())) {
            std::cout << read(command_history_file());
            return 0;
        }
        sqlite3 *database = open_db();
        if (!database) return 1;
        sqlite3_stmt *statement = nullptr;
        sqlite3_prepare_v2(database, "SELECT action, package_name, timestamp FROM history ORDER BY id DESC LIMIT 50", -1, &statement, nullptr);
        while (statement && sqlite3_step(statement) == SQLITE_ROW)
            std::cout << "  " << sqlite3_column_text(statement, 2) << " "
                      << sqlite3_column_text(statement, 0) << " "
                      << sqlite3_column_text(statement, 1) << '\n';
        sqlite3_finalize(statement);
        sqlite3_close(database);
        return 0;
    }
    if (args[0] == "market") return std::cout << YELLOW << "market: демонстрационный режим, источник данных ещё не подключён" << RESET << '\n', 0;
    if (args[0] == "matrix") return std::cout << YELLOW << "matrix: демонстрационный режим" << RESET << "\n🐙 🦑 🐚 🐙 🦑\n", 0;
    if (args[0] == "pulse") return std::cout << YELLOW << "pulse: демонстрационный режим" << RESET << "\n🐙 OCTO работает...\n", 0;
    if (args[0] == "interactive") return help(), 0;
    if (args[0] == "army") {
        if (backup() != 0) {
            log_error("automatic backup failed before army update");
            return 1;
        }
        const auto result = exec_with_spinner(sudo_pacman({"-Syu"}),
                                              "Осьминог обновляет армию", true);
        if (tui_mode() && !result.output.empty()) std::cout << result.output;
        if (result.code) log_error("army update failed"); else log_action("update", "army update completed");
        return result.code;
    }
    log_error("unknown command: " + args[0]);
    std::cerr << RED << "🐙 Команда не найдена: " << args[0] << RESET << '\n';
    return 1;
}

} // namespace

int main(int argc, char **argv) {
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    return dispatch(args);
}
