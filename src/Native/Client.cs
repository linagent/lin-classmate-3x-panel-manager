using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Microsoft.Win32.SafeHandles;

[assembly: AssemblyTitle("3XUI Panel Manager Public")]
[assembly: AssemblyDescription("Windows 原生 WPF 面板管理客户端；程序与本机数据分离")]
[assembly: AssemblyCompany("3XUI Panel Manager Contributors")]
[assembly: AssemblyProduct("3XUI Panel Manager Public")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

namespace Public.ThreeXPanelManager
{
    public sealed class PackageFile { public string Path { get; set; } public long Bytes { get; set; } public string Sha256 { get; set; } }
    public sealed class PackageManifest { public string Version { get; set; } public string PayloadSha256 { get; set; } public PackageFile[] Files { get; set; } }

    internal static class Client
    {
        private const string Version = "1.0.0";
        private const string Product = "3XUI Panel Manager Public";
        private static readonly string[] AllowedFiles = new string[] {
            "Panel-Manager.ps1", "Panel-Manager.Core.ps1", "Panel-Manager.Wpf.ps1",
            "Panel-StatusCheck.ps1", "Panel-AutoRefresh.ps1", "Panel-Metadata.ps1", "Panel-Lifecycle.ps1", "Panel-HomePackage.ps1", "Panel-CardPresentation.ps1", "Panel-Resources.ps1", "Panel-Purchases.ps1", "Panel-MonitorUi.ps1", "Panel-ResourceUi.ps1", "Panel-Tunnel.ps1", "Account-Transfer.ps1",
            "Manager-Extensions.ps1", "Panel-ClientActions.ps1", "Client-Bootstrap.ps1",
            "界面/Theme.xaml", "界面/MainWindow.xaml", "界面/ServerCard.xaml", "界面/SettingsWindow.xaml", "界面/AddWindow.xaml", "界面/DeleteWindow.xaml", "界面/TransferWindow.xaml", "界面/UpdateWindow.xaml", "界面/ResourceDrawer.xaml", "界面/PurchaseWindow.xaml", "界面/PurchaseManageWindow.xaml"
        };
        private static string reportPath;

        [STAThread]
        private static int Main(string[] args)
        {
            bool diagnostic = false;
            try
            {
                Dictionary<string, string> options = Parse(args);
                reportPath = Value(options, "report", null);
                diagnostic = options.ContainsKey("version") || options.ContainsKey("verify-package") || options.ContainsKey("self-test") || options.ContainsKey("startup-probe") || options.ContainsKey("render-preview");
                if (options.ContainsKey("version")) { Emit(new { Product = Product, Version = Version }); return 0; }
                PackageManifest manifest;
                byte[] payload = ReadAndVerifyPackage(out manifest);
                if (options.ContainsKey("verify-package"))
                {
                    Emit(new { Product = Product, Version = Version, AllPassed = true, PayloadSha256 = manifest.PayloadSha256, FileCount = manifest.Files.Length, ExplicitAllowlist = true, CredentialsEmbedded = false, ServerInventoryEmbedded = false, OnlineUpdateEnabled = false });
                    return 0;
                }
                if (options.ContainsKey("self-test"))
                {
                    string cache = PrepareCache(manifest, payload);
                    Emit(new { Product = Product, Version = Version, AllPassed = VerifyCache(cache, manifest), PayloadSha256 = manifest.PayloadSha256, FileCount = manifest.Files.Length, CacheDirectory = cache, ProgramDataSeparated = true, UsesBuiltInWindowsPowerShell = true, OnlineUpdateEnabled = false });
                    return 0;
                }
                string executable = Assembly.GetExecutingAssembly().Location;
                string root = ResolveDataRoot(Value(options, "data-root", null));
                string canonicalRoot = CanonicalDirectory(root);
                string cachePrefix = Path.GetFullPath(CacheRoot()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                if ((canonicalRoot + Path.DirectorySeparatorChar).StartsWith(cachePrefix, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("DataCannotBeInsideProgramCache");
                string sid = WindowsIdentity.GetCurrent().User.Value;
                string mutexName = "Local\\Public.ThreeXPanelManager." + Sha256(Encoding.UTF8.GetBytes(sid + "|" + canonicalRoot.ToUpperInvariant()));
                using (Mutex instance = new Mutex(false, mutexName))
                {
                    bool owns = false;
                    try
                    {
                        try { owns = instance.WaitOne(0); } catch (AbandonedMutexException) { owns = true; }
                        if (!owns)
                        {
                            if (diagnostic) Emit(new { AllPassed = false, Error = "AlreadyRunning", Version = Version });
                            else MessageBox.Show("这个数据目录的面板管家已经打开。请切回原窗口；更换 EXE 版本前先关闭原窗口。", Product, MessageBoxButtons.OK, MessageBoxIcon.Information);
                            return 2;
                        }
                        string cache = PrepareCache(manifest, payload);
                        InitialSessionState initial = InitialSessionState.CreateDefault();
                        initial.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
                        using (Runspace runspace = RunspaceFactory.CreateRunspace(initial))
                        {
                            runspace.ApartmentState = ApartmentState.STA;
                            runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                            runspace.Open();
                            using (PowerShell shell = PowerShell.Create())
                            {
                                shell.Runspace = runspace;
                                shell.AddCommand(Path.Combine(cache, "Client-Bootstrap.ps1")).AddParameter("DataRoot", root).AddParameter("ClientExecutable", executable);
                                if (options.ContainsKey("startup-probe"))
                                {
                                    if (String.IsNullOrEmpty(reportPath)) throw new ArgumentException("StartupProbeNeedsReport");
                                    shell.AddParameter("StartupProbe", true).AddParameter("ReportPath", Path.GetFullPath(reportPath)).AddParameter("CloseAfterMs", Int32.Parse(Value(options, "close-after-ms", "1500")));
                                }
                                if (options.ContainsKey("render-preview")) shell.AddParameter("RenderPreview", true).AddParameter("PreviewPath", Path.GetFullPath(options["render-preview"])).AddParameter("PreviewView", Value(options, "preview-view", "Main"));
                                shell.Invoke();
                                if (shell.HadErrors) throw new InvalidOperationException("PowerShellRunspaceFailed");
                            }
                        }
                        if (options.ContainsKey("render-preview")) Emit(new { Product = Product, Version = Version, AllPassed = true, RenderedPreview = Path.GetFullPath(options["render-preview"]), CredentialsEmbedded = false });
                        return 0;
                    }
                    finally { if (owns) instance.ReleaseMutex(); }
                }
            }
            catch (Exception ex)
            {
                // Never copy exception messages containing file contents, URLs or decrypted account data into reports.
                string kind = ex.GetType().Name;
                if (diagnostic) { try { Emit(new { Product = Product, Version = Version, AllPassed = false, Error = kind }); } catch { } }
                else MessageBox.Show("客户端无法启动（" + kind + "）。请检查程序包完整性、Windows 用户权限，以及独立数据目录。公开版只接受全新空目录，或带有公开版标识的数据目录。", Product, MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        private static Dictionary<string, string> Parse(string[] args)
        {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            HashSet<string> flags = new HashSet<string>(new string[] { "version", "verify-package", "self-test", "startup-probe" }, StringComparer.OrdinalIgnoreCase);
            HashSet<string> values = new HashSet<string>(new string[] { "data-root", "report", "render-preview", "preview-view", "close-after-ms" }, StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < args.Length; i++)
            {
                if (!args[i].StartsWith("--", StringComparison.Ordinal)) throw new ArgumentException("InvalidOption");
                string key = args[i].Substring(2);
                if (result.ContainsKey(key)) throw new ArgumentException("DuplicateOption");
                if (flags.Contains(key)) result.Add(key, "true");
                else if (values.Contains(key) && i + 1 < args.Length) result.Add(key, args[++i]);
                else throw new ArgumentException("UnknownOption");
            }
            if (result.ContainsKey("close-after-ms")) { int ms; if (!Int32.TryParse(result["close-after-ms"], out ms) || ms < 250 || ms > 60000) throw new ArgumentException("InvalidDuration"); }
            if (result.ContainsKey("preview-view") && result["preview-view"] != "Main" && result["preview-view"] != "Settings" && result["preview-view"] != "Transfer") throw new ArgumentException("InvalidPreviewView");
            return result;
        }
        private static string Value(Dictionary<string, string> options, string name, string fallback) { string result; return options.TryGetValue(name, out result) ? result : fallback; }
        private static void Emit(object value)
        {
            string json = new JavaScriptSerializer().Serialize(value);
            if (!String.IsNullOrEmpty(reportPath))
            {
                string path = Path.GetFullPath(reportPath); Directory.CreateDirectory(Path.GetDirectoryName(path));
                File.WriteAllText(path, json, new UTF8Encoding(false));
            }
            Console.WriteLine(json);
        }
        private static byte[] Resource(string name)
        {
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
            {
                if (stream == null || stream.Length > 20 * 1024 * 1024) throw new InvalidDataException("MissingResource");
                using (MemoryStream bytes = new MemoryStream()) { stream.CopyTo(bytes); return bytes.ToArray(); }
            }
        }
        private static byte[] ReadAndVerifyPackage(out PackageManifest manifest)
        {
            manifest = new JavaScriptSerializer().Deserialize<PackageManifest>(Encoding.UTF8.GetString(Resource("Client.Manifest.json")));
            byte[] payload = Resource("Client.Payload.zip");
            if (manifest == null || manifest.Version != Version || manifest.PayloadSha256 != Sha256(payload) || manifest.Files == null || manifest.Files.Length != AllowedFiles.Length) throw new InvalidDataException("PackageManifestMismatch");
            HashSet<string> allowed = new HashSet<string>(AllowedFiles, StringComparer.Ordinal);
            Dictionary<string, PackageFile> files = new Dictionary<string, PackageFile>(StringComparer.Ordinal);
            long total = 0;
            foreach (PackageFile file in manifest.Files)
            {
                if (file == null || !allowed.Contains(file.Path) || files.ContainsKey(file.Path) || file.Bytes < 0 || file.Bytes > 4 * 1024 * 1024 || String.IsNullOrEmpty(file.Sha256) || file.Sha256.Length != 64) throw new InvalidDataException("FileOutsideAllowlist");
                SafePath(Path.GetTempPath(), file.Path); files.Add(file.Path, file); total += file.Bytes;
            }
            if (total > 20 * 1024 * 1024) throw new InvalidDataException("PackageTooLarge");
            using (MemoryStream stream = new MemoryStream(payload, false))
            using (ZipArchive zip = new ZipArchive(stream, ZipArchiveMode.Read))
            {
                if (zip.Entries.Count != files.Count) throw new InvalidDataException("ArchiveFileCountMismatch");
                HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
                foreach (ZipArchiveEntry entry in zip.Entries)
                {
                    PackageFile file;
                    if (!files.TryGetValue(entry.FullName, out file) || !seen.Add(entry.FullName) || entry.Length != file.Bytes) throw new InvalidDataException("ArchivePathMismatch");
                    using (Stream content = entry.Open()) { if (Sha256(content) != file.Sha256) throw new InvalidDataException("ArchiveHashMismatch"); }
                }
            }
            return payload;
        }
        private static string CacheRoot() { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3XuiPanelManagerPublic", "app"); }
        private static string PrepareCache(PackageManifest manifest, byte[] payload)
        {
            string root = CacheRoot(); string target = Path.Combine(root, Version, manifest.PayloadSha256);
            EnsureCacheAncestorsSafe(target, Path.GetDirectoryName(root));
            string mutexName = "Local\\Public.ThreeXPanelManager.Payload." + manifest.PayloadSha256;
            using (Mutex extraction = new Mutex(false, mutexName))
            {
                bool owns = false;
                try
                {
                    try { owns = extraction.WaitOne(30000); } catch (AbandonedMutexException) { owns = true; }
                    if (!owns) throw new TimeoutException("CacheBusy");
                    if (VerifyCache(target, manifest)) return target;
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    if (Directory.Exists(target)) DeleteCacheDirectory(target, root);
                    string temporary = target + ".tmp-" + Guid.NewGuid().ToString("N");
                    try
                    {
                        Directory.CreateDirectory(temporary);
                        using (MemoryStream stream = new MemoryStream(payload, false))
                        using (ZipArchive zip = new ZipArchive(stream, ZipArchiveMode.Read))
                        {
                            foreach (ZipArchiveEntry entry in zip.Entries)
                            {
                                string path = SafePath(temporary, entry.FullName); Directory.CreateDirectory(Path.GetDirectoryName(path));
                                using (Stream source = entry.Open()) using (FileStream destination = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None)) source.CopyTo(destination);
                            }
                        }
                        if (!VerifyCache(temporary, manifest)) throw new InvalidDataException("ExtractedHashMismatch");
                        Directory.Move(temporary, target);
                    }
                    finally { if (Directory.Exists(temporary)) DeleteCacheDirectory(temporary, root); }
                    return target;
                }
                finally { if (owns) extraction.ReleaseMutex(); }
            }
        }
        private static void EnsureCacheAncestorsSafe(string directory, string boundary)
        {
            string full = Path.GetFullPath(directory); string stop = Path.GetFullPath(boundary);
            if (!full.StartsWith(stop + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("CacheEscapesApplicationRoot");
            for (string current = full; current != null; current = Path.GetDirectoryName(current))
            {
                if (Directory.Exists(current) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("CacheAncestorReparsePoint");
                if (String.Equals(current, stop, StringComparison.OrdinalIgnoreCase)) return;
            }
            throw new InvalidOperationException("CacheRootNotReached");
        }
        private static bool VerifyCache(string directory, PackageManifest manifest)
        {
            if (!Directory.Exists(directory)) return false;
            CheckCacheDirectories(directory);
            foreach (PackageFile file in manifest.Files)
            {
                string path = SafePath(directory, file.Path);
                if (!File.Exists(path) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0 || new FileInfo(path).Length != file.Bytes) return false;
                using (FileStream bytes = File.OpenRead(path)) { if (Sha256(bytes) != file.Sha256) return false; }
            }
            return Directory.GetFiles(directory, "*", SearchOption.AllDirectories).Length == manifest.Files.Length;
        }
        private static void CheckCacheDirectories(string directory)
        {
            if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("CacheReparsePoint");
            foreach (string child in Directory.GetDirectories(directory, "*", SearchOption.TopDirectoryOnly)) CheckCacheDirectories(child);
        }
        private static string SafePath(string root, string relative)
        {
            if (String.IsNullOrEmpty(relative) || relative.IndexOf('\\') >= 0 || relative.IndexOf(':') >= 0 || Path.IsPathRooted(relative)) throw new InvalidDataException("UnsafeArchivePath");
            foreach (string part in relative.Split('/')) if (part == "." || part == ".." || part.Length == 0) throw new InvalidDataException("UnsafeArchivePart");
            string prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string result = Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
            if (!result.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("ArchiveEscapesRoot");
            return result;
        }
        private static void DeleteCacheDirectory(string directory, string root)
        {
            string prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string full = Path.GetFullPath(directory);
            if (!full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) || full == prefix.TrimEnd(Path.DirectorySeparatorChar)) throw new InvalidOperationException("UnsafeCacheDelete");
            if ((File.GetAttributes(full) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("CacheReparsePoint");
            foreach (string child in Directory.GetDirectories(full, "*", SearchOption.TopDirectoryOnly)) DeleteCacheDirectory(child, root);
            foreach (string file in Directory.GetFiles(full)) { if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("CacheReparseFile"); File.Delete(file); }
            Directory.Delete(full, false);
        }
        private static string ResolveDataRoot(string explicitRoot)
        {
            string root = Path.GetFullPath(String.IsNullOrWhiteSpace(explicitRoot)
                ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3XuiPanelManagerPublic", "data")
                : explicitRoot);
            string cache = Path.GetFullPath(CacheRoot()).TrimEnd(Path.DirectorySeparatorChar);
            if (String.Equals(root.TrimEnd(Path.DirectorySeparatorChar), cache, StringComparison.OrdinalIgnoreCase)
                || (root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar).StartsWith(cache + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("DataCannotBeInsideProgramCache");
            // Never discover a neighboring project, select an existing private folder, or migrate it.
            // A nonempty directory must already belong to this public application.
            for (string current = root; current != null; current = Path.GetDirectoryName(current))
                if (Directory.Exists(current) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidDataException("DataRootAncestorReparsePoint");
            string marker = Path.Combine(root, ".3xui-panel-manager-public.json");
            string inventory = Path.Combine(root, "统一管理", "服务器列表.json");
            if (File.Exists(marker))
            {
                if ((File.GetAttributes(marker) & FileAttributes.ReparsePoint) != 0 || new FileInfo(marker).Length > 4096)
                    throw new InvalidDataException("InvalidPublicDataMarker");
                Dictionary<string, object> identity = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(marker, Encoding.UTF8));
                object product, schema;
                if (identity == null || !identity.TryGetValue("Product", out product) || !identity.TryGetValue("SchemaVersion", out schema)
                    || !String.Equals(Convert.ToString(product), Product, StringComparison.Ordinal) || Convert.ToString(schema) != "1")
                    throw new InvalidDataException("WrongPublicDataIdentity");
                if (Directory.Exists(Path.GetDirectoryName(inventory)) && (File.GetAttributes(Path.GetDirectoryName(inventory)) & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidDataException("PublicDataInventoryDirectoryReparsePoint");
                if (!File.Exists(inventory)) throw new InvalidDataException("PublicDataInventoryMissing");
                if ((File.GetAttributes(inventory) & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidDataException("PublicDataInventoryReparsePoint");
                return root;
            }
            if (Directory.Exists(root) && Directory.GetFileSystemEntries(root).Length != 0)
                throw new InvalidOperationException("RefusingExistingUnmarkedDataRoot");
            Directory.CreateDirectory(Path.GetDirectoryName(inventory));
            File.WriteAllText(inventory, "[]" + Environment.NewLine, new UTF8Encoding(true));
            File.WriteAllText(marker, "{\"Product\":\"3XUI Panel Manager Public\",\"SchemaVersion\":1}" + Environment.NewLine, new UTF8Encoding(false));
            return root;
        }
        private static string CanonicalDirectory(string root)
        {
            using (SafeFileHandle handle = CreateFile(root, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero))
            {
                if (handle.IsInvalid) throw new IOException("DataRootHandleFailed");
                StringBuilder buffer = new StringBuilder(32768); uint length = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0);
                if (length == 0 || length >= buffer.Capacity) throw new IOException("DataRootCanonicalizationFailed");
                string result = buffer.ToString();
                if (result.StartsWith("\\\\?\\UNC\\", StringComparison.OrdinalIgnoreCase)) result = "\\\\" + result.Substring(8);
                else if (result.StartsWith("\\\\?\\", StringComparison.Ordinal)) result = result.Substring(4);
                return result.TrimEnd(Path.DirectorySeparatorChar);
            }
        }
        private static string JoinArguments(IEnumerable<string> values) { List<string> quoted = new List<string>(); foreach (string value in values) quoted.Add(Quote(value)); return String.Join(" ", quoted.ToArray()); }
        private static string Quote(string value)
        {
            // Windows CommandLineToArgvW quoting: quotes and trailing backslashes must be doubled.
            StringBuilder result = new StringBuilder("\""); int slashes = 0;
            foreach (char c in value) { if (c == '\\') { slashes++; continue; } if (c == '"') { result.Append('\\', slashes * 2 + 1); result.Append(c); } else { result.Append('\\', slashes); result.Append(c); } slashes = 0; }
            result.Append('\\', slashes * 2); result.Append('"'); return result.ToString();
        }
        private static string Sha256(byte[] bytes) { using (MemoryStream stream = new MemoryStream(bytes, false)) return Sha256(stream); }
        private static string Sha256(Stream stream) { using (SHA256 hash = SHA256.Create()) { byte[] bytes = hash.ComputeHash(stream); return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant(); } }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, StringBuilder path, uint capacity, uint flags);
    }
}
