# RONIN Guard helper: reports lid open/close ("lid 0" / "lid 1") on stdout and
# turns the system volume to 100 % unmuted when it reads "max" on stdin.
# Windows PowerShell 5.1 (needs WinForms for the message loop).
Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System;
using System.Threading;
using System.Windows.Forms;
using System.Runtime.InteropServices;

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
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
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
  int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
}
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
  int EnumAudioEndpoints(int flow, int mask, out IntPtr devices);
  int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice d);
}
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}

public static class GuardVol {
  public static void Max() {
    try {
      var en = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
      IMMDevice dev; en.GetDefaultAudioEndpoint(0, 1, out dev);
      Guid iid = typeof(IAudioEndpointVolume).GUID; object o;
      dev.Activate(ref iid, 23, IntPtr.Zero, out o);
      var v = (IAudioEndpointVolume)o; Guid z = Guid.Empty;
      v.SetMute(false, ref z); v.SetMasterVolumeLevelScalar(1.0f, ref z);
    } catch (Exception e) { Console.WriteLine("err volume " + e.Message); Console.Out.Flush(); }
  }
}

public class GuardLid : NativeWindow {
  [DllImport("user32.dll")] static extern IntPtr RegisterPowerSettingNotification(IntPtr h, ref Guid g, int flags);
  static Guid LID = new Guid("BA3E0F4D-B817-4094-A2D1-D56379E6A0F3");
  public GuardLid() { CreateHandle(new CreateParams()); RegisterPowerSettingNotification(Handle, ref LID, 0); }
  protected override void WndProc(ref Message m) {
    // WM_POWERBROADCAST / PBT_POWERSETTINGCHANGE; POWERBROADCAST_SETTING = Guid(16) + DataLength(4) + Data
    if (m.Msg == 0x218 && m.WParam.ToInt64() == 0x8013) {
      Console.WriteLine("lid " + Marshal.ReadByte(m.LParam, 20)); Console.Out.Flush();
    }
    base.WndProc(ref m);
  }
  public static void ReadStdin() {
    var t = new Thread(() => { string line; while ((line = Console.In.ReadLine()) != null) { if (line.Trim() == "max") GuardVol.Max(); } Application.Exit(); });
    t.IsBackground = true; t.Start();
  }
}
"@
$w = New-Object GuardLid
[GuardLid]::ReadStdin()
"ready"
[System.Windows.Forms.Application]::Run()
