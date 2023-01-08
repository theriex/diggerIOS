/*global app, jt, Android, console */
/*jslint browser, white, long, unordered */

//Server communications for IOS platform
app.svc = (function () {
    "use strict";

    var mgrs = {};  //general container for managers


    //Media Playback manager handles transport and playback calls
    mgrs.mp = (function () {
        function deckPaths () {
            var qm = app.deck.stableDeckLength(); var paths;
            qm = app.player.dispatch("slp", "limitToSleepQueueMax", qm);
            const dst = app.deck.getState(qm);  //songs currently on deck
            if(dst.disp === "album") {
                paths = dst.disp.info.songs.map((s) => s.path); }
            else {  //send currently playing song as first path in list
                paths = dst.det.map((s) => s.path);
                paths.unshift(app.player.song().path); }
            return JSON.stringify(paths); }
        function notePlaybackState (stat) {
            app.player.dispatch("mob", "notePlaybackStatus", stat); }
    return {
        requestStatusUpdate: function (/*contf*/) {
            mgrs.ios.call("statusSync", deckPaths(), notePlaybackState); },
        pause: function () {
            mgrs.ios.call("pausePlayback", "", notePlaybackState); },
        resume: function () {
            mgrs.ios.call("resumePlayback", "", notePlaybackState); },
        seek: function (ms) {
            mgrs.ios.call("seekToOffset", String(ms), notePlaybackState); },
        playSong: function (/*path*/) {  //need entire queue, not just song
            mgrs.ios.call("startPlayback", deckPaths(), notePlaybackState); }
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
                app.top.dispatch("dbc", "verifySong", song);
                if(!song.ar) {  //artist required for hub sync
                    setArtistFromPath(song); } }); }
    return {
        verifyDatabase: function (dbo) {
            var stat = app.top.dispatch("dbc", "verifyDatabase", dbo);
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
                    app.deck.update("rebuildSongData");
                    if(apresloadcmd === "rebuild") {
                        app.player.next(); } }); }); }
    };  //end mgrs.sg returned functions
    }());


    //Local manager handles local environment interaction
    mgrs.loc = (function () {
        var config = null;
        var dbo = null;
    return {
        getConfig: function () { return config; },
        getDigDat: function () { return dbo; },
        songs: function () { return mgrs.loc.getDigDat().songs; },
        loadInitialData: function () {
            mgrs.ios.call("readConfig", null, function (cobj) {
                config = cobj || {};
                mgrs.ios.call("readDigDat", null, function (dobj) {
                    dbo = dobj || {};
                    config = config || {};  //default account set up in top.js
                    dbo = mgrs.sg.verifyDatabase(dbo);
                    //let rest of app know data is ready, then check library:
                    const startdata = {"config":config, songdata:dbo};
                    const uims = ["top",      //display login name
                                  "filter"];  //show settings, app.deck.update
                    uims.forEach(function (uim) {
                        app[uim].initialDataLoaded(startdata); });
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
        writeConfig: function (cfg, contf/*, errf*/) {
            config = cfg;
            const pjson = JSON.stringify(cfg, null, 2);  //readable file
            mgrs.ios.call("writeConfig", pjson, contf); },
        updateSong: function (song, contf/*, errf*/) {
            app.copyUpdatedSongData(song, dbo.songs[song.path]);
            mgrs.loc.writeDigDat(function () {
                jt.out("modindspan", "");  //turn off indicator light
                app.top.dispatch("srs", "syncToHub");  //sched sync
                if(contf) {
                    contf(dbo.songs[song.path]); } }); },
        noteUpdatedState: function (/*label*/) {
            //If label === "deck" and the IOS platform needs to keep info
            //outside the app UI, this is the place to update that data
            return; },
        fetchSongs: function (contf/*, errf*/) {  //call stack as if web call
            setTimeout(function () { contf(dbo.songs); }, 50); },
        fetchAlbum: function (contf/*, errf*/) {
            const ps = app.player.song();  //deck already checked not null
            mgrs.ios.call("fetchAlbum", JSON.stringify(ps), function (paths) {
                const songs = app.svc.songs();
                contf(paths.map((path) => songs[path])); }); },
        procSyncData: function (res) {
            app.player.logCurrentlyPlaying("svc.loc.procSyncData");
            const updacc = res[0];
            updacc.diggerVersion = mgrs.gen.plat().appversion;
            app.deck.dispatch("hsu", "noteSynchronizedAccount", updacc);
            app.deck.dispatch("hsu", "updateSynchronizedSongs", res.slice(1));
            return res; },
        hubSyncDat: function (data, contf/*, errf*/) {
            const param = {endpoint:"/hubsync", method:"POST", "data":data};
            mgrs.ios.call("hubSyncDat", JSON.stringify(param), function (res) {
                res = mgrs.loc.procSyncData(res);
                contf(res); }); },
        noteUpdatedSongData: function (/*updsong*/) {
            //on IOS the local database has already been updated, and
            //local memory is up to date.
            return; },
        makeHubAcctCall: function (verb, endpoint, data, contf/*, errf*/) {
            const param = {"endpoint":"/" + endpoint, method:verb, "data":data};
            const fname = "hubAcctCall" + endpoint;
            mgrs.ios.call(fname, JSON.stringify(param), contf); }
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
        function analyzeJSON (txt) {
            if(txt.startsWith("[") && txt.endsWith("]")) {
                jt.log("txt is '['...']'");
                txt = txt.slice(1, -1);
                const items = txt.split("},{");
                jt.log("},{ split yields " + items.length + " items");
                items.forEach(function (item, idx) {
                    if(!item.startsWith("{")) { item = "{" + item; }
                    if(!item.endsWith("}")) { item = item + "}"; }
                    try {
                        JSON.parse(item);
                    } catch(e) {
                        jt.log("item[" + idx + "] " + e);
                        jt.log(item); } }); } }
    return {
        call: function (iosFuncName, paramObj, callback) {
            var cruft = null;
            const qname = qnameForFunc(iosFuncName);
            paramObj = paramObj || "";
            qs[qname].cc += 1;
            qs[qname].q.push({fname:iosFuncName, pobj:paramObj, cbf:callback,
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
            var result = ""; var logmsg = mstr;
            if(logmsg.length > 250) {
                logmsg = mstr.slice(0, 150) + "..." + mstr.slice(-50); }
            jt.log("ios.retv: " + logmsg);
            const qname = mstr.slice(0, mstr.indexOf(":"));
            mstr = mstr.slice(mstr.indexOf(":") + 1);
            //const msgid = mstr.slice(0, mstr.indexOf(":"));
            mstr = mstr.slice(mstr.indexOf(":") + 1);
            const fname = mstr.slice(0, mstr.indexOf(":"));
            mstr = mstr.slice(mstr.indexOf(":") + 1);
            result = mstr;
            if(mstr && (mstr.startsWith("{") || mstr.startsWith("["))) {
                try {
                    result = JSON.parse(mstr);
                } catch(e) {
                    analyzeJSON(mstr);
                    jt.log("svc.ios.retv err " + e + " JSON text: " +
                           jt.ellipsis(mstr, 300) + " ... " +
                           mstr.slice(-300));
                    mstr = "Error - JSON parse failed " + e;
                } }
            if(!qs[qname].q.length) {
                jt.log("ios.retv ignoring spurious return."); }
            else if(qs[qname].q[0].fname === fname) {  //return value for call
                const mqo = qs[qname].q.shift();
                if(!mstr.startsWith("Error -")) {
                    try {
                        mqo.cbf(result);
                    } catch(e) {
                        jt.log("svc.ios.return callback failed: " + e);
                    } }
                if(qs[qname].q.length) {  //process next in queue
                    callIOS(qname, qs[qname].q[0]); } }
            else {  //mismatched return for current queue (previous timeout)
                jt.log("iosReturn no match current queue entry, ignoring."); } }
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
        updateMultipleSongs: function (/*updss, contf, errf*/) {
            jt.err("svc.gen.updateMultipleSongs is web only"); },
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
            const param = {endpoint:"/fanmsg", method:"POST", "data":data};
            mgrs.ios.call("hubfanmsg", JSON.stringify(param), contf); },
        copyToClipboard: function (txt, contf/*, errf*/) {
            mgrs.ios.call("copyToClipboard", txt, contf); }
    };  //end mgrs.gen returned functions
    }());

return {
    init: function () { mgrs.gen.initialize(); },
    plat: function (key) { return mgrs.gen.plat(key); },
    iosReturn: function (jsonstr) { mgrs.ios.retv(jsonstr); },
    loadDigDat: function (cbf) { mgrs.loc.loadDigDat(cbf); },
    songs: function () { return mgrs.loc.getDigDat().songs; },
    fetchSongs: function (cf, ef) { mgrs.loc.fetchSongs(cf, ef); },
    fetchAlbum: function (cf, ef) { mgrs.loc.fetchAlbum(cf, ef); },
    updateSong: function (song, cf, ef) { mgrs.loc.updateSong(song, cf, ef); },
    noteUpdatedState: function (label) { mgrs.loc.noteUpdatedState(label); },
    urlOpenSupp: function () { return false; }, //links break webview
    docContent: function (du, cf) { mgrs.gen.docContent(du, cf); },
    writeConfig: function (cfg, cf, ef) { mgrs.gen.writeConfig(cfg, cf, ef); },
    dispatch: function (mgrname, fname, ...args) {
        try {
            return mgrs[mgrname][fname].apply(app.svc, args);
        } catch(e) {
            console.log("top.dispatch: " + mgrname + "." + fname + " " + e +
                        " " + new Error("stack trace").stack);
        } }
};  //end of returned functions
}());
