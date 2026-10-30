# System volume bridge for RONIN Island (Windows PowerShell 5.1, Core Audio IAudioEndpointVolume).
# Prints one JSON line {ok, level 0-100, muted} per second and right after every command.
# Commands on stdin: get | set <0-100> | step <+-n> | mute <0|1> | togglemute
# Same Core Audio approach as ronin-guard/helper.ps1; the full vtable up to GetMute is declared here.
$ErrorActionPreference = "SilentlyContinue"
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IIslandEndpointVolume {
  int RegisterControlChangeNotify(IntPtr p);
  int UnregisterControlChangeNotify(IntPtr p);
  int GetChannelCount(out int c);
  int SetMasterVolumeLevel(float l, ref Guid g);
  int SetMasterVolumeLevelScalar(float l, ref Guid g);
  int GetMasterVolumeLevel(out float l);
  int GetMasterVolumeLevelScalar(out float l);
  int SetChannelVolumeLevel(uint ch, float l, ref Guid g);
  int SetChannelVolumeLevelScalar(uint ch, float l, ref Guid g);
  int GetChannelVolumeLevel(uint ch, out float l);
  int GetChannelVolumeLevelScalar(uint ch, out float l);
  int SetMute([MarshalAs(UnmanagedType.Bool)] bool m, ref Guid g);
  int GetMute([MarshalAs(UnmanagedType.Bool)] out bool m);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IIslandMMDevice {
  int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
}
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IIslandMMDeviceEnumerator {
  int EnumAudioEndpoints(int flow, int mask, out IntPtr devices);
  int GetDefaultAudioEndpoint(int flow, int role, out IIslandMMDevice d);
}
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class IslandMMDeviceEnumerator {}

// Console.In.ReadLineAsync() blocks synchronously on Windows PowerShell 5.1, so stdin is read on a background thread.
public static class IslandStdin {
  public static readonly System.Collections.Concurrent.ConcurrentQueue<string> Q = new System.Collections.Concurrent.ConcurrentQueue<string>();
  public static volatile bool Eof = false;
  public static void Start() {
    var t = new System.Threading.Thread(() => { string l; while ((l = Console.In.ReadLine()) != null) Q.Enqueue(l); Eof = true; });
    t.IsBackground = true; t.Start();
  }
}

public static class IslandVol {
  // Re-resolve the default render endpoint on every call so a headphone/speaker switch is followed.
  static IIslandEndpointVolume Ep() {
    var en = (IIslandMMDeviceEnumerator)(new IslandMMDeviceEnumerator());
    IIslandMMDevice dev; en.GetDefaultAudioEndpoint(0, 1, out dev);
    Guid iid = typeof(IIslandEndpointVolume).GUID; object o;
    dev.Activate(ref iid, 23, IntPtr.Zero, out o);
    return (IIslandEndpointVolume)o;
  }
  public static string Get() {
    try {
      var v = Ep(); float l; bool m;
      v.GetMasterVolumeLevelScalar(out l); v.GetMute(out m);
      return "{\"ok\":true,\"level\":" + (int)Math.Round(l * 100) + ",\"muted\":" + (m ? "true" : "false") + "}";
    } catch (Exception) { return "{\"ok\":false}"; }
  }
  public static void Set(int pct) {
    try { var v = Ep(); Guid z = Guid.Empty; v.SetMasterVolumeLevelScalar(Math.Max(0, Math.Min(100, pct)) / 100f, ref z); } catch (Exception) {}
  }
  public static void Step(int d) {
    try { var v = Ep(); float l; v.GetMasterVolumeLevelScalar(out l); Set((int)Math.Round(l * 100) + d); } catch (Exception) {}
  }
  public static void Mute(bool m) {
    try { var v = Ep(); Guid z = Guid.Empty; v.SetMute(m, ref z); } catch (Exception) {}
  }
  public static void ToggleMute() {
    try { var v = Ep(); bool m; v.GetMute(out m); Mute(!m); } catch (Exception) {}
  }
}
"@

[IslandStdin]::Start()
$lastOut = [DateTime]::MinValue
while ($true) {
  $did = $false
  $cmd = $null
  while ([IslandStdin]::Q.TryDequeue([ref]$cmd)) {
    $p = $cmd.Trim() -split '\s+'
    switch ($p[0]) {
      "set"        { [IslandVol]::Set([int]$p[1]) }
      "step"       { [IslandVol]::Step([int]$p[1]) }
      "mute"       { [IslandVol]::Mute($p[1] -eq "1") }
      "togglemute" { [IslandVol]::ToggleMute() }
    }
    $did = $true
  }
  if ([IslandStdin]::Eof -and [IslandStdin]::Q.IsEmpty) { [Console]::Out.WriteLine([IslandVol]::Get()); [Console]::Out.Flush(); exit 0 }
  if ($did -or ([DateTime]::Now - $lastOut).TotalMilliseconds -ge 1000) {
    [Console]::Out.WriteLine([IslandVol]::Get())
    [Console]::Out.Flush()
    $lastOut = [DateTime]::Now
  }
  Start-Sleep -Milliseconds 60
}
