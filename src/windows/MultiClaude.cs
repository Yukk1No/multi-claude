// Windows interop for multi-claude. Loaded with Add-Type (C# 5, no dependencies).
//   Window   tag a window with an AppUserModelID so the taskbar gives it its own button
//   Shortcut stamp the same AppUserModelID on a .lnk
//   Icon     recolor the installed Claude logo and write a multi-size .ico
//   Package  tell whether we run inside an MSIX package context (where AppData writes are redirected)
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

namespace MultiClaude {
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PropertyKey {
        public Guid FormatId; public uint PropertyId;
        public PropertyKey(Guid formatId, uint propertyId) { FormatId = formatId; PropertyId = propertyId; }
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct PropVariant {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(8)] public IntPtr Value;
        [FieldOffset(16)] public IntPtr Reserved; // PROPVARIANT is 24 bytes on x64
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }

    [ComImport, Guid("0000010b-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPersistFile {
        void GetClassID(out Guid classId);
        [PreserveSig] int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string file, uint mode);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string file, bool remember);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string file);
        void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string file);
    }

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")] class ShellLink { }

    [ComImport, Guid("56FDF342-FD6D-11d0-958A-006097C9A090"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ITaskbarList {
        void HrInit(); void AddTab(IntPtr hwnd); void DeleteTab(IntPtr hwnd); void ActivateTab(IntPtr hwnd); void SetActiveAlt(IntPtr hwnd);
    }
    [ComImport, Guid("56FDF344-FD6D-11d0-958A-006097C9A090")] class TaskbarList { }

    // System.AppUserModel.* properties (propkey.h).
    static class AppUserModel {
        static readonly Guid Format = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
        public const uint RelaunchCommand = 2, RelaunchIconResource = 3, RelaunchDisplayName = 4, Id = 5;
        const ushort VT_LPWSTR = 31;

        [DllImport("ole32.dll")] static extern int PropVariantClear(ref PropVariant value);

        public static void Set(IPropertyStore store, uint property, string text) {
            var key = new PropertyKey(Format, property);
            var value = new PropVariant { Type = VT_LPWSTR, Value = Marshal.StringToCoTaskMemUni(text) };
            int hr = store.SetValue(ref key, ref value);
            PropVariantClear(ref value);
            Marshal.ThrowExceptionForHR(hr);
        }

        public static string Get(IPropertyStore store, uint property) {
            var key = new PropertyKey(Format, property);
            PropVariant value;
            if (store.GetValue(ref key, out value) != 0) return null;
            string text = value.Type == VT_LPWSTR ? Marshal.PtrToStringUni(value.Value) : null;
            PropVariantClear(ref value);
            return text;
        }
    }

    public static class Window {
        const uint GW_OWNER = 4, WM_SETICON = 0x80, WM_CLOSE = 0x10, SMTO_ABORTIFHUNG = 2;
        const uint IMAGE_ICON = 1, LR_LOADFROMFILE = 0x10;
        const int GWL_EXSTYLE = -20, WS_EX_TOOLWINDOW = 0x80, ICON_SMALL = 0, ICON_BIG = 1;

        delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hwnd, uint relation);
        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hwnd, int index);
        [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr LoadImage(IntPtr instance, string name, uint type, int width, int height, uint flags);
        [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);

        static IntPtr smallIcon, bigIcon;

        // Visible, unowned, non-tool top-level windows of the given processes.
        public static IntPtr[] Of(uint[] processIds) {
            var wanted = new HashSet<uint>(processIds);
            var found = new List<IntPtr>();
            EnumWindows(delegate (IntPtr hwnd, IntPtr lParam) {
                uint pid; GetWindowThreadProcessId(hwnd, out pid);
                if (wanted.Contains(pid) && IsWindowVisible(hwnd) && GetWindow(hwnd, GW_OWNER) == IntPtr.Zero
                    && (GetWindowLong(hwnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) == 0) found.Add(hwnd);
                return true;
            }, IntPtr.Zero);
            return found.ToArray();
        }

        static IPropertyStore Store(IntPtr hwnd) {
            Guid iid = typeof(IPropertyStore).GUID;
            IPropertyStore store;
            Marshal.ThrowExceptionForHR(SHGetPropertyStoreForWindow(hwnd, ref iid, out store));
            return store;
        }

        public static string GetId(IntPtr hwnd) {
            IPropertyStore store = Store(hwnd);
            try { return AppUserModel.Get(store, AppUserModel.Id); } finally { Marshal.ReleaseComObject(store); }
        }

        // Relaunch properties first and the ID last: the ID is what the taskbar reacts to.
        public static void Tag(IntPtr hwnd, string id, string relaunchCommand, string displayName, string icon) {
            IPropertyStore store = Store(hwnd);
            try {
                AppUserModel.Set(store, AppUserModel.RelaunchCommand, relaunchCommand);
                AppUserModel.Set(store, AppUserModel.RelaunchIconResource, icon + ",0");
                AppUserModel.Set(store, AppUserModel.RelaunchDisplayName, displayName);
                AppUserModel.Set(store, AppUserModel.Id, id);
            } finally { Marshal.ReleaseComObject(store); }
            SetIcon(hwnd, icon);
            var taskbar = (ITaskbarList)new TaskbarList();   // re-adding the button makes the taskbar re-read the ID
            try { taskbar.HrInit(); taskbar.DeleteTab(hwnd); taskbar.AddTab(hwnd); } finally { Marshal.ReleaseComObject(taskbar); }
        }

        // Title bar and Alt+Tab icon. The handles live as long as this process (the profile's watcher).
        static void SetIcon(IntPtr hwnd, string icoPath) {
            if (!File.Exists(icoPath)) return;
            if (smallIcon == IntPtr.Zero) smallIcon = LoadImage(IntPtr.Zero, icoPath, IMAGE_ICON, 16, 16, LR_LOADFROMFILE);
            if (bigIcon == IntPtr.Zero) bigIcon = LoadImage(IntPtr.Zero, icoPath, IMAGE_ICON, 32, 32, LR_LOADFROMFILE);
            IntPtr ignored;
            if (smallIcon != IntPtr.Zero) SendMessageTimeout(hwnd, WM_SETICON, (IntPtr)ICON_SMALL, smallIcon, SMTO_ABORTIFHUNG, 1000, out ignored);
            if (bigIcon != IntPtr.Zero) SendMessageTimeout(hwnd, WM_SETICON, (IntPtr)ICON_BIG, bigIcon, SMTO_ABORTIFHUNG, 1000, out ignored);
        }

        public static void Close(IntPtr hwnd) { PostMessage(hwnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero); }
    }

    public static class Shortcut {
        const uint STGM_READ = 0, STGM_READWRITE = 2;

        public static void SetId(string lnkPath, string id) {
            object link = new ShellLink();
            try {
                ((IPersistFile)link).Load(lnkPath, STGM_READWRITE);
                var store = (IPropertyStore)link;
                AppUserModel.Set(store, AppUserModel.Id, id);
                Marshal.ThrowExceptionForHR(store.Commit());
                ((IPersistFile)link).Save(lnkPath, true);
            } finally { Marshal.ReleaseComObject(link); }
        }

        public static string GetId(string lnkPath) {
            object link = new ShellLink();
            try {
                ((IPersistFile)link).Load(lnkPath, STGM_READ);
                return AppUserModel.Get((IPropertyStore)link, AppUserModel.Id);
            } finally { Marshal.ReleaseComObject(link); }
        }
    }

    public static class Package {
        const int APPMODEL_ERROR_NO_PACKAGE = 15700;
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern int GetCurrentPackageFullName(ref int length, System.Text.StringBuilder name);

        // True inside an MSIX package context (e.g. a terminal opened from Claude Desktop).
        public static bool IsPackaged() {
            int length = 0;
            return GetCurrentPackageFullName(ref length, null) != APPMODEL_ERROR_NO_PACKAGE;
        }
    }

    public static class Icon {
        static readonly int[] Sizes = { 16, 20, 24, 32, 40, 48, 64, 96, 128, 256 };

        // Every colored pixel takes the target hue; saturation and brightness are scaled so the logo's
        // own brand color lands exactly on the target. Near-white pixels (the glyph) stay light.
        public static Bitmap Recolor(string sourcePng, Color target) {
            var bitmap = new Bitmap(sourcePng);
            var argb = new Bitmap(bitmap.Width, bitmap.Height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(argb)) g.DrawImage(bitmap, 0, 0, bitmap.Width, bitmap.Height);
            bitmap.Dispose();

            var data = argb.LockBits(new Rectangle(0, 0, argb.Width, argb.Height), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            var px = new byte[data.Stride * data.Height];   // BGRA
            Marshal.Copy(data.Scan0, px, 0, px.Length);

            double brandS, brandV; BrandColor(px, out brandS, out brandV);
            double h, s, v; ToHsv(target.R, target.G, target.B, out h, out s, out v);
            for (int i = 0; i < px.Length; i += 4) {
                if (px[i + 3] == 0) continue;
                double ph, ps, pv; ToHsv(px[i + 2], px[i + 1], px[i], out ph, out ps, out pv);
                double colored = Math.Min(1.0, ps / brandS);
                FromHsv(h, Math.Min(1.0, ps * s / brandS), Math.Min(1.0, pv * (1 - colored + colored * v / brandV)),
                        out px[i + 2], out px[i + 1], out px[i]);
            }
            Marshal.Copy(px, 0, data.Scan0, px.Length);
            argb.UnlockBits(data);
            return argb;
        }

        // Mean saturation and brightness of the clearly colored, opaque pixels.
        static void BrandColor(byte[] px, out double s, out double v) {
            double sumS = 0, sumV = 0; int n = 0;
            for (int i = 0; i < px.Length; i += 16) {   // every 4th pixel is plenty
                if (px[i + 3] < 200) continue;
                double ph, ps, pv; ToHsv(px[i + 2], px[i + 1], px[i], out ph, out ps, out pv);
                if (ps < 0.3) continue;
                sumS += ps; sumV += pv; n++;
            }
            s = n > 0 ? sumS / n : 0.6;
            v = n > 0 ? sumV / n : 0.85;
        }

        // .ico with PNG frames (Vista+), one per size.
        public static void SaveIco(Bitmap image, string path) {
            var frames = new List<byte[]>();
            foreach (int size in Sizes) {
                using (var frame = new Bitmap(size, size, PixelFormat.Format32bppArgb))
                using (var g = Graphics.FromImage(frame))
                using (var png = new MemoryStream()) {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.SmoothingMode = SmoothingMode.HighQuality;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(image, 0, 0, size, size);
                    frame.Save(png, ImageFormat.Png);
                    frames.Add(png.ToArray());
                }
            }
            using (var writer = new BinaryWriter(File.Create(path))) {
                writer.Write((short)0); writer.Write((short)1); writer.Write((short)Sizes.Length);   // ICONDIR
                int offset = 6 + 16 * Sizes.Length;
                for (int i = 0; i < Sizes.Length; i++) {                                               // ICONDIRENTRY
                    byte side = (byte)(Sizes[i] >= 256 ? 0 : Sizes[i]);
                    writer.Write(side); writer.Write(side); writer.Write((byte)0); writer.Write((byte)0);
                    writer.Write((short)1); writer.Write((short)32);
                    writer.Write(frames[i].Length); writer.Write(offset);
                    offset += frames[i].Length;
                }
                foreach (var frame in frames) writer.Write(frame);
            }
        }

        static void ToHsv(int r, int g, int b, out double h, out double s, out double v) {
            double rd = r / 255.0, gd = g / 255.0, bd = b / 255.0;
            double max = Math.Max(rd, Math.Max(gd, bd)), delta = max - Math.Min(rd, Math.Min(gd, bd));
            v = max; s = max == 0 ? 0 : delta / max;
            if (delta == 0) h = 0;
            else if (max == rd) h = 60 * (((gd - bd) / delta) % 6);
            else if (max == gd) h = 60 * ((bd - rd) / delta + 2);
            else h = 60 * ((rd - gd) / delta + 4);
            if (h < 0) h += 360;
        }

        static void FromHsv(double h, double s, double v, out byte r, out byte g, out byte b) {
            double c = v * s, x = c * (1 - Math.Abs((h / 60) % 2 - 1)), m = v - c, rr, gg, bb;
            if (h < 60)       { rr = c; gg = x; bb = 0; }
            else if (h < 120) { rr = x; gg = c; bb = 0; }
            else if (h < 180) { rr = 0; gg = c; bb = x; }
            else if (h < 240) { rr = 0; gg = x; bb = c; }
            else if (h < 300) { rr = x; gg = 0; bb = c; }
            else              { rr = c; gg = 0; bb = x; }
            r = (byte)Math.Round((rr + m) * 255); g = (byte)Math.Round((gg + m) * 255); b = (byte)Math.Round((bb + m) * 255);
        }
    }
}
