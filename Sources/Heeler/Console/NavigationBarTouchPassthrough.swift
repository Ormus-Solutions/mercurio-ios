import ObjectiveC
import SwiftUI
import UIKit

extension View {
    /// The floating header is this screen's top chrome. On a phone the system
    /// bar is hidden: its glass otherwise takes every touch across the top,
    /// so the header and the first rows of the surface never see them. Beside
    /// an iPad sidebar the bar stays for its own buttons, and empty glass
    /// lets the touch fall through to whatever is under it.
    func detailSurfaceNavigationBar() -> some View {
        modifier(DetailSurfaceNavigationBarModifier())
    }
}

private struct DetailSurfaceNavigationBarModifier: ViewModifier {
    @Environment(\.showsDetailBackButton) private var isPushedOverList

    func body(content: Content) -> some View {
        content
            .background {
                NavigationBarTouchPassthroughInstaller()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .modifier(DetailSurfaceNavigationBarVisibility(isPushedOverList: isPushedOverList))
    }
}

/// Hides the bar only once the screen is pushed over the list. The
/// visibility modifier is separate so the phone and the iPad each get one
/// stable branch, rather than toggling modifiers on and off.
private struct DetailSurfaceNavigationBarVisibility: ViewModifier {
    let isPushedOverList: Bool

    func body(content: Content) -> some View {
        if isPushedOverList {
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content
                .toolbarBackground(Color.clear, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar(.visible, for: .navigationBar)
        }
    }
}

/// Installs ``NavigationBarTouchPassthrough`` on the enclosing bar while
/// this screen is up.
private struct NavigationBarTouchPassthroughInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.installIfNeeded()
    }

    final class Probe: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is unavailable")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            installIfNeeded()
        }

        func installIfNeeded() {
            guard window != nil, let bar = enclosingNavigationBar() else { return }
            NavigationBarTouchPassthrough.install(on: bar)
        }

        private func enclosingNavigationBar() -> UINavigationBar? {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController,
                    let bar = controller.navigationController?.navigationBar
                {
                    return bar
                }
                responder = current.next
            }
            return nil
        }
    }
}

/// Empty navigation-bar glass does not keep a touch. A real control does.
@MainActor
enum NavigationBarTouchPassthrough {
    /// The set of classes already given the passthrough `point(inside:)`.
    /// Touched only on the main thread, from `install` and never from the
    /// patched method itself.
    nonisolated(unsafe) private static var patched = Set<ObjectIdentifier>()

    static func install(on bar: UINavigationBar) {
        let cls: AnyClass = object_getClass(bar) ?? UINavigationBar.self
        let id = ObjectIdentifier(cls)
        guard !patched.contains(id) else { return }

        let selector = #selector(UIView.point(inside:with:))
        guard let viewMethod = class_getInstanceMethod(UIView.self, selector),
            let encoding = method_getTypeEncoding(viewMethod)
        else { return }

        let superclass: AnyClass = class_getSuperclass(cls) ?? UIView.self
        guard let superIMP = class_getMethodImplementation(superclass, selector) else { return }
        typealias PointInside = @convention(c) (AnyObject, Selector, CGPoint, UIEvent?) -> Bool
        let inherited = unsafeBitCast(superIMP, to: PointInside.self)

        let block: @convention(block) (AnyObject, CGPoint, UIEvent?) -> Bool = { object, point, event in
            // UIKit hit-tests on the main thread.
            MainActor.assumeIsolated {
                guard inherited(object, selector, point, event), let view = object as? UIView else {
                    return false
                }
                return NavigationBarHitPolicy.containsClaim(in: view, at: point, event: event)
            }
        }

        let imp = imp_implementationWithBlock(block)
        if classDefines(cls, selector) {
            guard let method = class_getInstanceMethod(cls, selector) else { return }
            method_setImplementation(method, imp)
        } else if !class_addMethod(cls, selector, imp, encoding) {
            return
        }
        patched.insert(id)
    }

    /// `class_copyMethodList` is only the methods this class defines, not
    /// ones it inherits. Patching an inherited method would replace it for
    /// every view.
    private static func classDefines(_ cls: AnyClass, _ selector: Selector) -> Bool {
        var count: UInt32 = 0
        guard let list = class_copyMethodList(cls, &count) else { return false }
        defer { free(list) }
        for index in 0..<Int(count) where method_getName(list[index]) == selector {
            return true
        }
        return false
    }
}

/// Which views inside a bar are allowed to keep a touch.
@MainActor
enum NavigationBarHitPolicy {
    static func containsClaim(in view: UIView, at point: CGPoint, event: UIEvent?) -> Bool {
        containsClaim(in: view, at: point, event: event, barSize: view.bounds.size)
    }

    private static func containsClaim(
        in view: UIView, at point: CGPoint, event: UIEvent?, barSize: CGSize
    ) -> Bool {
        for subview in view.subviews.reversed() {
            guard subview.isUserInteractionEnabled, !subview.isHidden, subview.alpha > 0.01 else {
                continue
            }
            let local = view.convert(point, to: subview)
            guard subview.point(inside: local, with: event) else { continue }
            if claims(subview, barSize: barSize) { return true }
            if containsClaim(in: subview, at: local, event: event, barSize: barSize) { return true }
        }
        return false
    }

    /// A control small enough to be a button keeps the touch. The glass
    /// behind it covers the bar and must not.
    static func claims(_ view: UIView, barSize: CGSize) -> Bool {
        let size = view.bounds.size
        let coversWidth = barSize.width > 0 && size.width >= barSize.width * 0.8
        let coversHeight = barSize.height > 0 && size.height >= barSize.height * 0.7
        if coversWidth && coversHeight { return false }
        guard view.isUserInteractionEnabled else { return false }
        if let control = view as? UIControl { return control.isEnabled }
        if let recognizers = view.gestureRecognizers, recognizers.contains(where: { $0.isEnabled }) {
            return true
        }
        return false
    }
}
