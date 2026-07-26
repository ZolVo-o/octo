#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <regex>
#include <sstream>
#include <string>
#include <sys/wait.h>
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
fs::path root() { return home() / ".octo"; }
fs::path db() { return root() / "db"; }
fs::path packages_db() { return db() / "packages.json"; }
fs::path history_db() { return db() / "history.json"; }
fs::path cache() { return root() / "cache"; }
fs::path backups() { return root() / "backups"; }
fs::path logs() { return root() / "logs"; }
constexpr std::chrono::seconds AUR_CACHE_TTL{300};

void init() {
    for (const auto &path : {db(), root() / "pkgs", logs(), backups(), cache()})
        fs::create_directories(path);
    if (!fs::exists(packages_db()))
        std::ofstream(packages_db()) << "{\"installed\":[],\"total\":0}\n";
    if (!fs::exists(history_db()))
        std::ofstream(history_db()) << "{\"history\":[]}\n";
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

size_t matches(const std::string &text, const std::string &key) {
    const std::regex pattern("\\\"" + key + "\\\"\\s*:");
    return static_cast<size_t>(std::distance(std::sregex_iterator(text.begin(), text.end(), pattern), {}));
}

size_t files(const fs::path &path) {
    if (!fs::exists(path)) return 0;
    return static_cast<size_t>(std::distance(fs::directory_iterator(path), fs::directory_iterator{}));
}

void history(const std::string &action, const std::string &name) {
    std::string json = read(history_db());
    const auto position = json.rfind("]}");
    if (position == std::string::npos) return;
    const bool nonempty = json.find("\"history\":[]") == std::string::npos;
    json.insert(position, std::string(nonempty ? "," : "") +
        "{\"action\":\"" + action + "\",\"name\":\"" + name +
        "\",\"version\":\"unknown\",\"time\":\"now\"}");
    write(history_db(), json);
}

void package_add(const std::string &name) {
    std::string json = read(packages_db());
    if (json.find("\"name\":\"" + name + "\"") != std::string::npos) return;
    const auto position = json.rfind("]}");
    if (position == std::string::npos) return;
    const bool nonempty = !std::regex_search(json, std::regex("\"installed\"\\s*:\\s*\\[\\s*\\]"));
    json.insert(position, std::string(nonempty ? "," : "") +
        "{\"name\":\"" + name + "\",\"version\":\"unknown\",\"installed_at\":\"now\"}");
    json = std::regex_replace(json, std::regex("\"total\"\\s*:\\s*[0-9]+"),
                              "\"total\":" + std::to_string(matches(json, "name")));
    write(packages_db(), json);
    history("install", name);
}

void package_remove(const std::string &name) {
    std::string json = read(packages_db());
    const std::regex entry("\\{\\s*\"name\"\\s*:\\s*\"" + name +
        "\"\\s*,\\s*\"version\"\\s*:\\s*\"[^\"]*\"\\s*,\\s*\"installed_at\"\\s*:\\s*\"[^\"]*\"\\s*\\},?");
    json = std::regex_replace(json, entry, "");
    json = std::regex_replace(json, std::regex("\"total\"\\s*:\\s*[0-9]+"),
                              "\"total\":" + std::to_string(matches(json, "name")));
    write(packages_db(), json);
    history("remove", name);
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
    return exec({"curl", "-fsSL", "--compressed", "--retry", "2",
                 "--retry-delay", "1", "--retry-connrefused",
                 "--connect-timeout", "3", "--max-time", "8", url}, true);
}

int aur_search(const std::string &query) {
    if (!valid(query)) return 2;
    std::cout << CYAN << "🔍 Поиск в AUR: " << query << RESET << '\n';
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
        return 1;
    }
    const std::regex item("\"Name\"\\s*:\\s*\"([^\"]+)\".*?\"Version\"\\s*:\\s*\"([^\"]+)\".*?\"Description\"\\s*:\\s*(?:\"([^\"]*)\"|null)");
    size_t found = 0;
    for (std::sregex_iterator it(result.output.begin(), result.output.end(), item), end; it != end && found < 20; ++it, ++found)
        std::cout << "  " << GREEN << (*it)[1] << RESET << " v" << YELLOW << (*it)[2] << RESET
                  << "\n    " << (*it)[3] << '\n';
    if (!found) std::cout << YELLOW << "⚠️ Ничего не найдено" << RESET << '\n';
    return 0;
}

int install_package(const std::string &name, bool aur) {
    if (!valid(name)) return 2;
    std::cout << CYAN << "📦 Установка " << name << (aur ? " из AUR" : " из репозитория") << RESET << '\n';
    if (!yes("Продолжить?")) return 0;
    Result result;
    if (!aur) {
        result = exec({"sudo", "pacman", "-S", "--noconfirm", name});
    } else {
        const fs::path directory = fs::path("/tmp") / ("octo-" + name);
        fs::remove_all(directory);
        result = exec({"git", "clone", "https://aur.archlinux.org/" + name + ".git", directory.string()});
        if (!result.code) result = exec({"makepkg", "-si", "--noconfirm"}, false, directory);
        fs::remove_all(directory);
    }
    if (!result.code) {
        package_add(name);
        std::cout << GREEN << "✅ Установлено" << RESET << '\n';
    }
    return result.code;
}

