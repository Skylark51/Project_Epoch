class_name NotificationSoundPlayer
extends AudioStreamPlayer

var tone: AudioStreamWAV


func _ready() -> void:
    tone = _build_tone()
    stream = tone
    volume_db = -15.0


func play_notification(notification: Dictionary) -> void:
    pitch_scale = 1.18 if String(notification.get("severity", "")) in ["urgent", "decision_required"] else 1.0
    play()


func _build_tone() -> AudioStreamWAV:
    var wave := AudioStreamWAV.new()
    wave.format = AudioStreamWAV.FORMAT_16_BITS
    wave.mix_rate = 22050
    wave.stereo = false
    var samples := 2646
    var bytes := PackedByteArray()
    bytes.resize(samples * 2)
    for index in range(samples):
        var envelope := 1.0 - float(index) / float(samples)
        var sample := int(sin(TAU * 660.0 * float(index) / 22050.0) * 8000.0 * envelope)
        var encoded := sample & 0xffff
        bytes[index * 2] = encoded & 0xff
        bytes[index * 2 + 1] = (encoded >> 8) & 0xff
    wave.data = bytes
    return wave
