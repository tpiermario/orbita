import Foundation
import CoreImage
import ImageIO
let filter=CIFilter(name:"CIQRCodeGenerator")!
filter.setValue(Data("Orbita QR verification 2026".utf8),forKey:"inputMessage")
filter.setValue("M",forKey:"inputCorrectionLevel")
let image=filter.outputImage!.transformed(by:CGAffineTransform(scaleX:10,y:10))
let cg=CIContext().createCGImage(image,from:image.extent)!
let dest=CGImageDestinationCreateWithURL(URL(fileURLWithPath:CommandLine.arguments[1]) as CFURL,"public.png" as CFString,1,nil)!
CGImageDestinationAddImage(dest,cg,nil)
assert(CGImageDestinationFinalize(dest))
