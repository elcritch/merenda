$ErrorActionPreference = 'Stop'
$Lab = 'C:\MerendaLab'
New-Item -ItemType Directory -Force $Lab | Out-Null
# Run in the logged-in VirtualBox console. RDP and SSH can select a different
# rendering path or a noninteractive desktop, so they are not the acceptance test.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class MerendaGlProbe {
  [StructLayout(LayoutKind.Sequential)]
  struct Pfd {
    public ushort size, version;
    public uint flags;
    public byte pixelType, colorBits, redBits, redShift, greenBits, greenShift,
      blueBits, blueShift, alphaBits, alphaShift, accumBits, accumRedBits,
      accumGreenBits, accumBlueBits, accumAlphaBits, depthBits, stencilBits,
      auxBuffers, layerType, reserved;
    public uint layerMask, visibleMask, damageMask;
  }
  [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern IntPtr CreateWindowEx(uint ex, string cls, string name, uint style,
    int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
  [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr window);
  [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr window, IntPtr dc);
  [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr window);
  [DllImport("gdi32.dll", SetLastError=true)] static extern int ChoosePixelFormat(IntPtr dc, ref Pfd pfd);
  [DllImport("gdi32.dll", SetLastError=true)] static extern bool SetPixelFormat(IntPtr dc, int format, ref Pfd pfd);
  [DllImport("gdi32.dll")] static extern bool SwapBuffers(IntPtr dc);
  [DllImport("opengl32.dll", SetLastError=true)] static extern IntPtr wglCreateContext(IntPtr dc);
  [DllImport("opengl32.dll", SetLastError=true)] static extern bool wglMakeCurrent(IntPtr dc, IntPtr context);
  [DllImport("opengl32.dll")] static extern bool wglDeleteContext(IntPtr context);
  [DllImport("opengl32.dll", CharSet=CharSet.Ansi)] static extern IntPtr wglGetProcAddress(string name);
  [DllImport("opengl32.dll")] static extern IntPtr glGetString(uint name);
  [DllImport("opengl32.dll")] static extern void glClearColor(float r, float g, float b, float a);
  [DllImport("opengl32.dll")] static extern void glClear(uint mask);
  [DllImport("opengl32.dll")] static extern void glFinish();
  [DllImport("opengl32.dll")] static extern uint glGetError();
  [DllImport("opengl32.dll")] static extern void glReadPixels(int x, int y, int w, int h,
    uint format, uint type, [Out] byte[] pixels);
  [UnmanagedFunctionPointer(CallingConvention.Winapi)]
  delegate IntPtr CreateAttribs(IntPtr dc, IntPtr share, int[] attributes);

  public static Dictionary<string, object> Run() {
    IntPtr window = IntPtr.Zero, dc = IntPtr.Zero, context = IntPtr.Zero;
    try {
      window = CreateWindowEx(0, "STATIC", "Merenda OpenGL 3.3 probe", 0x10CF0000,
        100, 100, 320, 240, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
      if (window == IntPtr.Zero) throw new Win32Exception();
      dc = GetDC(window);
      Pfd pfd = new Pfd();
      pfd.size = (ushort)Marshal.SizeOf(typeof(Pfd)); pfd.version = 1;
      // Match Siwin's Windows pixel format used by Merenda.
      pfd.flags = 0x25 | 0x8000; pfd.colorBits = 32; pfd.depthBits = 24; pfd.alphaBits = 8;
      int format = ChoosePixelFormat(dc, ref pfd);
      if (format == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "ChoosePixelFormat failed");
      if (!SetPixelFormat(dc, format, ref pfd))
        throw new Win32Exception(Marshal.GetLastWin32Error(), "SetPixelFormat failed for format " + format);
      context = wglCreateContext(dc);
      if (context == IntPtr.Zero)
        throw new Win32Exception(Marshal.GetLastWin32Error(), "wglCreateContext failed for format " + format);
      if (!wglMakeCurrent(dc, context))
        throw new Win32Exception(Marshal.GetLastWin32Error(), "wglMakeCurrent failed");
      string initial = Marshal.PtrToStringAnsi(glGetString(0x1F02));
      IntPtr pointer = wglGetProcAddress("wglCreateContextAttribsARB");
      if (pointer == IntPtr.Zero || pointer.ToInt64() == 1 || pointer.ToInt64() == -1)
        throw new Exception("OpenGL 3.3 context creation unavailable; legacy version: " + initial);
      CreateAttribs create = (CreateAttribs)Marshal.GetDelegateForFunctionPointer(pointer, typeof(CreateAttribs));
      IntPtr core = create(dc, IntPtr.Zero, new int[] {0x2091, 3, 0x2092, 3, 0x9126, 1, 0});
      if (core == IntPtr.Zero) throw new Exception("Driver could not create an OpenGL 3.3 core context");
      wglMakeCurrent(IntPtr.Zero, IntPtr.Zero);
      wglDeleteContext(context); context = core;
      if (!wglMakeCurrent(dc, context)) throw new Win32Exception();
      var report = new Dictionary<string, object>();
      report["vendor"] = Marshal.PtrToStringAnsi(glGetString(0x1F00));
      report["renderer"] = Marshal.PtrToStringAnsi(glGetString(0x1F01));
      report["version"] = Marshal.PtrToStringAnsi(glGetString(0x1F02));
      report["glsl"] = Marshal.PtrToStringAnsi(glGetString(0x8B8C));
      glClearColor(0.125f, 0.5f, 0.875f, 1); glClear(0x4000); glFinish();
      byte[] pixel = new byte[4];
      glReadPixels(1, 1, 1, 1, 0x1908, 0x1401, pixel);
      uint error = glGetError();
      bool pixels = Math.Abs(pixel[0] - 32) <= 2 && Math.Abs(pixel[1] - 128) <= 2 &&
        Math.Abs(pixel[2] - 223) <= 2 && pixel[3] == 255 && error == 0;
      report["pixel"] = pixel; report["glError"] = error;
      report["core33"] = true; report["pixelReadback"] = pixels;
      SwapBuffers(dc);
      if (!pixels) throw new Exception("OpenGL framebuffer readback did not match the rendered color");
      return report;
    } finally {
      wglMakeCurrent(IntPtr.Zero, IntPtr.Zero);
      if (context != IntPtr.Zero) wglDeleteContext(context);
      if (dc != IntPtr.Zero) ReleaseDC(window, dc);
      if (window != IntPtr.Zero) DestroyWindow(window);
    }
  }
}
'@
try {
  $Report = [MerendaGlProbe]::Run()
  $Software = $Report.renderer -match 'llvmpipe|softpipe|SwiftShader|GDI Generic|Software Rasterizer|WARP|lavapipe'
  $Report['softwareRenderer'] = $Software
  $Report['ok'] = !$Software
  $Report['session'] = $env:SESSIONNAME
  $Report | ConvertTo-Json -Depth 4 | Tee-Object "$Lab\opengl-report.json"
  if ($Software) { throw 'Software renderer detected; hardware acceleration is required' }
  Write-Host 'OpenGL 3.3 core context and framebuffer readback passed.'
  Write-Host 'Also check the host VBox.log for the Radeon renderer; run a Merenda GUI example next.'
} catch {
  @{ok=$false; error=$_.Exception.Message; session=$env:SESSIONNAME} |
    ConvertTo-Json | Set-Content "$Lab\opengl-report.json"
  Write-Error $_
  exit 1
}
