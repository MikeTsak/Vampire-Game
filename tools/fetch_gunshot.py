"""
Replaces the synthesised gunshot with a real rifle recording.

Source: "GOLD TAPE: 33 Explosions and War", track 04 "Rifle Cracks with
Ricochet", from archive.org. Released CC0 1.0 (public domain dedication), so it
can ship in a commercial game with no attribution required.
  https://archive.org/details/GOLD_TAPE_33_Explosions_and_War

The tape is 21s of grouped shots. This pulls the single cleanest one -- the
last of the third burst, at ~18.50s, which has a 5ms attack and ~2.6s of
uninterrupted outdoor tail behind it -- then trims, normalises and fades it.

Kept at 48kHz/16-bit rather than the 22050Hz the other assets use: the crack of
a rifle lives in the top octaves, and downsampling is exactly what made the old
one sound synthetic.

Stdlib only, to match tools/generate_audio.py.
"""
import os, struct, urllib.request, wave

HERE = os.path.dirname(__file__)
OUT_DIR = os.path.join(HERE, "..", "audio")
CACHE_DIR = os.path.join(HERE, ".cache")
CACHE = os.path.join(CACHE_DIR, "gunshot_source.wav")
URL = ("https://archive.org/download/GOLD_TAPE_33_Explosions_and_War/"
       "G33-04-Rifle%20Cracks%20with%20Ricochet.wav")

SHOT_AT = 18.50      # seconds into the source
PRE_ROLL = 0.008     # keep a sliver of air before the transient
LENGTH = 1.90        # crack plus most of the natural tail
FADE_OUT = 0.35      # taper the tail so it does not cut off
TARGET_PEAK = 0.89   # ~-1 dBFS


def fetch():
    os.makedirs(CACHE_DIR, exist_ok=True)
    # .gdignore keeps the 5MB source out of Godot's import pipeline.
    open(os.path.join(CACHE_DIR, ".gdignore"), "a").close()
    if os.path.exists(CACHE) and os.path.getsize(CACHE) > 1_000_000:
        print("  using cached source")
        return
    print("  downloading CC0 source from archive.org ...")
    req = urllib.request.Request(URL, headers={"User-Agent": "vampire-game-build/1.0"})
    with urllib.request.urlopen(req, timeout=180) as r, open(CACHE, "wb") as f:
        f.write(r.read())
    print("  got %d KB" % (os.path.getsize(CACHE) // 1024))


def read_mono_24(path):
    w = wave.open(path)
    rate, width, ch, n = w.getframerate(), w.getsampwidth(), w.getnchannels(), w.getnframes()
    raw = w.readframes(n)
    w.close()
    assert width == 3, "expected 24-bit source, got %d bytes/sample" % width
    step = width * ch
    out = []
    for i in range(0, len(raw) - step + 1, step):
        v = raw[i] | (raw[i + 1] << 8) | (raw[i + 2] << 16)
        if v & 0x800000:
            v -= 1 << 24
        out.append(v / 8388608.0)
    return out, rate


def main():
    fetch()
    x, rate = read_mono_24(CACHE)

    # Snap to the true onset: walk back from the nominal position to where the
    # signal last sat in the noise floor, so the attack is never clipped.
    i_nom = int(SHOT_AT * rate)
    window = x[i_nom:i_nom + int(0.25 * rate)]
    pk = max(abs(v) for v in window)
    onset = i_nom
    for i in range(len(window)):
        if abs(window[i]) > pk * 0.05:
            onset = i_nom + i
            break

    start = max(0, onset - int(PRE_ROLL * rate))
    seg = x[start:start + int(LENGTH * rate)]

    peak = max(abs(v) for v in seg) or 1.0
    gain = TARGET_PEAK / peak
    seg = [v * gain for v in seg]

    # 1ms in, long taper out.
    fi = int(0.001 * rate)
    for i in range(min(fi, len(seg))):
        seg[i] *= i / fi
    fo = int(FADE_OUT * rate)
    for i in range(min(fo, len(seg))):
        j = len(seg) - 1 - i
        seg[j] *= (i / fo) ** 1.6

    ints = [int(max(-1.0, min(1.0, v)) * 32767) for v in seg]
    path = os.path.join(OUT_DIR, "gunshot.wav")
    with wave.open(path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(struct.pack("<%dh" % len(ints), *ints))
    print("  [OK] gunshot.wav  (%.2fs, %dHz, %d KB)" % (
        len(ints) / rate, rate, os.path.getsize(path) // 1024))


if __name__ == "__main__":
    main()
