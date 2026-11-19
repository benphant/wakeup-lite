import AppKit

let destination = CommandLine.arguments[1]
let set = URL(fileURLWithPath: destination).appendingPathExtension("iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
let sizes = [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),
             ("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),
             ("icon_512x512",512),("icon_512x512@2x",1024)]
for (name, size) in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size)
    func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(calibratedWhite: white, alpha: alpha)
    }
    let tile = NSBezierPath(roundedRect: NSRect(x:s*0.08,y:s*0.08,width:s*0.84,height:s*0.84), xRadius:s*0.22,yRadius:s*0.22)
    NSGradient(starting: gray(0.99), ending: gray(0.77))?.draw(in: tile, angle: -90)
    gray(1, 0.85).setStroke(); tile.lineWidth = s*0.014; tile.stroke()
    let ring = NSBezierPath(ovalIn: NSRect(x:s*0.285,y:s*0.285,width:s*0.43,height:s*0.43))
    gray(0.96, 0.6).setFill(); ring.fill()
    gray(0.49).setStroke(); ring.lineWidth = s*0.05; ring.stroke()
    let power = NSBezierPath()
    let center = NSPoint(x:s*0.5,y:s*0.49)
    power.appendArc(withCenter: center, radius:s*0.101, startAngle:129, endAngle:51, clockwise:false)
    power.move(to:NSPoint(x:s*0.5,y:s*0.50))
    power.line(to:NSPoint(x:s*0.5,y:s*0.615))
    power.lineCapStyle = .round; power.lineWidth = s*0.04
    gray(0.35).setStroke(); power.stroke()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
    try bitmap.representation(using:.png,properties:[:])!.write(to:set.appendingPathComponent(name+".png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath:"/usr/bin/iconutil")
task.arguments = ["-c","icns",set.path,"-o",destination+".icns"]
try task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(1) }
try FileManager.default.removeItem(at:set)
