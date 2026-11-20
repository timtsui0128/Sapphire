//
//  NotchHoverMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import Cocoa

@MainActor
struct NotchHoverMonitorHandlers {
    var onPointerEvent: () -> Void
    var onMouseDrag: (_ isInside: Bool, _ screenLocation: NSPoint) -> Void
    var onMouseDragEnded: (_ screenLocation: NSPoint) -> Void
    var onFileDrag: (_ isTargeted: Bool, _ screenLocation: NSPoint) -> Void
    var onFileDragEnded: (_ screenLocation: NSPoint, _ dropWasAccepted: Bool) -> Void
    var onFileDrop: (_ pasteboard: NSPasteboard, _ screenLocation: NSPoint, _ dragSequence: Int) -> Bool
}

// MARK: - Tracking View

final class HoverTrackingView: NSView {
    var onPointerEvent: ((_ isInside: Bool, _ event: NSEvent) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) { onPointerEvent?(true, event) }
    override func mouseExited(with event: NSEvent) { onPointerEvent?(false, event) }
}

// MARK: - Probe Window

final class HoverProbeWindow: NSPanel, NSDraggingDestination {
    var onFileDragBegan: ((NSPoint) -> Void)?
    var onFileDragMoved: ((NSPoint) -> Void)?
    var onFileDragExited: ((NSPoint) -> Void)?
    var onFileDragEnded: ((NSPoint, Bool) -> Void)?
    var onFileDrop: ((NSPasteboard, NSPoint, Int) -> Bool)?

    private var isFileDropDestination = false
    private var activeDragSequence: Int?
    var isFileDragSessionActive: Bool { activeDragSequence != nil }
    private(set) var isArmedForMouseSequence = false
    private(set) var isHoverDetectionEnabled = false
    private var sessionOperation: NSDragOperation = []
    private var lastDragUpdateLocation: NSPoint?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    convenience init(level: NSWindow.Level, collectionBehavior: NSWindow.CollectionBehavior) {
        self.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        self.level = level
        self.collectionBehavior = collectionBehavior
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        sharingType = .none
    }

    func enableFileDropDestination() {
        isFileDropDestination = true
        registerForDraggedTypes(FileDragPasteboard.droppableTypes)
        updateMouseEventHandling()
    }

    func disableFileDropDestination() {
        isFileDropDestination = false
        unregisterDraggedTypes()
        activeDragSequence = nil
        sessionOperation = []
        updateMouseEventHandling()
        onFileDragBegan = nil
        onFileDragMoved = nil
        onFileDragExited = nil
        onFileDragEnded = nil
        onFileDrop = nil
    }

    func setArmedForMouseSequence(_ isArmed: Bool) {
        isArmedForMouseSequence = isArmed
    }

    func setHoverDetectionEnabled(_ isEnabled: Bool) {
        isHoverDetectionEnabled = isEnabled
        updateMouseEventHandling()
    }

    // MARK: NSDraggingDestination

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if activeDragSequence != sender.draggingSequenceNumber {
            cancelFileDrag(at: screenLocation(for: sender))
        }
        let operation = acceptedOperation(for: sender)
        sessionOperation = operation
        lastDragUpdateLocation = nil
        guard !operation.isEmpty else { return [] }
        activeDragSequence = sender.draggingSequenceNumber
        updateMouseEventHandling()
        let location = screenLocation(for: sender)
        onFileDragBegan?(location)
        return operation
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard activeDragSequence == sender.draggingSequenceNumber, !sessionOperation.isEmpty else { return [] }
        let location = screenLocation(for: sender)
        if location != lastDragUpdateLocation {
            lastDragUpdateLocation = location
            onFileDragMoved?(location)
        }
        return sessionOperation
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        guard sender == nil || activeDragSequence == sender?.draggingSequenceNumber else { return }
        onFileDragExited?(screenLocation(for: sender))
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        activeDragSequence == sender.draggingSequenceNumber && !sessionOperation.isEmpty
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard prepareForDragOperation(sender) else { return false }
        let location = screenLocation(for: sender)
        let sequence = sender.draggingSequenceNumber
        let accepted = onFileDrop?(sender.draggingPasteboard, location, sequence) ?? false
        if activeDragSequence == sequence { finishFileDrag(at: location, accepted: accepted) }
        return accepted
    }

    func draggingEnded(_ sender: NSDraggingInfo) {
        guard activeDragSequence == sender.draggingSequenceNumber else { return }
        cancelFileDrag(at: screenLocation(for: sender))
    }

    func concludeDragOperation(_ sender: NSDraggingInfo?) {
        guard let sender else { return }
        draggingEnded(sender)
    }

    func cancelFileDrag(at location: NSPoint) {
        finishFileDrag(at: location, accepted: false)
    }

    private func canAcceptFiles(from sender: NSDraggingInfo) -> Bool {
        guard onFileDrop != nil else { return false }
        return FileDragPasteboard.containsDroppableContent(sender.draggingPasteboard)
    }

    private func acceptedOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptFiles(from: sender) else { return [] }
        let sourceOperations = sender.draggingSourceOperationMask
        if sourceOperations.contains(.copy) { return .copy }
        if sourceOperations.contains(.generic) { return .generic }
        return []
    }

    private func screenLocation(for sender: NSDraggingInfo?) -> NSPoint {
        guard let sender else { return NSEvent.mouseLocation }
        return convertPoint(toScreen: sender.draggingLocation)
    }

    private func finishFileDrag(at location: NSPoint, accepted: Bool) {
        guard isFileDragSessionActive else { return }
        activeDragSequence = nil
        sessionOperation = []
        lastDragUpdateLocation = nil
        updateMouseEventHandling()
        onFileDragEnded?(location, accepted)
    }

    private func updateMouseEventHandling() {
        // A clear NSPanel can still intercept another app's title-bar press.
        // Only the separately registered native drop destination needs input.
        ignoresMouseEvents = !(isFileDropDestination && (isHoverDetectionEnabled || isFileDragSessionActive))
    }
}

