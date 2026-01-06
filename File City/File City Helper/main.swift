import Foundation

let listener = NSXPCListener(machServiceName: PrivilegedHelper.machServiceName)
let helper = PrivilegedHelperService()
listener.delegate = helper
listener.resume()
RunLoop.main.run()
