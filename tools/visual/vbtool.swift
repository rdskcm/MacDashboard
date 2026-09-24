// tools/visual/vbtool.swift — pixel/window helper for tools/visual/run.sh.
// Compiled fresh at the start of every run: `swiftc -O -o .bin/vbtool vbtool.swift -framework AppKit`.
// Subcommands: preflight, windows, screen, cursor, park-point, alpha-check,
// downscale, diff, sheet, selftest. See tools/visual/README.md for the contract.

import AppKit
import CoreGraphics
import ImageIO

// MARK: - Errors

enum LoadError: Error, CustomStringConvertible {
    case noAlpha
    case cgError(String)
    var description: String {
        switch self {
        case .noAlpha: return "no alpha channel — capture must be screencapture -o -l"
        case .cgError(let s): return s
        }
    }
}

enum AlphaError: Error, CustomStringConvertible {
    case sizeMismatch
    var description: String { "capture size does not match window bounds (shadow included?)" }
}

func fail(_ msg: String, code: Int32 = 3) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(code)
}

// MARK: - Formatting

func fmt(_ d: Double) -> String { String(format: "%.2f", d) }
func fmt1(_ d: Double) -> String { String(format: "%.1f", d) }

func parseWxH(_ s: String) -> (Double, Double)? {
    let parts = s.lowercased().split(separator: "x")
    guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) else { return nil }
    return (w, h)
}

func approxEqual(_ a: Double, _ b: Double, eps: Double = 0.05) -> Bool { abs(a - b) < eps }

// MARK: - Argument parsing (every --flag takes exactly one value; repeatable via array)

func parseOptions(_ args: [String]) -> (positional: [String], options: [String: [String]]) {
    var positional: [String] = []
    var options: [String: [String]] = [:]
    var i = 0
    while i < args.count {
        let a = args[i]
        if a.hasPrefix("--") {
            let key = String(a.dropFirst(2))
            if i + 1 < args.count {
                options[key, default: []].append(args[i + 1])
                i += 2
            } else {
                options[key, default: []].append("true")
                i += 1
            }
        } else {
            positional.append(a)
            i += 1
        }
    }
    return (positional, options)
}

// MARK: - Pixel loading

struct PixelImage {
    var width: Int
    var height: Int
    var pixels: [UInt8] // RGBA8 premultipliedLast
}

func loadCGImage(_ url: URL) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw LoadError.cgError("cannot open \(url.path)")
    }
    guard let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw LoadError.cgError("cannot decode \(url.path)")
    }
    return cg
}

func checkHasAlpha(_ cg: CGImage) throws {
    switch cg.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast:
        throw LoadError.noAlpha
    default:
        break
    }
}

/// Draw at 1:1 into an RGBA8 premultipliedLast sRGB context (no interpolation, copy blend).
func drawRGBA(_ cg: CGImage) throws -> PixelImage {
    let w = cg.width, h = cg.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw LoadError.cgError("cannot create context")
    }
    ctx.interpolationQuality = .none
    ctx.setBlendMode(.copy)
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return PixelImage(width: w, height: h, pixels: pixels)
}

func loadPixelsRequireAlpha(_ url: URL) throws -> PixelImage {
    let cg = try loadCGImage(url)
    try checkHasAlpha(cg)
    return try drawRGBA(cg)
}

func loadPixelsAny(_ url: URL) throws -> PixelImage {
    let cg = try loadCGImage(url)
    return try drawRGBA(cg)
}

func writePNG(_ img: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw LoadError.cgError("cannot create PNG destination \(url.path)")
    }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw LoadError.cgError("cannot write PNG \(url.path)")
    }
}

func makeCGImage(from img: PixelImage) throws -> CGImage {
    var pixels = img.pixels
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: &pixels, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let cgImg = ctx.makeImage() else {
        throw LoadError.cgError("cannot render image")
    }
    return cgImg
}

// MARK: - Alpha-hole check

struct AlphaResult {
    var ok: Bool
    var holePx: Int
    var bbox: (x: Double, y: Double, w: Double, h: Double)?
    var regions: [String]
    var translucentPct: Double
    var cornerR: (tl: Double, tr: Double, bl: Double, br: Double)
    var scale: Double
    var warning: String?
}

