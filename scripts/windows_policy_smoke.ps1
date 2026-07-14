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
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr window);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out RECT bounds);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, System.Text.StringBuilder name, int maximum);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr window, System.Text.StringBuilder text, int maximum);
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

  public static IntPtr FindCapsule(uint pid) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      RECT r; if (Belongs(window, pid, true) && GetWindowRect(window, out r) &&
          r.Right - r.Left >= 76 && r.Bottom - r.Top == 46) {
        result = window; return false;
      }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static IntPtr FindWindowByTitle(uint pid, string expectedTitle) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      if (!Belongs(window, pid, true)) return true;
      var title = new System.Text.StringBuilder(256);
      GetWindowText(window, title, title.Capacity);
      if (title.ToString() == expectedTitle) { result = window; return false; }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static bool IsVisibleInteractiveDesktopPaper(IntPtr window) {
    if (window == IntPtr.Zero || !IsWindowVisible(window) ||
        GetParent(window) != IntPtr.Zero) return false;
    const long WS_CHILD = 0x40000000L;
    const long WS_POPUP = unchecked((long)0x80000000L);
    const long WS_THICKFRAME = 0x00040000L;
    const long WS_EX_TRANSPARENT = 0x00000020L;
    long style = GetWindowLongPtr(window, -16).ToInt64();
    long extended = GetWindowLongPtr(window, -20).ToInt64();
    return (style & WS_CHILD) == 0 &&
           (style & WS_POPUP) != 0 &&
           (style & WS_THICKFRAME) != 0 &&
           (extended & WS_EX_TRANSPARENT) == 0;
  }

  public static IntPtr FindWindowByTitleFragment(uint pid, string fragment) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      if (!Belongs(window, pid, true)) return true;
      var title = new System.Text.StringBuilder(256);
      GetWindowText(window, title, title.Capacity);
      if (title.ToString().Contains(fragment)) {
        result = window; return false;
      }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static IntPtr FindReminderBubble(uint pid) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      if (!Belongs(window, pid, true)) return true;
      var name = new System.Text.StringBuilder(128);
      GetClassName(window, name, name.Capacity);
      if (name.ToString() == "RePaperTodo.ReminderBubble") {
        result = window; return false;
      }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static int CountCapsules(uint pid) {
    int count = 0;
    EnumWindows((window, parameter) => {
      RECT r; if (Belongs(window, pid, true) && GetWindowRect(window, out r) &&
          r.Right - r.Left >= 76 && r.Bottom - r.Top == 46) count++;
      return true;
    }, IntPtr.Zero);
    return count;
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
  public static bool IsForeground(IntPtr window) {
    return window != IntPtr.Zero && GetForegroundWindow() == window;
  }
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
    if (!GetWindowRect(window, out windowBounds) ||
        !SystemParametersInfo(0x0030, 0, out workArea, 0) ||
        windowBounds.Right - windowBounds.Left < 92 ||
        windowBounds.Bottom - windowBounds.Top != 46) {
      return false;
    }
    // Normal capsules align their full right edge with the work area. Deep
    // capsules extend past it while their adaptive icon/title viewport stays
    // visible and the close area remains outside the work area.
    return windowBounds.Right == workArea.Right ||
           (windowBounds.Left < workArea.Right &&
            windowBounds.Right > workArea.Right);
  }

  public static bool IsLeftWorkAreaCapsule(IntPtr window) {
    RECT windowBounds, workArea;
    if (!GetWindowRect(window, out windowBounds) ||
        !SystemParametersInfo(0x0030, 0, out workArea, 0) ||
        windowBounds.Right - windowBounds.Left < 92 ||
        windowBounds.Bottom - windowBounds.Top != 46) return false;
    return windowBounds.Left <= workArea.Left &&
           windowBounds.Right > workArea.Left;
  }

  public static int CapsuleWindowWidth(IntPtr window) {
    RECT bounds; return GetWindowRect(window, out bounds)
      ? bounds.Right - bounds.Left
      : 0;
  }

  public static int RightWorkAreaVisibleWidth(IntPtr window) {
    RECT bounds, workArea;
    if (!GetWindowRect(window, out bounds) ||
        !SystemParametersInfo(0x0030, 0, out workArea, 0)) return 0;
    return Math.Max(0, Math.Min(bounds.Right, workArea.Right) -
                       Math.Max(bounds.Left, workArea.Left));
  }

  public static void HoverCapsule(IntPtr window) {
    RECT bounds; if (!GetWindowRect(window, out bounds)) return;
    int visibleRight = Math.Min(bounds.Right, bounds.Left +
      Math.Max(1, RightWorkAreaVisibleWidth(window)));
    SetCursorPos(Math.Max(bounds.Left, visibleRight - 8), bounds.Top + 30);
    System.Threading.Thread.Sleep(300);
  }

  public static void HoverWindow(IntPtr window) {
    RECT bounds; if (!GetWindowRect(window, out bounds)) return;
    SetCursorPos((bounds.Left + bounds.Right) / 2,
                 (bounds.Top + bounds.Bottom) / 2);
    System.Threading.Thread.Sleep(250);
  }

  public static void ClickWindow(IntPtr window) {
    HoverWindow(window);
    RECT bounds; if (!GetWindowRect(window, out bounds)) return;
    SetCursorPos((bounds.Left + bounds.Right) / 2,
                 (bounds.Top + bounds.Bottom) / 2);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(300);
    if (IsWindowVisible(window)) {
      PostMessage(window, 0x0202, IntPtr.Zero, IntPtr.Zero);
    }
  }

  public static bool IsAdjacent(IntPtr anchorWindow, IntPtr bubbleWindow) {
    RECT anchor, bubble;
    if (!GetWindowRect(anchorWindow, out anchor) ||
        !GetWindowRect(bubbleWindow, out bubble)) return false;
    int horizontalGap = Math.Min(Math.Abs(bubble.Left - anchor.Right),
                                 Math.Abs(anchor.Left - bubble.Right));
    bool verticallyOverlaps = bubble.Bottom >= anchor.Top &&
                              bubble.Top <= anchor.Bottom;
    return horizontalGap <= 20 && verticallyOverlaps;
  }

  public static string BoundsString(IntPtr window) {
    RECT bounds; if (!GetWindowRect(window, out bounds)) return "missing";
    return String.Format("{0},{1},{2},{3}", bounds.Left, bounds.Top,
                         bounds.Right, bounds.Bottom);
  }

  public static string VisibleWindowSummary(uint pid) {
    var entries = new List<string>();
    EnumWindows((window, parameter) => {
      if (!Belongs(window, pid, true)) return true;
      var title = new System.Text.StringBuilder(256);
      var name = new System.Text.StringBuilder(128);
      RECT bounds;
      GetWindowText(window, title, title.Capacity);
      GetClassName(window, name, name.Capacity);
      if (GetWindowRect(window, out bounds)) {
        entries.Add(String.Format("{0}|{1}|{2},{3},{4},{5}",
          title, name, bounds.Left, bounds.Top, bounds.Right, bounds.Bottom));
      }
      return true;
    }, IntPtr.Zero);
    return String.Join("; ", entries.ToArray());
  }

  public static void ClickCapsule(IntPtr window) {
    // Enter the currently visible strip first. Deep capsules expand toward the
    // desktop interior on hover, which changes their native left coordinate.
    HoverCapsule(window);
    RECT bounds; if (!GetWindowRect(window, out bounds)) return;
    if (!GetWindowRect(window, out bounds)) return;
    // Click the primary capsule action, not the dedicated close area at the
    // right edge of the adaptive-width surface.
    int visibleWidth = Math.Max(1, RightWorkAreaVisibleWidth(window));
    SetCursorPos(bounds.Left + Math.Max(16, visibleWidth / 2),
                 bounds.Top + Math.Max(12, (bounds.Bottom - bounds.Top) / 2));
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }

  public static void ClickNativeCapsule(IntPtr window) {
    if (window == IntPtr.Zero) return;
    PostMessage(window, 0x0201, new IntPtr(1), IntPtr.Zero);
    PostMessage(window, 0x0202, IntPtr.Zero, IntPtr.Zero);
    System.Threading.Thread.Sleep(300);
  }

  public static void HideWindow(IntPtr window) {
    if (window != IntPtr.Zero) ShowWindow(window, 0);
  }

  public static void DragCapsuleToLeft(IntPtr window) {
    HoverCapsule(window);
    RECT bounds, workArea;
    if (!GetWindowRect(window, out bounds) ||
        !SystemParametersInfo(0x0030, 0, out workArea, 0)) return;
    int startX = bounds.Left + 22;
    int startY = (bounds.Top + bounds.Bottom) / 2;
    int targetX = workArea.Left + 24;
    int targetY = startY;
    SetCursorPos(startX, startY);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    for (int step = 1; step <= 12; step++) {
      SetCursorPos(startX + ((targetX - startX) * step / 12),
                   startY + ((targetY - startY) * step / 12));
      System.Threading.Thread.Sleep(35);
    }
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(300);
  }

  public static void DragCapsuleVertically(IntPtr window, int deltaY) {
    HoverCapsule(window);
    RECT bounds, workArea;
    if (!GetWindowRect(window, out bounds) ||
        !SystemParametersInfo(0x0030, 0, out workArea, 0)) return;
    int visibleLeft = Math.Max(bounds.Left, workArea.Left);
    int visibleRight = Math.Min(bounds.Right, workArea.Right);
    int startX = visibleLeft + Math.Max(8, (visibleRight - visibleLeft) / 2);
    int startY = (bounds.Top + bounds.Bottom) / 2;
    SetCursorPos(startX, startY);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    for (int step = 1; step <= 10; step++) {
      SetCursorPos(startX, startY + (deltaY * step / 10));
      System.Threading.Thread.Sleep(35);
    }
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(300);
  }

  public static void DragPaperBy(IntPtr window, int deltaX, int deltaY) {
    RECT bounds; if (!GetWindowRect(window, out bounds)) return;
    int startX = (bounds.Left + bounds.Right) / 2;
    int startY = bounds.Top + 17;
    SetForegroundWindow(window);
    SetCursorPos(startX, startY);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    for (int step = 1; step <= 12; step++) {
      SetCursorPos(startX + (deltaX * step / 12),
                   startY + (deltaY * step / 12));
      System.Threading.Thread.Sleep(35);
    }
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(500);
  }

  public static void ClickRelative(IntPtr window, int x, int y) {
    RECT bounds; if (!GetWindowRect(window, out bounds)) return;
    SetForegroundWindow(window);
    SetCursorPos(bounds.Left + x, bounds.Top + y);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(250);
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
$capsuleWindowWidth = 0
$capsuleRestingVisibleWidth = 0
$capsuleHoverVisibleWidth = 0
$collapseAllMasterCapsule = $false
$nativeMasterPersists = $false
$expandedPaperProxy = $false
$masterCapsuleDragPersistence = $false
$expandedProxyClickActivates = $false
$expandedProxyDropRouting = $false
$reminderBubbleAdjacent = $false
$reminderBubbleHoverPause = $false
$reminderBubbleClickOpensPaper = $false
$capsuleDropRouting = $false
$contentEditGeometryStable = $false
$desktopPinnedPaperVisible = $false
$desktopPinnedPaperInteractive = $false
$scriptStartedPath = Join-Path $smokeRoot "script-started.txt"
$scriptCompletedPath = Join-Path $smokeRoot "script-completed.txt"

try {
  New-Item -ItemType Directory -Force -Path (Join-Path $smokeRoot "Release") | Out-Null
  Copy-Item -Path (Join-Path $releaseFull "*") -Destination (Join-Path $smokeRoot "Release") -Recurse -Force
  $desktopPinSeed = [ordered]@{
    papers = @([ordered]@{
      id = "pinned-policy-paper"; type = "note"; title = "Pinned QA"; x = 640.0; y = 260.0
      width = 320.0; height = 260.0; isVisible = $true; alwaysOnTop = $false
      isCollapsed = $false; isPinnedToDesktop = $true; items = @()
      content = "Pinned paper must remain visible and keep its unpin interaction."
    })
    fullscreenTopmostMode = "avoid"; theme = "light"; colorScheme = "warm"
    maxTitleLength = 64
  }
  $desktopPinSeed | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $stateFile -Encoding ascii
  $primary = Start-Process -FilePath $smokeExe -WorkingDirectory (Split-Path $smokeExe) -WindowStyle Hidden -PassThru
  Wait-ForCondition -TimeoutSeconds $StartupTimeoutSeconds -Message "Policy smoke desktop-pinned paper disappeared from the top-level window list." -Condition {
    [RePaperTodoPolicyNative]::FindWindowByTitleFragment(
      [uint32]$primary.Id, "Pinned QA") -ne [IntPtr]::Zero
  }
  $pinnedPaper = [RePaperTodoPolicyNative]::FindWindowByTitleFragment(
    [uint32]$primary.Id, "Pinned QA")
  $desktopPinnedPaperVisible = $true
  $desktopPinnedPaperInteractive =
    [RePaperTodoPolicyNative]::IsVisibleInteractiveDesktopPaper($pinnedPaper)
  if (-not $desktopPinnedPaperInteractive) {
    throw "Policy smoke desktop-pinned paper was reparented or made click-through."
  }
  $desktopPinExit = Start-Process -FilePath $smokeExe -ArgumentList "--exit" -WorkingDirectory (Split-Path $smokeExe) -WindowStyle Hidden -PassThru
  if (-not $desktopPinExit.WaitForExit($ExitTimeoutSeconds * 1000)) {
    throw "Policy smoke desktop-pin preflight exit command did not return."
  }
  if (-not $primary.WaitForExit($ExitTimeoutSeconds * 1000)) {
    throw "Policy smoke desktop-pin preflight app did not exit."
  }
  $primary = $null

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
      },
      [ordered]@{
        id = "reminder-policy-paper"; type = "todo"; title = "Reminder QA"; x = 520.0; y = 180.0
        width = 360.0; height = 280.0; isVisible = $true; alwaysOnTop = $false
        isCollapsed = $true; isPinnedToDesktop = $false
        items = @([ordered]@{
          id = "reminder-policy-item"; text = "Open from adjacent bubble"; done = $false; order = 0
          dueAtLocal = (Get-Date).AddMinutes(-5).ToString("o")
        })
      }
    )
    fullscreenTopmostMode = "avoid"; theme = "light"; colorScheme = "warm"
    useCapsuleCollapseAll = $true; capsuleCollapseAllActive = $true
    useTodoReminderInterval = $true; todoReminderIntervalValue = 1
    todoReminderIntervalUnit = "minutes"; todoReminderBubbleDurationSeconds = 15
    usePersistentPowerShellProcess = $true; preferPowerShell7 = $true
    hideScriptRunWindow = $true
  }
  $seed | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $stateFile -Encoding ascii
  $primary = Start-Process -FilePath $smokeExe -WorkingDirectory (Split-Path $smokeExe) -WindowStyle Hidden -PassThru
  Wait-ForCondition -TimeoutSeconds $StartupTimeoutSeconds -Message "Policy smoke app did not start." -Condition {
    (Test-Path -LiteralPath $stateFile -PathType Leaf) -and
      ([RePaperTodoPolicyNative]::FindCoordinator([uint32]$primary.Id) -ne [IntPtr]::Zero) -and
      ([RePaperTodoPolicyNative]::FindCapsule([uint32]$primary.Id) -ne [IntPtr]::Zero)
  }
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke collapse-all did not expose exactly one master capsule for the queue." -Condition {
    [RePaperTodoPolicyNative]::CountCapsules([uint32]$primary.Id) -eq 1
  }
  $masterCapsule = [RePaperTodoPolicyNative]::FindCapsule([uint32]$primary.Id)
  Start-Sleep -Milliseconds 3000
  [RePaperTodoPolicyNative]::ClickNativeCapsule($masterCapsule)
  try {
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke master capsule did not expand the queue." -Condition {
      [RePaperTodoPolicyNative]::FindSizedPaper([uint32]$primary.Id, 360, 280) -ne [IntPtr]::Zero
    }
  } catch {
    $windows = [RePaperTodoPolicyNative]::VisibleWindowSummary([uint32]$primary.Id)
    $exited = $primary.HasExited
    $exitCode = if ($exited) { $primary.ExitCode } else { "running" }
    throw "Policy smoke master capsule did not expand the queue (processExited=$exited, exitCode=$exitCode). Visible windows: $windows"
  }
  $collapseAllMasterCapsule = $true
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke did not reconcile native master/proxy surfaces after expanding the queue." -Condition {
    ([RePaperTodoPolicyNative]::FindWindowByTitleFragment([uint32]$primary.Id, "Native Capsule [master:") -ne [IntPtr]::Zero) -and
    ([RePaperTodoPolicyNative]::FindWindowByTitle([uint32]$primary.Id, "RePaperTodo Native Capsule [proxy:policy-paper]") -ne [IntPtr]::Zero)
  }
  $nativeMaster = [RePaperTodoPolicyNative]::FindWindowByTitleFragment([uint32]$primary.Id, "Native Capsule [master:")
  $expandedProxy = [RePaperTodoPolicyNative]::FindWindowByTitle([uint32]$primary.Id, "RePaperTodo Native Capsule [proxy:policy-paper]")
  if ($nativeMaster -eq [IntPtr]::Zero) {
    throw "Policy smoke native master capsule disappeared after expanding its queue."
  }
  if ($expandedProxy -eq [IntPtr]::Zero) {
    throw "Policy smoke expanded paper did not retain a native edge proxy."
  }
  $nativeMasterPersists = $true
  $expandedPaperProxy = $true
  [RePaperTodoPolicyNative]::DragCapsuleVertically($nativeMaster, 64)
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke native master drag did not persist the queue start margin." -Condition {
    try { $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { return $false }
    $margins = @($saved.deepCapsuleQueueStartTopMargins.PSObject.Properties | ForEach-Object { [double]$_.Value })
    @($margins | Where-Object { $_ -gt 80 }).Count -gt 0
  }
  $masterCapsuleDragPersistence = $true
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke native reminder bubble was not shown." -Condition {
    [RePaperTodoPolicyNative]::FindReminderBubble([uint32]$primary.Id) -ne [IntPtr]::Zero
  }
  try {
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke collapse-all expansion did not restore the reminder capsule." -Condition {
      [RePaperTodoPolicyNative]::FindWindowByTitle([uint32]$primary.Id, "Remind") -ne [IntPtr]::Zero
    }
  } catch {
    $windows = [RePaperTodoPolicyNative]::VisibleWindowSummary([uint32]$primary.Id)
    throw "Policy smoke collapse-all expansion did not restore the reminder capsule. Visible windows: $windows"
  }
  $reminderBubble = [RePaperTodoPolicyNative]::FindReminderBubble([uint32]$primary.Id)
  $reminderCapsule = [RePaperTodoPolicyNative]::FindWindowByTitle([uint32]$primary.Id, "Remind")
  $reminderBubbleAdjacent = [RePaperTodoPolicyNative]::IsAdjacent($reminderCapsule, $reminderBubble)
  if (-not $reminderBubbleAdjacent) {
    $anchorBounds = [RePaperTodoPolicyNative]::BoundsString($reminderCapsule)
    $bubbleBounds = [RePaperTodoPolicyNative]::BoundsString($reminderBubble)
    throw "Policy smoke reminder bubble was not placed beside its paper capsule (anchor=$anchorBounds, bubble=$bubbleBounds)."
  }
  [RePaperTodoPolicyNative]::HoverWindow($reminderBubble)
  Start-Sleep -Milliseconds 15500
  if (-not [RePaperTodoPolicyNative]::IsVisible($reminderBubble)) {
    throw "Policy smoke reminder bubble did not pause dismissal while hovered."
  }
  $reminderBubbleHoverPause = $true
  [RePaperTodoPolicyNative]::ClickWindow($reminderBubble)
  try {
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke reminder bubble did not open its paper." -Condition {
      $window = [RePaperTodoPolicyNative]::FindWindowByTitle([uint32]$primary.Id, "Remind")
      $window -ne [IntPtr]::Zero -and [RePaperTodoPolicyNative]::CapsuleWindowWidth($window) -eq 360
    }
  } catch {
    $bubbleVisible = [RePaperTodoPolicyNative]::IsVisible($reminderBubble)
    $windows = [RePaperTodoPolicyNative]::VisibleWindowSummary([uint32]$primary.Id)
    throw "Policy smoke reminder bubble did not open its paper (bubbleVisible=$bubbleVisible). Visible windows: $windows"
  }
  $reminderBubbleClickOpensPaper = $true
  # Both the ordinary policy paper and the reminder paper are 360x280 after
  # the reminder opens. Selecting by size made this assertion depend on
  # EnumWindows order and occasionally checked the reminder HWND instead of
  # the paper owned by the expanded proxy.
  $paper = [RePaperTodoPolicyNative]::FindWindowByTitle([uint32]$primary.Id, "Policy")
  if ($paper -eq [IntPtr]::Zero) {
    throw "Policy smoke could not identify the expanded proxy's owning paper."
  }
  $reminderPaper = [RePaperTodoPolicyNative]::FindWindowByTitle([uint32]$primary.Id, "Remind")
  [RePaperTodoPolicyNative]::HideWindow($paper)
  Wait-ForCondition -TimeoutSeconds 5 -Message "Policy smoke could not hide the proxy's paper for routing validation." -Condition {
    -not [RePaperTodoPolicyNative]::IsVisible($paper)
  }
  [RePaperTodoPolicyNative]::ClickNativeCapsule($expandedProxy)
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke expanded edge proxy did not restore its owning paper." -Condition {
    [RePaperTodoPolicyNative]::IsVisible($paper)
  }
  $expandedProxyClickActivates = $true
  [RePaperTodoPolicyNative]::SetForegroundWindow($reminderPaper) | Out-Null
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

  $paper = [RePaperTodoPolicyNative]::FindWindowByTitle([uint32]$primary.Id, "Policy")
  if ($paper -eq [IntPtr]::Zero) {
    throw "Policy smoke could not find the ordinary paper for drag/edit geometry validation."
  }
  $preDragBounds = [RePaperTodoPolicyNative]::BoundsString($paper)
  [RePaperTodoPolicyNative]::DragPaperBy($paper, 140, 90)
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke ordinary paper drag did not move the native window." -Condition {
    [RePaperTodoPolicyNative]::BoundsString($paper) -ne $preDragBounds
  }
  $draggedBounds = [RePaperTodoPolicyNative]::BoundsString($paper)
  # Edit immediately after the native drag. Waiting for the debounced state
  # save here used to hide a race where a later surface-property refresh could
  # replay the coordinator's stale pre-drag geometry.
  Add-Type -AssemblyName System.Windows.Forms
  [RePaperTodoPolicyNative]::ClickRelative($paper, 140, 52)
  [System.Windows.Forms.SendKeys]::SendWait(" updated")
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke could not edit todo content after dragging the paper." -Condition {
    if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { return $false }
    try { $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { return $false }
    $paperState = @($saved.papers | Where-Object { $_.id -eq "policy-paper" })[0]
    $null -ne $paperState -and
      @($paperState.items).Count -gt 0 -and
      [string]$paperState.items[0].text -match "updated"
  }
  Start-Sleep -Milliseconds 1000
  $postEditBounds = [RePaperTodoPolicyNative]::BoundsString($paper)
  if ($postEditBounds -ne $draggedBounds) {
    throw "Policy smoke content edit replayed stale paper geometry (dragged=$draggedBounds, afterEdit=$postEditBounds)."
  }
  $contentEditGeometryStable = $true
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke ordinary paper drag did not persist its geometry." -Condition {
    if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { return $false }
    try { $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { return $false }
    $paperState = @($saved.papers | Where-Object { $_.id -eq "policy-paper" })[0]
    $null -ne $paperState -and
      (([int][Math]::Round([double]$paperState.x)) -ne 220 -or
       ([int][Math]::Round([double]$paperState.y)) -ne 160)
  }

  $expandedProxy = [RePaperTodoPolicyNative]::FindWindowByTitle([uint32]$primary.Id, "RePaperTodo Native Capsule [proxy:policy-paper]")
  if ($expandedProxy -eq [IntPtr]::Zero) {
    throw "Policy smoke expanded paper proxy disappeared before drag routing validation."
  }
  [RePaperTodoPolicyNative]::DragCapsuleToLeft($expandedProxy)
  Wait-ForCondition -TimeoutSeconds 15 -Message "Policy smoke expanded proxy drag did not persist its queue assignment." -Condition {
    try { $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { return $false }
    $paperState = @($saved.papers | Where-Object { $_.id -eq "policy-paper" })[0]
    $null -ne $paperState -and $paperState.capsuleSide -eq "left"
  }
  $expandedProxyDropRouting = $true

  $scriptPaper = [RePaperTodoPolicyNative]::FindWindowByTitle([uint32]$primary.Id, "Long s")
  if ($scriptPaper -eq [IntPtr]::Zero) { throw "Policy smoke script capsule window was not found." }
  $capsuleEdgeDocking =
    [RePaperTodoPolicyNative]::IsRightWorkAreaCapsule($scriptPaper)
  if (-not $capsuleEdgeDocking) {
    throw "Policy smoke capsule did not dock to the right work-area edge."
  }
  $capsuleWindowWidth = [RePaperTodoPolicyNative]::CapsuleWindowWidth($scriptPaper)
  $capsuleRestingVisibleWidth = [RePaperTodoPolicyNative]::RightWorkAreaVisibleWidth($scriptPaper)
  [RePaperTodoPolicyNative]::HoverCapsule($scriptPaper)
  $capsuleHoverVisibleWidth = [RePaperTodoPolicyNative]::RightWorkAreaVisibleWidth($scriptPaper)
  if ($capsuleWindowWidth -le 92) {
    throw "Policy smoke long-title capsule did not expand beyond its minimum width."
  }
  if ($capsuleRestingVisibleWidth -le 0 -or
      $capsuleHoverVisibleWidth -le $capsuleRestingVisibleWidth -or
      $capsuleHoverVisibleWidth -ge $capsuleWindowWidth) {
    throw "Policy smoke adaptive deep-capsule viewport did not partially reveal on hover."
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
  [RePaperTodoPolicyNative]::DragCapsuleToLeft($scriptPaper)
  Wait-ForCondition -TimeoutSeconds 15 -Message "Policy smoke capsule drag did not snap to the opposite edge." -Condition {
    [RePaperTodoPolicyNative]::IsLeftWorkAreaCapsule($scriptPaper)
  }
  Wait-ForCondition -TimeoutSeconds 15 -Message "Policy smoke capsule drag did not persist its queue assignment." -Condition {
    $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    $scriptState = @($saved.papers | Where-Object { $_.id -eq "script-policy-paper" })[0]
    $null -ne $scriptState -and $scriptState.capsuleSide -eq "left"
  }
  $capsuleDropRouting = $true
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
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke left a persistent PowerShell worker after exit." -Condition {
    @(Get-CimInstance Win32_Process | Where-Object {
        $_.ParentProcessId -eq $primary.Id -and
        ($_.Name -eq "pwsh.exe" -or $_.Name -eq "powershell.exe")
      }).Count -eq 0
  }
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
      capsuleWindowWidth = $capsuleWindowWidth
      capsuleRestingVisibleWidth = $capsuleRestingVisibleWidth
      capsuleHoverVisibleWidth = $capsuleHoverVisibleWidth
      collapseAllMasterCapsule = $collapseAllMasterCapsule
      nativeMasterPersists = $nativeMasterPersists
      expandedPaperProxy = $expandedPaperProxy
      masterCapsuleDragPersistence = $masterCapsuleDragPersistence
      expandedProxyClickActivates = $expandedProxyClickActivates
      expandedProxyDropRouting = $expandedProxyDropRouting
      reminderBubbleAdjacent = $reminderBubbleAdjacent
      reminderBubbleHoverPause = $reminderBubbleHoverPause
      reminderBubbleClickOpensPaper = $reminderBubbleClickOpensPaper
      capsuleDropRouting = $capsuleDropRouting
      contentEditGeometryStable = $contentEditGeometryStable
      desktopPinnedPaperVisible = $desktopPinnedPaperVisible
      desktopPinnedPaperInteractive = $desktopPinnedPaperInteractive
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
