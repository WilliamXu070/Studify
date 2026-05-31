param(
    [int]$RemoteDebugPort = 9223,
    [string]$Expression
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Net.Http

Add-Type @"
using System;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public static class SpotXLabCdp {
    public static string Eval(string webSocketUrl, string expression) {
        using (var socket = new ClientWebSocket()) {
            socket.ConnectAsync(new Uri(webSocketUrl), CancellationToken.None).GetAwaiter().GetResult();
            var payload = "{\"id\":1,\"method\":\"Runtime.evaluate\",\"params\":{\"expression\":" + JsonString(expression) + ",\"returnByValue\":true}}";
            var bytes = Encoding.UTF8.GetBytes(payload);
            socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None).GetAwaiter().GetResult();

            var buffer = new byte[1024 * 1024];
            var builder = new StringBuilder();
            while (true) {
                var result = socket.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None).GetAwaiter().GetResult();
                if (result.MessageType == WebSocketMessageType.Close) break;
                builder.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));
                if (result.EndOfMessage) {
                    var text = builder.ToString();
                    if (text.Contains("\"id\":1")) return text;
                    builder.Clear();
                }
            }
        }
        return "";
    }

    private static string JsonString(string value) {
        var builder = new StringBuilder();
        builder.Append('"');
        foreach (var ch in value) {
            switch (ch) {
                case '\\': builder.Append("\\\\"); break;
                case '"': builder.Append("\\\""); break;
                case '\r': builder.Append("\\r"); break;
                case '\n': builder.Append("\\n"); break;
                case '\t': builder.Append("\\t"); break;
                default: builder.Append(ch); break;
            }
        }
        builder.Append('"');
        return builder.ToString();
    }
}
"@

$targets = Invoke-RestMethod -Uri "http://127.0.0.1:$RemoteDebugPort/json/list"
$target = @($targets | Where-Object {
    $_.type -eq 'page' -and $_.webSocketDebuggerUrl
} | Select-Object -First 1)[0]

if (-not $target) {
    throw "No Spotify DevTools page found on localhost:$RemoteDebugPort."
}

if (-not $Expression) {
    $Expression = @"
JSON.stringify({
  href: location.href,
  title: document.title,
  online: navigator.onLine,
  report: window.__spotxOfflineFixtureReport || null,
  fixtures: window.__spotxOfflineFixtures || null
})
"@
}

$raw = [SpotXLabCdp]::Eval($target.webSocketDebuggerUrl, $Expression)
$response = $raw | ConvertFrom-Json
$value = $response.result.result.value
if (-not $value) {
    $raw
    exit 0
}

$value | ConvertFrom-Json | ConvertTo-Json -Depth 20
