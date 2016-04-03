
//  Copyright (c) 2014-2016 SafeDrive. All rights reserved.
//

import Cocoa

class FlatWindowView: NSView {
    override var mouseDownCanMoveWindow:Bool {
        return true
    }
}

class FlatWindowBackgroundView: NSImageView {
    override var mouseDownCanMoveWindow:Bool {
        return true
    }
}


class FlatWindow: NSWindow {
    var closeButton = NSButton(frame: NSZeroRect)

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    required override init(contentRect: NSRect, styleMask aStyle: Int, backing bufferingType: NSBackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: aStyle, backing: bufferingType, defer: flag)
    }
    
    override func awakeFromNib() {
        self.level = Int(CGWindowLevelForKey(CGWindowLevelKey.StatusWindowLevelKey))
        self.opaque = false
        self.closeButton.image = NSImage(named: NSImageNameStopProgressTemplate)
        self.closeButton.bordered = false
        self.closeButton.setButtonType(.MomentaryChangeButton)
        self.closeButton.target = self
        self.closeButton.action = #selector(self.windowController!.close)
        self.backgroundColor = NSColor.clearColor()
        let offset = 8
        let size = 9
        self.closeButton.frame = NSRect(x: offset + 4, y: Int(self.frame.height) - size - offset, width: size, height: size)
        self.contentView?.addSubview(self.closeButton)

    }
    
    override var movableByWindowBackground: Bool {
        get {
            return true
        }
        set {
            
        }
    }
    
    override var canBecomeKeyWindow: Bool {
        get {
            return true
        }
        set {
            
        }
    }
    
    override var canBecomeMainWindow: Bool {
        get {
            return true
        }
        set {
            
        }
    }
}