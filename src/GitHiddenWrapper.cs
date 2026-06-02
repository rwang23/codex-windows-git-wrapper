using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

internal static class GitHiddenWrapper
{
    private const uint CreateNoWindow = 0x08000000;
    private const uint Infinite = 0xFFFFFFFF;
    private const int StartfUseStdHandles = 0x00000100;
    private const int StdInputHandle = -10;
    private const int StdOutputHandle = -11;
    private const int StdErrorHandle = -12;

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CreateProcessW(
        string lpApplicationName,
        StringBuilder lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetStdHandle(int nStdHandle);

    private static int Main(string[] args)
    {
        var realGit = ResolveRealGit();
        if (string.IsNullOrWhiteSpace(realGit) || !File.Exists(realGit))
        {
            SafeError("Real Git executable was not found. Set CODEX_REAL_GIT or reinstall the wrapper.");
            return 1;
        }

        var self = System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;
        if (string.Equals(Path.GetFullPath(realGit), Path.GetFullPath(self), StringComparison.OrdinalIgnoreCase))
        {
            SafeError("Refusing to launch the wrapper recursively. Check CODEX_REAL_GIT or real-git.txt.");
            return 1;
        }

        var commandLine = new StringBuilder(QuoteArg(realGit));
        if (args.Length > 0)
        {
            commandLine.Append(' ');
            commandLine.Append(QuoteArgs(args));
        }

        var startupInfo = new STARTUPINFO();
        startupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        startupInfo.dwFlags = StartfUseStdHandles;
        startupInfo.hStdInput = GetStdHandle(StdInputHandle);
        startupInfo.hStdOutput = GetStdHandle(StdOutputHandle);
        startupInfo.hStdError = GetStdHandle(StdErrorHandle);

        PROCESS_INFORMATION processInfo;
        if (!CreateProcessW(
            realGit,
            commandLine,
            IntPtr.Zero,
            IntPtr.Zero,
            true,
            CreateNoWindow,
            IntPtr.Zero,
            Environment.CurrentDirectory,
            ref startupInfo,
            out processInfo))
        {
            SafeError(new Win32Exception(Marshal.GetLastWin32Error()).Message);
            return 1;
        }

        try
        {
            WaitForSingleObject(processInfo.hProcess, Infinite);
            uint exitCode;
            if (!GetExitCodeProcess(processInfo.hProcess, out exitCode))
            {
                return 1;
            }

            return unchecked((int)exitCode);
        }
        finally
        {
            CloseHandle(processInfo.hThread);
            CloseHandle(processInfo.hProcess);
        }
    }

    private static string ResolveRealGit()
    {
        var fromEnv = Environment.GetEnvironmentVariable("CODEX_REAL_GIT");
        if (!string.IsNullOrWhiteSpace(fromEnv))
        {
            return fromEnv.Trim();
        }

        var configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "real-git.txt");
        if (File.Exists(configPath))
        {
            var configured = File.ReadAllText(configPath).Trim();
            if (!string.IsNullOrWhiteSpace(configured))
            {
                return configured;
            }
        }

        foreach (var candidate in new[]
        {
            @"C:\Program Files\Git\cmd\git.exe",
            @"C:\Program Files\Git\bin\git.exe",
            @"C:\Program Files (x86)\Git\cmd\git.exe",
            @"C:\Program Files (x86)\Git\bin\git.exe"
        })
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

    private static void SafeError(string message)
    {
        try
        {
            Console.Error.WriteLine(message);
        }
        catch
        {
        }
    }

    private static string QuoteArgs(string[] args)
    {
        var builder = new StringBuilder();
        for (var i = 0; i < args.Length; i++)
        {
            if (i > 0)
            {
                builder.Append(' ');
            }
            builder.Append(QuoteArg(args[i]));
        }
        return builder.ToString();
    }

    private static string QuoteArg(string arg)
    {
        if (arg.Length == 0)
        {
            return "\"\"";
        }

        if (arg.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0)
        {
            return arg;
        }

        var builder = new StringBuilder();
        builder.Append('"');
        var backslashes = 0;

        foreach (var character in arg)
        {
            if (character == '\\')
            {
                backslashes++;
                continue;
            }

            if (character == '"')
            {
                builder.Append('\\', backslashes * 2 + 1);
                builder.Append('"');
            }
            else
            {
                builder.Append('\\', backslashes);
                builder.Append(character);
            }
            backslashes = 0;
        }

        builder.Append('\\', backslashes * 2);
        builder.Append('"');
        return builder.ToString();
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct STARTUPINFO
    {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_INFORMATION
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }
}

