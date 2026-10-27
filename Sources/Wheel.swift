import AppKit
final class WheelView:NSView {
    var mode="convert"
    var urls:[URL]=[]
    var actions:[Action]=[]
    var selected:Int?
    var more=false
    var drop:(([URL],Action?)->Void)?
    var title:String { mode=="convert" ? "CONVERTI" : mode=="tools" ? "MODIFICA" : "AZIONI" }
    override init(frame:NSRect) {super.init(frame:frame);registerForDraggedTypes([.fileURL])}
    required init?(coder:NSCoder) {fatalError()}
    var count:Int {actions.count+(more ? 1:0)}
    func sector(_ point:NSPoint)->Int? {
        let dx=point.x-bounds.midX,dy=point.y-bounds.midY,d=hypot(dx,dy)
        if d<65 {return -1}
        guard count>0,d<=194 else{return nil}
        let step=2*Double.pi/Double(count)
        let angle=(atan2(Double(dx),Double(dy))+step/2+2*Double.pi).truncatingRemainder(dividingBy:2*Double.pi)
        return Int(angle/step)%count
    }
    override func draw(_ rect:NSRect) {
        let center=NSPoint(x:bounds.midX,y:bounds.midY)
        NSColor.windowBackgroundColor.withAlphaComponent(0.98).setFill();NSBezierPath(ovalIn:bounds.insetBy(dx:4,dy:4)).fill()
        if count>0 {
            let step=360.0/Double(count)
            for i in 0..<count {
                let angle=90-Double(i)*step,p=NSBezierPath()
                p.appendArc(withCenter:center,radius:190,startAngle:CGFloat(angle+step/2-1.5),endAngle:CGFloat(angle-step/2+1.5),clockwise:true)
                p.appendArc(withCenter:center,radius:72,startAngle:CGFloat(angle-step/2+1.5),endAngle:CGFloat(angle+step/2-1.5),clockwise:false);p.close()
                (selected==i ? Studio.accent:NSColor.controlBackgroundColor).setFill();p.fill()
                let title=i<actions.count ? actions[i].title : "Altri…"
                let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center;paragraph.lineBreakMode = .byWordWrapping
                let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:title.count>14 ? 11:15,weight:.semibold),.foregroundColor:selected==i ? NSColor.white:NSColor.labelColor,.paragraphStyle:paragraph]
                let r=angle*Double.pi/180
                (title as NSString).draw(in:NSRect(x:center.x+cos(r)*133-48,y:center.y+sin(r)*133-24,width:96,height:48),withAttributes:attrs)
            }
        }
        if selected == -1 {Studio.accent.withAlphaComponent(0.3).setFill();NSBezierPath(ovalIn:NSRect(x:center.x-63,y:center.y-63,width:126,height:126)).fill()}
        let labels=[(title,center.y+8,12.0),(urls.isEmpty ? "Trascina qui" : "\(urls.count) file",center.y-12,11.0),(mode=="actions" ? "Scaffale" : "Studio",center.y-30,10.0)]
        for (text,y,size) in labels {
            let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:size,weight:.medium),.foregroundColor:NSColor.labelColor]
            let s=(text as NSString).size(withAttributes:attrs);(text as NSString).draw(at:NSPoint(x:center.x-s.width/2,y:y),withAttributes:attrs)
        }
    }
    func update(_ sender:NSDraggingInfo)->NSDragOperation {
        let newURLs=fileURLs(sender.draggingPasteboard)
        if newURLs != urls {urls=newURLs;refresh()}
        selected=sector(convert(sender.draggingLocation,from:nil));needsDisplay=true
        return !urls.isEmpty && selected != nil ? .copy:[]
    }
    func refresh() {let all=Model.shared.available(urls,mode:mode);more=all.count>8;actions=Array(all.prefix(more ? 7:8));needsDisplay=true}
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {update(sender)}
    override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation {update(sender)}
    override func draggingExited(_ sender:NSDraggingInfo?) {selected=nil;needsDisplay=true}
    override func prepareForDragOperation(_ sender:NSDraggingInfo)->Bool {update(sender) == .copy}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        _=update(sender);guard let index=selected else{return false}
        if index == -1 && mode=="actions" {drop?(urls,Model.shared.actions.first{$0.id=="native.float"})}
        else {drop?(urls,index>=0 && index<actions.count ? actions[index]:nil)}
        return true
    }
}
