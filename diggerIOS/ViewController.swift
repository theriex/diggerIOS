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
            //self.dmp.synchronizePlaybackQueue(param) -- using hard queues
            return self.dmp.getPlaybackStatus("statusSync")
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


    //hub calls are differentiated by url and verb/method. The fname is
    //just referenced for return processing.  Caller sets url from endpoint.
    func handleHubCall(_ qname:String, _ msgid:String, _ fname:String,
                       _ param:String) {
        var url = ""
        var method = ""
        var data = ""
        if let pd = param.data(using: .utf8) {
            do {
                if let pobj = try JSONSerialization.jsonObject(
                     with: pd,
                     options: .mutableContainers) as? [String:String] {
                    url = pobj["url"]!
                    method = pobj["verb"]!
                    data = pobj["dat"]! }
            } catch {
                dpu.conlog("handleHubCall JSON unpack failed: \(error)")
            } }
        if(url == "") {
            webviewResult(qname, msgid, fname,
                          "Error - no url specified")
            return }
        if(hubsession == nil) {
            let scfg = URLSessionConfiguration.default
            hubsession = URLSession(configuration: scfg) }
        callHub(qname, msgid, fname, url, method, data)
    }

    func callHub(_ qname:String, _ msgid:String, _ fname:String,
                 _ url:String, _ method:String, _ data:String) {
        dpu.conlog("\(qname)\(msgid)\(fname) \(url) \(method) \(data)")
        let requrl = URL(string: "https://diggerhub.com/api" + url)
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
// Wrapper to provide Digger music playback functionality.
//
// Simple transport calls (pause, resume, seek) and data actions (read/write
// digdat, requestMediaRead, requestAudioSummary, fetchAlbum) are playback
// queue state independent.  Queue modification actions (startPlayback,
// statusSync) change the queue state.  iOS Notification callback handlers
// depend on the playback queue state, and must ignore duplicate notices.
//
// Queue state change calls:
//   startPlayback: Replace playing queue
//   synchronizePlaybackQueue: depends on updq parameter contents
//     - empty: no action  (initial playback status request)
//     - 1st song playing: Replace queue with remainder after song finishes
//     - 1st song not playing: Replace playing queue
//
//////////////////////////////////////////////////////////////////////
class DiggerQueuedPlayerManager {
    let dpu = DiggerProcessingUtilities()
    let smpc = MPMusicPlayerController.systemMusicPlayer
    let dqpmmode = "stateless"  //or "queuestate" for owned queue logic
    var mibp = [String: MPMediaItem]()   //Media items by path
    var dais = [[String: String]]()      //Digger Audio Items
    var medchk = "unchecked"             //media permissioning dlg stat
    var dmh: DiggerMessageHandler!       //back ref for app return values
    // playback queue state management
    var qpcmd = ""  //Queue processing command from app call thread
    var sleepAfterPath = ""  //empty means sleep not active
    var spqp = ""  //synchronizePlaybackQueue last processed paths
    var qsta:[MPMediaItem]? = nil  //current queue state array reference
    var queueResetFlag = false
    var playingLastSongInQueue = false
    var lastQueuedSongPath = ""
    var songChangeNoticePath = ""
    var sleepWakeupNeeded = false  //true if app slept

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
        if(dqpmmode == "queuestate") {
            songJustChanged() }
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
        var npp = ""
        if let nowpi = smpc.nowPlayingItem {
            if let url = nowpi.assetURL {  //succeeds if local music file
                npp = url.absoluteString } }
        if(medchk == "asking") { return }  //don't want two threads asking
        if(medchk != "authorized") { return checkMediaAuthorization() }
        let datezero = Date(timeIntervalSince1970: 0)
        let mqry = MPMediaQuery.songs()
        if let items = mqry.items {
            for item in items {
                if let url = item.assetURL {  //must have a url to play it
                    let path = url.absoluteString
                    mibp[path] = item
                    var lpd = item.lastPlayedDate ?? datezero
                    if(path == npp) {   //if now playing, use an up-to-date
                        lpd = Date() }  //lp val.  iOS waits until later.
                    dais.append(["path": path,
                                 "title": item.title ?? "",
                                 "artist": item.artist ?? "",
                                 "album": item.albumTitle ?? "",
                                 "mddn": String(item.discNumber),
                                 "mdtn": String(item.albumTrackNumber),
                                 "genre": item.genre ?? "",
                                 "pc": String(item.playCount),
                                 "lp": lpd.ISO8601Format() ]) } } }
        if(caller == "iosdlg") {
            DispatchQueue.main.async {  //needs to run on main thread
                self.dmh.webviewResult("iospush", "iosdlg", "initMediaInfo",
                                       "") } }
    }

    @discardableResult
    func setQueueProcessingCommand(_ cmd:String, _ prio:Bool) -> Bool {
        if(qpcmd.isEmpty || prio) {
            qpcmd = cmd
            dpu.conlog("setQueueProcessingCommand: \(cmd)")
            return true }
        return false
    }
    func clearQueueProcessingCommand(_ cmd:String) {
        if(qpcmd == cmd) {
            qpcmd = ""
            dpu.conlog("clearQueueProcessingCommand: \(cmd)") }
    }

    //The systemMusicPlayer is shared, so its queue can be changed any time
    //by any app.  Digger "startPlayback" sends an full queue of ~200 song
    //paths (or N album song paths) which is saved to digqstat.json.  The
    //update queue parameter given here will hard replace the existing queue
    //if the currently playing song does not match, otherwise it will
    //replace the queue after the currently playing song finishes to avoid
    //restarting playback.
    func synchronizePlaybackQueue(_ paths:String) {
        if(paths == spqp) {
            dpu.conlog("syncPQ no change in queue data sent")
            return }
        spqp = paths  //note to avoid duplicate calls
        let updq = pathsToMIA(paths, "synchronizePlaybackQueue")
        if(updq.isEmpty) {
            dpu.conlog("syncPQ ignoring call with empty updq")
            return }
        if(!setQueueProcessingCommand("synchronizePlaybackQueue", false)) {
            dpu.conlog("syncPQ yielding to \(qpcmd), no queue changes.")
            return }
        var firstSongCurrentlyPlaying = false
        if let nowpi = smpc.nowPlayingItem {
            if let url = nowpi.assetURL {  //succeeds if local music file
                if let q0u = updq[0].assetURL {  //always succeeds
                    if(url.absoluteString == q0u.absoluteString) {
                        firstSongCurrentlyPlaying = true } } } }
        if(firstSongCurrentlyPlaying) {
            setDiggerQueue(updq, "playnext") }
        else {  //replace currently playing song with Digger songs
            setDiggerQueue(updq, "playnow") }
        clearQueueProcessingCommand("synchronizePlaybackQueue")
    }

    struct NowPlayingInfo {
        var duration = 0
        var path = ""
        var title = ""
    }
    func nowPlayingInfo() -> NowPlayingInfo {
        var npi = NowPlayingInfo()
        if let item = smpc.nowPlayingItem {
            npi.duration = dpu.timeIntervalToMS(item.playbackDuration)
            if let url = item.assetURL {
                npi.path = url.absoluteString }
            npi.title = item.title ?? "" }
        return npi
    }

    func wasPlayingSleepAfterSong(_ npi:NowPlayingInfo) -> Bool {
        return (!sleepAfterPath.isEmpty && sleepAfterPath == npi.path)
    }

    func getDiggerPlaybackState(_ npi:NowPlayingInfo) -> String {
        let pbpos = dpu.timeIntervalToMS(smpc.currentPlaybackTime)
        var pbstat = "unknown"
        if((smpc.playbackState == MPMusicPlaybackState.playing) ||
             (smpc.playbackState == MPMusicPlaybackState.interrupted) ||
             (smpc.playbackState == MPMusicPlaybackState.seekingForward) ||
             (smpc.playbackState == MPMusicPlaybackState.seekingBackward)) {
            pbstat = "playing" }
        else if(smpc.playbackState == MPMusicPlaybackState.stopped) {
            if(wasPlayingSleepAfterSong(npi)) {
                sleepWakeupNeeded = true
                pbstat = "ended" }  //triggers resume playback display
            else {
                pbstat = "paused" } }
        else if(smpc.playbackState == MPMusicPlaybackState.paused) {
            if(wasPlayingSleepAfterSong(npi) &&
                 (pbpos < 2000 || (npi.duration > 0 &&
                                   npi.duration - pbpos < 2000))) {
                sleepWakeupNeeded = true
                pbstat = "ended" }
            else {
                pbstat = "paused" } }
        return pbstat
    }

    func getPlaybackStatus(_ caller:String) -> String {
        let npi = nowPlayingInfo()
        let pbstat = getDiggerPlaybackState(npi)
        let pbpos = dpu.timeIntervalToMS(smpc.currentPlaybackTime)
        //Not worth declaring an object for dpu.toJSONString to understand
        let statstr = "{\"state\":\"\(pbstat)\",\"pos\":\(pbpos),\"dur\":\(npi.duration),\"path\":\"\(npi.path)\"}"
        dpu.conlog("getPlaybackStatus (\(caller)): \(statstr)")
        return statstr
    }

    func pause() -> String {
        smpc.pause()
        return getPlaybackStatus("pause")
    }

    func resume() -> String {
        smpc.play()
        return getPlaybackStatus("resume")
    }        

    func seek(_ mstr:String) -> String {
        smpc.currentPlaybackTime = dpu.timeIntervalFromMStr(mstr)
        return getPlaybackStatus("seek")
    }

    func consoleLogMediaQueue(_ queue:[MPMediaItem]) {
        dpu.conlog("consoleLogMediaQueue media items:")
        for mi in queue {
            dpu.conlog("  \(mi.title ?? "NoTitleFound")") }
    }

    func managedQueueSetPlayback(_ updq:[MPMediaItem]) {
        setQueueProcessingCommand("startPlayback", true)
        dpu.conlog("startPlayback sleepAfterPath reset")
        sleepAfterPath = ""
        consoleLogMediaQueue(updq)
        setDiggerQueue(updq, "playnow")
        clearQueueProcessingCommand("startPlayback")
    }

    func queueStartsWithCurrentlyPlayingSong(_ updq:[MPMediaItem]) -> Bool {
        let npi = nowPlayingInfo()
        if let url = updq[0].assetURL {
            if(npi.path == url.absoluteString) {
                return true } }
        return false
    }

    func hardPlayQueue(_ updq:[MPMediaItem]) {
        let logpre = "hardPlayQueue"
        var pos:TimeInterval = 0
        if(queueStartsWithCurrentlyPlayingSong(updq)) {
            pos = smpc.currentPlaybackTime }
        smpc.setQueue(with: miaToMIQD(updq))  //MPMusicPlayerController
        smpc.prepareToPlay(  //must call for queue updates to take effect
          completionHandler: { (err) in
              if let errobj = err {
                  self.dpu.conlog("\(logpre) prepareToPlay error: \(errobj)")
                  self.smpc.currentPlaybackTime = pos
                  self.smpc.play() }  //Prepares the queue if needed.
              else {
                  self.dpu.conlog("\(logpre) prepareToPlay success")
                  //playback state might be left over from previous song so play
                  //even if smpc.playbackState != MPMusicPlaybackState.playing
                  self.smpc.currentPlaybackTime = pos
                  self.smpc.play() } })
    }

    //An explicit call to play takes precedence over all other queue operations.
    func startPlayback(_ param:String) -> String {
        let updq = pathsToMIA(param, "startPlayback")
        var retval = "Error - Empty queue given, startPlayback call ignored"
        if(!updq.isEmpty) {
            if(dqpmmode == "queuestate") {
                managedQueueSetPlayback(updq) }
            else {  //"stateless"
                hardPlayQueue(updq) }
            retval = "prepared" }
        return retval
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
                song["pd"] = "iosqueue"
                writeUpdatedDBO(dj) }
            else {
                dpu.conlog("updPCFD song not found") } }
        else {
            dpu.conlog("updPCFD songs field not in dictionary") }
    }

    func bumpPlayCountForPath(_ path:String) {
        let jsonstr = self.dpu.readFile("digdat.json", "raw")
        if let jdat = jsonstr.data(using: .utf8) {
            do {
                if let dj = try JSONSerialization.jsonObject(
                     with:jdat, options: .mutableContainers) as? [String:Any] {
                    updatePlayCountFromDBO(path, dj) }
            } catch {
                dpu.conlog("bumpPlayCountForPath JSON err: \(error)") } }
    }

    func bumpPlayCountForMediaItem(_ mi:MPMediaItem) {
        let pathurl = mi.assetURL!
        let path = pathurl.absoluteString  //matches diggerhub path value
        bumpPlayCountForPath(path)
    }

    func playbackQueueNormalEnd(_ npp:String) -> Bool {
        //always note if the player just loaded the last song in the queue
        if(!lastQueuedSongPath.isEmpty && npp == lastQueuedSongPath) {
            lastQueuedSongPath = ""
            playingLastSongInQueue = true }
        if(queueResetFlag) {  //new queue needs to be loaded
            return false }    //not a normal end, song could be stale
        //if not resetting the queue, then either end or continue
        if(playingLastSongInQueue) {  //done with queued songs
            playingLastSongInQueue = false
            smpc.pause()              //don't overrun into some other music
            return true }
        return false  //queue has not finished, continue playing
    }

    //At the time of this call, smpc has just finished playing Song A.
    //    smpc queue    updated queue
    //        Song A        Song A
    //        Song B        Song P?
    //        Song C        Song Q?
    //The updated queue is different.  If the user switched views from album
    //to deck and then back to album while Song A was playing, the updated
    //queue could be equivalent, but normally not.  Since the smpc queue is
    //opaque, the updated queue is always treated as different.  The updated
    //queue may be empty (has only Song A in it).
    func playbackQueueReset() -> Bool {
        if(!queueResetFlag) {
            return false }
        queueResetFlag = false
        if let updq = getDiggerQueueState() {
            if(updq.count > 1) {  //have more than currently playing song
                let remainder = Array(updq[1 ..< updq.endIndex])
                setDiggerQueue(remainder, "playnow") }  //updates playcount
            else {  //no more digger songs to play
                dpu.conlog("playbackQueueReset empty queue, stopping.")
                smpc.stop() } }  //smpc.playbackState: paused
        else {
            dpu.conlog("playbackQueueReset no updq state, stopping.")
            smpc.stop() }
        return true
    }

    //This function is called repeatedly in quick succession for no good
    //reason.  smpc.nowPlayingItem may not be well defined, and values from
    //smpc may not be reliable or consistent across repeat calls.  The
    //system queue is a shared resource that may have been altered by any
    //other app between when Digger last set the queue and this function
    //call.  The last understood Digger queue state is saved, but may not
    //match the current system queue state.  The system queue is opaque, so
    //merge is not possible beyond the currently playing item.
    //
    //When this function is called, the previous song has finished playing
    //and the next song is either already playing or about to play.  If the
    //previous song was the last in the queue, and something is playing, it
    //is important to call pause as quickly as possible to avoid playing any
    //more milliseconds of whatever media the system found.  You very much
    //don't want to hear a half second of something else after finishing an
    //album, but stopping quickly is the best we can do here.  However if
    //the previous song was NOT the last song in the queue, then calling
    //pause or stop will cause a stutter restart of song playback as the
    //queue resets.  You want smooth transitions through the queue.
    func songJustChanged() {
        if(!qpcmd.isEmpty) {
            dpu.conlog("songJustChanged: ignoring call within \(qpcmd)")
            return }
        let npi = nowPlayingInfo()
        if(npi.path.isEmpty) {
            dpu.conlog("songJustChanged: ignoring call with empty npi.path")
            return }
        if(npi.path == songChangeNoticePath) {
            dpu.conlog("songJustChanged: dupe notice \(songChangeNoticePath)")
            return }
        songChangeNoticePath = npi.path  //avoid duplicate notices
        dpu.conlog("songJustChanged: \(npi.path) \(npi.title)")
        if(playbackQueueNormalEnd(songChangeNoticePath)) {
            dpu.conlog("songJustChanged: playback has ended.")
            return }
        if(playbackQueueReset()) {
            dpu.conlog("songJustChanged: playback queue reset.")
            return }
        dpu.conlog("songJustChanged: continuing playback")
        bumpPlayCountForPath(npi.path)
    }

    //Calling MPMediaPlayback.stop by some earlier reference supposedly
    //clears the queue.  If what is playing does not match what should be
    //playing, then calling stop is a good idea since we are about to play
    //something else.  Otherwise, it could lead to stutter where the current
    //song is interrupted and then restarted.
    func needToStartPlayback(_ updq:[MPMediaItem]) -> Bool {
        if(updq.isEmpty) {  //nothing to play next but already paused
            dpu.conlog("empty updq, already paused, no need to stop")
            return false }
        let npi = nowPlayingInfo()
        if(npi.path.isEmpty) {
            dpu.conlog("no path for now playing song. stopping playback")
            smpc.stop()  //nothing playing so may as well call stop
            return false }
        let fqp = updq[0].assetURL!.absoluteString   //first queue elem path
        if(npi.path != fqp) {
            dpu.conlog("npi.path \(npi.path) != fqp \(fqp). stopping playback")
            smpc.stop()  //switching to a different song
            return true }  //need to start playback
        if(getDiggerPlaybackState(npi) == "ended" || sleepWakeupNeeded) {
            sleepWakeupNeeded = false;
            dpu.conlog("playback ended due to sleep so deck being reset")
            smpc.stop()  //ready to reset the playback queue
            return true }  //need to start playback
        dpu.conlog("Playing current song, not calling stop")
        return false
    }

    func resetPlayerQueueAndStartPlayback(_ updq:[MPMediaItem]) {
        let n2sp = needToStartPlayback(updq)
        //smpc.nowPlayingItem = nil  ..doesn't help clear state, causes errors
        queueResetFlag = false
        //spqp = ""  do NOT reset or syncPQ will repeat the same queue
        let logpre = "resetPlayerQueueAndStartPlayback"
        if(updq.isEmpty) {
            dpu.conlog("\(logpre) updq empty, nothing to play")
            return }
        //logically the play count should get bumped after actually playing,
        //but with hiccups and false starts it's better just to do this first.
        bumpPlayCountForMediaItem(updq[0])
        dpu.conlog("\(logpre) calling smpc.setQueue")
        smpc.setQueue(with: miaToMIQD(updq))  //MPMusicPlayerController
        if(!n2sp) {
            dpu.conlog("\(logpre) already playing, skipping prepareToPlay")
            return }
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
                qsta = pathsToMIA(qtxt, "getDiggerQueueState digqstat.json") }
            if(qsta == nil) {
                dpu.conlog("digqstat.json retrieval failed.") } }
        return qsta
    }

    func pathsToMIA(_ paths:String, _ caller:String) -> [MPMediaItem] {
        var mia = [MPMediaItem]()
        var lqsp = ""  //last queued song path
        dpu.conlog("pathsToMIA \(caller)")
        sleepAfterPath = ""  //if no sleep marker song found then no sleep
        if let data = paths.data(using: .utf8) {
            do {
                if let psa = try JSONSerialization.jsonObject(
                     with: data,
                     options: .mutableContainers) as? [String] {
                    //might get a path with no corresponding local media item
                    for path in psa {
                        if let mi = mibp[path] {
                            lqsp = path
                            //dpu.conlog("pathsToMIA \(mi.title ?? "NoTitle")")
                            mia.append(mi) } } }
            } catch {
                dpu.conlog("pathsToMIA failed: \(error)")
            } }
        lastQueuedSongPath = lqsp
        return mia
    }

    func miaToMIQD(_ mia:[MPMediaItem]) -> MPMusicPlayerQueueDescriptor {
        let mic = MPMediaItemCollection(items:mia)
        let miqd = MPMusicPlayerMediaItemQueueDescriptor(itemCollection:mic)
        return miqd as MPMusicPlayerQueueDescriptor
    }

}
