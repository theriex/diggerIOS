import UIKit
import WebKit
import MediaPlayer

class ViewController: UIViewController, WKUIDelegate {
    var webView: WKWebView!
    var dpu = DiggerProcessingUtilities()
    var dmp = DiggerQueuedPlayerManager()
    var hubsession: URLSession?

    override func loadView() {
        let wvconf = WKWebViewConfiguration()
        wvconf.userContentController.add(self, name:"diggerMsgHandler")
        webView = WKWebView(frame:.zero, configuration:wvconf)
        webView.uiDelegate = self
        webView.scrollView.bounces = false  //display is fixed on screen
        webView.scrollView.isScrollEnabled = false  //scroll within panels only
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
        self.webView.evaluateJavaScript(cbstr,
            completionHandler: { (obj, err) in
                if(err != nil) {
                    self.dpu.conlog("webviewResult eval failed: \(err!)")
                    let errscr = self.dpu.writeFile("evalErrScript.js", cbstr)
                    self.dpu.conlog("errscr: \(self.dpu.shortstr(errscr))")
                    let etxt = "Error - webviewResult callback failed"
                    let eret = "\(qname):\(msgid):\(fname):\(etxt)"
                    self.webView.evaluateJavaScript(eret) } })
    }


    func binfo(_ key:String) -> String {
        let rs = Bundle.main.infoDictionary?[key] as? String ?? "unknown"
        return rs
    }


