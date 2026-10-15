import CoreAudio
import Foundation

let fullScaleVolts = 10.0   // assumed: +-1.0 in the stream is about +-10 V on the jacks (es8.py)

struct ES8Error: Error { let message: String }

/// Step 3: ES-8 outputs 1-8 over Core Audio. Port of the control-voltage half of es8.py.
///
/// The audio callback only reads `target`/`slew` and writes `cur`: plain aligned Float loads and stores into
/// memory allocated up front, no locks, no allocation, no Swift objects. The main thread writes `target`/`slew`.
final class ES8Output: @unchecked Sendable {
    private static let channels = 8

    let deviceName: String
    private let device: AudioDeviceID
    private var procID: AudioDeviceIOProcID?
    private let target = UnsafeMutablePointer<Float>.allocate(capacity: ES8Output.channels)   // volts, already capped
    private let cur = UnsafeMutablePointer<Float>.allocate(capacity: ES8Output.channels)      // volts, owned by the callback
    private let slew = UnsafeMutablePointer<Float>.allocate(capacity: 1)                      // V/s, shared by all channels
    private let map = UnsafeMutablePointer<Int32>.allocate(capacity: ES8Output.channels * 3)  // per channel: buffer, channels in buffer, offset
    private let pulseRequest = UnsafeMutablePointer<Int32>.allocate(capacity: 1)               // main thread bumps it to ask for a trigger
    private let pulseState = UnsafeMutablePointer<Int32>.allocate(capacity: 2)                // callback only: [requests seen, samples left]
    private var running = false

    init() throws {
        target.initialize(repeating: 0, count: Self.channels)
        cur.initialize(repeating: 0, count: Self.channels)
        slew.initialize(to: 1)
        map.initialize(repeating: 0, count: Self.channels * 3)
        pulseRequest.initialize(to: 0)
        pulseState.initialize(repeating: 0, count: 2)

        guard let found = Self.findDevice() else {
            throw ES8Error(message: "ES-8 not found. If the rack was power cycled, unplug and replug the ES-8 USB cable.")
        }
        device = found.id
        deviceName = found.name

        // Which buffer and channel slot carries output channel 1-8. macOS reports 16 outputs; only 8 are jacks.
        let buffers = try Self.outputBuffers(of: device)
        let total = buffers.reduce(0) { $0 + Int($1) }
        guard total >= Self.channels else { throw ES8Error(message: "ES-8 reports only \(total) output channels") }
        for ch in 0..<Self.channels {
            var b = 0
            var first = 0
            while ch >= first + Int(buffers[b]) { first += Int(buffers[b]); b += 1 }
            map[ch * 3] = Int32(b)
            map[ch * 3 + 1] = Int32(buffers[b])
            map[ch * 3 + 2] = Int32(ch - first)
        }
        try Self.checkFloat32(device)
        let rate = try Self.sampleRate(of: device)
        installCallback(rate: Float(rate))
    }

    deinit {
        close()
        target.deallocate(); cur.deallocate(); slew.deallocate(); map.deallocate()
        pulseRequest.deallocate(); pulseState.deallocate()
    }

    // MARK: control (main thread)

    func start() throws {
        guard let procID, !running else { return }
        let s = AudioDeviceStart(device, procID)
        guard s == noErr else {
            throw ES8Error(message: "could not start the ES-8 (error \(s)). Unplug and replug its USB cable and try again.")
        }
        running = true
    }

    /// Aim every output at these volts (capped at +-5 V here, whatever the grid says).
    func set(targets: [Double], slew voltsPerSecond: Double) {
        slew.pointee = Float(max(0.01, voltsPerSecond))
        for ch in 0..<Self.channels {
            let v = ch < targets.count ? targets[ch] : 0
            target[ch] = Float(clamp(v, -maxVolts, maxVolts))
        }
    }

    /// A short +5 V pulse on the trigger output (Out 8), whatever else is going on. Safe to call at any time.
    func pulse() { pulseRequest.pointee &+= 1 }

    func currentVolts() -> [Double] { (0..<Self.channels).map { Double(cur[$0]) } }

    var atZero: Bool { (0..<Self.channels).allSatisfy { abs(cur[$0]) < 1e-6 } }

    /// Stop the device. Call only once the outputs are at 0 V (see `atZero`), or on a failed start.
    func close() {
        if running, let procID { AudioDeviceStop(device, procID) }
        running = false
        if let procID { AudioDeviceDestroyIOProcID(device, procID) }
        procID = nil
    }

