import UIKit
import Testing
@testable import SideSeat

private final class Counter {
    var count = 0
    var action: UIAction { UIAction { [self] _ in count += 1 } }
}

private final class Rows: NSObject, UITableViewDataSource, UITableViewDelegate {
    var selected: [Int] = []
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 3 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { UITableViewCell() }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { selected.append(indexPath.row) }
}

private final class GuardedRows: NSObject, UITableViewDataSource, UITableViewDelegate {
    var selected: [Int] = []
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 3 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { UITableViewCell() }
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? { indexPath.row == 2 ? nil : indexPath }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { selected.append(indexPath.row) }
}

private final class TappableView: UIView, SideSeatTappable {
    var points: [CGPoint] = []
    func sideSeatTap(at point: CGPoint) -> Bool {
        points.append(point)
        return true
    }
}

private final class KeyInputView: UIView, UIKeyInput {
    var typed = ""
    var hasText: Bool { !typed.isEmpty }
    func insertText(_ text: String) { typed += text }
    func deleteBackward() { typed = String(typed.dropLast()) }
}

private final class SwallowingView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        self.point(inside: point, with: event) ? self : nil
    }
}

private final class ModernPopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate {
    var allow = true
    var calls: [String] = []
    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        calls.append("shouldDismiss")
        return allow
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { calls.append("didDismiss") }
    func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
        calls.append("legacyShouldDismiss")
        return true
    }
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) { calls.append("legacyDidDismiss") }
}

private final class LegacyPopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate {
    var allow = true
    var calls: [String] = []
    func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
        calls.append("legacyShouldDismiss")
        return allow
    }
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) { calls.append("legacyDidDismiss") }
}

private final class InstantPopNavigation: UINavigationController {
    override func popViewController(animated: Bool) -> UIViewController? {
        super.popViewController(animated: false)
    }
}

@MainActor
@Suite struct InputTests {

    private let scene = CGRect(x: 0, y: 0, width: 1000, height: 500)

    private func window() -> UIWindow {
        let window = UIWindow(frame: scene)
        window.isHidden = false
        return window
    }

    private func dispatcher(_ windows: [UIWindow], responder: UIResponder? = nil) -> InputDispatcher {
        InputDispatcher(windows: { windows }, bounds: { [scene] in scene }, firstResponder: { responder })
    }

    private func tap(_ dispatcher: InputDispatcher, _ x: CGFloat, _ y: CGFloat) -> InputResult {
        dispatcher.perform(.tap(x: Double(x / scene.width), y: Double(y / scene.height)))
    }

    @Test func mapsNormalizedPointsAndClamps() {
        let d = dispatcher([])
        #expect(d.point(0.5, 0.5) == CGPoint(x: 500, y: 250))
        #expect(d.point(-1, 2) == CGPoint(x: 0, y: 500))
    }

    @Test func buttonsFireOnceAndDisabledOnesReportIt() {
        let w = window()
        let counter = Counter()
        let button = UIButton(frame: CGRect(x: 100, y: 100, width: 100, height: 40))
        button.addAction(counter.action, for: .touchUpInside)
        w.addSubview(button)
        let d = dispatcher([w])

        #expect(tap(d, 150, 120) == .performed)
        #expect(counter.count == 1)

        button.isEnabled = false
        #expect(tap(d, 150, 120) == .nothing("disabled"))
        #expect(counter.count == 1)
    }

    @Test func switchesSegmentsAndSlidersChangeValue() {
        let w = window()
        let toggle = UISwitch(frame: CGRect(x: 10, y: 10, width: 51, height: 31))
        let segments = UISegmentedControl(items: ["A", "B", "C"])
        segments.frame = CGRect(x: 100, y: 100, width: 300, height: 30)
        let slider = UISlider(frame: CGRect(x: 100, y: 300, width: 200, height: 30))
        [toggle, segments, slider].forEach(w.addSubview)
        let d = dispatcher([w])

        #expect(tap(d, 30, 25) == .performed)
        #expect(toggle.isOn)
        #expect(tap(d, 350, 115) == .performed)
        #expect(segments.selectedSegmentIndex == 2)
        #expect(tap(d, 150, 315) == .performed)
        #expect(abs(slider.value - 0.25) < 0.01)
    }

    @Test func tableRowsSelectThroughTheDelegate() {
        let w = window()
        let rows = Rows()
        let table = UITableView(frame: scene, style: .plain)
        table.dataSource = rows
        table.delegate = rows
        table.rowHeight = 100
        table.contentInsetAdjustmentBehavior = .never
        w.addSubview(table)
        table.layoutIfNeeded()
        let d = dispatcher([w])

        #expect(tap(d, 500, 150) == .performed)
        #expect(rows.selected == [1])
        #expect(table.indexPathForSelectedRow == IndexPath(row: 1, section: 0))
    }

    @Test func willSelectCanRefuseARow() {
        let w = window()
        let rows = GuardedRows()
        let table = UITableView(frame: scene, style: .plain)
        table.dataSource = rows
        table.delegate = rows
        table.rowHeight = 100
        table.contentInsetAdjustmentBehavior = .never
        w.addSubview(table)
        table.layoutIfNeeded()
        let d = dispatcher([w])

        #expect(tap(d, 500, 250) == .nothing("notSelectable"))
        #expect(tap(d, 500, 50) == .performed)
        #expect(rows.selected == [0])
    }