    func handleDiggerCall(_ fname:String, _ param:String) -> String {
        switch(fname) {
        case "getVersionCode":
            return binfo("CFBundleVersion")
        case "getAppVersion":
            return "v\(binfo("CFBundleShortVersionString"))"
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
            return self.dpu.xmitEscape(self.dpu.toJSONString(self.dmp.dais))
        case "requestAudioSummary":
            return self.dpu.xmitEscape(self.dpu.toJSONString(self.dmp.dais))
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
        if(hubsession == nil) {
            let scfg = URLSessionConfiguration.default
            hubsession = URLSession(configuration: scfg) }
        callHub(qname, msgid, fname, endpoint, method, data)
    }

    func callHub(_ qname:String, _ msgid:String, _ fname:String,
                 _ endpoint:String, _ method:String, _ data:String) {
        dpu.conlog("\(qname)\(msgid)\(fname) \(endpoint) \(method) \(data)")
        let requrl = URL(string: "https://diggerhub.com/api" + endpoint)
        var req = URLRequest(url: requrl!)
        req.httpMethod = method
        req.setValue("application/x-www-form-urlencoded",
                     forHTTPHeaderField: "Content-Type")
        req.httpBody = data.data(using: .utf8)
        let task = hubsession!.dataTask(
          with: req as URLRequest,
          completionHandler: { (result, response, error) in
              if(error != nil) {
                  DispatchQueue.main.async {
                      let errtxt = error!.localizedDescription
                      self.webviewResult(
                        qname, msgid, fname, 
                        "Error - code: 400 Call error: \(errtxt)") }
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
                  rstr = String(bytes: rdat, encoding: .utf8)!
                  //a failed call may have embedded quotes or newlines
                  rstr = self.dpu.xmitEscape(rstr) }
              if(sc < 200 || sc >= 300) {
                  DispatchQueue.main.async {
                      self.webviewResult(
                        qname, msgid, fname,
                        "Error - code: \(sc) \(rstr)") }
                  return }
              DispatchQueue.main.async {
                  //self.dpu.writeFile("hubres.json", rstr)
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
        ej = ej.replacingOccurrences(of:"\r", with:" ")
        ej = ej.replacingOccurrences(of:"\u{B}", with:" ") //line tab (LT)
        ej = ej.replacingOccurrences(of:"\u{C}", with:" ") //form feed (FF)
        ej = ej.replacingOccurrences(of:"\u{85}", with:" ") //next line (NEL)
        ej = ej.replacingOccurrences(of:"\u{2028}", with:" ") //line sep (LS)
        ej = ej.replacingOccurrences(of:"\u{2029}", with:" ") //para sep (PS)
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
        let subdir = "docroot/\(String(pfs[0]))"
        let fcs = pfs[1].split(separator: ".")
        let fnm = String(fcs[0])
        let ext = String(fcs[1])
        if let url = Bundle.main.url(forResource: fnm, withExtension: ext,
                                     subdirectory: subdir) {
            //conlog("readAppDocContent \(url)")
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
    var qsta:[MPMediaItem]? = nil  //current queue state reference
    var sleepOffset = 1000
    var sleeping = false
    var queueResetFlag = false
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
        songJustChanged()
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

    func synchronizePlaybackQueue(_ paths:String) {
        let updq = pathsToMIA(paths)
        if(updq.count == 0) {
            dpu.conlog("synchronizePlaybackQueue ignoring empty updq")
            return }
        if let qstat = getDiggerQueueState() { //loads from disk if needed
            if(qstat.isEmpty) {
                dpu.conlog("Replacing empty digger queue state")
                setDiggerQueue(updq, "playnow")
                return }
            if let nowpi = smpc.nowPlayingItem {
                let npidx = smpc.indexOfNowPlayingItem
                if(npidx == NSNotFound) {  //unknown how this can happen
                    dpu.conlog("No index for now playing, unknown queue state")
                    setDiggerQueue(updq, "playnow")
                    return }
                if(npidx < 0 || qstat.count <= npidx) {  //shouldn't happen
                    dpu.conlog("npidx \(npidx) outside of queue range")
                    setDiggerQueue(updq, "playnow")
                    return }
                if(!sameSong(nowpi, qstat[npidx])) {
                    //Probably Digger started while some other music playing.
                    //Could "playnext", but most likely want new music now.
                    dpu.conlog("now playing out of sync with app queue")
                    setDiggerQueue(updq, "playnow")
                    return }
                syncQueueWithUpdates(qstat, updq, nowpi, npidx) }
            else {  //no item to sync queues from if nowpi is nil
                dpu.conlog("now playing nil, restarting queue")
                setDiggerQueue(updq, "playnow")
                return } }
        else {  //no previous digger queue state. Start digger music now
            dpu.conlog("Initializing digger queue state")
            setDiggerQueue(updq, "playnow") }
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
        dpu.conlog("getPlaybackStatus: \(statstr)")
        return statstr
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

    func startPlayback(_ param:String) -> String {
        dpu.conlog("Starting playback")
        let updq = pathsToMIA(param)
        if(updq.count == 0) {
            return "Error - Empty queue given, startPlayback call ignored" }
        setDiggerQueue(updq, "playnow")
        return "prepared"
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
                    for (_, mi) in mibp {  //walk dict
                        if(mi.artist == artist && mi.albumTitle == title) {
                            mis.append(mi) } }
                    mis.sort(by: {$0.albumTrackNumber < $1.albumTrackNumber})
                    let paths = mis.map({$0.assetURL!.absoluteString})
                    rets = dpu.toJSONString(paths) }
                else {
                    dpu.conlog("getAlbumSongs unable to load JSON") }
            } catch {
                dpu.conlog("getAlbumSongs failed: \(error)")
            } }
        else {
            dpu.conlog("getAlbum songs, no data for now playing song") }
        return rets
    }

    // helper functions

    func songJustChanged() {
        if(sleepOffset <= 0) {
            if(!sleeping) {
                dpu.conlog("songJustChanged sleepOffset \(sleepOffset)")
                sleeping = true
                smpc.stop() } }
        else {
            sleepOffset -= 1
            if(queueResetFlag) {
                queueResetFlag = false
                if let updq = getDiggerQueueState() {
                    //need to remove the song that just ended
                    let cdr = Array(updq[1 ..< updq.endIndex])
                    setDiggerQueue(cdr, "playnow") }
                else {
                    dpu.conlog("queueResetFlag cleared but no updq") } } }
    }

    func setPlayerQueueAndStartPlayback(_ updq:[MPMediaItem]) {
        smpc.stop()  //MPMediaPlayback.  Supposedly clears the queue.
        smpc.nowPlayingItem = nil  //clear state
        smpc.setQueue(with: miaToMIQD(updq))  //MPMusicPlayerController
        sleepOffset = updq.count
        sleeping = false
        queueResetFlag = false
        smpc.prepareToPlay(  //must call for queue updates to take effect
          completionHandler: { (err) in
              if let errobj = err {
                  self.dpu.conlog("prepareToPlay error: \(errobj)")
                  self.smpc.play() }  //Prepares the queue if needed.
              else {
                  self.dpu.conlog("prepareToPlay success")
                  if(self.smpc.playbackState != MPMusicPlaybackState.playing) {
                      self.smpc.play() } } })
    }

    func setDiggerQueue(_ updq:[MPMediaItem], _ play:String) {
        saveDiggerQueueState(updq)
        if(play == "playnow") {
            setPlayerQueueAndStartPlayback(updq) }
        else {  //playnext
            queueResetFlag = true }
    }

    func saveDiggerQueueState(_ updq:[MPMediaItem]) {
        qsta = updq
        let res = dpu.writeFile("digqstat.json",
                                dpu.toJSONString(updq.map({ $0.assetURL })))
        let content = dpu.shortstr(res)
        dpu.conlog("saveDiggerQueueState \(qsta!.count) items: \(content)")
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
                    //might get a path with no corresponding local media item
                    for path in psa {
                        if let mi = mibp[path] {
                            mia.append(mi) } } }
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

    //with qstat and updq both available, check no changes and
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
                    setDiggerQueue(updq, "playnext")
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
                let merged = qstat + newsongs
                saveDiggerQueueState(merged) } }
        else if(updq.count <= 1 && sleepOffset <= 0) {
            dpu.conlog("syncQueueWithUpdates noted sleep state") }
        else {  //situation should have been caught in synchronizePlaybackQueue
            dpu.conlog("synchronizePlaybackQueue now playing was not in queue")
            setDiggerQueue(updq, "playnow") }
    }
}
