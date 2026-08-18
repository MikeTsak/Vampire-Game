"""
Sub-bass layer for the rifle, played on top of the existing gunshot.wav.

Kept as its own script so running it cannot clobber the other assets that
generate_audio.py produces. The existing gunshot has a good crack and bolt
rattle but its body decays fast; this adds the low punch that makes the shot
feel like it has mass behind it.

Output: res://audio/gunshot_body.wav
"""
import wave, math, random, struct, os

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "audio")
SAMPLE_RATE = 22050

random.seed(4771)


def clamp(v, lo=-1.0, hi=1.0):
    return max(lo, min(hi, v))


def write_wav(filename, samples):
    path = os.path.join(OUT_DIR, filename)
    ints = [int(clamp(s) * 32767) for s in samples]
    with wave.open(path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(struct.pack("<%dh" % len(ints), *ints))
    print("  [OK] %s  (%.2fs, %d KB)" % (
        filename, len(ints) / SAMPLE_RATE, os.path.getsize(path) // 1024))


print("Generating gunshot_body.wav ...")
dur = 0.85
n = int(dur * SAMPLE_RATE)
samples = []
phase = 0.0
lp = 0.0
for i in range(n):
    t = i / SAMPLE_RATE
    # Pitch drops from a chest-hit 115Hz down to a 42Hz rumble.
    freq = 42.0 + 73.0 * math.exp(-t * 11.0)
    phase += 2.0 * math.pi * freq / SAMPLE_RATE
    body = math.sin(phase) * math.exp(-t * 4.2) * 0.92
    # Slow-decaying low noise, heavily smoothed, for the room punch.
    lp += (random.uniform(-1.0, 1.0) - lp) * 0.045
    rumble = lp * math.exp(-t * 6.5) * 0.55
    # A single hard click at sample zero keeps it tight against the crack.
    click = math.exp(-t * 320.0) * 0.35
    samples.append(body + rumble + click)

peak = max(abs(s) for s in samples) or 1.0
samples = [s / peak * 0.95 for s in samples]
write_wav("gunshot_body.wav", samples)
