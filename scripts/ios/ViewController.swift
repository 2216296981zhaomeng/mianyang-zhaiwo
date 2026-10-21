import UIKit
import DCloudUniappRuntime

/// Production entry: launch the uni-app x SDK immediately instead of the demo button page.
class ViewController: UIViewController {
    private var started = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true

        let options = UniAppXSDKStartOptions()
        options.appScheme = "tcwangAgent"
        options.openType = .present
        options.animationType = .none
        options.viewController = self
        UniAppXSDK.start(options: options)
    }
}
