import UIKit
import WebKit

class ViewController: UIViewController, WKUIDelegate {
    var webView: WKWebView!

    override func loadView() {
        let wvconf = WKWebViewConfiguration()
        wvconf.userContentController.add(self, name:"diggerMsgHandler")
        webView = WKWebView(frame:.zero, configuration:wvconf)
        webView.uiDelegate = self
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let du = Bundle.main.resourceURL!.appendingPathComponent("docroot")
        //debugPrint("du: ", du)
        let iu = Bundle.main.url(forResource: "index",
                                 withExtension: "html",
                                 subdirectory: "docroot")!
        debugPrint("iu: ", iu)
        webView.loadFileURL(iu, allowingReadAccessTo: du)
        let request = URLRequest(url: iu)
        webView.load(request)
    }
}


//receive JSON: {qname:"Main", fname:"getData", pobj:Any}
//   send JSON: {qname:"Main", fname:"getData", res:Any}
extension ViewController:WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive msg: WKScriptMessage) {
        if msg.name != "diggerMsgHandler" {
            debugPrint("unknown msg.name: ", msg.name) }
        let jstr = msg.body as! String
        let jdat = Data(jstr.utf8)
        do {
            if let dpd = try JSONSerialization.jsonObject(
              with: jdat, options: .mutableContainers) as? [String: Any] {
                let qname = dpd["qname"] as! String
                let fname = dpd["fname"] as! String
                let resjson = handleDiggerCall(qname, fname, dpd["pobj"]!)
                let rjstr = String(data:resjson, encoding:.utf8)!
                debugPrint("rjstr: ", rjstr)
                let msg = "app.svc.iosReturn('\(rjstr)')"
                debugPrint("msg: ", msg)
                self.webView.evaluateJavaScript(msg) }
        } catch let error as NSError {
            print("Failed to load: \(error.localizedDescription)")
        }
    }


    func makeResult(_ qn:String, _ fn:String, _ res:Codable) -> Data {
        let resobj = ["qname":qn, "fname":fn, "result":res]
        let resdat = try! JSONSerialization.data(withJSONObject:resobj)
        return resdat
    }


    func handleDiggerCall(_ qname:String, _ fname:String, _ pobj:Any) -> Data {
        switch(fname) {
        case "getVersionCode":
            return makeResult(qname, fname, "alpha")
        default:
            debugPrint("handleDiggerCall unknown fname: ", fname)
            return makeResult(qname, fname, "") }
    }
}
