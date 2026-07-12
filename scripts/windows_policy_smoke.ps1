param(
  [string]$ReleaseDirectory = "",
  [int]$StartupTimeoutSeconds = 30,
  [int]$ExitTimeoutSeconds = 30,
  [string]$ResultJson = ""
)

$ErrorActionPreference = "Stop"

function Assert-WindowsHost {
  if (-not ($IsWindows -or $env:OS -eq "Windows_NT")) {
    throw "Windows policy smoke tests can only run on Windows."
  }
}

function Wait-ForCondition {
  param([scriptblock]$Condition, [int]$TimeoutSeconds, [string]$Message)
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (& $Condition) { return }
    Start-Sleep -Milliseconds 200
  }
  throw $Message
}

function Assert-PathInside {
  param([string]$Path, [string]$ParentPath)
  $child = [IO.Path]::GetFullPath($Path)
  $parent = [IO.Path]::GetFullPath($ParentPath)
  if (-not $parent.EndsWith([IO.Path]::DirectorySeparatorChar)) {
    $parent += [IO.Path]::DirectorySeparatorChar
  }
  if ($child -eq $parent.TrimEnd([IO.Path]::DirectorySeparatorChar) -or
      -not $child.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use a policy smoke path outside the repository temp root."
  }
}

function Initialize-PolicyNative {
  if ("RePaperTodoPolicyNative" -as [type]) { return }
  Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class RePaperTodoPolicyNative {
  public delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct NOTIFYICONDATA {
    public uint cbSize; public IntPtr hWnd; public uint uID; public uint uFlags;
    public uint uCallbackMessage; public IntPtr hIcon;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
    public uint dwState, dwStateMask;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
    public uint uVersion;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
    public uint dwInfoFlags; public Guid guidItem; public IntPtr hBalloonIcon;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct NOTIFYICONIDENTIFIER {
    public uint cbSize; public IntPtr hWnd; public uint uID; public Guid guidItem;
  }

  [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out RECT bounds);
  [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
  [DllImport("user32.dll")] static extern uint RegisterWindowMessage(string name);
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action, uint parameter, out RECT bounds, uint flags);
  [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern bool Shell_NotifyIcon(uint message, ref NOTIFYICONDATA data);
  [DllImport("shell32.dll")] static extern int Shell_NotifyIconGetRect(ref NOTIFYICONIDENTIFIER identifier, out RECT rect);

  static bool Belongs(IntPtr window, uint expectedPid, bool visible) {
    uint actualPid; GetWindowThreadProcessId(window, out actualPid);
    return actualPid == expectedPid && (!visible || IsWindowVisible(window));
  }

  public static IntPtr FindCoordinator(uint pid) {
    IntPtr result = IntPtr.Zero; long largest = 0;
    EnumWindows((window, parameter) => {
      RECT r; if (!Belongs(window, pid, false) || !GetWindowRect(window, out r)) return true;
      long area = (long)(r.Right - r.Left) * (r.Bottom - r.Top);
      if (area > largest) { largest = area; result = window; }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static IntPtr FindPaper(uint pid) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      RECT r; if (Belongs(window, pid, true) && GetWindowRect(window, out r) &&
          (r.Right - r.Left < 800 || r.Bottom - r.Top < 500)) { result = window; return false; }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static IntPtr FindSizedPaper(uint pid, int width, int height) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      RECT r; if (Belongs(window, pid, true) && GetWindowRect(window, out r) &&
          r.Right - r.Left == width && r.Bottom - r.Top == height) { result = window; return false; }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static IntPtr FindLargestVisible(uint pid) {
    IntPtr result = IntPtr.Zero; long largest = 0;
    EnumWindows((window, parameter) => {
      RECT r; if (!Belongs(window, pid, true) || !GetWindowRect(window, out r)) return true;
      long area = (long)(r.Right - r.Left) * (r.Bottom - r.Top);
      if (area > largest) { largest = area; result = window; }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static int ForegroundProcessId() {
    IntPtr window = GetForegroundWindow(); uint processId;
    if (window == IntPtr.Zero) return 0;
    GetWindowThreadProcessId(window, out processId);
    return (int)processId;
  }

  public static bool IsTopmost(IntPtr window) { return (GetWindowLongPtr(window, -20).ToInt64() & 8) != 0; }
  public static bool IsVisible(IntPtr window) { return IsWindowVisible(window); }
  public static bool IsBorderlessResizable(IntPtr window) {
    long style = GetWindowLongPtr(window, -16).ToInt64();
    return (style & 0x00C00000) == 0 &&
           (style & unchecked((long)0x80000000)) != 0 &&
           (style & 0x00040000) != 0;
  }

  public static bool IsShownInTaskSwitcher(IntPtr window) {
    long style = GetWindowLongPtr(window, -20).ToInt64();
    return (style & 0x00040000) != 0 && (style & 0x00000080) == 0;
  }

  public static bool IsRightWorkAreaCapsule(IntPtr window) {
    RECT windowBounds, workArea;
    return GetWindowRect(window, out windowBounds) &&
           SystemParametersInfo(0x0030, 0, out workArea, 0) &&
           windowBounds.Right == workArea.Right &&
           windowBounds.Right - windowBounds.Left == 92 &&
           windowBounds.Bottom - windowBounds.Top == 46;
  }

  public static void ClickCapsule(IntPtr window) {
    RECT bounds; if (!GetWindowRect(window, out bounds)) return;
    SetCursorPos((bounds.Left + bounds.Right) / 2, bounds.Top + 30);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }

  public static void CloseWindow(IntPtr window) {
    PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero);
  }

  public static void ActivateFullscreen(IntPtr window) {
    RECT bounds; if (!GetWindowRect(window, out bounds)) return;
    ShowWindow(window, 5);
    SetWindowPos(window, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
    SetForegroundWindow(window);
    SetCursorPos((bounds.Left + bounds.Right) / 2, (bounds.Top + bounds.Bottom) / 2);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }

  static NOTIFYICONIDENTIFIER Identifier(IntPtr window) {
    return new NOTIFYICONIDENTIFIER { cbSize = (uint)Marshal.SizeOf(typeof(NOTIFYICONIDENTIFIER)), hWnd = window, uID = 1, guidItem = Guid.Empty };
  }

  public static bool TrayIconExists(IntPtr window) {
    var identifier = Identifier(window); RECT rect;
    return Shell_NotifyIconGetRect(ref identifier, out rect) == 0;
  }

  public static bool DeleteTrayIcon(IntPtr window) {
    var data = new NOTIFYICONDATA {
      cbSize = (uint)Marshal.SizeOf(typeof(NOTIFYICONDATA)), hWnd = window, uID = 1,
      szTip = "", szInfo = "", szInfoTitle = ""
    };
    return Shell_NotifyIcon(2, ref data);
  }

  public static void BroadcastTaskbarCreated(IntPtr window) {
    SendMessage(window, RegisterWindowMessage("TaskbarCreated"), IntPtr.Zero, IntPtr.Zero);
  }
}
"@ | Out-Null
}

function Start-FullscreenProbe {
  $source = @'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$form.BackColor = [System.Drawing.Color]::Black
$form.ShowInTaskbar = $true
$form.Add_Shown({ $form.Activate() })
[System.Windows.Forms.Application]::Run($form)
'@
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
  return Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-NoProfile", "-Sta", "-EncodedCommand", $encoded) `
    -WindowStyle Hidden -PassThru
}

function Resolve-ResultJsonPath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  if ($Path -match "[\x00-\x1F\x7F-\x9F]") {
    throw "Windows policy smoke result JSON path must not contain control characters."
  }
  if ($Path -match "[*?]") {
    throw "Windows policy smoke result JSON path must not contain wildcard characters."
  }
  try { $full = [IO.Path]::GetFullPath($Path) } catch {
    throw "Windows policy smoke result JSON path is invalid: $($_.Exception.Message)"
  }
  if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($full))) {
    throw "Windows policy smoke result JSON path must include a file name."
  }
  if ([IO.Path]::GetExtension($full).ToLowerInvariant() -ne ".json") {
    throw "Windows policy smoke result JSON path must use the .json extension."
  }
  return $full
}

Assert-WindowsHost
$resultPath = Resolve-ResultJsonPath $ResultJson
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReleaseDirectory)) {
  $ReleaseDirectory = Join-Path $repoRoot "build\windows\x64\runner\Release"
}
$releaseFull = [IO.Path]::GetFullPath($ReleaseDirectory)
$sourceExe = Join-Path $releaseFull "repapertodo.exe"
if (-not (Test-Path -LiteralPath $sourceExe -PathType Leaf)) {
  throw "Windows policy smoke release exe was not found: $sourceExe"
}
if (@(Get-Process -Name "repapertodo" -ErrorAction SilentlyContinue).Count -gt 0) {
  throw "Close existing RePaperTodo processes before policy smoke."
}

Initialize-PolicyNative
$tempRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot ".tmp"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$smokeRoot = Join-Path $tempRoot "repapertodo-policy-smoke-$([Guid]::NewGuid().ToString('N'))"
Assert-PathInside $smokeRoot $tempRoot
$smokeExe = Join-Path $smokeRoot "Release\repapertodo.exe"
$stateFile = Join-Path $smokeRoot "Release\data.json"
$primary = $null
$fullscreen = $null
$failure = $null
$trayRecovered = $false
$fullscreenAvoided = $false
$fullscreenRestored = $false
$longRunningScriptCapsule = $false
$borderlessResizableWindow = $false
$taskSwitcherVisibility = $false
$capsuleEdgeDocking = $false
$scriptStartedPath = Join-Path $smokeRoot "script-started.txt"
$scriptCompletedPath = Join-Path $smokeRoot "script-completed.txt"

try {
  New-Item -ItemType Directory -Force -Path (Join-Path $smokeRoot "Release") | Out-Null
  Copy-Item -Path (Join-Path $releaseFull "*") -Destination (Join-Path $smokeRoot "Release") -Recurse -Force
  $seed = [ordered]@{
    papers = @(
      [ordered]@{
        id = "policy-paper"; type = "todo"; title = "Policy QA"; x = 220.0; y = 160.0
        width = 360.0; height = 280.0; isVisible = $true; alwaysOnTop = $true
        isCollapsed = $false; isPinnedToDesktop = $false
        items = @([ordered]@{ id = "policy-item"; text = "policy"; done = $false; order = 0 })
      },
      [ordered]@{
        id = "script-policy-paper"; type = "note"; title = "Long script"; x = 300.0; y = 120.0
        width = 360.0; height = 280.0; isVisible = $true; alwaysOnTop = $false
        isCollapsed = $true; isPinnedToDesktop = $false; items = @()
        content = "!pf`nSet-Content -LiteralPath '$scriptStartedPath' -Value started -Encoding ascii`nStart-Sleep -Seconds 20`nSet-Content -LiteralPath '$scriptCompletedPath' -Value completed -Encoding ascii"
      }
    )
    fullscreenTopmostMode = "avoid"; theme = "light"; colorScheme = "warm"
    usePersistentPowerShellProcess = $true; preferPowerShell7 = $true
    hideScriptRunWindow = $true
  }
  $seed | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $stateFile -Encoding ascii
  $primary = Start-Process -FilePath $smokeExe -WorkingDirectory (Split-Path $smokeExe) -WindowStyle Hidden -PassThru
  Wait-ForCondition -TimeoutSeconds $StartupTimeoutSeconds -Message "Policy smoke app did not start." -Condition {
    (Test-Path -LiteralPath $stateFile -PathType Leaf) -and
      ([RePaperTodoPolicyNative]::FindPaper([uint32]$primary.Id) -ne [IntPtr]::Zero)
  }
  $paper = [RePaperTodoPolicyNative]::FindSizedPaper([uint32]$primary.Id, 360, 280)
  $coordinator = [RePaperTodoPolicyNative]::FindCoordinator([uint32]$primary.Id)
  $borderlessResizableWindow =
    [RePaperTodoPolicyNative]::IsBorderlessResizable($paper)
  if (-not $borderlessResizableWindow) {
    throw "Policy smoke paper does not use the expected borderless resizable style."
  }
  $taskSwitcherVisibility =
    [RePaperTodoPolicyNative]::IsShownInTaskSwitcher($paper)
  if (-not $taskSwitcherVisibility) {
    throw "Policy smoke paper is missing from the task switcher despite the visible setting."
  }
  Wait-ForCondition -TimeoutSeconds $StartupTimeoutSeconds -Message "Policy smoke paper did not become topmost." -Condition {
    [RePaperTodoPolicyNative]::IsTopmost($paper)
  }
  $trayBefore = [RePaperTodoPolicyNative]::TrayIconExists($coordinator)
  if (-not $trayBefore) { throw "Policy smoke could not find the initial tray icon." }
  if (-not [RePaperTodoPolicyNative]::DeleteTrayIcon($coordinator)) {
    throw "Policy smoke could not remove the tray icon for recovery simulation."
  }
  Start-Sleep -Milliseconds 300
  if ([RePaperTodoPolicyNative]::TrayIconExists($coordinator)) {
    throw "Policy smoke tray icon removal simulation did not remove the icon."
  }
  [RePaperTodoPolicyNative]::BroadcastTaskbarCreated($coordinator)
  Wait-ForCondition -TimeoutSeconds $StartupTimeoutSeconds -Message "Policy smoke tray icon did not recover after TaskbarCreated." -Condition {
    [RePaperTodoPolicyNative]::TrayIconExists($coordinator)
  }
  $trayRecovered = $true

  $fullscreen = Start-FullscreenProbe
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke fullscreen probe did not create a window." -Condition {
    [RePaperTodoPolicyNative]::FindLargestVisible([uint32]$fullscreen.Id) -ne [IntPtr]::Zero
  }
  $fullscreenWindow = [RePaperTodoPolicyNative]::FindLargestVisible([uint32]$fullscreen.Id)
  [RePaperTodoPolicyNative]::ActivateFullscreen($fullscreenWindow)
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke fullscreen probe did not become the foreground process." -Condition {
    [RePaperTodoPolicyNative]::ForegroundProcessId() -eq $fullscreen.Id
  }
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke paper did not avoid the fullscreen foreground window." -Condition {
    -not [RePaperTodoPolicyNative]::IsTopmost($paper)
  }
  $fullscreenAvoided = $true
  Stop-Process -Id $fullscreen.Id -Force -ErrorAction SilentlyContinue
  $fullscreen = $null
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke paper did not restore topmost after fullscreen closed." -Condition {
    [RePaperTodoPolicyNative]::IsTopmost($paper)
  }
  $fullscreenRestored = $true

  $scriptPaper = [RePaperTodoPolicyNative]::FindSizedPaper([uint32]$primary.Id, 92, 46)
  if ($scriptPaper -eq [IntPtr]::Zero) { throw "Policy smoke script capsule window was not found." }
  $capsuleEdgeDocking =
    [RePaperTodoPolicyNative]::IsRightWorkAreaCapsule($scriptPaper)
  if (-not $capsuleEdgeDocking) {
    throw "Policy smoke capsule did not dock to the right work-area edge."
  }
  [RePaperTodoPolicyNative]::ClickCapsule($scriptPaper)
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke long-running script did not start." -Condition {
    Test-Path -LiteralPath $scriptStartedPath -PathType Leaf
  }
  $persistentWorkers = @(Get-CimInstance Win32_Process | Where-Object {
      $_.ParentProcessId -eq $primary.Id -and
      ($_.Name -eq "pwsh.exe" -or $_.Name -eq "powershell.exe")
    })
  if ($persistentWorkers.Count -lt 1) { throw "Policy smoke persistent PowerShell worker was not found." }
  $settings = Start-Process -FilePath $smokeExe -ArgumentList "--settings" -WorkingDirectory (Split-Path $smokeExe) -WindowStyle Hidden -PassThru
  if (-not $settings.WaitForExit(10000)) { throw "Policy smoke settings command did not return while script was running." }
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke UI did not respond while script was running." -Condition {
    [RePaperTodoPolicyNative]::IsVisible($coordinator)
  }
  [RePaperTodoPolicyNative]::CloseWindow($coordinator)
  $longRunningScriptCapsule = $true

  $exit = Start-Process -FilePath $smokeExe -ArgumentList "--exit" -WorkingDirectory (Split-Path $smokeExe) -WindowStyle Hidden -PassThru
  if (-not $exit.WaitForExit($ExitTimeoutSeconds * 1000)) { throw "Policy smoke app did not exit." }
  if (-not $primary.WaitForExit($ExitTimeoutSeconds * 1000)) { throw "Policy smoke primary app did not exit." }
  Start-Sleep -Milliseconds 500
  $remainingWorkers = @(Get-CimInstance Win32_Process | Where-Object {
      $_.ParentProcessId -eq $primary.Id -and
      ($_.Name -eq "pwsh.exe" -or $_.Name -eq "powershell.exe")
    })
  if ($remainingWorkers.Count -ne 0) { throw "Policy smoke left a persistent PowerShell worker after exit." }
  if (-not [string]::IsNullOrWhiteSpace($resultPath)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resultPath) | Out-Null
    [ordered]@{
      status = "passed"; checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
      releaseDirectory = $releaseFull; exeFileName = "repapertodo.exe"
      trayIconRecoveredAfterTaskbarCreated = $trayRecovered
      fullscreenAvoidance = $fullscreenAvoided
      fullscreenTopmostRestored = $fullscreenRestored
      longRunningScriptCapsule = $longRunningScriptCapsule
      borderlessResizableWindow = $borderlessResizableWindow
      taskSwitcherVisibility = $taskSwitcherVisibility
      capsuleEdgeDocking = $capsuleEdgeDocking
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resultPath -Encoding ascii
  }
  Write-Host "Windows policy smoke passed: tray recovery, fullscreen avoidance, and long-running script capsules verified."
} catch {
  $failure = $_
  throw
} finally {
  if ($null -ne $fullscreen -and -not $fullscreen.HasExited) { Stop-Process -Id $fullscreen.Id -Force -ErrorAction SilentlyContinue }
  if ($null -ne $primary -and -not $primary.HasExited) { Stop-Process -Id $primary.Id -Force -ErrorAction SilentlyContinue }
  if (Test-Path -LiteralPath $smokeRoot) {
    Remove-Item -LiteralPath $smokeRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
