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

struct SavedNodeInfo: Decodable {
    var name: String
    var address: String
    var nodeId: String
    enum CodingKeys: String, CodingKey {
        case name = "host_name", address, nodeId = "node_id"
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
    let unixSocketPath = "/tmp/gu-provider.socket"
    var serverProcessHandle: Process?
    var localServerRequestTimer: Timer?

    var nodes: [NodeInfo] = []
    var nodeSelected: [Bool] = []

    struct ServerResponse: Decodable {
        let envs: [String:String]
    }

    func isServerReady() -> Bool {
        let status = getHTTPBodyFromUnixSocket(path: unixSocketPath, query: "/status?timeout=5")
        if status == nil { return false }
        do {
            let json = try JSONDecoder().decode(ServerResponse.self, from:status!.data(using: .utf8)!)
            let status = json.envs["hostDirect"] ?? "Error"
            return status == "Ready"
        } catch {
            return false
        }

    }

    @objc func updateServerStatus() {
        self.setMenuBarText(text: isServerReady() ? "" : "!");
    }

    func requestHTTPFromUnixSocket(path: String, method: String, query: String) -> String? {
        do {
            let socket = try Socket.create(family: .unix, type: Socket.SocketType.stream, proto: .unix)
            try socket.connect(to: path)
            try socket.write(from: method + " " + query + " HTTP/1.0\r\n\r\n")
            var result = ""
            while true {
                let str = try? socket.readString()
                if str == nil || str! == nil { break } else { result += str!! }
            }
            socket.close()
            return result
        } catch {
            return nil
        }
    }

    func getHTTPBodyFromUnixSocket(path: String, query: String) -> String? {
        let response = requestHTTPFromUnixSocket(path: path, method: "GET", query: query)
        if response == nil { return nil }
        let body = response!.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
        return body
    }

    func launchServerPolling() {
        localServerRequestTimer = Timer.scheduledTimer(timeInterval: 10, target: self,
                                                       selector: #selector(updateServerStatus), userInfo: nil, repeats: true)
    }

    func setMenuBarText(text: String) {
        DispatchQueue.main.async {
            self.statusBarItem.button!.title = text
        }
    }

    func addStatusBarMenu() {
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
        let providerProcess = Process()
        providerProcess.launchPath = "/bin/bash"
        providerProcess.arguments = ["-lc", "gu-provider " + arguments.joined(separator: " ")]
        let pipe = Pipe()
        providerProcess.standardOutput = pipe
        providerProcess.standardError = nil
        providerProcess.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        providerProcess.waitUntilExit()
        return data
    }

    func dataToBool(data: Data) -> Bool? { return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespaces).lowercased() == "true" }

    func reloadHubList() {
        let auto = getProviderOutput(arguments: ["configure", "-g", "auto"]) ?? "false".data(using: .utf8, allowLossyConversion: false)!
        autoModeButton.state = (dataToBool(data: auto) ?? false) ? .on : .off
        var all: Set<String> = []
        let data = getProviderOutput(arguments: ["--json", "lan", "list", "-I", "hub"]) ?? "[]".data(using: .utf8, allowLossyConversion: false)!
        nodes = try! JSONDecoder().decode([NodeInfo].self, from: data)
        nodeSelected = []
        for node in nodes {
            nodeSelected.append(dataToBool(data: getProviderOutput(arguments: ["configure", "-g", node.nodeId()!])!) ?? false)
            all.insert(node.nodeId()!)
        }
        let saved_nodes_data = getProviderOutput(arguments: ["configure", "-l"]) ?? "[]".data(using: .utf8, allowLossyConversion: false)!
        let saved_nodes = try! JSONDecoder().decode([SavedNodeInfo].self, from: saved_nodes_data)
        for node in saved_nodes {
            if !all.contains(node.nodeId) {
                nodes.append(NodeInfo(name: node.name, address: node.address, description: "node_id=" + node.nodeId))
                nodeSelected.append(dataToBool(data: getProviderOutput(arguments: ["configure", "-g", node.nodeId])!) ?? false)
                all.insert(node.nodeId)
            }
        }
        hubListTable.reloadData()
    }

    @objc func checkBoxPressed(sender: NSButton) {
        let row = hubListTable.row(for:sender)
        let _ = getProviderOutput(arguments: ["configure", sender.state == .on ? "-a" : "-d", nodes[row].nodeId() ?? "_", nodes[row].address,
                                              nodes[row].name.replacingOccurrences(of: " ", with: "_")])
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
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @IBAction func addEnteredHub(_ sender: NSButton) {
        let ipPort = hubIP.stringValue + ":" + hubPort.stringValue
        // TODO check IP
        let urlString = "http://" + ipPort + "/node_id/"
        URLSession.shared.dataTask(with: URL(string: urlString)!) { (data, res, err) in
            if data == nil || err != nil { self.showError(message: "Cannot connect to " + ipPort); return }
            let nodeIdAndHostName = String(data: data!, encoding: .utf8)!.split(separator: " ")
            if nodeIdAndHostName.count != 2 || (res as! HTTPURLResponse).statusCode != 200 {
                self.showError(message: "Bad answer from " + urlString + ".")
                return
            }
            let args = ["configure", "-a", String(nodeIdAndHostName[0]), ipPort, String(nodeIdAndHostName[1])]
            let _ = self.getProviderOutput(arguments: args)
            DispatchQueue.main.async {
                self.reloadHubList()
                self.hubIP.stringValue = ""
                self.addHubPanel.orderOut(self)
            }
        }.resume()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        addHubPanel.isFloatingPanel = true
        addStatusBarMenu()
        launchServerPolling()
        reloadHubList()
        if !UserDefaults.standard.bool(forKey: "firstRun") {
            UserDefaults.standard.set(true, forKey: "firstRun")
            showConfigurationWindow(self)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        localServerRequestTimer?.invalidate()
        serverProcessHandle?.terminate()
    }

    @IBAction func quitApp(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }

}
