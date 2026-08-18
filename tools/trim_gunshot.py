"""
Cuts a single shot out of the full rifle take.

The supplied recording (audio/source/gunshot_full_take.wav) is 14.71s holding
about 25 separate shots. Playing it whole on every trigger pull is what made
the gun sound like it looped forever -- it was not looping, it was playing an
entire firing sequence each time.

This lifts the best single bang out of it: the shot at 9.10s, which has the
sharpest attack in the take (3.4ms) and 1.17s of clear air behind it, then
normalises it hot so the shot actually cracks.

The source lives under audio/source/, which carries a .gdignore so Godot never
imports the 1.3MB original alongside the trimmed one.

Stdlib only, to match the other audio tools.
"""
import math, os, struct, wave

HERE = os.path.dirname(__file__)
SRC = os.path.join(HERE, "..", "audio", "source", "gunshot_full_take.wav")
DST = os.path.join(HERE, "..", "audio", "gunshot.wav")

SHOT_AT = 9.10       # seconds into the take
PRE_ROLL = 0.006     # a sliver of air so the transient is never clipped
LENGTH = 1.10        # crack + tail, ending before the next shot at 10.30s
FADE_OUT = 0.30
TARGET_PEAK = 0.97   # ~-0.26 dBFS
DRIVE = 2.1          # pre-limiter gain; see the soft-clip note below


def main():
    w = wave.open(SRC)
    rate, width, ch = w.getframerate(), w.getsampwidth(), w.getnchannels()
    raw = w.readframes(w.getnframes())
    w.close()
    assert width == 2 and ch == 1, "expected 16-bit mono, got %d-bit %dch" % (width * 8, ch)

    x = []
    for i in range(0, len(raw) - 1, 2):
        v = raw[i] | (raw[i + 1] << 8)
        x.append((v - 65536 if v & 0x8000 else v) / 32768.0)

    # Snap to the true onset so the attack is never shaved off.
    i_nom = int(SHOT_AT * rate)
    window = x[i_nom:i_nom + int(0.20 * rate)]
    pk = max(abs(v) for v in window)
    onset = i_nom
    for i, v in enumerate(window):
        if abs(v) > pk * 0.05:
            onset = i_nom + i
            break

    start = max(0, onset - int(PRE_ROLL * rate))
    seg = x[start:start + int(LENGTH * rate)]

    # Peak-normalising alone does not make a shot sound loud -- it only moves
    # the single highest sample to full scale. Driving into a tanh soft-clip
    # lifts the body of the crack toward the peak instead, which is what the ear
    # reads as loudness, and the mild saturation suits a gunshot.
    peak = max(abs(v) for v in seg) or 1.0
    seg = [math.tanh(v / peak * DRIVE) for v in seg]
    peak = max(abs(v) for v in seg) or 1.0
    seg = [v * (TARGET_PEAK / peak) for v in seg]

    fi = max(1, int(0.0008 * rate))
    for i in range(min(fi, len(seg))):
        seg[i] *= i / fi
    fo = int(FADE_OUT * rate)
    for i in range(min(fo, len(seg))):
        j = len(seg) - 1 - i
        seg[j] *= (i / fo) ** 1.5

    ints = [int(max(-1.0, min(1.0, v)) * 32767) for v in seg]
    with wave.open(DST, "w") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(struct.pack("<%dh" % len(ints), *ints))
    rms = (sum(v * v for v in seg) / len(seg)) ** 0.5
    print("  [OK] gunshot.wav  %.2fs  %dHz  %d KB  peak %.2f  rms %.3f (was 14.71s)" % (
        len(ints) / rate, rate, os.path.getsize(DST) // 1024, max(abs(v) for v in seg), rms))


if __name__ == "__main__":
    main()
