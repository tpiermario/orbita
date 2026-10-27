import Foundation
import Darwin
import Vision
import AppKit
@main struct VisionCLI {
    static func main() {
        let resultFD=dup(STDOUT_FILENO)
        dup2(STDERR_FILENO,STDOUT_FILENO)
        do {
            guard CommandLine.arguments.count==3 else { throw NSError(domain:"Orbita",code:1) }
            let mode=CommandLine.arguments[1], url=URL(fileURLWithPath:CommandLine.arguments[2])
            let handler=VNImageRequestHandler(url:url,options:[:]);var values:[[String:Any]]=[]
            func rect(_ r:CGRect)->[Double] { [r.minX,1-r.maxY,r.width,r.height].map(Double.init) }
            if mode=="faces" {
                let request=VNDetectFaceRectanglesRequest();try handler.perform([request])
                values=(request.results ?? []).map { ["text":"face","rect":rect($0.boundingBox)] }
            } else if mode=="qr" {
                let request=VNDetectBarcodesRequest();try handler.perform([request])
                values=(request.results ?? []).map { ["text":$0.payloadStringValue ?? "","rect":rect($0.boundingBox)] }
            } else {
                let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.usesLanguageCorrection=true
                request.recognitionLanguages=["it-IT","en-US"]
                try handler.perform([request]);values=(request.results ?? []).map { ["text":$0.topCandidates(1).first?.string ?? "","rect":rect($0.boundingBox)] }
            }
            let data=try JSONSerialization.data(withJSONObject:values);FileHandle(fileDescriptor:resultFD).write(data)
        } catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8));exit(1) }
    }
}
