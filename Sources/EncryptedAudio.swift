import Foundation
import JavaScriptCore

// MARK: - 加密音频格式

/// 需要解密才能交给 ffmpeg 处理的音乐格式。
///
/// 这里的分类对应内置 WebAssembly 引擎里的不同解密路径，
/// 扩展名集合与 翱翔音频转换大师 保持一致，另补充了酷狗 / 酷我 / 虾米等。
enum EncryptedAudioFormat: String, CaseIterable {
    case ncm      // 网易云音乐
    case qmc1     // QQ 音乐旧版：qmc0/qmc2/qmc3/qmcflac/qmcogg、bkc*、tkm
    case qmc2     // QQ 音乐新版：mflac / mgg（ekey 内嵌在文件尾部）
    case kugou    // 酷狗：kgm / vpr
    case kuwo     // 酷我：kwm
    case xiami    // 虾米：xm
    case migu3d   // 咪咕：mg3d

    /// 该分类覆盖的扩展名
    var extensions: Set<String> {
        switch self {
        case .ncm:
            return ["ncm"]
        case .qmc1:
            return ["qmc0", "qmc2", "qmc3", "qmcflac", "qmcogg", "qmc", "qmcra",
                    "bkcmp3", "bkcflac", "tkm",
                    "666c6163", "6d7033", "6f6767", "6d3461", "776176"]
        case .qmc2:
            return ["mflac", "mflac0", "mgg", "mgg0", "mgg1", "mggl", "mmp4"]
        case .kugou:
            return ["kgm", "vpr"]
        case .kuwo:
            return ["kwm"]
        case .xiami:
            return ["xm"]
        case .migu3d:
            return ["mg3d"]
        }
    }

    /// 解密后最可能的容器（嗅探失败时的兜底）
    var fallbackExtension: String {
        switch self {
        case .ncm:             return "mp3"
        case .qmc1:            return "mp3"
        case .qmc2:            return "flac"
        case .kugou, .kuwo:    return "mp3"
        case .xiami:           return "mp3"
        case .migu3d:          return "mp3"
        }
    }

    var displayName: String {
        switch self {
        case .ncm:    return "网易云音乐 (ncm)"
        case .qmc1:   return "QQ 音乐 (qmc)"
        case .qmc2:   return "QQ 音乐 (mflac/mgg)"
        case .kugou:  return "酷狗音乐"
        case .kuwo:   return "酷我音乐"
        case .xiami:  return "虾米音乐"
        case .migu3d: return "咪咕音乐"
        }
    }
}

enum EncryptedAudioError: LocalizedError {
    case engineUnavailable(String)
    case unsupportedExtension(String)
    case unreadableFile(URL)
    case decryptionFailed(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .engineUnavailable(let why):
            return "解密引擎未就绪：\(why)"
        case .unsupportedExtension(let ext):
            return "不支持的加密格式 .\(ext)"
        case .unreadableFile(let url):
            return "无法读取文件：\(url.lastPathComponent)"
        case .decryptionFailed(let why):
            return why
        case .emptyOutput:
            return "解密结果为空，文件可能已损坏"
        }
    }
}

// MARK: - 解密引擎

/// 加密音乐解密器。
///
/// 实现思路：用系统自带的 JavaScriptCore 执行内置的 WebAssembly 模块
/// （unlock-music 项目的 Rust 实现，MIT / Apache-2.0 双许可）。
/// 这样 App 不需要 node、不需要 ncmdump、不依赖 Homebrew，完全自包含离线运行。
///
/// 线程模型：JSContext 只能在单一线程上访问，所以所有 JS 调用都派发到
/// 内部串行队列执行，外部暴露同步接口（调用方本就在后台线程）。
final class AudioDecryptor {

    static let shared = AudioDecryptor()

    /// 全部受支持的加密扩展名
    static let supportedExtensions: Set<String> = {
        var set = Set<String>()
        for f in EncryptedAudioFormat.allCases { set.formUnion(f.extensions) }
        return set
    }()

