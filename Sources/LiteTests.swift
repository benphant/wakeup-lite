import AppKit

@MainActor enum LiteTests {
    static func run() throws {
        var checks=0
        func check(_ ok:Bool,_ message:String)throws { guard ok else { throw NSError(domain:"LiteTests",code:1,userInfo:[NSLocalizedDescriptionKey:message]) };checks+=1 }
        for battery in [true,false] { for enabled in [true,false] { for p:Int? in [nil,-1,0,9,10,20,100,101] {
            let expected=battery && enabled && p.map{(0..<10).contains($0)} == true
            try check(Battery(onBattery:battery,percent:p).shouldStop(enabled:enabled)==expected,"battery threshold matrix")
        } } }
        var sample=Battery(onBattery:true,percent:20)
        let model=LiteModel(runTimer:false,battery:{sample})
        defer { model.stop() }
        model.toggle()
        try check(model.awake && model.power.active,"actual power assertion acquired")
        model.displayOn=true;try check(model.awake && model.power.active,"display control independent")
        model.displayOn=false;try check(model.power.active,"display release keeps system assertion")
        sample=Battery(onBattery:true,percent:10);model.poll();try check(model.awake,"10 percent continues")
        sample=Battery(onBattery:true,percent:9);model.poll();try check(!model.awake && !model.power.active,"9 percent releases actual assertion")
        model.toggle();try check(!model.awake,"low battery start rejected")
        sample=Battery(onBattery:false,percent:9);model.toggle();try check(model.awake,"external power low battery allowed")
        sample=Battery(onBattery:true,percent:9);model.poll()
        try check(!model.awake && !model.power.active,"unplugging below threshold releases assertion")
        model.lowBattery=false;model.toggle();try check(model.awake,"protection disabled allows low battery")
        model.lowBattery=true;try check(!model.awake,"enabling protection immediately checks battery")
        sample=Battery(onBattery:true,percent:nil);model.toggle();try check(model.awake,"unknown battery does not mean zero")
        model.stop();try check(!model.power.active,"manual end releases")
        print("PASS: \(checks) lite checks, including real power assertion lifecycle; no global sleep settings changed")
    }
}
