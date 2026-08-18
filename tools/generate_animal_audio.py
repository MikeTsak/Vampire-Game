"""
Animal Audio Generator — PS1 Horror Vampire Game
Procedurally generates CC0 animal audio assets using only Python stdlib.
Sounds:
  1. hoof_step.wav       – single hoof impact on dirt
  2. sheep_bleat.wav     – sheep idle vocalization
  3. deer_snort.wav      – deer idle snort/grunt
  4. animal_death.wav    – brutal death cry (shared)
"""
import wave, math, random, struct, os

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "audio")
os.makedirs(OUT_DIR, exist_ok=True)

SR = 22050
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
    print(f"  [OK] {filename}  ({len(int_s)/SR:.2f}s, {os.path.getsize(path)//1024} KB)")

def sine(t, freq, amp=1.0):
    return amp * math.sin(2 * math.pi * freq * t)

def noise(amp=1.0):
    return random.uniform(-amp, amp)

def lowpass(samples, cutoff):
    rc = 1.0 / (2 * math.pi * cutoff)
    dt = 1.0 / SR
    alpha = dt / (rc + dt)
    out, prev = [], 0.0
    for s in samples:
        prev = prev + alpha * (s - prev)
        out.append(prev)
    return out

def adsr(samples, attack, decay, sustain, release):
    """Apply ADSR envelope. All times in seconds, sustain is 0-1 level."""
    n = len(samples)
    a_s = int(attack * SR)
    d_s = int(decay * SR)
    r_s = int(release * SR)
    s_s = max(0, n - a_s - d_s - r_s)
    out = []
    for i, s in enumerate(samples):
        if i < a_s:
            env = i / max(1, a_s)
        elif i < a_s + d_s:
            env = 1.0 - (1.0 - sustain) * ((i - a_s) / max(1, d_s))
        elif i < a_s + d_s + s_s:
            env = sustain
        else:
            prog = (i - a_s - d_s - s_s) / max(1, r_s)
            env = sustain * (1.0 - prog)
        out.append(s * env)
    return out

# ─────────────────────────────────────────────────────────────────
# 1. HOOF STEP  (hollow thump + dirt scatter)
# ─────────────────────────────────────────────────────────────────
print("Generating hoof_step.wav...")
dur = 0.28
n = int(dur * SR)
samples = []
for i in range(n):
    t = i / SR
    # Hollow clop — two resonant tones
    clop_env = math.exp(-t * 35.0)
    clop = (sine(t, 180.0, 0.55) + sine(t, 280.0, 0.25) + sine(t, 90.0, 0.35)) * clop_env
    # Dirt scatter — band-limited noise burst
    scatter_env = math.exp(-t * 28.0)
    scatter = noise(0.35) * scatter_env
    samples.append(clop + scatter)
samples = lowpass(samples, 5000)
samples = [clamp(s * 0.88) for s in samples]
write_wav("hoof_step.wav", samples)

# ─────────────────────────────────────────────────────────────────
# 2. SHEEP BLEAT  (formant vowel + vibrato + nasal quality)
# ─────────────────────────────────────────────────────────────────
print("Generating sheep_bleat.wav...")
dur = 0.9
n = int(dur * SR)
samples = []
for i in range(n):
    t = i / SR
    # Sheep pitch: starts ~400Hz, slides down to ~250Hz
    pitch = 400.0 - 160.0 * (t / dur)
    # Vibrato modulation
    vib = 1.0 + 0.04 * math.sin(2 * math.pi * 7.0 * t)
    # Fundamental + harmonics (sheep has lots of 2nd harmonic)
    voice = (sine(t, pitch * vib, 0.5)
           + sine(t, pitch * 2 * vib, 0.35)
           + sine(t, pitch * 3 * vib, 0.15)
           + sine(t, pitch * 0.5 * vib, 0.2))
    # Nasal formant at ~1800 Hz
    nasal = sine(t, 1800.0, 0.12) * math.sin(2 * math.pi * pitch * vib * t)
    samples.append((voice + nasal) * 0.55)
samples = adsr(samples, 0.03, 0.05, 0.75, 0.2)
samples = lowpass(samples, 4500)
write_wav("sheep_bleat.wav", samples)

# ─────────────────────────────────────────────────────────────────
# 3. DEER SNORT  (nasal burst + low grunt)
# ─────────────────────────────────────────────────────────────────
print("Generating deer_snort.wav...")
dur = 0.45
n = int(dur * SR)
samples = []
for i in range(n):
    t = i / SR
    # Short percussive nasal burst (snort)
    snort_env = math.exp(-t * 18.0)
    snort = noise(0.55) * snort_env
    # Low grunt undertone  
    grunt_env = math.exp(-t * 6.0)
    grunt_pitch = 85.0 + 25.0 * math.exp(-t * 10.0)
    grunt = sine(t, grunt_pitch, 0.45) * grunt_env + sine(t, grunt_pitch * 2, 0.2) * grunt_env
    samples.append(snort + grunt)
samples = lowpass(samples, 6000)
samples = adsr(samples, 0.005, 0.05, 0.6, 0.15)
samples = [clamp(s * 0.85) for s in samples]
write_wav("deer_snort.wav", samples)

# ─────────────────────────────────────────────────────────────────
# 4. ANIMAL DEATH CRY  (distressed bleat → cutoff → thud)
# ─────────────────────────────────────────────────────────────────
print("Generating animal_death.wav...")
dur = 1.2
n = int(dur * SR)
samples = []
for i in range(n):
    t = i / SR
    # Phase 1: panicked high bleat (0 – 0.35s)
    cry_pitch = 500.0 - 200.0 * min(t / 0.35, 1.0)
    cry_env = min(t / 0.05, 1.0) * max(0, 1.0 - (t - 0.1) / 0.28)
    cry_env = max(0, cry_env)
    cry = (sine(t, cry_pitch, 0.6) + sine(t, cry_pitch * 2, 0.25) + noise(0.08)) * cry_env
    # Phase 2: body thud (0.35 – 0.65s)
    thud_t = t - 0.35
    thud_env = max(0, math.exp(-thud_t * 20.0)) if t > 0.35 else 0.0
    thud = (sine(t, 80.0, 0.7) + sine(t, 130.0, 0.3) + noise(0.3) * 0.5) * thud_env
    # Phase 3: death rattle/exhale (0.5 – 1.2s)
    rattle_t = t - 0.5
    rattle_env = max(0, math.exp(-rattle_t * 4.0)) if t > 0.5 else 0.0
    rattle = noise(0.35) * rattle_env * math.sin(2 * math.pi * 8.0 * t)
    samples.append(cry + thud + rattle)
samples = lowpass(samples, 5500)
samples = [clamp(s * 0.9) for s in samples]
write_wav("animal_death.wav", samples)

print("\nAll animal audio generated in:", os.path.abspath(OUT_DIR))
