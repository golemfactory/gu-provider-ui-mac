import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusBarMenu: NSMenu!
    let statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    let localServerAddress = "http://127.0.0.1:61621/status?timeout=9"
    let serverFileLocation = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/gu-provider")
    var serverProcessHandle: Process?
    var localServerRequestTimer: Timer?

    struct ServerResponse: Decodable {
        let envs: [String:String]
    }
    
    @objc func updateServerStatus() {
        URLSession.shared.dataTask(with: URL(string:localServerAddress)!) { (data, res, err) in
            if (data == nil) { return }
            do {
                let json = try JSONDecoder().decode(ServerResponse.self, from:data!)
                let status = json.envs["hostDirect"] ?? "Error"
                NSLog("Server status: " + status + ".")
                self.setMenuBarText(text: status)
            } catch {
                NSLog("Cannot get server status.")
            }
        }.resume()
    }

    func launchServerPolling() {
        localServerRequestTimer = Timer.scheduledTimer(timeInterval: 10, target: self,
                                                       selector: #selector(updateServerStatus), userInfo: nil, repeats: true)
    }
    
    func launchServer() {
        do {
            serverProcessHandle = try Process.run(serverFileLocation, arguments: ["server"]) { (process) in
                NSLog("Process ended: " + self.serverFileLocation.absoluteString)
                self.setMenuBarText(text: "Error.")
            }
            setMenuBarText(text: "Loading...")
            Timer.scheduledTimer(timeInterval: 2, target: self,
                                 selector: #selector(updateServerStatus), userInfo: nil, repeats: false)
        } catch {
            NSLog(error.localizedDescription)
            setMenuBarText(text: "Error")
        }
    }

    func setMenuBarText(text: String) {
        DispatchQueue.main.async {
            self.statusBarItem.button!.title = "GU:  " + text + "  "
        }
    }
    
    func addStatusBarMenu() {
        setMenuBarText(text: "Loading...")
        statusBarItem.button?.image = NSImage.init(named: "GolemMenuIcon")
        statusBarItem.button?.image?.isTemplate = true
        statusBarItem.button?.imagePosition = NSControl.ImagePosition.imageLeft
        statusBarItem.menu = statusBarMenu
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        addStatusBarMenu()
        launchServer()
        launchServerPolling()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        localServerRequestTimer?.invalidate()
        serverProcessHandle?.terminate()
    }

    @IBAction func quitApp(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }

}
