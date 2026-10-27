import AppKit
import CryptoKit

final class Shelf:NSObject,NSTableViewDataSource,NSTableViewDelegate {
    let window:NSPanel
    let table=NSTableView()
    var urls:[URL]=[]
    var open:(([URL])->Void)?
    override init() {
        window=NSPanel(contentRect:NSRect(x:0,y:0,width:420,height:300),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
        super.init();window.title="Orbita · Scaffale";window.level = .floating;window.isReleasedWhenClosed=false;window.center()
        let root=FileDropView(frame:NSRect(x:0,y:0,width:420,height:300));root.receive={ [weak self] in self?.add($0) };root.autoresizingMask=[.width,.height];window.contentView=root
        let scroll=NSScrollView(frame:NSRect(x:10,y:50,width:400,height:240));scroll.autoresizingMask=[.width,.height];scroll.hasVerticalScroller=true
        let col=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("file"));col.width=380;table.addTableColumn(col);table.headerView=nil;table.rowHeight=30;table.allowsMultipleSelection=true;table.dataSource=self;table.delegate=self;table.target=self;table.doubleAction=#selector(show);table.setDraggingSourceOperationMask(.copy,forLocal:false);scroll.documentView=table;root.addSubview(scroll)
        let show=NSButton(title:"Apri in Studio",target:self,action:#selector(show));show.frame=NSRect(x:10,y:10,width:160,height:30);root.addSubview(show)
        let clear=NSButton(title:"Svuota scaffale",target:self,action:#selector(clear));clear.frame=NSRect(x:220,y:10,width:180,height:30);root.addSubview(clear)
    }
    func add(_ new:[URL]) {for url in new where !urls.contains(url) {urls.append(url)};table.reloadData();window.orderFrontRegardless()}
    func numberOfRows(in tableView:NSTableView)->Int {urls.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {NSTextField(labelWithString:urls[row].lastPathComponent)}
    func tableView(_ tableView:NSTableView,pasteboardWriterForRow row:Int)->NSPasteboardWriting? {urls[row] as NSURL}
    @objc func show() {let selected=table.selectedRowIndexes.map{urls[$0]};open?(selected.isEmpty ? urls:selected)}
    @objc func clear() {urls=[];table.reloadData()}
}
struct FileStamp:Equatable {
    let size:Int
    let modified:Date
}
struct StableFileTracker {
    private var samples:[String:(FileStamp,Date)]=[:]
    mutating func ready(_ key:String,stamp:FileStamp,now:Date,delay:TimeInterval=4)->Bool {
        if let old=samples[key],old.0==stamp {return now.timeIntervalSince(old.1)>=delay}
        samples[key]=(stamp,now);return false
    }
    mutating func remove(_ key:String) {samples.removeValue(forKey:key)}
}
struct Watch:Codable {var folder:String;var destination:String;var action:String
    var key:String {folder+"|"+destination+"|"+action}
}
final class Watcher {
    var watches:[Watch]=[]
    var known:[String:FileStamp]=[:]
    var tracker=StableFileTracker()
    var timer:Timer?
    var report:((String)->Void)?
    init() {
        if let data=UserDefaults.standard.data(forKey:"watches") {watches=(try? JSONDecoder().decode([Watch].self,from:data)) ?? []}
        for watch in watches {baseline(watch)}
        timer=Timer.scheduledTimer(withTimeInterval:4,repeats:true) { [weak self] _ in self?.scan() }
    }
    func files(_ watch:Watch)->[URL] {(try? FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:watch.folder),includingPropertiesForKeys:[.isRegularFileKey,.fileSizeKey,.contentModificationDateKey],options:[.skipsHiddenFiles])) ?? []}
    func stamp(_ url:URL)->FileStamp? {
        guard let v=try? url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey,.contentModificationDateKey]),v.isRegularFile==true,let date=v.contentModificationDate else{return nil}
        return FileStamp(size:v.fileSize ?? 0,modified:date)
    }
    func baseline(_ watch:Watch) {for url in files(watch) {if let value=stamp(url) {known[watch.key+"|"+url.path]=value}}}
    func save() {UserDefaults.standard.set(try? JSONEncoder().encode(watches),forKey:"watches")}
    func add(_ watch:Watch) {guard !watches.contains(where:{$0.key==watch.key}) else{return};watches.append(watch);baseline(watch);save()}
    func clear() {watches=[];tracker=StableFileTracker();known=[:];save()}
    func scan() {
        guard !Model.shared.busy else{return}
        for watch in watches {
            guard let action=Model.shared.actions.first(where:{$0.id==watch.action}) else{continue}
            for url in files(watch) {
                let key=watch.key+"|"+url.path
                guard let value=stamp(url),known[key] != value,action.families.contains(family(url)) else{continue}
                guard tracker.ready(key,stamp:value,now:Date()) else{continue}
                known[key]=value;tracker.remove(key)
                Model.shared.run(action,urls:[url],params:[:]) { outputs,error in
                    for output in outputs {if let value=self.stamp(output) {for w in self.watches {self.known[w.key+"|"+output.path]=value}}}
                    if let error=error {self.report?("Cartella automatica: "+error);return}
                    do {
                        var moved:[URL]=[]
                        for output in outputs {
                            let target=uniqueURL(folder:URL(fileURLWithPath:watch.destination),name:output.lastPathComponent)
                            try FileManager.default.moveItem(at:output,to:target);moved.append(target)
                            if let value=self.stamp(target) {for w in self.watches {self.known[w.key+"|"+target.path]=value}}
                        }
                        Model.shared.results=moved
                        self.report?("Convertito: "+url.lastPathComponent)
                    } catch {self.report?("Risultato nella cartella sorgente: "+error.localizedDescription)}
                };return
            }
        }
    }
}
func uniqueURL(folder:URL,name:String)->URL {
    let original=folder.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath:original.path) {return original}
    for i in 1..<10000 {
        let url=folder.appendingPathComponent(original.deletingPathExtension().lastPathComponent+"-\(i)").appendingPathExtension(original.pathExtension)
        if !FileManager.default.fileExists(atPath:url.path) {return url}
    };return folder.appendingPathComponent(UUID().uuidString+"-"+name)
}
