#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="${ROOT_DIR}/.build/icons"
ICONSET_DIR="${TMP_DIR}/AppIcon.iconset"
APP_BASE="${TMP_DIR}/AppIconBase.png"
STATUS_ICON="${TMP_DIR}/StatusIconTemplate.png"
APP_ICNS="${TMP_DIR}/AppIcon.icns"

mkdir -p "${TMP_DIR}"
rm -rf "${ICONSET_DIR}" "${APP_BASE}" "${STATUS_ICON}" "${APP_ICNS}"

cat > "${TMP_DIR}/draw_icons.swift" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

func makeContext(size: Int) -> CGContext {
    let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

func writePNG(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建 PNG 输出"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "IconGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG 写入失败"])
    }
}

func drawAppIcon(size: Int) throws -> CGImage {
    let s = CGFloat(size)
    let ctx = makeContext(size: size)
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    let bgRect = rect.insetBy(dx: 32, dy: 32)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 220, cornerHeight: 220, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    let gradientColors: [CGColor] = [
        color(0.20, 0.60, 0.98, 1.0),
        color(0.14, 0.34, 0.86, 1.0)
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 60, y: s - 80),
        end: CGPoint(x: s - 80, y: 60),
        options: []
    )

    ctx.resetClip()
    let windowRect = CGRect(x: 180, y: 250, width: 664, height: 520)
    let windowPath = CGPath(roundedRect: windowRect, cornerWidth: 88, cornerHeight: 88, transform: nil)
    ctx.addPath(windowPath)
    ctx.setFillColor(color(1, 1, 1, 0.92))
    ctx.fillPath()

    let titleBarRect = CGRect(x: windowRect.minX + 34, y: windowRect.maxY - 88, width: windowRect.width - 68, height: 42)
    let titleBarPath = CGPath(roundedRect: titleBarRect, cornerWidth: 20, cornerHeight: 20, transform: nil)
    ctx.addPath(titleBarPath)
    ctx.setFillColor(color(0.88, 0.88, 0.88, 0.95))
    ctx.fillPath()

    let midX = windowRect.midX
    let midY = windowRect.midY - 12
    ctx.setStrokeColor(color(0.15, 0.38, 0.88, 1.0))
    ctx.setLineWidth(24)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: midX - 110, y: midY))
    ctx.addLine(to: CGPoint(x: midX + 110, y: midY))
    ctx.move(to: CGPoint(x: midX, y: midY - 110))
    ctx.addLine(to: CGPoint(x: midX, y: midY + 110))
    ctx.strokePath()

    let dotRect = CGRect(x: midX - 26, y: midY - 26, width: 52, height: 52)
    ctx.setFillColor(color(0.11, 0.30, 0.80, 1.0))
    ctx.fillEllipse(in: dotRect)

    guard let image = ctx.makeImage() else {
        throw NSError(domain: "IconGen", code: 3, userInfo: [NSLocalizedDescriptionKey: "应用图标绘制失败"])
    }
    return image
}

func drawStatusIcon(size: Int) throws -> CGImage {
    let s = CGFloat(size)
    let ctx = makeContext(size: size)
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    ctx.clear(rect)

    let windowRect = CGRect(x: 8, y: 10, width: 48, height: 36)
    let windowPath = CGPath(roundedRect: windowRect, cornerWidth: 7, cornerHeight: 7, transform: nil)
    ctx.addPath(windowPath)
    ctx.setStrokeColor(color(0, 0, 0, 1))
    ctx.setLineWidth(4)
    ctx.strokePath()

    ctx.setStrokeColor(color(0, 0, 0, 1))
    ctx.setLineWidth(4)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: windowRect.midX - 10, y: windowRect.midY))
    ctx.addLine(to: CGPoint(x: windowRect.midX + 10, y: windowRect.midY))
    ctx.move(to: CGPoint(x: windowRect.midX, y: windowRect.midY - 10))
    ctx.addLine(to: CGPoint(x: windowRect.midX, y: windowRect.midY + 10))
    ctx.strokePath()

    guard let image = ctx.makeImage() else {
        throw NSError(domain: "IconGen", code: 4, userInfo: [NSLocalizedDescriptionKey: "状态栏图标绘制失败"])
    }
    return image
}

let outputDir = CommandLine.arguments[1]
try writePNG(drawAppIcon(size: 1024), to: outputDir + "/AppIconBase.png")
try writePNG(drawStatusIcon(size: 64), to: outputDir + "/StatusIconTemplate.png")
SWIFT

swift "${TMP_DIR}/draw_icons.swift" "${TMP_DIR}"

mkdir -p "${ICONSET_DIR}"

make_icon() {
  local px="$1"
  local name="$2"
  sips -s format png -z "${px}" "${px}" "${APP_BASE}" --out "${ICONSET_DIR}/${name}" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

iconutil -c icns "${ICONSET_DIR}" -o "${APP_ICNS}"
echo "图标已生成: ${APP_ICNS}, ${STATUS_ICON}"