/// A pixel (sampled at its centre, x+0.5/y+0.5) is in a corner flap when it lies inside
/// one of the four r x r corner squares AND its distance from that square's inner arc
/// centre is greater than r.
func isCornerFlap(_ x: Int, _ y: Int, pw: Int, ph: Int, r: Double) -> Bool {
    let cx = Double(x) + 0.5, cy = Double(y) + 0.5
    let inTL = cx < r && cy < r
    let inTR = cx >= Double(pw) - r && cy < r
    let inBL = cx < r && cy >= Double(ph) - r
    let inBR = cx >= Double(pw) - r && cy >= Double(ph) - r
    guard inTL || inTR || inBL || inBR else { return false }
    let center: (Double, Double)
    if inTL { center = (r, r) }
    else if inTR { center = (Double(pw) - r, r) }
    else if inBL { center = (r, Double(ph) - r) }
    else { center = (Double(pw) - r, Double(ph) - r) }
    let dx = cx - center.0, dy = cy - center.1
    return (dx * dx + dy * dy).squareRoot() > r
}

func alphaCheck(img: PixelImage, W: Double, H: Double, cornerPt: Double, edgeInsetPx: Int) throws -> AlphaResult {
    let s = Double(img.width) / W
    guard abs(s - s.rounded()) < 0.01 else { throw AlphaError.sizeMismatch }
    guard abs(Double(img.height) - H * s) <= s else { throw AlphaError.sizeMismatch }
    let r = cornerPt * s
    let pw = img.width, ph = img.height

    var holePx = 0
    var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
    var translucentCount = 0
    var checkedCount = 0
    for y in 0..<ph {
        for x in 0..<pw {
            if x < edgeInsetPx || y < edgeInsetPx || x >= pw - edgeInsetPx || y >= ph - edgeInsetPx { continue }
            if isCornerFlap(x, y, pw: pw, ph: ph, r: r) { continue }
            checkedCount += 1
            let idx = (y * pw + x) * 4
            let a = img.pixels[idx + 3]
            if a < 250 { translucentCount += 1 }
            if a == 0 {
                holePx += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }

    var bbox: (Double, Double, Double, Double)? = nil
    var regions: [String] = []
    if holePx > 0 {
        let bx = Double(minX) / s, by = Double(minY) / s
        let bw = Double(maxX - minX + 1) / s, bh = Double(maxY - minY + 1) / s
        bbox = (bx, by, bw, bh)
        if by < 60 { regions.append("titlebar") }
        if bx < 12 { regions.append("left-edge") }
        if bx + bw >= W - 12 { regions.append("right-edge") }
        if by + bh >= H - 12 { regions.append("bottom-edge") }
        if regions.isEmpty { regions.append("interior") }
    }
    let translucentPct = checkedCount > 0 ? Double(translucentCount) / Double(checkedCount) * 100 : 0

    func estimate(_ startX: Int, _ startY: Int, _ dx: Int, _ dy: Int) -> Double {
        let maxSteps = min(pw, ph) / 2
        var i = 0
        while i < maxSteps {
            let x = startX + dx * i, y = startY + dy * i
            if x < 0 || x >= pw || y < 0 || y >= ph { break }
            let idx = (y * pw + x) * 4
            if img.pixels[idx + 3] > 0 { break }
            i += 1
        }
        return Double(i) / (0.2929 * s)
    }
    let tlR = estimate(0, 0, 1, 1)
    let trR = estimate(pw - 1, 0, -1, 1)
    let blR = estimate(0, ph - 1, 1, -1)
    let brR = estimate(pw - 1, ph - 1, -1, -1)

    var warning: String? = nil
    if blR >= cornerPt - 2 || brR >= cornerPt - 2 {
        warning = "WARNING corner radius \u{2248} \(Int(max(blR, brR).rounded())) pt \u{2265} corner_pt-2"
    }

    return AlphaResult(
        ok: holePx == 0, holePx: holePx, bbox: bbox, regions: regions,
        translucentPct: translucentPct, cornerR: (tlR, trR, blR, brR), scale: s, warning: warning
    )
}

func printAlphaLine(_ r: AlphaResult) {
    let bboxStr = r.bbox.map { String(format: "%.2f,%.2f,%.2f,%.2f", $0.x, $0.y, $0.w, $0.h) } ?? "none"
    let regionsStr = r.regions.isEmpty ? "none" : r.regions.joined(separator: ",")
    print(
        "ALPHA \(r.ok ? "ok" : "FAIL") hole_px=\(r.holePx) bbox_pt=\(bboxStr) regions=\(regionsStr) " +
        "translucent_pct=\(fmt(r.translucentPct)) corner_r_pt=\(fmt1(r.cornerR.tl)),\(fmt1(r.cornerR.tr))," +
        "\(fmt1(r.cornerR.bl)),\(fmt1(r.cornerR.br)) scale=\(fmt1(r.scale))"
    )
    if let w = r.warning { print(w) }
}

// MARK: - Diff

func computeDiff(ref: PixelImage, cur: PixelImage, tol: Int) -> (pct: Double, sizeDiffers: Bool, mask: [UInt8]) {
    if ref.width != cur.width || ref.height != cur.height {
        return (100.0, true, [])
    }
    let total = ref.width * ref.height
    var diffCount = 0
    var mask = [UInt8](repeating: 0, count: total * 4)
    for i in 0..<total {
        let o = i * 4
        let dr = abs(Int(ref.pixels[o]) - Int(cur.pixels[o]))
        let dg = abs(Int(ref.pixels[o + 1]) - Int(cur.pixels[o + 1]))
        let db = abs(Int(ref.pixels[o + 2]) - Int(cur.pixels[o + 2]))
        let da = abs(Int(ref.pixels[o + 3]) - Int(cur.pixels[o + 3]))
        let m = max(dr, dg, db, da)
        if m > tol {
            diffCount += 1
            mask[o] = 255; mask[o + 1] = 0; mask[o + 2] = 255; mask[o + 3] = 255
        } else {
            let a = 0.25
            let cr = Double(cur.pixels[o]), cg = Double(cur.pixels[o + 1]), cb = Double(cur.pixels[o + 2])
            mask[o] = UInt8((cr * a + 255 * (1 - a)).rounded())
            mask[o + 1] = UInt8((cg * a + 255 * (1 - a)).rounded())
            mask[o + 2] = UInt8((cb * a + 255 * (1 - a)).rounded())
            mask[o + 3] = 255
        }
    }
    let pct = Double(diffCount) / Double(total) * 100
    return (pct, false, mask)
}

// MARK: - Synthetic image builders (selftest only)

func makeRoundedRect(wPt: Double, hPt: Double, s: Double, radiusPt: Double) -> PixelImage {
    let w = Int((wPt * s).rounded()), h = Int((hPt * s).rounded())
    let radiusPx = radiusPt * s
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h {
        for x in 0..<w {
            let cx = Double(x) + 0.5, cy = Double(y) + 0.5
            var alpha: UInt8 = 255
            let inTL = cx < radiusPx && cy < radiusPx
            let inTR = cx >= Double(w) - radiusPx && cy < radiusPx
            let inBL = cx < radiusPx && cy >= Double(h) - radiusPx
            let inBR = cx >= Double(w) - radiusPx && cy >= Double(h) - radiusPx
            if inTL || inTR || inBL || inBR {
                let center: (Double, Double)
                if inTL { center = (radiusPx, radiusPx) }
                else if inTR { center = (Double(w) - radiusPx, radiusPx) }
                else if inBL { center = (radiusPx, Double(h) - radiusPx) }
                else { center = (Double(w) - radiusPx, Double(h) - radiusPx) }
                let dx = cx - center.0, dy = cy - center.1
                if (dx * dx + dy * dy).squareRoot() > radiusPx { alpha = 0 }
            }
            let idx = (y * w + x) * 4
            pixels[idx] = 255; pixels[idx + 1] = 255; pixels[idx + 2] = 255; pixels[idx + 3] = alpha
        }
    }
    return PixelImage(width: w, height: h, pixels: pixels)
}

func makeSolid(w: Int, h: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> PixelImage {
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    for i in 0..<(w * h) {
        let o = i * 4
        pixels[o] = r; pixels[o + 1] = g; pixels[o + 2] = b; pixels[o + 3] = a
    }
    return PixelImage(width: w, height: h, pixels: pixels)
}

func makeOpaqueCGImage(w: Int, h: Int) -> CGImage {
    var pixels = [UInt8](repeating: 255, count: w * h * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    return ctx.makeImage()!
}

// MARK: - Subcommands

func cmdPreflight() {
    exit(CGPreflightScreenCaptureAccess() ? 0 : 1)
}

func cmdWindows(_ args: [String]) {
    let (_, opts) = parseOptions(args)
    guard let pidStr = opts["pid"]?.first, let pid = pid_t(pidStr) else {
        fail("windows: --pid required", code: 3)
    }
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: AnyObject]] else {
        fail("windows: cannot list windows", code: 3)
    }
    for w in list {
        guard let ownerPID = w[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { continue }
        guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
        guard let alpha = w[kCGWindowAlpha as String] as? Double, alpha > 0 else { continue }
        guard let idNum = w[kCGWindowNumber as String] as? Int else { continue }
        guard let boundsCF = w[kCGWindowBounds as String],
              let rect = CGRect(dictionaryRepresentation: boundsCF as! CFDictionary) else { continue }
        print("\(idNum) \(fmt(rect.origin.x)) \(fmt(rect.origin.y)) \(fmt(rect.width)) \(fmt(rect.height))")
    }
}

func cmdScreen() {
    guard let screen = NSScreen.main else { fail("screen: no main screen", code: 3) }
    let frame = screen.frame
    let vf = screen.visibleFrame
    let scale = screen.backingScaleFactor
    let vx = vf.origin.x
    let vy = frame.height - vf.maxY
    print("\(fmt(frame.width)) \(fmt(frame.height)) \(fmt1(scale)) \(fmt(vx)) \(fmt(vy)) \(fmt(vf.width)) \(fmt(vf.height))")
}

func cmdCursor() {
    guard let loc = CGEvent(source: nil)?.location else { fail("cursor: cannot get location", code: 3) }
    print("\(fmt(loc.x)) \(fmt(loc.y))")
}

func distanceToRect(_ p: CGPoint, _ r: CGRect) -> Double {
    let dx = max(r.minX - p.x, 0, p.x - r.maxX)
    let dy = max(r.minY - p.y, 0, p.y - r.maxY)
    return (dx * dx + dy * dy).squareRoot()
}

func cmdParkPoint(_ args: [String]) {
    let (_, opts) = parseOptions(args)
    var rects: [CGRect] = []
    for s in opts["avoid"] ?? [] {
        let parts = s.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { continue }
        rects.append(CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]))
    }
    guard let screen = NSScreen.main else { fail("park-point: no main screen", code: 3) }
    let frame = screen.frame
    let vf = screen.visibleFrame
    let vx = vf.origin.x
    let vy = frame.height - vf.maxY
    let inset: Double = 40
    let area = CGRect(x: vx + inset, y: vy + inset, width: vf.width - 2 * inset, height: vf.height - 2 * inset)
    guard area.width > 0, area.height > 0 else { exit(1) }
    var best: (pt: CGPoint, dist: Double)? = nil
    let step: Double = 20
    var gy = area.minY
    while gy <= area.maxY {
        var gx = area.minX
        while gx <= area.maxX {
            let p = CGPoint(x: gx, y: gy)
            var inAny = false
            var minDist = Double.greatestFiniteMagnitude
            for r in rects {
                if r.contains(p) { inAny = true; break }
                minDist = min(minDist, distanceToRect(p, r))
            }
            if !inAny {
                if rects.isEmpty { minDist = 0 }
                if best == nil || minDist > best!.dist { best = (p, minDist) }
            }
            gx += step
        }
        gy += step
    }
    guard let b = best else { exit(1) }
    print("\(Int(b.pt.x.rounded())),\(Int(b.pt.y.rounded()))")
}

func cmdAlphaCheck(_ args: [String]) {
    let (pos, opts) = parseOptions(args)
    guard pos.count >= 1, let pointsStr = opts["points"]?.first, let wh = parseWxH(pointsStr) else {
        fail("alpha-check: usage PNG --points WxH", code: 3)
    }
    let cornerPt = Double(opts["corner-pt"]?.first ?? "32") ?? 32
    let edgeInset = Int(opts["edge-inset-px"]?.first ?? "0") ?? 0
    do {
        let img = try loadPixelsRequireAlpha(URL(fileURLWithPath: pos[0]))
        let r = try alphaCheck(img: img, W: wh.0, H: wh.1, cornerPt: cornerPt, edgeInsetPx: edgeInset)
        printAlphaLine(r)
        exit(r.ok ? 0 : 1)
    } catch {
        fail("alpha-check: \(error)", code: 3)
    }
}

func cmdDownscale(_ args: [String]) {
    let (pos, opts) = parseOptions(args)
    guard pos.count >= 2, let sizeStr = opts["size"]?.first, let wh = parseWxH(sizeStr) else {
        fail("downscale: usage IN OUT --size WxH", code: 3)
    }
    do {
        let cg = try loadCGImage(URL(fileURLWithPath: pos[0]))
        let w = Int(wh.0.rounded()), h = Int(wh.1.rounded())
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw LoadError.cgError("cannot create context") }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let outImg = ctx.makeImage() else { throw LoadError.cgError("cannot render") }
        try writePNG(outImg, to: URL(fileURLWithPath: pos[1]))
        exit(0)
    } catch {
        fail("downscale: \(error)", code: 3)
    }
}