    static func isEncrypted(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func format(of url: URL) -> EncryptedAudioFormat? {
        let ext = url.pathExtension.lowercased()
        return EncryptedAudioFormat.allCases.first { $0.extensions.contains(ext) }
    }

    // MARK: 私有状态

    private let queue = DispatchQueue(label: "com.aoxing.transmute.decrypt", qos: .userInitiated)
    private var context: JSContext?
    /// 每次喂给 JS 的字节数。必须是 3 的倍数，否则分块 base64 中间会出现 '=' 填充，
    /// 拼接后 Swift 端 Data(base64Encoded:) 会解析失败返回 nil。
    private static let feedChunkBytes = 3 * 1024 * 1024      // 3 MB
    /// 从 JS 取回结果时的分块大小，同样必须是 3 的倍数。
    private static let drainChunkBytes = 3 * 8192            // 24576 B

    private init() {}

    // MARK: - 对外接口

    /// 解密单个文件。
    /// - Returns: 解密产物的 URL（位于临时目录，调用方负责清理所在目录）
    func decrypt(fileAt url: URL, progress: ((Double) -> Void)? = nil) throws -> URL {
        guard let format = Self.format(of: url) else {
            throw EncryptedAudioError.unsupportedExtension(url.pathExtension)
        }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber, size.int64Value > 0 else {
            throw EncryptedAudioError.unreadableFile(url)
        }

        // JS 侧全部在串行队列里跑，避免 JSContext 被并发访问
        return try queue.sync {
            let ctx = try makeContext()
            let total = size.int64Value

            try prepare(total: total)
            try feed(fileAt: url, total: total, progress: progress)

            let result = try run(kind: format, in: ctx)
            let produced = result

            progress?(0.9)
            let tempDir = Self.makeTempDirectory()
            let sniffed = try drain(to: tempDir, length: produced)
            clearBuffers()

            let finalURL = tempDir.appendingPathComponent(Self.outputName(for: url, extension: sniffed))
            let rawURL = tempDir.appendingPathComponent("decoded.bin")
            try FileManager.default.moveItem(at: rawURL, to: finalURL)
            progress?(1.0)
            return finalURL
        }
    }

    // MARK: - 引擎初始化

    private func makeContext() throws -> JSContext {
        if let ctx = context { return ctx }

        guard let loaderURL = Self.locateLoader() else {
            throw EncryptedAudioError.engineUnavailable("找不到内置解密模块 unlock-music-loader.js")
        }
        let loaderSource: String
        do {
            loaderSource = try String(contentsOf: loaderURL, encoding: .utf8)
        } catch {
            throw EncryptedAudioError.engineUnavailable("读取解密模块失败：\(error.localizedDescription)")
        }

        let ctx = JSContext()!
        ctx.exceptionHandler = { _, exception in
            // 异常大多来自 WASM 内部的 panic，记录下来避免静默失败
            if let ex = exception {
                NSLog("[AudioDecryptor] JS 异常: \(ex)")
            }
        }

        ctx.evaluateScript(Self.polyfillSource)
        // 把 CJS 模块包进函数作用域，导出对象挂到全局，避免依赖 require
        ctx.evaluateScript(
            "(function(){var module={exports:{}};var exports=module.exports;\n"
            + loaderSource
            + "\n;globalThis.__UMCRYPTO = module.exports;})();"
        )
        ctx.evaluateScript(Self.engineSource)

        let ok: Bool
        do {
            ok = try initializeWASM(in: ctx)
        } catch {
            throw EncryptedAudioError.engineUnavailable(error.localizedDescription)
        }
        guard ok else {
            throw EncryptedAudioError.engineUnavailable("WebAssembly 模块初始化失败")
        }

        context = ctx
        return ctx
    }

    private func initializeWASM(in ctx: JSContext) throws -> Bool {
        let result = ctx.evaluateScript(
            "(function(){ try { globalThis.__UMCRYPTO.initSync(); return 'ok'; } catch(e) { return String(e); } })()"
        )
        guard let text = result?.toString() else { return false }
        if text == "ok" { return true }
        throw EncryptedAudioError.engineUnavailable(text)
    }

    /// 在 app bundle / 可执行文件旁 / 源码树中定位解密模块。
    /// CLI 回归测试从仓库根目录跑，所以必须支持源码树路径。
    private static func locateLoader() -> URL? {
        let fm = FileManager.default
        let name = "unlock-music-loader.js"

        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent(name))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources").appendingPathComponent(name))
        if let exePath = CommandLine.arguments.first {
            let exeDir = URL(fileURLWithPath: exePath).deletingLastPathComponent()
            candidates.append(exeDir.appendingPathComponent(name))
            candidates.append(exeDir.appendingPathComponent("Resources").appendingPathComponent(name))
            candidates.append(
                exeDir.deletingLastPathComponent()
                    .appendingPathComponent("Sources")
                    .appendingPathComponent("Resources")
                    .appendingPathComponent(name)
            )
        }
        candidates.append(
            URL(fileURLWithPath: fm.currentDirectoryPath)
                .appendingPathComponent("Sources")
                .appendingPathComponent("Resources")
                .appendingPathComponent(name)
        )

        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    // MARK: - JS 交互

    private func prepare(total: Int64) throws {
        try call("globalThis.__UMprepare(\(total))")
    }

    private func feed(fileAt url: URL, total: Int64, progress: ((Double) -> Void)?) throws {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw EncryptedAudioError.unreadableFile(url)
        }
        defer { try? handle.close() }

        guard let feedFn = context?.objectForKeyedSubscript("__UMfeed") else {
            throw EncryptedAudioError.engineUnavailable("数据入口丢失")
        }

        let chunk = Self.feedChunkBytes
        var sent: Int64 = 0
        while sent < total {
            let data = handle.readData(ofLength: chunk)
            if data.isEmpty { break }

            feedFn.call(withArguments: [data.base64EncodedString()])
            sent += Int64(data.count)
            // 喂数据阶段占整体进度的 80%
            progress?(min(Double(sent) / Double(total), 1.0) * 0.8)
        }

        guard sent == total else {
            throw EncryptedAudioError.unreadableFile(url)
        }
    }

