
//  Copyright (c) 2014-2016 SafeDrive. All rights reserved.
//

// swiftlint:disable force_cast


import Foundation
import SafeDriveSDK
import SystemConfiguration


protocol InstallerDelegate: class {
    func needsDependencies()
    func didValidateDependencies()
    func didFail(error: NSError)
}

class Installer: NSObject {
    
    weak var delegate: InstallerDelegate?
    
    fileprivate var prompted = false
    
        
    fileprivate var isOSXFUSEInstalled: Bool {
        let pipe: Pipe = Pipe()
        let task: Process = Process()
        task.launchPath = "/usr/sbin/pkgutil"
        task.arguments = ["--pkgs=com.github.osxfuse.pkg.Core"]
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            return true
        }
        return false
    }
    
    fileprivate var isOSXFUSECurrent: Bool {
        let pipe: Pipe = Pipe()
        let task: Process = Process()
        task.launchPath = "/usr/sbin/pkgutil"
        task.arguments = ["--pkg-info=com.github.osxfuse.pkg.Core"]
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let linefeed = CharacterSet(charactersIn: "\n")

                let kv = output.components(separatedBy: linefeed)
                var m = [String: String]()
                for pair in kv {
                    let kv = pair.components(separatedBy: ": ")
                    let key = kv[0]
                    let value = kv[1]
                    m[key] = value
                }
                if let currentVersion = m["version"] {
                    return currentVersion == "3.5.6"
                }
            }
        }
        return false
    }
    
    fileprivate var isDirectoryOK: Bool {
        // swiftlint:disable force_unwrapping
        let usrlocalbin = URL(string: "file:///usr/local/bin")!
        // swiftlint:enable force_unwrapping

        var isDirectory: ObjCBool = false
        let directoryExists = FileManager.default.fileExists(atPath: usrlocalbin.path, isDirectory: &isDirectory) && isDirectory.boolValue == true
        
        // check if the directory is actually writable and readable
        let directoryIsWritable = FileManager.default.isWritableFile(atPath: usrlocalbin.path)
        return directoryExists && directoryIsWritable
    }
    
    fileprivate var isCLIAppInstalled: Bool {
        // swiftlint:disable force_unwrapping
        let destination = URL(string: "file:///usr/local/bin/safedrive")!
        // swiftlint:enable force_unwrapping
        
        if FileManager.default.fileExists(atPath: destination.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                let type = attributes[FileAttributeKey.type] as! FileAttributeType
                let isSymlink = (type == FileAttributeType.typeSymbolicLink)
                return isSymlink
            } catch {
                return false
            }
        }

        return false
    }
    
    fileprivate var isCLIAppCurrent: Bool {
        let pipe: Pipe = Pipe()
        let task: Process = Process()
        task.launchPath = "/usr/local/bin/safedrive"
        task.arguments = ["version"]
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let cs = CharacterSet(charactersIn: "\n ")
            if let output = String(data: data, encoding: .utf8) {
                let version = output.trimmingCharacters(in: cs)
                return version == SafeDriveSDK.sddk_version
            }
        }
        return false
    }
    
    var dependenciesValidated: Bool {
        return self.isOSXFUSEInstalled && self.isCLIAppInstalled && self.isDirectoryOK
    }
    
    init(delegate: InstallerDelegate?) {
        self.delegate = delegate
    }
    
    func check() {
        DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).async {
            while !self.dependenciesValidated {
                if !self.prompted {
                    self.prompted = true
                    DispatchQueue.main.async {
                        self.delegate?.needsDependencies()
                    }
                }
                Thread.sleep(forTimeInterval: 1)
            }
            DispatchQueue.main.async {
                self.delegate?.didValidateDependencies()
            }
        }
    }
    
    func installDependencies() {
        DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).async {
            do {
                if !self.isDirectoryOK {
                    try self.setupDirectories()
                }
                if !self.isOSXFUSEInstalled {
                    try self.installOSXFUSE()
                }
                try self.deployService()
                if !self.isCLIAppInstalled {
                    try self.installCLI()
                }
            } catch let error as NSError {
                DispatchQueue.main.async {
                    self.delegate?.didFail(error: error)
                }
            }
        }
        
    }
    
    func deployService() throws {
        let fileManager: FileManager = FileManager.default
        // swiftlint:disable force_try

        let libraryURL = try! fileManager.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        
        let launchAgentsURL = libraryURL.appendingPathComponent("LaunchAgents", isDirectory: true)
        do {
            try fileManager.createDirectory(at: launchAgentsURL, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            let message = NSLocalizedString("Error creating launch agents directory: \(error)", comment: "")
            SDLog(message)
            let error = SDError(message: message, kind: .serviceDeployment)
            throw error
        }
        
        let applicationSupportURL = try! fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        // swiftlint:enable force_try

        let safeDriveApplicationSupportURL = applicationSupportURL.appendingPathComponent("SafeDrive", isDirectory: true)
        
        let serviceDestinationURL = safeDriveApplicationSupportURL.appendingPathComponent("SafeDriveService.app", isDirectory: true)
        
        let serviceSourceURL = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/SafeDriveService.app", isDirectory: true)
        
        // copy launch agent to ~/Library/LaunchAgents/
        let launchAgentDestinationURL = launchAgentsURL.appendingPathComponent("io.safedrive.SafeDrive.Service.plist", isDirectory: false)
        // swiftlint:disable force_unwrapping
        let launchAgentSourceURL: URL = Bundle.main.url(forResource: "io.safedrive.SafeDrive.Service", withExtension: "plist")!
        // swiftlint:enable force_unwrapping

        if FileManager.default.fileExists(atPath: launchAgentDestinationURL.path) {
            do {
                try FileManager.default.removeItem(at: launchAgentDestinationURL)
            } catch let error as NSError {
                SDLog("Error removing old launch agent: \(error)")
            }
        }
        do {
            try fileManager.copyItem(at: launchAgentSourceURL, to: launchAgentDestinationURL)
        } catch let error as NSError {
            let message = NSLocalizedString("Error copying launch agent: \(error)", comment: "")
            SDLog(message)
            let error = SDError(message: message, kind: .serviceDeployment)
            throw error
        }
        
        // copy background service to ~/Library/Application Support/SafeDrive/
        do {
            try fileManager.createDirectory(at: safeDriveApplicationSupportURL, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            let message = NSLocalizedString("Error creating support directory: \(error)", comment: "")
            SDLog(message)
            let error = SDError(message: message, kind: .serviceDeployment)
            throw error
        }
        
        if fileManager.fileExists(atPath: serviceDestinationURL.path) {
            do {
                try fileManager.removeItem(at: serviceDestinationURL)
            } catch let error as NSError {
                SDLog("Error removing old service: \(error)")
            }
        }
        do {
            try fileManager.copyItem(at: serviceSourceURL, to: serviceDestinationURL)
        } catch let error as NSError {
            let message = NSLocalizedString("Error copying service: \(error)", comment: "")
            SDLog(message)
            let error = SDError(message: message, kind: .serviceDeployment)
            throw error
        }
        
    }
    
    func installOSXFUSE() throws {
        let osxfuseURL = Bundle.main.url(forResource: "FUSE for macOS 3.5.6", withExtension: "pkg", subdirectory: nil)
        let privilegedTask = STPrivilegedTask()
        privilegedTask.launchPath = "/usr/sbin/installer"
        // swiftlint:disable force_unwrapping
        privilegedTask.arguments = ["-pkg", (osxfuseURL?.path)!, "-target", "/"]
        // swiftlint:enable force_unwrapping

        let err = privilegedTask.launch()
        
        if err != errAuthorizationSuccess {
            if err == errAuthorizationCanceled {
                SDLog("User cancelled installer")
                let message = NSLocalizedString("FUSE installation cancelled by user", comment: "")
                SDLog(message)
                let error = SDError(message: message, kind: .fuseDeployment)
                throw error
            } else {
                let message = NSLocalizedString("Installer could not be launched", comment: "")
                SDLog(message)
                let error = SDError(message: message, kind: .fuseDeployment)
                throw error
            }
        } else {
            SDLog("Installer launched")
        }
    }
    
    func installCLI() throws {

        guard let cli = Bundle.main.url(forAuxiliaryExecutable: "io.safedrive.SafeDrive.cli") else {
            let message = NSLocalizedString("CLI app missing, contact SafeDrive support", comment: "")
            SDLog(message)
            let error = SDError(message: message, kind: .cliMissing)
            throw error
        }
        
        SDLog("CLI location: \(cli.path)")
        // swiftlint:disable force_unwrapping
        let usrlocalbin = URL(string: "file:///usr/local/bin")!
        // swiftlint:enable force_unwrapping


        let destination = usrlocalbin.appendingPathComponent("safedrive")
        
        let fileManager: FileManager = FileManager.default
        if FileManager.default.fileExists(atPath: destination.path) {
            do {
                try FileManager.default.removeItem(at: destination)
            } catch let error as NSError {
                SDLog("Error removing old CLI app: \(error)")
            }
        }
        do {
            try fileManager.createSymbolicLink(at: destination, withDestinationURL: cli)
        } catch let error as NSError {
            let message = NSLocalizedString("Error installing CLI app symlink: \(error)", comment: "")
            SDLog(message)
            let error = SDError(message: message, kind: .cliDeployment)
            throw error
        }
    }
    
    func setupDirectories() throws {
        guard let cli = Bundle.main.url(forAuxiliaryExecutable: "io.safedrive.SafeDrive.cli") else {
            let message = NSLocalizedString("CLI app missing, contact SafeDrive support", comment: "")
            SDLog(message)
            let error = SDError(message: message, kind: .cliMissing)
            throw error
        }
                
        var uid: uid_t = 0
        var gid: gid_t = 0
        
        guard let cfname = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) else {
            let message = NSLocalizedString("Failed to get user information from system", comment: "")
            SDLog(message)
            let error = SDError(message: message, kind: .setupDirectories)
            throw error
        }
        
        let name = cfname as String
        
        SDLog("name = \(name), uid = \(uid), gid = \(gid)")

        let privilegedTask = STPrivilegedTask()

        privilegedTask.launchPath = cli.path
        privilegedTask.arguments = ["doctor", "--uid", String(uid), "--gid", String(gid)]
        
        let err = privilegedTask.launch()
        privilegedTask.waitUntilExit()
        
        if err != errAuthorizationSuccess {
            if err == errAuthorizationCanceled {
                let message = NSLocalizedString("Directory setup cancelled by user", comment: "")
                SDLog(message)
                let error = SDError(message: message, kind: .setupDirectories)
                throw error
            } else {
                let message = NSLocalizedString("Setup could not be completed", comment: "")
                SDLog(message)
                let error = SDError(message: message, kind: .setupDirectories)
                throw error
            }
        } else {
            SDLog("Directory setup launched")
        }
        let data = privilegedTask.outputFileHandle.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            SDLog("Directory setup output: \(output)")

        }
    }
}
