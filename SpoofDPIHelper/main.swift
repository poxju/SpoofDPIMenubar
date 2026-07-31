import Foundation

let delegate = HelperXPCDelegate()
let listener = NSXPCListener(machServiceName: "com.spoofdpi.menubar.helper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
