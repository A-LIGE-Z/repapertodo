param(
  [string]$ReleaseDirectory = "",
  [int]$StartupTimeoutSeconds = 30,
  [int]$ExitTimeoutSeconds = 30,
  [string]$ResultJson = ""
)

$ErrorActionPreference = "Stop"

function Assert-WindowsHost {
  if (-not ($IsWindows -or $env:OS -eq "Windows_NT")) {
    throw "Windows release smoke tests can only run on Windows."
  }
}

function Assert-NoExistingRePaperTodoProcess {
  $processes = @(Get-Process -Name "repapertodo" -ErrorAction SilentlyContinue)
  if ($processes.Count -gt 0) {
    $processIds = ($processes | ForEach-Object { $_.Id }) -join ", "
    throw "Close existing RePaperTodo processes before running the Windows smoke test. Running process IDs: $processIds"
  }
}

function Assert-PathInside {
  param(
    [string]$Path,
    [string]$ParentPath,
    [string]$Message
  )

  $resolvedPath = [IO.Path]::GetFullPath($Path)
  $resolvedParent = [IO.Path]::GetFullPath($ParentPath)
  if (-not $resolvedParent.EndsWith([IO.Path]::DirectorySeparatorChar)) {
    $resolvedParent = "$resolvedParent$([IO.Path]::DirectorySeparatorChar)"
  }
  if ($resolvedPath -eq $resolvedParent.TrimEnd([IO.Path]::DirectorySeparatorChar) -or
      -not $resolvedPath.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw $Message
  }
}

function Wait-ForCondition {
  param(
    [scriptblock]$Condition,
    [int]$TimeoutSeconds,
    [string]$TimeoutMessage
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (& $Condition) {
      return
    }
    Start-Sleep -Milliseconds 250
  }
  throw $TimeoutMessage
}

function Get-PaperCount {
  param([string]$StateFile)

  $counts = Get-PaperTypeCounts -StateFile $StateFile
  return [int]$counts.total
}

function Get-VisiblePaperCount {
  param([string]$StateFile)

  if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
    return 0
  }
  try {
    $state = Get-Content -Raw -LiteralPath $StateFile | ConvertFrom-Json
    $visibleCount = 0
    foreach ($paper in @($state.papers)) {
      if ([bool]$paper.isVisible) {
        $visibleCount += 1
      }
    }
    return $visibleCount
  } catch {
    return 0
  }
}

