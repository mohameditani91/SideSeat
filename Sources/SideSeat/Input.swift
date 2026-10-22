import UIKit
import SwiftUI

/// Adopt on views whose taps aren't plain controls, such as gesture-driven cells.
public protocol SideSeatTappable: AnyObject {
    /// `point` is in the view's own coordinates. Return false to let the tap reach the view's ancestors.
    func sideSeatTap(at point: CGPoint) -> Bool
}

public extension View {
    /// Lets the agent trigger `action` by tapping this view. Use it on SwiftUI views driven by gestures.
    func sideSeatTarget(_ action: @escaping () -> Void) -> some View {
        background(TargetMarker(action: action))
    }
}

private struct TargetMarker: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> TargetView {
        let view = TargetView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: TargetView, context: Context) {
        uiView.action = action
    }
}

final class TargetView: UIView {
    var action: (() -> Void)?
}

final class InputDispatcher {

    private let windows: () -> [UIWindow]
    private let bounds: () -> CGRect
    private let firstResponder: () -> UIResponder?

    init(windows: @escaping () -> [UIWindow], bounds: @escaping () -> CGRect, firstResponder: @escaping () -> UIResponder? = UIResponder.sideSeatFirstResponder) {
        self.windows = windows
        self.bounds = bounds
        self.firstResponder = firstResponder
    }

    func perform(_ input: RemoteInput) -> InputResult {
        switch input {
        case .tap(let x, let y):
            return tap(at: point(x, y))
        case .scroll(let x, let y, let dx, let dy):
            let size = bounds().size
            return scroll(at: point(x, y), by: CGVector(dx: dx * size.width, dy: dy * size.height))
        case .text(let text):
            guard let input = firstResponder() as? UIKeyInput else { return .nothing("noFocusedField") }
            input.insertText(text)
            return .performed
        case .key(let key):
            return press(key)
        case .back:
            return goBack()
        }
    }

    func point(_ x: Double, _ y: Double) -> CGPoint {
        let bounds = bounds()
        return CGPoint(x: bounds.minX + CGFloat(min(max(x, 0), 1)) * bounds.width, y: bounds.minY + CGFloat(min(max(y, 0), 1)) * bounds.height)
    }

    func hit(at point: CGPoint) -> (window: UIWindow, view: UIView, point: CGPoint)? {
        for window in WindowSelection.forInput(windows()) {
            let local = CGPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
            guard window.point(inside: local, with: nil), let view = window.hitTest(local, with: nil) else { continue }
            return (window, view, local)
        }
        return nil
    }

    private func tap(at point: CGPoint) -> InputResult {
        guard let hit = hit(at: point) else { return .nothing("noTarget") }
        if let result = closePopover(tappedOn: hit.view, in: hit.window) { return result }
        if let target = Self.target(near: hit.view, at: hit.point, in: hit.window) {
            target.action?()
            return .performed
        }
        var view: UIView? = hit.view
        while let current = view, current !== hit.window {
            if let result = activate(current, at: hit.window.convert(hit.point, to: current)) { return result }
            view = current.superview
        }
        if Self.containsDisabledControl(at: hit.point, under: hit.view, in: hit.window) { return .nothing("disabled") }
        return accessibilityActivation(from: hit.view) ?? .nothing("noTarget")
    }

    private func activate(_ view: UIView, at point: CGPoint) -> InputResult? {
        if let tappable = view as? SideSeatTappable {
            return tappable.sideSeatTap(at: point) ? .performed : nil
        }
        switch view {
        case let toggle as UISwitch:
            guard toggle.isEnabled else { return .nothing("disabled") }
            toggle.setOn(!toggle.isOn, animated: true)
            toggle.sendActions(for: .valueChanged)
            return .performed
        case let segmented as UISegmentedControl:
            return select(segmented, at: point)
        case let slider as UISlider:
            guard slider.isEnabled else { return .nothing("disabled") }
            var fraction = Float(min(max(point.x / max(slider.bounds.width, 1), 0), 1))
            if slider.effectiveUserInterfaceLayoutDirection == .rightToLeft { fraction = 1 - fraction }
            slider.setValue(slider.minimumValue + fraction * (slider.maximumValue - slider.minimumValue), animated: true)
            slider.sendActions(for: .valueChanged)
            return .performed
        case let field as UITextField:
            guard field.isEnabled else { return .nothing("disabled") }
            return field.becomeFirstResponder() || field.isFirstResponder ? .performed : .nothing("cannotFocus")
        case let textView as UITextView:
            guard textView.isEditable else { return nil }
            return textView.becomeFirstResponder() || textView.isFirstResponder ? .performed : .nothing("cannotFocus")
        case let control as UIControl:
            return fire(control)
        case let cell as UITableViewCell:
            return select(cell)
        case let cell as UICollectionViewCell:
            return select(cell)
        default:
            return nil
        }
    }

