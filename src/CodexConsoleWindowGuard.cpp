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

static bool HasCodexGitAncestry(DWORD processId) {
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

    bool hasGit = false;
    bool hasCodexDesktop = false;
    for (int depth = 0; depth < 64; depth++) {
        const auto iterator = processes.find(processId);
        if (iterator == processes.end()) {
            break;
        }

        const std::wstring& executableName = iterator->second.executableName;
        hasGit = hasGit || executableName == L"git.exe";
        hasCodexDesktop = hasCodexDesktop ||
            executableName == L"chatgpt.exe" ||
            executableName == L"codex.exe";
        if (hasGit && hasCodexDesktop) {
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
    if (processId == 0 || !HasCodexGitAncestry(processId)) {
        return;
    }

    ShowWindow(window, SW_HIDE);
    if (g_exitAfterFirstMatch) {
        PostQuitMessage(0);
    }
}

static bool HasOnceArgument() {
    int argumentCount = 0;
    LPWSTR* arguments = CommandLineToArgvW(GetCommandLineW(), &argumentCount);
    if (arguments == nullptr) {
        return false;
    }

    bool result = false;
    for (int index = 1; index < argumentCount; index++) {
        if (_wcsicmp(arguments[index], L"--once") == 0) {
            result = true;
            break;
        }
    }
    LocalFree(arguments);
    return result;
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    g_exitAfterFirstMatch = HasOnceArgument();
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
