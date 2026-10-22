import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = RootTabController()
        window.makeKeyAndVisible()
        self.window = window
        Support.startIfRequested(in: scene)
    }
}

final class RootTabController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let tasks = UINavigationController(rootViewController: TasksViewController())
        tasks.tabBarItem = UITabBarItem(title: "Tasks", image: UIImage(systemName: "checklist"), tag: 0)
        let profile = ProfileHostingController()
        profile.tabBarItem = UITabBarItem(title: "Profile", image: UIImage(systemName: "person.crop.circle"), tag: 1)
        let support = UINavigationController(rootViewController: SupportViewController())
        support.tabBarItem = UITabBarItem(title: "Support", image: UIImage(systemName: "person.wave.2"), tag: 2)
        viewControllers = [tasks, profile, support]
    }
}