function Initialize-WindowEnumerator {
  if ("RePaperTodoSmokeWindowEnumerator" -as [type]) {
    return
  }
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class RePaperTodoSmokeWindowEnumerator {
  public delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

  [DllImport("user32.dll")]
  private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);

  [DllImport("user32.dll")]
  private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

  [DllImport("kernel32.dll")]
  private static extern uint GetCurrentThreadId();

  [DllImport("user32.dll")]
  private static extern bool IsWindowVisible(IntPtr window);

  [DllImport("user32.dll")]
  private static extern bool GetWindowRect(IntPtr window, out RECT bounds);

  [DllImport("user32.dll")]
  private static extern uint GetDpiForWindow(IntPtr window);

  [DllImport("user32.dll")]
  private static extern bool GetCursorPos(out POINT point);

  [DllImport("user32.dll")]
  private static extern bool SetCursorPos(int x, int y);

  [DllImport("user32.dll")]
  private static extern bool SetForegroundWindow(IntPtr window);

  [DllImport("user32.dll")]
  private static extern IntPtr GetForegroundWindow();

  [DllImport("user32.dll")]
  private static extern bool AttachThreadInput(uint attachThread,
                                                uint attachToThread,
                                                bool attach);

  [DllImport("user32.dll")]
  private static extern IntPtr SetActiveWindow(IntPtr window);

  [DllImport("user32.dll")]
  private static extern IntPtr SetFocus(IntPtr window);

  [DllImport("user32.dll")]
  private static extern bool ShowWindow(IntPtr window, int command);

  [DllImport("user32.dll")]
  private static extern void SwitchToThisWindow(IntPtr window, bool altTab);

  [DllImport("user32.dll")]
  private static extern bool BringWindowToTop(IntPtr window);

  [DllImport("user32.dll")]
  private static extern void mouse_event(uint flags, uint dx, uint dy,
                                         uint data, UIntPtr extraInfo);

  [DllImport("user32.dll", SetLastError = true)]
  private static extern uint SendInput(uint inputCount, INPUT[] inputs,
                                       int inputSize);

  [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
  private static extern IntPtr GetWindowLongPtr(IntPtr window, int index);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  private static extern int GetWindowText(IntPtr window,
                                          System.Text.StringBuilder text,
                                          int maximum);

  [DllImport("user32.dll")]
  private static extern bool PostMessage(IntPtr window, uint message,
                                         IntPtr wParam, IntPtr lParam);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  private static extern IntPtr GetProp(IntPtr window, string name);

  [DllImport("user32.dll")]
  private static extern IntPtr GetWindow(IntPtr window, uint command);

  [DllImport("user32.dll", SetLastError = true)]
  private static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter,
                                          int x, int y, int width, int height,
                                          uint flags);

  private struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  private struct POINT {
    public int X;
    public int Y;
  }

  [StructLayout(LayoutKind.Sequential)]
  private struct INPUT {
    public uint Type;
    public INPUTUNION Data;
  }

  [StructLayout(LayoutKind.Explicit)]
  private struct INPUTUNION {
    [FieldOffset(0)]
    public MOUSEINPUT Mouse;

    [FieldOffset(0)]
    public KEYBDINPUT Keyboard;
  }

  [StructLayout(LayoutKind.Sequential)]
  private struct MOUSEINPUT {
    public int X;
    public int Y;
    public uint MouseData;
    public uint Flags;
    public uint Time;
    public UIntPtr ExtraInfo;
  }

  [StructLayout(LayoutKind.Sequential)]
  private struct KEYBDINPUT {
    public ushort VirtualKey;
    public ushort ScanCode;
    public uint Flags;
    public UIntPtr Time;
    public IntPtr ExtraInfo;
  }

  private static bool IsIndependentPaperWindow(IntPtr window,
                                                uint expectedProcessId) {
    uint processId;
    GetWindowThreadProcessId(window, out processId);
    if (processId != expectedProcessId || !IsWindowVisible(window)) {
      return false;
    }
    const long WS_THICKFRAME = 0x00040000L;
    long style = GetWindowLongPtr(window, -16).ToInt64();
    if ((style & WS_THICKFRAME) == 0) {
      return false;
    }
    RECT bounds;
    if (!GetWindowRect(window, out bounds)) {
      return false;
    }
    // The settings coordinator uses the large desktop viewport. Independent
    // paper windows in this smoke use compact persisted paper dimensions.
    return bounds.Right - bounds.Left < 800 ||
           bounds.Bottom - bounds.Top < 500;
  }

  public static int CountVisibleTopLevelWindows(uint expectedProcessId) {
    var count = 0;
    EnumWindows((window, parameter) => {
      uint processId;
      GetWindowThreadProcessId(window, out processId);
      if (processId == expectedProcessId && IsWindowVisible(window)) {
        count += 1;
      }
      return true;
    }, IntPtr.Zero);
    return count;
  }

  public static int CountVisiblePaperWindows(uint expectedProcessId) {
    var count = 0;
    EnumWindows((window, parameter) => {
      if (IsIndependentPaperWindow(window, expectedProcessId)) {
        count += 1;
      }
      return true;
    }, IntPtr.Zero);
    return count;
  }

  public static int CountVisibleNativeCapsuleWindows(uint expectedProcessId) {
    var count = 0;
    EnumWindows((window, parameter) => {
      uint processId;
      GetWindowThreadProcessId(window, out processId);
      if (processId != expectedProcessId || !IsWindowVisible(window)) {
        return true;
      }
      var title = new System.Text.StringBuilder(256);
      GetWindowText(window, title, title.Capacity);
      if (title.ToString().StartsWith("RePaperTodo Native Capsule [",
                                      StringComparison.Ordinal)) {
        count += 1;
      }
      return true;
    }, IntPtr.Zero);
    return count;
  }

  public static long FindVisibleCoordinatorWindow(uint expectedProcessId) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      uint processId;
      GetWindowThreadProcessId(window, out processId);
      if (processId != expectedProcessId || !IsWindowVisible(window)) {
        return true;
      }
      RECT bounds;
      if (GetWindowRect(window, out bounds) &&
          bounds.Right - bounds.Left >= 800 &&
          bounds.Bottom - bounds.Top >= 500) {
        result = window;
        return false;
      }
      return true;
    }, IntPtr.Zero);
    return result.ToInt64();
  }

  public static long FindVisiblePaperWindow(uint expectedProcessId) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      if (IsIndependentPaperWindow(window, expectedProcessId)) {
        result = window;
        return false;
      }
      return true;
    }, IntPtr.Zero);
    return result.ToInt64();
  }

  public static bool MoveResizeWindow(long window, int x, int y,
                                      int width, int height) {
    const uint SWP_NOZORDER = 0x0004;
    const uint SWP_NOACTIVATE = 0x0010;
    return window != 0 && SetWindowPos(new IntPtr(window), IntPtr.Zero,
                                      x, y, width, height,
                                      SWP_NOZORDER | SWP_NOACTIVATE);
  }

  public static int DragRightEdgeToResize(long window, int delta) {
    if (window == 0 || delta < 20) return Int32.MinValue;
    var handle = new IntPtr(window);
    RECT before;
    if (!GetWindowRect(handle, out before)) return Int32.MinValue + 1;
    const uint GW_CHILD = 5;
    var child = GetWindow(handle, GW_CHILD);
    RECT interactiveBounds;
    if (child == IntPtr.Zero || !GetWindowRect(child, out interactiveBounds)) {
      return Int32.MinValue + 2;
    }
    POINT original;
    var restoreCursor = GetCursorPos(out original);
    var x = interactiveBounds.Right - 10;
    var y = interactiveBounds.Top +
            ((interactiveBounds.Bottom - interactiveBounds.Top) / 2);
    try {
      ShowWindow(handle, 5);
      BringWindowToTop(handle);
      SwitchToThisWindow(handle, true);
      SetForegroundWindow(handle);
      SetCursorPos(x, y);
      System.Threading.Thread.Sleep(250);
      const uint MOUSEEVENTF_MOVE = 0x0001;
      const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
      const uint MOUSEEVENTF_LEFTUP = 0x0004;
      mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
      System.Threading.Thread.Sleep(700);
      for (var step = 1; step <= 8; step += 1) {
        SetCursorPos(x + ((delta * step) / 8), y);
        mouse_event(MOUSEEVENTF_MOVE, 1, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(100);
      }
      mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
      System.Threading.Thread.Sleep(400);
    } finally {
      if (restoreCursor) SetCursorPos(original.X, original.Y);
    }
    RECT after;
    if (!GetWindowRect(handle, out after)) return Int32.MinValue + 3;
    return (after.Right - after.Left) - (before.Right - before.Left);
  }

  public static int LastResizeHitTest(long window) {
    if (window == 0) return 0;
    return GetProp(new IntPtr(window), "RePaperTodo.ResizeHitTest").ToInt32();
  }

  public static int[] GetBounds(long window) {
    RECT bounds;
    if (window == 0 ||
        !GetWindowRect(new IntPtr(window), out bounds)) {
      return null;
    }
    return new[] {
      bounds.Left,
      bounds.Top,
      bounds.Right - bounds.Left,
      bounds.Bottom - bounds.Top
    };
  }

  public static int EditTodoText(long window, string text) {
    if (window == 0 || String.IsNullOrEmpty(text)) {
      return -1;
    }
    var handle = new IntPtr(window);
    RECT bounds;
    if (!GetWindowRect(handle, out bounds)) {
      return -2;
    }
    var width = bounds.Right - bounds.Left;
    var height = bounds.Bottom - bounds.Top;
    if (width < 160 || height < 100) {
      return -3;
    }

    POINT originalCursor;
    var restoreCursor = GetCursorPos(out originalCursor);
    uint processId;
    var targetThread = GetWindowThreadProcessId(handle, out processId);
    var currentThread = GetCurrentThreadId();
    var attached = targetThread != 0 && targetThread != currentThread &&
                   AttachThreadInput(currentThread, targetThread, true);
    try {
      ShowWindow(handle, 5);
      BringWindowToTop(handle);
      SwitchToThisWindow(handle, true);
      SetForegroundWindow(handle);
      SetActiveWindow(handle);
      SetFocus(handle);
      System.Threading.Thread.Sleep(200);

      // PaperTodo's compact title bar is 31px high. The first todo text field
      // begins immediately below it, after the leading checkbox hit area.
      var dpi = GetDpiForWindow(handle);
      var scale = dpi == 0 ? 1.0 : dpi / 96.0;
      var logicalTextX = (int)Math.Round(92 * scale);
      var logicalTextY = (int)Math.Round(56 * scale);
      var clickX = bounds.Left +
                   Math.Min(width - 64, Math.Max(logicalTextX, width / 3));
      var clickY = bounds.Top + Math.Min(height - 40, logicalTextY);
      if (!SetCursorPos(clickX, clickY)) {
        return -4;
      }
      const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
      const uint MOUSEEVENTF_LEFTUP = 0x0004;
      mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
      mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
      System.Threading.Thread.Sleep(250);
      if (GetForegroundWindow() != handle) {
        return -5;
      }

      const uint INPUT_KEYBOARD = 1;
      const uint KEYEVENTF_KEYUP = 0x0002;
      const uint KEYEVENTF_UNICODE = 0x0004;
      var inputs = new INPUT[text.Length * 2];
      for (var index = 0; index < text.Length; index += 1) {
        inputs[index * 2] = new INPUT {
          Type = INPUT_KEYBOARD,
          Data = new INPUTUNION {
            Keyboard = new KEYBDINPUT {
              VirtualKey = 0,
              ScanCode = text[index],
              Flags = KEYEVENTF_UNICODE,
              Time = UIntPtr.Zero,
              ExtraInfo = IntPtr.Zero
            }
          }
        };
        inputs[(index * 2) + 1] = new INPUT {
          Type = INPUT_KEYBOARD,
          Data = new INPUTUNION {
            Keyboard = new KEYBDINPUT {
              VirtualKey = 0,
              ScanCode = text[index],
              Flags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP,
              Time = UIntPtr.Zero,
              ExtraInfo = IntPtr.Zero
            }
          }
        };
      }
      var sent = SendInput((uint)inputs.Length, inputs,
                           Marshal.SizeOf(typeof(INPUT)));
      return sent == (uint)inputs.Length ? 1 : -6;
    } finally {
      if (restoreCursor) {
        SetCursorPos(originalCursor.X, originalCursor.Y);
      }
      if (attached) {
        AttachThreadInput(currentThread, targetThread, false);
      }
    }
  }

  public static bool CloseWindow(long window) {
    return window != 0 && PostMessage(new IntPtr(window), 0x0010,
                                      IntPtr.Zero, IntPtr.Zero);
  }
}
"@ | Out-Null
}

