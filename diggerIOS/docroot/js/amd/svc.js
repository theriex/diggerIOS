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
        playSong: function (path) {
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
                        app.player.next(); } }); }, "srdr"); }
    };  //end mgrs.sg returned functions
    }());


    //Local manager handles local environment interaction
    mgrs.loc = (function () {
        var config = null;
        var dbo = null;
    return {
        getConfig: function () { return config; },
        getDigDat: function () { return dbo; },
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
        fetchAlbum: function (/*contf, errf*/) {
            throw("Can't infer song order from opaque path so this will need another query..."); }
    };  //end mgrs.loc returned functions
    }());


    //ios manager handles calls between js and ios.  All calls are across
    //separate processes with no synchronous support, so queue calls to avoid
    //unintuitive sequencing, deadlock, starvation etc.
    mgrs.ios = (function () {
        const qs = {"main":{q:[], cc:0, maxlag:10 * 1000},
                    "srdr":{q:[], cc:0, maxlag:25 * 1000},
                    "hubc":{q:[], cc:0, maxlag:30 * 1000}};
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
        call: function (iosFuncName, paramObj, callback, qname) {
            var cruft = null;
            qname = qname || "main";
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
            const msgid = mstr.slice(0, mstr.indexOf(":"));
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
            const logtxt = (qname + " " + msgid + " " + fname + " " +
                            jt.ellipsis(mstr, 300));
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
        initialize: function () {  //don't block init of rest of modules
            setTimeout(mgrs.loc.loadInitialData, 50);
            mgrs.ios.call("getVersionCode", null, function (val) {
                platconf.versioncode = val; });
            mgrs.ios.call("getAppVersion", null, function (val) {
                platconf.appversion = val; }); }
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
    dispatch: function (mgrname, fname, ...args) {
        try {
            return mgrs[mgrname][fname].apply(app.svc, args);
        } catch(e) {
            console.log("top.dispatch: " + mgrname + "." + fname + " " + e +
                        " " + new Error("stack trace").stack);
        } }
};  //end of returned functions
}());
