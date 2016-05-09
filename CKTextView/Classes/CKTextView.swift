//
//  CKTextView.swift
//  Pods
//
//  Created by Chanricle King on 4/29/16.
//
//

import UIKit

public class CKTextView: UITextView, UITextViewDelegate, UIActionSheetDelegate {
    // Record current cursor point, to choose operations.
    var currentCursorPoint: CGPoint?
    var currentCursorType: ListType = .None
    
    var prevCursorPoint: CGPoint?
    var prevCursorY: CGFloat?
    
    var willReturnTouch: Bool = false
    var willBackspaceTouch: Bool = false
    var willChangeText: Bool = false
    var willDeletedString: String?
    
    var isFirstLocationInLine: Bool = false
    
    var listPrefixContainerMap: Dictionary<CGFloat, NumberedListItem> = [:]

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        initialized()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialized()
    }
    
    func initialized()
    {
        self.delegate = self
        
        setupNotificationCenterObservers()
        
    }
    
    // MARK: Setups
    
    func setupNotificationCenterObservers()
    {
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(CKTextView.keyboardWillShow), name: UIKeyboardDidShowNotification, object: nil)
    }
    
    // MARK: Drawing
    
    func drawNumberLabelWithY(y: CGFloat, number: Int) -> NumberedListItem
    {
        self.font ?? UIFont.systemFontSize()
        
        let lineFragmentPadding = self.textContainer.lineFragmentPadding
        let lineHeight = self.font!.lineHeight
        
        // FIXME: Maybe Height not full made line wrong indent
        let height = CGFloat(2) //lineHeight - lineFragmentPadding * 2
        var width = lineHeight + 10
        
        // Woo.. too big
        if number >= 100 {
            let numberCount = "\(number)".characters.count
            width += CGFloat(numberCount - 2) * CGFloat(10)
        }
        
        let x: CGFloat = 8
        let size = CGSize(width: width, height: height)
        
        let numberBezierPath = UIBezierPath(rect: CGRect(origin: CGPoint(x: x, y: y), size: size))
        
        let numberLabel = UILabel(frame: CGRect(origin: numberBezierPath.bounds.origin, size: CGSize(width: width, height: lineHeight)))
        numberLabel.text = "\(number)."
        numberLabel.font = font
        
        if number < 10 {
            numberLabel.text = "  \(number)."
        }
        
        // Append label and exclusion bezier path.
        self.addSubview(numberLabel)
        self.textContainer.exclusionPaths.append(numberBezierPath)
        
        let numberedListItem = NumberedListItem(keyY: y, label: numberLabel, bezierPath: numberBezierPath, number: number)
        
        // Save to container
        listPrefixContainerMap[y] = numberedListItem
        
        return numberedListItem
    }
    
    func deleteListPrefixWithY(y: CGFloat, cursorPoint: CGPoint)
    {
        if let item = listPrefixContainerMap[y]
        {
            item.label.removeFromSuperview()
            
            if let index = self.textContainer.exclusionPaths.indexOf(item.bezierPath)
            {
                self.textContainer.exclusionPaths.removeAtIndex(index)
            }
            
            for (index, value) in item.keyYSet.enumerate() {
                listPrefixContainerMap.removeValueForKey(value)
            }
            
            // reload
            changeCurrentCursorPointIfNeeded(cursorPoint)
        }
    }
    
    // MARK: Change even
    
    func changeCurrentCursorPointIfNeeded(cursorPoint: CGPoint)
    {
        prevCursorPoint = currentCursorPoint
        currentCursorPoint = cursorPoint
        
        guard prevCursorPoint != nil else { return }
        
        if prevCursorPoint!.y != cursorPoint.y {
            prevCursorY = prevCursorPoint!.y
            
            // Text not change, only normal cursor moving..
            if !willChangeText || willBackspaceTouch {
                currentCursorType = listPrefixContainerMap[cursorPoint.y] == nil ? ListType.None : ListType.Numbered
                return
            }
            
            // Text changed, something happend.
            // Handle too long string typed.. add moreline bezierPath space fill. and set key to container.
            if !willReturnTouch && !willBackspaceTouch {
                if let item = listPrefixContainerMap[prevCursorY!]
                {
                    // key Y of New line add to container.
                    item.keyYSet.insert(cursorPoint.y)
                    listPrefixContainerMap[cursorPoint.y] = item
                    
                    // TODO: change BeizerPathRect, more height
                }
            }
            
            print("cursorY changed to: \(currentCursorPoint?.y), prev cursorY: \(prevCursorY)")
        }
    }
    
    // MARK: UITextViewDelegate
    
    public func textView(textView: UITextView, shouldChangeTextInRange range: NSRange, replacementText text: String) -> Bool
    {
        let cursorLocation = textView.selectedRange.location
        let cursorPoint = CKTextUtil.cursorPointInTextView(textView)
        
        isFirstLocationInLine = CKTextUtil.isFirstLocationInLineWithLocation(cursorLocation, textView: textView)
        
        if CKTextUtil.isReturn(text) {
            willReturnTouch = true
            
            isFirstLocationInLine = CKTextUtil.isFirstLocationInLineWithLocation(cursorLocation, textView: textView)
        
            if (currentCursorType == ListType.Numbered) && isFirstLocationInLine
            {
                deleteListPrefixWithY(cursorPoint.y, cursorPoint: cursorPoint)
                currentCursorType = .Text
                willReturnTouch = false
                
                return false
            }
        }
        if CKTextUtil.isBackspace(text) {
            willBackspaceTouch = true
            
            let cursorLocation = textView.selectedRange.location
            
            if cursorLocation == 0 {
                // If delete first character.
                deleteListPrefixWithY(cursorPoint.y, cursorPoint: cursorPoint)
                
            } else {
                let deleteRange = Range(start: textView.text.startIndex.advancedBy(range.location), end: textView.text.startIndex.advancedBy(range.location + range.length))
                willDeletedString = textView.text.substringWithRange(deleteRange)
            }
        }
        
        willChangeText = true
        
        print("shouldChangeTextInRange")
        
        return true
    }

    public func textViewDidChange(textView: UITextView)
    {
        guard currentCursorPoint != nil else { return }
        
        let cursorLocation = textView.selectedRange.location
        
//        print("----------- Status Log -----------")
//        print("cursor location: \(cursorLocation)")
//        print("text height: \(CKTextUtil.textHeightForTextView(textView))")
//        print("cursor point: \(cursorPoint)")
//        print("")
        
        // Keyword input will convert to List style.
        if CKTextUtil.isListKeywordInvokeWithLocation(cursorLocation, type: ListKeywordType.NumberedList, textView: textView)
        {
            let clearRange = Range(start: textView.text.endIndex.advancedBy(-3), end: textView.text.endIndex)
            textView.text.replaceRange(clearRange, with: "")
            
            drawNumberLabelWithY(currentCursorPoint!.y, number: 1)
            
            currentCursorType = ListType.Numbered
        }
    
        // Handle return operate.
        if willReturnTouch {
            if currentCursorType == ListType.Numbered {
                let item = listPrefixContainerMap[prevCursorY!]
                // Draw new item.
                let newItem = drawNumberLabelWithY(currentCursorPoint!.y, number: item!.number + 1)
                
                // Handle prev, next relationships.
                item?.nextItem = newItem
                newItem.prevItem = item
            }
            
            willReturnTouch = false
        }
        // Handle backspace operate.
        if willBackspaceTouch {
            // Delete list prefix
            guard willDeletedString != nil && willDeletedString!.containsString("\n") else { return }
            guard prevCursorY != nil else { return }
            
            deleteListPrefixWithY(prevCursorY!, cursorPoint: currentCursorPoint!)
            
            willDeletedString = nil
            willBackspaceTouch = false
        }
        
        willChangeText = false
        
        print("textViewDidChange")
    }
    
    public func textViewDidChangeSelection(textView: UITextView) {
        let cursorPoint = CKTextUtil.cursorPointInTextView(textView)
        changeCurrentCursorPointIfNeeded(cursorPoint)
        
        print("textViewDidChangeSelection")
    }
    
    // MARK: Copy & Paste
    
//    public override func paste(sender: AnyObject?) {
//        print("textview paste invoke. paste content: \(UIPasteboard.generalPasteboard().string)")
//    }

    // MARK: BarButtonItem action
    
    func listButtonAction(sender: UIBarButtonItem)
    {
        print("listButtonAction")
    }
    
    // MARK: KVO
    
    func keyboardWillShow(notification: NSNotification)
    {
        if let userInfo: NSDictionary = notification.userInfo {
            let value = userInfo["UIKeyboardBoundsUserInfoKey"]
            if let rect = value?.CGRectValue() {
                self.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: rect.height + 100, right: 0)
            }
        }
    }
    
}
