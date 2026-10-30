# Windows media session bridge for RONIN Island (Windows PowerShell 5.1, WinRT).
# Prints one JSON line per second with the current track; reads commands from stdin: toggle | next | prev.
$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, [Type]$t) { $task = $asTaskGeneric.MakeGenericMethod($t).Invoke($null, @($op)); $task.Wait(-1) | Out-Null; $task.Result }
[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime] | Out-Null
$mgr = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])

# Console.In.ReadLineAsync() blocks synchronously on Windows PowerShell 5.1 (the old loop printed nothing until a
# command arrived), so stdin is read on a background thread into a queue.
Add-Type -TypeDefinition @"
public static class IslandMediaStdin {
  public static readonly System.Collections.Concurrent.ConcurrentQueue<string> Q = new System.Collections.Concurrent.ConcurrentQueue<string>();
  public static volatile bool Eof = false;
  public static void Start() {
    var t = new System.Threading.Thread(() => { string l; while ((l = System.Console.In.ReadLine()) != null) Q.Enqueue(l); Eof = true; });
    t.IsBackground = true; t.Start();
  }
}
"@
[IslandMediaStdin]::Start()
while ($true) {
  $s = $mgr.GetCurrentSession()
  $cmd = $null
  if ([IslandMediaStdin]::Q.TryDequeue([ref]$cmd)) {
    if ($s) {
      switch ($cmd.Trim()) {
        "toggle" { Await ($s.TryTogglePlayPauseAsync()) ([bool]) | Out-Null }
        "next"   { Await ($s.TrySkipNextAsync()) ([bool]) | Out-Null }
        "prev"   { Await ($s.TrySkipPreviousAsync()) ([bool]) | Out-Null }
      }
    }
    Start-Sleep -Milliseconds 250
    $s = $mgr.GetCurrentSession()
  } elseif ([IslandMediaStdin]::Eof) { break }
  $out = @{ ok = $false }
  if ($s) {
    $p = Await ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
    $info = $s.GetPlaybackInfo()
    $out = @{ ok = $true; title = $p.Title; artist = $p.Artist; app = $s.SourceAppUserModelId; playing = ($info.PlaybackStatus.ToString() -eq "Playing") }
  }
  [Console]::Out.WriteLine(($out | ConvertTo-Json -Compress))
  [Console]::Out.Flush()
  Start-Sleep -Milliseconds 1000
}
