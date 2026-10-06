using System;
using System.Collections.Concurrent;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;

namespace TurnTabler;

internal sealed class ObsAudioServer : IDisposable
{
    private readonly TcpListener listener;
    private readonly CancellationTokenSource stop = new();
    private readonly ConcurrentDictionary<TcpClient, Channel<byte[]>> clients = new();
    private readonly ProcessAudioCapture capture;
    private readonly string requestPath;
    internal string Url { get; }
    internal int Connections => clients.Count;
    internal bool IsRunning => disposed == 0;

    internal ObsAudioServer(int processId, int port, string token, Action<string> error)
    {
        requestPath = "/audio/" + token + ".wav";
        listener = new TcpListener(IPAddress.Loopback, port); listener.Start(4);
        Url = "http://127.0.0.1:" + ((IPEndPoint)listener.LocalEndpoint).Port + requestPath;
        capture = new ProcessAudioCapture(processId, bytes =>
        {
            foreach (var queue in clients.Values) queue.Writer.TryWrite(bytes);
        }, message => { error(message); Dispose(); });
        _ = Task.Run(Accept);
    }
    private async Task Accept()
    {
        try
        {
            while (!stop.IsCancellationRequested)
            {
                var client = await listener.AcceptTcpClientAsync(stop.Token);
                if (clients.Count >= 4) { client.Dispose(); continue; }
                _ = Serve(client);
            }
        }
        catch (OperationCanceledException) { }
        catch (SocketException) { }
    }
    private async Task Serve(TcpClient client)
    {
        var queue = Channel.CreateBounded<byte[]>(new BoundedChannelOptions(60) { FullMode = BoundedChannelFullMode.DropOldest, SingleReader = true, SingleWriter = true });
        try
        {
            using (client)
            {
                client.NoDelay = true;
                var stream = client.GetStream();
                using var handshake = CancellationTokenSource.CreateLinkedTokenSource(stop.Token);
                handshake.CancelAfter(5000);
                var header = new MemoryStream(); var one = new byte[1];
                while (header.Length < 4096)
                {
                    if (await stream.ReadAsync(one, handshake.Token) == 0) return;
                    header.WriteByte(one[0]);
                    if (header.Length >= 4 && Encoding.ASCII.GetString(header.GetBuffer(), (int)header.Length - 4, 4) == "\r\n\r\n") break;
                }
                string request = Encoding.ASCII.GetString(header.ToArray());
                if (!request.StartsWith("GET " + requestPath + " HTTP/1.", StringComparison.Ordinal))
                {
                    await stream.WriteAsync(Encoding.ASCII.GetBytes("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"), stop.Token); return;
                }
                await stream.WriteAsync(Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: audio/wav\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"), stop.Token);
                await stream.WriteAsync(WaveHeader(), stop.Token);
                clients.TryAdd(client, queue);
                await foreach (byte[] bytes in queue.Reader.ReadAllAsync(stop.Token))
                    await stream.WriteAsync(bytes, stop.Token);
            }
        }
        catch (IOException) { }
        catch (SocketException) { }
        catch (OperationCanceledException) { }
        catch (ObjectDisposedException) { }
        finally { clients.TryRemove(client, out _); queue.Writer.TryComplete(); client.Dispose(); }
    }
    private static byte[] WaveHeader()
    {
        using var data = new MemoryStream(); using var writer = new BinaryWriter(data);
        writer.Write(Encoding.ASCII.GetBytes("RIFF")); writer.Write(uint.MaxValue);
        writer.Write(Encoding.ASCII.GetBytes("WAVEfmt ")); writer.Write(16);
        writer.Write((short)1); writer.Write((short)2); writer.Write(48000); writer.Write(192000); writer.Write((short)4); writer.Write((short)16);
        writer.Write(Encoding.ASCII.GetBytes("data")); writer.Write(uint.MaxValue);
        return data.ToArray();
    }
    private int disposed;
    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0) return;
        stop.Cancel(); listener.Stop(); capture?.Dispose();
        foreach (var client in clients.Keys) client.Dispose();
    }
}
