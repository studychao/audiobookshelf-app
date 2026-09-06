import UIKit

/// Used only by the optional CarPlay scene configuration.
class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        if window == nil {
            let phoneWindow = UIWindow(windowScene: windowScene)
            phoneWindow.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController()
            window = phoneWindow
            phoneWindow.makeKeyAndVisible()
        }
        (UIApplication.shared.delegate as? AppDelegate)?.window = window
        self.scene(scene, openURLContexts: connectionOptions.urlContexts)
        for activity in connectionOptions.userActivities { self.scene(scene, continue: activity) }
    }
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let delegate = UIApplication.shared.delegate as? AppDelegate else { return }
        for context in URLContexts { _ = delegate.application(UIApplication.shared, open: context.url, options: [:]) }
    }
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        _ = (UIApplication.shared.delegate as? AppDelegate)?.application(UIApplication.shared, continue: userActivity, restorationHandler: { _ in })
    }
}