    /// Glide everything to 0 V (10 V/s as in es8.py close), wait for it, then stop. Blocks up to ~2.5 s.
    func shutdown() {
        set(targets: [], slew: 10)
        for _ in 0..<50 where !atZero { Thread.sleep(forTimeInterval: 0.05) }
        Thread.sleep(forTimeInterval: 0.05)   // let a block of zeros go out
        close()
    }

    // MARK: audio callback

    private func installCallback(rate: Float) {
        let target = self.target, cur = self.cur, slew = self.slew, map = self.map
        let pulseRequest = self.pulseRequest, pulseState = self.pulseState
        let channels = Self.channels
        let gateCh = gateOutput, trigCh = trigOutput
        let limit = Float(maxVolts)
        let scale = Float(fullScaleVolts)
        let trigLevel = Float(gateVolts)
        let pulseSamples = Int32(trigSeconds * Double(rate))
        var id: AudioDeviceIOProcID?
        _ = AudioDeviceCreateIOProcIDWithBlock(&id, device, nil) { _, _, _, outData, _ in
            let list = UnsafeMutableAudioBufferListPointer(outData)
            for b in list where b.mData != nil { memset(b.mData, 0, Int(b.mDataByteSize)) }
            let step = slew.pointee / rate                       // largest move per sample
            for ch in 0..<channels {
                let b = Int(map[ch * 3]), n = Int(map[ch * 3 + 1]), off = Int(map[ch * 3 + 2])
                guard b < list.count, let raw = list[b].mData else { continue }
                let frames = Int(list[b].mDataByteSize) / (4 * max(n, 1))
                let out = raw.assumingMemoryBound(to: Float.self)
                if ch == trigCh {                                // trigger: a pulse of fixed length, never a level
                    let requested = pulseRequest.pointee
                    if requested != pulseState[0] { pulseState[0] = requested; pulseState[1] = pulseSamples }
                    var left = pulseState[1]
                    var last: Float = 0
                    for f in 0..<frames where left > 0 {
                        out[f * n + off] = trigLevel / scale
                        last = trigLevel
                        left -= 1
                    }
                    if left <= 0 { last = 0 }
                    pulseState[1] = left
                    cur[ch] = last
                    continue
                }
                let goal = max(-limit, min(limit, target[ch]))
                if ch == gateCh {                                // gate: snaps to its target, no glide
                    for f in 0..<frames { out[f * n + off] = goal / scale }
                    cur[ch] = goal
                    continue
                }
                var v = cur[ch]
                for f in 0..<frames {
                    v += max(-step, min(step, goal - v))          // glide: never jump, whatever the target
                    out[f * n + off] = v / scale
                }
                cur[ch] = v
            }
        }
        procID = id
    }

    // MARK: Core Audio lookups

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func findDevice(named wanted: String = "ES-8") -> (id: AudioDeviceID, name: String)? {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return nil }
        for id in ids {
            var nameAddr = address(kAudioObjectPropertyName)
            var cf: CFString?
            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            let status = withUnsafeMutablePointer(to: &cf) {
                AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, $0)
            }
            guard status == noErr, let name = cf as String?,
                  name.lowercased().contains(wanted.lowercased()),
                  let buffers = try? outputBuffers(of: id), !buffers.isEmpty else { continue }
            return (id, name)
        }
        return nil
    }

    /// Channel count of each output buffer.
    private static func outputBuffers(of device: AudioDeviceID) throws -> [UInt32] {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else {
            throw ES8Error(message: "could not read the ES-8 output layout")
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr else {
            throw ES8Error(message: "could not read the ES-8 output layout")
        }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.map { $0.mNumberChannels }
    }

    private static func checkFloat32(_ device: AudioDeviceID) throws {
        var addr = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size >= 4 else { return }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &streams) == noErr else { return }
        for s in streams {
            var fa = address(kAudioStreamPropertyVirtualFormat)
            var fmt = AudioStreamBasicDescription()
            var fsize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            guard AudioObjectGetPropertyData(s, &fa, 0, nil, &fsize, &fmt) == noErr else { continue }
            let isFloat = fmt.mFormatFlags & kAudioFormatFlagIsFloat != 0
            guard fmt.mFormatID == kAudioFormatLinearPCM, isFloat, fmt.mBitsPerChannel == 32 else {
                throw ES8Error(message: "the ES-8 stream is not 32-bit float; refusing to send")
            }
        }
    }

    private static func sampleRate(of device: AudioDeviceID) throws -> Double {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var rate = 0.0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate) == noErr, rate > 0 else {
            throw ES8Error(message: "could not read the ES-8 sample rate")
        }
        return rate
    }
}
