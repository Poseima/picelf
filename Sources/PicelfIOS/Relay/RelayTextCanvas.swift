import UIKit

enum RelayTextLayout {
    static func color(_ value: RelayTextBox.Color) -> UIColor {
        switch value {
        case .charcoal: return UIColor(white: 0.12, alpha: 1)
        case .white: return .white
        case .emerald: return UIColor(red: 0, green: 0.5, blue: 0.37, alpha: 1)
        case .red: return UIColor(red: 0.83, green: 0.14, blue: 0.16, alpha: 1)
        case .blue: return UIColor(red: 0.1, green: 0.3, blue: 0.85, alpha: 1)
        }
    }
    static func padding(_ box: RelayTextBox) -> CGFloat { max(4, box.fontSize * 0.2) }
    static func attributes(_ box: RelayTextBox) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = box.alignment == .left ? .left : box.alignment == .center ? .center : .right
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: UIFont.systemFont(ofSize: box.fontSize, weight: box.bold ? .bold : .regular),
                .foregroundColor: color(box.color), .paragraphStyle: paragraph]
    }
    static func layout(_ box: RelayTextBox) -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
        let storage = NSTextStorage(string: box.text, attributes: attributes(box))
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(1, box.width - padding(box) * 2), height: 100_000))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        return (storage, manager, container)
    }
    static func frame(_ box: RelayTextBox) -> CGRect {
        let (storage, manager, container) = layout(box)
        return withExtendedLifetime(storage) {
            CGRect(x: box.x, y: box.y, width: box.width,
                   height: max(UIFont.systemFont(ofSize: box.fontSize).lineHeight, manager.usedRect(for: container).height) + padding(box) * 2)
        }
    }
    static func draw(_ document: RelayTextDocument) {
        for box in document.boxes where !box.text.isEmpty {
            let rect = frame(box), pad = padding(box)
            if box.background {
                UIColor(white: 1, alpha: 0.92).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: pad).fill()
            }
            let (storage, manager, container) = layout(box)
            withExtendedLifetime(storage) {
                let range = manager.glyphRange(for: container)
                manager.drawBackground(forGlyphRange: range, at: CGPoint(x: rect.minX + pad, y: rect.minY + pad))
                manager.drawGlyphs(forGlyphRange: range, at: CGPoint(x: rect.minX + pad, y: rect.minY + pad))
            }
        }
    }
    static func image(_ document: RelayTextDocument, size: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(document) }
    }
}