    private func fire(_ control: UIControl) -> InputResult? {
        let events = control.allControlEvents.intersection([.touchUpInside, .primaryActionTriggered])
        guard !events.isEmpty else { return nil }
        guard control.isEnabled else { return .nothing("disabled") }
        if events.contains(.touchUpInside) { control.sendActions(for: .touchUpInside) }
        if events.contains(.primaryActionTriggered) { control.sendActions(for: .primaryActionTriggered) }
        return .performed
    }

    private func select(_ segmented: UISegmentedControl, at point: CGPoint) -> InputResult {
        guard segmented.isEnabled, segmented.numberOfSegments > 0 else { return .nothing("disabled") }
        var x = min(max(point.x, 0), segmented.bounds.width)
        if segmented.effectiveUserInterfaceLayoutDirection == .rightToLeft { x = segmented.bounds.width - x }
        let widths = (0..<segmented.numberOfSegments).map { segmented.widthForSegment(at: $0) }
        let automaticCount = CGFloat(max(widths.filter { $0 == 0 }.count, 1))
        let automaticWidth = max(segmented.bounds.width - widths.reduce(0, +), 0) / automaticCount
        var edge: CGFloat = 0
        var index = segmented.numberOfSegments - 1
        for (i, width) in widths.enumerated() {
            edge += width == 0 ? automaticWidth : width
            if x < edge {
                index = i
                break
            }
        }
        guard segmented.isEnabledForSegment(at: index) else { return .nothing("disabled") }
        guard segmented.isMomentary || segmented.selectedSegmentIndex != index else { return .performed }
        segmented.selectedSegmentIndex = index
        segmented.sendActions(for: .valueChanged)
        return .performed
    }

    private func select(_ cell: UITableViewCell) -> InputResult? {
        guard let table = cell.ancestor(UITableView.self), let indexPath = table.indexPath(for: cell) else { return nil }
        guard table.isEditing ? table.allowsSelectionDuringEditing : table.allowsSelection else { return .nothing("selectionDisabled") }
        let delegate = table.delegate
        if delegate?.tableView?(table, shouldHighlightRowAt: indexPath) == false { return .nothing("notSelectable") }

        let multiple = table.isEditing ? table.allowsMultipleSelectionDuringEditing : table.allowsMultipleSelection
        if multiple, table.indexPathsForSelectedRows?.contains(indexPath) == true {
            guard let target = Self.willDeselect(indexPath, in: table) else { return .nothing("notSelectable") }
            table.deselectRow(at: target, animated: true)
            delegate?.tableView?(table, didDeselectRowAt: target)
            return .performed
        }

        guard let target = Self.willSelect(indexPath, in: table) else { return .nothing("notSelectable") }
        if !multiple, let previous = table.indexPathForSelectedRow, previous != target {
            table.deselectRow(at: previous, animated: false)
            delegate?.tableView?(table, didDeselectRowAt: previous)
        }
        table.selectRow(at: target, animated: true, scrollPosition: .none)
        delegate?.tableView?(table, didSelectRowAt: target)
        return .performed
    }

