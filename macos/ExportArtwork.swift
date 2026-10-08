import AppKit
import ImageIO
import UniformTypeIdentifiers

// The same source image, geometry and groove/lighting separation as native/Artwork.cs.
// Generate the layers on the build machine; no pre-exported Windows artifacts are needed.
@main struct ExportArtwork {
    static let colorSpace = CGColorSpaceCreateDeviceRGB()
    static let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    static func clamp(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double { min(upper,max(lower,value)) }
    static func smooth(_ value: Double) -> Double { let v = clamp(value); return v*v*(3-2*v) }
    static func byte(_ value: Double) -> UInt8 { UInt8(clamp(value.rounded(),0,255)) }
    static func pixels(_ image: CGImage, width: Int, height: Int, disc: Bool = false) -> [UInt8] {
        var bytes = [UInt8](repeating:0,count:width*height*4)
        bytes.withUnsafeMutableBytes { data in
            let context = CGContext(data:data.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:colorSpace,bitmapInfo:bitmapInfo)!
            // Quartz bitmap rows and CGImage cropping both use the source's top-to-bottom pixel order.
            if disc { context.addEllipse(in:CGRect(x:0,y:0,width:width,height:height)); context.clip() }
            context.interpolationQuality = .high; context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        }
        // Work in straight alpha, matching WPF's Bgra32 arithmetic.
        for i in stride(from:0,to:bytes.count,by:4) where bytes[i+3] > 0 && bytes[i+3] < 255 {
            let alpha = Double(bytes[i+3])/255
            for c in 0..<3 { bytes[i+c] = byte(Double(bytes[i+c])/alpha) }
        }
        return bytes
    }
    static func write(_ bytes: [UInt8], width: Int, height: Int, to url: URL) throws {
        let data = Data(bytes) as CFData
        let provider = CGDataProvider(data:data)!
        let image = CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:colorSpace,
                            bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw CocoaError(.fileReadInvalidFileName) }
        let input = URL(fileURLWithPath:CommandLine.arguments[1]), output = URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
        guard let source = CGImageSourceCreateWithURL(input as CFURL,nil), let image = CGImageSourceCreateImageAtIndex(source,0,nil), image.width == 1536, image.height == 1024 else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let width = image.width, height = image.height
        var body = pixels(image,width:width,height:height), arm = [UInt8](repeating:0,count:width*height*4)
        let plinth = CGMutablePath()
        plinth.move(to:CGPoint(x:157,y:66)); plinth.addLine(to:CGPoint(x:1362,y:66)); plinth.addQuadCurve(to:CGPoint(x:1469,y:175),control:CGPoint(x:1469,y:66))
        plinth.addLine(to:CGPoint(x:1469,y:850)); plinth.addQuadCurve(to:CGPoint(x:1364,y:958),control:CGPoint(x:1469,y:958))
        plinth.addLine(to:CGPoint(x:158,y:958)); plinth.addQuadCurve(to:CGPoint(x:61,y:852),control:CGPoint(x:61,y:958))
        plinth.addLine(to:CGPoint(x:61,y:172)); plinth.addQuadCurve(to:CGPoint(x:157,y:66),control:CGPoint(x:61,y:66)); plinth.closeSubpath()
        let inner = CGMutablePath()
        inner.move(to:CGPoint(x:165,y:111)); inner.addLine(to:CGPoint(x:1358,y:111)); inner.addQuadCurve(to:CGPoint(x:1429,y:184),control:CGPoint(x:1429,y:111))
        inner.addLine(to:CGPoint(x:1429,y:845)); inner.addQuadCurve(to:CGPoint(x:1358,y:920),control:CGPoint(x:1429,y:920))
        inner.addLine(to:CGPoint(x:166,y:920)); inner.addQuadCurve(to:CGPoint(x:104,y:843),control:CGPoint(x:104,y:920))
        inner.addLine(to:CGPoint(x:104,y:187)); inner.addQuadCurve(to:CGPoint(x:165,y:111),control:CGPoint(x:104,y:111)); inner.closeSubpath()
        let cartridge = CGMutablePath(); cartridge.move(to:CGPoint(x:1098,y:665)); cartridge.addLine(to:CGPoint(x:1182,y:701)); cartridge.addLine(to:CGPoint(x:1118,y:821)); cartridge.addLine(to:CGPoint(x:1010,y:772)); cartridge.closeSubpath()
        let hardware = CGMutablePath(); hardware.addRect(CGRect(x:1245,y:83,width:113,height:107)); hardware.addEllipse(in:CGRect(x:1163,y:179,width:234,height:234)); hardware.addPath(cartridge)
        let tube = CGMutablePath(); tube.move(to:CGPoint(x:1293,y:172)); tube.addLine(to:CGPoint(x:1287,y:466)); tube.addCurve(to:CGPoint(x:1117,y:738),control1:CGPoint(x:1295,y:602),control2:CGPoint(x:1260,y:674))
        tube.move(to:CGPoint(x:1340,y:332)); tube.addLine(to:CGPoint(x:1427,y:421)); tube.move(to:CGPoint(x:1109,y:771)); tube.addLine(to:CGPoint(x:1157,y:818))
        let moving = CGMutablePath(); moving.move(to:CGPoint(x:1287,y:351)); moving.addLine(to:CGPoint(x:1287,y:466)); moving.addCurve(to:CGPoint(x:1117,y:738),control1:CGPoint(x:1295,y:602),control2:CGPoint(x:1260,y:674))
        moving.move(to:CGPoint(x:1109,y:771)); moving.addLine(to:CGPoint(x:1157,y:818))
        let tubeArea = tube.copy(strokingWithWidth:35,lineCap:.butt,lineJoin:.miter,miterLimit:10)
        let movingArea = moving.copy(strokingWithWidth:35,lineCap:.butt,lineJoin:.miter,miterLimit:10)
        for y in 0..<height { for x in 0..<width {
            let i = (y*width+x)*4, point = CGPoint(x:x,y:y)
            let instrument = x > 980 && (hardware.contains(point) || tubeArea.contains(point))
            let record = pow((Double(x)-664)/463,2) + pow((Double(y)-487)/444,2) < 1
            if (record || !plinth.contains(point)) && !instrument { body[i+3] = 0; continue }
            let value = Double(max(body[i],max(body[i+1],body[i+2])))
            var alpha: Double
            if instrument { alpha = clamp((value-5)/24) }
            else {
                alpha = max(0,(value-3)/252)
                if alpha > 0 { for c in 0..<3 { body[i+c] = UInt8(min(255,Double(body[i+c])/alpha)) } }
                if inner.contains(point) { alpha *= 0.32 }
            }
            body[i+3] = byte(alpha*255)
            if instrument && y >= 351 && (movingArea.contains(point) || cartridge.contains(point)) {
                for c in 0..<4 { arm[i+c] = body[i+c] }; body[i+3] = 0
            }
        } }
        guard let crop = image.cropping(to:CGRect(x:201,y:43,width:926,height:888)) else { throw CocoaError(.fileReadCorruptFile) }
        var highlights = pixels(crop,width:540,height:540,disc:true)
        let unpatched = highlights
        for y in 0..<540 { for x in 0..<540 {
            let angle = atan2(Double(y)-269.5,Double(x)-269.5)*180 / .pi, radius = hypot(Double(x)-269.5,Double(y)-269.5)
            let blend = smooth((angle-18)/14)*smooth((70-angle)/14)*smooth((radius-228)/20)
            if blend <= 0 { continue }
            let i = (y*540+x)*4, opposite = ((539-y)*540+539-x)*4
            for c in 0..<3 { highlights[i+c] = byte(Double(unpatched[i+c])*(1-blend)+Double(unpatched[opposite+c])*blend) }
        } }
        var surface = highlights, sum = [Double](repeating:0,count:541*541), weight = [Int](repeating:0,count:541*541)
        for y in 0..<540 { for x in 0..<540 {
            let i = (y*540+x)*4, k = (y+1)*541+x+1, valid = highlights[i+3] > 0 ? 1 : 0
            let luminance = (Double(highlights[i])+Double(highlights[i+1])+Double(highlights[i+2]))/3
            sum[k] = luminance*Double(valid)+sum[k-1]+sum[k-541]-sum[k-542]
            weight[k] = valid+weight[k-1]+weight[k-541]-weight[k-542]
        } }
        for y in 0..<540 { for x in 0..<540 {
            let i = (y*540+x)*4, radius = hypot(Double(x)-270,Double(y)-270)
            let value = (Double(highlights[i])+Double(highlights[i+1])+Double(highlights[i+2]))/3
            let left = max(0,x-22), right = min(540,x+23), top = max(0,y-22), bottom = min(540,y+23)
            let a = top*541+left, b = top*541+right, c = bottom*541+left, d = bottom*541+right
            let broad = (sum[d]-sum[b]-sum[c]+sum[a])/Double(max(1,weight[d]-weight[b]-weight[c]+weight[a]))
            let blend = clamp((radius-100)/15)*clamp((269-radius)/3), groove = clamp(18+(value-broad)*0.65,8,58)
            for channel in 0..<3 { surface[i+channel] = byte(Double(surface[i+channel])*(1-blend)+groove*blend) }
            let edge = clamp((radius-100)/20)*clamp((269-radius)/10), alpha = highlights[i+3]
            highlights[i] = 235; highlights[i+1] = 235; highlights[i+2] = 235
            highlights[i+3] = UInt8(alpha == 0 ? 0 : clamp((broad-14)*0.35,0,44)*edge)
        } }
        try write(body,width:width,height:height,to:output.appendingPathComponent("body.png"))
        try write(arm,width:width,height:height,to:output.appendingPathComponent("tonearm.png"))
        try write(surface,width:540,height:540,to:output.appendingPathComponent("record.png"))
        try write(highlights,width:540,height:540,to:output.appendingPathComponent("highlights.png"))
    }
}
