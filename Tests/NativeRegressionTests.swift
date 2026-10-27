import AppKit

@main struct NativeRegressionTests {
    static func main() throws {
        _=NSApplication.shared
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        Model.shared.actions=try JSONDecoder().decode([Action].self,from:Data(contentsOf:root.appendingPathComponent("Engine/actions.json")))
        let studio=Studio();let png=URL(fileURLWithPath:"/tmp/orbita-test.png")
        studio.urls=[png];studio.mode.selectedSegment=1;studio.refresh(preferred:"image.resize")
        studio.inputs["width"]?.stringValue="640"
        studio.refresh(preferred:"image.crop")
        assert(studio.selected?.id=="image.crop")
        studio.refresh(preferred:"image.resize")
        assert(studio.inputs["width"]?.stringValue=="640")
        print("PASS tool selection and draft preservation")
        studio.search.stringValue="does-not-exist";studio.refresh();assert(studio.selected==nil && !studio.go.isEnabled)
        studio.search.stringValue="";studio.refresh();assert(studio.selected != nil)
        print("PASS empty search clears executable selection")
        for size in [NSSize(width:880,height:640),NSSize(width:1020,height:720),NSSize(width:1300,height:900)] {
            studio.window.setContentSize(size);studio.refresh(preferred:"image.crop");studio.window.contentView?.layoutSubtreeIfNeeded()
            assert(studio.previewCard.frame.height>=169)
            assert(studio.formCard.frame.maxY<=studio.previewCard.frame.minY)
            assert(studio.go.frame.width>=128)
            for input in studio.inputs.values {assert(input.frame.width>=79)}
        }
        print("PASS responsive layout at three window sizes")
        studio.setBusy(true) // Reads shared state intentionally; set state to exercise all controls.
        Model.shared.busy=true;studio.setBusy(true)
        assert(!studio.go.isEnabled && !studio.search.isEnabled && !studio.choose.isEnabled)
        Model.shared.busy=false;studio.setBusy(false)
        print("PASS controls locked during execution")
        let sentinel=URL(fileURLWithPath:"/tmp/last-real-result.png")
        Model.shared.results=[sentinel]
        var callback=false
        Model.shared.run(Model.shared.actions[0],urls:[png],params:[:],recordResults:false) { result,error in
            callback=true;assert(error != nil && !error!.isEmpty)
        }
        // Tests run outside an app bundle: missing runtime is a deliberate launch-failure fixture.
        assert(callback && !Model.shared.busy && Model.shared.results==[sentinel])
        let unstarted=Process();Model.shared.process=unstarted;Model.shared.cancel();Model.shared.process=nil
        print("PASS failed launch callback, state cleanup and safe early cancel")
        var tracker=StableFileTracker();let stamp=FileStamp(size:10,modified:Date(timeIntervalSince1970:1));let t=Date(timeIntervalSince1970:100)
        assert(!tracker.ready("file",stamp:stamp,now:t))
        assert(!tracker.ready("file",stamp:stamp,now:t.addingTimeInterval(3.99)))
        assert(tracker.ready("file",stamp:stamp,now:t.addingTimeInterval(4.01)))
        let modified=FileStamp(size:10,modified:Date(timeIntervalSince1970:2))
        assert(!tracker.ready("file",stamp:modified,now:t.addingTimeInterval(5)))
        print("PASS watcher timer jitter and same-size modifications")
        let flags:NSEvent.ModifierFlags=[.shift,.option]
        assert(flags.contains([.shift,.option]) && !NSEvent.ModifierFlags.shift.contains([.shift,.option]))
        print("PASS Shift+Option activation condition")
        studio.window.close()
        let rename=Model.shared.actions.first{$0.id=="files.renameOriginals"}!
        let convert=Model.shared.actions.first{$0.id=="document.to.pdf"}!
        assert(!requiresAppleExport(rename) && requiresAppleExport(convert))
        print("PASS Apple file actions preserve original file identity")
        print("PASS all native regressions")
    }
}
