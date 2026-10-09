import SwiftUI
import OpenLatchCore

struct PrimaryButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringKey
    var symbol: String? = nil
    var doorMark = false
    var busy = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if !dynamicTypeSize.isAccessibilitySize && (busy || doorMark || symbol != nil) {
                    ZStack {
                        if busy {
                            ProgressView().tint(.white)
                        } else if doorMark {
                            CarDoorMark().fill(.white, style: FillStyle(eoFill: true))
                        } else if let symbol {
                            Image(systemName: symbol)
                        }
                    }
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
                }
                Text(title).fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .disabled(!enabled || busy)
        .accessibilityLabel(Text(title))
        .accessibilityValue(busy ? Text("Waiting…") : Text(""))
    }
}

/// Scrolls when text grows or the phone is short; otherwise fills the screen
/// so the primary action stays comfortably within reach.
struct FlowLayout<Content: View>: View {
    var alignment: Alignment = .center
    @ViewBuilder var content: Content
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) { content }
                    .frame(maxWidth: 460)
                    .frame(minHeight: max(0, geometry.size.height - 48), alignment: alignment)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

struct InlineFeedback: View {
    let text: String?
    var success = false
    var body: some View {
        if let text {
            Label(text, systemImage: success ? "checkmark.circle.fill" : "info.circle")
                .font(.subheadline)
                .foregroundStyle(success ? Color.green : .secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("feedback")
        }
    }
}

/// Reserve the same line before, during and after an action so feedback does
/// not redistribute the screen's spacers and move the car illustration.
struct DoorFeedback: View {
    let text: String?
    var success = false
    var body: some View {
        Text(text ?? String(localized: "Door open"))
            .font(.headline)
            .foregroundStyle(success ? Color(uiColor: .label) : .secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background {
                Capsule().fill(Color.blue.opacity(0.14))
                    .opacity(success ? 1 : 0)
            }
            .opacity(text == nil ? 0 : 1)
            .accessibilityHidden(text == nil)
            .accessibilityIdentifier("feedback")
    }
}

struct BrandIcon: View {
    var size: CGFloat = 104
    var body: some View {
        Image("BrandIcon")
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct CarIllustration: View {
    var model: VehicleModel = .unknown
    var maximumWidth: CGFloat = 290

    var body: some View {
        Group {
            if model == .unknown {
                ZStack {
                    Circle().fill(Color.blue.opacity(0.08))
                    Image(systemName: "car.side")
                        .font(.system(size: 66, weight: .light))
                        .foregroundStyle(.blue)
                }
                .frame(width: 156, height: 156)
            } else {
                Image("CarFront-\(model.rawValue)")
                    .resizable().scaledToFit()
            }
        }
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: maximumWidth)
            .accessibilityHidden(true)
    }
}

extension VehicleDoor {
    var symbolName: String {
        switch self {
        case .driver: "car.top.door.front.left.open"
        case .passenger: "car.top.door.front.right.open"
        case .rearDriver: "car.top.door.rear.left.open"
        case .rearPassenger: "car.top.door.rear.right.open"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .driver: "Driver door"
        case .passenger: "Passenger door"
        case .rearDriver: "Rear driver-side door"
        case .rearPassenger: "Rear passenger-side door"
        }
    }

    var openTitle: LocalizedStringKey {
        switch self {
        case .driver: "Open driver door"
        case .passenger: "Open passenger door"
        case .rearDriver: "Open rear driver-side door"
        case .rearPassenger: "Open rear passenger-side door"
        }
    }
}

/// A vehicle keycard resting on a reader, without payment-card markings.
struct KeyCardIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.18), lineWidth: 2)
                }
                .frame(width: 154, height: 94)
                .offset(x: 12, y: 15)
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(.blue.opacity(0.65))
                .offset(x: 64, y: 42)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.blue)
                .overlay {
                    Image(systemName: "car.side")
                        .font(.system(size: 43, weight: .light))
                        .foregroundStyle(.white)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(10)
                }
                .frame(width: 126, height: 80)
                .rotationEffect(.degrees(-12))
                .offset(x: -13, y: -10)
        }
        .frame(width: 190, height: 144)
        .accessibilityHidden(true)
    }
}

/// The same car-door silhouette as the app mark, with a transparent window.
private struct CarDoorMark: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        return Path { p in
            p.move(to: CGPoint(x: w*0.12, y: h*0.50))
            p.addQuadCurve(to: CGPoint(x: w*0.87, y: h*0.08), control: CGPoint(x: w*0.44, y: h*0.10))
            p.addLine(to: CGPoint(x: w*0.86, y: h*0.82))
            p.addQuadCurve(to: CGPoint(x: w*0.20, y: h*0.94), control: CGPoint(x: w*0.53, y: h*0.93))
            p.addLine(to: CGPoint(x: w*0.12, y: h*0.50))
            p.closeSubpath()
            p.move(to: CGPoint(x: w*0.25, y: h*0.47))
            p.addQuadCurve(to: CGPoint(x: w*0.77, y: h*0.20), control: CGPoint(x: w*0.49, y: h*0.23))
            p.addLine(to: CGPoint(x: w*0.77, y: h*0.44))
            p.closeSubpath()
            p.addRoundedRect(in: CGRect(x: w*0.62, y: h*0.55, width: w*0.16, height: h*0.04), cornerSize: CGSize(width: w*0.02, height: w*0.02))
        }
    }
}