func cmdDiff(_ args: [String]) {
    let (pos, opts) = parseOptions(args)
    guard pos.count >= 2, let tolStr = opts["tol"]?.first, let tol = Int(tolStr), let maskPath = opts["mask"]?.first else {
        fail("diff: usage REF CUR --tol N --mask OUT", code: 3)
    }
    do {
        let refImg = try loadPixelsAny(URL(fileURLWithPath: pos[0]))
        let curImg = try loadPixelsAny(URL(fileURLWithPath: pos[1]))
        if refImg.width != curImg.width || refImg.height != curImg.height {
            print("DIFF pct=100.00 size=ref \(refImg.width)x\(refImg.height) cur \(curImg.width)x\(curImg.height)")
            exit(0)
        }
        let (pct, _, mask) = computeDiff(ref: refImg, cur: curImg, tol: tol)
        print("DIFF pct=\(fmt(pct)) size=same")
        let maskImg = try makeCGImage(from: PixelImage(width: refImg.width, height: refImg.height, pixels: mask))
        try writePNG(maskImg, to: URL(fileURLWithPath: maskPath))
        exit(0)
    } catch {
        fail("diff: \(error)", code: 3)
    }
}

func drawCheckerboard(ctx: CGContext, rect: CGRect) {
    let sq: CGFloat = 8
    var rowIdx = 0
    var yy = rect.minY
    while yy < rect.maxY {
        var colIdx = 0
        var xx = rect.minX
        while xx < rect.maxX {
            let isWhite = (rowIdx + colIdx) % 2 == 0
            ctx.setFillColor(isWhite ? CGColor(gray: 1, alpha: 1) : CGColor(red: 0.867, green: 0.867, blue: 0.867, alpha: 1))
            ctx.fill(CGRect(x: xx, y: yy, width: min(sq, rect.maxX - xx), height: min(sq, rect.maxY - yy)))
            xx += sq; colIdx += 1
        }
        yy += sq; rowIdx += 1
    }
}

