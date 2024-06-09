import UIKit
import WebKit
import MediaPlayer

class ViewController: UIViewController, WKUIDelegate {
    var webView: WKWebView!
    var dmh = DiggerMessageHandler()
    var dpu = DiggerProcessingUtilities()

    override func loadView() {
        let wvconf = WKWebViewConfiguration()
        wvconf.userContentController.add(self, name:"diggerMsgHandler")
        webView = WKWebView(frame:.zero, configuration:wvconf)
        webView.uiDelegate = self
        webView.scrollView.bounces = false  //display is fixed on screen
        webView.scrollView.isScrollEnabled = false  //scroll within panels only
        if #available(macOS 13.3, iOS 16.4, tvOS 16.4, *) {
            webView.isInspectable = true }
        view = webView
        dmh.setCallbackWebView(webView)
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
        dmh.handleDiggerMessage(qname, msgid, fname, mstr)
    }
}


//////////////////////////////////////////////////////////////////////
//
// Handle platform request messages from the Digger App
//
//////////////////////////////////////////////////////////////////////
class DiggerMessageHandler {
    var dmhwv: WKWebView!
    var hubsession: URLSession?
    var dpu = DiggerProcessingUtilities()
    var dmp = DiggerQueuedPlayerManager()

    func setCallbackWebView(_ webv:WKWebView) {
        dmhwv = webv
        dmp.setCallbackMessageHandler(self)
    }

