// Kopplung und Laden des Uhr-Pakets über den eigenen Worker. Läuft nur, solange das Handy verbunden ist; das Paket
// liegt danach im Speicher der Uhr, unterwegs braucht das Datenfeld kein Handy.
//
// Ablauf: POST /v1/watch/hello (Geräteschlüssel) → Code anzeigen, bis die App gekoppelt hat →
// GET /v1/watch/index → neueste Route in Teilen laden (GET /v1/watch/chunk) → speichern.

import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.PersistedContent;
import Toybox.StringUtil;
import Toybox.System;

// Antwort von makeWebRequest (JSON wird zum Dictionary).
typedef Response as Null or ByteArray or Dictionary or String or PersistedContent.Iterator;

class WatchSync {
    // Anzeige, solange kein Paket da ist (bzw. Stand des Ladens).
    public var status as String = "Wird vorbereitet …";
    // Kopplungscode für die App (sechs Zeichen), sonst null.
    public var code as String? = null;
    public var routePackage as WatchPackage? = null;

    private var _busy as Boolean = false;
    // Zeitpunkt der letzten vollständigen Abfrage (null: noch keine). Danach fragt die Uhr wieder nach – ohne Route
    // alle 30 s, mit Route alle 2 min, aber nur solange die Aktivität nicht läuft.
    private var _checkedAt as Number? = null;
    private var _lastTry as Number = -100000;
    private var _routeId as String = "";
    private var _updatedAt as String = "";
    private var _chunkCount as Number = 0;
    private var _chunks as Array<String> = [];

    public function initialize() {
        load();
    }

    // Gespeichertes Paket laden (beim Start und nach dem Herunterladen).
    public function load() as Void {
        var count = Storage.getValue("chunks");
        if (!(count instanceof Number) || count <= 0) {
            return;
        }
        var data = []b;
        for (var i = 0; i < count; i++) {
            var part = Storage.getValue("chunk" + i);
            if (!(part instanceof String)) {
                return;
            }
            data.addAll(decode(part));
        }
        try {
            routePackage = new WatchPackage(data);
            status = "";
        } catch (error) {
            routePackage = null;
            status = "Route beschädigt – neu laden";
        }
    }

    private function decode(text as String) as ByteArray {
        return StringUtil.convertEncodedString(text, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
        }) as ByteArray;
    }

    // Adresse aus den Einstellungen, wenn dort eine gültige steht, sonst die beim Build eingesetzte.
    private function workerUrl() as String? {
        var setting = Properties.getValue("workerUrl");
        if (isUrl(setting)) {
            return setting as String;
        }
        return isUrl(WORKER_URL) ? WORKER_URL : null;
    }

    private function isUrl(value as Object?) as Boolean {
        if (!(value instanceof String)) {
            return false;
        }
        return value.length() >= 8 && value.find("__") == null && value.find("http") == 0;
    }

    // Geräteschlüssel: eindeutige Kennung der Uhr für diese App (sonst einmal zufällig erzeugt).
    private function deviceKey() as String {
        var stored = Storage.getValue("device");
        if (stored instanceof String) {
            return stored;
        }
        var id = System.getDeviceSettings().uniqueIdentifier;
        var key = id != null ? id : "";
        while (key.length() < 32) {
            key += Math.rand().format("%08x");
        }
        Storage.setValue("device", key);
        return key;
    }

    // Jede Sekunde aus compute(): fragt höchstens alle 20 s beim Worker nach, solange etwas zu tun ist. Läuft die
    // Aktivität (running), bleibt eine geladene Route unverändert.
    public function tick(running as Boolean) as Void {
        if (_busy) {
            return;
        }
        var checkedAt = _checkedAt;
        if (checkedAt != null) {
            if (routePackage != null && running) {
                return;
            }
            var wait = routePackage == null ? 30000 : 120000;
            if (System.getTimer() - checkedAt < wait) {
                return;
            }
        }
        if (workerUrl() == null) {
            status = "Worker-Adresse fehlt";
            return;
        }
        if (!System.getDeviceSettings().phoneConnected) {
            if (routePackage == null) {
                status = "Handy in die Nähe bringen";
            }
            return;
        }
        var now = System.getTimer();
        if (now - _lastTry < 20000) {
            return;
        }
        _lastTry = now;
        hello();
    }

    private function request(
        path as String,
        params as Dictionary<Object, Object>?,
        post as Boolean,
        callback as Method(responseCode as Number, data as Response) as Void
    ) as Void {
        _busy = true;
        var options = {
            :method => post ? Communications.HTTP_REQUEST_METHOD_POST : Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
        };
        if (post) {
            options[:headers] = { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON };
        }
        Communications.makeWebRequest((workerUrl() as String) + path, params, options, callback);
    }

    private function hello() as Void {
        request("/v1/watch/hello", { "device" => deviceKey() }, true, method(:onHello));
    }

    public function onHello(responseCode as Number, data as Response) as Void {
        _busy = false;
        if (responseCode != 200 || !(data instanceof Dictionary)) {
            status = "Worker nicht erreichbar (" + responseCode + ")";
            return;
        }
        if (data["paired"] == true) {
            code = null;
            request("/v1/watch/index", { "device" => deviceKey() }, false, method(:onIndex));
            return;
        }
        var value = data["code"];
        if (value instanceof String) {
            code = value;
            status = "In AIronLudi koppeln";
        }
    }

    public function onIndex(responseCode as Number, data as Response) as Void {
        _busy = false;
        if (responseCode != 200 || !(data instanceof Dictionary)) {
            status = "Routen nicht abrufbar (" + responseCode + ")";
            return;
        }
        var routes = data["routes"];
        if (!(routes instanceof Array) || routes.size() == 0) {
            _checkedAt = System.getTimer();
            if (routePackage == null) {
                status = "Keine Route.\nIn AIronLudi „Karte auf die Uhr“ tippen";
            }
            return;
        }
        var newest = routes[0] as Dictionary;
        var id = newest["id"] as String;
        var updatedAt = newest["updatedAt"] as String;
        if (id.equals(Storage.getValue("routeId")) && updatedAt.equals(Storage.getValue("updatedAt"))) {
            _checkedAt = System.getTimer();
            return;
        }
        _routeId = id;
        _updatedAt = updatedAt;
        _chunkCount = newest["chunks"] as Number;
        _chunks = [];
        fetchChunk();
    }

    private function fetchChunk() as Void {
        status = "Route wird geladen " + (_chunks.size() + 1) + "/" + _chunkCount;
        request(
            "/v1/watch/chunk",
            { "device" => deviceKey(), "route" => _routeId, "n" => _chunks.size() },
            false,
            method(:onChunk)
        );
    }

    public function onChunk(responseCode as Number, data as Response) as Void {
        _busy = false;
        if (responseCode != 200 || !(data instanceof Dictionary) || !(data["data"] instanceof String)) {
            status = "Laden unterbrochen (" + responseCode + ")";
            return;
        }
        _chunks.add(data["data"] as String);
        if (_chunks.size() < _chunkCount) {
            fetchChunk();
            return;
        }
        for (var i = 0; i < _chunks.size(); i++) {
            Storage.setValue("chunk" + i, _chunks[i]);
        }
        Storage.setValue("chunks", _chunks.size());
        Storage.setValue("routeId", _routeId);
        Storage.setValue("updatedAt", _updatedAt);
        _chunks = [];
        _checkedAt = System.getTimer();
        load();
    }
}