func drawTile(ctx: CGContext, path: String, rect: CGRect, missingText: String) {
    ctx.saveGState()
    ctx.clip(to: rect)
    drawCheckerboard(ctx: ctx, rect: rect)
    if let cg = try? loadCGImage(URL(fileURLWithPath: path)) {
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        let scale = min(rect.width / iw, rect.height / ih)
        let dw = iw * scale, dh = ih * scale
        let dx = rect.minX + (rect.width - dw) / 2
        let dy = rect.minY + (rect.height - dh) / 2
        let imgRect = CGRect(x: dx, y: dy, width: dw, height: dh)
        // `ctx` was globally y-flipped once (top of cmdSheet) so text and rect
        // fills use top-down coordinates. CGContext.draw(image:in:) assumes an
        // unflipped context, so drawing straight into that flipped `ctx` here
        // renders every image tile vertically mirrored. Counter-flip locally
        // around the image rect's own vertical midline before drawing it.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: imgRect.minY * 2 + imgRect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: imgRect)
        ctx.restoreGState()
    } else {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.darkGray]
        let str = NSAttributedString(string: missingText, attributes: attrs)
        let size = str.size()
        str.draw(at: CGPoint(x: rect.minX + (rect.width - size.width) / 2, y: rect.minY + (rect.height - size.height) / 2))
    }
    ctx.restoreGState()
}