    private static func willSelect(_ indexPath: IndexPath, in table: UITableView) -> IndexPath? {
        guard let delegate = table.delegate, delegate.responds(to: #selector(UITableViewDelegate.tableView(_:willSelectRowAt:))) else { return indexPath }
        return delegate.tableView?(table, willSelectRowAt: indexPath)
    }

    private static func willDeselect(_ indexPath: IndexPath, in table: UITableView) -> IndexPath? {
        guard let delegate = table.delegate, delegate.responds(to: #selector(UITableViewDelegate.tableView(_:willDeselectRowAt:))) else { return indexPath }
        return delegate.tableView?(table, willDeselectRowAt: indexPath)
    }

    private func select(_ cell: UICollectionViewCell) -> InputResult? {
        guard let collection = cell.ancestor(UICollectionView.self), let indexPath = collection.indexPath(for: cell) else { return nil }
        guard collection.isEditing ? collection.allowsSelectionDuringEditing : collection.allowsSelection else { return .nothing("selectionDisabled") }
        let delegate = collection.delegate
        if delegate?.collectionView?(collection, shouldHighlightItemAt: indexPath) == false { return .nothing("notSelectable") }

        let multiple = collection.isEditing ? collection.allowsMultipleSelectionDuringEditing : collection.allowsMultipleSelection
        if multiple, collection.indexPathsForSelectedItems?.contains(indexPath) == true {
            guard delegate?.collectionView?(collection, shouldDeselectItemAt: indexPath) != false else { return .nothing("notSelectable") }
            collection.deselectItem(at: indexPath, animated: true)
            delegate?.collectionView?(collection, didDeselectItemAt: indexPath)
            return .performed
        }

        guard delegate?.collectionView?(collection, shouldSelectItemAt: indexPath) != false else { return .nothing("notSelectable") }
        if !multiple {
            for previous in collection.indexPathsForSelectedItems ?? [] where previous != indexPath {
                collection.deselectItem(at: previous, animated: false)
                delegate?.collectionView?(collection, didDeselectItemAt: previous)
            }
        }
        collection.selectItem(at: indexPath, animated: true, scrollPosition: [])
        delegate?.collectionView?(collection, didSelectItemAt: indexPath)
        return .performed
    }

    private static func containsDisabledControl(at point: CGPoint, under root: UIView, in window: UIWindow) -> Bool {
        root.subviews.reversed().contains { view in
            guard !view.isHidden, view.alpha > 0.01, view.bounds.contains(window.convert(point, to: view)) else { return false }
            if let control = view as? UIControl, !control.isEnabled { return true }
            return containsDisabledControl(at: point, under: view, in: window)
        }
    }

    private func accessibilityActivation(from view: UIView) -> InputResult? {
        var current: UIView? = view
        while let candidate = current {
            if candidate.isAccessibilityElement { return candidate.accessibilityActivate() ? .performed : nil }
            current = candidate.superview
        }
        return nil
    }

    static func target(near view: UIView, at point: CGPoint, in window: UIWindow) -> TargetView? {
        var container: UIView? = view
        while let current = container, current !== window {
            if let target = smallestTarget(in: current, at: point, window: window) { return target }
            if current.next is UIViewController { return nil }
            container = current.superview
        }
        return nil
    }

    private static func smallestTarget(in root: UIView, at point: CGPoint, window: UIWindow) -> TargetView? {
        var best: (view: TargetView, area: CGFloat)?
        func visit(_ view: UIView, clip: CGRect) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            let frame = view.convert(view.bounds, to: window)
            if let target = view as? TargetView, target.action != nil, frame.contains(point), clip.contains(point) {
                let area = frame.width * frame.height
                if area < (best?.area ?? .greatestFiniteMagnitude) { best = (target, area) }
            }
            let childClip = view.clipsToBounds ? clip.intersection(frame) : clip
            view.subviews.forEach { visit($0, clip: childClip) }
        }
        visit(root, clip: window.bounds)
        return best?.view
    }

    private func closePopover(tappedOn view: UIView, in window: UIWindow) -> InputResult? {
        guard let top = window.rootViewController?.topPresented,
              let popover = top.presentationController as? UIPopoverPresentationController,
              let popup = popover.presentedView, !view.isDescendant(of: popup),
              !(popover.passthroughViews ?? []).contains(where: view.isDescendant(of:)) else { return nil }
        if top is UIAlertController { return .nothing("alertOpen") }
        guard !top.isModalInPresentation, Self.shouldDismiss(popover) else { return .nothing("popoverStaysOpen") }
        popover.delegate?.presentationControllerWillDismiss?(popover)
        top.dismiss(animated: true) { Self.didDismiss(popover) }
        return .performed
    }

    static func shouldDismiss(_ popover: UIPopoverPresentationController) -> Bool {
        guard let delegate = popover.delegate else { return true }
        if let answer = delegate.presentationControllerShouldDismiss?(popover) { return answer }
        return unsafeBitCast(delegate, to: LegacyPopoverDelegate.self).popoverPresentationControllerShouldDismissPopover?(popover) ?? true
    }

    static func didDismiss(_ popover: UIPopoverPresentationController) {
        guard let delegate = popover.delegate else { return }
        if delegate.presentationControllerDidDismiss?(popover) == nil {
            unsafeBitCast(delegate, to: LegacyPopoverDelegate.self).popoverPresentationControllerDidDismissPopover?(popover)
        }
    }

    private func scroll(at point: CGPoint, by delta: CGVector) -> InputResult {
        guard let hit = hit(at: point) else { return .nothing("noScrollView") }
        let vertical = abs(delta.dy) >= abs(delta.dx)
        let ancestors = sequence(first: hit.view, next: \.superview).compactMap { $0 as? UIScrollView }.filter(\.isScrollEnabled)
        let candidates = Self.scrollViews(at: hit.point, under: hit.view, in: hit.window) + ancestors
        guard let target = candidates.first(where: { $0.canScroll(vertically: vertical) }) ?? candidates.first else { return .nothing("noScrollView") }
        return move(target, by: delta)
    }

    private static func scrollViews(at point: CGPoint, under view: UIView, in window: UIWindow) -> [UIScrollView] {
        view.subviews.reversed().flatMap { subview -> [UIScrollView] in
            guard !subview.isHidden, subview.alpha > 0.01, subview.isUserInteractionEnabled else { return [] }
            let inside = subview.bounds.contains(window.convert(point, to: subview))
            guard inside || !subview.clipsToBounds else { return [] }
            let nested = scrollViews(at: point, under: subview, in: window)
            guard inside, let scrollView = subview as? UIScrollView, scrollView.isScrollEnabled else { return nested }
            return nested + [scrollView]
        }
    }

    private func move(_ scrollView: UIScrollView, by delta: CGVector) -> InputResult {
        let inset = scrollView.adjustedContentInset
        let minX = -inset.left
        let minY = -inset.top
        let maxX = max(minX, scrollView.contentSize.width + inset.right - scrollView.bounds.width)
        let maxY = max(minY, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        let offset = scrollView.contentOffset
        let target = CGPoint(x: min(max(offset.x + delta.dx, minX), maxX), y: min(max(offset.y + delta.dy, minY), maxY))
        guard abs(target.x - offset.x) > 0.5 || abs(target.y - offset.y) > 0.5 else { return .nothing("atEdge") }
        scrollView.setContentOffset(target, animated: false)
        return .performed
    }

    private func press(_ key: RemoteKey) -> InputResult {
        guard let responder = firstResponder() else { return .nothing("noFocusedField") }
        switch key {
        case .backspace:
            guard let input = responder as? UIKeyInput else { return .nothing("noFocusedField") }
            input.deleteBackward()
        case .return:
            if let field = responder as? UITextField {
                if field.delegate?.textFieldShouldReturn?(field) ?? true {
                    field.sendActions(for: .editingDidEndOnExit)
                }
            } else if let input = responder as? UIKeyInput {
                input.insertText("\n")
            } else {
                return .nothing("noFocusedField")
            }
        }
        return .performed
    }

    private func goBack() -> InputResult {
        guard let top = WindowSelection.forInput(windows()).lazy.compactMap(\.rootViewController).first?.topPresented else { return .nothing("nothingToGoBack") }
        if top is UIAlertController { return .nothing("alertOpen") }
        if let navigation = Self.navigationToPop(in: top) {
            guard navigation.topViewController?.navigationItem.hidesBackButton != true else { return .nothing("backHidden") }
            navigation.popViewController(animated: true)
            return .performed
        }
        guard top.presentingViewController != nil, !top.isModalInPresentation else { return .nothing("nothingToGoBack") }
        top.dismiss(animated: true)
        return .performed
    }

    static func navigationToPop(in controller: UIViewController) -> UINavigationController? {
        if let navigation = controller as? UINavigationController, navigation.viewControllers.count > 1 { return navigation }
        for child in controller.children where child.isViewLoaded && child.view.window != nil && !child.view.isHidden {
            if let navigation = navigationToPop(in: child) { return navigation }
        }
        return nil
    }
}

@objc private protocol LegacyPopoverDelegate {
    @objc optional func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool
    @objc optional func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController)
}

private extension UIView {
    func ancestor<T: UIView>(_ type: T.Type) -> T? {
        sequence(first: superview, next: { $0?.superview }).lazy.compactMap { $0 as? T }.first
    }
}

private extension UIViewController {
    var topPresented: UIViewController {
        var top = self
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}

private extension UIScrollView {
    func canScroll(vertically: Bool) -> Bool {
        let inset = adjustedContentInset
        return vertically
            ? contentSize.height + inset.top + inset.bottom > bounds.height + 0.5
            : contentSize.width + inset.left + inset.right > bounds.width + 0.5
    }
}

extension UIResponder {

    private static weak var found: UIResponder?

    static func sideSeatFirstResponder() -> UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.sideSeatCaptureFirstResponder(_:)), to: nil, from: nil, for: nil)
        return found
    }

    @objc private func sideSeatCaptureFirstResponder(_ sender: Any?) {
        UIResponder.found = self
    }
}
