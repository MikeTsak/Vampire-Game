"""
Realistic WWI Bolt-Action Rifle Shot Generator
Synthesizes a layered, loud, punchy gunshot using only Python stdlib.

Layers:
  1. Supersonic bullet crack  — ultra-sharp 0.3ms spike
  2. Muzzle blast             — broadband pressure wave burst
  3. Chamber resonance        — metallic 200/380Hz ring
  4. Powder boom              — deep 65Hz subsonic body
  5. Forest echo tail         — 3 decaying echo taps

Output: res://audio/gunshot.wav   (44100 Hz, 16-bit, mono, ~1.8s)
"""
import wave, math, random, struct, os

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "audio")
SR = 44100
CHANNELS = 1

def clamp(v, lo=-1.0, hi=1.0):
    return max(lo, min(hi, v))

def write_wav(filename, samples):
    path = os.path.join(OUT_DIR, filename)
    int_s = [int(clamp(s) * 32767) for s in samples]
    packed = struct.pack(f"<{len(int_s)}h", *int_s)
    with wave.open(path, "w") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(packed)
    size_kb = os.path.getsize(path) // 1024
    print(f"  [OK] {filename}  ({len(int_s)/SR:.2f}s, {size_kb} KB, peak={max(abs(s) for s in samples):.3f})")

def sine(t, freq, amp=1.0):
    return amp * math.sin(2 * math.pi * freq * t)

def noise():
    return random.gauss(0, 0.33)  # Gaussian noise sounds more natural than uniform

def lowpass(samples, cutoff):
    rc  = 1.0 / (2 * math.pi * cutoff)
    dt  = 1.0 / SR
    alpha = dt / (rc + dt)
    out, prev = [], 0.0
    for s in samples:
        prev = prev + alpha * (s - prev)
        out.append(prev)
    return out

def highpass(samples, cutoff):
    """Simple 1-pole highpass to remove rumble or shape spectrum."""
    rc  = 1.0 / (2 * math.pi * cutoff)
    dt  = 1.0 / SR
    alpha = rc / (rc + dt)
    out, prev_in, prev_out = [], 0.0, 0.0
    for s in samples:
        y = alpha * (prev_out + s - prev_in)
        prev_in, prev_out = s, y
        out.append(y)
    return out

def add_echo(samples, delay_s, decay, n):
    """Add n echo taps with delay_s spacing and exponential decay."""
    out = list(samples)
    delay_samps = int(delay_s * SR)
    for tap in range(1, n + 1):
        offset = delay_samps * tap
        att = decay ** tap
        for i in range(len(out)):
            src = i - offset
            if src >= 0:
                out[i] = clamp(out[i] + samples[src] * att)
    return out

# ─────────────────────────────────────────────────────────────────────────────
print("Generating gunshot.wav (realistic WWI bolt-action rifle) ...")
dur = 1.8
N   = int(dur * SR)
raw = [0.0] * N

for i in range(N):
    t = i / SR
    s = 0.0

    # ── LAYER 1: Supersonic Crack ─────────────────────────────────────────
    # Extremely brief impulse spike — like a whip-crack. Decays in <3ms.
    crack_tau = 0.0007                         # 0.7ms time constant
    crack_env = math.exp(-t / crack_tau)
    # Broadband white noise burst shaped to sound like transonic crack
    crack = noise() * crack_env * 1.15

    # ── LAYER 2: Muzzle Blast ─────────────────────────────────────────────
    # Massive pressure wave — dominates 0–25ms.
    # Uses pink-ish noise (average of 4 noise sources) for realism.
    blast_tau  = 0.018                         # 18ms decay
    blast_env  = math.exp(-t / blast_tau)
    blast_pre  = 0.008                         # slight pre-delay before peak
    if t < blast_pre:
        blast_ramp = t / blast_pre             # linear ramp-up
    else:
        blast_ramp = math.exp(-(t - blast_pre) / blast_tau)
    blast_noise = (noise() + noise() + noise()) / 3.0
    blast = blast_noise * blast_ramp * 0.95

    # ── LAYER 3: Chamber / Barrel Resonance ──────────────────────────────
    # Metallic ring from the barrel tube resonating. Decays in ~60ms.
    ring_tau = 0.055
    ring_env = math.exp(-t / ring_tau)
    # Two partials — fundamental + 2nd harmonic with slight detuning
    ring = (sine(t, 210.0, 0.28) + sine(t, 385.0, 0.18) + sine(t, 620.0, 0.08)) * ring_env
    # Small bolt-clank transient at ~80ms (bolt starting to cycle)
    clank_t = t - 0.085
    if clank_t > 0:
        clank_env = math.exp(-clank_t / 0.012)
        ring += (sine(t, 900.0, 0.12) + noise() * 0.15) * clank_env

    # ── LAYER 4: Powder Boom ──────────────────────────────────────────────
    # Deep subsonic chest-punch. 60–100 Hz, decays in ~120ms.
    boom_tau  = 0.12
    boom_env  = math.exp(-t / boom_tau)
    # Slightly pitch-bending down (powder gases expanding rapidly)
    boom_freq = 68.0 + 30.0 * math.exp(-t * 40.0)
    boom = (sine(t, boom_freq, 0.70) + sine(t, boom_freq * 1.48, 0.25) +
            sine(t, boom_freq * 0.51, 0.35)) * boom_env

    # ── LAYER 5: Low-Mid Body ─────────────────────────────────────────────
    # 120–300Hz "body" that gives weight. Decays in ~80ms.
    body_tau = 0.075
    body_env = math.exp(-t / body_tau)
    body = (sine(t, 135.0, 0.30) + sine(t, 260.0, 0.18)) * body_env

    # ── MIX ───────────────────────────────────────────────────────────────
    s = crack + blast + ring * 0.6 + boom * 0.85 + body * 0.55
    raw[i] = s

# ── POST-PROCESSING ──────────────────────────────────────────────────────────

# 1. High-pass to remove DC / ultra-low rumble (not useful for PS1 aesthetic)
raw = highpass(raw, 35.0)

# 2. Forest echo (3 taps at ~110ms spacing, 35% decay each)
#    Simulates sound bouncing off trees at ~18m distance
raw = add_echo(raw, delay_s=0.11, decay=0.35, n=3)

# 3. Brick-wall limiter / soft clip — ensure we never clip while staying LOUD
#    Use tanh soft-saturation so the peak sounds punchy, not distorted
def soft_clip(s, drive=1.6):
    return math.tanh(s * drive) / math.tanh(drive)

raw = [soft_clip(s * 0.92) for s in raw]

# 4. Normalize to 98% of full scale so it's as loud as possible
peak = max(abs(s) for s in raw)
if peak > 0:
    raw = [s / peak * 0.98 for s in raw]

write_wav("gunshot.wav", raw)
print("Done. Overwriting res://audio/gunshot.wav")
