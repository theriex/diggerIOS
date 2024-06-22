/*global app, jt, Android, console */
/*jslint browser, white, long, unordered */
/*global console */

//Server communications for IOS platform
app.svc = (function () {
    "use strict";

    var mgrs = {};  //general container for managers
    const clg = console.log;


    //Media Playback manager handles transport and playback calls
    mgrs.mp = (function () {
        const sleepstat = {};
        function deckPaths () {
            const playstate = app.deck.getPlaybackState(true, "paths");
            return JSON.stringify(playstate.qsi); }
        function notePlaybackState (stat, src) {
            if(sleepstat.cbf) {
                sleepstat.cbf(sleepstat.cmd);
                sleepstat.cbf = null; }
            if(stat && typeof stat === "object") {  //might be incomplete
                src = src || "unknown";
                stat.path = stat.path || "";
                app.player.dispatch("mob", "notePlaybackStatus", stat); } }
    return {
        requestStatusUpdate: function (/*contf*/) {
            if(!app.scr.stubbed("statusSync", null, notePlaybackState)) {
                mgrs.ios.call("statusSync", deckPaths(), function (stat) {
                    notePlaybackState(stat, "statusSync"); }); } },
        pause: function () {
            mgrs.ios.call("pausePlayback", "", function (stat) {
                notePlaybackState(stat, "pausePlayback"); }); },
        resume: function (unsleep) {
            unsleep = unsleep || "";
            mgrs.ios.call("resumePlayback", unsleep, function (stat) {
                notePlaybackState(stat, "resumePlayback"); }); },
        seek: function (ms) {
            mgrs.ios.call("seekToOffset", String(ms), function (stat) {
                notePlaybackState(stat, "seekToOffset"); }); },
        sleep: function (count, cmd, cbf) {
            sleepstat.count = count;  //rcv appropriately truncated|restored
            sleepstat.cmd = cmd;      //queue on next status update
            sleepstat.cbf = cbf; },
        playSong: function (path) {  //need entire queue, not just song
            if(!app.scr.stubbed("startPlayback", path, notePlaybackState)) {
                mgrs.ios.call("startPlayback", deckPaths(), function (stat) {
                    notePlaybackState(stat, "startPlayback"); }); } }
    };  //end mgrs.mp returned functions
    }());


    //Copy export manager handles playlist creation.  No file copying.
    mgrs.cpx = (function () {
    return {
        exportSongs: function (/*dat, statusfunc, contfunc, errfunc*/) {
            jt.log("svc.cpx.exportSongs not supported."); }
    };  //end mgrs.cpx returned functions
    }());


    //song database processing
    mgrs.sg = (function () {
        var dbstatdiv = "topdlgdiv";
        var apresloadcmd = "";
        function parseAudioSummary (dais) {
            jt.out(dbstatdiv, "Parsing audio summary...");
            dais = dais.filter((d) => d.title && d.path);  //title and path req
            dais.forEach(function (dai) {
                dai.artist = dai.artist || "Unknown";
                dai.album = dai.album || "Singles"; });
            return dais; }
        function setArtistFromPath (song) {
            const pes = song.path.split("/");
            song.ti = pes[pes.length - 1];
            if(pes.length >= 3) {
                song.ar = pes[pes.length - 3];
                song.ab = pes[pes.length - 2]; }
            else if(pes.length >= 2) {
                song.ar = pes[pes.length - 2]; } }
        function mergeAudioData (dais) {
            dais = parseAudioSummary(dais);
            jt.out(dbstatdiv, "Merging Digger data...");
            const dbo = mgrs.loc.getDigDat();
            Object.values(dbo.songs).forEach(function (s) {  //mark all deleted
                s.fq = s.fq || "N";
                if(!s.fq.startsWith("D")) {
                    s.fq = "D" + s.fq; } });
            dbo.songcount = dais.length;
            jt.out("countspan", String(dbo.songcount) + "&nbsp;songs");
            dais.forEach(function (dai) {
                var song = dbo.songs[dai.path];
                if(!song) {
                    dbo.songs[dai.path] = {};
                    song = dbo.songs[dai.path]; }
                song.path = dai.path;
                song.fq = song.fq || "N";
                if(song.fq.startsWith("D")) {
                    song.fq = song.fq.slice(1); }
                song.ti = dai.title;
                song.ar = dai.artist;
                song.ab = dai.album;
                song.genrejson = JSON.stringify(dai.genre);
                app.top.dispatch("dbc", "verifySong", song);
                if(!song.ar) {  //artist required for hub sync
                    setArtistFromPath(song); } }); }
    return {
        verifyDatabase: function (dbo) {
            var stat = app.top.dispatch("dbc", "verifyDatabase", dbo);
            dbo.version = mgrs.gen.plat("appversion");
            if(stat.verified) { return dbo; }
            jt.log("svc.db.verifyDatabase re-initializing dbo, received " +
                   JSON.stringify(stat));
            dbo = {version:mgrs.gen.plat("appversion"),
                   scanned:"",  //ISO latest walk of song files
                   songcount:0,
                   //songs are indexed by relative path off of musicPath e.g.
                   //"artistFolder/albumFolder/disc#?/songFile"
                   songs:{}};
            return dbo; },
        loadLibrary: function (procdivid, apresload) {
            dbstatdiv = procdivid || "topdlgdiv";
            apresloadcmd = apresload || "";
            mgrs.ios.call("requestMediaRead", null, function (dais) {
                mergeAudioData(dais);
                mgrs.loc.writeDigDat(function () {
                    jt.out(dbstatdiv, "");
                    app.top.markIgnoreSongs();
                    app.top.rebuildKeywords();
                    app.deck.songDataChanged("rebuildSongData");
                    if(apresloadcmd === "rebuild") {
                        app.player.next(); } }); }); }
    };  //end mgrs.sg returned functions
    }());


    //Local manager handles local environment interaction
    mgrs.loc = (function () {
        var config = null;
        var dbo = null;
        function synthesizeAlbumPaths(song) {
            //no relative paths to work with so can only reason from ar/ab
            //ar may vary (e.g. "main artist featuring whoever")
            var abs = [];
            Object.entries(dbo.songs).forEach(function ([p, s]) {
                if(song.ab === s.ab && (song.ar.startsWith(s.ar) ||
                                        s.ar.startsWith(song.ar))) {
                    abs.push(p); } });
            return abs; }
    return {
        getConfig: function () { return config; },
        getDigDat: function () { return dbo; },
        songs: function () { return mgrs.loc.getDigDat().songs; },
        writeConfig: function (cfg, contf/*, errf*/) {
            config = cfg;
            const pjson = JSON.stringify(cfg, null, 2);  //readable file
            mgrs.ios.call("writeConfig", pjson, contf); },
        getDatabase: function () { return dbo; },
        loadInitialData: function () {
            mgrs.ios.call("readConfig", null, function (cobj) {
                config = cobj || {};
                mgrs.ios.call("readDigDat", null, function (dobj) {
                    dbo = dobj || {};
                    config = config || {};  //default account set up in top.js
                    dbo = mgrs.sg.verifyDatabase(dbo);
                    //let rest of app know data is ready, then check library:
                    app.initialDataLoaded({"config":config, songdata:dbo});
                    if(!dbo.scanned) {
                        setTimeout(mgrs.sg.loadLibrary, 50); } }); }); },
        loadLibrary: function (procdivid) {
            mgrs.sg.loadLibrary(procdivid); },
        loadDigDat: function (cbf) {
            mgrs.ios.call("readDigDat", null, function (dobj) {
                dbo = dobj || {};
                dbo = mgrs.sg.verifyDatabase(dbo);
                cbf(dbo); }); },
        writeDigDat: function (cbf) {
            var stat = app.top.dispatch("dbc", "verifyDatabase", dbo);
            if(!stat.verified) {
                return jt.err("writeDigDat got bad data not writing: " +
                              JSON.stringify(stat)); }
            const datstr = JSON.stringify(dbo, null, 2);
            mgrs.ios.call("writeDigDat", datstr, cbf); },
        saveSongs: function (songs, contf/*, errf*/) {
            var upds = [];
            songs.forEach(function (song) {
                app.copyUpdatedSongData(dbo.songs[song.path], song);
                upds.push(dbo.songs[song.path]); });
            mgrs.loc.writeDigDat(function () {
                app.top.dispatch("srs", "syncToHub");  //sched sync
                if(contf) {
                    contf(upds); } }); },
        noteUpdatedState: function (/*label*/) {
            //If label === "deck" and the IOS platform needs to keep info
            //outside the app UI, this is the place to update that data
            return; },
        fetchSongs: function (contf/*, errf*/) {  //call stack as if web call
            setTimeout(function () { contf(dbo.songs); }, 50); },
        fetchAlbum: function (np, contf/*, errf*/) {
            const qdat = JSON.stringify({ar:np.ar, ab:np.ab});
            mgrs.ios.call("fetchAlbum", qdat, function (paths) {
                if(!paths || !paths.length) {  //should at least find curr song
                    clg("No album song paths returned, synthesizing");
                    paths = synthesizeAlbumPaths(np); }
                const songs = app.svc.songs();
                const abs = paths.map((path) => songs[path]);
                contf(np, abs); }); },
        writeSongs: function () {
            mgrs.loc.writeDigDat(function () {
                jt.log("svc.loc.writeSongs completed successfully"); }); },
        procSyncData: function (res) {
            app.player.logCurrentlyPlaying("svc.loc.procSyncData");
            const updacc = res[0];
            updacc.diggerVersion = mgrs.gen.plat("appversion");
            app.deck.dispatch("hsu", "noteSynchronizedAccount", updacc);
            app.deck.dispatch("hsu", "updateSynchronizedSongs", res.slice(1));
            return res; },
        hubSyncDat: function (data, contf, errf) {
            if(app.scr.stubbed("hubsync", null, contf, errf)) {
                return; }
            const param = {endpoint:"/hubsync", method:"POST", "data":data};
            mgrs.ios.call("hubSyncDat", JSON.stringify(param), function (res) {
                app.top.dispatch("srs", "hubStatInfo", "receiving...");
                res = mgrs.loc.procSyncData(res);
                contf(res); }, errf); },
        noteUpdatedSongData: function (updsong) {
            //on IOS the local database has already been updated, and
            //local memory is up to date.
            return dbo.songs[updsong.path]; },
        makeHubAcctCall: function (verb, endpoint, data, contf, errf) {
            const fname = "hubAcctCall" + endpoint;
            if(app.scr.stubbed(fname, null, contf, errf)) {
                return; }
            const param = {"endpoint":"/" + endpoint, method:verb,
                           "data":data || ""};  //Swift needs [String:String]
            mgrs.ios.call(fname, JSON.stringify(param), contf, errf); }
    };  //end mgrs.loc returned functions
    }());


    //ios manager handles calls between js and ios.  All calls are across
    //separate processes with no synchronous support, so calls are queued to
    //avoid unintuitive sequencing, deadlock, starvation etc.  Standard API
    //calls are expected to be nearly instant, but it is possible something
    //might take a few seconds when the app is first spinning up.  Reading
    //the song library is also typically very fast, but the app can handle
    //that taking longer without looking crashed.  Hub calls can take random
    //amounts of time so each call type gets its own queue.
    mgrs.ios = (function () {
        const qs = {"main":{q:[], cc:0, maxlag:10 * 1000},   //API calls
                    "srdr":{q:[], cc:0, maxlag:25 * 1000}};  //song lib read
        function qnameForFunc (iosFuncName) {
            if(iosFuncName === "requestMediaRead") {
                return "srdr"; }
            if(iosFuncName.startsWith("hub")) {
                if(!qs[iosFuncName]) {
                    qs[iosFuncName] = {q:[], cc:0, maxlag:30 * 1000}; }
                return iosFuncName; }
            return "main"; }
        function callIOS (queueName, mqo) {
            var logmsg;
            var param = mqo.pobj || "";
            if(param && typeof param === "object") {  //object or array
                param = JSON.stringify(param); }
            const msg = (queueName + ":" + mqo.msgnum + ":" + mqo.fname + ":" +
                         param);
            logmsg = msg;
            if(logmsg.length > 250) {
                logmsg = msg.slice(0, 150) + "..." + msg.slice(-50); }
            jt.log("callIOS: " + logmsg);
            window.webkit.messageHandlers.diggerMsgHandler.postMessage(msg); }
        function readSerializedObject(txt) {
            var oei = 1;
            var cnt = 1;
            var esc = false;
            var inq = false;
            var ch = "";
            while(txt && oei < txt.length && cnt) {
                ch = txt.charAt(oei);
                if(ch === "\\" && !esc) {
                    esc = true; }
                else if(!esc) {  //not an escaped char
                    if(ch === "\"") {
                        inq = !inq; }
                    else if(!inq) {  //not part of a string
                        if(ch === "{") { cnt += 1; }
                        if(ch === "}") { cnt -= 1; } } }
                oei += 1; }
            return txt.slice(0, oei); }
        function readSerializedObjectsCSV (txt) {
            var res = []; var obj;
            while(txt) {
                obj = readSerializedObject(txt);
                res.push(obj);
                txt = txt.slice(obj.length);
                if(txt.startsWith(",")) {
                    txt = txt.slice(1).trim(); } }
            return res; }
        function analyzeJSON (txt) {
            if(txt.startsWith("[") && txt.endsWith("]")) {
                jt.log("analyzeJSON txt is an array: '['...']'");
                const objs = readSerializedObjectsCSV(txt.slice(1, -1));
                jt.log("analyzeJSON found " + objs.length + " objs");
                objs.forEach(function (obj, idx) {
                    try {
                        JSON.parse(obj);
                    } catch(e) {
                        jt.log("obj[" + idx + "] " + e);
                        jt.log(obj); } }); } }
        function unhandledError (code, errtxt) {
            jt.log("Default error handler code: " + code +
                   ", errtxt: " + errtxt); }
        function logMessageText (mstr) {
            var logmsg = mstr;
            if(logmsg.length > 250) {
                logmsg = mstr.slice(0, 150) + "..." + mstr.slice(-50); }
            jt.log("ios.retv: " + logmsg); }
        function parseMessageText(mstr) {
            var res = "";
            logMessageText(mstr);
            const [qname, msgid, fname, ...msgtxt] = mstr.split(":");
            res = msgtxt.join(":");
            if(res && (res.startsWith("{") || res.startsWith("["))) {
                try {
                    res = JSON.parse(res);
                } catch(e) {
                    //dump full string to console so it can be debug viewed
                    jt.log("svc.ios.retv parse err " + e + " JSON res: " + res);
                    analyzeJSON(res);
                    res = "Error - parseMessageText failed " + e;
                } }
            return {"qname":qname, "msgid":msgid, "fname":fname, "res":res}; }
        function parseErrorText (rmo) {
            var errmsg = rmo.res;
            const emprefix = "Error - ";
            errmsg = errmsg.slice(emprefix.length);
            const codeprefix = "code: ";
            if(errmsg.indexOf(codeprefix) >= 0) {
                errmsg = errmsg.slice(codeprefix.length);
                rmo.errcode = parseInt(errmsg, 10) || 0;
                if(errmsg.indexOf(" ") >= 0) {
                    errmsg = errmsg.slice(errmsg.indexOf(" ")); } }
            else {
                rmo.errcode = 0; }
            rmo.errmsg = errmsg; }
        function handlePushMessage(rmo) {
            jt.log("handlePushMessage " + JSON.stringify(rmo));
            if(rmo.fname === "initMediaInfo") {
                mgrs.sg.loadLibrary(); } }  //go get the media
        function verifyQueueMatch(rmo) {
            if(rmo.qname === "iospush") {
                handlePushMessage(rmo);
                return false; }  //no corresponding queue
            if(!qs[rmo.qname].q.length) {
                jt.log("ios.retv no pending mssages in queue " + rmo.qname +
                       ". Ignoring.");
                return false; }
            if(qs[rmo.qname].q[0].fname !== rmo.fname) {
                jt.log("ios.retv queue " + rmo.qname + " expected fname " +
                       qs[rmo.qname].q[0].fname + " but received " +
                       rmo.fname + ". Ignoring.");
                return false; }
            const expmid = qs[rmo.qname].q[0].msgnum;
            const rcvmid = parseInt(rmo.msgid, 10);
            if(expmid !== rcvmid) {
                jt.log("ios.retv queue " + rmo.qname + " fname " + rmo.fname +
                       " expected msgid " + expmid + " but received " +
                       rcvmid + ". Continuing despite sequence error.");
                return true; }
            return true; }
    return {
        call: function (iosFuncName, paramObj, callback, errorf) {
            var cruft = null;
            if(app.scr.stubbed(iosFuncName, null, callback, errorf)) {
                return; }
            const qname = qnameForFunc(iosFuncName);
            paramObj = paramObj || "";
            qs[qname].cc += 1;
            qs[qname].q.push({fname:iosFuncName, pobj:paramObj, cbf:callback,
                              errf:errorf || unhandledError,
                              msgnum:qs[qname].cc, ts:Date.now()});
            if(qs[qname].q.length === 1) {
                callIOS(qname, qs[qname].q[0]); }
            else {  //multiple calls in queue, clear cruft and resume if needed
                while(Date.now - qs[qname].q[0].ts > qs[qname].maxlag) {
                    cruft = qs[qname].q.shift();
                    jt.log("ios call cleared crufty " + cruft.fname + " " +
                           jt.ellipsis(JSON.stringify(cruft.pobj), 300)); }
                if(cruft) {  //restart the queue
                    callIOS(qname, qs[qname].q[0]); } } },
        retv: function (mstr) {
            var mqo = null;
            const rmo = parseMessageText(mstr);
            if(!verifyQueueMatch(rmo)) {  //failure message logged
                return; }
            if(typeof rmo.res === "string" && rmo.res.startsWith("Error - ")) {
                parseErrorText(rmo); }
            mqo = qs[rmo.qname].q.shift();
            try {
                if(rmo.errmsg) {
                    mqo.errf(rmo.errcode, rmo.errmsg); }
                else {  //send a modifiable deep copy of results for use by cbf
                    mqo.cbf(JSON.parse(JSON.stringify(rmo.res))); }
            } catch(e) {
                jt.log("ios.retv " + rmo.qname + " " + rmo.msgid + " " +
                       rmo.fname + " " +(rmo.errmsg? "error" : "success") +
                       " callback failed: " + e + "  stack: " + e.stack);
            }
            if(qs[rmo.qname].q.length) {  //process next in queue
                callIOS(rmo.qname, qs[rmo.qname].q[0]); } }
    };  //end mgrs.ios returned functions
    }());


    //general manager is main interface for app logic
    mgrs.gen = (function () {
        var platconf = {
            hdm: "loc",   //host data manager is local
            musicPath: "fixed",  //can't change where music files are
            dbPath: "fixed",  //rating info is only kept in app files for now
            audsrc: "IOS",
            appversion: "",
            versioncode: ""};
    return {
        plat: function (key) { return platconf[key]; },
        updateMultipleSongs: function (songs, contf, errf) {
            return mgrs.loc.updateMultipleSongs(songs, contf, errf); },
        initialize: function () {  //don't block init of rest of modules
            setTimeout(mgrs.loc.loadInitialData, 50);
            mgrs.ios.call("getVersionCode", null, function (val) {
                platconf.versioncode = val; });
            mgrs.ios.call("getAppVersion", null, function (val) {
                platconf.appversion = val; }); },
        docContent: function (docurl, contf) {
            var fn = jt.dec(docurl);
            var sidx = fn.lastIndexOf("/");
            if(sidx >= 0) {
                fn = fn.slice(sidx + 1); }
            mgrs.ios.call("docContent", "docs/" + fn, contf); },
        makeHubAcctCall: function (verb, endpoint, data, contf, errf) {
            mgrs.loc.makeHubAcctCall(verb, endpoint, data, contf, errf); },
        writeConfig: function (cfg, contf, errf) {
            mgrs.loc.writeConfig(cfg, contf, errf); },
        fanGroupAction: function (data, contf/*, errf*/) {
            const param = {endpoint:"/fangrpact", method:"POST", "data":data};
            //caller writes updated account data
            mgrs.ios.call("hubfangrpact", JSON.stringify(param), contf); },
        fanCollab: function (data, contf/*, errf*/) {
            const param = {endpoint:"/fancollab", method:"POST", "data":data};
            mgrs.ios.call("hubfanclab", JSON.stringify(param), function (res) {
                res = mgrs.loc.procSyncData(res);
                contf(res); }); },
        fanMessage: function (data, contf/*, errf*/) {
            if(app.scr.stubbed("hubAcctCallmessages", data, contf)) {
                return; }
            const param = {endpoint:"/fanmsg", method:"POST", "data":data};
            mgrs.ios.call("hubfanmsg", JSON.stringify(param), contf); },
        copyToClipboard: function (txt, contf/*, errf*/) {
            mgrs.ios.call("copyToClipboard", txt, contf); },
        tlasupp: function (act) {
            const unsupp = {
                "updversionnote":"App Store updates after server",
                "ignorefldrsbutton":"No music file folders on IOS",
                "readfilesbutton":"All media queried at app startup"};
            return (!act.id || !unsupp[act.id]); }
    };  //end mgrs.gen returned functions
    }());

return {
    init: function () { mgrs.gen.initialize(); },
    plat: function (key) { return mgrs.gen.plat(key); },
    iosReturn: function (jsonstr) { mgrs.ios.retv(jsonstr); },
    loadDigDat: function (cbf) { mgrs.loc.loadDigDat(cbf); },
    songs: function () { return mgrs.loc.getDigDat().songs; },
    fetchSongs: function (cf, ef) { mgrs.loc.fetchSongs(cf, ef); },
    fetchAlbum: function (np, cf, ef) { mgrs.loc.fetchAlbum(np, cf, ef); },
    saveSongs: function (songs, cf, ef) { mgrs.loc.saveSongs(songs, cf, ef); },
    noteUpdatedState: function (label) { mgrs.loc.noteUpdatedState(label); },
    urlOpenSupp: function () { return false; }, //links break webview
    docContent: function (du, cf) { mgrs.gen.docContent(du, cf); },
    topLibActionSupported: function (a) { return mgrs.gen.tlasupp(a); },
    writeConfig: function (cfg, cf, ef) { mgrs.gen.writeConfig(cfg, cf, ef); },
    dispatch: function (mgrname, fname, ...args) {
        try {
            return mgrs[mgrname][fname].apply(app.svc, args);
        } catch(e) {
            console.log("svc.dispatch: " + mgrname + "." + fname + " " + e +
                        " " + new Error("stack trace").stack);
        } }
};  //end of returned functions
}());
