using System;
using System.Diagnostics;
using System.Threading;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length != 1)
        {
            return 2;
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = args[0],
            UseShellExecute = false,
            CreateNoWindow = false,
        };

        using (var child = Process.Start(startInfo))
        {
            if (child == null)
            {
                return 3;
            }

            Thread.Sleep(3000);
            if (!child.HasExited)
            {
                child.Kill();
                child.WaitForExit();
            }
        }

        return 0;
    }
}
