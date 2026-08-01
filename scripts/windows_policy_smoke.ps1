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

function Assert-MonotonicAlpha {
  param(
    [int[]]$Samples,
    [bool]$Increasing,
    [string]$Message,
    [int]$Tolerance = 3
  )
  if ($null -eq $Samples -or $Samples.Count -lt 2) {
    throw "$Message Alpha samples were unavailable."
  }
  for ($index = 1; $index -lt $Samples.Count; $index++) {
    $previous = [int]$Samples[$index - 1]
    $current = [int]$Samples[$index]
    $reversed = if ($Increasing) {
      $current + $Tolerance -lt $previous
    } else {
      $current - $Tolerance -gt $previous
    }
    if ($reversed) {
      throw "$Message Alpha reversed at sample $index ($previous -> $current): $($Samples -join ',')."
    }
  }
  $minimum = ($Samples | Measure-Object -Minimum).Minimum
  $maximum = ($Samples | Measure-Object -Maximum).Maximum
  if ([int]$minimum -gt 5 -or [int]$maximum -lt 250) {
    throw "$Message Alpha did not cover both visible and retracted endpoints: $($Samples -join ',')."
  }
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
  public static string LastVerticalDragTrace = "";
  public static string LastResizeTrace = "";
  public static string LastForegroundTrace = "";
  public static string LastSettingsDragTrace = "";

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }

  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X, Y; }

  [StructLayout(LayoutKind.Sequential)]
  public struct MONITORINFO {
    public uint cbSize;
    public RECT rcMonitor;
    public RECT rcWork;
    public uint dwFlags;
  }

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
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr window);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out RECT bounds);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, System.Text.StringBuilder name, int maximum);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr window, System.Text.StringBuilder text, int maximum);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetProp(IntPtr window, string name);
  [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
  [DllImport("user32.dll", SetLastError = true)] static extern bool GetLayeredWindowAttributes(IntPtr window, out uint colorKey, out byte alpha, out uint flags);
  [DllImport("user32.dll")] static extern uint RegisterWindowMessage(string name);
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT point);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint flags);
  [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
  [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
  [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action, uint parameter, out RECT bounds, uint flags);
  [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern bool Shell_NotifyIcon(uint message, ref NOTIFYICONDATA data);
  [DllImport("shell32.dll")] static extern int Shell_NotifyIconGetRect(ref NOTIFYICONIDENTIFIER identifier, out RECT rect);

  static bool Belongs(IntPtr window, uint expectedPid, bool visible) {
    uint actualPid; GetWindowThreadProcessId(window, out actualPid);
    if (actualPid != expectedPid || (visible && !IsWindowVisible(window))) {
      return false;
    }
    var className = new System.Text.StringBuilder(128);
    GetClassName(window, className, className.Capacity);
    return className.ToString() != "RePaperTodo.PaperShadow";
  }

  static byte EffectiveWindowAlpha(IntPtr window) {
    const long WS_EX_LAYERED = 0x00080000L;
    const uint LWA_ALPHA = 0x00000002;
    if ((GetWindowLongPtr(window, -20).ToInt64() & WS_EX_LAYERED) == 0) {
      return 255;
    }
    long nativeCapsuleAlpha =
        GetProp(window, "RePaperTodo.NativeCapsuleAlpha").ToInt64();
    if (nativeCapsuleAlpha > 0 && nativeCapsuleAlpha <= 256) {
      return (byte)(nativeCapsuleAlpha - 1);
    }
    uint colorKey, flags;
    byte alpha;
    if (!GetLayeredWindowAttributes(window, out colorKey, out alpha, out flags) ||
        (flags & LWA_ALPHA) == 0) {
      return 255;
    }
    return alpha;
  }

  static bool IsPerceptible(IntPtr window) {
    return IsWindowVisible(window) && EffectiveWindowAlpha(window) > 0;
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
      RECT r; if (Belongs(window, pid, true) && IsPerceptible(window) &&
          GetWindowRect(window, out r) &&
          (r.Right - r.Left < 800 || r.Bottom - r.Top < 500)) { result = window; return false; }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static IntPtr FindSizedPaper(uint pid, int width, int height) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      RECT r; if (Belongs(window, pid, true) && IsPerceptible(window) &&
          GetWindowRect(window, out r) &&
          r.Right - r.Left == width && r.Bottom - r.Top == height) { result = window; return false; }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static IntPtr FindCapsule(uint pid) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      RECT r; if (Belongs(window, pid, true) && IsPerceptible(window) &&
          GetWindowRect(window, out r) &&
          r.Right - r.Left >= 34 && r.Bottom - r.Top == 46) {
        result = window; return false;
      }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static IntPtr FindWindowByTitle(uint pid, string expectedTitle) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      if (!Belongs(window, pid, true) || !IsPerceptible(window)) return true;
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
      if (!Belongs(window, pid, true) || !IsPerceptible(window)) return true;
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
      RECT r; if (Belongs(window, pid, true) && IsPerceptible(window) &&
          GetWindowRect(window, out r) &&
          r.Right - r.Left >= 34 && r.Bottom - r.Top == 46) count++;
      return true;
    }, IntPtr.Zero);
    return count;
  }

  public static IntPtr FindLargestVisible(uint pid) {
    IntPtr result = IntPtr.Zero; long largest = 0;
    EnumWindows((window, parameter) => {
      RECT r; if (!Belongs(window, pid, true) || !IsPerceptible(window) ||
          !GetWindowRect(window, out r)) return true;
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
  public static bool IsWindowHandle(IntPtr window) {
    return window != IntPtr.Zero && IsWindow(window);
  }
  public static int LayeredAlpha(IntPtr window) { return EffectiveWindowAlpha(window); }
  public static IntPtr FindPaperShadowFor(IntPtr paperWindow) {
    RECT paperBounds;
    if (paperWindow == IntPtr.Zero ||
        !GetWindowRect(paperWindow, out paperBounds)) {
      return IntPtr.Zero;
    }
    IntPtr taggedShadow = IntPtr.Zero;
    IntPtr boundsMatchedShadow = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      var className = new System.Text.StringBuilder(128);
      GetClassName(window, className, className.Capacity);
      if (className.ToString() != "RePaperTodo.PaperShadow") return true;
      if (GetProp(window, "RePaperTodo.PaperShadowOwner") == paperWindow) {
        taggedShadow = window;
        return false;
      }
      RECT shadowBounds;
      if (boundsMatchedShadow == IntPtr.Zero &&
          GetWindowRect(window, out shadowBounds) &&
          shadowBounds.Left == paperBounds.Left &&
          shadowBounds.Top == paperBounds.Top &&
          shadowBounds.Right == paperBounds.Right &&
          shadowBounds.Bottom == paperBounds.Bottom) {
        // Older already-built smoke binaries predate the diagnostic property.
        // Capture the exact pre-resize shadow HWND once; later samples inspect
        // that same handle even if it retains stale geometry during sizing.
        boundsMatchedShadow = window;
      }
      return true;
    }, IntPtr.Zero);
    return taggedShadow != IntPtr.Zero ? taggedShadow : boundsMatchedShadow;
  }
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
    RECT bounds;
    if (!GetWindowRect(window, out bounds)) return 0;
    IntPtr monitor = MonitorFromWindow(window, 2);
    var info = new MONITORINFO {
      cbSize = (uint)Marshal.SizeOf(typeof(MONITORINFO))
    };
    if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref info)) return 0;
    return Math.Max(0, Math.Min(bounds.Right, info.rcWork.Right) -
                       Math.Max(bounds.Left, info.rcWork.Left));
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
    int x = Math.Max(1, (bounds.Right - bounds.Left) / 2);
    int y = Math.Max(1, (bounds.Bottom - bounds.Top) / 2);
    SetCursorPos(bounds.Left + x, bounds.Top + y);
    SendMessage(window, 0x0200, IntPtr.Zero,
                new IntPtr((y << 16) | (x & 0xFFFF)));
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

  public static string CapsuleActionPointSummary(IntPtr window) {
    HoverCapsule(window);
    RECT bounds; if (!GetWindowRect(window, out bounds)) return "missing";
    int visibleWidth = Math.Max(1, RightWorkAreaVisibleWidth(window));
    var point = new POINT {
      X = bounds.Left + Math.Max(16, visibleWidth / 2),
      Y = bounds.Top + Math.Max(12, (bounds.Bottom - bounds.Top) / 2)
    };
    IntPtr hit = WindowFromPoint(point);
    IntPtr root = hit == IntPtr.Zero ? IntPtr.Zero : GetAncestor(hit, 2);
    var hitClass = new System.Text.StringBuilder(128);
    var rootTitle = new System.Text.StringBuilder(256);
    if (hit != IntPtr.Zero) GetClassName(hit, hitClass, hitClass.Capacity);
    if (root != IntPtr.Zero) GetWindowText(root, rootTitle, rootTitle.Capacity);
    long packedPoint = ((long)(ushort)point.Y << 16) | (ushort)point.X;
    long hitTest = root == IntPtr.Zero
      ? -1
      : SendMessage(root, 0x0084, IntPtr.Zero, new IntPtr(packedPoint)).ToInt64();
    return String.Format(
      "target=0x{0:X};bounds={1},{2},{3},{4};visible={5};point={6},{7};hit=0x{8:X};hitClass={9};root=0x{10:X};rootTitle={11};hitTest={12}",
      window.ToInt64(), bounds.Left, bounds.Top, bounds.Right, bounds.Bottom,
      visibleWidth, point.X, point.Y, hit.ToInt64(), hitClass.ToString(),
      root.ToInt64(), rootTitle.ToString(), hitTest);
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
        entries.Add(String.Format("{0}|{1}|{2},{3},{4},{5}|alpha={6}",
          title, name, bounds.Left, bounds.Top, bounds.Right, bounds.Bottom,
          EffectiveWindowAlpha(window)));
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
    RECT bounds;
    if (!GetWindowRect(window, out bounds)) return;
    int x = Math.Max(1, (bounds.Right - bounds.Left) / 2);
    int y = Math.Max(1, (bounds.Bottom - bounds.Top) / 2);
    IntPtr point = new IntPtr((y << 16) | (x & 0xFFFF));
    SendMessage(window, 0x0201, new IntPtr(1), point);
    SendMessage(window, 0x0202, IntPtr.Zero, point);
    System.Threading.Thread.Sleep(300);
  }

  public static int[] ClickNativeCapsuleAndSampleForeground(
      IntPtr capsule, IntPtr paper, int durationMilliseconds,
      int intervalMilliseconds) {
    LastForegroundTrace = "";
    if (capsule == IntPtr.Zero || paper == IntPtr.Zero) {
      return new int[] { -1, -1, 0 };
    }
    RECT bounds;
    if (!GetWindowRect(capsule, out bounds)) {
      return new int[] { -1, -1, 0 };
    }
    int x = Math.Max(1, (bounds.Right - bounds.Left) / 2);
    int y = Math.Max(1, (bounds.Bottom - bounds.Top) / 2);
    IntPtr point = new IntPtr((y << 16) | (x & 0xFFFF));
    SendMessage(capsule, 0x0201, new IntPtr(1), point);
    SendMessage(capsule, 0x0202, IntPtr.Zero, point);

    var stopwatch = System.Diagnostics.Stopwatch.StartNew();
    var changes = new List<string>();
    IntPtr previous = IntPtr.Zero;
    int firstPaperMilliseconds = -1;
    int firstLossMilliseconds = -1;
    bool reachedPaper = false;
    while (stopwatch.ElapsedMilliseconds <= durationMilliseconds) {
      IntPtr foreground = GetForegroundWindow();
      int elapsed = (int)stopwatch.ElapsedMilliseconds;
      if (foreground != previous) {
        changes.Add(String.Format("{0}:0x{1:X}", elapsed,
                                  foreground.ToInt64()));
        previous = foreground;
      }
      if (foreground == paper) {
        if (!reachedPaper) firstPaperMilliseconds = elapsed;
        reachedPaper = true;
      } else if (reachedPaper && firstLossMilliseconds < 0) {
        firstLossMilliseconds = elapsed;
      }
      System.Threading.Thread.Sleep(Math.Max(1, intervalMilliseconds));
    }
    LastForegroundTrace = String.Join(",", changes.ToArray());
    return new int[] {
        firstPaperMilliseconds,
        firstLossMilliseconds,
        GetForegroundWindow() == paper ? 1 : 0,
    };
  }

  public static int[] ClickNativeCapsuleAndSampleAlpha(
      IntPtr clickWindow, IntPtr sampleWindow, int durationMilliseconds,
      int intervalMilliseconds) {
    var samples = new List<int>();
    if (clickWindow == IntPtr.Zero || sampleWindow == IntPtr.Zero) {
      return samples.ToArray();
    }
    samples.Add(EffectiveWindowAlpha(sampleWindow));
    RECT bounds;
    if (!GetWindowRect(clickWindow, out bounds)) return samples.ToArray();
    int x = Math.Max(1, (bounds.Right - bounds.Left) / 2);
    int y = Math.Max(1, (bounds.Bottom - bounds.Top) / 2);
    IntPtr point = new IntPtr((y << 16) | (x & 0xFFFF));
    SendMessage(clickWindow, 0x0201, new IntPtr(1), point);
    SendMessage(clickWindow, 0x0202, IntPtr.Zero, point);
    int interval = Math.Max(1, intervalMilliseconds);
    int sampleCount = Math.Max(1, durationMilliseconds / interval);
    for (int index = 0; index < sampleCount; index++) {
      System.Threading.Thread.Sleep(interval);
      if (!IsWindow(sampleWindow)) break;
      samples.Add(EffectiveWindowAlpha(sampleWindow));
    }
    return samples.ToArray();
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
    SetForegroundWindow(window);
    SetCursorPos(startX, startY);
    System.Threading.Thread.Sleep(120);
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

  public static int MeasureVerticalDragFollowing(
      IntPtr masterWindow, IntPtr childWindow, int deltaY) {
    RECT masterStart, childStart, workArea;
    if (masterWindow == IntPtr.Zero || childWindow == IntPtr.Zero ||
        !GetWindowRect(masterWindow, out masterStart) ||
        !GetWindowRect(childWindow, out childStart) ||
        !SystemParametersInfo(0x0030, 0, out workArea, 0)) {
      LastVerticalDragTrace = "initial window geometry unavailable";
      return Int32.MaxValue;
    }
    var trace = new System.Text.StringBuilder();
    trace.AppendFormat("start master={0}, child={1}",
                       masterStart.Top, childStart.Top);
    int visibleLeft = Math.Max(masterStart.Left, workArea.Left);
    int visibleRight = Math.Min(masterStart.Right, workArea.Right);
    int startX = visibleLeft + Math.Max(8, (visibleRight - visibleLeft) / 2);
    int startY = (masterStart.Top + masterStart.Bottom) / 2;
    SetCursorPos(startX, startY);
    System.Threading.Thread.Sleep(80);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    int maximumError = 0;
    int previousMasterTop = masterStart.Top;
    int previousChildTop = childStart.Top;
    int activeMasterStart = masterStart.Top;
    int activeChildStart = childStart.Top;
    bool dragStarted = false;
    for (int step = 1; step <= 12; step++) {
      SetCursorPos(startX, startY + (deltaY * step / 12));
      System.Threading.Thread.Sleep(35);
      RECT masterCurrent, childCurrent;
      if (!GetWindowRect(masterWindow, out masterCurrent) ||
          !GetWindowRect(childWindow, out childCurrent)) {
        maximumError = Int32.MaxValue;
        trace.AppendFormat("; step {0}: geometry unavailable", step);
        break;
      }
      if (!dragStarted) {
        if (masterCurrent.Top == previousMasterTop) {
          // Cursor motion below the system drag threshold is still a click.
          // A child may legitimately finish an earlier reveal during this
          // interval; keep refreshing the baselines until the master itself
          // proves that the queue drag has begun.
          previousMasterTop = masterCurrent.Top;
          previousChildTop = childCurrent.Top;
          trace.AppendFormat("; step {0}: waiting master={1}, child={2}",
                             step, masterCurrent.Top, childCurrent.Top);
          continue;
        }
        dragStarted = true;
        activeMasterStart = previousMasterTop;
        activeChildStart = previousChildTop;
      }
      int masterOffset = masterCurrent.Top - activeMasterStart;
      int childOffset = childCurrent.Top - activeChildStart;
      int frameError = Math.Abs(masterOffset - childOffset);
      maximumError = Math.Max(maximumError, frameError);
      trace.AppendFormat(
          "; step {0}: master={1} ({2}), child={3} ({4}), error={5}",
          step, masterCurrent.Top, masterOffset, childCurrent.Top, childOffset,
          frameError);
      previousMasterTop = masterCurrent.Top;
      previousChildTop = childCurrent.Top;
    }
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(300);
    LastVerticalDragTrace = trace.ToString();
    return dragStarted ? maximumError : Int32.MaxValue;
  }

  public static void MoveFlutterCapsuleToLeftAndFinish(IntPtr window) {
    RECT bounds, workArea;
    if (!GetWindowRect(window, out bounds) ||
        !SystemParametersInfo(0x0030, 0, out workArea, 0)) return;
    int width = bounds.Right - bounds.Left;
    int height = bounds.Bottom - bounds.Top;
    int cursorX = workArea.Left + 24;
    int cursorY = (bounds.Top + bounds.Bottom) / 2;
    SetCursorPos(cursorX, cursorY);
    SetWindowPos(window, IntPtr.Zero, workArea.Left, bounds.Top, width, height,
                 0x0004 | 0x0010);
    SendMessage(window, 0x0232, IntPtr.Zero, IntPtr.Zero);
    System.Threading.Thread.Sleep(500);
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

  public static void DragSettingsBy(IntPtr window, int deltaX, int deltaY) {
    RECT bounds;
    if (!GetWindowRect(window, out bounds)) {
      LastSettingsDragTrace = "initial window geometry unavailable";
      return;
    }
    int startX = (bounds.Left + bounds.Right) / 2;
    // SettingsCoordinatorHitTest reserves 20..64 logical pixels for the
    // native caption. Use its middle instead of the ordinary paper's 17 px
    // Flutter-header drag point.
    int startY = bounds.Top + 32;
    var point = new POINT { X = startX, Y = startY };
    IntPtr hit = WindowFromPoint(point);
    IntPtr root = hit == IntPtr.Zero ? IntPtr.Zero : GetAncestor(hit, 2);
    var hitClass = new System.Text.StringBuilder(128);
    if (hit != IntPtr.Zero) GetClassName(hit, hitClass, hitClass.Capacity);
    long packedPoint = ((long)(ushort)startY << 16) | (ushort)startX;
    long rootHitTest = SendMessage(window, 0x0084, IntPtr.Zero,
                                   new IntPtr(packedPoint)).ToInt64();
    long childHitTest = hit == IntPtr.Zero
      ? -1
      : SendMessage(hit, 0x0084, IntPtr.Zero,
                    new IntPtr(packedPoint)).ToInt64();
    LastSettingsDragTrace = String.Format(
      "before={0},{1},{2},{3};point={4},{5};hit=0x{6:X};hitClass={7};root=0x{8:X};rootHitTest={9};childHitTest={10};foreground=0x{11:X}",
      bounds.Left, bounds.Top, bounds.Right, bounds.Bottom, startX, startY,
      hit.ToInt64(), hitClass.ToString(), root.ToInt64(), rootHitTest,
      childHitTest, GetForegroundWindow().ToInt64());
    SetForegroundWindow(window);
    SetCursorPos(startX, startY);
    System.Threading.Thread.Sleep(80);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    for (int step = 1; step <= 12; step++) {
      SetCursorPos(startX + (deltaX * step / 12),
                   startY + (deltaY * step / 12));
      System.Threading.Thread.Sleep(35);
    }
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(500);
    RECT finalBounds;
    if (GetWindowRect(window, out finalBounds)) {
      LastSettingsDragTrace += String.Format(
        ";after={0},{1},{2},{3};foregroundAfter=0x{4:X}",
        finalBounds.Left, finalBounds.Top, finalBounds.Right,
        finalBounds.Bottom, GetForegroundWindow().ToInt64());
    } else {
      LastSettingsDragTrace += ";final window geometry unavailable";
    }
  }

  public static int[] ResizePaperAndMeasureSurface(
      IntPtr window, int deltaX, int deltaY) {
    RECT start;
    if (window == IntPtr.Zero || !GetWindowRect(window, out start)) {
      return new int[] { Int32.MaxValue, 0, 0, 0 };
    }
    // Pick a visible point inside the bottom-right resize band. Ordinary paper
    // windows expose a painted grip dot near 4 px, while the settings paper's
    // larger rounded corner becomes hit-testable farther inward. Color-key
    // transparent candidates resolve to another root HWND and are skipped.
    int startX = start.Right - 4;
    int startY = start.Bottom - 4;
    int selectedInset = 4;
    foreach (int inset in new int[] { 4, 8, 10, 12 }) {
      POINT candidate = new POINT {
        X = start.Right - inset,
        Y = start.Bottom - inset,
      };
      IntPtr hit = WindowFromPoint(candidate);
      if (hit == window || (hit != IntPtr.Zero &&
                            GetAncestor(hit, 2) == window)) {
        startX = candidate.X;
        startY = candidate.Y;
        selectedInset = inset;
        break;
      }
    }
    POINT selectedPoint = new POINT { X = startX, Y = startY };
    IntPtr selectedHit = WindowFromPoint(selectedPoint);
    IntPtr selectedRoot = selectedHit == IntPtr.Zero
                              ? IntPtr.Zero
                              : GetAncestor(selectedHit, 2);
    long packedPoint = ((long)(ushort)startX) |
                       ((long)(ushort)startY << 16);
    int selectedHitTest = SendMessage(
        window, 0x0084, IntPtr.Zero, new IntPtr(packedPoint)).ToInt32();
    LastResizeTrace = String.Format(
        "start={0}x{1}, inset={2}, point={3},{4}, hit=0x{5:X}, root=0x{6:X}, nchittest={7}",
        start.Right - start.Left, start.Bottom - start.Top, selectedInset,
        startX, startY, selectedHit.ToInt64(), selectedRoot.ToInt64(),
        selectedHitTest);
    IntPtr paperShadow = FindPaperShadowFor(window);
    SetForegroundWindow(window);
    SetCursorPos(startX, startY);
    System.Threading.Thread.Sleep(100);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    int maximumVisibleShadows = 0;
    int minimumPaperAlpha = EffectiveWindowAlpha(window);
    for (int step = 1; step <= 12; step++) {
      SetCursorPos(startX + (deltaX * step / 12),
                   startY + (deltaY * step / 12));
      System.Threading.Thread.Sleep(35);
      RECT interactiveFrame;
      if (GetWindowRect(window, out interactiveFrame) &&
          (interactiveFrame.Right - interactiveFrame.Left !=
               start.Right - start.Left ||
           interactiveFrame.Bottom - interactiveFrame.Top !=
               start.Bottom - start.Top)) {
        // Flutter's edge listener enters the native modal sizing loop through
        // an asynchronous method-channel call. The ordinary shadow is still
        // expected before USER32 changes the first HWND frame; measure only
        // frames whose bounds prove that interactive sizing has begun.
        maximumVisibleShadows = Math.Max(
            maximumVisibleShadows,
            paperShadow != IntPtr.Zero && IsWindowVisible(paperShadow) ? 1 : 0);
        minimumPaperAlpha = Math.Min(
            minimumPaperAlpha, EffectiveWindowAlpha(window));
      }
    }
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(500);
    RECT finalBounds;
    if (!GetWindowRect(window, out finalBounds)) {
      LastResizeTrace += "; final geometry unavailable";
      return new int[] {
          maximumVisibleShadows, minimumPaperAlpha, 0, 0 };
    }
    LastResizeTrace += String.Format(
        "; final={0}x{1}, delta={2},{3}",
        finalBounds.Right - finalBounds.Left,
        finalBounds.Bottom - finalBounds.Top,
        (finalBounds.Right - finalBounds.Left) - (start.Right - start.Left),
        (finalBounds.Bottom - finalBounds.Top) - (start.Bottom - start.Top));
    return new int[] {
        maximumVisibleShadows,
        minimumPaperAlpha,
        (finalBounds.Right - finalBounds.Left) - (start.Right - start.Left),
        (finalBounds.Bottom - finalBounds.Top) - (start.Bottom - start.Top),
    };
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
$dataDirectoryOverrideName = "REPAPERTODO_DATA_DIRECTORY"
$previousDataDirectoryOverride = [Environment]::GetEnvironmentVariable(
  $dataDirectoryOverrideName, "Process")
[Environment]::SetEnvironmentVariable(
  $dataDirectoryOverrideName, (Join-Path $smokeRoot "Release"), "Process")
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
$collapsedPaperCapsuleClickExpands = $false
$paperCollapseThenCapsuleExpands = $false
$paperCapsuleRepeatedCycles = $false
$masterTogglePreservesExpandedPaper = $false
$masterCapsuleRepeatedToggle = $false
$masterCapsuleDragPersistence = $false
$masterCapsuleChildHandlePersists = $false
$masterCapsuleCollapseAlphaMonotonic = $false
$masterCapsuleExpandAlphaMonotonic = $false
$masterCapsuleDragMaxFrameError = [int]::MaxValue
$expandedProxyClickActivates = $false
$expandedProxyDropRouting = $false
$reminderBubbleAdjacent = $false
$reminderBubbleHoverPause = $false
$reminderBubbleClickOpensPaper = $false
$capsuleDropRouting = $false
$contentEditGeometryStable = $false
$interactiveResizeShadowSuppressed = $false
$interactiveResizePaperVisible = $false
$interactiveResizeBoundsChanged = $false
$settingsWindowMovable = $false
$settingsWindowResizable = $false
$desktopPinnedPaperVisible = $false
$desktopPinnedPaperInteractive = $false
$pinnedCapsuleUnpinsAndForegrounds = $false
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
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke desktop-pinned paper did not expose its edge capsule." -Condition {
    [RePaperTodoPolicyNative]::FindWindowByTitle(
      [uint32]$primary.Id,
      "RePaperTodo Native Capsule [proxy:pinned-policy-paper]") -ne [IntPtr]::Zero
  }
  # The first registry frame can be followed immediately by the initial tray
  # and paper-engine reconciliation. Reacquire the stable HWND rather than
  # sending input to a startup-frame handle that may just have been replaced.
  Start-Sleep -Milliseconds 1000
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke desktop-pinned edge capsule did not stabilize." -Condition {
    [RePaperTodoPolicyNative]::FindWindowByTitle(
      [uint32]$primary.Id,
      "RePaperTodo Native Capsule [proxy:pinned-policy-paper]") -ne [IntPtr]::Zero
  }
  $pinnedPaper = [RePaperTodoPolicyNative]::FindWindowByTitleFragment(
    [uint32]$primary.Id, "Pinned QA")
  if ($pinnedPaper -eq [IntPtr]::Zero -or
      -not [RePaperTodoPolicyNative]::IsVisibleInteractiveDesktopPaper($pinnedPaper)) {
    $windows = [RePaperTodoPolicyNative]::VisibleWindowSummary([uint32]$primary.Id)
    throw "Policy smoke desktop-pinned paper did not retain a stable interactive HWND. Visible windows: $windows"
  }
  $desktopPinnedProxy = [RePaperTodoPolicyNative]::FindWindowByTitle(
    [uint32]$primary.Id,
    "RePaperTodo Native Capsule [proxy:pinned-policy-paper]")
  $pinnedActivationMetrics =
    [RePaperTodoPolicyNative]::ClickNativeCapsuleAndSampleForeground(
      $desktopPinnedProxy, $pinnedPaper, 800, 5)
  if ([int]$pinnedActivationMetrics[0] -lt 0) {
    $trace = [RePaperTodoPolicyNative]::LastForegroundTrace
    throw "Policy smoke pinned capsule never foregrounded its paper. Foreground trace: $trace"
  }
  if ([int]$pinnedActivationMetrics[1] -ge 0) {
    $trace = [RePaperTodoPolicyNative]::LastForegroundTrace
    throw "Policy smoke pinned capsule foreground bounced away after activation at $($pinnedActivationMetrics[1]) ms. Foreground trace: $trace"
  }
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke pinned capsule did not unpin and foreground its paper." -Condition {
    if (-not [RePaperTodoPolicyNative]::IsVisible($pinnedPaper) -or
        -not [RePaperTodoPolicyNative]::IsForeground($pinnedPaper)) {
      return $false
    }
    try { $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { return $false }
    $savedPaper = @($saved.papers | Where-Object { $_.id -eq "pinned-policy-paper" })[0]
    $null -ne $savedPaper -and -not [bool]$savedPaper.isPinnedToDesktop
  }
  if (-not [RePaperTodoPolicyNative]::IsVisibleInteractiveDesktopPaper($pinnedPaper)) {
    throw "Policy smoke unpinned paper lost its top-level interactive window style."
  }
  $pinnedCapsuleUnpinsAndForegrounds = $true
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
      },
      [ordered]@{
        id = "collapsed-policy-paper"; type = "note"; title = "Collapsed QA"; x = 680.0; y = 220.0
        width = 360.0; height = 280.0; isVisible = $true; alwaysOnTop = $false
        isCollapsed = $true; isPinnedToDesktop = $false; items = @()
        content = "A normal collapsed paper must expand from its own capsule."
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
  try {
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke expanded paper did not finish its initial window reconciliation." -Condition {
      $candidate = [RePaperTodoPolicyNative]::FindWindowByTitleFragment(
        [uint32]$primary.Id, "Policy")
      $candidate -ne [IntPtr]::Zero -and
        [RePaperTodoPolicyNative]::CapsuleWindowWidth($candidate) -eq 360
    }
  } catch {
    $windows = [RePaperTodoPolicyNative]::VisibleWindowSummary([uint32]$primary.Id)
    throw "Policy smoke expanded paper did not finish its initial window reconciliation. Visible windows: $windows"
  }
  $paper = [RePaperTodoPolicyNative]::FindWindowByTitleFragment(
    [uint32]$primary.Id, "Policy")
  if ($paper -eq [IntPtr]::Zero -or
      [RePaperTodoPolicyNative]::CapsuleWindowWidth($paper) -ne 360) {
    throw "Policy smoke master collapse hid or resized an expanded paper."
  }
  Start-Sleep -Milliseconds 3000
  $masterCapsule = [RePaperTodoPolicyNative]::FindCapsule([uint32]$primary.Id)
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
  try {
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke did not reconcile native master/proxy surfaces after expanding the queue." -Condition {
      ([RePaperTodoPolicyNative]::FindWindowByTitleFragment([uint32]$primary.Id, "Native Capsule [master:") -ne [IntPtr]::Zero) -and
      ([RePaperTodoPolicyNative]::FindWindowByTitle([uint32]$primary.Id, "RePaperTodo Native Capsule [proxy:policy-paper]") -ne [IntPtr]::Zero)
    }
  } catch {
    $windows = [RePaperTodoPolicyNative]::VisibleWindowSummary([uint32]$primary.Id)
    throw "Policy smoke did not reconcile native master/proxy surfaces after expanding the queue. Visible windows: $windows"
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
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke could not identify the normal collapsed paper capsule." -Condition {
    [RePaperTodoPolicyNative]::FindWindowByTitle(
      [uint32]$primary.Id, "Collap") -ne [IntPtr]::Zero
  }
  $collapsedPaperCapsule = [RePaperTodoPolicyNative]::FindWindowByTitle(
    [uint32]$primary.Id, "Collap")
  $collapsedPaperCapsuleDebug =
    [RePaperTodoPolicyNative]::CapsuleActionPointSummary($collapsedPaperCapsule)
  [RePaperTodoPolicyNative]::ClickCapsule($collapsedPaperCapsule)
  try {
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke normal collapsed paper capsule did not expand its paper." -Condition {
      $expandedCollapsedPaper = [RePaperTodoPolicyNative]::FindWindowByTitleFragment(
        [uint32]$primary.Id, "Collap")
      $expandedCollapsedPaper -ne [IntPtr]::Zero -and
        [RePaperTodoPolicyNative]::CapsuleWindowWidth($expandedCollapsedPaper) -eq 360
    }
  } catch {
    $windows = [RePaperTodoPolicyNative]::VisibleWindowSummary([uint32]$primary.Id)
    throw "Policy smoke normal collapsed paper capsule did not expand its paper. Click target: $collapsedPaperCapsuleDebug. Visible windows: $windows"
  }
  $collapsedPaperCapsuleClickExpands = $true
  $masterHandleBeforeToggle = $nativeMaster
  $proxyHandleBeforeToggle = $expandedProxy
  $collapseAlphaSamples =
    [RePaperTodoPolicyNative]::ClickNativeCapsuleAndSampleAlpha(
      $nativeMaster, $expandedProxy, 800, 8)
  Assert-MonotonicAlpha -Samples $collapseAlphaSamples -Increasing $false `
    -Message "Policy smoke master collapse flashed a child capsule."
  $masterCapsuleCollapseAlphaMonotonic = $true
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke master capsule did not collapse its child capsule queue on the second toggle." -Condition {
    [RePaperTodoPolicyNative]::CountCapsules([uint32]$primary.Id) -eq 1
  }
  if (-not [RePaperTodoPolicyNative]::IsWindowHandle($proxyHandleBeforeToggle)) {
    throw "Policy smoke master collapse destroyed its retained child capsule HWND."
  }
  if (-not [RePaperTodoPolicyNative]::IsVisible($paper) -or
      [RePaperTodoPolicyNative]::CapsuleWindowWidth($paper) -ne 360) {
    throw "Policy smoke repeated master collapse changed the expanded paper surface."
  }
  $masterTogglePreservesExpandedPaper = $true
  $expandAlphaSamples =
    [RePaperTodoPolicyNative]::ClickNativeCapsuleAndSampleAlpha(
      $nativeMaster, $expandedProxy, 800, 8)
  Assert-MonotonicAlpha -Samples $expandAlphaSamples -Increasing $true `
    -Message "Policy smoke master expansion flashed a child capsule."
  $masterCapsuleExpandAlphaMonotonic = $true
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke master capsule did not restore all child capsules after a repeated toggle." -Condition {
    ([RePaperTodoPolicyNative]::FindWindowByTitle(
      [uint32]$primary.Id, "RePaperTodo Native Capsule [proxy:policy-paper]") -ne [IntPtr]::Zero) -and
    ([RePaperTodoPolicyNative]::FindWindowByTitle(
      [uint32]$primary.Id, "Long s") -ne [IntPtr]::Zero) -and
    ([RePaperTodoPolicyNative]::FindWindowByTitle(
      [uint32]$primary.Id, "Remind") -ne [IntPtr]::Zero)
  }
  $nativeMaster = [RePaperTodoPolicyNative]::FindWindowByTitleFragment(
    [uint32]$primary.Id, "Native Capsule [master:")
  $expandedProxy = [RePaperTodoPolicyNative]::FindWindowByTitle(
    [uint32]$primary.Id, "RePaperTodo Native Capsule [proxy:policy-paper]")
  if ($nativeMaster -ne $masterHandleBeforeToggle -or
      $expandedProxy -ne $proxyHandleBeforeToggle) {
    throw "Policy smoke master toggle recreated a retained master/proxy capsule HWND."
  }
  $masterCapsuleChildHandlePersists = $true
  $masterCapsuleRepeatedToggle = $true

  # Exercise the user-facing path: collapse the real Flutter paper from its
  # header, then click the paper's own capsule HWND to restore the paper.
  # This catches stale child-engine geometry and native capsule registries
  # that seeded collapsed papers do not exercise.
  [RePaperTodoPolicyNative]::ClickRelative($paper, 336, 24)
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke paper header collapse did not persist." -Condition {
    try { $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { return $false }
    $savedPaper = @($saved.papers | Where-Object { $_.id -eq "policy-paper" })[0]
    $null -ne $savedPaper -and [bool]$savedPaper.isCollapsed
  }
  try {
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke collapsed paper HWND did not become a capsule." -Condition {
    $collapsed = [RePaperTodoPolicyNative]::FindWindowByTitleFragment([uint32]$primary.Id, "Policy")
      $collapsed -ne [IntPtr]::Zero -and
        [RePaperTodoPolicyNative]::CapsuleWindowWidth($collapsed) -lt 220
    }
  } catch {
    $windows = [RePaperTodoPolicyNative]::VisibleWindowSummary([uint32]$primary.Id)
    throw "Policy smoke collapsed paper HWND did not become a perceptible capsule. Visible windows: $windows"
  }
  $collapsed = [RePaperTodoPolicyNative]::FindWindowByTitleFragment(
    [uint32]$primary.Id, "Policy")
  [RePaperTodoPolicyNative]::ClickCapsule($collapsed)
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke paper capsule did not restore the collapsed paper." -Condition {
    try { $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { return $false }
    $savedPaper = @($saved.papers | Where-Object { $_.id -eq "policy-paper" })[0]
    $expanded = [RePaperTodoPolicyNative]::FindWindowByTitleFragment([uint32]$primary.Id, "Policy")
    $null -ne $savedPaper -and -not [bool]$savedPaper.isCollapsed -and
      $expanded -ne [IntPtr]::Zero -and
      [RePaperTodoPolicyNative]::CapsuleWindowWidth($expanded) -eq 360
  }
  $paperCollapseThenCapsuleExpands = $true
  for ($cycle = 1; $cycle -le 3; $cycle++) {
    $paper = [RePaperTodoPolicyNative]::FindWindowByTitleFragment(
      [uint32]$primary.Id, "Policy")
    if ($paper -eq [IntPtr]::Zero -or
        [RePaperTodoPolicyNative]::CapsuleWindowWidth($paper) -ne 360) {
      $windows = [RePaperTodoPolicyNative]::VisibleWindowSummary([uint32]$primary.Id)
      throw "Policy smoke repeated paper cycle $cycle could not reacquire the expanded paper HWND. Visible windows: $windows"
    }
    [RePaperTodoPolicyNative]::ClickRelative($paper, 336, 24)
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke repeated paper collapse cycle $cycle did not persist." -Condition {
      try { $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { return $false }
      $savedPaper = @($saved.papers | Where-Object { $_.id -eq "policy-paper" })[0]
      $null -ne $savedPaper -and [bool]$savedPaper.isCollapsed
    }
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke repeated paper collapse cycle $cycle did not reach capsule geometry." -Condition {
      $candidate = [RePaperTodoPolicyNative]::FindWindowByTitleFragment(
        [uint32]$primary.Id, "Policy")
      $candidate -ne [IntPtr]::Zero -and
        [RePaperTodoPolicyNative]::CapsuleWindowWidth($candidate) -lt 220
    }
    $collapsed = [RePaperTodoPolicyNative]::FindWindowByTitleFragment(
      [uint32]$primary.Id, "Policy")
    [RePaperTodoPolicyNative]::ClickCapsule($collapsed)
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke repeated paper capsule cycle $cycle did not expand." -Condition {
      try { $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { return $false }
      $savedPaper = @($saved.papers | Where-Object { $_.id -eq "policy-paper" })[0]
      $expanded = [RePaperTodoPolicyNative]::FindWindowByTitleFragment([uint32]$primary.Id, "Policy")
      $null -ne $savedPaper -and -not [bool]$savedPaper.isCollapsed -and
        $expanded -ne [IntPtr]::Zero -and
        [RePaperTodoPolicyNative]::CapsuleWindowWidth($expanded) -eq 360
    }
    $nativeMaster = [RePaperTodoPolicyNative]::FindWindowByTitleFragment(
      [uint32]$primary.Id, "Native Capsule [master:")
    [RePaperTodoPolicyNative]::ClickNativeCapsule($nativeMaster)
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke repeated master collapse cycle $cycle did not retract child capsules." -Condition {
      [RePaperTodoPolicyNative]::CountCapsules([uint32]$primary.Id) -eq 1
    }
    [RePaperTodoPolicyNative]::ClickNativeCapsule($nativeMaster)
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke repeated master expand cycle $cycle did not restore child capsules." -Condition {
      [RePaperTodoPolicyNative]::FindWindowByTitle(
        [uint32]$primary.Id, "RePaperTodo Native Capsule [proxy:policy-paper]") -ne [IntPtr]::Zero -and
      [RePaperTodoPolicyNative]::FindWindowByTitle(
        [uint32]$primary.Id, "Long s") -ne [IntPtr]::Zero
    }
  }
  $paperCapsuleRepeatedCycles = $true
  $expandedProxy = [RePaperTodoPolicyNative]::FindWindowByTitle(
    [uint32]$primary.Id, "RePaperTodo Native Capsule [proxy:policy-paper]")
  $masterCapsuleDragMaxFrameError =
    [RePaperTodoPolicyNative]::MeasureVerticalDragFollowing(
      $nativeMaster, $expandedProxy, 64)
  if ($masterCapsuleDragMaxFrameError -gt 2) {
    $dragTrace = [RePaperTodoPolicyNative]::LastVerticalDragTrace
    throw "Policy smoke child capsules did not follow the master in the same animation frame (maximum error=$masterCapsuleDragMaxFrameError px). Trace: $dragTrace"
  }
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
  $paper = [RePaperTodoPolicyNative]::FindWindowByTitleFragment([uint32]$primary.Id, "Policy")
  if ($paper -eq [IntPtr]::Zero) {
    throw "Policy smoke could not identify the expanded proxy's owning paper."
  }
  $reminderPaper = [RePaperTodoPolicyNative]::FindWindowByTitle([uint32]$primary.Id, "Remind")
  [RePaperTodoPolicyNative]::SetForegroundWindow($reminderPaper) | Out-Null
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke could not move focus away from the expanded proxy's paper." -Condition {
    [RePaperTodoPolicyNative]::IsForeground($reminderPaper)
  }
  [RePaperTodoPolicyNative]::ClickNativeCapsule($expandedProxy)
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke expanded edge proxy did not foreground its owning paper." -Condition {
    [RePaperTodoPolicyNative]::IsVisible($paper) -and
      [RePaperTodoPolicyNative]::IsForeground($paper)
  }
  $expandedProxyClickActivates = $true
  if ([RePaperTodoPolicyNative]::CapsuleWindowWidth($paper) -ne 360) {
    [RePaperTodoPolicyNative]::ClickCapsule($paper)
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke routed proxy paper did not expand from its real capsule." -Condition {
      [RePaperTodoPolicyNative]::CapsuleWindowWidth($paper) -eq 360
    }
  }
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
  try {
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke paper did not avoid the fullscreen foreground window." -Condition {
      -not [RePaperTodoPolicyNative]::IsTopmost($paper)
    }
  } catch {
    $paperBounds = [RePaperTodoPolicyNative]::BoundsString($paper)
    $fullscreenBounds = [RePaperTodoPolicyNative]::BoundsString($fullscreenWindow)
    $foregroundPid = [RePaperTodoPolicyNative]::ForegroundProcessId()
    $paperTopmost = [RePaperTodoPolicyNative]::IsTopmost($paper)
    throw "Policy smoke paper did not avoid the fullscreen foreground window (paperBounds=$paperBounds, fullscreenBounds=$fullscreenBounds, foregroundPid=$foregroundPid, expectedForegroundPid=$($fullscreen.Id), paperTopmost=$paperTopmost)."
  }
  $fullscreenAvoided = $true
  Stop-Process -Id $fullscreen.Id -Force -ErrorAction SilentlyContinue
  $fullscreen = $null
  # The shell may restore a different maximized/fullscreen application after
  # the probe exits (for example the test host itself). In that state keeping
  # papers non-topmost is correct. Explicitly return foreground ownership to a
  # RePaperTodo paper before asserting the no-fullscreen restoration path.
  [RePaperTodoPolicyNative]::SetForegroundWindow($reminderPaper) | Out-Null
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke could not return foreground ownership to RePaperTodo after fullscreen closed." -Condition {
    [RePaperTodoPolicyNative]::ForegroundProcessId() -eq $primary.Id
  }
  Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke paper did not restore topmost after fullscreen closed." -Condition {
    [RePaperTodoPolicyNative]::IsTopmost($paper)
  }
  $fullscreenRestored = $true

  $paper = [RePaperTodoPolicyNative]::FindWindowByTitleFragment([uint32]$primary.Id, "Policy")
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
    try {
      if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { return $false }
      $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    } catch { return $false }
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
    try {
      if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { return $false }
      $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    } catch { return $false }
    $paperState = @($saved.papers | Where-Object { $_.id -eq "policy-paper" })[0]
    $null -ne $paperState -and
      (([int][Math]::Round([double]$paperState.x)) -ne 220 -or
       ([int][Math]::Round([double]$paperState.y)) -ne 160)
  }

  $resizeMetrics = [RePaperTodoPolicyNative]::ResizePaperAndMeasureSurface(
    $paper, 96, 72)
  if ($resizeMetrics.Count -ne 4) {
    throw "Policy smoke paper resize did not return complete frame metrics."
  }
  if ([int]$resizeMetrics[0] -ne 0) {
    throw "Policy smoke paper shadow remained visible during interactive resize (maximum visible shadows=$($resizeMetrics[0]))."
  }
  $interactiveResizeShadowSuppressed = $true
  if ([int]$resizeMetrics[1] -le 0) {
    throw "Policy smoke paper became fully transparent during interactive resize."
  }
  $interactiveResizePaperVisible = $true
  if ([Math]::Abs([int]$resizeMetrics[2]) -lt 48 -or
      [Math]::Abs([int]$resizeMetrics[3]) -lt 36) {
    $resizeTrace = [RePaperTodoPolicyNative]::LastResizeTrace
    throw "Policy smoke paper resize did not change the HWND by the requested amount (widthDelta=$($resizeMetrics[2]), heightDelta=$($resizeMetrics[3])). Trace: $resizeTrace"
  }
  $interactiveResizeBoundsChanged = $true

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
  $scriptPaper = [RePaperTodoPolicyNative]::FindWindowByTitle([uint32]$primary.Id, "Long s")
  if ($scriptPaper -eq [IntPtr]::Zero) {
    throw "Policy smoke script capsule disappeared before drag validation."
  }
  [RePaperTodoPolicyNative]::MoveFlutterCapsuleToLeftAndFinish($scriptPaper)
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
  # IsVisible can turn true in the same dispatch that asks Flutter to build the
  # settings page. A human cannot press the title in that sub-frame, so wait
  # for the first interactive Flutter frame before injecting mouse input.
  Start-Sleep -Milliseconds 250
  $settingsBoundsBeforeMove =
    [RePaperTodoPolicyNative]::BoundsString($coordinator)
  [RePaperTodoPolicyNative]::DragSettingsBy($coordinator, 84, 58)
  try {
    Wait-ForCondition -TimeoutSeconds 10 -Message "Policy smoke settings window could not be moved from its paper header." -Condition {
      [RePaperTodoPolicyNative]::BoundsString($coordinator) -ne
        $settingsBoundsBeforeMove
    }
  } catch {
    $settingsDragTrace = [RePaperTodoPolicyNative]::LastSettingsDragTrace
    throw "Policy smoke settings window could not be moved from its paper header. Trace: $settingsDragTrace"
  }
  $settingsWindowMovable = $true
  $settingsResizeMetrics =
    [RePaperTodoPolicyNative]::ResizePaperAndMeasureSurface(
      $coordinator, 90, 64)
  if ([Math]::Abs([int]$settingsResizeMetrics[2]) -lt 45 -or
      [Math]::Abs([int]$settingsResizeMetrics[3]) -lt 32) {
    $resizeTrace = [RePaperTodoPolicyNative]::LastResizeTrace
    throw "Policy smoke settings window could not be resized (widthDelta=$($settingsResizeMetrics[2]), heightDelta=$($settingsResizeMetrics[3])). Trace: $resizeTrace"
  }
  $settingsWindowResizable = $true
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
       collapsedPaperCapsuleClickExpands = $collapsedPaperCapsuleClickExpands
       paperCollapseThenCapsuleExpands = $paperCollapseThenCapsuleExpands
       paperCapsuleRepeatedCycles = $paperCapsuleRepeatedCycles
       masterTogglePreservesExpandedPaper = $masterTogglePreservesExpandedPaper
      masterCapsuleRepeatedToggle = $masterCapsuleRepeatedToggle
      masterCapsuleDragPersistence = $masterCapsuleDragPersistence
      masterCapsuleChildHandlePersists = $masterCapsuleChildHandlePersists
      masterCapsuleCollapseAlphaMonotonic = $masterCapsuleCollapseAlphaMonotonic
      masterCapsuleExpandAlphaMonotonic = $masterCapsuleExpandAlphaMonotonic
      masterCapsuleDragMaxFrameError = $masterCapsuleDragMaxFrameError
      expandedProxyClickActivates = $expandedProxyClickActivates
      expandedProxyDropRouting = $expandedProxyDropRouting
      reminderBubbleAdjacent = $reminderBubbleAdjacent
      reminderBubbleHoverPause = $reminderBubbleHoverPause
      reminderBubbleClickOpensPaper = $reminderBubbleClickOpensPaper
      capsuleDropRouting = $capsuleDropRouting
      contentEditGeometryStable = $contentEditGeometryStable
      interactiveResizeShadowSuppressed = $interactiveResizeShadowSuppressed
      interactiveResizePaperVisible = $interactiveResizePaperVisible
      interactiveResizeBoundsChanged = $interactiveResizeBoundsChanged
      settingsWindowMovable = $settingsWindowMovable
      settingsWindowResizable = $settingsWindowResizable
      settingsDragTrace = [RePaperTodoPolicyNative]::LastSettingsDragTrace
      desktopPinnedPaperVisible = $desktopPinnedPaperVisible
      desktopPinnedPaperInteractive = $desktopPinnedPaperInteractive
      pinnedCapsuleUnpinsAndForegrounds = $pinnedCapsuleUnpinsAndForegrounds
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resultPath -Encoding ascii
  }
  Write-Host "Windows policy smoke passed: tray recovery, fullscreen avoidance, and long-running script capsules verified."
} catch {
  $failure = $_
  throw
} finally {
  [Environment]::SetEnvironmentVariable(
    $dataDirectoryOverrideName, $previousDataDirectoryOverride, "Process")
  if ($null -ne $fullscreen -and -not $fullscreen.HasExited) { Stop-Process -Id $fullscreen.Id -Force -ErrorAction SilentlyContinue }
  if ($null -ne $primary -and -not $primary.HasExited) { Stop-Process -Id $primary.Id -Force -ErrorAction SilentlyContinue }
  if ($null -eq $failure -and (Test-Path -LiteralPath $smokeRoot)) {
    Remove-Item -LiteralPath $smokeRoot -Recurse -Force -ErrorAction SilentlyContinue
  } elseif ($null -ne $failure) {
    Write-Warning "Windows policy smoke failure artifacts were preserved at $smokeRoot"
  }
}