func cmdSheet(_ args: [String]) {
    let (_, opts) = parseOptions(args)
    guard let tsvPath = opts["results"]?.first, let refDir = opts["ref"]?.first,
          let normDir = opts["norm"]?.first, let diffDir = opts["diff"]?.first,
          let title = opts["title"]?.first, let outPath = opts["out"]?.first else {
        fail("sheet: missing options", code: 3)
    }
    do {
        let tsv = try String(contentsOfFile: tsvPath, encoding: .utf8)
        let lines = tsv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var rows: [[String]] = []
        for (i, line) in lines.enumerated() {
            if i == 0 || line.hasPrefix("#") { continue }
            rows.append(line.components(separatedBy: "\t"))
        }
        let tileW: CGFloat = 520, tileH: CGFloat = 360
        let margin: CGFloat = 20
        let labelH: CGFloat = 22
        let titleH: CGFloat = 30
        let rowH = tileH + labelH + margin
        let sheetW = margin * 4 + tileW * 3
        let sheetH = titleH + margin + CGFloat(max(rows.count, 1)) * rowH + margin

        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: Int(sheetW), height: Int(sheetH), bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw LoadError.cgError("cannot create sheet context") }

        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
        // Flip so all subsequent drawing (raster fills, image draws, text) uses top-down coordinates.
        ctx.translateBy(x: 0, y: sheetH)
        ctx.scaleBy(x: 1, y: -1)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

        NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 16)])
            .draw(at: CGPoint(x: margin, y: 6))

        var y = titleH + margin
        for row in rows {
            guard row.count >= 8 else { continue }
            let state = row[0], alpha = row[1], holePx = row[2], regions = row[4]
            let diffPct = row[5], threshold = row[6], verdict = row[7]
            let label = "\(state) \u{2014} alpha: \(alpha) (\(holePx) px, \(regions)) \u{2014} diff: \(diffPct) % (threshold \(threshold) %) \u{2014} \(verdict)"
            NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 12)])
                .draw(at: CGPoint(x: margin, y: y))
            let tileY = y + labelH
            drawTile(ctx: ctx, path: "\(refDir)/\(state).png", rect: CGRect(x: margin, y: tileY, width: tileW, height: tileH), missingText: "no reference")
            drawTile(ctx: ctx, path: "\(normDir)/\(state).png", rect: CGRect(x: margin * 2 + tileW, y: tileY, width: tileW, height: tileH), missingText: "no reference")
            drawTile(ctx: ctx, path: "\(diffDir)/\(state).png", rect: CGRect(x: margin * 3 + tileW * 2, y: tileY, width: tileW, height: tileH), missingText: "size changed")
            y += rowH
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let outImg = ctx.makeImage() else { throw LoadError.cgError("cannot render sheet") }
        try writePNG(outImg, to: URL(fileURLWithPath: outPath))
        exit(0)
    } catch {
        fail("sheet: \(error)", code: 3)
    }
}