function Get-VisibleTopLevelWindowCount {
  param([int]$ProcessId)

  Initialize-WindowEnumerator
  return [RePaperTodoSmokeWindowEnumerator]::CountVisibleTopLevelWindows(
    [uint32]$ProcessId)
}

function Get-VisiblePaperWindowCount {
  param([int]$ProcessId)

  Initialize-WindowEnumerator
  return [RePaperTodoSmokeWindowEnumerator]::CountVisiblePaperWindows(
    [uint32]$ProcessId)
}

function Get-VisibleNativeCapsuleWindowCount {
  param([int]$ProcessId)

  Initialize-WindowEnumerator
  return [RePaperTodoSmokeWindowEnumerator]::CountVisibleNativeCapsuleWindows(
    [uint32]$ProcessId)
}

function Get-VisibleCoordinatorWindow {
  param([int]$ProcessId)

  Initialize-WindowEnumerator
  return [RePaperTodoSmokeWindowEnumerator]::FindVisibleCoordinatorWindow(
    [uint32]$ProcessId)
}

function Get-VisiblePaperWindow {
  param([int]$ProcessId)

  Initialize-WindowEnumerator
  return [RePaperTodoSmokeWindowEnumerator]::FindVisiblePaperWindow(
    [uint32]$ProcessId)
}

