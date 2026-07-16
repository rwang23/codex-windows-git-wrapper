#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <shellapi.h>
#include <tlhelp32.h>

#include <cwctype>
#include <string>
#include <unordered_map>
#include <vector>

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "shell32.lib")

struct ProcessInfo {
    DWORD parentProcessId;
    std::wstring executableName;
    std::wstring executablePath;
};

static bool g_exitAfterFirstMatch = false;
static std::wstring g_logPath;
static unsigned int g_scanTick = 0;

enum class WindowRule {
    None,
    CodexShell,
    CodexBackend,
    ChromeNativeHost,
};

static std::wstring ToLower(const std::wstring& value) {
    std::wstring result = value;
    for (wchar_t& character : result) {
        character = static_cast<wchar_t>(towlower(character));
    }
    return result;
}

static bool IsCodexDesktopExecutable(const std::wstring& executableName) {
    return executableName == L"chatgpt.exe" || executableName == L"codex.exe";
}

static bool IsConsoleLauncherExecutable(const std::wstring& executableName) {
    return executableName == L"git.exe" ||
        executableName == L"cmd.exe" ||
        executableName == L"powershell.exe" ||
        executableName == L"pwsh.exe";
}

static bool IsCodexBackendSurfaceExecutable(const std::wstring& executableName) {
    return executableName == L"codex.exe" ||
        executableName == L"conhost.exe" ||
        executableName == L"openconsole.exe" ||
        executableName == L"codex-command-runner.exe" ||
        executableName == L"codex-code-mode-host.exe" ||
        executableName == L"node_repl.exe";
}

static bool IsPotentialWindowOwnerExecutable(const std::wstring& executableName) {
    return IsConsoleLauncherExecutable(executableName) ||
        IsCodexBackendSurfaceExecutable(executableName);
}

static bool IsCodexChromeExtensionHostPath(const std::wstring& executablePath) {
    return executablePath.find(L"\\plugins\\cache\\openai-bundled\\chrome\\") != std::wstring::npos &&
        executablePath.find(L"\\extension-host\\windows\\x64\\extension-host.exe") != std::wstring::npos;
}

static std::wstring GetProcessImagePath(DWORD processId) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
    if (process == nullptr) {
        return L"";
    }

    std::vector<wchar_t> buffer(32768);
    DWORD length = static_cast<DWORD>(buffer.size());
    std::wstring result;
    if (QueryFullProcessImageNameW(process, 0, buffer.data(), &length)) {
        result.assign(buffer.data(), length);
    }
    CloseHandle(process);
    return ToLower(result);
}

static std::wstring GetProcessExecutableName(DWORD processId) {
    std::wstring path = GetProcessImagePath(processId);
    size_t slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? path : path.substr(slash + 1);
}