    @Test func tappableViewsGetTheirOwnCoordinates() {
        let w = window()
        let view = TappableView(frame: CGRect(x: 200, y: 100, width: 100, height: 100))
        w.addSubview(view)
        #expect(tap(dispatcher([w]), 260, 130) == .performed)
        #expect(view.points == [CGPoint(x: 60, y: 30)])
    }

    @Test func swiftUITargetsResolveToTheSmallestOneUnderThePoint() {
        let w = window()
        let host = UIView(frame: scene)
        var fired: [String] = []
        let big = TargetView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        big.action = { fired.append("big") }
        let small = TargetView(frame: CGRect(x: 50, y: 50, width: 50, height: 50))
        small.action = { fired.append("small") }
        [big, small].forEach { $0.isUserInteractionEnabled = false; host.addSubview($0) }
        w.addSubview(host)
        let d = dispatcher([w])

        #expect(tap(d, 60, 60) == .performed)
        #expect(tap(d, 300, 300) == .performed)
        #expect(fired == ["small", "big"])
    }

    @Test func plainViewsAreNothingToTap() {
        let w = window()
        w.addSubview(UIView(frame: scene))
        #expect(tap(dispatcher([w]), 500, 250) == .nothing("noTarget"))
    }

    @Test func scrollPrefersTheScrollViewThatCanMoveThatWayAndClamps() {
        let w = window()
        let outer = UIScrollView(frame: scene)
        outer.contentSize = CGSize(width: 1000, height: 2000)
        let inner = UIScrollView(frame: CGRect(x: 0, y: 0, width: 1000, height: 200))
        inner.contentSize = CGSize(width: 3000, height: 200)
        inner.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 3000, height: 200)))
        outer.addSubview(inner)
        w.addSubview(outer)
        let d = dispatcher([w])

        #expect(d.perform(.scroll(x: 0.5, y: 0.1, dx: 0, dy: 0.2)) == .performed)
        #expect(outer.contentOffset.y == 100)
        #expect(d.perform(.scroll(x: 0.5, y: 0.1, dx: 0.3, dy: 0)) == .performed)
        #expect(inner.contentOffset.x == 300)
        #expect(d.perform(.scroll(x: 0.5, y: 0.5, dx: 0, dy: -5)) == .performed)
        #expect(outer.contentOffset.y == 0)
        #expect(d.perform(.scroll(x: 0.5, y: 0.5, dx: 0, dy: -1)) == .nothing("atEdge"))
    }

    @Test func scrollFindsScrollViewsBelowViewsThatSwallowHitTesting() {
        let w = window()
        let host = SwallowingView(frame: scene)
        let list = UIScrollView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        list.contentSize = CGSize(width: 500, height: 2000)
        let frozen = UIScrollView(frame: CGRect(x: 500, y: 0, width: 500, height: 500))
        frozen.contentSize = CGSize(width: 500, height: 2000)
        frozen.isUserInteractionEnabled = false
        [list, frozen].forEach(host.addSubview)
        w.addSubview(host)
        let d = dispatcher([w])

        #expect(d.perform(.scroll(x: 0.25, y: 0.5, dx: 0, dy: 0.2)) == .performed)
        #expect(list.contentOffset.y == 100)
        #expect(d.perform(.scroll(x: 0.75, y: 0.5, dx: 0, dy: 0.2)) == .nothing("noScrollView"))
    }

    @Test func textAndKeysGoToTheFocusedField() {
        let field = KeyInputView()
        let d = dispatcher([], responder: field)
        #expect(d.perform(.text("ab")) == .performed)
        #expect(d.perform(.key(.backspace)) == .performed)
        #expect(d.perform(.key(.return)) == .performed)
        #expect(field.typed == "a\n")
        #expect(dispatcher([]).perform(.text("x")) == .nothing("noFocusedField"))
    }

    @Test func backPopsTheVisibleNavigationUnlessBackIsHidden() {
        let w = window()
        let navigation = InstantPopNavigation(rootViewController: UIViewController())
        navigation.pushViewController(UIViewController(), animated: false)
        w.rootViewController = navigation
        let d = dispatcher([w])

        navigation.topViewController?.navigationItem.hidesBackButton = true
        #expect(d.perform(.back) == .nothing("backHidden"))
        navigation.topViewController?.navigationItem.hidesBackButton = false
        #expect(d.perform(.back) == .performed)
        #expect(navigation.viewControllers.count == 1)
        #expect(d.perform(.back) == .nothing("nothingToGoBack"))
    }

    @Test func popoverDismissalAsksOnlyTheModernDelegateMethodsWhenImplemented() {
        let delegate = ModernPopoverDelegate()
        let popover = UIPopoverPresentationController(presentedViewController: UIViewController(), presenting: nil)
        popover.delegate = delegate

        #expect(InputDispatcher.shouldDismiss(popover))
        delegate.allow = false
        #expect(!InputDispatcher.shouldDismiss(popover))
        InputDispatcher.didDismiss(popover)
        #expect(delegate.calls == ["shouldDismiss", "shouldDismiss", "didDismiss"])
    }

    @Test func popoverDismissalFallsBackToTheLegacyDelegateMethods() {
        let delegate = LegacyPopoverDelegate()
        let popover = UIPopoverPresentationController(presentedViewController: UIViewController(), presenting: nil)
        popover.delegate = delegate

        #expect(InputDispatcher.shouldDismiss(popover))
        delegate.allow = false
        #expect(!InputDispatcher.shouldDismiss(popover))
        InputDispatcher.didDismiss(popover)
        #expect(delegate.calls == ["legacyShouldDismiss", "legacyShouldDismiss", "legacyDidDismiss"])
    }
}
