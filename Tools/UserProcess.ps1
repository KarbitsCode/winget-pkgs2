[CmdletBinding()]
param(
  [Parameter(Mandatory, Position = 0)]
  [string]$Command
)

$ErrorActionPreference = 'Stop'
if (-not (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Runner has to be in elevated session."
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Win32 {
    [StructLayout(LayoutKind.Sequential)] public struct SA {
        public int nLength;
        public IntPtr lpSecurityDescriptor;
        public bool bInheritHandle;
    }
    [StructLayout(LayoutKind.Sequential)] public struct SI {
        public int cb;
        public string lpReserved, lpDesktop, lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)] public struct PI {
        public IntPtr hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }
    [StructLayout(LayoutKind.Sequential)] public struct TE {
        public int TokenIsElevated;
    }
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr h, out int code);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool CreatePipe( out IntPtr hReadPipe, out IntPtr hWritePipe, ref SA lpPipeAttributes, uint nSize);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetHandleInformation(IntPtr hObject, uint dwMask, uint dwFlags);
    [DllImport("advapi32.dll", SetLastError = true)] public static extern bool OpenProcessToken(IntPtr proc, int access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)] public static extern bool GetTokenInformation(IntPtr token, int infoClass, out TE info, int infoLength, out int returnLength);
    [DllImport("advapi32.dll", SetLastError = true)] public static extern bool GetTokenInformation(IntPtr token, int infoClass, out int info, int infoLength, out int returnLength);
    [DllImport("advapi32.dll", SetLastError = true)] public static extern bool DuplicateTokenEx(IntPtr tok, int access, ref SA sa, int impLevel, int tokType, out IntPtr newTok);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool CreateProcessWithTokenW(IntPtr token, int logonFlags, string appName, string cmdLine, int creationFlags, IntPtr env, string curDir, ref SI si, out PI pi);
    [DllImport("userenv.dll", SetLastError = true)] public static extern bool CreateEnvironmentBlock(out IntPtr env, IntPtr token, bool inherit);
    [DllImport("userenv.dll", SetLastError = true)] public static extern bool DestroyEnvironmentBlock(IntPtr env);
}
'@

# Find explorer.exe
$curSession = (Get-Process -Id $PID).SessionId
$explorer = Get-Process explorer | Where-Object SessionId -eq $curSession | Select-Object -First 1
if (-not $explorer) {
    throw "No explorer.exe found in this session."
}

# Copy explorer's token
$hExplorer = [Win32]::OpenProcess(0x0400 <# PROCESS_QUERY_INFORMATION #>, $false, $explorer.Id)
$hToken = [IntPtr]::Zero
if (-not [Win32]::OpenProcessToken($hExplorer, 0x0002 -bor 0x0008 <# TOKEN_DUPLICATE | TOKEN_QUERY #>, [ref]$hToken)) {
    throw "OpenProcessToken failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}
$elevation = New-Object Win32+TE
$elevationType = 0
$returnLength = 0
if (-not [Win32]::GetTokenInformation($hToken, 20 <# TokenElevation #>, [ref]$elevation, [Runtime.InteropServices.Marshal]::SizeOf($elevation), [ref]$returnLength)) {
    throw "GetTokenInformation failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}
if (-not [Win32]::GetTokenInformation($hToken, 18 <# TokenElevationType #>, [ref]$elevationType, 4, [ref]$returnLength)) {
    throw "GetTokenInformation2 failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}
whoami /all
Write-Host "Explorer elevated: $([bool]$elevation.TokenIsElevated) $(switch ($elevationType) {
    1 { 'Default' }
    2 { 'Full' }
    3 { 'Limited' }
    default { `"Unknown ($type)`" }
})"
$sa = New-Object Win32+SA;
$sa.nLength = [Runtime.InteropServices.Marshal]::SizeOf($sa)
$sa.bInheritHandle = $true
$hTokenCopy = [IntPtr]::Zero
if (-not [Win32]::DuplicateTokenEx($hToken, 0xF01FF <# TOKEN_ALL_ACCESS #>, [ref]$sa, 2 <# SECURITY_IMPERSONATION_LEVEL.SecurityImpersonation #>, 1 <# TOKEN_TYPE.TokenPrimary #>, [ref]$hTokenCopy)) {
    throw "DuplicateTokenEx failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}

# Make a pipe so output can streams live
$outRead  = [IntPtr]::Zero
$outWrite = [IntPtr]::Zero
if (-not [Win32]::CreatePipe([ref]$outRead, [ref]$outWrite, [ref]$sa, 0)) {
    throw "CreatePipe failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}

# Parent must NOT leak its read handle into the child.
[Win32]::SetHandleInformation($outRead, 0x00000001 <# HANDLE_FLAG_INHERIT #>, 0) | Out-Null

$psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
$cmdLine = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded"
$cmdPwd = (Get-Location).Path # For ERROR_INVALID_NAME
$exitCode = 0

$si = New-Object Win32+SI
$si.cb = [Runtime.InteropServices.Marshal]::SizeOf($si)
$si.dwFlags = 0x100 # STARTF_USESTDHANDLES
$si.wShowWindow = 0 # SW_HIDE
$si.hStdOutput = $outWrite
$si.hStdError = $outWrite
$pi = New-Object Win32+PI

# Build the environment block manually (ERROR_ENVVAR_NOT_FOUND in some cases).
$envBlock = [IntPtr]::Zero
if (-not [Win32]::CreateEnvironmentBlock([ref]$envBlock, $hTokenCopy, $false)) {
    Write-Warning "CreateEnvironmentBlock failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}

$creationFlags = 0x400 # CREATE_UNICODE_ENVIRONMENT
if (-not [Win32]::CreateProcessWithTokenW($hTokenCopy, 0, $psExe, $cmdLine, $creationFlags, $envBlock, $cmdPwd, [ref]$si, [ref]$pi)) {
    throw "CreateProcessWithTokenW failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}

[Win32]::CloseHandle($outWrite) | Out-Null
$safe = New-Object Microsoft.Win32.SafeHandles.SafeFileHandle($outRead, $true)
$fs = New-Object System.IO.FileStream($safe, [System.IO.FileAccess]::Read)
$reader = New-Object System.IO.StreamReader($fs)
while ($null -ne ($line = $reader.ReadLine())) {
    # Stream the outputs
    Write-Host $line
}

[Win32]::WaitForSingleObject($pi.hProcess, [uint32]::MaxValue <# INFINITE #>) | Out-Null
[Win32]::GetExitCodeProcess($pi.hProcess, [ref]$exitCode) | Out-Null

if ($envBlock -ne [IntPtr]::Zero) {
    [Win32]::DestroyEnvironmentBlock($envBlock) | Out-Null
}
foreach ($h in @($pi.hProcess, $pi.hThread, $hTokenCopy, $hToken, $hExplorer)) {
    [Win32]::CloseHandle($h) | Out-Null
}

exit $exitCode
