@tool
extends Node

## Peak-cache envelope for the waveform (osu!-style).
##
## compute_peaks() runs ONE async pass per song and stores a compact min/max
## envelope (PEAKS_PER_SEC buckets, 2 bytes each). Views then read windows
## out of the cache via sample_range() — drawing is synchronous and cheap,
## so the waveform follows playback/zoom every frame with no textures,
## no GPU size limits and no render livelock.

signal generation_progress(normalized_progress)

## Envelope resolution: 5 ms per bucket. At 600 px/sec (1.67 ms/px) a few
## columns share one bucket — smooth enough, and cheap to compute.
const PEAKS_PER_SEC := 200
## Max raw samples scanned per bucket (evenly strided). Enough for a stable
## min/max envelope without decoding every sample.
const SAMPLES_PER_BUCKET := 24

var is_working := false
var must_abort := false

# --- peak cache (one entry per bucket, stored 0..255, 128 = silence) ---
var peak_min := PackedByteArray()
var peak_max := PackedByteArray()
var peak_count := 0
var peak_rate := PEAKS_PER_SEC
var song_length := 0.0


func has_peaks() -> bool:
	return peak_count > 0 and peak_min.size() == peak_count and peak_max.size() == peak_count


## Min/max envelope bytes (0..255, 128 = silence) over [t0_sec, t1_sec].
## Returns Vector2i(min_byte, max_byte). Synchronous — safe every frame.
func sample_range(t0_sec: float, t1_sec: float) -> Vector2i:
	if not has_peaks():
		return Vector2i(128, 128)
	var b0 := clampi(int(t0_sec * float(peak_rate)), 0, peak_count - 1)
	var b1 := clampi(int(t1_sec * float(peak_rate)), 0, peak_count - 1)
	if b1 < b0:
		var tmp := b0
		b0 = b1
		b1 = tmp
	var mn := 128
	var mx := 128
	for b in range(b0, b1 + 1):
		mn = mini(mn, int(peak_min[b]))
		mx = maxi(mx, int(peak_max[b]))
	return Vector2i(mn, mx)


func abort() -> void:
	if is_working:
		must_abort = true
		while is_working:
			await get_tree().process_frame


## One pass over the song, fills the min/max envelope. Returns false when
## aborted or the format is unsupported (caller should drop the result).
func compute_peaks(stream: AudioStreamWAV) -> bool:
	if stream == null:
		return false
	if stream.format == AudioStreamWAV.FORMAT_IMA_ADPCM:
		return false # not supported
	var data := stream.data
	if data.is_empty():
		return false
	if is_working:
		must_abort = true
		while is_working:
			await get_tree().process_frame
	is_working = true
	must_abort = false

	var bytes_per_sample := 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var channels := 2 if stream.stereo else 1
	var frame_size := bytes_per_sample * channels
	var frame_count := int(data.size() / frame_size)
	var mix_rate := float(maxi(1, stream.mix_rate))
	song_length = float(frame_count) / mix_rate
	peak_rate = PEAKS_PER_SEC
	peak_count = maxi(1, int(ceil(song_length * float(peak_rate))))
	peak_min.resize(peak_count)
	peak_max.resize(peak_count)

	var frames_per_bucket := float(frame_count) / float(peak_count)
	var stride := maxi(1, int(frames_per_bucket / float(SAMPLES_PER_BUCKET)))
	var is_16bit := stream.format == AudioStreamWAV.FORMAT_16_BITS

	for b in range(peak_count):
		var f0 := int(b * frames_per_bucket)
		var f1 := mini(frame_count, int((b + 1) * frames_per_bucket))
		var mn := 1.0
		var mx := -1.0
		var f := f0
		while f < f1:
			for ch in range(channels):
				var v := _decode_sample(data, (f * channels + ch) * bytes_per_sample, is_16bit)
				mn = minf(mn, v)
				mx = maxf(mx, v)
			f += stride
		# Buckets narrower than the stride still need at least one sample.
		if f0 < f1 and mx < mn:
			for ch in range(channels):
				var v := _decode_sample(data, (f0 * channels + ch) * bytes_per_sample, is_16bit)
				mn = minf(mn, v)
				mx = maxf(mx, v)
		peak_min[b] = clampi(int(round(mn * 127.0)) + 128, 0, 255)
		peak_max[b] = clampi(int(round(mx * 127.0)) + 128, 0, 255)

		if must_abort:
			is_working = false
			must_abort = false
			return false
		if (b % 128) == 0:
			emit_signal("generation_progress", float(b) / float(peak_count))
			await get_tree().process_frame

	is_working = false
	emit_signal("generation_progress", 1.0)
	return true


func _decode_sample(data: PackedByteArray, off: int, is_16bit: bool) -> float:
	if is_16bit:
		if off + 1 >= data.size():
			return 0.0
		var v := int(data[off]) | (int(data[off + 1]) << 8)
		if v >= 32768:
			v -= 65536
		return float(v) / 32768.0
	if off >= data.size():
		return 0.0
	return (float(data[off]) - 128.0) / 128.0
