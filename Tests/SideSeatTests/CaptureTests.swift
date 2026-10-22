import UIKit
import Testing
@testable import SideSeat

private final class PinScreen: UIViewController {}

@MainActor
@Suite struct CaptureTests {

    private func window() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.isHidden = false
        return window
    }

    @Test func secureFieldsAndFlaggedViewsAreMasked() {
        let w = window()
        let secret = UITextField(frame: CGRect(x: 10, y: 10, width: 100, height: 30))
        secret.isSecureTextEntry = true
        let flagged = UIView(frame: CGRect(x: 200, y: 10, width: 50, height: 50))
        flagged.isSideSeatMasked = true
        let plain = UILabel(frame: CGRect(x: 300, y: 10, width: 50, height: 20))
        [secret, flagged, plain].forEach(w.addSubview)

        #expect(MaskCollector.rects(in: w) == [
            CGRect(x: 8, y: 8, width: 104, height: 34),
            CGRect(x: 198, y: 8, width: 54, height: 54)
        ])
    }

    @Test func masksUnderALaterOpaqueViewAreDropped() {
        let w = window()
        let flagged = UIView(frame: CGRect(x: 100, y: 100, width: 50, height: 50))
        flagged.isSideSeatMasked = true
        let cover = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        cover.backgroundColor = .white
        [flagged, cover].forEach(w.addSubview)
        #expect(MaskCollector.rects(in: w).isEmpty)

        cover.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        #expect(MaskCollector.rects(in: w).count == 1)
    }

    @Test func masksAreClippedAndHiddenViewsSkipped() {
        let w = window()
        let clip = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        clip.clipsToBounds = true
        let flagged = UIView(frame: CGRect(x: 50, y: 50, width: 200, height: 200))
        flagged.isSideSeatMasked = true
        clip.addSubview(flagged)
        let hidden = UIView(frame: CGRect(x: 300, y: 300, width: 50, height: 50))
        hidden.isSideSeatMasked = true
        hidden.isHidden = true
        [clip, hidden].forEach(w.addSubview)

        #expect(MaskCollector.rects(in: w) == [CGRect(x: 48, y: 48, width: 54, height: 54)])
    }

    @Test func screenRulesMaskAWholeScreen() {
        let w = window()
        let screen = PinScreen()
        screen.view.frame = CGRect(x: 100, y: 100, width: 300, height: 200)
        w.addSubview(screen.view)
        #expect(MaskCollector.rects(in: w, rule: MaskRules.screens([PinScreen.self])) == [CGRect(x: 98, y: 98, width: 304, height: 204)])
        #expect(MaskCollector.rects(in: w, rule: MaskRules.screens([UINavigationController.self])).isEmpty)
    }

    @Test func overlayAndSystemWindowsAreNeverCapturedOrTapped() {
        let app = window()
        let alert = UIWindow(frame: app.frame)
        alert.windowLevel = .alert
        alert.isHidden = false
        let overlay = OverlayWindow(frame: app.frame)
        overlay.isHidden = false
        let hidden = UIWindow(frame: app.frame)

        #expect(WindowSelection.capturable([alert, overlay, app, hidden]) == [app, alert])
        alert.isUserInteractionEnabled = false
        #expect(WindowSelection.forInput([alert, overlay, app]) == [app])
    }

    @Test func aDraggedBannerStaysInsideTheArea() {
        let area = CGRect(x: 0, y: 20, width: 1000, height: 700)
        let size = CGSize(width: 300, height: 36)
        #expect(BannerPosition.clamped(CGPoint(x: 500, y: 300), size: size, in: area) == CGPoint(x: 500, y: 300))
        #expect(BannerPosition.clamped(CGPoint(x: -50, y: 0), size: size, in: area) == CGPoint(x: 150, y: 38))
        #expect(BannerPosition.clamped(CGPoint(x: 2000, y: 900), size: size, in: area) == CGPoint(x: 850, y: 702))
    }
}