    private func run(kind: EncryptedAudioFormat, in ctx: JSContext) throws -> Int {
        guard let fn = ctx.objectForKeyedSubscript("__UMrun") else {
            throw EncryptedAudioError.engineUnavailable("解密入口丢失")
        }
        let text = fn.call(withArguments: [kind.rawValue])?.toString() ?? "ERR|引擎无返回"
        if text.hasPrefix("OK|") {
            let lenPart = text.dropFirst(3)
            return Int(lenPart) ?? 0
        }
        let reason = String(text.dropFirst(4))
        throw EncryptedAudioError.decryptionFailed(reason)
    }

    private func drain(to directory: URL, length: Int) throws -> String {
        guard length > 0 else { throw EncryptedAudioError.emptyOutput }

        let ctx = context!
        guard let lenFn = ctx.objectForKeyedSubscript("__UMoutLen"),
              let chunkFn = ctx.objectForKeyedSubscript("__UMchunk") else {
            throw EncryptedAudioError.engineUnavailable("结果读取入口丢失")
        }

        // 用引擎自己报的长度做一次交叉校验，避免拿 run() 声明的长度去读越界数据
        if let reported = lenFn.call(withArguments: [])?.toInt32(), Int(reported) != length {
            throw EncryptedAudioError.decryptionFailed(
                "解密结果长度不一致（声明 \(length)，实际 \(reported)）"
            )
        }

        let fileURL = directory.appendingPathComponent("decoded.bin")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: fileURL)

