import AppKit
import ImageIO

struct Parameter: Codable { let key: String; let label: String; let `default`: String; let kind: String }
struct Action: Codable {
    let id: String; let title: String; let families: [String]; let mode: String
    let fields: [Parameter]; let note: String; let batch: Bool
}
func family(_ url: URL) -> String {
    let ext = url.pathExtension.lowercased()
    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !["pages","numbers","key"].contains(ext) { return "folder" }
    let groups: [(String,[String])] = [
        ("image", "jpg jpeg png webp avif heic heif tif tiff gif bmp ico icns psd jp2".components(separatedBy: " ")),
        ("video", "mp4 m4v mov mkv webm avi wmv mpg mpeg ts mts m2ts flv 3gp".components(separatedBy: " ")),
        ("audio", "mp3 m4a aac wav flac ogg opus aiff aif wma caf amr".components(separatedBy: " ")),
        ("pdf", ["pdf"]), ("document", "doc docx odt rtf txt html htm md markdown epub pages".components(separatedBy: " ")),
        ("slides", ["ppt", "pptx", "odp", "key"]), ("sheet", ["xlsx","xls","ods","csv","tsv","json","numbers"]),
        ("subtitle", ["srt","vtt"]), ("archive", ["zip","tar","gz","tgz","7z","rar","bz2","xz"])]
    return groups.first { $0.1.contains(ext) }?.0 ?? "file"
}
func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
    let urls=(pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    if !urls.isEmpty {return urls}
    return (pasteboard.propertyList(forType:NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] ?? []).map{URL(fileURLWithPath:$0)}
}
final class Model {
    static let shared = Model()
    var actions: [Action] = []
    var busyChanged: ((Bool)->Void)?
    var busy = false { didSet { busyChanged?(busy) } }
    var process: Process?
    var cancelled = false
    var results: [URL] = []
    var status: ((String) -> Void)?
    var completion: (([URL],String?) -> Void)?
    var favorites: [String] {
        get { UserDefaults.standard.stringArray(forKey: "favorites") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "favorites") }
    }
    init() {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Engine/actions.json"), let data = try? Data(contentsOf: url) {
            actions = (try? JSONDecoder().decode([Action].self, from: data)) ?? []
        }
    }
    func available(_ urls: [URL], mode: String? = nil) -> [Action] {
        actions.filter { a in
            (mode == nil || a.mode == mode) && !urls.isEmpty && urls.allSatisfy { a.families.contains("any") || a.families.contains(family($0)) }
        }.sorted { a,b in
            let af=favorites.contains(a.id), bf=favorites.contains(b.id)
            return af != bf ? af : false
        }
    }
    func run(_ action: Action, urls: [URL], params: [String:String], destinations: [String:String] = [:], recordResults: Bool = true, done: (([URL],String?) -> Void)? = nil) {
        guard !busy else { return }
        busy=true;cancelled=false;status?(action.title+"…")
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("orbita-request-\(UUID().uuidString)")
        let callback=done ?? completion
        let request:[String:Any] = ["action":action.id,"paths":urls.map(\.path),"params":params,"destinations":destinations]
        do {
            try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try JSONSerialization.data(withJSONObject:request).write(to:temp.appendingPathComponent("request.json"),options:.atomic)
            guard let resources=Bundle.main.resourceURL else {throw NSError(domain:"Orbita",code:1,userInfo:[NSLocalizedDescriptionKey:"Risorse dell’app non disponibili."])}
            let output=temp.appendingPathComponent("response.json"),errorFile=temp.appendingPathComponent("error.txt")
            try Data().write(to:output);try Data().write(to:errorFile)
            let out=try FileHandle(forWritingTo:output),err=try FileHandle(forWritingTo:errorFile)
            let process=Process();self.process=process
            process.executableURL=resources.appendingPathComponent(runtimeDirectory+"/python/bin/python3")
            process.arguments=["-B","-I",resources.appendingPathComponent("Engine/runner.py").path,temp.appendingPathComponent("request.json").path]
            process.environment=ProcessInfo.processInfo.environment.merging(["PYTHONDONTWRITEBYTECODE":"1","PYTHONNOUSERSITE":"1"]) {_,new in new}
            process.standardOutput=out;process.standardError=err
            do {try process.run();busyChanged?(true)} catch {try? out.close();try? err.close();throw error}
            DispatchQueue.global(qos:.userInitiated).async {
                process.waitUntilExit();try? out.close();try? err.close()
                var message:String?;var results:[URL]=[]
                do {
                    guard let json=try JSONSerialization.jsonObject(with:Data(contentsOf:output)) as? [String:Any],let ok=json["ok"] as? Bool else {
                        throw NSError(domain:"Orbita",code:2,userInfo:[NSLocalizedDescriptionKey:"Risposta del motore non valida."])
                    }
                    results=(json["outputs"] as? [String] ?? []).map{URL(fileURLWithPath:$0)}
                    if !ok || process.terminationStatus != 0 {message=json["error"] as? String ?? "Conversione non completata."}
                } catch {
                    let details=((try? String(contentsOf:errorFile)) ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
                    message=details.isEmpty ? "Il motore non ha restituito un risultato. "+error.localizedDescription:String(details.suffix(1800))
                }
                try? FileManager.default.removeItem(at:temp)
                DispatchQueue.main.async {
                    self.process=nil;self.busy=false
                    if self.cancelled {message="Annullato. Gli eventuali risultati già creati sono conservati."}
                    if recordResults && !results.isEmpty {self.results=results}
                    self.status?(message == nil ? "\(results.count) file creati" : "Operazione interrotta")
                    callback?(results,message)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at:temp);process=nil;busy=false
            status?("Impossibile avviare l’operazione")
            callback?([],error.localizedDescription)
        }
    }
    func cancel() {
        guard let process=process,process.isRunning else {return}
        cancelled=true;process.terminate()
    }
}

func requiresAppleExport(_ action:Action)->Bool { ["document.","slides.","sheet."].contains { action.id.hasPrefix($0) } }

// Choose the runtime that matches the running executable slice.
var runtimeDirectory:String {
#if arch(arm64)
    return "Runtime-arm64"
#else
    return "Runtime"
#endif
}