function Move-ResizePaperWindow {
  param(
    [long]$WindowHandle,
    [int]$X,
    [int]$Y,
    [int]$Width,
    [int]$Height
  )

  Initialize-WindowEnumerator
  if (-not [RePaperTodoSmokeWindowEnumerator]::MoveResizeWindow(
      $WindowHandle, $X, $Y, $Width, $Height)) {
    throw "Windows release smoke could not move and resize an independent paper window."
  }
}

function Invoke-NativePaperEdgeResize {
  param(
    [long]$WindowHandle,
    [int]$Delta = 80
  )

  Initialize-WindowEnumerator
  return [RePaperTodoSmokeWindowEnumerator]::DragRightEdgeToResize(
    $WindowHandle, $Delta)
}

function Get-LastNativeResizeHitTest {
  param([long]$WindowHandle)

  Initialize-WindowEnumerator
  return [RePaperTodoSmokeWindowEnumerator]::LastResizeHitTest($WindowHandle)
}

function Get-PaperWindowBounds {
  param([long]$WindowHandle)

  Initialize-WindowEnumerator
  $bounds = [RePaperTodoSmokeWindowEnumerator]::GetBounds($WindowHandle)
  if ($null -eq $bounds -or $bounds.Count -ne 4) {
    return $null
  }
  return [ordered]@{
    x = [int]$bounds[0]
    y = [int]$bounds[1]
    width = [int]$bounds[2]
    height = [int]$bounds[3]
  }
}

function Edit-PaperTodoTextField {
  param(
    [long]$WindowHandle,
    [string]$Text
  )

  Initialize-WindowEnumerator
  $result = [RePaperTodoSmokeWindowEnumerator]::EditTodoText(
    $WindowHandle, $Text)
  if ($result -ne 1) {
    throw "Windows release smoke could not type into an independent paper content field (native input result $result)."
  }
}

function Test-PaperWindowBounds {
  param(
    [long]$WindowHandle,
    [int]$X,
    [int]$Y,
    [int]$Width,
    [int]$Height
  )

  $bounds = Get-PaperWindowBounds -WindowHandle $WindowHandle
  return $null -ne $bounds -and
    [Math]::Abs([int]$bounds.x - $X) -le 1 -and
    [Math]::Abs([int]$bounds.y - $Y) -le 1 -and
    [Math]::Abs([int]$bounds.width - $Width) -le 1 -and
    [Math]::Abs([int]$bounds.height - $Height) -le 1
}