        var offset = 0
        var sniffed: String?
        while offset < length {
            let count = min(Self.drainChunkBytes, length - offset)
            guard let b64 = chunkFn.call(withArguments: [offset, count])?.toString(),
                  let data = Data(base64Encoded: b64), !data.isEmpty else {
                try? handle.close()
                throw EncryptedAudioError.decryptionFailed("读取解密结果失败（偏移 \(offset)）")
            }
            // 首块里嗅探真实格式，用来决定最终扩展名
            if sniffed == nil {
                sniffed = Self.sniffAudioExtension(data)
            }
            handle.write(data)
            offset += count
        }
        try handle.close()
        return sniffed ?? "mp3"
    }

    private func clearBuffers() {
        _ = try? call("globalThis.__UMclear()")
    }

    /// 在当前串行队列里执行一段 JS 表达式。
    private func call(_ expression: String) throws {
        guard let ctx = context else {
            throw EncryptedAudioError.engineUnavailable("引擎未初始化")
        }
        ctx.evaluateScript(expression)
    }

    // MARK: - 工具

    private static func makeTempDirectory() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("transmute-decrypt-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func outputName(for source: URL, extension ext: String) -> String {
        let base = source.deletingPathExtension().lastPathComponent
        return "\(base).\(ext)"
    }

    /// 清掉上次运行留下的解密临时目录。
    /// 崩溃或被强杀时 defer 不会执行，这里做一次兜底，避免 /tmp 堆积上百 MB 副本。
    static func sweepStaleTempDirectories() {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        guard let entries = try? fm.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix("transmute-decrypt-") {
            try? fm.removeItem(at: entry)
        }
    }

    /// 根据文件头判断真实音频格式。
    /// 解密后的文件扩展名必须由内容决定——同一个 .mflac 解出来可能是 flac 也可能是 mp3。
    static func sniffAudioExtension(_ data: Data) -> String? {
        guard data.count >= 12 else { return nil }
        let b = [UInt8](data.prefix(12))

        // ID3v2 标签，或者 MPEG 帧同步字
        if b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33 { return "mp3" }
        if b[0] == 0xFF && (b[1] & 0xE0) == 0xE0 { return "mp3" }
        // fLaC
        if b[0] == 0x66 && b[1] == 0x4C && b[2] == 0x61 && b[3] == 0x43 { return "flac" }
        // OggS
        if b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53 { return "ogg" }
        // RIFF....WAVE
        if b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
           b[8] == 0x57 && b[9] == 0x41 && b[10] == 0x56 && b[11] == 0x45 { return "wav" }
        // ....ftyp (MP4/M4A 家族)
        if b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70 { return "m4a" }
        // #!AMR
        if b[0] == 0x23 && b[1] == 0x21 && b[2] == 0x41 && b[3] == 0x4D && b[4] == 0x52 { return "amr" }
        return nil
    }
}

// MARK: - 注入的 JavaScript

extension AudioDecryptor {

    /// JavaScriptCore 缺少浏览器环境的一部分全局对象，wasm-bindgen 的胶水代码依赖它们。
    /// 这里补齐 atob / btoa / TextDecoder / TextEncoder / performance。
    /// 注意：JSC 原生就支持 WebAssembly，所以不需要任何外部运行时。
    static let polyfillSource = """
    globalThis.atob = function(s){
      var B = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      s = s.replace(/[=]{1,2}$/, '');
      var n = s.length, out = [], buf = 0, bits = 0;
      for (var i = 0; i < n; i++){
        buf = (buf << 6) | B.indexOf(s[i]); bits += 6;
        if (bits >= 8){ bits -= 8; out.push((buf >> bits) & 0xff); }
      }
      var r = '';
      for (var k = 0; k < out.length; k += 32768) r += String.fromCharCode.apply(null, out.slice(k, k + 32768));
      return r;
    };
    globalThis.btoa = function(s){
      var B = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      var n = s.length, out = [], i = 0;
      while (i < n){
        var c1 = s.charCodeAt(i++), c2 = s.charCodeAt(i++), c3 = s.charCodeAt(i++);
        var e2 = isNaN(c2), e3 = isNaN(c3);
        out.push(B.charCodeAt(c1 >> 2), B.charCodeAt(((c1 & 3) << 4) | (e2 ? 0 : c2 >> 4)));
        out.push(e2 ? 61 : B.charCodeAt(((c2 & 15) << 2) | (e3 ? 0 : c3 >> 6)));
        out.push(e3 ? 61 : B.charCodeAt(c3 & 63));
      }
      var r = '';
      for (var k = 0; k < out.length; k += 32768) r += String.fromCharCode.apply(null, out.slice(k, k + 32768));
      return r;
    };
    globalThis.TextDecoder = function(enc){ this.encoding = enc || 'utf-8'; };
    globalThis.TextDecoder.prototype.decode = function(b){
      if (b == null) return '';
      var u = (b instanceof Uint8Array) ? b : new Uint8Array(b);
      var o = [], i = 0, n = u.length;
      while (i < n){
        var c = u[i];
        if (c < 0x80){ o.push(c); i += 1; }
        else if (c < 0xE0){ o.push(((c & 0x1F) << 6) | (u[i+1] & 0x3F)); i += 2; }
        else if (c < 0xF0){ o.push(((c & 0x0F) << 12) | ((u[i+1] & 0x3F) << 6) | (u[i+2] & 0x3F)); i += 3; }
        else {
          var cp = ((c & 0x07) << 18) | ((u[i+1] & 0x3F) << 12) | ((u[i+2] & 0x3F) << 6) | (u[i+3] & 0x3F);
          cp -= 0x10000; o.push(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF)); i += 4;
        }
      }
      var s = '';
      for (var k = 0; k < o.length; k += 32768) s += String.fromCharCode.apply(null, o.slice(k, k + 32768));
      return s;
    };
    globalThis.TextEncoder = function(){};
    globalThis.TextEncoder.prototype.encode = function(s){
      var u = unescape(encodeURIComponent(s)), o = new Uint8Array(u.length);
      for (var i = 0; i < u.length; i++) o[i] = u.charCodeAt(i);
      return o;
    };
    globalThis.performance = { now: function(){ return Date.now(); } };
    globalThis.crypto = globalThis.crypto || {
      getRandomValues: function(a){ for (var i = 0; i < a.length; i++) a[i] = (Math.random()*256)|0; return a; }
    };
    """

