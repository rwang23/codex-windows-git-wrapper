#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <shellapi.h>

#include <cwctype>
#include <string>
#include <vector>

static std::wstring GetExeDirectory() {
    std::vector<wchar_t> buffer(MAX_PATH);
    DWORD length = 0;

    for (;;) {
        length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
        if (length == 0) {
            return L"";
        }
        if (length < buffer.size() - 1) {
            break;
        }
        buffer.resize(buffer.size() * 2);
    }

    std::wstring path(buffer.data(), length);
    size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) {
        return L"";
    }
    return path.substr(0, slash);
}

static bool FileExists(const std::wstring& path) {
    DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY);
}

static bool DirectoryExists(const std::wstring& path) {
    DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY);
}

static std::wstring Trim(const std::wstring& value) {
    const wchar_t* whitespace = L" \t\r\n";
    size_t first = value.find_first_not_of(whitespace);
    if (first == std::wstring::npos) {
        return L"";
    }
    size_t last = value.find_last_not_of(whitespace);
    return value.substr(first, last - first + 1);
}

static std::wstring ReadTextFile(const std::wstring& path) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return L"";
    }

    LARGE_INTEGER size;
    if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 || size.QuadPart > 32768) {
        CloseHandle(file);
        return L"";
    }

    std::string bytes(static_cast<size_t>(size.QuadPart), '\0');
    DWORD read = 0;
    BOOL ok = ReadFile(file, &bytes[0], static_cast<DWORD>(bytes.size()), &read, nullptr);
    CloseHandle(file);
    if (!ok) {
        return L"";
    }
    bytes.resize(read);

    int wideLength = MultiByteToWideChar(CP_UTF8, 0, bytes.data(), static_cast<int>(bytes.size()), nullptr, 0);
    if (wideLength <= 0) {
        wideLength = MultiByteToWideChar(CP_ACP, 0, bytes.data(), static_cast<int>(bytes.size()), nullptr, 0);
        if (wideLength <= 0) {
            return L"";
        }
        std::wstring wide(wideLength, L'\0');
        MultiByteToWideChar(CP_ACP, 0, bytes.data(), static_cast<int>(bytes.size()), &wide[0], wideLength);
        return Trim(wide);
    }

    std::wstring wide(wideLength, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, bytes.data(), static_cast<int>(bytes.size()), &wide[0], wideLength);
    return Trim(wide);
}

static std::wstring GetEnvironmentString(const wchar_t* name) {
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
    return Trim(value);
}

static std::wstring ResolveConfiguredTempDirectory() {
    std::wstring fromEnvironment = GetEnvironmentString(L"CODEX_TEMP_DIR");
    if (!fromEnvironment.empty() && DirectoryExists(fromEnvironment)) {
        return fromEnvironment;
    }

    std::wstring exeDir = GetExeDirectory();
    if (!exeDir.empty()) {
        std::wstring configured = ReadTextFile(exeDir + L"\\codex-temp-dir.txt");
        if (!configured.empty() && DirectoryExists(configured)) {
            return configured;
        }
    }

    return L"";
}

static void ApplyConfiguredTempDirectory() {
    std::wstring configured = ResolveConfiguredTempDirectory();
    if (configured.empty()) {
        return;
    }

    SetEnvironmentVariableW(L"TEMP", configured.c_str());
    SetEnvironmentVariableW(L"TMP", configured.c_str());
}

struct TargetConfig {
    std::wstring displayName;
    std::wstring environmentVariable;
    std::wstring configFile;
    std::vector<std::wstring> candidates;
};

static std::wstring GetExeBaseName() {
    std::vector<wchar_t> buffer(MAX_PATH);
    DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) {
        return L"";
    }
    std::wstring path(buffer.data(), length);
    size_t slash = path.find_last_of(L"\\/");
    std::wstring name = slash == std::wstring::npos ? path : path.substr(slash + 1);
    for (wchar_t& ch : name) {
        ch = static_cast<wchar_t>(towlower(ch));
    }
    return name;
}

static TargetConfig GetTargetConfig() {
    std::wstring exeBaseName = GetExeBaseName();
    if (exeBaseName == L"powershell.exe") {
        wchar_t windowsDirectory[MAX_PATH] = {};
        GetWindowsDirectoryW(windowsDirectory, MAX_PATH);
        std::wstring systemPowerShell = std::wstring(windowsDirectory) + L"\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
        return {L"PowerShell", L"CODEX_REAL_POWERSHELL", L"real-powershell.txt", {systemPowerShell}};
    }

    if (exeBaseName == L"cmd.exe") {
        wchar_t windowsDirectory[MAX_PATH] = {};
        GetWindowsDirectoryW(windowsDirectory, MAX_PATH);
        std::wstring systemCmd = std::wstring(windowsDirectory) + L"\\System32\\cmd.exe";
        return {L"Command Prompt", L"CODEX_REAL_CMD", L"real-cmd.txt", {systemCmd}};
    }

    return {
        L"Git",
        L"CODEX_REAL_GIT",
        L"real-git.txt",
        {
            L"C:\\Program Files\\Git\\mingw64\\bin\\git.exe",
            L"C:\\Program Files\\Git\\cmd\\git.exe",
            L"C:\\Program Files\\Git\\bin\\git.exe",
            L"C:\\Program Files (x86)\\Git\\mingw64\\bin\\git.exe",
            L"C:\\Program Files (x86)\\Git\\cmd\\git.exe",
            L"C:\\Program Files (x86)\\Git\\bin\\git.exe",
        },
    };
}

