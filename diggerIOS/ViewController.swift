import UIKit
import WebKit
import MediaPlayer

class ViewController: UIViewController, WKUIDelegate {
    var webView: WKWebView!
    var dpu = DiggerProcessingUtilities()
    var dmp = DiggerQueuedPlayerManager()

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
        var mstr = msg.body as! String
        var idx = mstr.firstIndex(of:":")!
        let qname = String(mstr.prefix(upTo: idx))
        //dpu.conlog("userContentController qname: \(qname)")
        idx = mstr.index(after: idx)  //idx += 1
        mstr.removeSubrange(mstr.startIndex..<idx)  //mutate mstr
        idx = mstr.firstIndex(of:":")!
        let msgid = String(mstr.prefix(upTo: idx))
        //dpu.conlog("userContentController msgid: \(msgid)")
        idx = mstr.index(after: idx)  //idx += 1
        mstr.removeSubrange(mstr.startIndex..<idx)  //mutate mstr
        idx = mstr.firstIndex(of:":")!
        let fname = String(mstr.prefix(upTo: idx))
        //dpu.conlog("userContentController fname: \(fname)")
        idx = mstr.index(after: idx)  //idx += 1
        mstr.removeSubrange(mstr.startIndex..<idx)  //mutate mstr
        //dpu.conlog("userContentController param: \(mstr)")
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
        dpu.conlog("retval: \(dpu.shortstr(retval))")
        let cbstr = "app.svc.iosReturn('\(retval)')"
        //dpu.writeFile("lastScript.js", cbstr)   //for debug analysis
        self.webView.evaluateJavaScript(cbstr)
    }


    func handleDiggerCall(_ fname:String, _ param:String) -> String {
        switch(fname) {
        case "getVersionCode":
            return "alpha"
        case "getAppVersion":  //v + CFBundleVersion
            return "v1.0.?"
        case "readConfig":
            return self.dpu.readFile("config.json")
        case "writeConfig":
            return self.dpu.writeFile("config.json", param)
        case "readDigDat":
            self.dmp.initMediaInfo()
            return self.dpu.readFile("digdat.json")
        case "writeDigDat":
            return self.dpu.writeFile("digdat.json", param)
        case "requestMediaRead":
            return self.dpu.xmitEscape(self.dpu.toJSONString(self.dmp.dais));
        case "requestAudioSummary":
            return self.dpu.xmitEscape(self.dpu.toJSONString(self.dmp.dais));
        case "statusSync":
            self.dmp.synchronizePlaybackQueue(param)
            return self.dmp.getPlaybackStatus()
        case "pausePlayback":
            return self.dmp.pause()
        case "resumePlayback":
            return self.dmp.resume()
        case "seekToOffset":
            return self.dmp.seek(param)
        case "startPlayback":
            return self.dmp.startPlayback(param)
        case "fetchAlbum":
            return self.dmp.getAlbumSongs(param)
        case "copyToClipboard":
            UIPasteboard.general.string = param
            return ""
        case "docContent":
            return self.dpu.readAppDocContent(param)
        default:
            let err = "Error - handleDiggerCall unknown fname: \(fname)"
            self.dpu.conlog(err)
            return err }
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
                dpu.conlog("handleHubCall JSON unpack failed: \(error)")
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
                  DispatchQueue.main.async {
                      self.webviewResult(
                        qname, msgid, fname,
                        "Error - code: 400 Call error: \(error!)") }
                  return }
              guard let hursp = response as? HTTPURLResponse else {
                  DispatchQueue.main.async {
                      self.webviewResult(
                        qname, msgid, fname,
                        "Error - code: 500 Non http response") }
                  return }
              let sc = hursp.statusCode
              var rstr = ""
              if let rdat = result {
                  rstr = String(bytes: rdat, encoding: .utf8)! }
              if(sc < 200 || sc >= 300) {
                  DispatchQueue.main.async {
                      self.webviewResult(
                        qname, msgid, fname,
                        "Error - code: \(sc) \(rstr)") }
                  return }
              DispatchQueue.main.async {
                  self.webviewResult(qname, msgid, fname, rstr) } })
        task.resume()
    }
}


//////////////////////////////////////////////////////////////////////
//
// Factored utility methods for Digger request processing
//
//////////////////////////////////////////////////////////////////////
class DiggerProcessingUtilities {
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

    func toJSONString<T>(_ value: T) -> String where T: Encodable {
        var retval = ""
        let enc = JSONEncoder()
        enc.outputFormatting = .withoutEscapingSlashes
        if let jsondat = try? enc.encode(value) {
            if let jsonstr = String(data: jsondat, encoding: .utf8) {
                retval = jsonstr } }
        return retval
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
                ret = readFileURL(url) } }
        return ret
    }

    func readFile(_ name:String) -> String {
        return readFileURL(docDirFileURL(name))
    }

    func readFileURL(_ furl:URL) -> String {
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
}


//////////////////////////////////////////////////////////////////////
//
// Wrapper to provide Digger music playback functionality
//
//////////////////////////////////////////////////////////////////////
class DiggerQueuedPlayerManager {
    let dpu = DiggerProcessingUtilities()
    let smpc = MPMusicPlayerController.systemMusicPlayer
    var perr = ""
    var qsta:[MPMediaItem]? = nil  //current queue state reference
    var sleepOffset = 1000
    var sleeping = false
    var mibp = [String: MPMediaItem]()  //Media items by path
    var dais = [[String: String]]()  //Digger Audio Items

