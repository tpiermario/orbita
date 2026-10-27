import AppKit
import Carbon
import CryptoKit

final class AppDelegate:NSObject,NSApplicationDelegate {
    var status:NSStatusItem!
    var panel:NSPanel!
    var wheel:WheelView!
    var studio:Studio!
    var shelf:Shelf!
    var watcher:Watcher!
    var timer:Timer?
    var downPoint:NSPoint?
    var manual=false
    var hotKey:EventHotKeyRef?
    var hotHandler:EventHandlerRef?
    var help:NSWindow?
    var services:NSObject?
    func applicationDidFinishLaunching(_ notification:Notification) {
        let mainMenu=NSMenu();let appItem=NSMenuItem();let appMenu=NSMenu();appMenu.addItem(withTitle:"Esci da Orbita",action:#selector(quit),keyEquivalent:"q").target=self;appItem.submenu=appMenu;mainMenu.addItem(appItem)
        let editItem=NSMenuItem();let edit=NSMenu(title:"Modifica")
        for (title,selector,key) in [("Annulla","undo:","z"),("Taglia","cut:","x"),("Copia","copy:","c"),("Incolla","paste:","v"),("Seleziona tutto","selectAll:","a")] {edit.addItem(withTitle:title,action:Selector(selector),keyEquivalent:key)}
        editItem.submenu=edit;mainMenu.addItem(editItem);NSApp.mainMenu=mainMenu
        studio=Studio();studio.perform={ [weak self] action,urls,params in self?.execute(action,urls,params) }
        shelf=Shelf();shelf.open={ [weak self] in self?.studio.load($0) }
        watcher=Watcher();watcher.report={ [weak self] in self?.studio.statusLabel.stringValue=$0 }
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status.button?.image=NSImage(systemSymbolName:"circle.hexagongrid.fill",accessibilityDescription:"Orbita")
        let menu=NSMenu()
        for (title,action,key) in [("Apri Studio…",#selector(openStudio),""),("Ruota Converti · ⇧⌥",#selector(manualWheel),""),("Scaffale",#selector(showShelf),""),("Aggiungi cartella automatica…",#selector(addWatch),""),("Gestisci cartelle automatiche…",#selector(manageWatches),""),("Mostra ultimi risultati",#selector(reveal),""),("Istruzioni",#selector(showHelp),""),("Esci da Orbita",#selector(quit),"")] {
            let item=menu.addItem(withTitle:title,action:action,keyEquivalent:key);item.target=self
        };status.menu=menu
        panel=NSPanel(contentRect:NSRect(x:0,y:0,width:400,height:400),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .popUpMenu;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        wheel=WheelView(frame:NSRect(x:0,y:0,width:400,height:400));panel.contentView=wheel
        wheel.drop={ [weak self] urls,action in
            guard let self=self else{return};self.panel.orderOut(nil);self.manual=false
            if let action=action {
                if action.fields.isEmpty {self.execute(action,urls,[:])} else {self.studio.load(urls,action:action)}
            } else {self.studio.load(urls)}
        }
        timer=Timer(timeInterval:0.035,repeats:true) { [weak self] _ in self?.tick() };RunLoop.main.add(timer!,forMode:.common)
        Model.shared.busyChanged={ [weak self] busy in self?.studio.setBusy(busy) }
        Model.shared.status={ [weak self] text in
            self?.studio.statusLabel.stringValue=text
            if Model.shared.busy {self?.studio.progress.startAnimation(nil)} else {self?.studio.progress.stopAnimation(nil)}
            self?.status.button?.image=NSImage(systemSymbolName:Model.shared.busy ? "hourglass":"circle.hexagongrid.fill",accessibilityDescription:text)
        }
        Model.shared.completion={ [weak self] outputs,error in
            if let error=error {self?.alert("Operazione non completata",error+(outputs.isEmpty ? "":"\n\n\(outputs.count) risultati parziali conservati."))}
            if !outputs.isEmpty {NSWorkspace.shared.activateFileViewerSelecting(outputs)}
        }
        NSApp.servicesProvider=self;NSUpdateDynamicServices()
        registerHotKey()
        NSAppleEventManager.shared().setEventHandler(self,andSelector:#selector(handleURL(_:reply:)),forEventClass:AEEventClass(kInternetEventClass),andEventID:AEEventID(kAEGetURL))
        if let index=CommandLine.arguments.firstIndex(of:"--open"),CommandLine.arguments.count>index+1 {
            studio.load([URL(fileURLWithPath:CommandLine.arguments[index+1])])
        } else {studio.show()}
    }
    func tick() {
        guard !Model.shared.busy else{return}
        let point=NSEvent.mouseLocation,pressed=NSEvent.pressedMouseButtons & 1 != 0
        if !pressed {downPoint=nil;if !manual {panel.orderOut(nil)};return}
        if downPoint==nil {downPoint=point};guard let origin=downPoint,hypot(point.x-origin.x,point.y-origin.y)>5 else{return}
        let flags=NSEvent.modifierFlags;var mode:String?
        if flags.contains([.shift,.option]) {mode="convert"}
        else if flags.contains(.command) {mode="tools"}
        else if flags.contains(.control) {mode="actions"}
        if let mode=mode {
            if !panel.isVisible {wheel.mode=mode;showWheel(point)}
            else if wheel.mode != mode {wheel.mode=mode;wheel.refresh()}
        } else if !manual {panel.orderOut(nil)}
    }
    func showWheel(_ point:NSPoint) {
        let frame=(NSScreen.screens.first{$0.frame.contains(point)} ?? NSScreen.main!).visibleFrame
        wheel.urls=[];wheel.actions=[];wheel.more=false;wheel.selected=nil;wheel.needsDisplay=true
        panel.setFrameOrigin(NSPoint(x:min(max(point.x-200,frame.minX),frame.maxX-400),y:min(max(point.y-200,frame.minY),frame.maxY-400)));panel.orderFrontRegardless()
    }
    @objc func manualWheel() {manual.toggle();if manual {wheel.mode="convert";showWheel(NSEvent.mouseLocation)} else {panel.orderOut(nil)}}
    @objc func openStudio() {studio.show()}
    @objc func showShelf() {shelf.window.orderFrontRegardless()}
    @objc func reveal() {if !Model.shared.results.isEmpty {NSWorkspace.shared.activateFileViewerSelecting(Model.shared.results)}}
    @objc func quit() {if Model.shared.busy {Model.shared.cancel()};NSApp.terminate(nil)}
    func alert(_ title:String,_ text:String) {NSApp.activate(ignoringOtherApps:true);let a=NSAlert();a.messageText=title;a.informativeText=text;a.runModal()}
    func execute(_ action:Action,_ urls:[URL],_ params:[String:String]) {
        guard !Model.shared.busy else{return}
        if action.id.hasPrefix("native.") {native(action,urls,params)} else if requiresAppleExport(action) && urls.contains(where:{["pages","key","numbers"].contains($0.pathExtension.lowercased())}) {
            prepareAppleDocuments(action,urls,params)
        } else {Model.shared.run(action,urls:urls,params:params)}
    }
    func prepareAppleDocuments(_ action:Action,_ urls:[URL],_ params:[String:String]) {
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("orbita-apple-\(UUID().uuidString)")
        var sources:[URL]=[],destinations:[String:String]=[:]
        func quote(_ value:String)->String {"\""+value.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")+"\""}
        do {
            try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
            for (index,url) in urls.enumerated() {
                let kind=url.pathExtension.lowercased()
                guard ["pages","key","numbers"].contains(kind) else {sources.append(url);continue}
                let app=kind=="pages" ? "Pages":kind=="key" ? "Keynote":"Numbers"
                let outputExt=kind=="pages" ? "docx":kind=="key" ? "pptx":"xlsx"
                let format=kind=="pages" ? "Microsoft Word":kind=="key" ? "Microsoft PowerPoint":"Microsoft Excel"
                let folder=temp.appendingPathComponent(String(index));try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                let output=folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension(outputExt)
                let code="tell application \"\(app)\"\nset d to open POSIX file \(quote(url.path))\nexport d to POSIX file \(quote(output.path)) as \(format)\nclose d saving no\nend tell"
                var error:NSDictionary?;NSAppleScript(source:code)?.executeAndReturnError(&error)
                if let error=error {throw NSError(domain:"Orbita",code:1,userInfo:[NSLocalizedDescriptionKey:error.description])}
                guard FileManager.default.fileExists(atPath:output.path) else {throw NSError(domain:"Orbita",code:2,userInfo:[NSLocalizedDescriptionKey:"Esportazione \(app) non riuscita."])}
                sources.append(output);destinations[output.path]=url.path
            }
            Model.shared.run(action,urls:sources,params:params,destinations:destinations) { outputs,error in
                try? FileManager.default.removeItem(at:temp);Model.shared.completion?(outputs,error)
            }
        } catch {try? FileManager.default.removeItem(at:temp);alert("Documento Apple",error.localizedDescription)}
    }
    func native(_ action:Action,_ urls:[URL],_ params:[String:String]) {
        guard let first=urls.first else{return}
        switch action.id {
        case "native.float":shelf.add(urls)
        case "native.reveal":NSWorkspace.shared.activateFileViewerSelecting(urls)
        case "native.path":NSPasteboard.general.clearContents();NSPasteboard.general.setString(urls.map(\.path).joined(separator:"\n"),forType:.string)
        case "native.copy":NSPasteboard.general.clearContents();NSPasteboard.general.writeObjects(urls.map{$0 as NSURL})
        case "native.copyimage":if let image=NSImage(contentsOf:first) {NSPasteboard.general.clearContents();NSPasteboard.general.writeObjects([image])}
        case "native.airdrop":
            if let service=NSSharingService(named:.sendViaAirDrop) {service.perform(withItems:urls)}
        case "native.hash":
            Model.shared.busy=true;Model.shared.status?("Calcolo SHA-256…")
            DispatchQueue.global().async {
                var lines:[String]=[];var failure:String?
                do {for url in urls {
                    let file=try FileHandle(forReadingFrom:url);defer {try? file.close()};var hash=SHA256()
                    while let data=try file.read(upToCount:1024*1024),!data.isEmpty {hash.update(data:data)}
                    lines.append(hash.finalize().map{String(format:"%02x",$0)}.joined()+"  "+url.lastPathComponent)
                }} catch {failure=error.localizedDescription}
                DispatchQueue.main.async {
                    Model.shared.busy=false
                    if let failure=failure {Model.shared.status?(failure)} else {
                        NSPasteboard.general.clearContents();NSPasteboard.general.setString(lines.joined(separator:"\n"),forType:.string);Model.shared.status?("Checksum copiato negli appunti")
                    }
                }
            }
        case "native.terminal":
            let dir=first.hasDirectoryPath ? first:first.deletingLastPathComponent()
            NSWorkspace.shared.open([dir],withApplicationAt:URL(fileURLWithPath:"/System/Applications/Utilities/Terminal.app"),configuration:NSWorkspace.OpenConfiguration())
        case "native.move","native.copyto":
            let p=NSOpenPanel();p.canChooseFiles=false;p.canChooseDirectories=true;p.canCreateDirectories=true;p.prompt="Scegli cartella"
            if p.runModal() == .OK,let folder=p.url {
                do {var results:[URL]=[];for url in urls {if action.id=="native.move" && url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()==folder.standardizedFileURL.resolvingSymlinksInPath() {results.append(url);continue};let dest=uniqueURL(folder:folder,name:url.lastPathComponent);if action.id=="native.move" {try FileManager.default.moveItem(at:url,to:dest)} else {try FileManager.default.copyItem(at:url,to:dest)};results.append(dest)};Model.shared.results=results;NSWorkspace.shared.activateFileViewerSelecting(results)} catch {alert("Operazione interrotta",error.localizedDescription)}
            }
        case "native.dmg":createDMG(urls,params)
        case "native.pages","native.keynote":appleExport(action,urls)
        default:break
        }
    }
    func createDMG(_ urls:[URL],_ params:[String:String]) {
        guard let password=params["password"],!password.isEmpty else{alert("Password necessaria","Inserisci una password.");return}
        let dest=uniqueURL(folder:urls[0].deletingLastPathComponent(),name:urls[0].deletingPathExtension().lastPathComponent+"-orbita.dmg")
        Model.shared.busy=true;Model.shared.status?("Creazione immagine disco cifrata…")
        DispatchQueue.global().async {
            var failure:String?
            let temp=FileManager.default.temporaryDirectory.appendingPathComponent("orbita-dmg-\(UUID().uuidString)")
            do {
                try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
                for url in urls {try FileManager.default.copyItem(at:url,to:temp.appendingPathComponent(url.lastPathComponent))}
                let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/hdiutil");process.arguments=["create","-srcfolder",temp.path,"-volname","Orbita","-encryption","AES-256","-stdinpass",dest.path]
                let input=Pipe(),err=Pipe();process.standardInput=input;process.standardOutput=FileHandle.nullDevice;process.standardError=err
                try process.run();input.fileHandleForWriting.write(Data((password+"\0").utf8));try? input.fileHandleForWriting.close();let data=err.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
                if process.terminationStatus != 0 {failure=String(data:data,encoding:.utf8) ?? "Creazione fallita."}
            } catch {failure=error.localizedDescription}
            try? FileManager.default.removeItem(at:temp)
            DispatchQueue.main.async {Model.shared.busy=false;Model.shared.status?(failure ?? "Immagine disco creata");if let failure=failure {self.alert("Errore",failure)} else {Model.shared.results=[dest];NSWorkspace.shared.activateFileViewerSelecting([dest])}}
        }
    }
    func appleExport(_ action:Action,_ urls:[URL]) {
        let app=action.id=="native.pages" ? "Pages":"Keynote",ext=action.id=="native.pages" ? "pages":"key"
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier:app=="Pages" ? "com.apple.iWork.Pages":"com.apple.iWork.Keynote") != nil else {alert("\(app) necessario","Installa \(app) per creare documenti nel suo formato nativo.");return}
        func quote(_ text:String)->String {"\""+text.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")+"\""}
        Model.shared.results=[]
        for url in urls {
            let dest=uniqueURL(folder:url.deletingLastPathComponent(),name:url.deletingPathExtension().lastPathComponent+"-orbita."+ext)
            let code="tell application \"\(app)\"\nset d to open POSIX file \(quote(url.path))\nsave d in POSIX file \(quote(dest.path))\nclose d saving no\nend tell"
            var error:NSDictionary?;NSAppleScript(source:code)?.executeAndReturnError(&error)
            if let error=error {alert("Esportazione non riuscita",error.description);return}
            Model.shared.results.append(dest)
        };reveal()
    }
    @objc func addWatch() {
        let source=NSOpenPanel();source.canChooseFiles=false;source.canChooseDirectories=true;source.message="Cartella da monitorare: verranno elaborati solo i nuovi file.";guard source.runModal() == .OK,let folder=source.url else{return}
        let target=NSOpenPanel();target.canChooseFiles=false;target.canChooseDirectories=true;target.canCreateDirectories=true;target.message="Cartella distinta per i risultati";guard target.runModal() == .OK,let dest=target.url,dest != folder else{return}
        let choices=Model.shared.actions.filter{$0.mode=="convert" && !$0.id.hasPrefix("native.") && $0.fields.isEmpty && $0.id != "archive.extract"}
        let a=NSAlert();a.messageText="Conversione automatica";a.informativeText="I file nuovi compatibili verranno convertiti mentre Orbita è aperta. Gli originali restano nella cartella sorgente."
        let popup=NSPopUpButton(frame:NSRect(x:0,y:0,width:340,height:28));popup.addItems(withTitles:choices.map{$0.families[0]+" → "+$0.title});a.accessoryView=popup;a.addButton(withTitle:"Attiva");a.addButton(withTitle:"Annulla")
        if a.runModal() == .alertFirstButtonReturn {watcher.add(Watch(folder:folder.path,destination:dest.path,action:choices[popup.indexOfSelectedItem].id))}
    }
    @objc func manageWatches() {
        let a=NSAlert();a.messageText="Cartelle automatiche";a.informativeText=watcher.watches.isEmpty ? "Nessuna cartella configurata.":watcher.watches.map{$0.folder+"\n→ "+$0.destination+" ("+$0.action+")"}.joined(separator:"\n\n");a.addButton(withTitle:"Chiudi")
        if !watcher.watches.isEmpty {a.addButton(withTitle:"Disattiva tutte")}
        if a.runModal() == .alertSecondButtonReturn {watcher.clear()}
    }
    @objc func showHelp() {
        let a=NSAlert();a.messageText="Trascina. Scegli. Fatto."
        a.informativeText="Durante il trascinamento:\n\n⇧⌥  Converti\n⌘  Modifica\n⌃  Azioni\n\n⌃⌥K  Apri Orbita"
        a.addButton(withTitle:"Apri Orbita");a.addButton(withTitle:"Chiudi")
        if a.runModal() == .alertFirstButtonReturn {studio.show()}
    }
    func openFinderSelection() {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" {
            let script="tell application \"Finder\"\nset itemsSelected to selection as alias list\nset paths to {}\nrepeat with f in itemsSelected\nset end of paths to POSIX path of f\nend repeat\nreturn paths\nend tell"
            var error:NSDictionary?
            if let result=NSAppleScript(source:script)?.executeAndReturnError(&error),error==nil,result.numberOfItems>0 {
                let urls=(1...result.numberOfItems).compactMap{result.atIndex($0)?.stringValue}.map{URL(fileURLWithPath:$0)}
                if !urls.isEmpty {studio.load(urls);return}
            }
        };openStudio()
    }
    func registerHotKey() {
        var type=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),{ _,_,pointer in
            guard let pointer=pointer else{return noErr};let app=Unmanaged<AppDelegate>.fromOpaque(pointer).takeUnretainedValue();DispatchQueue.main.async{app.openFinderSelection()};return noErr
        },1,&type,Unmanaged.passUnretained(self).toOpaque(),&hotHandler)
        RegisterEventHotKey(UInt32(kVK_ANSI_K),UInt32(controlKey|optionKey),EventHotKeyID(signature:0x4F524249,id:1),GetApplicationEventTarget(),0,&hotKey)
    }
    @objc func openInOrbita(_ pasteboard:NSPasteboard,userData:String?,error:AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls=fileURLs(pasteboard)
        if urls.isEmpty {error.pointee="Nessun file ricevuto."} else {studio.load(urls)}
    }
    @objc func handleURL(_ event:NSAppleEventDescriptor,reply:NSAppleEventDescriptor) {
        guard let string=event.paramDescriptor(forKeyword:keyDirectObject)?.stringValue,let components=URLComponents(string:string),components.scheme=="orbita" else{return}
        let paths=(components.queryItems ?? []).filter{$0.name=="file"}.compactMap{$0.value}.map{URL(fileURLWithPath:$0)}
        let id=components.queryItems?.first{$0.name=="action"}?.value
        guard !paths.isEmpty else{openStudio();return}
        // URL links open a reviewable action; never execute an operation silently.
        studio.load(paths,action:Model.shared.actions.first{$0.id==id})
    }
}
let app=NSApplication.shared
let delegate=AppDelegate();app.delegate=delegate;app.setActivationPolicy(.accessory);app.run()