static WindowRule ClassifyWindowProcessGraph(
    const std::unordered_map<DWORD, ProcessInfo>& processes,
    DWORD processId) {
    const auto owner = processes.find(processId);
    if (owner == processes.end()) {
        return WindowRule::None;
    }

    DWORD chromeCmdProcessId = 0;
    DWORD cursor = processId;
    for (int depth = 0; depth < 4; depth++) {
        const auto iterator = processes.find(cursor);
        if (iterator == processes.end()) {
            break;
        }
        if (iterator->second.executableName == L"cmd.exe") {
            chromeCmdProcessId = cursor;
            break;
        }
        if (depth == 0 &&
            iterator->second.executableName != L"conhost.exe" &&
            iterator->second.executableName != L"openconsole.exe") {
            break;
        }
        cursor = iterator->second.parentProcessId;
    }

    if (chromeCmdProcessId != 0) {
        bool hasChromeParent = false;
        cursor = processes.at(chromeCmdProcessId).parentProcessId;
        for (int depth = 0; depth < 4; depth++) {
            const auto iterator = processes.find(cursor);
            if (iterator == processes.end()) {
                break;
            }
            if (iterator->second.executableName == L"chrome.exe") {
                hasChromeParent = true;
                break;
            }
            cursor = iterator->second.parentProcessId;
        }

        if (hasChromeParent) {
            for (const auto& entry : processes) {
                if (entry.second.parentProcessId == chromeCmdProcessId &&
                    entry.second.executableName == L"extension-host.exe" &&
                    IsCodexChromeExtensionHostPath(entry.second.executablePath)) {
                    return WindowRule::ChromeNativeHost;
                }
            }

            // Chrome creates the cmd.exe bridge before extension-host.exe is
            // visible in the process snapshot. A direct Chrome -> cmd.exe
            // console is a native-messaging bridge, not a user terminal.
            return WindowRule::ChromeNativeHost;
        }
    }

    bool hasConsoleLauncher = false;
    bool hasCodexDesktop = false;
    bool hasChatGptDesktop = false;
    bool hasCodexBackend = false;
    cursor = processId;
    for (int depth = 0; depth < 64; depth++) {
        const auto iterator = processes.find(cursor);
        if (iterator == processes.end()) {
            break;
        }

        const std::wstring& executableName = iterator->second.executableName;
        hasConsoleLauncher = hasConsoleLauncher || IsConsoleLauncherExecutable(executableName);
        hasCodexDesktop = hasCodexDesktop || IsCodexDesktopExecutable(executableName);
        hasChatGptDesktop = hasChatGptDesktop || executableName == L"chatgpt.exe";
        hasCodexBackend = hasCodexBackend || executableName == L"codex.exe";
        if (hasConsoleLauncher && hasCodexDesktop) {
            return WindowRule::CodexShell;
        }

        DWORD parentProcessId = iterator->second.parentProcessId;
        if (parentProcessId == 0 || parentProcessId == cursor) {
            break;
        }
        cursor = parentProcessId;
    }

    if (hasChatGptDesktop &&
        hasCodexBackend &&
        IsCodexBackendSurfaceExecutable(owner->second.executableName)) {
        return WindowRule::CodexBackend;
    }

    return WindowRule::None;
}

static bool HasCodexConsoleLauncherAncestry(
    const std::unordered_map<DWORD, ProcessInfo>& processes,
    DWORD processId) {
    return ClassifyWindowProcessGraph(processes, processId) != WindowRule::None;
}

static std::unordered_map<DWORD, ProcessInfo> GetProcessSnapshot() {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return {};
    }

    std::unordered_map<DWORD, ProcessInfo> processes;
    PROCESSENTRY32W entry = {};
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snapshot, &entry)) {
        do {
            std::wstring executableName = ToLower(entry.szExeFile);
            std::wstring executablePath;
            if (executableName == L"extension-host.exe") {
                executablePath = GetProcessImagePath(entry.th32ProcessID);
            }
            processes.emplace(entry.th32ProcessID, ProcessInfo{
                entry.th32ParentProcessID,
                executableName,
                executablePath,
            });
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);

    return processes;
}

static std::wstring GetEnvironmentValue(const wchar_t* name) {
    DWORD length = GetEnvironmentVariableW(name, nullptr, 0);
    if (length == 0) {
        return L"";
    }
    std::wstring value(length, L'\0');
    DWORD copied = GetEnvironmentVariableW(name, &value[0], length);
    if (copied == 0 || copied >= length) {
        return L"";
    }
    value.resize(copied);
    return value;
}

static std::string WideToUtf8(const std::wstring& value) {
    if (value.empty()) {
        return "";
    }
    int length = WideCharToMultiByte(
        CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (length <= 0) {
        return "";
    }
    std::string result(length, '\0');
    WideCharToMultiByte(
        CP_UTF8, 0, value.data(), static_cast<int>(value.size()), &result[0], length, nullptr, nullptr);
    return result;
}

static const wchar_t* WindowRuleName(WindowRule rule) {
    switch (rule) {
    case WindowRule::CodexShell:
        return L"codex-shell";
    case WindowRule::CodexBackend:
        return L"codex-backend";
    case WindowRule::ChromeNativeHost:
        return L"chrome-native-host";
    default:
        return L"none";
    }
}

static void AppendGuardLog(
    DWORD processId,
    const std::wstring& executableName,
    const std::wstring& className,
    WindowRule rule) {
    if (g_logPath.empty()) {
        return;
    }

    HANDLE file = CreateFileW(
        g_logPath.c_str(),
        GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return;
    }

    LARGE_INTEGER size = {};
    if (GetFileSizeEx(file, &size) && size.QuadPart > 1024 * 1024) {
        LARGE_INTEGER start = {};
        SetFilePointerEx(file, start, nullptr, FILE_BEGIN);
        SetEndOfFile(file);
    } else {
        LARGE_INTEGER end = {};
        SetFilePointerEx(file, end, nullptr, FILE_END);
    }

    SYSTEMTIME now = {};
    GetSystemTime(&now);
    wchar_t timestamp[64] = {};
    swprintf_s(
        timestamp,
        L"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
        now.wYear,
        now.wMonth,
        now.wDay,
        now.wHour,
        now.wMinute,
        now.wSecond,
        now.wMilliseconds);

    std::wstring line = std::wstring(timestamp) +
        L" hidden pid=" + std::to_wstring(processId) +
        L" process=" + executableName +
        L" class=" + className +
        L" rule=" + WindowRuleName(rule) + L"\r\n";
    std::string bytes = WideToUtf8(line);
    DWORD written = 0;
    if (!bytes.empty()) {
        WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr);
    }
    CloseHandle(file);
}