function Test-PersistedPaperBounds {
  param(
    [string]$StateFile,
    [int]$X,
    [int]$Y,
    [int]$Width,
    [int]$Height
  )

  if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
    return $false
  }
  try {
    $state = Get-Content -Raw -LiteralPath $StateFile | ConvertFrom-Json
    foreach ($paper in @($state.papers)) {
      if ([Math]::Abs([double]$paper.x - $X) -le 1 -and
          [Math]::Abs([double]$paper.y - $Y) -le 1 -and
          [Math]::Abs([double]$paper.width - $Width) -le 1 -and
          [Math]::Abs([double]$paper.height - $Height) -le 1) {
        return $true
      }
    }
  } catch {
    return $false
  }
  return $false
}

function Test-PersistedPaperContentMarker {
  param(
    [string]$StateFile,
    [string]$Marker
  )

  if ([string]::IsNullOrWhiteSpace($Marker) -or
      -not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
    return $false
  }
  try {
    $state = Get-Content -Raw -LiteralPath $StateFile | ConvertFrom-Json
    foreach ($paper in @($state.papers)) {
      if (([string]$paper.title).Contains($Marker) -or
          ([string]$paper.content).Contains($Marker)) {
        return $true
      }
      foreach ($item in @($paper.items)) {
        if (([string]$item.text).Contains($Marker)) {
          return $true
        }
        foreach ($column in @($item.todoExtraColumns)) {
          if (([string]$column).Contains($Marker)) {
            return $true
          }
        }
      }
      foreach ($element in @($paper.noteCanvasElements)) {
        if (([string]$element.text).Contains($Marker)) {
          return $true
        }
      }
    }
  } catch {
    return $false
  }
  return $false
}

function Close-CoordinatorWindow {
  param([long]$WindowHandle)

  Initialize-WindowEnumerator
  if (-not [RePaperTodoSmokeWindowEnumerator]::CloseWindow($WindowHandle)) {
    throw "Windows release smoke could not close the settings coordinator window."
  }
}

function Get-PaperTypeCounts {
  param([string]$StateFile)

  $counts = [ordered]@{
    total = 0
    todo = 0
    note = 0
    other = 0
  }
  if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
    return $counts
  }
  try {
    $state = Get-Content -Raw -LiteralPath $StateFile | ConvertFrom-Json
    if ($null -eq $state.papers) {
      return $counts
    }
    foreach ($paper in @($state.papers)) {
      $counts.total += 1
      $type = ([string]$paper.type).Trim().ToLowerInvariant()
      if ($type -eq "todo") {
        $counts.todo += 1
      } elseif ($type -eq "note") {
        $counts.note += 1
      } else {
        $counts.other += 1
      }
    }
  } catch {
    return [ordered]@{
      total = 0
      todo = 0
      note = 0
      other = 0
    }
  }
  return $counts
}

function Invoke-SecondaryStartupCommand {
  param(
    [string]$Executable,
    [string]$WorkingDirectory,
    [string]$Command
  )

  $process = Start-Process `
    -FilePath $Executable `
    -ArgumentList $Command `
    -WorkingDirectory $WorkingDirectory `
    -WindowStyle Hidden `
    -PassThru
  if (-not $process.WaitForExit(10000)) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    throw "Secondary startup command '$Command' did not exit promptly."
  }
  if ($process.ExitCode -ne 0) {
    throw "Secondary startup command '$Command' failed with exit code $($process.ExitCode)."
  }
}

function Remove-SmokeRoot {
  param(
    [string]$SmokeRoot,
    [string]$TempRoot
  )

  if ([string]::IsNullOrWhiteSpace($SmokeRoot) -or
      -not (Test-Path -LiteralPath $SmokeRoot)) {
    return
  }
  Assert-PathInside `
    -Path $SmokeRoot `
    -ParentPath $TempRoot `
    -Message "Refusing to remove a smoke-test directory outside the system temp path."
  $lastError = $null
  for ($attempt = 1; $attempt -le 10; $attempt += 1) {
    try {
      Remove-Item -LiteralPath $SmokeRoot -Recurse -Force
      return
    } catch {
      $lastError = $_
      Start-Sleep -Milliseconds 300
    }
  }
  throw $lastError
}

