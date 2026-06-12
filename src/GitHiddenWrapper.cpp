#define UNICODE
#define _UNICODE

#include <windows.h>
#include <shellapi.h>

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
    BOOL ok = ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr);
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
        MultiByteToWideChar(CP_ACP, 0, bytes.data(), static_cast<int>(bytes.size()), wide.data(), wideLength);
        return Trim(wide);
    }

    std::wstring wide(wideLength, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, bytes.data(), static_cast<int>(bytes.size()), wide.data(), wideLength);
    return Trim(wide);
}

static std::wstring GetEnvironmentString(const wchar_t* name) {
    DWORD length = GetEnvironmentVariableW(name, nullptr, 0);
    if (length == 0) {
        return L"";
    }
    std::wstring value(length, L'\0');
    DWORD copied = GetEnvironmentVariableW(name, value.data(), length);
    if (copied == 0 || copied >= length) {
        return L"";
    }
    value.resize(copied);
    return Trim(value);
}

static std::wstring ResolveRealGit() {
    std::wstring fromEnv = GetEnvironmentString(L"CODEX_REAL_GIT");
    if (!fromEnv.empty() && FileExists(fromEnv)) {
        return fromEnv;
    }

    std::wstring exeDir = GetExeDirectory();
    if (!exeDir.empty()) {
        std::wstring configured = ReadTextFile(exeDir + L"\\real-git.txt");
        if (!configured.empty() && FileExists(configured)) {
            return configured;
        }
    }

    const wchar_t* candidates[] = {
        L"C:\\Program Files\\Git\\cmd\\git.exe",
        L"C:\\Program Files\\Git\\bin\\git.exe",
        L"C:\\Program Files (x86)\\Git\\cmd\\git.exe",
        L"C:\\Program Files (x86)\\Git\\bin\\git.exe",
    };

    for (const wchar_t* candidate : candidates) {
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
    std::wstring realGit = ResolveRealGit();
    if (realGit.empty()) {
        WriteStderr(L"Real Git executable was not found. Set CODEX_REAL_GIT or reinstall the wrapper.");
        return 1;
    }

    std::wstring fullCommandLine = QuoteArg(realGit);
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
        realGit.c_str(),
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
        WriteStderr(L"Failed to start real Git.");
        return 1;
    }

    WaitForSingleObject(processInfo.hProcess, INFINITE);

    DWORD exitCode = 1;
    GetExitCodeProcess(processInfo.hProcess, &exitCode);

    CloseHandle(processInfo.hThread);
    CloseHandle(processInfo.hProcess);

    return static_cast<int>(exitCode);
}