static bool HideMatchingWindow(
    HWND window,
    const std::unordered_map<DWORD, ProcessInfo>& processes) {
    if (window == nullptr) {
        return false;
    }

    DWORD processId = 0;
    GetWindowThreadProcessId(window, &processId);
    const auto process = processes.find(processId);
    if (processId == 0 || process == processes.end()) {
        return false;
    }

    WindowRule rule = ClassifyWindowProcessGraph(processes, processId);
    if (rule == WindowRule::None) {
        return false;
    }

    wchar_t classNameBuffer[128] = {};
    GetClassNameW(window, classNameBuffer, 128);
    bool wasVisible = IsWindowVisible(window) != FALSE;
    ShowWindow(window, SW_HIDE);
    if (wasVisible) {
        AppendGuardLog(processId, process->second.executableName, classNameBuffer, rule);
        if (g_exitAfterFirstMatch) {
            PostQuitMessage(0);
        }
    }
    return true;
}

static BOOL CALLBACK CollectPotentialWindow(HWND window, LPARAM parameter) {
    if (window == nullptr || IsWindowVisible(window) == FALSE) {
        return TRUE;
    }

    DWORD processId = 0;
    GetWindowThreadProcessId(window, &processId);
    if (processId == 0 ||
        !IsPotentialWindowOwnerExecutable(GetProcessExecutableName(processId))) {
        return TRUE;
    }

    auto* windows = reinterpret_cast<std::vector<HWND>*>(parameter);
    if (windows != nullptr) {
        windows->push_back(window);
    }
    return TRUE;
}

static void ScanExistingWindows() {
    std::vector<HWND> candidateWindows;
    EnumWindows(CollectPotentialWindow, reinterpret_cast<LPARAM>(&candidateWindows));
    if (candidateWindows.empty()) {
        return;
    }

    const auto processes = GetProcessSnapshot();
    for (HWND window : candidateWindows) {
        HideMatchingWindow(window, processes);
    }
}

static void CALLBACK OnWindowEvent(
    HWINEVENTHOOK,
    DWORD eventType,
    HWND window,
    LONG objectId,
    LONG childId,
    DWORD,
    DWORD) {
    if ((eventType != EVENT_OBJECT_CREATE && eventType != EVENT_OBJECT_SHOW) ||
        objectId != OBJID_WINDOW ||
        childId != 0 ||
        window == nullptr) {
        return;
    }

    wchar_t className[128] = {};
    bool isTraditionalConsole =
        GetClassNameW(window, className, 128) != 0 &&
        _wcsicmp(className, L"ConsoleWindowClass") == 0;
    if (!isTraditionalConsole) {
        DWORD processId = 0;
        GetWindowThreadProcessId(window, &processId);
        if (processId == 0 ||
            !IsPotentialWindowOwnerExecutable(GetProcessExecutableName(processId))) {
            return;
        }
    }

    const auto processes = GetProcessSnapshot();
    if (!processes.empty()) {
        HideMatchingWindow(window, processes);
    }
}

static void CALLBACK OnScanTimer(HWND, UINT, UINT_PTR, DWORD) {
    g_scanTick++;
    if (g_scanTick == 2 ||
        g_scanTick == 5 ||
        g_scanTick == 10 ||
        g_scanTick == 20 ||
        g_scanTick % 30 == 0) {
        ScanExistingWindows();
    }
}