final class RelayTextItemView: UIView {
    let id: UUID
    let textView: UITextView
    let handle = UIView()
    var activate: (() -> Void)?
    override func accessibilityActivate() -> Bool { activate?(); return activate != nil }
    init(box: RelayTextBox) {
        id = box.id
        let storage = NSTextStorage(), manager = NSLayoutManager(), container = NSTextContainer()
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        textView = UITextView(frame: .zero, textContainer: container)
        super.init(frame: RelayTextLayout.frame(box))
        textView.backgroundColor = .clear; textView.isScrollEnabled = false
        textView.textContainer.lineFragmentPadding = 0
        textView.overrideUserInterfaceStyle = .light
        textView.accessibilityIdentifier = "relay.textInput"
        textView.accessibilityLabel = L10n.localized("文字内容", "Text Content")
        textView.accessibilityHint = L10n.localized("可键入文字，或使用系统键盘的听写按钮", "Type text or use the dictation button on the system keyboard")
        addSubview(textView)
        handle.backgroundColor = UIColor(red: 0, green: 0.57, blue: 0.42, alpha: 1)
        handle.isUserInteractionEnabled = false; addSubview(handle)
        accessibilityIdentifier = "relay.textBox.\(id)"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(_ box: RelayTextBox, selected: Bool, editing: Bool, zoom: CGFloat) {
        var displayed = box
        if editing { displayed.text = textView.text }
        frame = RelayTextLayout.frame(displayed)
        let pad = RelayTextLayout.padding(box)
        textView.frame = bounds
        textView.textContainerInset = UIEdgeInsets(top: pad, left: pad, bottom: pad, right: pad)
        textView.textContainer.size = CGSize(width: max(1, bounds.width - pad * 2), height: 100_000)
        // A remote preview or a caret move must never replace marked input.
        if !editing {
            let value = NSAttributedString(string: box.text, attributes: RelayTextLayout.attributes(box))
            if textView.attributedText != value { textView.attributedText = value }
            textView.typingAttributes = RelayTextLayout.attributes(box)
        }
        if textView.isEditable != editing { textView.isEditable = editing }
        if textView.isSelectable != editing { textView.isSelectable = editing }
        textView.isUserInteractionEnabled = editing
        backgroundColor = box.background ? UIColor(white: 1, alpha: 0.92) : .clear
        layer.cornerRadius = pad
        layer.borderWidth = selected ? 1.5 / max(zoom, 0.01) : 0
        layer.borderColor = UIColor(red: 0, green: 0.57, blue: 0.42, alpha: 1).cgColor
        let handleWidth = 8 / max(zoom, 0.01), handleHeight = 24 / max(zoom, 0.01)
        handle.frame = CGRect(x: bounds.width - handleWidth / 2, y: (bounds.height - handleHeight) / 2, width: handleWidth, height: handleHeight)
        handle.layer.cornerRadius = handleWidth / 2; handle.isHidden = !selected || editing
        isAccessibilityElement = !editing
        accessibilityLabel = box.text.isEmpty ? L10n.localized("空文本框", "Empty Text Box") : box.text
        accessibilityHint = L10n.localized("双击编辑文字；使用文字工具可拖动位置和宽度", "Double-tap to edit. Use the text tool to move or resize the box")
        accessibilityTraits = [.button]
    }
}

private final class RelayTextPanGesture: UIPanGestureRecognizer {
    private(set) var initialPoint: CGPoint?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if initialPoint == nil { initialPoint = touches.first?.location(in: view) }
        super.touchesBegan(touches, with: event)
    }
    override func reset() { super.reset(); initialPoint = nil }
}

final class RelayTextOverlay: UIView, UITextViewDelegate, UIGestureRecognizerDelegate {
    unowned let model: RelayDrawingModel
    weak var host: RelayCanvasHost?
    private var items: [UUID: RelayTextItemView] = [:]
    private var editingBaseline: RelayTextDocument?
    private var activeInputID: UUID?
    private var dragBaseline: RelayTextDocument?
    private var dragBox: RelayTextBox?
    private var resizing = false
    private var savedViewport: (CGFloat, CGPoint)?
    private var keyboardFrame: CGRect?
    private var observers: [NSObjectProtocol] = []
    private var finishing = false

