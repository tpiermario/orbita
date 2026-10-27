import AppKit
import AVKit
import PDFKit

final class FileDropView: NSView {
    var receive: (([URL])->Void)?
    var canReceive: (()->Bool)?
    override init(frame:NSRect) { super.init(frame:frame);registerForDraggedTypes([.fileURL]) }
    required init?(coder:NSCoder) { fatalError() }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation { canReceive?() == false ? []:.copy }
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool { guard canReceive?() != false else{return false};let urls=fileURLs(sender.draggingPasteboard);receive?(urls);return !urls.isEmpty }
}
final class SelectionCanvas: NSView {
    var allowsSelection=false
    var image:NSImage?
    var imageSize:NSSize = .zero
    var selection:NSRect?
    var start:NSPoint?
    var changed:((NSRect)->Void)?
    var imageRect:NSRect {
        guard imageSize.width>0 else { return .zero }
        let scale=min(bounds.width/imageSize.width,bounds.height/imageSize.height)
        let size=NSSize(width:imageSize.width*scale,height:imageSize.height*scale)
        return NSRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2,width:size.width,height:size.height)
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor(calibratedWhite:0.12,alpha:1).setFill();bounds.fill()
        image?.draw(in:imageRect)
        if let rect=selection {
            NSColor.systemOrange.withAlphaComponent(0.15).setFill();rect.fill()
            NSColor.systemOrange.setStroke();let path=NSBezierPath(rect:rect);path.lineWidth=2;path.stroke()
        }
    }
    override func mouseDown(with event:NSEvent) { guard allowsSelection else{return};start=convert(event.locationInWindow,from:nil);selection=nil }
    override func mouseDragged(with event:NSEvent) {
        guard let a=start else {return};let b=convert(event.locationInWindow,from:nil)
        selection=NSRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y)).intersection(imageRect);needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        guard let rect=selection,rect.width>1,rect.height>1,imageRect.width>0 else { return }
        let scale=imageSize.width/imageRect.width
        changed?(NSRect(x:(rect.minX-imageRect.minX)*scale,y:(imageRect.maxY-rect.maxY)*scale,width:rect.width*scale,height:rect.height*scale))
    }
}
final class SignatureCanvas:NSView {
    var strokes:[NSBezierPath]=[]
    override func draw(_ dirtyRect:NSRect) {
        NSColor.white.setFill();bounds.fill();NSColor.black.setStroke();for p in strokes { p.stroke() }
    }
    override func mouseDown(with event:NSEvent) { let p=NSBezierPath();p.lineWidth=3;p.lineCapStyle = .round;p.move(to:convert(event.locationInWindow,from:nil));strokes.append(p) }
    override func mouseDragged(with event:NSEvent) { strokes.last?.line(to:convert(event.locationInWindow,from:nil));needsDisplay=true }
    func png()->Data? {
        let image=NSImage(size:bounds.size);image.lockFocus();NSColor.black.setStroke();for p in strokes { p.stroke() };image.unlockFocus()
        guard let data=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data) else {return nil};return bitmap.representation(using:.png,properties:[:])
    }
}
final class Surface:NSView {
    override init(frame:NSRect) {super.init(frame:frame);wantsLayer=true;layer?.cornerRadius=16;updateColors()}
    required init?(coder:NSCoder) {fatalError()}
    func updateColors() {layer?.backgroundColor=NSColor.controlBackgroundColor.cgColor;layer?.borderColor=NSColor.separatorColor.withAlphaComponent(0.35).cgColor;layer?.borderWidth=0.5}
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();updateColors()}
}
final class Studio:NSObject,NSTableViewDataSource,NSTableViewDelegate,NSSearchFieldDelegate,NSWindowDelegate {
    let window:NSWindow
    let table=NSTableView(),search=NSSearchField()
    let fileLabel=NSTextField(labelWithString:"Il tuo prossimo formato.")
    let fileDetail=NSTextField(labelWithString:""),actionTitle=NSTextField(labelWithString:"")
    let fileIcon=NSImageView(),statusLabel=NSTextField(labelWithString:"")
    let form=NSStackView(),preview=NSView(),progress=NSProgressIndicator()
    let mode=NSSegmentedControl(labels:["Converti","Modifica","Azioni"],trackingMode:.selectOne,target:nil,action:nil)
    let formScroll=NSScrollView(),formCard=Surface(),previewCard=Surface()
    var formHeight:NSLayoutConstraint!
    var go:NSButton!,choose:NSButton!,previewButton:NSButton!,favorite:NSButton!,sign:NSButton!,cancel:NSButton!,info:NSButton!
    var urls:[URL]=[],rows:[Action]=[],inputs:[String:NSTextField]=[:],pickedFiles:[String:URL]=[:]
    var selected:Action?,previewTemp:URL?,player:AVPlayer?,signatureWindow:NSWindow?,signatureCanvas:SignatureCanvas?
    var perform:((Action,[URL],[String:String])->Void)?
    var drafts:[String:[String:String]]=[:]
    var generation=UUID(),refreshing=false
    var detailPopover:NSPopover?
    static let accent=NSColor(calibratedRed:0.39,green:0.36,blue:0.89,alpha:1)
    init(title:String="Orbita") {
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1020,height:720),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        super.init();window.title=title;window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.minSize=NSSize(width:880,height:640);window.isReleasedWhenClosed=false;window.delegate=self;window.center()
        let root=FileDropView();root.receive={ [weak self] in self?.load($0) };root.canReceive={ !Model.shared.busy };window.contentView=root
        let sidebar=NSVisualEffectView();sidebar.material = .sidebar;sidebar.blendingMode = .behindWindow;sidebar.state = .active
        let content=NSView()
        for view in [sidebar,content] {view.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(view)}
        NSLayoutConstraint.activate([sidebar.leadingAnchor.constraint(equalTo:root.leadingAnchor),sidebar.topAnchor.constraint(equalTo:root.topAnchor),sidebar.bottomAnchor.constraint(equalTo:root.bottomAnchor),sidebar.widthAnchor.constraint(equalToConstant:244),content.leadingAnchor.constraint(equalTo:sidebar.trailingAnchor),content.trailingAnchor.constraint(equalTo:root.trailingAnchor),content.topAnchor.constraint(equalTo:root.topAnchor),content.bottomAnchor.constraint(equalTo:root.bottomAnchor)])
        let brand=NSTextField(labelWithString:"Orbita");brand.font = .systemFont(ofSize:23,weight:.bold)
        let brandIcon=NSImageView();brandIcon.image=NSImage(systemSymbolName:"circle.hexagongrid.fill",accessibilityDescription:nil);brandIcon.contentTintColor=Self.accent
        let brandRow=NSStackView(views:[brandIcon,brand]);brandRow.spacing=10;brandIcon.widthAnchor.constraint(equalToConstant:26).isActive=true;brandIcon.heightAnchor.constraint(equalToConstant:26).isActive=true
        mode.selectedSegment=0;mode.target=self;mode.action=#selector(filterChanged);mode.segmentStyle = .rounded;mode.font = .systemFont(ofSize:11,weight:.medium)
        search.placeholderString="Cerca";search.delegate=self;search.controlSize = .large
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.drawsBackground=false;scroll.borderType = .noBorder
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("action"));column.width=212;table.addTableColumn(column);table.headerView=nil;table.rowHeight=38;table.backgroundColor = .clear;table.style = .sourceList;table.dataSource=self;table.delegate=self;table.target=self;table.doubleAction=#selector(runSelected);table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle;scroll.documentView=table
        let hint=NSTextField(labelWithString:"⇧⌥  trascina e converti");hint.font = .systemFont(ofSize:11,weight:.medium);hint.textColor = .secondaryLabelColor
        for v in [brandRow,mode,search,scroll,hint] {v.translatesAutoresizingMaskIntoConstraints=false;sidebar.addSubview(v)}
        NSLayoutConstraint.activate([brandRow.topAnchor.constraint(equalTo:sidebar.topAnchor,constant:56),brandRow.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:22),mode.topAnchor.constraint(equalTo:brandRow.bottomAnchor,constant:24),mode.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:16),mode.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-16),search.topAnchor.constraint(equalTo:mode.bottomAnchor,constant:16),search.leadingAnchor.constraint(equalTo:mode.leadingAnchor),search.trailingAnchor.constraint(equalTo:mode.trailingAnchor),search.heightAnchor.constraint(equalToConstant:30),scroll.topAnchor.constraint(equalTo:search.bottomAnchor,constant:12),scroll.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:8),scroll.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-8),scroll.bottomAnchor.constraint(equalTo:hint.topAnchor,constant:-14),hint.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:22),hint.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor,constant:-22)])
        fileLabel.font = .systemFont(ofSize:18,weight:.semibold);fileLabel.lineBreakMode = .byTruncatingMiddle;fileLabel.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        fileDetail.font = .systemFont(ofSize:12);fileDetail.textColor = .secondaryLabelColor;fileDetail.lineBreakMode = .byTruncatingTail
        let fileText=NSStackView(views:[fileLabel,fileDetail]);fileText.orientation = .vertical;fileText.alignment = .leading;fileText.spacing=5
        fileIcon.image=NSImage(systemSymbolName:"doc.badge.plus",accessibilityDescription:nil);fileIcon.contentTintColor=Self.accent
        choose=iconButton("plus",label:"Aggiungi file",action:#selector(chooseFiles))
        let header=NSStackView(views:[fileIcon,fileText,choose]);header.spacing=14;fileIcon.widthAnchor.constraint(equalToConstant:38).isActive=true;fileIcon.heightAnchor.constraint(equalToConstant:42).isActive=true;fileText.setContentHuggingPriority(.defaultLow,for:.horizontal)
        preview.wantsLayer=true;preview.layer?.cornerRadius=10;preview.layer?.masksToBounds=true
        preview.translatesAutoresizingMaskIntoConstraints=false;previewCard.addSubview(preview)
        NSLayoutConstraint.activate([preview.leadingAnchor.constraint(equalTo:previewCard.leadingAnchor,constant:10),preview.trailingAnchor.constraint(equalTo:previewCard.trailingAnchor,constant:-10),preview.topAnchor.constraint(equalTo:previewCard.topAnchor,constant:10),preview.bottomAnchor.constraint(equalTo:previewCard.bottomAnchor,constant:-10)])
        formScroll.hasVerticalScroller=true;formScroll.drawsBackground=false;formScroll.borderType = .noBorder;formScroll.translatesAutoresizingMaskIntoConstraints=false;formCard.addSubview(formScroll)
        NSLayoutConstraint.activate([formScroll.leadingAnchor.constraint(equalTo:formCard.leadingAnchor,constant:16),formScroll.trailingAnchor.constraint(equalTo:formCard.trailingAnchor,constant:-16),formScroll.topAnchor.constraint(equalTo:formCard.topAnchor),formScroll.bottomAnchor.constraint(equalTo:formCard.bottomAnchor)])
        form.orientation = .vertical;form.alignment = .leading;form.spacing=10;form.edgeInsets=NSEdgeInsets(top:8,left:0,bottom:8,right:0);form.translatesAutoresizingMaskIntoConstraints=false;formScroll.documentView=form;form.widthAnchor.constraint(equalTo:formScroll.contentView.widthAnchor).isActive=true
        actionTitle.font = .systemFont(ofSize:17,weight:.semibold);actionTitle.lineBreakMode = .byTruncatingTail;actionTitle.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        info=iconButton("info.circle",label:"Dettagli e limiti",action:#selector(showDetails))
        let actionRow=NSStackView(views:[actionTitle,info]);actionRow.spacing=8
        let spacer=NSView();spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
        favorite=iconButton("star",label:"Preferito",action:#selector(toggleFavorite))
        previewButton=iconButton("eye",label:"Anteprima risultato",action:#selector(previewResult))
        sign=iconButton("signature",label:"Disegna firma",action:#selector(drawSignature))
        cancel=iconButton("stop.circle",label:"Annulla operazione",action:#selector(cancelWork));cancel.isHidden=true
        go=button("Converti",#selector(runSelected));go.bezelColor=Self.accent;go.keyEquivalent="\r";go.controlSize = .large;go.font = .systemFont(ofSize:13,weight:.semibold);go.widthAnchor.constraint(greaterThanOrEqualToConstant:128).isActive=true
        let footer=NSStackView(views:[favorite,previewButton,sign,spacer,cancel,go]);footer.spacing=10
        statusLabel.font = .systemFont(ofSize:11);statusLabel.textColor = .secondaryLabelColor;statusLabel.lineBreakMode = .byTruncatingTail
        progress.style = .spinning;progress.controlSize = .small;progress.isDisplayedWhenStopped=false;progress.widthAnchor.constraint(equalToConstant:16).isActive=true
        let statusRow=NSStackView(views:[progress,statusLabel]);statusRow.spacing=8
        for v in [header,previewCard,actionRow,formCard,footer,statusRow] {v.translatesAutoresizingMaskIntoConstraints=false;content.addSubview(v)}
        formHeight=formCard.heightAnchor.constraint(equalToConstant:0)
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:26),header.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-26),header.topAnchor.constraint(equalTo:content.topAnchor,constant:50),header.heightAnchor.constraint(equalToConstant:48),previewCard.leadingAnchor.constraint(equalTo:header.leadingAnchor),previewCard.trailingAnchor.constraint(equalTo:header.trailingAnchor),previewCard.topAnchor.constraint(equalTo:header.bottomAnchor,constant:20),previewCard.bottomAnchor.constraint(equalTo:actionRow.topAnchor,constant:-18),previewCard.heightAnchor.constraint(greaterThanOrEqualToConstant:170),actionRow.leadingAnchor.constraint(equalTo:header.leadingAnchor),actionRow.trailingAnchor.constraint(equalTo:header.trailingAnchor),actionRow.bottomAnchor.constraint(equalTo:formCard.topAnchor,constant:-12),actionRow.heightAnchor.constraint(equalToConstant:26),formCard.leadingAnchor.constraint(equalTo:header.leadingAnchor),formCard.trailingAnchor.constraint(equalTo:header.trailingAnchor),formHeight,formCard.bottomAnchor.constraint(equalTo:footer.topAnchor,constant:-18),footer.leadingAnchor.constraint(equalTo:header.leadingAnchor),footer.trailingAnchor.constraint(equalTo:header.trailingAnchor),footer.heightAnchor.constraint(equalToConstant:36),footer.bottomAnchor.constraint(equalTo:statusRow.topAnchor,constant:-12),statusRow.leadingAnchor.constraint(equalTo:header.leadingAnchor),statusRow.trailingAnchor.constraint(equalTo:header.trailingAnchor),statusRow.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-18),statusRow.heightAnchor.constraint(equalToConstant:18)])
        showPreview();updateControls()
    }
    func button(_ title:String,_ action:Selector)->NSButton {let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded;return b}
    func iconButton(_ symbol:String,label:String,action:Selector)->NSButton {let b=button("",action);b.image=NSImage(systemSymbolName:symbol,accessibilityDescription:label);b.toolTip=label;b.setAccessibilityLabel(label);b.widthAnchor.constraint(equalToConstant:32).isActive=true;return b}
    func show() {NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil)}
    func params()->[String:String] {var values=inputs.mapValues(\.stringValue);for (key,url) in pickedFiles {values[key]=url.path};return values}
    func saveDraft() {if let selected=selected {drafts[selected.id]=params()}}
    func invalidatePreview() {generation=UUID();if !Model.shared.busy,let old=previewTemp {try? FileManager.default.removeItem(at:old);previewTemp=nil}}
    func load(_ urls:[URL],action:Action?=nil) {
        guard !Model.shared.busy,window.attachedSheet==nil else{return}
        invalidatePreview();drafts=[:];self.urls=urls;search.stringValue=""
        mode.selectedSegment=action.map{["convert","tools","actions"].firstIndex(of:$0.mode) ?? 0} ?? 0
        fileLabel.stringValue=urls.count==1 ? urls[0].lastPathComponent : "\(urls.count) file"
        fileIcon.image=urls.first.map{NSWorkspace.shared.icon(forFile:$0.path)}
        if let url=urls.first,urls.count==1 {let size=(try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0;fileDetail.stringValue=url.pathExtension.uppercased()+"  ·  "+ByteCountFormatter.string(fromByteCount:Int64(size),countStyle:.file)} else {fileDetail.stringValue="Selezione multipla"}
        selected=nil;refresh(preferred:action?.id);show()
    }
    func refresh(preferred:String?=nil) {
        saveDraft();let wanted=preferred ?? selected?.id;invalidatePreview()
        let query=search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        rows=Model.shared.available(urls,mode:query.isEmpty ? ["convert","tools","actions"][max(0,mode.selectedSegment)] : nil).filter{query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)}
        refreshing=true;table.reloadData()
        if rows.isEmpty {selected=nil;table.deselectAll(nil)} else {let i=rows.firstIndex{$0.id==wanted} ?? 0;selected=rows[i];table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false)}
        refreshing=false;configure()
    }
    @objc func filterChanged() {refresh()}
    func controlTextDidChange(_ obj:Notification) {refresh()}
    func numberOfRows(in tableView:NSTableView)->Int {rows.count}
    func symbol(_ action:Action)->String {
        if action.mode=="convert" {return "doc"}
        if action.id.contains("password") || action.id.contains("dmg") {return "lock"}
        if action.id.contains("sign") {return "signature"}
        if action.id.contains("ocr") || action.id.contains("transcribe") {return "text.viewfinder"}
        return action.mode=="actions" ? "folder":"slider.horizontal.3"
    }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        let action=rows[row];let icon=NSImageView();icon.image=NSImage(systemSymbolName:symbol(action),accessibilityDescription:nil);icon.contentTintColor=Self.accent;icon.widthAnchor.constraint(equalToConstant:18).isActive=true
        let label=NSTextField(labelWithString:action.title);label.font = .systemFont(ofSize:12,weight:action.mode=="convert" ? .semibold:.regular);label.lineBreakMode = .byTruncatingTail;label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let row=NSStackView(views:[icon,label]);row.spacing=10;row.toolTip=action.title;row.edgeInsets=NSEdgeInsets(top:0,left:6,bottom:0,right:6)
        if Model.shared.favorites.contains(action.id) {let star=NSImageView();star.image=NSImage(systemSymbolName:"star.fill",accessibilityDescription:"Preferito");star.contentTintColor=Self.accent;star.widthAnchor.constraint(equalToConstant:10).isActive=true;row.addArrangedSubview(star)}
        return row
    }
    func tableViewSelectionDidChange(_ notification:Notification) {guard !refreshing,!Model.shared.busy,rows.indices.contains(table.selectedRow) else{return};saveDraft();invalidatePreview();selected=rows[table.selectedRow];configure()}
    func clearForm() {form.arrangedSubviews.forEach{form.removeArrangedSubview($0);$0.removeFromSuperview()};inputs=[:];pickedFiles=[:]}
    func configure() {
        clearForm()
        guard let action=selected else {actionTitle.stringValue=urls.isEmpty ? "" : "Nessun risultato";formHeight.constant=0;formCard.isHidden=true;showPreview();updateControls();return}
        actionTitle.stringValue=action.mode=="convert" ? "Esporta in "+action.title:action.title
        for parameter in action.fields {
            let row=NSStackView();row.orientation = .horizontal;row.spacing=10;row.translatesAutoresizingMaskIntoConstraints=false
            let label=NSTextField(labelWithString:parameter.label);label.font = .systemFont(ofSize:12);label.lineBreakMode = .byTruncatingTail;label.toolTip=parameter.label
            label.widthAnchor.constraint(equalToConstant:174).isActive=true
            let input:NSTextField=parameter.kind=="password" ? NSSecureTextField():NSTextField();input.font = .systemFont(ofSize:13);input.bezelStyle = .roundedBezel;input.setContentHuggingPriority(.defaultLow,for:.horizontal);input.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);input.widthAnchor.constraint(greaterThanOrEqualToConstant:80).isActive=true
            let value=drafts[action.id]?[parameter.key] ?? (action.id=="pdf.sign" && parameter.key=="file" ? (UserDefaults.standard.string(forKey:"signaturePath") ?? parameter.default):parameter.default)
            input.stringValue=value;input.setAccessibilityLabel(parameter.label);inputs[parameter.key]=input
            row.addArrangedSubview(label);row.addArrangedSubview(input)
            if parameter.kind=="file" {
                input.isEditable=false;input.placeholderString="Scegli file"
                if !value.isEmpty {let url=URL(fileURLWithPath:value);pickedFiles[parameter.key]=url;input.stringValue=url.lastPathComponent;input.toolTip=url.path}
                let b=iconButton("folder",label:"Scegli "+parameter.label,action:#selector(pickParameterFile(_:)));b.identifier=NSUserInterfaceItemIdentifier(parameter.key);row.addArrangedSubview(b)
            }
            form.addArrangedSubview(row);row.widthAnchor.constraint(equalTo:form.widthAnchor).isActive=true;row.heightAnchor.constraint(greaterThanOrEqualToConstant:28).isActive=true
        }
        formHeight.constant=action.fields.isEmpty ? 0:min(190,CGFloat(action.fields.count)*38+32);formCard.isHidden=action.fields.isEmpty
        showPreview();updateControls()
    }
    func updateControls() {
        let busy=Model.shared.busy;let action=selected
        go.isEnabled=action != nil && !busy;go.title=action?.mode=="convert" ? "Converti":action?.mode=="actions" ? "Esegui":"Applica"
        choose.isEnabled = !busy;mode.isEnabled = !busy;search.isEnabled = !busy;table.isEnabled = !busy
        favorite.isEnabled=action != nil && !busy;favorite.image=NSImage(systemSymbolName:action.map{Model.shared.favorites.contains($0.id)} == true ? "star.fill":"star",accessibilityDescription:"Preferito")
        let canPreview=action.map{!$0.id.hasPrefix("native.") && !$0.id.hasPrefix("files.") && !$0.id.hasPrefix("archive.")} ?? false
        previewButton.isHidden = !(canPreview && urls.first.map{["image","pdf"].contains(family($0))} == true);previewButton.isEnabled = !busy
        sign.isHidden=action?.id != "pdf.sign";sign.isEnabled = !busy;info.isHidden=action?.note.isEmpty ?? true
        cancel.isHidden = !busy;cancel.isEnabled=Model.shared.process != nil
        for input in inputs.values {input.isEnabled = !busy}
        if busy {progress.startAnimation(nil)} else {progress.stopAnimation(nil)}
    }
    func setBusy(_ busy:Bool) {updateControls()}
    func showPreview(_ result:URL?=nil) {
        player?.pause();player=nil;preview.subviews.forEach{$0.removeFromSuperview()}
        guard let url=result ?? urls.first else {
            let icon=NSImageView();icon.image=NSImage(systemSymbolName:"square.and.arrow.down",accessibilityDescription:nil);icon.contentTintColor=Self.accent
            let title=NSTextField(labelWithString:"Trascina un file");title.font = .systemFont(ofSize:21,weight:.semibold)
            let subtitle=NSTextField(labelWithString:"oppure usa +");subtitle.textColor = .secondaryLabelColor;subtitle.font = .systemFont(ofSize:13)
            let stack=NSStackView(views:[icon,title,subtitle]);stack.orientation = .vertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=false;preview.addSubview(stack);NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo:preview.centerXAnchor),stack.centerYAnchor.constraint(equalTo:preview.centerYAnchor),icon.widthAnchor.constraint(equalToConstant:42),icon.heightAnchor.constraint(equalToConstant:42)]);return
        }
        let kind=family(url)
        if kind=="image",let image=NSImage(contentsOf:url) {
            let canvas=SelectionCanvas(frame:preview.bounds);canvas.autoresizingMask=[.width,.height];canvas.image=image
            if let bitmap=image.representations.first {canvas.imageSize=NSSize(width:bitmap.pixelsWide,height:bitmap.pixelsHigh)} else {canvas.imageSize=image.size}
            canvas.allowsSelection=result==nil && ["image.crop","image.redact"].contains(selected?.id ?? "")
            canvas.toolTip=canvas.allowsSelection ? "Trascina per selezionare l’area":nil
            canvas.changed={ [weak self] rect in for (key,value) in [("x",rect.minX),("y",rect.minY),("width",rect.width),("height",rect.height)] {self?.inputs[key]?.stringValue=String(Int(value))} };preview.addSubview(canvas)
        } else if kind=="pdf" {
            let view=PDFView(frame:preview.bounds);view.autoresizingMask=[.width,.height];view.autoScales=true;view.document=PDFDocument(url:url);preview.addSubview(view)
        } else if kind=="video" || kind=="audio" {
            let hasRange=selected?.fields.contains{$0.key=="start" || $0.key=="end"} ?? false
            let offset:CGFloat=hasRange ? 38:0
            let pv=AVPlayerView(frame:NSRect(x:0,y:offset,width:preview.bounds.width,height:preview.bounds.height-offset));pv.autoresizingMask=[.width,.height];player=AVPlayer(url:url);pv.player=player;preview.addSubview(pv)
            if hasRange {let a=button("Inizio",#selector(markStart));a.frame=NSRect(x:8,y:4,width:90,height:28);preview.addSubview(a);let b=button("Fine",#selector(markEnd));b.frame=NSRect(x:106,y:4,width:90,height:28);preview.addSubview(b)}
        } else {
            let icon=NSImageView();icon.image=NSWorkspace.shared.icon(forFile:url.path);icon.translatesAutoresizingMaskIntoConstraints=false;preview.addSubview(icon);NSLayoutConstraint.activate([icon.centerXAnchor.constraint(equalTo:preview.centerXAnchor),icon.centerYAnchor.constraint(equalTo:preview.centerYAnchor),icon.widthAnchor.constraint(equalToConstant:100),icon.heightAnchor.constraint(equalToConstant:100)])
        }
    }
    @objc func previewResult() {
        guard let action=selected,!Model.shared.busy else{return};invalidatePreview();let token=generation
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("orbita-preview-\(UUID().uuidString)");previewTemp=folder
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);var copies:[URL]=[]
            for (i,url) in urls.enumerated() {let copy=folder.appendingPathComponent("\(i)-"+url.lastPathComponent);try FileManager.default.copyItem(at:url,to:copy);copies.append(copy)}
            Model.shared.run(action,urls:copies,params:params(),recordResults:false) { [weak self] outputs,error in
                guard let self=self,self.generation==token else {try? FileManager.default.removeItem(at:folder);return}
                if let error=error {self.statusLabel.stringValue=error;self.statusLabel.toolTip=error}
                else if let output=outputs.first {self.showPreview(output);self.statusLabel.stringValue="Anteprima · non salvata"}
            }
            updateControls()
        } catch {try? FileManager.default.removeItem(at:folder);statusLabel.stringValue=error.localizedDescription}
    }
    @objc func showDetails() {guard let note=selected?.note,!note.isEmpty else{return};let controller=NSViewController();let text=NSTextField(wrappingLabelWithString:note);text.font = .systemFont(ofSize:13);text.frame=NSRect(x:18,y:18,width:304,height:120);controller.view=NSView(frame:NSRect(x:0,y:0,width:340,height:156));controller.view.addSubview(text);let pop=NSPopover();pop.contentViewController=controller;pop.behavior = .transient;pop.show(relativeTo:info.bounds,of:info,preferredEdge:.maxY);detailPopover=pop}
    @objc func markStart() {if let t=player?.currentTime().seconds,t.isFinite {inputs["start"]?.stringValue=String(format:"%.3f",t)}}
    @objc func markEnd() {if let t=player?.currentTime().seconds,t.isFinite {inputs["end"]?.stringValue=String(format:"%.3f",t)}}
    @objc func chooseFiles() {guard !Model.shared.busy else{return};let p=NSOpenPanel();p.allowsMultipleSelection=true;p.canChooseDirectories=true;if p.runModal() == .OK {load(p.urls)}}
    @objc func pickParameterFile(_ sender:NSButton) {guard !Model.shared.busy else{return};let p=NSOpenPanel();if p.runModal() == .OK,let key=sender.identifier?.rawValue,let url=p.url {pickedFiles[key]=url;inputs[key]?.stringValue=url.lastPathComponent;inputs[key]?.toolTip=url.path}}
    @objc func runSelected() {guard let action=selected,!Model.shared.busy else{return};player?.pause();perform?(action,urls,params());updateControls()}
    @objc func toggleFavorite() {guard let action=selected else{return};saveDraft();var fav=Model.shared.favorites;if fav.contains(action.id) {fav.removeAll{$0==action.id}} else {fav.append(action.id)};Model.shared.favorites=fav;refresh(preferred:action.id)}
    @objc func cancelWork() {Model.shared.cancel()}
    @objc func drawSignature() {
        guard selected?.id=="pdf.sign",!Model.shared.busy,window.attachedSheet==nil else{return}
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:250),styleMask:[.titled,.closable],backing:.buffered,defer:false);w.title="La tua firma";w.isReleasedWhenClosed=false;w.center()
        let canvas=SignatureCanvas(frame:NSRect(x:20,y:55,width:540,height:170));w.contentView?.addSubview(canvas);signatureCanvas=canvas
        let save=button("Usa firma",#selector(saveSignature));save.frame=NSRect(x:420,y:12,width:140,height:30);w.contentView?.addSubview(save)
        let clear=button("Cancella",#selector(clearSignature));clear.frame=NSRect(x:20,y:12,width:120,height:30);w.contentView?.addSubview(clear);let dismiss=button("Annulla",#selector(dismissSignature));dismiss.frame=NSRect(x:280,y:12,width:120,height:30);w.contentView?.addSubview(dismiss);signatureWindow=w;window.beginSheet(w) { _ in }
    }
    @objc func dismissSignature() {if let w=signatureWindow {window.endSheet(w);w.close()}}
    @objc func clearSignature() {signatureCanvas?.strokes=[];signatureCanvas?.needsDisplay=true}
    @objc func saveSignature() {
        guard selected?.id=="pdf.sign",!Model.shared.busy,let canvas=signatureCanvas,!canvas.strokes.isEmpty,let data=canvas.png() else{return}
        let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Orbita"),url=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Orbita/signature.png")
        do {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);try data.write(to:url,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path);UserDefaults.standard.set(url.path,forKey:"signaturePath");pickedFiles["file"]=url;inputs["file"]?.stringValue="Firma";if let w=signatureWindow {window.endSheet(w);w.close()}} catch {statusLabel.stringValue=error.localizedDescription}
    }
    func windowWillClose(_ notification:Notification) {player?.pause();invalidatePreview()}
}