func cmdSelftest() {
    var passed = 0
    let total = 9
    func check(_ n: Int, _ cond: Bool, _ detail: @autoclosure () -> String = "") {
        if cond { passed += 1 } else { print("selftest case \(n) FAILED \(detail())") }
    }

    let img1 = makeRoundedRect(wPt: 200, hPt: 100, s: 2, radiusPt: 20)
    let r1 = try! alphaCheck(img: img1, W: 200, H: 100, cornerPt: 32, edgeInsetPx: 0)
    check(1, r1.ok && r1.holePx == 0, "hole_px=\(r1.holePx)")

    var img2 = img1
    for y in 0..<40 { for x in 60..<260 { let idx = (y * img2.width + x) * 4; img2.pixels[idx + 3] = 0 } }
    let r2 = try! alphaCheck(img: img2, W: 200, H: 100, cornerPt: 32, edgeInsetPx: 0)
    let expect2 = 100 * 20 * 4
    check(2,
        !r2.ok && r2.holePx == expect2 && r2.regions.contains("titlebar") && r2.bbox != nil
        && approxEqual(r2.bbox!.x, 30) && approxEqual(r2.bbox!.y, 0) && approxEqual(r2.bbox!.w, 100) && approxEqual(r2.bbox!.h, 20),
        "hole_px=\(r2.holePx) bbox=\(String(describing: r2.bbox))")

    // Amended 2026-09-24: the image centre is at y=50 pt, which lies inside the
    // titlebar band (y < 60 pt), contradicting the "interior" expectation. Use
    // (100 pt, 80 pt) instead, which is outside the titlebar/edge bands.
    var img3 = img1
    let cx3 = Int(100.0 * 2), cy3 = Int(80.0 * 2)
    let idx3 = (cy3 * img3.width + cx3) * 4
    img3.pixels[idx3 + 3] = 0
    let r3 = try! alphaCheck(img: img3, W: 200, H: 100, cornerPt: 32, edgeInsetPx: 0)
    check(3, !r3.ok && r3.holePx == 1 && r3.regions.contains("interior"), "hole_px=\(r3.holePx) regions=\(r3.regions)")

    let img4 = makeRoundedRect(wPt: 200, hPt: 100, s: 2, radiusPt: 30)
    let r4 = try! alphaCheck(img: img4, W: 200, H: 100, cornerPt: 32, edgeInsetPx: 0)
    check(4, r4.ok && r4.holePx == 0, "hole_px=\(r4.holePx)")

    let cg5 = makeOpaqueCGImage(w: 10, h: 10)
    var case5ok = false
    do { try checkHasAlpha(cg5) } catch { case5ok = true }
    check(5, case5ok)

    let a6 = makeSolid(w: 100, h: 100, r: 100, g: 100, b: 100, a: 255)
    let d6 = computeDiff(ref: a6, cur: a6, tol: 24)
    check(6, !d6.sizeDiffers && approxEqual(d6.pct, 0.0))

    var b7 = a6
    for y in 0..<10 { for x in 0..<10 { let o = (y * 100 + x) * 4; b7.pixels[o] = UInt8(min(255, Int(b7.pixels[o]) + 100)) } }
    let d7 = computeDiff(ref: a6, cur: b7, tol: 24)
    check(7, approxEqual(d7.pct, 1.0), "pct=\(d7.pct)")

    let c8 = makeSolid(w: 50, h: 50, r: 100, g: 100, b: 100, a: 255)
    let d8 = computeDiff(ref: a6, cur: c8, tol: 24)
    check(8, d8.sizeDiffers && approxEqual(d8.pct, 100.0))

    var b9 = a6
    for y in 0..<10 { for x in 0..<10 { let o = (y * 100 + x) * 4; b9.pixels[o] = UInt8(min(255, Int(b9.pixels[o]) + 10)) } }
    let d9 = computeDiff(ref: a6, cur: b9, tol: 24)
    check(9, approxEqual(d9.pct, 0.0), "pct=\(d9.pct)")

    print("selftest: \(passed)/\(total) passed")
    exit(passed == total ? 0 : 1)
}

// MARK: - Main

let cliArgs = CommandLine.arguments
guard cliArgs.count > 1 else { fail("usage: vbtool <subcommand> ...", code: 3) }
let cmd = cliArgs[1]
let rest = Array(cliArgs.dropFirst(2))

switch cmd {
case "preflight": cmdPreflight()
case "windows": cmdWindows(rest)
case "screen": cmdScreen()
case "cursor": cmdCursor()
case "park-point": cmdParkPoint(rest)
case "alpha-check": cmdAlphaCheck(rest)
case "downscale": cmdDownscale(rest)
case "diff": cmdDiff(rest)
case "sheet": cmdSheet(rest)
case "selftest": cmdSelftest()
default: fail("unknown subcommand: \(cmd)", code: 3)
}
