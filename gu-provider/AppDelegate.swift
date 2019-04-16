import Cocoa

struct NodeInfo: Decodable {
    var name: String
    var address: String
    var description: String
    enum CodingKeys: String, CodingKey {
        case name = "Host name", address = "Addresses", description = "Description"
    }
    func nodeId() -> String? {
        let parts = description.split(separator: "=")
        if parts.count < 1 { return nil } else { return String(parts[1]) }
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDelegate, NSTableViewDataSource {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var addHubPanel: NSPanel!
    @IBOutlet weak var statusBarMenu: NSMenu!
    @IBOutlet weak var autoModeButton: NSButton!
    @IBOutlet weak var hubListTable: NSTableView!
    @IBOutlet weak var hubIP: NSTextField!
    @IBOutlet weak var hubPort: NSTextField!

    let statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    let localServerAddress = "http://127.0.0.1:61621/"
    let serverFileLocation = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/gu-provider")
    var serverProcessHandle: Process?
    var localServerRequestTimer: Timer?

    var nodes: [NodeInfo] = []
    var nodeSelected: [Bool] = []
    
    struct ServerResponse: Decodable {
        let envs: [String:String]
    }

    @objc func updateServerStatus() {
        URLSession.shared.dataTask(with: URL(string:localServerAddress+"status?timeout=9")!) { (data, res, err) in
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
            //self.statusBarItem.button!.title = "GU:  " + text + "  "
        }
    }
    
    func addStatusBarMenu() {
        setMenuBarText(text: "Loading...")
        statusBarItem.button?.image = NSImage.init(named: "GolemMenuIcon")
        statusBarItem.button?.image?.isTemplate = true
        statusBarItem.button?.imagePosition = NSControl.ImagePosition.imageLeft
        statusBarItem.menu = statusBarMenu
    }
    
    @IBAction func showConfigurationWindow(_ sender: Any) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(self)
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableColumn?.identifier.rawValue != "Selected" {
            let cell = tableView.makeView(withIdentifier:NSUserInterfaceItemIdentifier(tableColumn!.identifier.rawValue + ""), owner: nil) as! NSTableCellView
            let node = nodes[row]
            cell.textField?.stringValue = ["", node.name, node.address, node.address][tableView.tableColumns.firstIndex(of: tableColumn!)!]
            return cell
        } else {
            let cell = tableView.makeView(withIdentifier:NSUserInterfaceItemIdentifier("Selected"), owner: nil) as! NSTableCellView
            (cell.viewWithTag(100) as! NSButton).action = #selector(AppDelegate.checkBoxPressed)
            (cell.viewWithTag(100) as! NSButton).state = nodeSelected[row] ? .on : .off
            return cell
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return nodes.count
    }
    
    func getProviderOutput(arguments: [String]) -> Data? {
        NSLog("%@", arguments.joined(separator: "/"))
        let providerProcess = Process()
        // TODO
        providerProcess.launchPath = "/Users/dev/.cargo/bin/gu-provider"
        //providerProcess.launchPath = "/Users/user/Documents/golem-unlimited/target/debug/gu-provider"
        if !FileManager.default.isExecutableFile(atPath: providerProcess.launchPath!) {
            showError(message: "Error: " + providerProcess.launchPath! + " not found.")
            return nil
        }
        providerProcess.arguments = arguments
        let pipe = Pipe()
        providerProcess.standardOutput = pipe
        providerProcess.standardError = pipe
        providerProcess.launch()
        NSLog("-->")
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        providerProcess.waitUntilExit()
        NSLog("-->OK %@", String(data: data, encoding: .utf8)!)
        //let sys = String(data: retData, encoding: .utf8)
        return data
    }
    
    func dataToBool(data: Data) -> Bool? { return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespaces).lowercased() == "true" }
    
    func reloadHubList() {
        let auto = getProviderOutput(arguments: ["configure", "-g", "auto"]) ?? "false".data(using: .utf8, allowLossyConversion: false)!
        autoModeButton.state = (dataToBool(data: auto) ?? false) ? .on : .off
        let data = getProviderOutput(arguments: ["--json", "lan", "list", "-I", "hub"]) ?? "[]".data(using: .utf8, allowLossyConversion: false)!
        nodes = try! JSONDecoder().decode([NodeInfo].self, from: data)
        nodeSelected = []
        for node in nodes {
            nodeSelected.append(dataToBool(data: getProviderOutput(arguments: ["configure", "-g", node.nodeId()!])!) ?? false)
        }
        hubListTable.reloadData()
    }
    
    @objc func checkBoxPressed(sender: NSButton) {
        let row = hubListTable.row(for:sender)
        let _ = getProviderOutput(arguments: ["configure", sender.state == .on ? "-a" : "-d", nodes[row].nodeId() ?? "", nodes[row].address, nodes[row].name])
        let _ = getProviderOutput(arguments: ["hubs", sender.state == .on ? "connect" : "disconnect", nodes[row].address])
    }
	
    @IBAction func addHubPressed(_ sender: NSButton) {
        addHubPanel.makeKeyAndOrderFront(self)
    }
    
    @IBAction func refreshPressed(_ sender: NSButton) {
        reloadHubList()
    }
    
    @IBAction func autoConnectPressed(_ sender: NSButton) {
        let _ = getProviderOutput(arguments: ["configure", sender.state == .on ? "-A" : "-D"])
        let _ = getProviderOutput(arguments: ["hubs", sender.state == .on ? "auto" : "manual"])
    }

    func showError(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @IBAction func addEnteredHub(_ sender: NSButton) {
        let ipPort = hubIP.stringValue + ":" + hubPort.stringValue
        // TODO check IP
        let urlString = "http://" + ipPort + "/node_id/"
        URLSession.shared.dataTask(with: URL(string: urlString)!) { (data, res, err) in
            if data == nil || err != nil { self.showError(message: "Cannot connect to " + urlString); return }
            let nodeIdAndHostName = String(data: data!, encoding: .utf8)!.split(separator: " ")
            if nodeIdAndHostName.count != 2 || (res as! HTTPURLResponse).statusCode != 200 {
                self.showError(message: "Bad answer from " + urlString + ".")
                return
            }
            let args = ["configure", "-a", String(nodeIdAndHostName[0]), ipPort, String(nodeIdAndHostName[1])]
            let _ = self.getProviderOutput(arguments: args)
            DispatchQueue.main.async {
                self.reloadHubList()
                self.addHubPanel.orderOut(self)
            }
        }.resume()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        addHubPanel.isFloatingPanel = true
        addStatusBarMenu()
        launchServerPolling()
        reloadHubList()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        localServerRequestTimer?.invalidate()
        serverProcessHandle?.terminate()
    }

    @IBAction func quitApp(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }

}