    func handleDiggerMessage(_ qname:String, _ msgid:String, _ fname:String,
                             _ mstr:String) {
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
        self.dmhwv.evaluateJavaScript(cbstr,
            completionHandler: { (obj, err) in
                if(err != nil) {
                    self.dpu.conlog("webviewResult eval failed: \(err!)")
                    let errscr = self.dpu.writeFile("evalErrScript.js", cbstr)
                    self.dpu.conlog("errscr: \(self.dpu.shortstr(errscr))")
                    let etxt = "Error - webviewResult callback failed"
                    let eret = "\(qname):\(msgid):\(fname):\(etxt)"
                    self.dmhwv.evaluateJavaScript(eret) } })
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
            return self.dpu.readFile("config.json", "xmit")
        case "writeConfig":
            return self.dpu.writeFile("config.json", param)
        case "readDigDat":
            self.dmp.initMediaInfo("readDigDat")
            return self.dpu.readFile("digdat.json", "xmit")
        case "writeDigDat":
            return self.dpu.writeFile("digdat.json", param)
        case "requestMediaRead":
            self.dmp.initMediaInfo("requestMediaRead")
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
                ret = readFileURL(url, "xmit") } }
        return ret
    }

    func readFile(_ name:String, _ retform:String) -> String {
        return readFileURL(docDirFileURL(name), retform)
    }

    func readFileURL(_ furl:URL, _ retform:String) -> String {
        do {
            let fileManager = FileManager.default
            if(!fileManager.fileExists(atPath: furl.path)) {
                return "" }
            let dc = try Data(contentsOf: furl)
            var rv = String(data: dc, encoding: .utf8)
            if(retform == "xmit") {  //as opposed to "raw"
                rv = xmitEscape(rv!) }
            return rv!
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
    var latestStatusItemPath = ""
    var songChangeNoticePath = ""
    var mibp = [String: MPMediaItem]()  //Media items by path
    var dais = [[String: String]]()  //Digger Audio Items
    var medchk = "unchecked"
    var dmh: DiggerMessageHandler!

    init() {
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(noteMPNPIDC),
          name: NSNotification.Name.MPMusicPlayerControllerNowPlayingItemDidChange,
          object: nil)
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(noteAppTerminating),
          name: UIApplication.willTerminateNotification,
          object: nil)
    }

    @objc func noteMPNPIDC(_ nfn:Notification) {
        songJustChanged()
    }

    @objc func noteAppTerminating(_ nfn:Notification) {
        let pb = dmh.dmp.pause()
        dpu.conlog("noteAppTerminating pause: \(pb)")
    }

    func setCallbackMessageHandler(_ dmhobj:DiggerMessageHandler) {
        dmh = dmhobj
    }

    func checkMediaAuthorization() {
        if #available(iOS 9.3, *) {  //9.3 or later has permissioning
            dpu.conlog("checkMediaAuthorization request authorizationStatus")
            let authstat = MPMediaLibrary.authorizationStatus()
            switch authstat {
            case .notDetermined: //show permission prompt if not asked yet
                dpu.conlog("checkMediaAuthorization: .notDetermined")
                medchk = "asking"
                MPMediaLibrary.requestAuthorization({[weak self] (newAuthorizationStatus: MPMediaLibraryAuthorizationStatus) in
                    if(newAuthorizationStatus == .authorized) {
                        self?.medchk = "authorized" }
                    else {
                        self?.medchk = "denied" }
                    self?.initMediaInfo("iosdlg") })
                return
            case .denied, .restricted:  //can't use MPMediaQuery
                dpu.conlog("checkMediaAuthorization: .denied or .restricted")
                medchk = "denied"
                return
            case .authorized:
                medchk = "authorized"
                dpu.conlog("checkMediaAuthorization: .authorized")
                break
            default:  //not sure what case this is, but worth trying read
                medchk = "authorized"
                dpu.conlog("checkMediaAuthorization default case fallthrough")
                break } }
        else {
            medchk = "authorized" }
    }

    func initMediaInfo(_ caller:String) {
        mibp = [String: MPMediaItem]()  //reset
        dais = [[String: String]]()  //reset
        if(medchk == "asking") { return }  //don't want two threads asking
        if(medchk != "authorized") { return checkMediaAuthorization() }
        let datezero = Date(timeIntervalSince1970: 0)
        let mqry = MPMediaQuery.songs()
        if let items = mqry.items {
            for item in items {
                if let url = item.assetURL {  //must have a url to play it
                    let path = url.absoluteString
                    mibp[path] = item
                    let lpd = item.lastPlayedDate ?? datezero
                    dais.append(["path": path,
                                 "title": item.title ?? "",
                                 "artist": item.artist ?? "",
                                 "album": item.albumTitle ?? "",
                                 "genre": item.genre ?? "",
                                 "lp": lpd.ISO8601Format() ]) } } }
        if(caller == "iosdlg") {
            DispatchQueue.main.async {  //needs to run on main thread
                self.dmh.webviewResult("iospush", "iosdlg", "initMediaInfo",
                                       "") } }
    }

    //The systemMusicPlayer is shared, so its queue can be changed any time
    //by any app.  Digger "startPlayback" sends an full queue of ~200 song
    //paths (or N album song paths) which is saved to digqstat.json.  The
    //update queue parameter given here will hard replace the existing queue
    //if there are no songs left in the existing queue to play.  Otherwise
    //it will continue to play what it still has left.  The first song in
    //the queue is the one currently playing.  An empty updq is ignored.  An
    //empty queue happens at app launch when the app does an initial status
    //check to see what is currently playing.
    func synchronizePlaybackQueue(_ paths:String) {
        let updq = pathsToMIA(paths)
        if(updq.isEmpty) {
            dpu.conlog("syncPQ ignoring call with empty updq")
            return }
        let srt = queuedCommonSongsRemainingToPlay(updq)
        if(srt > 1) {  //now playing common, 1+ common digq/updq songs after
            dpu.conlog("syncPQ \(srt) queued songs left, continuing playback") }
        else if(srt == 1) {  //currently playing song in common
            //if updq.count > 1 then previous check shows hard reset needed
            if((updq.count == 1) && existingQueueEquivalent(updq)) {
                dpu.conlog("syncPQ no change to existing queue") }
            else {  //change queue after current song finishes
                dpu.conlog("syncPQ resetting queue after current song ends")
                setDiggerQueue(updq, "playnext") } }
        else {  //srt == 0, nothing in common, hard reset queue and play
            dpu.conlog("syncPQ replacing queue with update queue")
            setDiggerQueue(updq, "playnow") }
    }

    //Unless overwritten by another app, the systemMusicPlayer queue (sysq)
    //is equivalent to the digger queue (digq) it was last set with.  The
    //sysq is opaque, so use indexOfNowPlayingItem to test nowPlayingItem
    //against the same index in digq.  If NOT the same song, then sysq has
    //changed, otherwise proceed on the hope that digq and sysq have the
    //same content.  Treating digq as equivalent to sysq, count remaining
    //songs in digq that are still in updq.  The currently playing song may
    //be in common or not.
    func queuedCommonSongsRemainingToPlay(_ updq:[MPMediaItem]) -> Int {
        if let digq = getDiggerQueueState() { //loads from disk if needed
            if(digq.isEmpty) {
                dpu.conlog("qSR2P digq empty")
                return 0 }
            if let nowpi = smpc.nowPlayingItem {
                let npidx = smpc.indexOfNowPlayingItem
                if(npidx == NSNotFound) {  //unknown how this can happen
                    dpu.conlog("qSR2P no index for now playing")
                    return 0 }
                if(npidx < 0 || digq.count <= npidx) {
                    dpu.conlog("qSR2P npidx \(npidx) outside of digq range")
                    return 0 }
                if(!sameSong(nowpi, digq[npidx])) {
                    dpu.conlog("qSR2P now playing out of sync with app queue")
                    return 0 }
                if(updq.isEmpty) {  //open status query with no queue update
                    dpu.conlog("qSR2P empty updq, returning remaining")
                    return (digq.count - npidx) }
                var cntidx = 0  //now playing song is updq[0] (if common)
                while((cntidx + npidx < digq.count) &&
                        (cntidx < updq.count) &&
                        (sameSong(digq[npidx + cntidx], updq[cntidx]))) {
                    cntidx += 1 }
                dpu.conlog("qSR2P \(cntidx) digq songs remaining")
                return cntidx }
            dpu.conlog("qSR2P no smpc.nowPlayingItem")
            return 0 }
        dpu.conlog("qSR2P no digger queue")
        return 0  //no digger queue means no queued songs left
    }

    func existingQueueEquivalent(_ updq:[MPMediaItem]) -> Bool {
        if let digq = getDiggerQueueState() { //loads from disk if needed
            if(digq.count != updq.count) {
                return false }
            var ccnt = 0
            while(ccnt < updq.count) {
                if(!sameSong(digq[ccnt], updq[ccnt])) {
                    return false }
                ccnt += 1 }
            return true }
        return false
    }

    func getPlaybackStatus() -> String {
        var pbstat = "unknown"
        if((smpc.playbackState == MPMusicPlaybackState.playing) ||
             (smpc.playbackState == MPMusicPlaybackState.interrupted) ||
             (smpc.playbackState == MPMusicPlaybackState.seekingForward) ||
             (smpc.playbackState == MPMusicPlaybackState.seekingBackward)) {
            pbstat = "playing" }
        else if((smpc.playbackState == MPMusicPlaybackState.stopped) ||
                  (smpc.playbackState == MPMusicPlaybackState.paused)) {
            pbstat = "paused" }
        if(sleeping) {
            pbstat = "ended" }
        let pbpos = dpu.timeIntervalToMS(smpc.currentPlaybackTime)
        var itemDuration = 0
        if let npi = smpc.nowPlayingItem {
            itemDuration = dpu.timeIntervalToMS(npi.playbackDuration)
            if let url = npi.assetURL {
                latestStatusItemPath = url.absoluteString } }
        //Not worth declaring an object for dpu.toJSONString to understand
        let statstr = "{\"state\":\"\(pbstat)\",\"pos\":\(pbpos),\"dur\":\(itemDuration),\"path\":\"\(latestStatusItemPath)\"}"
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

    func consoleLogMediaQueue(_ queue:[MPMediaItem]) {
        dpu.conlog("consoleLogMediaQueue media items:")
        for mi in queue {
            dpu.conlog("  \(mi.title ?? "NoTitleFound")") }
    }

    func startPlayback(_ param:String) -> String {
        dpu.conlog("Starting playback")
        let updq = pathsToMIA(param)
        consoleLogMediaQueue(updq)
        if(updq.isEmpty) {
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
                    let album = sj["ab"]
                    var mis = [MPMediaItem]()
                    for (_, mi) in mibp {  //walk dict
                        if(mi.artist == artist && mi.albumTitle == album) {
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

    func writeUpdatedDBO(_ dj:[String:Any]) {
        //dpu.conlog("writeUpdatedDBO start")
        do {
            let resdat = try JSONSerialization.data(
                 withJSONObject:dj, options: .prettyPrinted)
            if let ddstr = String(data:resdat, encoding: .utf8) {
                let _ = self.dpu.writeFile("digdat.json", ddstr)
                dpu.conlog("writeUpdatedDBO digdat.json complete") }
            else {
                dpu.conlog("writeUpdatedDBO Data to String conv failed") }
        } catch {
            dpu.conlog("writeUpdatedDBO serialization err: \(error)") }
    }

    func updatePlayCountFromDBO(_ path:String, _ dj:[String:Any]) {
        //dpu.conlog("updPCFD accessing songs")
        if let sd = dj["songs"] as? [String:Any] {
            dpu.conlog("updPCFD song path: \(path)")
            if var song = sd[path] as? [String:Any] {
                var title = "UNKNOWN"
                if let ti = song["ti"] as? String {
                    title = ti }
                dpu.conlog("updPCFD updating song: \(title)")
                var playcount = 0
                if let pc = song["pc"] as? Int {
                    dpu.conlog("updPCFD retrieved pc: \(pc)")
                    playcount = pc }
                playcount += 1
                song["pc"] = playcount
                dpu.conlog("updPCFD playcount: \(playcount)")
                let tfmt = ISO8601DateFormatter()
                let lastplayed = tfmt.string(from:Date.now)
                song["lp"] = lastplayed
                dpu.conlog("updPCFD lastplayed: \(lastplayed)")
                writeUpdatedDBO(dj) }
            else {
                dpu.conlog("updPCFD song not found") } }
        else {
            dpu.conlog("updPCFD songs field not in dictionary") }
    }

    func updatePlayCount(_ updq:[MPMediaItem]) {
        //dpu.conlog("updatePlayCount called updq.count: \(updq.count)")
        if(updq.isEmpty) { return }
        let pathurl = updq[0].assetURL!
        let path = pathurl.absoluteString  //matches diggerhub path value
        let jsonstr = self.dpu.readFile("digdat.json", "raw")
        //dpu.conlog("updatePlayCount jsonstr: \(jsonstr.prefix(200))")
        if let jdat = jsonstr.data(using: .utf8) {
            do {
                if let dj = try JSONSerialization.jsonObject(
                     with:jdat, options: .mutableContainers) as? [String:Any] {
                    updatePlayCountFromDBO(path, dj) }
            } catch {
                dpu.conlog("updatePlayCount JSON deserialize err: \(error)") } }
    }

    //An empty queue does not necessarily mean sleep.  Could be no more
    //songs on deck.  This function may be called repeatedly in quick
    //succession for no good reason.  smpc.nowPlayingItem may not be well
    //defined or reliable of repeat calls.
    func songJustChanged() {
        dpu.conlog("songJustChanged sleepOffset: \(sleepOffset), queueResetFlag: \(queueResetFlag), latestStatusItemPath: \(latestStatusItemPath)")
        if(songChangeNoticePath == latestStatusItemPath) {
            dpu.conlog("songJustChanged dupe notice \(songChangeNoticePath)")
            return }
        songChangeNoticePath = latestStatusItemPath
        if(queueResetFlag) {
            smpc.pause()  //might be end of album or songs, play after reset
            queueResetFlag = false
            sleepOffset = 0
            if let updq = getDiggerQueueState() {
                if(updq.count > 1) {  //currently playing song first in queue
                    //need to remove the song that just ended
                    let cdr = Array(updq[1 ..< updq.endIndex])
                    updatePlayCount(cdr)  //setDiggerQueue updates sleepOffset
                    setDiggerQueue(cdr, "playnow") }
                else {
                    dpu.conlog("songJustChanged queue reset empty") } }
            else {
                dpu.conlog("songJustChanged queue reset no updq") } }
        else {  //no queue reset, check and update sleepOffset\
            if(sleepOffset > 0) {  //no reset, and more songs to go
                sleepOffset -= 1 }
            else {  //sleepOffset <= 0
                if(!sleeping) {
                    sleeping = true
                    smpc.stop() } } }  //"stopped" == sleeping
    }

    func resetPlayerQueueAndStartPlayback(_ updq:[MPMediaItem]) {
        smpc.stop()  //MPMediaPlayback.  Supposedly clears the queue.
        smpc.nowPlayingItem = nil  //clear state
        sleepOffset = updq.count
        sleeping = false
        queueResetFlag = false
        let logpre = "resetPlayerQueueAndStartPlayback"
        dpu.conlog("\(logpre) sleepOffset: \(sleepOffset)")
        if(updq.isEmpty) {
            dpu.conlog("\(logpre) updq empty, nothing to play")
            return }
        dpu.conlog("\(logpre) calling smpc.setQueue")
        smpc.setQueue(with: miaToMIQD(updq))  //MPMusicPlayerController
        dpu.conlog("\(logpre) calling smpc.prepareToPlay")
        smpc.prepareToPlay(  //must call for queue updates to take effect
          completionHandler: { (err) in
              if let errobj = err {
                  self.dpu.conlog("\(logpre) prepareToPlay error: \(errobj)")
                  self.smpc.play() }  //Prepares the queue if needed.
              else {
                  self.dpu.conlog("\(logpre) prepareToPlay success")
                  //playback state might be left over from previous song so play
                  //even if smpc.playbackState != MPMusicPlaybackState.playing
                  self.smpc.play() } })
    }

    func setDiggerQueue(_ updq:[MPMediaItem], _ play:String) {
        if(updq.isEmpty && queueResetFlag) {
            dpu.conlog("setDiggerQueue empty updq, queueResetFlag already set")
            return }
        dpu.conlog("setDiggerQueue \(updq.count) songs, \(play)")
        saveDiggerQueueState(updq)
        if(play == "playnow") {
            resetPlayerQueueAndStartPlayback(updq) }
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
            let qtxt = dpu.readFile("digqstat.json", "raw")
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
                            //dpu.conlog("pathsToMIA \(mi.title ?? "NoTitle")")
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
        else {  //replace queue, leave now playing song.
            dpu.conlog("syncQueueWithUpdates now playing was not in queue")
            setDiggerQueue(updq, "playnext") }
    }
}