// MARK: - Monitor

@MainActor
final class NotchHoverMonitor {
    private let mouseLocation: () -> NSPoint
    private let isPrimaryButtonPressed: () -> Bool
    private let installGlobalDragMonitor: (@escaping (NSEvent) -> Void) -> Any?
    private let removeGlobalDragMonitor: (Any) -> Void

    init(
        mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
        isPrimaryButtonPressed: @escaping () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 },
        installGlobalDragMonitor: @escaping (@escaping (NSEvent) -> Void) -> Any? = {
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: $0)
        },
        removeGlobalDragMonitor: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) }
    ) {
        self.mouseLocation = mouseLocation
        self.isPrimaryButtonPressed = isPrimaryButtonPressed
        self.installGlobalDragMonitor = installGlobalDragMonitor
        self.removeGlobalDragMonitor = removeGlobalDragMonitor
    }

    private weak var notchWindow: NSWindow?
    private var probeWindow: HoverProbeWindow?
    private var tracker: HoverTrackingView?
    private var handlers: NotchHoverMonitorHandlers?

    private var currentRect: CGRect = .null
    private var requestedRect: CGRect = .null
    private var pendingRect: CGRect = .null
    private var settleTask: Task<Void, Never>?
    private var isParked = true
    private var pointerIsInside = false
    private var pointerSamplingTimer: Timer?
    private var lastSampledPointer: NSPoint?
    private var globalDragMonitor: Any?
    private var dragSamplingTimer: Timer?
    private var deferredDisarmTask: Task<Void, Never>?
    private var pendingPlainDragEndLocation: NSPoint?
    private var pendingProactiveFileDragEndLocation: NSPoint?
    private var localMouseMonitor: Any?
    private var mouseUpToken: UUID?
    private var mouseDownLocation: NSPoint?
    private var lastIdleDragPasteboardChangeCount = 0
    private var dragPasteboardChangeCountBeforeMouseSequence: Int?
    private var mouseSequenceGeneration: UInt64 = 0
    private var activeMouseSequenceGeneration: UInt64?
    private var hasObservedMouseDrag = false
    private var hasEnteredDuringMouseDrag = false
    private var didObserveFileDragInMouseSequence = false
    private var didTargetFileDragInMouseSequence = false
    private var isProactiveFileDragTargeted = false
    private var isExternalMouseDragActive = false
    private var isSystemWindowDragSuppressed = false
    private var lastExternalMouseDragLocation: NSPoint?
    private var dropWindow: HoverProbeWindow?
    private var dropArmMouseDownToken: UUID?
    private var dropArmTimer: Timer?
    private var dropArmBaselineChangeCount: Int?
    private var nativeReleaseObservedAt: TimeInterval?
    private var isDropZoneShown = false
    private var isDropZoneEngaged = false

    private static let resizeThreshold: CGFloat = 6
    private static let mouseDragThresholdSquared: CGFloat = 9
    private static let lateNativeFileDragGrace: Duration = .milliseconds(100)
    private static let dropZoneOutset = CGSize(width: 60, height: 60)
    private static let dropArmPollInterval: TimeInterval = 1 / 15

    private static let pointerSampleInterval: TimeInterval = 0.05

    var isRunning: Bool { notchWindow != nil }
    private var isNativeFileDragActive: Bool { dropWindow?.isFileDragSessionActive == true }
    var hasActiveMouseEventMonitors: Bool {
        localMouseMonitor != nil || globalDragMonitor != nil || mouseUpToken != nil || dragSamplingTimer != nil
    }
    var isHoverProbeListeningForPointer: Bool {
        probeWindow?.isHoverDetectionEnabled == true
    }

    // MARK: Lifecycle

    func start(window: NSWindow, handlers: NotchHoverMonitorHandlers) {
        if notchWindow === window, probeWindow != nil {
            self.handlers = handlers
            return
        }
        stop()

        notchWindow = window
        self.handlers = handlers
        lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount

        let probe = HoverProbeWindow(level: window.level, collectionBehavior: window.collectionBehavior)
        let tracker = HoverTrackingView(frame: .zero)
        tracker.autoresizingMask = [.width, .height]
        tracker.onPointerEvent = { [weak self] isInside, event in
            self?.handleProbeBoundary(isInside: isInside, event: event)
        }
        probe.contentView = tracker

        let drop = HoverProbeWindow(level: window.level, collectionBehavior: window.collectionBehavior)
        drop.contentView = NSView(frame: .zero)
        drop.onFileDragBegan = { [weak self] location in
            self?.setDropZoneEngaged(true)
            self?.handleFileDragBegan(at: location)
        }
        drop.onFileDragMoved = { [weak self] location in
            self?.handlers?.onFileDrag(true, location)
        }
        drop.onFileDragExited = { [weak self] location in
            self?.setDropZoneEngaged(false)
            self?.handlers?.onFileDrag(false, location)
        }
        drop.onFileDragEnded = { [weak self] location, dropWasAccepted in
            self?.handleFileDragEnded(at: location, dropWasAccepted: dropWasAccepted)
        }
        drop.onFileDrop = { [weak self] pasteboard, location, sequence in
            self?.handlers?.onFileDrop(pasteboard, location, sequence) ?? false
        }
        drop.enableFileDropDestination()

        self.tracker = tracker
        self.probeWindow = probe
        self.dropWindow = drop
        dropArmMouseDownToken = EventMonitorHub.shared.register(for: .leftMouseDown) { [weak self] _ in
            self?.armDropZoneForPotentialDrag()
        }

        (NSApp.delegate as? AppDelegate)?.attachAuxiliaryNotchWindow(probe)
        window.addChildWindow(probe, ordered: .above)

    }

    func stop() {
        stopPointerSampling()
        stopDragMonitoring()
        deferredDisarmTask?.cancel()
        deferredDisarmTask = nil
        pendingPlainDragEndLocation = nil
        pendingProactiveFileDragEndLocation = nil
        settleTask?.cancel()
        settleTask = nil

        removeLocalMouseMonitor()
        stopGlobalMouseUpMonitoring()
        mouseDownLocation = nil
        activeMouseSequenceGeneration = nil
        dragPasteboardChangeCountBeforeMouseSequence = nil
        lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        hasObservedMouseDrag = false
        hasEnteredDuringMouseDrag = false
        didObserveFileDragInMouseSequence = false
        didTargetFileDragInMouseSequence = false
        isProactiveFileDragTargeted = false
        isExternalMouseDragActive = false
        lastExternalMouseDragLocation = nil

        tracker?.onPointerEvent = nil
        tracker = nil

        if let dropArmMouseDownToken {
            EventMonitorHub.shared.unregister(token: dropArmMouseDownToken, for: .leftMouseDown)
            self.dropArmMouseDownToken = nil
        }
        stopDropArmTimer()
        if let dropWindow {
            dropWindow.disableFileDropDestination()
            dropWindow.orderOut(nil)
            dropWindow.contentView = nil
            dropWindow.close()
        }
        dropWindow = nil
        isDropZoneShown = false
        isDropZoneEngaged = false

        if let probeWindow {
            notchWindow?.removeChildWindow(probeWindow)
            (NSApp.delegate as? AppDelegate)?.detachAuxiliaryNotchWindow(probeWindow)
            probeWindow.orderOut(nil)
            probeWindow.contentView = nil
            probeWindow.close()
        }
        probeWindow = nil

        notchWindow = nil
        handlers = nil
        currentRect = .null
        requestedRect = .null
        isParked = true
        pointerIsInside = false
        isSystemWindowDragSuppressed = false
    }

    // MARK: Geometry

    func update(hoverRect rect: CGRect, pointerIsInside: Bool) {
        guard let window = notchWindow, let probeWindow else { return }
        guard !isSystemWindowDragSuppressed else {
            park()
            return
        }

        self.pointerIsInside = pointerIsInside
        probeWindow.setHoverDetectionEnabled(!pointerIsInside)
        syncLocalMouseMonitor()

        guard !rect.isNull, !rect.isEmpty else {
            requestedRect = .null
            park()
            return
        }
        requestedRect = rect
        if isDropZoneShown { placeDropZone() }

        if probeWindow.isArmedForMouseSequence || isNativeFileDragActive {
            if !rect.equalTo(currentRect) {
                applyRect(rect, to: probeWindow, in: window)
            }
        } else if movedMeaningfully(from: currentRect, to: rect) {
            applyRect(rect, to: probeWindow, in: window)
        } else if !rect.equalTo(currentRect) {
            scheduleSettle(rect)
        }

        if isParked {
            isParked = false
            probeWindow.order(.above, relativeTo: window.windowNumber)
            startPointerSampling()
        }
    }

    func invalidatePlacement() {
        guard !isParked else { return }
        currentRect = .null
    }

    private func applyRect(_ rect: CGRect, to probeWindow: HoverProbeWindow, in window: NSWindow) {
        settleTask?.cancel()
        settleTask = nil
        pendingRect = .null
        currentRect = rect
        let screenRect = window.convertToScreen(rect)
        probeWindow.setFrame(screenRect, display: false)
        notifyIfContainmentDisagrees(with: screenRect)
        refreshMouseDragContainment(at: mouseLocation())
    }

    private func notifyIfContainmentDisagrees(with screenRect: CGRect) {
        let containsPointer = screenRect.contains(mouseLocation())
        guard containsPointer != pointerIsInside else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handleProbePointerSample()
        }
    }

    private func scheduleSettle(_ rect: CGRect) {
        pendingRect = rect
        guard settleTask == nil else { return }
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.settleTask = nil
            let pending = self.pendingRect
            self.pendingRect = .null
            guard !pending.isNull, !pending.equalTo(self.currentRect) else { return }
            guard let probeWindow = self.probeWindow, let window = self.notchWindow else { return }
            self.currentRect = pending
            let screenRect = window.convertToScreen(pending)
            probeWindow.setFrame(screenRect, display: false)
            self.notifyIfContainmentDisagrees(with: screenRect)
            self.refreshMouseDragContainment(at: mouseLocation())
        }
    }

    private func park() {
        stopPointerSampling()
        dropWindow?.cancelFileDrag(at: mouseLocation())
        stopDropArmTimer()
        hideDropZone()
        settleTask?.cancel()
        settleTask = nil
        pendingRect = .null
        probeWindow?.setHoverDetectionEnabled(false)
        guard !isParked else { return }
        isParked = true
        currentRect = .null
        probeWindow?.orderOut(nil)
    }

    private func movedMeaningfully(from old: CGRect, to new: CGRect) -> Bool {
        if old.isNull { return true }
        let threshold = Self.resizeThreshold
        return abs(new.minX - old.minX) > threshold
            || abs(new.minY - old.minY) > threshold
            || abs(new.width - old.width) > threshold
            || abs(new.height - old.height) > threshold
    }

    // A click-through panel may miss AppKit tracking-area crossings. Compare
    // the cursor with the displayed bounds without taking the underlying press.
    private func startPointerSampling() {
        guard pointerSamplingTimer == nil else { return }
        let timer = Timer(timeInterval: Self.pointerSampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let probeWindow = self.probeWindow else { return }
                let point = self.mouseLocation()
                guard point != self.lastSampledPointer else { return }
                self.lastSampledPointer = point
                if self.pointerIsInside || probeWindow.frame.contains(point) {
                    self.handleProbePointerSample()
                }
            }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        pointerSamplingTimer = timer
    }

    private func stopPointerSampling() {
        pointerSamplingTimer?.invalidate()
        pointerSamplingTimer = nil
        lastSampledPointer = nil
    }

    private func syncLocalMouseMonitor() {
        let shouldMonitor = pointerIsInside || activeMouseSequenceGeneration != nil
        if shouldMonitor {
            installLocalMouseMonitor()
        } else {
            removeLocalMouseMonitor()
        }
    }

    private func installLocalMouseMonitor() {
        guard localMouseMonitor == nil else { return }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let location = self.screenLocation(for: event)
                switch event.type {
                case .leftMouseDown:
                    self.armDropZoneForPotentialDrag()
                    self.armForPotentialMouseDrag(at: location)
                case .leftMouseDragged:
                    self.handleMouseDragged(at: location)
                case .leftMouseUp:
                    self.handleMouseUp(at: location)
                default:
                    break
                }
            }
            return event
        }
    }

    private func removeLocalMouseMonitor() {
        guard let localMouseMonitor else { return }
        NSEvent.removeMonitor(localMouseMonitor)
        self.localMouseMonitor = nil
    }

    private func startGlobalMouseUpMonitoring() {
        guard mouseUpToken == nil else { return }
        mouseUpToken = EventMonitorHub.shared.register(for: .leftMouseUp) { [weak self] event in
            guard let self else { return }
            self.handleMouseUp(at: self.screenLocation(for: event))
        }
    }

    private func stopGlobalMouseUpMonitoring() {
        guard let mouseUpToken else { return }
        EventMonitorHub.shared.unregister(token: mouseUpToken, for: .leftMouseUp)
        self.mouseUpToken = nil
    }

    func setExternalMouseDragActive(_ isActive: Bool) {
        guard isExternalMouseDragActive != isActive else { return }
        isExternalMouseDragActive = isActive

        if isActive {
            // AX has identified a window move. It now owns the final snap callback.
            hasEnteredDuringMouseDrag = false
            pendingPlainDragEndLocation = nil
            lastExternalMouseDragLocation = nil
            startDragMonitoring()
            sampleMouseDragState()
        } else {
            let location = mouseLocation()
            lastExternalMouseDragLocation = nil
            if !isPrimaryButtonPressed() { handleMouseUp(at: location) }
            if mouseDownLocation == nil { stopDragMonitoring() }
            handlers?.onMouseDrag(false, location)
            handlers?.onMouseDragEnded(location)
        }
    }

    func setSystemWindowDragSuppressed(_ suppressed: Bool) {
        guard isSystemWindowDragSuppressed != suppressed else { return }
        isSystemWindowDragSuppressed = suppressed
        if suppressed {
            // Global observation may continue, but the transparent probe must
            // not remain armed over Mission Control or receive the drop.
            probeWindow?.setArmedForMouseSequence(false)
            park()
        }
    }

    // MARK: Drag ownership

    private func handleProbeBoundary(isInside: Bool, event: NSEvent) {
        guard !isSystemWindowDragSuppressed else { return }
        if isPrimaryButtonPressed() {
            handleMouseDragged(
                at: screenLocation(for: event),
                knownContainment: isInside
            )
        } else {
            lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        }
        handlers?.onPointerEvent()
    }

    private func handleProbePointerSample() {
        guard !isSystemWindowDragSuppressed else { return }
        if isPrimaryButtonPressed() {
            armForPotentialMouseDrag(at: mouseLocation())
        } else {
            lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        }
        handlers?.onPointerEvent()
    }

    private func armForPotentialMouseDrag(at location: NSPoint) {
        guard !isSystemWindowDragSuppressed, !isExternalMouseDragActive,
              isPrimaryButtonPressed(),
              let probeWindow else { return }

        finishDeferredMouseSequenceBeforeNewPress(in: probeWindow)
        guard !isNativeFileDragActive,
              mouseDownLocation == nil else { return }

        beginMouseSequence(at: location)
    }

    private func beginMouseSequence(at location: NSPoint) {
        pendingPlainDragEndLocation = nil
        pendingProactiveFileDragEndLocation = nil
        mouseSequenceGeneration &+= 1
        activeMouseSequenceGeneration = mouseSequenceGeneration
        mouseDownLocation = location
        dragPasteboardChangeCountBeforeMouseSequence = lastIdleDragPasteboardChangeCount
        hasObservedMouseDrag = false
        didObserveFileDragInMouseSequence = false
        didTargetFileDragInMouseSequence = false
        isProactiveFileDragTargeted = false
        startGlobalMouseUpMonitoring()
        syncLocalMouseMonitor()
        startDragMonitoring()
    }

    private func finishDeferredMouseSequenceBeforeNewPress(in probeWindow: HoverProbeWindow) {
        guard mouseDownLocation == nil,
              activeMouseSequenceGeneration != nil,
              !isNativeFileDragActive else { return }

        deferredDisarmTask?.cancel()
        deferredDisarmTask = nil
        if let location = pendingPlainDragEndLocation,
           !didObserveFileDragInMouseSequence {
            handlers?.onMouseDrag(false, location)
            handlers?.onMouseDragEnded(location)
        }
        if let location = pendingProactiveFileDragEndLocation {
            isProactiveFileDragTargeted = false
            handlers?.onFileDrag(false, location)
            handlers?.onFileDragEnded(location, false)
        }
        pendingPlainDragEndLocation = nil
        pendingProactiveFileDragEndLocation = nil
        didObserveFileDragInMouseSequence = false
        didTargetFileDragInMouseSequence = false
        activeMouseSequenceGeneration = nil
        dragPasteboardChangeCountBeforeMouseSequence = nil
        lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        probeWindow.setArmedForMouseSequence(false)
    }

    private func handleMouseDragged(
        at location: NSPoint,
        knownContainment: Bool? = nil
    ) {
        guard !isSystemWindowDragSuppressed, !isExternalMouseDragActive,
              isPrimaryButtonPressed(), !isNativeFileDragActive,
              let probeWindow else { return }
        if mouseDownLocation == nil {
            finishDeferredMouseSequenceBeforeNewPress(in: probeWindow)
        }
        deferredDisarmTask?.cancel()
        deferredDisarmTask = nil
        if activeMouseSequenceGeneration == nil || mouseDownLocation == nil {
            beginMouseSequence(at: location)
        }
        pendingPlainDragEndLocation = nil
        pendingProactiveFileDragEndLocation = nil
        mouseDownLocation = mouseDownLocation ?? location
        hasObservedMouseDrag = true
        probeWindow.setArmedForMouseSequence(true)
        startDragMonitoring()

        if let isInside = knownContainment {
            publishMouseDragContainment(isInside, at: location)
            return
        }
        refreshMouseDragContainment(at: location)
    }

    private func refreshMouseDragContainment(at location: NSPoint) {
        guard let probeWindow,
              probeWindow.isArmedForMouseSequence,
              hasObservedMouseDrag,
              isPrimaryButtonPressed(),
              !isNativeFileDragActive else { return }

        let isInside = probeWindow.isVisible && probeWindow.frame.contains(location)
        publishMouseDragContainment(isInside, at: location)
    }

    private func publishMouseDragContainment(_ isInside: Bool, at location: NSPoint) {
        let isFileDrag = didObserveFileDragInMouseSequence
            || dragPasteboardChangeCountBeforeMouseSequence.map {
                FileDragPasteboard.containsDroppableContent(NSPasteboard(name: .drag), newerThan: $0)
            } == true
        if isFileDrag {
            didObserveFileDragInMouseSequence = true
            hasEnteredDuringMouseDrag = false
            if isInside {
                didTargetFileDragInMouseSequence = true
            }
            if isInside || isProactiveFileDragTargeted {
                handlers?.onFileDrag(isInside, location)
            }
            isProactiveFileDragTargeted = isInside
            return
        }

        if isProactiveFileDragTargeted {
            isProactiveFileDragTargeted = false
            handlers?.onFileDrag(false, location)
        }
        if isInside {
            hasEnteredDuringMouseDrag = true
        }
        handlers?.onMouseDrag(isInside, location)
    }

    private func handleMouseUp(at location: NSPoint) {
        guard let probeWindow,
              let sequenceGeneration = activeMouseSequenceGeneration,
              mouseDownLocation != nil else { return }
        stopGlobalMouseUpMonitoring()
        if !isExternalMouseDragActive { stopDragMonitoring() }

        if !didObserveFileDragInMouseSequence,
           let baseline = dragPasteboardChangeCountBeforeMouseSequence,
           probeWindow.isVisible,
           probeWindow.frame.contains(location),
           FileDragPasteboard.containsDroppableContent(NSPasteboard(name: .drag), newerThan: baseline) {
            didObserveFileDragInMouseSequence = true
            didTargetFileDragInMouseSequence = true
            isProactiveFileDragTargeted = true
            handlers?.onMouseDrag(false, location)
            handlers?.onFileDrag(true, location)
        }

        let wasObservedDragReleasedInsideProbe = hasObservedMouseDrag
            && probeWindow.isVisible
            && probeWindow.frame.contains(location)
        let shouldFinishMouseDrag = hasEnteredDuringMouseDrag
            && !isNativeFileDragActive
            && !didObserveFileDragInMouseSequence
        let shouldFinishProactiveFileDrag = didTargetFileDragInMouseSequence
            && !isNativeFileDragActive

        mouseDownLocation = nil
        hasObservedMouseDrag = false
        hasEnteredDuringMouseDrag = false
        guard !isNativeFileDragActive else { return }

        if shouldFinishMouseDrag, pendingPlainDragEndLocation == nil {
            pendingPlainDragEndLocation = location
        }
        if shouldFinishProactiveFileDrag, pendingProactiveFileDragEndLocation == nil {
            pendingProactiveFileDragEndLocation = location
        }
        let allowsLateNativeFileDrag = isProactiveFileDragTargeted
            || wasObservedDragReleasedInsideProbe
        scheduleDeferredDisarm(
            of: probeWindow,
            sequenceGeneration: sequenceGeneration,
            allowsLateNativeFileDrag: allowsLateNativeFileDrag
        )
    }

    private func handleFileDragBegan(at location: NSPoint) {
        startDropArmTimer()
        deferredDisarmTask?.cancel()
        deferredDisarmTask = nil
        pendingPlainDragEndLocation = nil
        pendingProactiveFileDragEndLocation = nil
        if activeMouseSequenceGeneration == nil {
            mouseSequenceGeneration &+= 1
            activeMouseSequenceGeneration = mouseSequenceGeneration
        }
        didObserveFileDragInMouseSequence = true
        didTargetFileDragInMouseSequence = true
        isProactiveFileDragTargeted = true
        hasObservedMouseDrag = true
        hasEnteredDuringMouseDrag = false
        handlers?.onMouseDrag(false, location)
        handlers?.onFileDrag(true, location)
    }

    private func handleFileDragEnded(at location: NSPoint, dropWasAccepted: Bool) {
        stopDropArmTimer()
        hideDropZone()
        stopDragMonitoring()
        stopGlobalMouseUpMonitoring()
        deferredDisarmTask?.cancel()
        deferredDisarmTask = nil
        pendingPlainDragEndLocation = nil
        pendingProactiveFileDragEndLocation = nil
        mouseDownLocation = nil
        hasObservedMouseDrag = false
        hasEnteredDuringMouseDrag = false
        didObserveFileDragInMouseSequence = false
        didTargetFileDragInMouseSequence = false
        isProactiveFileDragTargeted = false
        lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        dragPasteboardChangeCountBeforeMouseSequence = nil
        activeMouseSequenceGeneration = nil
        probeWindow?.setArmedForMouseSequence(false)
        syncLocalMouseMonitor()
        handlers?.onFileDrag(false, location)
        handlers?.onFileDragEnded(location, dropWasAccepted)
    }

    // MARK: Drop zone

    private func armDropZoneForPotentialDrag() {
        guard let dropWindow, !requestedRect.isNull, !isParked, !isSystemWindowDragSuppressed else { return }
        dropWindow.cancelFileDrag(at: mouseLocation())
        hideDropZone()
        dropArmBaselineChangeCount = NSPasteboard(name: .drag).changeCount
        startDropArmTimer()
    }

    private func startDropArmTimer() {
        guard dropArmTimer == nil else { return }
        let timer = Timer(timeInterval: Self.dropArmPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollDropArm() }
        }
        timer.tolerance = Self.dropArmPollInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        dropArmTimer = timer
    }

    private func pollDropArm() {
        guard isPrimaryButtonPressed() else {
            let location = mouseLocation()
            if isNativeFileDragActive {
                // Give AppKit time to deliver the drop before recovering a lost end callback.
                let now = ProcessInfo.processInfo.systemUptime
                if let releasedAt = nativeReleaseObservedAt {
                    if now - releasedAt >= 0.25 { dropWindow?.cancelFileDrag(at: location) }
                } else {
                    nativeReleaseObservedAt = now
                }
            } else {
                handleMouseUp(at: location)
                stopDropArmTimer()
                hideDropZone()
            }
            return
        }
        nativeReleaseObservedAt = nil
        guard !isDropZoneShown, let baseline = dropArmBaselineChangeCount else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != baseline else { return }
        dropArmBaselineChangeCount = nil
        guard FileDragPasteboard.containsDroppableContent(pasteboard) else {
            stopDropArmTimer()
            return
        }
        showDropZone()
    }

    private func stopDropArmTimer() {
        nativeReleaseObservedAt = nil
        dropArmTimer?.invalidate()
        dropArmTimer = nil
        dropArmBaselineChangeCount = nil
    }

    private func showDropZone() {
        guard let dropWindow, !isDropZoneShown else { return }
        isDropZoneShown = true
        placeDropZone()
        dropWindow.setHoverDetectionEnabled(true)
        dropWindow.orderFrontRegardless()
    }

    private func placeDropZone() {
        guard let dropWindow,
              let window = notchWindow,
              !requestedRect.isNull,
              !requestedRect.isEmpty else { return }
        var zone = window.convertToScreen(requestedRect)
        if isDropZoneEngaged {
            zone = zone.insetBy(dx: -Self.dropZoneOutset.width, dy: 0)
            zone.origin.y -= Self.dropZoneOutset.height
            zone.size.height += Self.dropZoneOutset.height
        }
        if let screen = window.screen { zone = zone.intersection(screen.frame) }
        guard !zone.isEmpty, !zone.equalTo(dropWindow.frame) else { return }
        dropWindow.setFrame(zone, display: false)
    }

    private func setDropZoneEngaged(_ isEngaged: Bool) {
        guard isDropZoneEngaged != isEngaged else { return }
        isDropZoneEngaged = isEngaged
        if isDropZoneShown { placeDropZone() }
    }

    private func hideDropZone() {
        isDropZoneEngaged = false
        guard isDropZoneShown, let dropWindow else { return }
        isDropZoneShown = false
        dropWindow.setHoverDetectionEnabled(false)
        dropWindow.orderOut(nil)
    }

    private func startDragMonitoring() {
        if globalDragMonitor == nil, dragSamplingTimer == nil {
            globalDragMonitor = installGlobalDragMonitor { [weak self] event in
                MainActor.assumeIsolated { self?.handleGlobalMouseDragged(event) }
            }
        }
        // AppKit may skip motion or mouse-up during a window move or app switch.
        // Sample confirmed window motion and check the button for every sequence.
        guard dragSamplingTimer == nil else { return }

        let interval: TimeInterval = 1 / 30
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleMouseDragState() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        dragSamplingTimer = timer
    }

    private func stopDragMonitoring() {
        if let globalDragMonitor {
            removeGlobalDragMonitor(globalDragMonitor)
            self.globalDragMonitor = nil
        }
        dragSamplingTimer?.invalidate()
        dragSamplingTimer = nil
    }

    private func handleGlobalMouseDragged(_ event: NSEvent) {
        guard !isSystemWindowDragSuppressed, isPrimaryButtonPressed() else { return }
        let location = screenLocation(for: event)
        if isExternalMouseDragActive {
            guard location != lastExternalMouseDragLocation else { return }
            lastExternalMouseDragLocation = location
            let isInside = probeWindow?.isVisible == true
                && (probeWindow?.frame.contains(location) ?? false)
            handlers?.onMouseDrag(isInside, location)
        } else {
            handleMouseDragged(at: location)
        }
    }

    private func scheduleDeferredDisarm(
        of probeWindow: HoverProbeWindow,
        sequenceGeneration: UInt64,
        allowsLateNativeFileDrag: Bool
    ) {
        guard deferredDisarmTask == nil else { return }
        deferredDisarmTask = Task { @MainActor [weak self, weak probeWindow] in
            if allowsLateNativeFileDrag {
                try? await Task.sleep(for: Self.lateNativeFileDragGrace)
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled,
                  let self,
                  let probeWindow,
                  self.mouseDownLocation == nil,
                  self.activeMouseSequenceGeneration == sequenceGeneration,
                  !self.isNativeFileDragActive else { return }
            if let location = self.pendingPlainDragEndLocation,
               !self.didObserveFileDragInMouseSequence {
                self.handlers?.onMouseDrag(false, location)
                self.handlers?.onMouseDragEnded(location)
            }
            if let location = self.pendingProactiveFileDragEndLocation,
               !self.isNativeFileDragActive {
                self.isProactiveFileDragTargeted = false
                self.handlers?.onFileDrag(false, location)
                self.handlers?.onFileDragEnded(location, false)
            }
            self.pendingPlainDragEndLocation = nil
            self.pendingProactiveFileDragEndLocation = nil
            self.lastIdleDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
            self.dragPasteboardChangeCountBeforeMouseSequence = nil
            self.didObserveFileDragInMouseSequence = false
            self.didTargetFileDragInMouseSequence = false
            self.activeMouseSequenceGeneration = nil
            probeWindow.setArmedForMouseSequence(false)
            self.deferredDisarmTask = nil
            self.stopGlobalMouseUpMonitoring()
            self.syncLocalMouseMonitor()
        }
    }

    private func sampleMouseDragState() {
        if isExternalMouseDragActive {
            // A release can be missing from event delivery as well. Clean up
            // even during Mission Control handoff; the next drag starts fresh.
            guard isPrimaryButtonPressed() else {
                setExternalMouseDragActive(false)
                return
            }
            guard !isSystemWindowDragSuppressed else { return }
            let location = mouseLocation()
            if location != lastExternalMouseDragLocation {
                lastExternalMouseDragLocation = location
                let isInside = probeWindow?.isVisible == true
                    && (probeWindow?.frame.contains(location) ?? false)
                handlers?.onMouseDrag(isInside, location)
            }
            return
        }

        guard activeMouseSequenceGeneration != nil else {
            stopDragMonitoring()
            return
        }
        guard isPrimaryButtonPressed() else {
            handleMouseUp(at: mouseLocation())
            return
        }
        guard !isSystemWindowDragSuppressed, globalDragMonitor == nil else { return }
        let location = mouseLocation()
        if !hasObservedMouseDrag {
            guard let origin = mouseDownLocation else {
                mouseDownLocation = location
                return
            }
            let dx = location.x - origin.x
            let dy = location.y - origin.y
            guard (dx * dx) + (dy * dy) >= Self.mouseDragThresholdSquared else { return }
            hasObservedMouseDrag = true
            probeWindow?.setArmedForMouseSequence(true)
        }
        refreshMouseDragContainment(at: location)
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        guard let eventWindow = event.window else { return event.locationInWindow }
        return eventWindow.convertPoint(toScreen: event.locationInWindow)
    }
}
