import UIKit
import SwiftUI

private var maskedKey: UInt8 = 0

public extension UIView {
    /// Paints this view (and everything inside it) black in frames sent to the agent.
    var isSideSeatMasked: Bool {
        get { (objc_getAssociatedObject(self, &maskedKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &maskedKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

public extension View {
    /// Paints this view black in frames sent to the agent.
    func sideSeatMasked() -> some View {
        background(MaskMarker())
    }
}

public enum MaskRules {
    /// Masks the whole root view of any view controller of the given types.
    public static func screens(_ types: [UIViewController.Type]) -> (UIView) -> Bool {
        { view in
            guard let controller = view.next as? UIViewController, controller.viewIfLoaded === view else { return false }
            return types.contains { controller.isKind(of: $0) }
        }
    }
}

private struct MaskMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isSideSeatMasked = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

enum MaskCollector {

    static let padding: CGFloat = 2

    static func rects(in window: UIWindow, rule: ((UIView) -> Bool)? = nil) -> [CGRect] {
        var masks: [CGRect] = []

        func visit(_ view: UIView, clip: CGRect) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            let frame = view.convert(view.bounds, to: window)
            if isMasked(view, rule: rule) {
                let visible = frame.intersection(clip)
                if !visible.isNull, visible.width >= 1, visible.height >= 1 { masks.append(visible) }
                return
            }
            if covers(view) { masks.removeAll { frame.contains($0) } }
            let childClip = view.clipsToBounds ? clip.intersection(frame) : clip
            view.subviews.forEach { visit($0, clip: childClip) }
        }

        window.subviews.forEach { visit($0, clip: window.bounds) }
        return masks.map { $0.insetBy(dx: -padding, dy: -padding) }
    }

    private static func isMasked(_ view: UIView, rule: ((UIView) -> Bool)?) -> Bool {
        if view.isSideSeatMasked { return true }
        if let field = view as? UITextField, field.isSecureTextEntry { return true }
        return rule?(view) ?? false
    }

    private static func covers(_ view: UIView) -> Bool {
        guard view.alpha >= 1, (view.backgroundColor?.cgColor.alpha ?? 0) >= 1 else { return false }
        return view.transform.isIdentity && CATransform3DIsIdentity(view.layer.transform) && view.layer.cornerRadius == 0
    }
}