static bool HasArgument(const wchar_t* expectedArgument) {
    if (expectedArgument == nullptr) {
        return false;
    }

    int argumentCount = 0;
    LPWSTR* arguments = CommandLineToArgvW(GetCommandLineW(), &argumentCount);
    if (arguments == nullptr) {
        return false;
    }

    bool result = false;
    for (int index = 1; index < argumentCount; index++) {
        if (_wcsicmp(arguments[index], expectedArgument) == 0) {
            result = true;
            break;
        }
    }
    LocalFree(arguments);
    return result;
}

static bool RunProcessGraphSelfTest() {
    {
        std::unordered_map<DWORD, ProcessInfo> processes = {
            {100, {0, L"chatgpt.exe"}},
            {101, {100, L"cmd.exe"}},
            {102, {101, L"conhost.exe"}},
        };
        if (!HasCodexConsoleLauncherAncestry(processes, 102)) {
            return false;
        }
    }

    {
        std::unordered_map<DWORD, ProcessInfo> processes = {
            {200, {0, L"codex.exe"}},
            {201, {200, L"powershell.exe"}},
            {202, {201, L"conhost.exe"}},
        };
        if (!HasCodexConsoleLauncherAncestry(processes, 202)) {
            return false;
        }
    }

    {
        std::unordered_map<DWORD, ProcessInfo> processes = {
            {300, {0, L"chatgpt.exe"}},
            {301, {300, L"git.exe"}},
            {302, {301, L"conhost.exe"}},
        };
        if (!HasCodexConsoleLauncherAncestry(processes, 302)) {
            return false;
        }
    }

    {
        std::unordered_map<DWORD, ProcessInfo> processes = {
            {400, {0, L"chatgpt.exe"}},
            {401, {400, L"conhost.exe"}},
        };
        if (HasCodexConsoleLauncherAncestry(processes, 401)) {
            return false;
        }
    }

    {
        std::unordered_map<DWORD, ProcessInfo> processes = {
            {500, {0, L"cmd.exe"}},
            {501, {500, L"conhost.exe"}},
        };
        if (HasCodexConsoleLauncherAncestry(processes, 501)) {
            return false;
        }
    }

    {
        std::unordered_map<DWORD, ProcessInfo> processes = {
            {600, {0, L"chatgpt.exe"}},
            {601, {600, L"codex.exe"}},
        };
        if (!HasCodexConsoleLauncherAncestry(processes, 601)) {
            return false;
        }
    }

    {
        std::unordered_map<DWORD, ProcessInfo> processes = {
            {700, {0, L"chrome.exe"}},
            {701, {700, L"cmd.exe"}},
            {702, {701, L"extension-host.exe", L"c:\\users\\test\\.codex\\plugins\\cache\\openai-bundled\\chrome\\26.707.1\\extension-host\\windows\\x64\\extension-host.exe"}},
        };
        if (!HasCodexConsoleLauncherAncestry(processes, 701)) {
            return false;
        }
    }

    {
        std::unordered_map<DWORD, ProcessInfo> processes = {
            {800, {0, L"chatgpt.exe"}},
            {801, {800, L"codex.exe"}},
            {802, {801, L"notepad.exe"}},
        };
        if (HasCodexConsoleLauncherAncestry(processes, 802)) {
            return false;
        }
    }

    return true;
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    if (HasArgument(L"--self-test-process-graph")) {
        return RunProcessGraphSelfTest() ? 0 : 1;
    }

    g_exitAfterFirstMatch = HasArgument(L"--once");
    g_logPath = GetEnvironmentValue(L"CODEX_CONSOLE_GUARD_LOG");
    HWINEVENTHOOK hook = SetWinEventHook(
        EVENT_OBJECT_CREATE,
        EVENT_OBJECT_SHOW,
        nullptr,
        OnWindowEvent,
        0,
        0,
        WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    if (hook == nullptr) {
        return 1;
    }

    UINT_PTR timer = SetTimer(nullptr, 1, 1000, OnScanTimer);
    ScanExistingWindows();

    MSG message = {};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }

    if (timer != 0) {
        KillTimer(nullptr, timer);
    }
    UnhookWinEvent(hook);
    return 0;
}