int remove_package(const std::string &name, bool dependencies) {
    if (!valid(name)) return 2;
    if (!yes("Удалить " + name + "?")) return 0;
    const auto result = exec({"sudo", "pacman", dependencies ? "-Rsc" : "-R", name});
    if (!result.code) {
        package_remove(name);
        std::cout << GREEN << "✅ Удалено" << RESET << '\n';
    }
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
            result = std::max(result, exec({"sudo", "pacman", "-S", "--noconfirm", package}).code);
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
    std::cout << "📦 Packages DB: " << (fs::exists(packages_db()) ? "OK" : "missing") << '\n';
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
    const auto packages = read(packages_db());
    const auto history_json = read(history_db());
    std::cout << CYAN << "📊 Статистика OCTO" << RESET << '\n'
              << GREEN << "🐙 Установлено: " << matches(packages, "name") << RESET << '\n'
              << YELLOW << "📜 История: " << matches(history_json, "action") << RESET << '\n'
              << "💾 Бэкапов: " << files(backups()) << "\n📋 Логов: " << files(logs()) << '\n';
    return 0;
}

void help() {
    std::cout << CYAN << "🐙 OCTO C++ backend 5.0" << RESET << R"(

  install|-S <pkg> [--aur]   установить пакет
  remove|-R <pkg> [-d]        удалить пакет
  update|-Syu                 обновить систему
  search|-Ss <query>          поиск в репозиториях и AUR
  info|-Si <pkg>              информация о пакете
  list|-Q, shell              список пакетов
  catch, release, tentacle    AUR-совместимые команды
  army                        обновить установленные пакеты
  stats, cache-stats          статистика
  clean cache|backups|all     очистка
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
    if (a.empty() || a[0] == "help" || a[0] == "-h" || a[0] == "--help") { help(); return 0; }
    if (a[0] == "version" || a[0] == "-v") { std::cout << "OCTO C++ backend 5.0\n"; return 0; }
    if (a[0] == "install" || a[0] == "-S" || a[0] == "catch") {
        const bool aur = a[0] == "catch" || (a.size() > 1 && (a[1] == "--aur" || a[1] == "-a"));
        const size_t index = a[0] == "catch" ? 1 : (aur ? 2 : 1);
        return a.size() > index ? install_package(a[index], aur) : 2;
    }
    if (a[0] == "update" || a[0] == "-Syu") return exec({"sudo", "pacman", "-Syu"}).code;
    if (a[0] == "remove" || a[0] == "release" || a[0] == "-R") {
        const bool deps = a.size() > 1 && (a[1] == "--deps" || a[1] == "-d");
        const size_t index = deps ? 2 : 1;
        return a.size() > index ? remove_package(a[index], deps) : 2;
    }
    if (a[0] == "search" || a[0] == "-Ss" || a[0] == "tentacle") {
        const size_t index = (a.size() > 1 && (a[1] == "--aur" || a[1] == "-a")) ? 2 : 1;
        if (a.size() <= index) return 2;
        if (index == 1) exec({"pacman", "-Ss", a[index]});
        return aur_search(a[index]);
    }
    if (a[0] == "info" || a[0] == "-Si" || a[0] == "ink")
        return a.size() > 1 ? exec({"pacman", "-Si", a[1]}).code : 2;
    if (a[0] == "list" || a[0] == "-Q" || a[0] == "shell") return exec({"pacman", "-Qe"}).code;
    if (a[0] == "stats") return stats();
    if (a[0] == "cache-stats") return std::cout << "📦 Кэш: " << files(cache()) << " файлов\n", 0;
    if (a[0] == "clean") return a.size() > 1 ? clean(a[1]) : 2;
    if (a[0] == "backup") return backup();
    if (a[0] == "restore") return a.size() > 1 ? restore_backup(a[1]) : 2;
    if (a[0] == "security") return a.size() > 1 ? security_command(a[1]) : 2;
    if (a[0] == "sandbox") {
        std::cout << YELLOW << "sandbox: сборка выполняется в отдельном временном каталоге" << RESET << '\n';
        return a.size() > 1 ? install_package(a[1], true) : 2;
    }
    if (a[0] == "diagnostic" || a[0] == "diag") return diagnostic();
    if (a[0] == "monitor") return monitor();
    if (a[0] == "benchmark") {
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
    if (a[0] == "profile") {
        std::cout << YELLOW << "profile: пока доступен только общий мониторинг системы" << RESET << '\n';
        return monitor();
    }
    if (a[0] == "predict") {
        std::cout << YELLOW << "predict: экспериментальная оценка, не измерение времени установки" << RESET << '\n'
                  << "Прогноз: 30–60 секунд для " << (a.size() > 1 ? a[1] : "пакета") << '\n';
        return 0;
    }
    if (a[0] == "logs") {
        const auto error_log = logs() / "errors.log";
        if (!fs::is_regular_file(error_log)) {
            std::cout << "Лог ошибок пока пуст.\n";
            return 0;
        }
        return exec({"tail", "-n", "50", error_log.string()}).code;
    }
    if (a[0] == "market") return std::cout << YELLOW << "market: демонстрационный режим, источник данных ещё не подключён" << RESET << '\n', 0;
    if (a[0] == "matrix") return std::cout << YELLOW << "matrix: демонстрационный режим" << RESET << "\n🐙 🦑 🐚 🐙 🦑\n", 0;
    if (a[0] == "pulse") return std::cout << YELLOW << "pulse: демонстрационный режим" << RESET << "\n🐙 OCTO работает...\n", 0;
    if (a[0] == "interactive") return help(), 0;
    if (a[0] == "army") return exec({"sudo", "pacman", "-Syu"}).code;
    std::cerr << RED << "🐙 Команда не найдена: " << a[0] << RESET << '\n';
    return 1;
}

} // namespace

int main(int argc, char **argv) {
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    return dispatch(args);
}
