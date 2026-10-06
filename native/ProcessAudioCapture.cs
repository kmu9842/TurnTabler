using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace TurnTabler;

// Windows process-loopback captures the actual WebView2 audio service, rather
// than the WPF window. No device routing or global desktop capture is involved.
public sealed class ProcessAudioCapture : IDisposable
{
    private readonly CancellationTokenSource stop = new();
    private readonly Thread thread;
    internal ProcessAudioCapture(int processId, Action<byte[]> samples, Action<string> error)
    {
        thread = new Thread(() => Run(processId, samples, error)) { IsBackground = true, Name = "TurnTabler audio capture" };
        thread.SetApartmentState(ApartmentState.MTA); thread.Start();
    }
    private void Run(int processId, Action<byte[]> samples, Action<string> error)
    {
        IAudioClient? client = null; IAudioCaptureClient? capture = null;
        IntPtr parameters = Marshal.AllocCoTaskMem(12);
        using var ready = new AutoResetEvent(false);
        CoInitializeEx(IntPtr.Zero, 0);
        try
        {
            // AUDIOCLIENT_ACTIVATION_PARAMS: PROCESS_LOOPBACK, PID, INCLUDE_TREE.
            Marshal.WriteInt32(parameters, 0, 1); Marshal.WriteInt32(parameters, 4, processId); Marshal.WriteInt32(parameters, 8, 0);
            var variant = new PropVariant { Type = 65, Size = 12, Data = parameters };
            using var callback = new Activation();
            Guid iid = typeof(IAudioClient).GUID;
            Check(ActivateAudioInterfaceAsync("VAD\\Process_Loopback", ref iid, ref variant, callback, out var operation));
            if (!callback.Ready.Wait(5000)) throw new TimeoutException("오디오 캡처 초기화 시간 초과");
            Check(callback.Result); client = (IAudioClient)callback.Client!;
            Marshal.ReleaseComObject(operation);
            var format = new WaveFormat { Format = 1, Channels = 2, Rate = 48000, BytesPerSecond = 192000, BlockAlign = 4, Bits = 16 };
            Check(client.Initialize(0, 0x80000000 | 0x00020000 | 0x00040000, 10000000, 0, ref format, IntPtr.Zero));
            Check(client.GetBufferSize(out _));
            Guid captureId = typeof(IAudioCaptureClient).GUID;
            Check(client.GetService(ref captureId, out object service)); capture = (IAudioCaptureClient)service;
            Check(client.SetEventHandle(ready.SafeWaitHandle.DangerousGetHandle())); Check(client.Start());
            while (!stop.IsCancellationRequested)
            {
                ready.WaitOne(30);
                Check(capture.GetNextPacketSize(out uint count));
                while (count > 0)
                {
                    Check(capture.GetBuffer(out IntPtr data, out uint frames, out uint flags, out _, out _));
                    var bytes = new byte[checked((int)frames * 4)];
                    if ((flags & 2) == 0) Marshal.Copy(data, bytes, 0, bytes.Length);
                    Check(capture.ReleaseBuffer(frames)); samples(bytes);
                    Check(capture.GetNextPacketSize(out count));
                }
            }
        }
        catch (Exception exception) { if (!stop.IsCancellationRequested) error(exception.ToString()); }
        finally
        {
            if (client != null) { client.Stop(); Marshal.ReleaseComObject(client); }
            if (capture != null) Marshal.ReleaseComObject(capture);
            Marshal.FreeCoTaskMem(parameters);
            CoUninitialize();
        }
    }
    private static void Check(int result) { if (result < 0) Marshal.ThrowExceptionForHR(result); }
    public void Dispose() { stop.Cancel(); if (Thread.CurrentThread != thread) thread.Join(1500); }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    private struct PropVariant { [FieldOffset(0)] public ushort Type; [FieldOffset(8)] public int Size; [FieldOffset(16)] public IntPtr Data; }
    [StructLayout(LayoutKind.Sequential, Pack = 2)]
    private struct WaveFormat { public ushort Format, Channels; public uint Rate, BytesPerSecond; public ushort BlockAlign, Bits, Extra; }
    [DllImport("Mmdevapi.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
    private static extern int ActivateAudioInterfaceAsync(string path, ref Guid iid, ref PropVariant parameters, IActivationHandler handler, out IActivationOperation operation);
    [DllImport("ole32.dll")] private static extern int CoInitializeEx(IntPtr reserved, uint mode);
    [DllImport("ole32.dll")] private static extern void CoUninitialize();
    [DllImport("ole32.dll")] private static extern int CoCreateFreeThreadedMarshaler(IntPtr outer, out IntPtr marshaler);
    [ComVisible(true), Guid("41D949AB-9862-444A-80F6-C261334DA5EB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IActivationHandler { [PreserveSig] int ActivateCompleted(IActivationOperation operation); }
    [ComImport, Guid("72A22D78-CDE4-431D-B8CC-843A71199B6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IActivationOperation { [PreserveSig] int GetActivateResult(out int result, [MarshalAs(UnmanagedType.IUnknown)] out object client); }
    [ComVisible(true), Guid("94EA2B94-E9CC-49E0-C0FF-EE64CA8F5B90"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAgileObject { }
    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    public sealed class Activation : IActivationHandler, IAgileObject, ICustomQueryInterface, IDisposable
    {
        private IntPtr marshaler;
        public Activation() { Check(CoCreateFreeThreadedMarshaler(IntPtr.Zero, out marshaler)); }
        public CustomQueryInterfaceResult GetInterface(ref Guid iid, out IntPtr pointer)
        {
            pointer = IntPtr.Zero;
            if (iid != new Guid("00000003-0000-0000-C000-000000000046") || marshaler == IntPtr.Zero) return CustomQueryInterfaceResult.NotHandled;
            return Marshal.QueryInterface(marshaler, ref iid, out pointer) == 0 ? CustomQueryInterfaceResult.Handled : CustomQueryInterfaceResult.Failed;
        }
        public void Dispose() { if (marshaler != IntPtr.Zero) { Marshal.Release(marshaler); marshaler = IntPtr.Zero; } Ready.Dispose(); }
        public readonly ManualResetEventSlim Ready = new();
        public int Result; public object? Client;
        public int ActivateCompleted(IActivationOperation operation)
        {
            int hr = operation.GetActivateResult(out int result, out object client);
            Result = hr < 0 ? hr : result; Client = client; Ready.Set(); return 0;
        }
    }
    [ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioClient
    {
        [PreserveSig] int Initialize(int mode, uint flags, long duration, long periodicity, ref WaveFormat format, IntPtr session);
        [PreserveSig] int GetBufferSize(out uint frames);
        [PreserveSig] int GetStreamLatency(out long latency);
        [PreserveSig] int GetCurrentPadding(out uint frames);
        [PreserveSig] int IsFormatSupported(int mode, IntPtr format, out IntPtr closest);
        [PreserveSig] int GetMixFormat(out IntPtr format);
        [PreserveSig] int GetDevicePeriod(out long normal, out long minimum);
        [PreserveSig] int Start();
        [PreserveSig] int Stop();
        [PreserveSig] int Reset();
        [PreserveSig] int SetEventHandle(IntPtr handle);
        [PreserveSig] int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object service);
    }
    [ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioCaptureClient
    {
        [PreserveSig] int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong position, out ulong counter);
        [PreserveSig] int ReleaseBuffer(uint frames);
        [PreserveSig] int GetNextPacketSize(out uint frames);
    }
}
