import Testing
import UIKit

@testable import Mercurio

@Suite("Navigation bar touch passthrough")
@MainActor
struct NavigationBarTouchPassthroughTests {
    @Test func glassAcrossTheBarDoesNotClaimATouch() {
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 54))
        let glass = UIView(frame: bar.bounds)
        glass.isUserInteractionEnabled = true
        bar.addSubview(glass)

        #expect(NavigationBarHitPolicy.containsClaim(in: bar, at: CGPoint(x: 20, y: 20), event: nil) == false)
    }

    @Test func aButtonOnTheGlassKeepsTheTouch() {
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 54))
        let glass = UIView(frame: bar.bounds)
        bar.addSubview(glass)
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 270, y: 8, width: 36, height: 36)
        glass.addSubview(button)

        #expect(
            NavigationBarHitPolicy.containsClaim(in: bar, at: CGPoint(x: 20, y: 20), event: nil) == false)
        #expect(
            NavigationBarHitPolicy.containsClaim(in: bar, at: CGPoint(x: 288, y: 26), event: nil))
    }

    @Test func anEmptyNavigationBarLetsTheTouchReachTheScreenUnderIt() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let root = UIViewController()
        let under = UIButton(type: .system)
        under.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        root.view.addSubview(under)
        let navigation = UINavigationController(rootViewController: root)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        navigation.view.layoutIfNeeded()

        let bar = navigation.navigationBar
        NavigationBarTouchPassthrough.install(on: bar)
        let point = window.convert(CGPoint(x: 16, y: bar.bounds.midY), from: bar)
        let hit = window.hitTest(point, with: nil)

        #expect(hit === under || hit?.isDescendant(of: under) == true)
    }
}
