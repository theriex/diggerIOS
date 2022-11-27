import UIKit
import WebKit

class ViewController: UIViewController, WKUIDelegate {
    var webView: WKWebView!

    override func loadView() {
        let wvconf = WKWebViewConfiguration()
        webView = WKWebView(frame:.zero, configuration:wvconf)
        webView.uiDelegate = self
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let htmlFile = Bundle.main.path(forResource: "docroot/test",
                                        ofType: "html")
        let html = try? String(contentsOfFile: htmlFile!,
                               encoding: String.Encoding.utf8)
        webView.loadHTMLString(html!, baseURL: nil)
    }
}
