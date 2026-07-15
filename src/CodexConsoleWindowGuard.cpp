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

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "shell32.lib")

struct ProcessInfo {
    DWORD parentProcessId;
    std::wstring executableName;
};

static bool g_exitAfterFirstMatch = false;

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

static bool HasCodexConsoleLauncherAncestry(
    const std::unordered_map<DWORD, ProcessInfo>& processes,
    DWORD processId) {
    bool hasConsoleLauncher = false;
    bool hasCodexDesktop = false;
    for (int depth = 0; depth < 64; depth++) {
        const auto iterator = processes.find(processId);
        if (iterator == processes.end()) {
            break;
        }

        const std::wstring& executableName = iterator->second.executableName;
        hasConsoleLauncher = hasConsoleLauncher || IsConsoleLauncherExecutable(executableName);
        hasCodexDesktop = hasCodexDesktop || IsCodexDesktopExecutable(executableName);
        if (hasConsoleLauncher && hasCodexDesktop) {
            return true;
        }

        DWORD parentProcessId = iterator->second.parentProcessId;
        if (parentProcessId == 0 || parentProcessId == processId) {
            break;
        }
        processId = parentProcessId;
    }

    return false;
}

static bool HasCodexConsoleLauncherAncestry(DWORD processId) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return false;
    }

    std::unordered_map<DWORD, ProcessInfo> processes;
    PROCESSENTRY32W entry = {};
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snapshot, &entry)) {
        do {
            processes.emplace(entry.th32ProcessID, ProcessInfo{
                entry.th32ParentProcessID,
                ToLower(entry.szExeFile),
            });
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);

    return HasCodexConsoleLauncherAncestry(processes, processId);
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
    if (GetClassNameW(window, className, 128) == 0 ||
        _wcsicmp(className, L"ConsoleWindowClass") != 0) {
        return;
    }

    DWORD processId = 0;
    GetWindowThreadProcessId(window, &processId);
    if (processId == 0 || !HasCodexConsoleLauncherAncestry(processId)) {
        return;
    }

    ShowWindow(window, SW_HIDE);
    if (g_exitAfterFirstMatch) {
        PostQuitMessage(0);
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

    return true;
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    if (HasArgument(L"--self-test-process-graph")) {
        return RunProcessGraphSelfTest() ? 0 : 1;
    }

    g_exitAfterFirstMatch = HasArgument(L"--once");
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

    MSG message = {};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }

    UnhookWinEvent(hook);
    return 0;
}
