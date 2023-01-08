import UIKit
import WebKit
import MediaPlayer

class ViewController: UIViewController, WKUIDelegate {
    var webView: WKWebView!
    let smpc = MPMusicPlayerController.systemMusicPlayer
    var perr = ""
    var qsta:[MPMediaItem]? = nil  //current queue state reference
    var mibp = [String: MPMediaItem]()  //Media items by path
    var dais = [[String: String]]()  //Digger Audio Items

    func conlog(_ txt:String) {
        let fmat = DateFormatter()
        fmat.dateStyle = .medium
        fmat.timeStyle = .medium
        let date = Date()
        let tstmp = fmat.string(from: date)
        print("\(tstmp) \(txt)")
    }

    func shortstr(_ txt:String) -> String {
        var st = txt
        if(txt.count > 250) {
            st = txt.prefix(180) + "..." + txt.suffix(50) }
        return st
    }

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

    func initMediaInfo() {
        mibp = [String: MPMediaItem]()  //reset
        dais = [[String: String]]()  //reset
        let datezero = Date(timeIntervalSince1970: 0)
        let mqry = MPMediaQuery.songs()
        if let items = mqry.items {
            for item in items {
                if let url = item.assetURL {  //must have a url to play it
                    mibp[url.absoluteString] = item
                    let lpd = item.lastPlayedDate ?? datezero
                    dais.append(["path": url.absoluteString,
                                 "title": item.title ?? "",
                                 "artist": item.artist ?? "",
                                 "album": item.albumTitle ?? "",
                                 "lp": lpd.ISO8601Format() ]) } } }
    }

    func getAlbumSongs(_ nps:String) -> String {
        var rets = ""
        if let data = nps.data(using: .utf8) {
            do {
                if let sj = try JSONSerialization.jsonObject(
                     with: data,
                     options: .mutableContainers) as? [String:String] {
                    let artist = sj["ar"]
                    let title = sj["ti"]
                    var mis = [MPMediaItem]()
                    for (_, mi) in mibp {
                        if(mi.artist == artist && mi.albumTitle == title) {
                            mis.append(mi) } }
                    mis.sort(by: {$0.albumTrackNumber < $1.albumTrackNumber})
                    let paths = mis.map({$0.assetURL!.absoluteString})
                    rets = toJSONString(paths) }
            } catch {
                conlog("getAlbumSongs failed: \(error)")
            } }
        return rets
    }

    func toJSONString<T>(_ value: T) -> String where T: Encodable {
        var retval = ""
        let enc = JSONEncoder()
        enc.outputFormatting = .withoutEscapingSlashes
        if let jsondat = try? enc.encode(value) {
            if let jsonstr = String(data: jsondat, encoding: .utf8) {
                retval = jsonstr } }
        return retval
    }
}


