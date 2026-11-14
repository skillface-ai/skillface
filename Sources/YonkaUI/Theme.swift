import AppKit
import SwiftUI
import YonkaCore

/// Yonka's own look: a dark room where the apps are what's lit. A serif for what it says, a
/// monospace for small labels, one accent. An app's own interface is not this: it's the app's.
enum Theme {
    static let ink = Color(red: 0.047, green: 0.051, blue: 0.063)
    static let panel = Color(red: 0.082, green: 0.090, blue: 0.106)
    static let raised = Color(red: 0.133, green: 0.145, blue: 0.169)
    static let line = Color(red: 0.165, green: 0.180, blue: 0.212)
    static let rule = Color(red: 0.290, green: 0.314, blue: 0.361)
    static let dim = Color(red: 0.639, green: 0.659, blue: 0.702)
    static let soft = Color(red: 0.788, green: 0.804, blue: 0.839)
    static let accent = Color(red: 1, green: 0.416, blue: 0.278)

    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
    static let label = Font.system(size: 11, design: .monospaced)

    /// Room for the window's close, minimise and zoom buttons, which sit over the content.
    static let lights: CGFloat = 78
}

extension View {
    /// The content, lifted off the room: rounded, with a hairline.
    func stage() -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return background(Color(nsColor: .textBackgroundColor))
            .clipShape(shape)
            .overlay { shape.strokeBorder(Theme.line, lineWidth: 1) }
    }

    /// A quiet round button: an outline, or filled when it's the thing to press.
    func pill(filled: Bool = false, on: Bool = false) -> some View {
        font(.system(size: 13, weight: filled ? .bold : .regular))
            .foregroundStyle(filled ? Theme.ink : .primary)
            .padding(.horizontal, 16).frame(height: 32)
            .background(filled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(on ? Theme.accent.opacity(0.12) : .clear), in: Capsule())
            .overlay { Capsule().strokeBorder(on ? Theme.accent : Theme.rule, lineWidth: filled ? 0 : 1) }
            .contentShape(Capsule())
            // Never squeezed: a row short of room gives it up elsewhere.
            .fixedSize()
    }
}

/// An app's icon: its symbol on a swatch of its own colour, the same on every Mac. One still
/// being built is only an outline.
struct AppTile: View {
    let app: SkillApp
    var size: CGFloat = 46

    var body: some View {
        let hash = app.id.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        let hue = Color(hue: Double(hash % 360) / 360, saturation: 0.5, brightness: 0.92)
        // The builder picks the symbol, and may name one this Mac doesn't have.
        let symbol = NSImage(systemSymbolName: app.info.symbol, accessibilityDescription: nil) == nil ? "sparkles" : app.info.symbol
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        let building = app.info.stage != .done
        shape.fill(building ? AnyShapeStyle(.clear) : AnyShapeStyle(hue))
            .overlay { if building { shape.strokeBorder(hue, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) } }
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol).font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(building ? hue : Theme.ink)
            }
    }
}
