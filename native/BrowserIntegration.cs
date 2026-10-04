using System;
using System.Buffers.Binary;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Security.Principal;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace TurnTabler;

// Desktop handoff for builds with browser integration. The optional Chrome
// package uses its independent host so existing released EXEs also work.
// Direct host invocations still hand off without creating WPF windows.
internal static class BrowserIntegration
{
    internal const string ExtensionId = "ebnjhkdpohpgeipkalbfklpfibjadnhd";
    internal const string Origin = "chrome-extension://" + ExtensionId + "/";
    internal const int MaximumMessageBytes = 16384;
    internal static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    internal sealed record Request(string Action, string? Url = null);
    internal sealed record Reply(bool Ok, string? Error = null, string? Url = null, int? ProcessId = null, int Protocol = 1);

    internal static string PipeName => "TurnTabler.Browser." + WindowsIdentity.GetCurrent().User!.Value + "." +
        Process.GetCurrentProcess().SessionId + (Program.BrowserSmoke ? ".BrowserSmoke" : Program.Smoke ? ".Smoke" : "");

    internal static Request Validate(Request request)
    {
        if (request.Action != "play") throw new ArgumentException("지원하지 않는 요청입니다.");
        if (string.IsNullOrWhiteSpace(request.Url) || request.Url.Length > 4096)
            throw new ArgumentException("영상 또는 재생목록 주소를 확인해 주세요.");
        return request with { Url = YouTubeAddress.Parse(request.Url).AbsoluteUri };
    }

    internal static async Task<T> Read<T>(Stream stream, CancellationToken cancellation = default)
    {
        var header = new byte[4];
        await stream.ReadExactlyAsync(header, cancellation);
        int length = BinaryPrimitives.ReadInt32LittleEndian(header);
        if (length <= 0 || length > MaximumMessageBytes) throw new InvalidDataException("잘못된 메시지 크기입니다.");
        var body = new byte[length];
        await stream.ReadExactlyAsync(body, cancellation);
        return JsonSerializer.Deserialize<T>(body, JsonOptions) ?? throw new InvalidDataException("요청이 비어 있습니다.");
    }

    internal static async Task Write<T>(Stream stream, T value, CancellationToken cancellation = default)
    {
        byte[] body = JsonSerializer.SerializeToUtf8Bytes(value, JsonOptions);
        if (body.Length > MaximumMessageBytes) throw new InvalidDataException("메시지가 너무 큽니다.");
        var header = new byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(header, body.Length);
        await stream.WriteAsync(header, cancellation);
        await stream.WriteAsync(body, cancellation);
        await stream.FlushAsync(cancellation);
    }

    // Null means no listener was reached. Never retry after a request was sent.
    internal static async Task<Reply?> TrySend(Request request, int connectTimeout, CancellationToken cancellation)
    {
        using var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.InOut, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        try { await pipe.ConnectAsync(connectTimeout, cancellation); }
        catch (TimeoutException) { return null; }
        await Write(pipe, request, cancellation);
        return await Read<Reply>(pipe, cancellation);
    }

    internal static async Task<int> RunHost(string origin)
    {
        using var output = Console.OpenStandardOutput();
        Reply reply;
        try
        {
            if (origin != Origin) throw new ArgumentException("허용되지 않은 확장 프로그램입니다.");
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(40));
            using var input = Console.OpenStandardInput();
            var request = await Read<Request>(input, timeout.Token);
            if (request.Action == "ping") reply = new Reply(true);
            else
            {
                request = Validate(request);
                Reply? received = await TrySend(request, 400, timeout.Token);
                if (received == null)
                {
                    var start = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = true };
                    // No message can set process arguments.
                    if (Program.BrowserSmoke) start.ArgumentList.Add("--browser-smoke");
                    using var launched = Process.Start(start) ?? throw new IOException("TurnTabler를 실행하지 못했습니다.");
                    while (received == null)
                    {
                        received = await TrySend(request, 500, timeout.Token);
                        if (received == null) await Task.Delay(100, timeout.Token);
                    }
                }
                reply = received;
            }
        }
        catch (OperationCanceledException) { reply = new Reply(false, "TurnTabler가 응답하지 않습니다. 이전 버전이 실행 중이면 종료하고 최신 EXE로 다시 연결해 주세요."); }
        catch (Exception error) { reply = new Reply(false, error.Message); }
        try { await Write(output, reply); return reply.Ok ? 0 : 1; }
        catch (IOException) { return 1; }
    }

    internal sealed class Listener : IDisposable
    {
        private readonly CancellationTokenSource stop = new();
        private readonly Task running;

        internal Listener(Func<string, Task> play) => running = Task.Run(() => Listen(play));

        private async Task Listen(Func<string, Task> play)
        {
            while (!stop.IsCancellationRequested)
            {
                using var pipe = new NamedPipeServerStream(PipeName, PipeDirection.InOut, 1,
                    PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                try
                {
                    await pipe.WaitForConnectionAsync(stop.Token);
                    using var timeout = CancellationTokenSource.CreateLinkedTokenSource(stop.Token);
                    timeout.CancelAfter(TimeSpan.FromSeconds(30));
                    Reply reply;
                    try
                    {
                        var request = Validate(await Read<Request>(pipe, timeout.Token));
                        await play(request.Url!).WaitAsync(timeout.Token);
                        reply = new Reply(true, Url: request.Url, ProcessId: Environment.ProcessId);
                    }
                    catch (Exception error) { reply = new Reply(false, error.Message); }
                    await Write(pipe, reply, timeout.Token);
                }
                catch (OperationCanceledException) { }
                catch (IOException) { }
                // Malformed or disconnected clients must not stop subsequent requests.
            }
        }

        public void Dispose()
        {
            stop.Cancel();
            try { running.GetAwaiter().GetResult(); }
            finally { stop.Dispose(); }
        }
    }
}