function Resolve-ResultJsonPath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }
  if ($Path -match "[\x00-\x1F\x7F-\x9F]") {
    throw "Windows release smoke result JSON path must not contain control characters."
  }
  if ($Path -match "[*?]") {
    throw "Windows release smoke result JSON path must not contain wildcard characters."
  }
  try {
    $fullPath = [IO.Path]::GetFullPath($Path)
  } catch {
    throw "Windows release smoke result JSON path is invalid: $($_.Exception.Message)"
  }
  if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($fullPath))) {
    throw "Windows release smoke result JSON path must include a file name."
  }
  if ([IO.Path]::GetExtension($fullPath).ToLowerInvariant() -ne ".json") {
    throw "Windows release smoke result JSON path must use the .json extension."
  }
  return $fullPath
}

$resultJsonFullPath = Resolve-ResultJsonPath -Path $ResultJson
Assert-WindowsHost
Assert-NoExistingRePaperTodoProcess

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReleaseDirectory)) {
  $ReleaseDirectory = Join-Path $repoRoot "build\windows\x64\runner\Release"
}
$releaseDirectoryFullPath = [IO.Path]::GetFullPath($ReleaseDirectory)
$sourceExe = Join-Path $releaseDirectoryFullPath "repapertodo.exe"
$sourceFlutterDll = Join-Path $releaseDirectoryFullPath "flutter_windows.dll"
$sourceDataDirectory = Join-Path $releaseDirectoryFullPath "data"

foreach ($requiredPath in @($sourceExe, $sourceFlutterDll, $sourceDataDirectory)) {
  if (-not (Test-Path -LiteralPath $requiredPath)) {
    throw "Windows release smoke input was not found: $requiredPath"
  }
}

$tempRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot ".tmp"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$smokeRoot = Join-Path $tempRoot "repapertodo-windows-smoke-$([Guid]::NewGuid().ToString("N"))"
$smokeReleaseDirectory = Join-Path $smokeRoot "Release"
$smokeExe = Join-Path $smokeReleaseDirectory "repapertodo.exe"
$smokeStateFile = Join-Path $smokeReleaseDirectory "data.json"
$primaryProcess = $null
$smokeFailure = $null
$hiddenStartupCommands = @("--hide")
$ignoredSecondaryStartupCommands = @("--unknown-startup-command")
$secondaryStartupCommands = @("--new-note", "--new-todo", "--exit")
$settingsStartupCommands = @("--settings")
$initialPaperCount = 0
$initialVisibleWindowCount = 0
$finalVisibleWindowCount = 0
$visiblePaperCountAfterIgnoredCommand = 0
$visiblePaperCountBeforeSettings = 0
$visibleTopLevelWindowCountWhileSettingsOpen = 0
$visibleTopLevelWindowCountAfterSettingsClose = 0
$geometryPersistenceVerified = $false
$contentEditGeometryStabilityVerified = $false
$interactiveEdgeResizeVerified = $false
$contentEditMarker = "SmokeEdit$([Guid]::NewGuid().ToString('N').Substring(0, 10))"
$geometryTestBounds = [ordered]@{
  x = 180
  y = 140
  width = 360
  height = 280
}
$initialPaperTypeCounts = [ordered]@{
  total = 0
  todo = 0
  note = 0
  other = 0
}