    /// 引擎入口：分块喂入数据 → 解密 → 分块取回结果。
    /// 全程不在 JS 与原生之间传递整文件字符串，避免大文件把内存打爆。
    static let engineSource = """
    globalThis.__UM = { raw: null, pos: 0, out: null };

    globalThis.__UMprepare = function(total){
      globalThis.__UM.raw = new Uint8Array(total);
      globalThis.__UM.pos = 0;
      globalThis.__UM.out = null;
    };

    globalThis.__UMfeed = function(b64){
      var s = globalThis.atob(b64), a = globalThis.__UM.raw, p = globalThis.__UM.pos;
      for (var i = 0; i < s.length; i++) a[p + i] = s.charCodeAt(i) & 0xff;
      globalThis.__UM.pos += s.length;
      return globalThis.__UM.pos;
    };

    globalThis.__UMrun = function(kind){
      try {
        var C = globalThis.__UMCRYPTO, raw = globalThis.__UM.raw, out = null;
        if (kind === 'ncm'){
          var f = new C.NCMFile();
          var need = f.open(raw.slice(0, 8192)), guard = 0, want = 8192;
          while (need > 0 && guard++ < 12){
            want = Math.min(raw.length, want * 4);
            if (want >= raw.length){
              // 整个文件都喂进去了还缺字节，说明头部本身不合法
              need = f.open(raw);
              break;
            }
            need = f.open(raw.slice(0, want));
          }
          if (need !== 0){
            throw new Error('不是合法的 NCM 文件（open 返回 ' + need + '）');
          }
          out = raw.slice(f.audioOffset);
          f.decrypt(out, 0);
        } else if (kind === 'qmc2'){
          var footer = C.QMCFooter.parse(raw.slice(-1024));
          if (!footer){
            throw new Error('QMC2 尾部解析失败，不是合法的 mflac / mgg 文件');
          }
          if (!footer.ekey){
            throw new Error('该文件没有内嵌密钥（QQ 音乐 1763+ 新版由服务器下发），离线无法解密。\\n' +
                            '可改用旧版 QQ 音乐客户端重新下载，或使用在线解锁工具。');
          }
          out = new Uint8Array(raw.slice(0, raw.length - footer.size));
          var cipher = new C.QMC2(footer.ekey);
          cipher.decrypt(out, 0);
        } else if (kind === 'qmc1'){
          out = new Uint8Array(raw);
          C.decryptQMC1(out, 0);
        } else {
          throw new Error('暂未支持的加密类型: ' + kind);
        }
        globalThis.__UM.out = out;
        return 'OK|' + out.length;
      } catch (e) {
        return 'ERR|' + (e && e.message ? e.message : String(e));
      }
    };

    globalThis.__UMoutLen = function(){
      return globalThis.__UM.out ? globalThis.__UM.out.length : 0;
    };

    globalThis.__UMchunk = function(off, count){
      var a = globalThis.__UM.out, end = Math.min(off + count, a.length), s = '';
      for (var i = off; i < end; i++) s += String.fromCharCode(a[i]);
      return globalThis.btoa(s);
    };

    globalThis.__UMclear = function(){
      globalThis.__UM.raw = null;
      globalThis.__UM.out = null;
      globalThis.__UM.pos = 0;
    };
    """
}
