import CoreAudio
import Foundation

enum AudioControllerError: LocalizedError {
    case noDefaultOutput
    case unsupported
    case coreAudio(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noDefaultOutput: "No default audio output device is available."
        case .unsupported: "The current audio device does not support this control."
        case .coreAudio(let status): "CoreAudio returned error \(status)."
        }
    }
}

struct AudioController: Sendable {
    func toggleMute() throws {
        let device = try defaultOutputDevice()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { throw AudioControllerError.unsupported }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        guard status == noErr else { throw AudioControllerError.coreAudio(status) }
        muted = muted == 0 ? 1 : 0
        status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &muted)
        guard status == noErr else { throw AudioControllerError.coreAudio(status) }
    }

    func adjustVolume(by delta: Float32) throws {
        let device = try defaultOutputDevice()
        if try adjustMasterVolume(device: device, by: delta) { return }
        var changed = false
        for channel in [UInt32(1), UInt32(2)] {
            changed = try adjustVolume(device: device, channel: channel, by: delta) || changed
        }
        if !changed { throw AudioControllerError.unsupported }
    }

    private func defaultOutputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr else { throw AudioControllerError.coreAudio(status) }
        guard device != kAudioObjectUnknown else { throw AudioControllerError.noDefaultOutput }
        return device
    }

    private func adjustMasterVolume(device: AudioDeviceID, by delta: Float32) throws -> Bool {
        try adjustVolume(device: device, channel: kAudioObjectPropertyElementMain, by: delta)
    }

    private func adjustVolume(device: AudioDeviceID, channel: UInt32, by delta: Float32) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        guard status == noErr else { throw AudioControllerError.coreAudio(status) }
        volume = min(1, max(0, volume + delta))
        status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume)
        guard status == noErr else { throw AudioControllerError.coreAudio(status) }
        return true
    }
}