    init(model: RelayDrawingModel, host: RelayCanvasHost) {
        self.model = model; self.host = host
        super.init(frame: .zero)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2; tap.require(toFail: doubleTap)
        let pan = RelayTextPanGesture(target: self, action: #selector(dragged(_:)))
        pan.maximumNumberOfTouches = 1
        for gesture in [tap, doubleTap, pan] { gesture.delegate = self; addGestureRecognizer(gesture) }
        model.finishTextInput = { [weak self] in self?.finishEditing() }
        model.textUndo = { [weak self] in self?.input?.undoManager?.undo() }
        model.textRedo = { [weak self] in self?.input?.undoManager?.redo() }
        model.textUndoState = { [weak self] in (self?.input?.undoManager?.canUndo ?? false, self?.input?.undoManager?.canRedo ?? false) }
        observers.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.keyboardChanged(note) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreViewport() }
        })
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    private var input: UITextView? { model.editingTextID.flatMap { items[$0]?.textView } }
    func refresh() {
        let ids = Set(model.texts.boxes.map(\.id))
        for id in Array(items.keys) where !ids.contains(id) { items.removeValue(forKey: id)?.removeFromSuperview() }
        for box in model.texts.boxes {
            let item = items[box.id] ?? RelayTextItemView(box: box)
            if items[box.id] == nil {
                items[box.id] = item; addSubview(item); item.textView.delegate = self
                item.activate = { [weak self] in
                    guard let self, self.host?.editable == true else { return }
                    self.finishEditing(); self.model.textMode = true
                    self.model.selectedTextID = box.id; self.model.editingTextID = box.id; self.refresh()
                }
            }
            item.update(box, selected: model.selectedTextID == box.id, editing: model.editingTextID == box.id, zoom: host?.scroll.zoomScale ?? 1)
            bringSubviewToFront(item)
        }
        if let id = model.editingTextID, let item = items[id], activeInputID != id, host?.editable == true {
            beginEditing(id)
        }
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard host?.editable == true, !model.busy else { return nil }
        if !model.textMode {
            guard event?.allTouches?.first?.type != .pencil, box(at: point) != nil else { return nil }
        }
        return super.hitTest(point, with: event)
    }
    private func box(at point: CGPoint) -> RelayTextBox? {
        let margin = 22 / max(host?.scroll.zoomScale ?? 1, 0.01)
        return model.texts.boxes.reversed().first {
            RelayTextLayout.frame($0).insetBy(dx: -margin, dy: -margin).contains(point)
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let input, touch.view?.isDescendant(of: input) == true { return false }
        return touch.type != .pencil || model.textMode
    }
    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        finishEditing()
        if let box = box(at: point), !model.textInsertionArmed {
            model.textMode = true; model.selectedTextID = box.id
        } else if model.textInsertionArmed {
            model.addText(at: point, zoom: host?.scroll.zoomScale ?? 1)
        } else { model.selectedTextID = nil }
        refresh(); host?.updateToolVisibility()
    }
    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        guard let box = box(at: recognizer.location(in: self)) else { return }
        finishEditing(); model.textMode = true; model.textInsertionArmed = false
        model.selectedTextID = box.id; model.editingTextID = box.id; refresh()
    }
    private func beginEditing(_ id: UUID) {
        guard let item = items[id], let box = model.texts.boxes.first(where: { $0.id == id }) else { return }
        activeInputID = id
        editingBaseline = model.pendingTextBaseline ?? model.texts; model.pendingTextBaseline = nil
        if savedViewport == nil, let scroll = host?.scroll { savedViewport = (scroll.zoomScale, scroll.contentOffset) }
        item.textView.attributedText = NSAttributedString(string: box.text, attributes: RelayTextLayout.attributes(box))
        item.textView.undoManager?.removeAllActions()
        item.textView.isEditable = true; item.textView.isSelectable = true; item.textView.isUserInteractionEnabled = true
        host?.updateToolVisibility()
        item.textView.becomeFirstResponder()
        item.textView.selectedRange = NSRange(location: (box.text as NSString).length, length: 0)
        model.updateUndoState()
    }
    func finishEditing() {
        guard !finishing, let id = model.editingTextID else { return }
        finishing = true; defer { finishing = false }
        input?.unmarkText()
        if let input { textViewDidChange(input) }
        input?.resignFirstResponder()
        model.editingTextID = nil; model.hasMarkedText = false; model.textMode = false
        if let box = model.texts.boxes.first(where: { $0.id == id }), box.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var value = model.texts; value.boxes.removeAll { $0.id == id }; model.replaceTexts(value, undo: false)
            model.selectedTextID = nil
        }
        if let baseline = editingBaseline { model.registerTextUndo(baseline) }
        editingBaseline = nil; activeInputID = nil
        model.updateUndoState(); refresh(); host?.updateToolVisibility(activateCanvas: true)
    }
    func textViewDidEndEditing(_ textView: UITextView) { if !finishing { finishEditing() } }
    func textViewDidChange(_ textView: UITextView) {
        model.hasMarkedText = textView.markedTextRange != nil
        guard !model.hasMarkedText, let id = model.editingTextID else { return }
        model.updateTextBox(id, undo: false) { $0.text = textView.text }
        if let box = model.texts.boxes.first(where: { $0.id == id }), let item = items[id] {
            item.frame = RelayTextLayout.frame(box); textView.frame = item.bounds
        }
        DispatchQueue.main.async { [weak self] in self?.model.updateUndoState(); self?.revealCaret() }
    }
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard let value = textView.text as NSString?, range.location + range.length <= value.length else { return false }
        return value.replacingCharacters(in: range, with: text).utf8.count <= 16_384
    }
    @objc private func dragged(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            let translation = recognizer.translation(in: self)
            let start = (recognizer as? RelayTextPanGesture)?.initialPoint ?? CGPoint(x: point.x - translation.x, y: point.y - translation.y)
            guard model.editingTextID == nil, let box = box(at: start) else { return }
            model.textMode = true; model.textInsertionArmed = false; model.selectedTextID = box.id
            dragBaseline = model.texts; dragBox = box
            resizing = abs(start.x - RelayTextLayout.frame(box).maxX) < 22 / max(host?.scroll.zoomScale ?? 1, 0.01)
        case .changed:
            guard let box = dragBox else { return }
            let delta = recognizer.translation(in: self)
            model.updateTextBox(box.id, undo: false) { value in
                if resizing { value.width = min(model.pixelSize.width - box.x, max(48, box.width + delta.x)) }
                else {
                    value.x = max(0, min(model.pixelSize.width - box.width, box.x + delta.x))
                    value.y = max(0, min(model.pixelSize.height - min(RelayTextLayout.frame(box).height, model.pixelSize.height), box.y + delta.y))
                }
            }
        case .ended:
            if let baseline = dragBaseline { model.registerTextUndo(baseline) }
            dragBaseline = nil; dragBox = nil
        case .cancelled, .failed:
            if let baseline = dragBaseline { model.replaceTexts(baseline, undo: false) }
            dragBaseline = nil; dragBox = nil
        default: break
        }
        refresh()
    }
    private func keyboardChanged(_ note: Notification) {
        guard let host, model.editingTextID != nil,
              let rect = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let local = host.convert(rect, from: nil)
        keyboardFrame = local
        let overlap = host.bounds.intersection(local)
        host.keyboardInset = overlap.isNull ? 0 : overlap.height
        host.centerContent()
        DispatchQueue.main.async { [weak self] in self?.revealCaret() }
    }
    private func revealCaret() {
        guard let host, let input, let range = input.selectedTextRange else { return }
        let caret = input.convert(input.caretRect(for: range.end), to: host).insetBy(dx: -16, dy: -24)
        var bottom = host.bounds.maxY
        if let keyboardFrame, keyboardFrame.intersects(caret) || keyboardFrame.maxY >= host.bounds.maxY - 1 {
            bottom = min(bottom, keyboardFrame.minY)
        }
        let delta = caret.maxY > bottom ? caret.maxY - bottom : min(0, caret.minY)
        guard abs(delta) > 1 else { return }
        let scroll = host.scroll
        let y = min(max(scroll.contentOffset.y + delta, -scroll.contentInset.top),
                    max(-scroll.contentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.contentInset.bottom))
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: !UIAccessibility.isReduceMotionEnabled)
    }
    private func restoreViewport() {
        guard let host, model.editingTextID == nil else { return }
        keyboardFrame = nil
        host.keyboardInset = 0; host.centerContent()
        if let savedViewport {
            host.scroll.setZoomScale(savedViewport.0, animated: false)
            host.scroll.setContentOffset(savedViewport.1, animated: false)
        }
        savedViewport = nil
    }
}