//receive JSON: {qname:"Main", fname:"getData", pobj:Any}
//   send JSON: {qname:"Main", fname:"getData", res:Any}
extension ViewController:WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive msg: WKScriptMessage) {
        if msg.name != "diggerMsgHandler" {
            debugPrint("unknown msg.name: ", msg.name) }
        var mstr = msg.body as! String
        var idx = mstr.firstIndex(of:":")!
        let qname = String(mstr.prefix(upTo: idx))
        //conlog("userContentController qname: \(qname)")
        idx = mstr.index(after: idx)  //idx += 1
        mstr.removeSubrange(mstr.startIndex..<idx)  //mutate mstr
        idx = mstr.firstIndex(of:":")!
        let msgid = String(mstr.prefix(upTo: idx))
        //conlog("userContentController msgid: \(msgid)")
        idx = mstr.index(after: idx)  //idx += 1
        mstr.removeSubrange(mstr.startIndex..<idx)  //mutate mstr
        idx = mstr.firstIndex(of:":")!
        let fname = String(mstr.prefix(upTo: idx))
        //conlog("userContentController fname: \(fname)")
        idx = mstr.index(after: idx)  //idx += 1
        mstr.removeSubrange(mstr.startIndex..<idx)  //mutate mstr
        //conlog("userContentController param: \(mstr)")
        if(fname.starts(with:"hub")) {
            handleHubCall(qname, msgid, fname, mstr) }
        else {
            let resjson = handleDiggerCall(fname, mstr)
            webviewResult(qname, msgid, fname, resjson) }
    }


    func webviewResult(_ qname:String, _ msgid:String, _ fname:String,
                       _ resjson:String) {
        let basic = "\(qname):\(msgid):\(fname):\(resjson)"
        let retval = basic.replacingOccurrences(of:"'", with:"\\'")
        conlog("retval: \(shortstr(retval))")
        let cbstr = "app.svc.iosReturn('\(retval)')"
        writeFile("lastScript.js", cbstr)
        self.webView.evaluateJavaScript(cbstr)
    }


    func handleDiggerCall(_ fname:String, _ param:String) -> String {
        switch(fname) {
        case "getVersionCode":
            return "alpha"
        case "getAppVersion":  //v + CFBundleVersion
            return "v1.0.?"
        case "readConfig":
            return readFile(docDirFileURL("config.json"))
        case "writeConfig":
            return writeFile("config.json", param)
        case "readDigDat":
            initMediaInfo()
            return readFile(docDirFileURL("digdat.json"))
        case "writeDigDat":
            return writeFile("digdat.json", param)
        case "requestMediaRead":
            return xmitEscape(toJSONString(self.dais));
        case "requestAudioSummary":
            return xmitEscape(toJSONString(self.dais));
        case "statusSync":
            synchronizePlaybackQueue(param)
            return getPlaybackStatus()
        case "pausePlayback":
            self.smpc.pause()   //MPMediaPlayback protocol
            return getPlaybackStatus()
        case "resumePlayback":
            self.smpc.play()
            return getPlaybackStatus()
        case "seekToOffset":
            self.smpc.currentPlaybackTime = timeIntervalFromMStr(param)
            return getPlaybackStatus()
        case "startPlayback":
            resetQueueAndPlay(pathsToMIA(param), "Starting playback")
            if(perr != "") {
                return perr }
            return "prepared"
        case "fetchAlbum":
            return getAlbumSongs(param)
        case "copyToClipboard":
            UIPasteboard.general.string = param
            return ""
        case "docContent":
            return readAppDocContent(param)
        default:
            let err = "Error - handleDiggerCall unknown fname: \(fname)"
            conlog(err)
            return err }
    }


    func docDirFileURL(_ fname:String) -> URL {
        let fcs = fname.split(separator: ".")
        let fnm = String(fcs[0])
        let ext = String(fcs[1])
        let docdirURL = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask)[0]
        let fileURL = URL(fileURLWithPath: fnm,
                          relativeTo: docdirURL).appendingPathExtension(ext)
        return fileURL
    }


    func xmitEscape(_ json:String) -> String {
        var ej = json
        ej = ej.replacingOccurrences(of:"\n", with:" ")
        ej = ej.replacingOccurrences(of:"  ", with:" ")
        ej = ej.replacingOccurrences(of:"  ", with:" ")
        ej = ej.replacingOccurrences(of:"  ", with:" ")
        ej = ej.replacingOccurrences(of:"\\", with:"\\\\")
        ej = ej.replacingOccurrences(of:"\"", with:"\\\"")
        return ej
    }


    //param is a simple doc file url e.g. "docs/privacy.html"
    func readAppDocContent(_ param:String) -> String {
        var ret = "Error - File not found: \(param)"
        let pfs = param.split(separator: "/")
        let subdir = String(pfs[0])
        let fcs = pfs[1].split(separator: ".")
        let fnm = String(fcs[0])
        let ext = String(fcs[1])
        if let url = Bundle.main.url(forResource: fnm, withExtension: ext,
                                     subdirectory: subdir) {
            if FileManager.default.fileExists(atPath: url.path) {
                ret = readFile(url) } }
        return ret
    }


    func readFile(_ furl:URL) -> String {
        do {
            let fileManager = FileManager.default
            if(!fileManager.fileExists(atPath: furl.path)) {
                return "" }
            let dc = try Data(contentsOf: furl)
            let rv = String(data: dc, encoding: .utf8)
            return xmitEscape(rv!)
        } catch {
            return "Error - readFile failed"
        }
    }


    func writeFile(_ fname:String, _ content:String) -> String {
        let furl = docDirFileURL(fname)
        guard let data = content.data(using: .utf8) else {
            return "Error - writeFile data conversion failed" }
        do {
            try data.write(to: furl)
            return xmitEscape(content)
        } catch {
            return "Error - writeFile data.write failed"
        }
    }


    func timeIntervalToMS(_ ti:TimeInterval) -> Int {
        return Int(round(ti * 1000))
    }


    func timeIntervalFromMStr(_ mstr:String) -> TimeInterval {
        var ims = Int(mstr) ?? -1
        if(ims < 0) {
            conlog("Could not convert ms string to Int: \(mstr)")
            ims = 0 }
        return TimeInterval(ims / 1000)
    }


    func pathsToMIA(_ paths:String) -> [MPMediaItem] {
        var mia = [MPMediaItem]()
        if let data = paths.data(using: .utf8) {
            do {
                if let psa = try JSONSerialization.jsonObject(
                     with: data,
                     options: .mutableContainers) as? [String] {
                    mia = psa.map({ mibp[$0]! }) }
            } catch {
                conlog("pathsToMIA failed: \(error)")
            } }
        return mia
    }


    func miaToMIQD(_ mia:[MPMediaItem]) -> MPMusicPlayerQueueDescriptor {
        let mic = MPMediaItemCollection(items:mia)
        let miqd = MPMusicPlayerMediaItemQueueDescriptor(itemCollection:mic)
        return miqd as MPMusicPlayerQueueDescriptor
    }


    func getPlaybackStatus() -> String {
        var pbstat = "paused"  //By default, show a play button.
        if(self.smpc.playbackState == MPMusicPlaybackState.playing) {
            pbstat = "playing" }
        let pbpos = timeIntervalToMS(self.smpc.currentPlaybackTime)
        var itemDuration = 0
        var itemPath = ""
        if let npi = self.smpc.nowPlayingItem {
            itemDuration = timeIntervalToMS(npi.playbackDuration)
            if let url = npi.assetURL {
                itemPath = url.absoluteString } }
        let statstr = toJSONString(["state": pbstat,
                                    "pos": String(pbpos),
                                    "dur": String(itemDuration),
                                    "path": itemPath])
        return statstr
    }


    func getDiggerQueueState() -> [MPMediaItem]? {
        if(qsta == nil) {
            let qtxt = readFile(docDirFileURL("digqstat.json"))
            if(!qtxt.hasPrefix("Error ")) {
                qsta = pathsToMIA(qtxt) }
            if(qsta == nil) {
                conlog("digqstat.json retrieval failed.") } }
        return qsta
    }


    func saveDiggerQueueState(_ updq:[MPMediaItem]) {
        qsta = updq
        let res = writeFile("digqstat.json",
                            toJSONString(updq.map({ $0.assetURL })))
        let content = shortstr(res)
        conlog("saveDiggerQueueState \(qsta!.count) items: \(content)")
    }


    //Assuming the queue has been set, prepare for playback
    func prepPlayback(_ caller:String) {
        self.smpc.prepareToPlay(
          completionHandler: { (err) in
              if let errobj = err {
                  self.conlog("\(caller) prepareToPlay error: \(errobj)")
                  self.smpc.play() }  //Prepares the queue if needed.
              else {
                  self.conlog("\(caller) prepareToPlay success")
                  if(self.smpc.playbackState != MPMusicPlaybackState.playing) {
                      self.smpc.play() } } })
    }


    //Prefer to have playback transition without interrupting the currently
    //playing song, but most important to actually start playing the queue.
    func resetQueueAndPlay(_ updq:[MPMediaItem], _ reason:String) {
        conlog("resetQueueAndPlay: \(reason)")
        perr = ""
        if(updq.count == 0) {
            perr = "Error - Empty queue given, resetQueueAndPlay ignored"
            return }
        saveDiggerQueueState(updq)
        self.smpc.stop()  //MPMediaPlayback.  Clears the queue.
        self.smpc.nowPlayingItem = nil  //clear state
        self.smpc.setQueue(with: miaToMIQD(updq))  //MPMusicPlayerController
        prepPlayback("resetQueueAndPlay")
    }


    //It's remotely possible the paths could change while the app is
    //running, but that would mess up finding an updated song on return from
    //hubsync so just as well to use the path as the comparison here.  Only
    //allowed to play locally available files.
    func sameSong(_ mif:MPMediaItem?, _ mib:MPMediaItem?) -> Bool {
        if((mif == nil) || (mib == nil)) {
            return false }
        if(mif!.assetURL == mib!.assetURL) {
            return true }
        return false
    }


    //provided qstat and updq are both available, check no changes and
    //append any additional songs given.
    func syncQueueWithUpdates(_ qstat:[MPMediaItem], _ updq:[MPMediaItem],
                              _ nowpi:MPMediaItem, _ npidx:Int) {
        if let upidx = updq.firstIndex(where: {sameSong($0, nowpi)}) {
            var offset = 0
            while(((npidx + offset) < qstat.count) &&
                  ((upidx + offset) < updq.count)) {
                if(!sameSong(qstat[npidx + offset], updq[upidx + offset])) {
                    conlog("syncQueueWithUpdates differs at offset \(offset)")
                    conlog("   qstat: \(qstat[npidx + offset].assetURL!)")
                    conlog("    updq: \(updq[upidx + offset].assetURL!)")
                    resetQueueAndPlay(updq, "Update queue content differs")
                    return }
                offset += 1 }
            if((npidx + offset) < qstat.count) {
                //update queue was shorter, probably additional filtering
                resetQueueAndPlay(updq, "Update queue has fewer items") }
            else if((upidx + offset) >= updq.count) { //queues were same length
                conlog("playback queue up to date, \(qstat.count) items") }
            else {  //queues match, append additional update items
                conlog("appending additional songs to playback queue")
                var newsongs = [MPMediaItem]()
                while((upidx + offset) < updq.count) {
                    newsongs.append(updq[upidx + offset]) }
                self.smpc.append(miaToMIQD(newsongs))
                //self.smpc.prepareToPlay()
                let merged = qstat + newsongs
                saveDiggerQueueState(merged) } }
        else {
            resetQueueAndPlay(updq, "Now playing song not in updated queue") }
    }


    func synchronizePlaybackQueue(_ paths:String) {
        let updq = pathsToMIA(paths)
        if let qstat = getDiggerQueueState() { //loads from disk if needed
            if(qstat.isEmpty) {
                resetQueueAndPlay(updq, "Replacing empty digger queue state")
                return }
            if(!self.smpc.isPreparedToPlay) {
                prepPlayback("synchronizePlaybackQueue")
                return }
            if let nowpi = self.smpc.nowPlayingItem {
                let npidx = self.smpc.indexOfNowPlayingItem
                if(npidx == NSNotFound) {
                    resetQueueAndPlay(updq, "No index for now playing")
                    return }
                if(npidx < 0 || qstat.count <= npidx) {
                    resetQueueAndPlay(updq, "npidx out of range")
                    return }
                if(!sameSong(nowpi, qstat[npidx])) {
                    //current queue is out of sync with app state queue
                    resetQueueAndPlay(updq, "Queue state inconsistent")
                    return }
                syncQueueWithUpdates(qstat, updq, nowpi, npidx) }
            else {  //no item to sync queues from if nowpi is nil
                resetQueueAndPlay(updq, "No currently playing item")
                return } }
        else {
            resetQueueAndPlay(updq, "No digger queue state available") }
    }


    //hub calls are differentiated by endpoint and protocol. The fname is
    //just referenced for return processing.
    func handleHubCall(_ qname:String, _ msgid:String, _ fname:String,
                       _ param:String) {
        var endpoint = ""
        var method = ""
        var data = ""
        if let pd = param.data(using: .utf8) {
            do {
                if let pobj = try JSONSerialization.jsonObject(
                     with: pd,
                     options: .mutableContainers) as? [String:String] {
                    endpoint = pobj["endpoint"]!
                    method = pobj["method"]!
                    data = pobj["data"]! }
            } catch {
                conlog("handleHubCall JSON unpack failed: \(error)")
            } }
        if(endpoint == "") {
            webviewResult(qname, msgid, fname,
                          "Error - no endpoint specified")
            return }
        let scfg = URLSessionConfiguration.default
        scfg.timeoutIntervalForRequest = 6
        scfg.timeoutIntervalForResource = 20
        let session = URLSession(configuration: scfg)
        let requrl = URL(string: "https://diggerhub.com/api" + endpoint)
        var req = URLRequest(url: requrl!)
        req.httpMethod = method
        req.setValue("application/x-www-form-urlencoded",
                     forHTTPHeaderField: "Content-Type")
        req.httpBody = data.data(using: .utf8)
        let task = session.dataTask(
          with: req as URLRequest,
          completionHandler: { (result, response, error) in
              if(error != nil) {
                  self.webviewResult(qname, msgid, fname,
                                     "Error - Call error: \(error!)")
                  return }
              guard let hursp = response as? HTTPURLResponse else {
                  self.webviewResult(qname, msgid, fname,
                                     "Error - Non http response")
                  return }
              if(hursp.statusCode < 200 || hursp.statusCode >= 300) {
                  self.webviewResult(qname, msgid, fname,
                                     "Error - code: \(hursp.statusCode)")
                  return }
              let rstr = String(bytes: result!, encoding: .utf8)
              self.webviewResult(qname, msgid, fname, rstr!) })
        task.resume()
    }
}