    init() {
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(noteMPNPIDC),
          name: NSNotification.Name.MPMusicPlayerControllerNowPlayingItemDidChange,
          object: nil)
    }

    @objc func noteMPNPIDC(_ nfn:Notification) {
        songJustEnded()
    }

    func songJustEnded() {
        if(sleepOffset <= 0) {
            dpu.conlog("songJustEnded sleepOffset \(sleepOffset)")
            sleeping = true
            smpc.stop(); }
        else {
            sleepOffset -= 1 }
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
                    rets = dpu.toJSONString(paths) }
            } catch {
                dpu.conlog("getAlbumSongs failed: \(error)")
            } }
        return rets
    }

    func getDiggerQueueState() -> [MPMediaItem]? {
        if(qsta == nil) {  //restore if available if app restarted
            let qtxt = dpu.readFile("digqstat.json")
            if(!qtxt.hasPrefix("Error ")) {
                qsta = pathsToMIA(qtxt) }
            if(qsta == nil) {
                dpu.conlog("digqstat.json retrieval failed.") } }
        return qsta
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
                dpu.conlog("pathsToMIA failed: \(error)")
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
        if(smpc.playbackState == MPMusicPlaybackState.playing) {
            pbstat = "playing" }
        if(sleeping) {
            pbstat = "ended" }
        let pbpos = dpu.timeIntervalToMS(smpc.currentPlaybackTime)
        var itemDuration = 0
        var itemPath = ""
        if let npi = smpc.nowPlayingItem {
            itemDuration = dpu.timeIntervalToMS(npi.playbackDuration)
            if let url = npi.assetURL {
                itemPath = url.absoluteString } }
        let statstr = dpu.toJSONString(["state": pbstat,
                                        "pos": String(pbpos),
                                        "dur": String(itemDuration),
                                        "path": itemPath])
        return statstr
    }

    func startPlayback(_ param:String) -> String {
        resetQueueAndPlay(pathsToMIA(param), "Starting playback")
        if(perr != "") {
            return perr }
        return "prepared"
    }

    func pause() -> String {
        smpc.pause()
        return getPlaybackStatus()
    }

    func resume() -> String {
        smpc.play()
        return getPlaybackStatus()
    }        

    func seek(_ mstr:String) -> String {
        smpc.currentPlaybackTime = dpu.timeIntervalFromMStr(mstr)
        return getPlaybackStatus()
    }

    func saveDiggerQueueState(_ updq:[MPMediaItem]) {
        qsta = updq
        let res = dpu.writeFile("digqstat.json",
                                dpu.toJSONString(updq.map({ $0.assetURL })))
        let content = dpu.shortstr(res)
        dpu.conlog("saveDiggerQueueState \(qsta!.count) items: \(content)")
    }


    //Assuming the queue has been set, prepare for playback
    func prepPlayback(_ caller:String) {
        smpc.prepareToPlay(
          completionHandler: { (err) in
              if let errobj = err {
                  self.dpu.conlog("\(caller) prepareToPlay error: \(errobj)")
                  self.smpc.play() }  //Prepares the queue if needed.
              else {
                  self.dpu.conlog("\(caller) prepareToPlay success")
                  if(self.smpc.playbackState != MPMusicPlaybackState.playing) {
                      self.smpc.play() } } })
    }


    //Prefer to have playback transition without interrupting the currently
    //playing song, but most important to actually start playing the queue.
    func resetQueueAndPlay(_ updq:[MPMediaItem], _ reason:String) {
        dpu.conlog("resetQueueAndPlay: \(reason)")
        perr = ""
        if(updq.count == 0) {
            perr = "Error - Empty queue given, resetQueueAndPlay ignored"
            return }
        saveDiggerQueueState(updq)
        smpc.stop()  //MPMediaPlayback.  Clears the queue.
        smpc.nowPlayingItem = nil  //clear state
        smpc.setQueue(with: miaToMIQD(updq))  //MPMusicPlayerController
        sleepOffset = updq.count
        sleeping = false
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
                    dpu.conlog("syncQueueWithUpdates differs offset \(offset)")
                    dpu.conlog("   qstat: \(qstat[npidx + offset].assetURL!)")
                    dpu.conlog("    updq: \(updq[upidx + offset].assetURL!)")
                    resetQueueAndPlay(updq, "Update queue content differs")
                    return }
                offset += 1 }
            if((npidx + offset) < qstat.count) {
                //update queue was shorter e.g. sleep or additional filtering
                dpu.conlog("updq shorter (\(npidx + offset) < \(qstat.count))")
                sleepOffset = npidx + offset - 1 }
            else if((upidx + offset) >= updq.count) { //queues were same length
                dpu.conlog("playback queue up to date, \(qstat.count) items") }
            else {  //queues match, append additional update items
                dpu.conlog("appending additional songs to playback queue")
                var newsongs = [MPMediaItem]()
                while((upidx + offset) < updq.count) {
                    newsongs.append(updq[upidx + offset])
                    sleepOffset += 1
                    offset += 1 }
                smpc.append(miaToMIQD(newsongs))
                //smpc.prepareToPlay()
                let merged = qstat + newsongs
                saveDiggerQueueState(merged) } }
        else if(updq.count <= 1 && sleepOffset <= 0) {
            dpu.conlog("syncQueueWithUpdates noted sleep state") }
        else {
            resetQueueAndPlay(updq, "Now playing song not in updated queue") }
    }


    func synchronizePlaybackQueue(_ paths:String) {
        let updq = pathsToMIA(paths)
        if let qstat = getDiggerQueueState() { //loads from disk if needed
            if(qstat.isEmpty) {
                resetQueueAndPlay(updq, "Replacing empty digger queue state")
                return }
            if(!smpc.isPreparedToPlay) {
                prepPlayback("synchronizePlaybackQueue")
                return }
            if let nowpi = smpc.nowPlayingItem {
                let npidx = smpc.indexOfNowPlayingItem
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
}
