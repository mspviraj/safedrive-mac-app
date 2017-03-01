//
//  OpenFileWarningWindowController.swift
//  SafeDrive
//
//  Created by steve on 2/21/17.
//  Copyright © 2017 Infincia LLC. All rights reserved.
//

import Cocoa

protocol OpenFileWarningDelegate: class {
    func closeApplication(_ process: RunningProcess)
    func runningProcesses(success: @escaping ([RunningProcess]) -> Void)
    func blockingProcesses(_ url: URL,success: @escaping ([RunningProcess]) -> Void)
    func tryAgain()
    func finished()
}

protocol OpenFileReactor: class {
    func didTerminate(_ notification: Notification)
}

extension OpenFileWarningWindowController: OpenFileReactor {
    func didTerminate(_ notification: Notification) {
        if let userInfo = notification.userInfo,
            let app = userInfo[NSWorkspaceApplicationKey] as? NSRunningApplication {
            
            let pid = app.processIdentifier
            let index = self.processes.index(where: { (process) -> Bool in
                process.pid == Int(pid)
            })
            if let i = index {
                self.processes.remove(at: i)
                self.processList.reloadData()
            }
        }
    }
}

extension OpenFileWarningWindowController: NSTableViewDataSource {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0 else {
            return nil
        }
        
        let view = tableView.make(withIdentifier: "OpenFileWarningTableCellView", owner: self) as! OpenFileWarningTableCellView
        
        let process = self.processes[row]
        
        view.name.stringValue = process.command
        view.processName = process.command
        view.processPID = process.pid
        view.closeApp.tag = process.pid
        
        view.icon.image = process.icon
        
        return view
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.processes.count
    }
    
    func numberOfSections(in tableView: NSTableView) -> Int {
        return 1
    }
}

extension OpenFileWarningWindowController:  NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        let sessionIndex = processList.selectedRow
        
        guard let _ = processList.view(atColumn: 0, row: sessionIndex, makeIfNecessary: false) as? OpenFileWarningTableCellView else {
            return
        }
        
    }
}


class OpenFileWarningWindowController: NSWindowController {
    @IBOutlet weak var spinner: NSProgressIndicator!
    @IBOutlet weak var errorField: NSTextField!
    @IBOutlet weak var processList: NSTableView!
    
    fileprivate weak var openFileWarningDelegate: OpenFileWarningDelegate?
    
    fileprivate var processes = [RunningProcess]()
    
    fileprivate var _shouldCheckRunning = true
    
    fileprivate var url: URL!
    
    fileprivate let checkQueue = DispatchQueue(label: "io.safedrive.checkQueue")
    
    var shouldCheckRunning: Bool {
        get {
            var r: Bool?
            checkQueue.sync {
                r = self._shouldCheckRunning
            }
            return r!
        }
        set (newValue) {
            checkQueue.sync(flags: .barrier, execute: {
                self._shouldCheckRunning = newValue
            })
        }
    }
    
    
    convenience init() {
        self.init(windowNibName: "OpenFileWarningWindow")
    }
    
    
    convenience init?(delegate: OpenFileWarningDelegate, url: URL, processes: [RunningProcess]) {
        self.init(windowNibName: "OpenFileWarningWindow")

        self.openFileWarningDelegate = delegate
        self.processes = processes
        self.url = url
        let nc = NSWorkspace.shared().notificationCenter
        nc.addObserver(self, selector: #selector(didTerminate(_:)), name: Notification.Name.NSWorkspaceDidTerminateApplication, object: nil)
        
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        self.spinner.stopAnimation(self)
        self.errorField.stringValue = ""
        self.processList.reloadData()
        weak var weakSelf: OpenFileWarningWindowController? = self

        DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).async {
            while self.shouldCheckRunning {
                weakSelf?.openFileWarningDelegate?.runningProcesses { (runningProcesses) in
                
                    let runningSet = Set<RunningProcess>(runningProcesses)
                    SDLog("there are \(runningProcesses.count) running processes")
                    
                    weakSelf?.openFileWarningDelegate?.blockingProcesses(self.url) { (blockingProcesses) in
                        let blockingSet = Set<RunningProcess>(blockingProcesses)
                        SDLog("volume \(self.url!.lastPathComponent) has \(blockingProcesses.count) blocking processes")

                        let processes = Array(blockingSet.intersection(runningSet))
                        SDLog("volume \(self.url!.lastPathComponent) has \(processes.count) processes with open files")
                        DispatchQueue.main.sync {
                            if processes.count == 0 {
                                SDLog("volume \(self.url!.path) is safe do disconnect now")
                                weakSelf?.openFileWarningDelegate?.tryAgain()
                                weakSelf?.shouldCheckRunning = false
                            } else {
                                
                            }
                            weakSelf?.processes = processes
                            weakSelf?.processList.reloadData()
                        }
                    }
                }
                Thread.sleep(forTimeInterval: 1)
            }
        }
    }
    
    @IBAction func close(_ sender: AnyObject) {
        self.shouldCheckRunning = false
        let nc = NSWorkspace.shared().notificationCenter
        nc.removeObserver(self)
        self.openFileWarningDelegate?.finished()
    }
    
    
    @IBAction func closeApp(_ sender: AnyObject) {
        let b = sender as! NSButton
        
        if let index = self.processes.index(where: { (process) -> Bool in
            process.pid == b.tag
        }) {
            let process = self.processes[index]
            self.openFileWarningDelegate?.closeApplication(process)
        }
    }
    
    @IBAction func closeAllApps(_ sender: AnyObject) {
        for process in self.processes {
            self.openFileWarningDelegate?.closeApplication(process)
        }
    }
    
}
