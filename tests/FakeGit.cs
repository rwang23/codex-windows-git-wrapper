using System;
using System.Runtime.InteropServices;
using System.Threading;

internal static class Program
{
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AllocConsole();

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeConsole();

    private static int Main()
    {
        if (!AllocConsole())
        {
            return Marshal.GetLastWin32Error();
        }

        Thread.Sleep(3000);
        FreeConsole();
        return 0;
    }
}