try {
  New-Item -ItemType Directory -Force -Path $smokeReleaseDirectory | Out-Null
  Copy-Item `
    -Path (Join-Path $releaseDirectoryFullPath "*") `
    -Destination $smokeReleaseDirectory `
    -Recurse `
    -Force

  $primaryProcess = Start-Process `
    -FilePath $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -WindowStyle Hidden `
    -PassThru

  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke app did not create an initial data.json in time." `
    -Condition {
      -not $primaryProcess.HasExited -and
        (Test-Path -LiteralPath $smokeStateFile -PathType Leaf) -and
        (Get-PaperCount -StateFile $smokeStateFile) -ge 1
    }

  $initialPaperTypeCounts = Get-PaperTypeCounts -StateFile $smokeStateFile
  $initialPaperCount = [int]$initialPaperTypeCounts.total
  Start-Sleep -Milliseconds 1000
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke did not create one visible top-level window per initial paper." `
    -Condition {
      $visibleWindowCount = Get-VisiblePaperWindowCount -ProcessId $primaryProcess.Id
      $visibleWindowCount -ge $initialPaperCount
    }
  $initialVisibleWindowCount =
    Get-VisiblePaperWindowCount -ProcessId $primaryProcess.Id

  $paperWindow = Get-VisiblePaperWindow -ProcessId $primaryProcess.Id
  if ($paperWindow -eq 0) {
    throw "Windows release smoke could not find the initial independent paper window."
  }
  $interactiveResizeDelta =
    Invoke-NativePaperEdgeResize -WindowHandle $paperWindow -Delta 80
  if ($interactiveResizeDelta -lt 40) {
    $resizeHitTest = Get-LastNativeResizeHitTest -WindowHandle $paperWindow
    throw "Windows release smoke could not resize a paper through a real right-edge mouse drag (width delta $interactiveResizeDelta, native hit test $resizeHitTest)."
  }
  $interactiveEdgeResizeVerified = $true
  Move-ResizePaperWindow `
    -WindowHandle $paperWindow `
    -X $geometryTestBounds.x `
    -Y $geometryTestBounds.y `
    -Width $geometryTestBounds.width `
    -Height $geometryTestBounds.height
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke did not persist native paper window geometry." `
    -Condition {
      Test-PersistedPaperBounds `
        -StateFile $smokeStateFile `
        -X $geometryTestBounds.x `
        -Y $geometryTestBounds.y `
        -Width $geometryTestBounds.width `
        -Height $geometryTestBounds.height
    }
  $geometryPersistenceVerified = $true

  Edit-PaperTodoTextField `
    -WindowHandle $paperWindow `
    -Text $contentEditMarker
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke could not persist the automated paper content edit." `
    -Condition {
      Test-PersistedPaperContentMarker `
        -StateFile $smokeStateFile `
        -Marker $contentEditMarker
    }
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke did not preserve paper geometry after a content edit." `
    -Condition {
      (Test-PersistedPaperBounds `
        -StateFile $smokeStateFile `
        -X $geometryTestBounds.x `
        -Y $geometryTestBounds.y `
        -Width $geometryTestBounds.width `
        -Height $geometryTestBounds.height) -and
      (Test-PaperWindowBounds `
        -WindowHandle $paperWindow `
        -X $geometryTestBounds.x `
        -Y $geometryTestBounds.y `
        -Width $geometryTestBounds.width `
        -Height $geometryTestBounds.height)
    }
  $contentEditGeometryStabilityVerified = $true

  Invoke-SecondaryStartupCommand `
    -Executable $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -Command $hiddenStartupCommands[0]

  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke app did not persist secondary --hide command in time." `
    -Condition {
      -not $primaryProcess.HasExited -and
        (Get-VisiblePaperCount -StateFile $smokeStateFile) -eq 0
    }
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke did not hide every independent paper window." `
    -Condition {
      (Get-VisiblePaperWindowCount -ProcessId $primaryProcess.Id) -eq 0 -and
        (Get-VisibleNativeCapsuleWindowCount -ProcessId $primaryProcess.Id) -eq 0
    }

  Invoke-SecondaryStartupCommand `
    -Executable $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -Command $ignoredSecondaryStartupCommands[0]

  Start-Sleep -Milliseconds 750
  $visiblePaperCountAfterIgnoredCommand =
    Get-VisiblePaperCount -StateFile $smokeStateFile
  if ($visiblePaperCountAfterIgnoredCommand -ne 0) {
    throw "Windows release smoke unknown secondary startup command unexpectedly changed paper visibility."
  }

  Invoke-SecondaryStartupCommand `
    -Executable $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -Command $secondaryStartupCommands[0]
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke app did not persist the secondary --new-note paper in time." `
    -Condition {
      -not $primaryProcess.HasExited -and
        (Get-PaperCount -StateFile $smokeStateFile) -ge ($initialPaperCount + 1)
    }
  Invoke-SecondaryStartupCommand `
    -Executable $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -Command $secondaryStartupCommands[1]

  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke app did not persist secondary startup command papers in time." `
    -Condition {
      -not $primaryProcess.HasExited -and
        (Get-PaperCount -StateFile $smokeStateFile) -ge 3
    }
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke did not create one visible top-level HWND per visible paper." `
    -Condition {
      $visiblePapers = Get-VisiblePaperCount -StateFile $smokeStateFile
      $visibleWindows = Get-VisiblePaperWindowCount -ProcessId $primaryProcess.Id
      $visiblePapers -ge 2 -and $visibleWindows -ge $visiblePapers
    }
  $finalVisibleWindowCount =
    Get-VisiblePaperWindowCount -ProcessId $primaryProcess.Id

  $visiblePaperCountBeforeSettings =
    Get-VisiblePaperCount -StateFile $smokeStateFile
  Invoke-SecondaryStartupCommand `
    -Executable $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -Command $settingsStartupCommands[0]
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke forwarded --settings command did not reveal the coordinator window." `
    -Condition {
      (Get-VisibleCoordinatorWindow -ProcessId $primaryProcess.Id) -ne 0 -and
        (Get-VisiblePaperWindowCount -ProcessId $primaryProcess.Id) -eq
          $visiblePaperCountBeforeSettings
    }
  $visibleTopLevelWindowCountWhileSettingsOpen =
    Get-VisibleTopLevelWindowCount -ProcessId $primaryProcess.Id
  $coordinatorWindow =
    Get-VisibleCoordinatorWindow -ProcessId $primaryProcess.Id
  Close-CoordinatorWindow -WindowHandle $coordinatorWindow
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke settings coordinator did not close without changing independent papers." `
    -Condition {
      (Get-VisibleCoordinatorWindow -ProcessId $primaryProcess.Id) -eq 0 -and
        (Get-VisiblePaperWindowCount -ProcessId $primaryProcess.Id) -eq
          $visiblePaperCountBeforeSettings -and
        (Get-VisiblePaperCount -StateFile $smokeStateFile) -eq
          $visiblePaperCountBeforeSettings
    }
  $visibleTopLevelWindowCountAfterSettingsClose =
    Get-VisiblePaperWindowCount -ProcessId $primaryProcess.Id

  Invoke-SecondaryStartupCommand `
    -Executable $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -Command $secondaryStartupCommands[2]

  if (-not $primaryProcess.WaitForExit($ExitTimeoutSeconds * 1000)) {
    throw "Windows release smoke app did not exit after --exit forwarding."
  }
  if ($primaryProcess.ExitCode -ne 0) {
    throw "Windows release smoke app exited with code $($primaryProcess.ExitCode)."
  }

  $finalPaperTypeCounts = Get-PaperTypeCounts -StateFile $smokeStateFile
  $paperCount = [int]$finalPaperTypeCounts.total
  if ([int]$finalPaperTypeCounts.note -le [int]$initialPaperTypeCounts.note) {
    throw "Windows release smoke --new-note did not increase the persisted note paper count."
  }
  if ([int]$finalPaperTypeCounts.todo -le [int]$initialPaperTypeCounts.todo) {
    throw "Windows release smoke --new-todo did not increase the persisted todo paper count."
  }
  if (-not [string]::IsNullOrWhiteSpace($ResultJson)) {
    $resultDirectory = Split-Path -Parent $resultJsonFullPath
    if (-not [string]::IsNullOrWhiteSpace($resultDirectory)) {
      New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
    }
    [ordered]@{
      status = "passed"
      checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
      releaseDirectory = $releaseDirectoryFullPath
      exeFileName = "repapertodo.exe"
      initialPaperCount = $initialPaperCount
      finalPaperCount = $paperCount
      initialTodoPaperCount = [int]$initialPaperTypeCounts.todo
      finalTodoPaperCount = [int]$finalPaperTypeCounts.todo
      initialNotePaperCount = [int]$initialPaperTypeCounts.note
      finalNotePaperCount = [int]$finalPaperTypeCounts.note
      initialVisibleTopLevelWindowCount = $initialVisibleWindowCount
      finalVisibleTopLevelWindowCount = $finalVisibleWindowCount
      independentPaperSurfaces = $true
      geometryPersistenceVerified = $geometryPersistenceVerified
      contentEditGeometryStabilityVerified =
        $contentEditGeometryStabilityVerified
      interactiveEdgeResizeVerified = $interactiveEdgeResizeVerified
      geometryTestBounds = $geometryTestBounds
      settingsCoordinatorLifecycle = $true
      settingsStartupCommands = $settingsStartupCommands
      visiblePaperCountBeforeSettings = $visiblePaperCountBeforeSettings
      visibleTopLevelWindowCountWhileSettingsOpen =
        $visibleTopLevelWindowCountWhileSettingsOpen
      visibleTopLevelWindowCountAfterSettingsClose =
        $visibleTopLevelWindowCountAfterSettingsClose
      hiddenStartupCommands = $hiddenStartupCommands
      ignoredSecondaryStartupCommands = $ignoredSecondaryStartupCommands
      visiblePaperCountAfterIgnoredCommand = $visiblePaperCountAfterIgnoredCommand
      secondaryStartupCommands = $secondaryStartupCommands
      startupTimeoutSeconds = $StartupTimeoutSeconds
      exitTimeoutSeconds = $ExitTimeoutSeconds
    } |
      ConvertTo-Json -Depth 4 |
      Set-Content -LiteralPath $resultJsonFullPath -Encoding ascii
  }
  Write-Host "Windows release smoke passed with $paperCount persisted papers and $finalVisibleWindowCount independent visible HWNDs."
} catch {
  $smokeFailure = $_
  throw
} finally {
  if ($null -ne $primaryProcess -and -not $primaryProcess.HasExited) {
    Stop-Process -Id $primaryProcess.Id -Force -ErrorAction SilentlyContinue
    Wait-Process -Id $primaryProcess.Id -Timeout 5 -ErrorAction SilentlyContinue
  }
  try {
    Remove-SmokeRoot -SmokeRoot $smokeRoot -TempRoot $tempRoot
  } catch {
    if ($null -eq $smokeFailure) {
      throw
    }
    Write-Warning "Unable to remove Windows smoke temp directory '$smokeRoot': $($_.Exception.Message)"
  }
}