static bool ShouldSuppressProcessSampling(const TargetConfig& target, const std::wstring& commandLine) {
    if (target.displayName != L"PowerShell") {
        return false;
    }

    std::wstring enabled = GetEnvironmentString(L"CODEX_WRAPPER_SUPPRESS_PROCESS_SAMPLING");
    if (enabled != L"1" && enabled != L"true") {
        return false;
    }

    bool isProcessQuery = commandLine.find(L"Get-CimInstance Win32_Process") != std::wstring::npos;
    bool isJsonOutput = commandLine.find(L"ConvertTo-Json") != std::wstring::npos;
    bool isKnownSampler =
        commandLine.find(L"Select-Object ProcessId,ParentProcessId") != std::wstring::npos ||
        commandLine.find(L"Win32_PerfFormattedData_PerfProc_Process") != std::wstring::npos;
    return isProcessQuery && isJsonOutput && isKnownSampler;
}

static void WriteStdoutUtf8(const std::string& value) {
    HANDLE outputHandle = GetStdHandle(STD_OUTPUT_HANDLE);
    if (outputHandle == INVALID_HANDLE_VALUE || outputHandle == nullptr) {
        return;
    }
    DWORD written = 0;
    WriteFile(outputHandle, value.data(), static_cast<DWORD>(value.size()), &written, nullptr);
}

static std::wstring ResolveRealExecutable(const TargetConfig& target) {
    std::wstring fromEnv = GetEnvironmentString(target.environmentVariable.c_str());
    if (!fromEnv.empty() && FileExists(fromEnv)) {
        return fromEnv;
    }

    std::wstring exeDir = GetExeDirectory();
    if (!exeDir.empty()) {
        std::wstring configured = ReadTextFile(exeDir + L"\\" + target.configFile);
        if (!configured.empty() && FileExists(configured)) {
            return configured;
        }
    }

    for (const std::wstring& candidate : target.candidates) {
        if (FileExists(candidate)) {
            return candidate;
        }
    }

    return L"";
}

static std::wstring QuoteArg(const std::wstring& arg) {
    if (arg.empty()) {
        return L"\"\"";
    }

    if (arg.find_first_of(L" \t\n\v\"") == std::wstring::npos) {
        return arg;
    }

    std::wstring result = L"\"";
    int backslashes = 0;

    for (wchar_t ch : arg) {
        if (ch == L'\\') {
            backslashes++;
            continue;
        }

        if (ch == L'"') {
            result.append(backslashes * 2 + 1, L'\\');
            result.push_back(L'"');
        } else {
            result.append(backslashes, L'\\');
            result.push_back(ch);
        }
        backslashes = 0;
    }

    result.append(backslashes * 2, L'\\');
    result.push_back(L'"');
    return result;
}

static void WriteStderr(const std::wstring& message) {
    HANDLE errorHandle = GetStdHandle(STD_ERROR_HANDLE);
    if (errorHandle == INVALID_HANDLE_VALUE || errorHandle == nullptr) {
        return;
    }

    DWORD written = 0;
    std::wstring line = message + L"\r\n";
    WriteConsoleW(errorHandle, line.c_str(), static_cast<DWORD>(line.size()), &written, nullptr);
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR commandLine, int) {
    TargetConfig target = GetTargetConfig();
    std::wstring rawCommandLine = commandLine == nullptr ? L"" : commandLine;
    if (ShouldSuppressProcessSampling(target, rawCommandLine)) {
        WriteStdoutUtf8("[]\r\n");
        return 0;
    }

    std::wstring realExecutable = ResolveRealExecutable(target);
    if (realExecutable.empty()) {
        WriteStderr(L"Real " + target.displayName + L" executable was not found. Reinstall the wrapper.");
        return 1;
    }

    ApplyConfiguredTempDirectory();

    std::wstring fullCommandLine = QuoteArg(realExecutable);
    if (commandLine != nullptr && commandLine[0] != L'\0') {
        fullCommandLine += L" ";
        fullCommandLine += commandLine;
    }

    STARTUPINFOW startupInfo = {};
    startupInfo.cb = sizeof(startupInfo);
    startupInfo.dwFlags = STARTF_USESTDHANDLES;
    startupInfo.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startupInfo.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    startupInfo.hStdError = GetStdHandle(STD_ERROR_HANDLE);

    PROCESS_INFORMATION processInfo = {};
    std::vector<wchar_t> mutableCommandLine(fullCommandLine.begin(), fullCommandLine.end());
    mutableCommandLine.push_back(L'\0');

    BOOL created = CreateProcessW(
        realExecutable.c_str(),
        mutableCommandLine.data(),
        nullptr,
        nullptr,
        TRUE,
        CREATE_NO_WINDOW,
        nullptr,
        nullptr,
        &startupInfo,
        &processInfo);

    if (!created) {
        WriteStderr(L"Failed to start real " + target.displayName + L".");
        return 1;
    }

    WaitForSingleObject(processInfo.hProcess, INFINITE);

    DWORD exitCode = 1;
    GetExitCodeProcess(processInfo.hProcess, &exitCode);

    CloseHandle(processInfo.hThread);
    CloseHandle(processInfo.hProcess);

    return static_cast<int>(exitCode);
}
