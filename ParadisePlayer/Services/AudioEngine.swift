import AVFoundation
import Observation

/// Wiedergabe mit AVAudioEngine:
/// Player -> Varispeed (Pitch wie am Plattenspieler) -> TimePitch (Key Lock) -> EQ -> Ausgang.
/// Bei Pitch 0 sind Varispeed und TimePitch umgangen, der Klang bleibt unverändert.
@MainActor
@Observable
final class AudioEngine {
    private(set) var isPlaying = false
    private(set) var isLoaded = false
    private(set) var duration: TimeInterval = 0

    // Pitch
    var pitchPercent: Double = 0 { didSet { applyPitch() } }
    var keyLock = false { didSet { applyPitch() } }

    // Equalizer (3 Bänder wie am DJ-Mixer, erweiterbar)
    static let eqBandNames = ["Low", "Mid", "High"]
    static let eqGainRange: ClosedRange<Float> = -26...10
    var eqEnabled = true { didSet { applyEQ() } }
    var eqGains: [Float] = [0, 0, 0] { didSet { applyEQ() } }
    var eqKills: [Bool] = [false, false, false] { didSet { applyEQ() } }

    var isEQActive: Bool {
        eqEnabled && (eqGains.contains { $0 != 0 } || eqKills.contains(true))
    }

    /// Wird aufgerufen, wenn ein Track bis zum Ende gespielt wurde.
    @ObservationIgnored var onTrackFinished: (() -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()
    private let timePitch = AVAudioUnitTimePitch()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)

    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var connectedFormat: AVAudioFormat?
    @ObservationIgnored private var segmentStartFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var pausedFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        configureSession()
        engine.attach(player)
        engine.attach(varispeed)
        engine.attach(timePitch)
        engine.attach(eq)
        configureEQBands()
        if let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) {
            connectChain(format: format)
        }
        applyPitch()
        applyEQ()
        observeNotifications()
    }

    // MARK: Laden

    func load(url: URL) throws {
        stopPlayer()
        let newFile = try AVAudioFile(forReading: url)
        let format = newFile.processingFormat
        if connectedFormat?.sampleRate != format.sampleRate || connectedFormat?.channelCount != format.channelCount {
            engine.stop()
            connectChain(format: format)
        }
        file = newFile
        duration = Double(newFile.length) / format.sampleRate
        pausedFrame = 0
        isLoaded = true
        try startEngineIfNeeded()
    }

    func unload() {
        stopPlayer()
        file = nil
        isLoaded = false
        duration = 0
        pausedFrame = 0
    }

    // MARK: Transport

    func play() {
        guard let file, !isPlaying else { return }
        do { try startEngineIfNeeded() } catch { return }
        guard schedule(file: file, from: pausedFrame) else {
            onTrackFinished?()
            return
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        guard isPlaying else { return }
        pausedFrame = currentFrame()
        stopPlayer()
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func seek(to time: TimeInterval) {
        guard let file else { return }
        let sampleRate = file.processingFormat.sampleRate
        let clamped = max(0, min(time, duration))
        let wasPlaying = isPlaying
        stopPlayer()
        pausedFrame = min(AVAudioFramePosition(clamped * sampleRate), max(file.length - 1, 0))
        if wasPlaying { play() }
    }

    var currentTime: TimeInterval {
        guard let file else { return 0 }
        return Double(currentFrame()) / file.processingFormat.sampleRate
    }

    // MARK: EQ

    func resetEQ() {
        eqGains = [0, 0, 0]
        eqKills = [false, false, false]
    }

    // MARK: Intern

    private func currentFrame() -> AVAudioFramePosition {
        guard isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return pausedFrame }
        let frame = segmentStartFrame + playerTime.sampleTime
        return min(max(frame, 0), file?.length ?? 0)
    }

    /// Plant die Wiedergabe ab `frame`. Gibt `false` zurück, wenn nichts mehr zu spielen ist.
    private func schedule(file: AVAudioFile, from frame: AVAudioFramePosition) -> Bool {
        let remaining = file.length - frame
        guard remaining > 0 else { return false }
        segmentStartFrame = frame
        let gen = generation
        player.scheduleSegment(
            file,
            startingFrame: frame,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { @Sendable _ in
            Task { @MainActor in self.segmentFinished(generation: gen) }
        }
        return true
    }

    private func segmentFinished(generation gen: Int) {
        // Ältere Segmente (nach Seek, Pause oder Trackwechsel) ignorieren.
        guard gen == generation, isPlaying else { return }
        isPlaying = false
        pausedFrame = file?.length ?? 0
        onTrackFinished?()
    }

    private func stopPlayer() {
        generation += 1
        player.stop()
        isPlaying = false
    }

    private func startEngineIfNeeded() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    private func connectChain(format: AVAudioFormat) {
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(varispeed)
        engine.disconnectNodeOutput(timePitch)
        engine.disconnectNodeOutput(eq)
        engine.connect(player, to: varispeed, format: format)
        engine.connect(varispeed, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        connectedFormat = format
    }

    private func applyPitch() {
        let rate = Float(1 + pitchPercent / 100)
        let neutral = abs(pitchPercent) < 0.0001
        if keyLock {
            varispeed.bypass = true
            timePitch.rate = rate
            timePitch.pitch = 0
            timePitch.bypass = neutral
        } else {
            timePitch.bypass = true
            varispeed.rate = rate
            varispeed.bypass = neutral
        }
    }

    private func configureEQBands() {
        let bands = eq.bands
        bands[0].filterType = .lowShelf
        bands[0].frequency = 150
        bands[1].filterType = .parametric
        bands[1].frequency = 1_000
        bands[1].bandwidth = 1.5
        bands[2].filterType = .highShelf
        bands[2].frequency = 4_500
        for band in bands {
            band.gain = 0
            band.bypass = false
        }
    }

    private func applyEQ() {
        for (i, band) in eq.bands.enumerated() where i < eqGains.count {
            band.gain = eqKills[i] ? -96 : eqGains[i]
        }
        eq.bypass = !eqEnabled
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        // Aktivieren im Hintergrund, damit die Oberfläche nicht blockiert
        Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    private func observeNotifications() {
        let center = NotificationCenter.default

        // Kopfhörer abgezogen -> pausieren
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
            }
        })

        // Anruf o. Ä. -> pausieren
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                if type == AVAudioSession.InterruptionType.began.rawValue { self?.pause() }
            }
        })

        // Audio-Hardware hat gewechselt, Engine wurde vom System gestoppt
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        })
    }

    private func handleConfigurationChange() {
        guard isPlaying else { return }
        pausedFrame = currentFrame()
        stopPlayer()
    }
}
