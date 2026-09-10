// UTF-16 Windows process launcher with an owned, kill-on-close job.
// YaneuraOu receives ASCII relative model paths in its own working directory.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

class EngineHost {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll")]
    static extern bool SetInformationJobObject(IntPtr job, int type, IntPtr data, uint length);
    [DllImport("kernel32.dll")]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);

    [StructLayout(LayoutKind.Sequential)]
    struct BasicLimits {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr MinimumWorkingSet, MaximumWorkingSet;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct IoCounters { public ulong ReadCount, WriteCount, OtherCount, ReadBytes, WriteBytes, OtherBytes; }
    [StructLayout(LayoutKind.Sequential)]
    struct ExtendedLimits {
        public BasicLimits Basic;
        public IoCounters Io;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }

    static int Main(string[] args) {
        if (args.Length != 1 || !File.Exists(args[0])) return 2;
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero) return 3;
        var limits = new ExtendedLimits();
        limits.Basic.Flags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        int bytes = Marshal.SizeOf(limits);
        IntPtr data = Marshal.AllocHGlobal(bytes);
        try {
            Marshal.StructureToPtr(limits, data, false);
            if (!SetInformationJobObject(job, 9, data, (uint)bytes)) return 4;
        } finally { Marshal.FreeHGlobal(data); }
        try {
            var start = new ProcessStartInfo(Path.GetFullPath(args[0]));
            start.WorkingDirectory = Path.GetDirectoryName(Path.GetFullPath(args[0]));
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.RedirectStandardInput = true;
            start.RedirectStandardOutput = true;
            start.RedirectStandardError = true;
            start.StandardOutputEncoding = Encoding.UTF8;
            start.StandardErrorEncoding = Encoding.UTF8;
            Console.InputEncoding = new UTF8Encoding(false);
            Console.OutputEncoding = new UTF8Encoding(false);
            using (var process = new Process()) {
                process.StartInfo = start;
                process.OutputDataReceived += (sender, e) => { if (e.Data != null) { Console.Out.WriteLine(e.Data); Console.Out.Flush(); } };
                process.ErrorDataReceived += (sender, e) => { if (e.Data != null) { Console.Error.WriteLine(e.Data); Console.Error.Flush(); } };
                process.Start();
                if (!AssignProcessToJobObject(job, process.Handle)) { process.Kill(); return 5; }
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
                var writer = new StreamWriter(process.StandardInput.BaseStream, new UTF8Encoding(false));
                writer.AutoFlush = true;
                var input = new Thread(() => {
                    try {
                        string line;
                        while ((line = Console.ReadLine()) != null && !process.HasExited) {
                            writer.WriteLine(line);
                        }
                        if (!process.HasExited) process.Kill();
                    } catch (InvalidOperationException) { }
                      catch (IOException) { }
                });
                input.IsBackground = true;
                input.Start();
                process.WaitForExit();
                return process.ExitCode;
            }
        } catch (Exception e) {
            Console.Error.WriteLine("EngineHost: " + e.Message);
            return 6;
        } finally { CloseHandle(job); }
    }
}
