"""
PS1 Horror Audio Generator
Procedurally generates CC0 audio assets for the Vampire Game.
No external dependencies — uses only Python stdlib (wave, math, random, struct).
Output: res://audio/*.wav
"""
import wave, math, random, struct, os, array

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "audio")
os.makedirs(OUT_DIR, exist_ok=True)

SAMPLE_RATE = 22050   # Low sample-rate for that PS1 lo-fi quality
CHANNELS    = 1
BIT_DEPTH   = 16

def clamp(v, lo=-1.0, hi=1.0):
    return max(lo, min(hi, v))

def write_wav(filename, samples):
    """samples is a list of floats in [-1, 1]"""
    path = os.path.join(OUT_DIR, filename)
    int_samples = [int(clamp(s) * 32767) for s in samples]
    packed = struct.pack(f"<{len(int_samples)}h", *int_samples)
    with wave.open(path, "w") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(packed)
    size_kb = os.path.getsize(path) // 1024
    print(f"  [OK] {filename}  ({len(int_samples)//SAMPLE_RATE:.1f}s, {size_kb} KB)")

def noise(amplitude=1.0):
    return random.uniform(-amplitude, amplitude)

def sine(t, freq, amplitude=1.0):
    return amplitude * math.sin(2 * math.pi * freq * t)

def lowpass(samples, cutoff, sr=SAMPLE_RATE):
    """Simple one-pole IIR low-pass filter."""
    rc = 1.0 / (2 * math.pi * cutoff)
    dt = 1.0 / sr
    alpha = dt / (rc + dt)
    out = []
    prev = 0.0
    for s in samples:
        prev = prev + alpha * (s - prev)
        out.append(prev)
    return out

# ─────────────────────────────────────────────────────
# 1. FOREST AMBIENCE  (30 seconds, loopable)
#    Wind noise + slow drone + high cricket chirps
# ─────────────────────────────────────────────────────
print("Generating forest_ambience.wav ...")
dur = 30
n = dur * SAMPLE_RATE
t_arr = [i / SAMPLE_RATE for i in range(n)]

samples = []
for i, t in enumerate(t_arr):
    # Wind: band-limited noise
    wind_raw = noise(0.18)
    # Slow eerie drone: two detuned low sines
    drone = sine(t, 48.0, 0.10) + sine(t, 51.3, 0.07) + sine(t, 96.0, 0.04)
    # Subtle cricket pulse: 4 kHz bursts modulated at 3 Hz
    cricket_mod = 0.5 + 0.5 * math.sin(2 * math.pi * 3.0 * t)
    cricket = sine(t, 4000.0, 0.035 * cricket_mod)
    # Occasional low rumble swell
    swell = 0.5 + 0.5 * math.sin(2 * math.pi * 0.05 * t)
    samples.append(wind_raw + drone * swell + cricket)

# Low-pass to keep it muddy (PS1 style)
samples = lowpass(samples, 5000)
write_wav("forest_ambience.wav", samples)

# ─────────────────────────────────────────────────────
# 2. GUNSHOT  (WWI bolt-action, punchy)
# ─────────────────────────────────────────────────────
print("Generating gunshot.wav ...")
dur = 1.5
n = int(dur * SAMPLE_RATE)
samples = []
for i in range(n):
    t = i / SAMPLE_RATE
    # Initial transient bang: noise burst with sharp exponential decay
    bang_env = math.exp(-t * 60.0)
    bang = noise(1.0) * bang_env * 1.0
    # Low body thump
    thump_env = math.exp(-t * 15.0)
    thump = sine(t, 80.0, 0.6 * thump_env) + sine(t, 120.0, 0.3 * thump_env)
    # High crack / pressure wave
    crack_env = math.exp(-t * 40.0)
    crack = noise(0.5) * crack_env * 0.7
    # Tail rumble (mechanical bolt rattle)
    rattle_start = 0.08
    rattle_env = max(0, math.exp(-(t - rattle_start) * 25.0)) if t > rattle_start else 0
    rattle = noise(0.3) * rattle_env
    samples.append(bang + thump + crack + rattle)

samples = [clamp(s * 0.8) for s in samples]
write_wav("gunshot.wav", samples)

# ─────────────────────────────────────────────────────
# 3. FOOTSTEP  (dirt/grass, single step)
# ─────────────────────────────────────────────────────
print("Generating footstep.wav ...")
dur = 0.35
n = int(dur * SAMPLE_RATE)
samples = []
for i in range(n):
    t = i / SAMPLE_RATE
    # Soft impact thump
    thump_env = math.exp(-t * 30.0)
    thump = (sine(t, 90.0, 0.5) + sine(t, 140.0, 0.2)) * thump_env
    # Dirt/crunch texture: noise with mid-frequency emphasis
    crunch_env = math.exp(-t * 20.0)
    crunch = noise(0.4) * crunch_env
    # Grass swish high-freq tail
    swish_env = math.exp(-t * 45.0)
    swish = noise(0.15) * swish_env
    samples.append(thump + crunch + swish)

samples = lowpass(samples, 4500)
samples = [clamp(s * 0.9) for s in samples]
write_wav("footstep.wav", samples)

# ─────────────────────────────────────────────────────
# 4. DIALOGUE BLIP  (low retro mumble / voice blip)
#    Short vowel-like formant synthesis
# ─────────────────────────────────────────────────────
print("Generating dialogue_blip.wav ...")
dur = 0.06  # Very short – played per-character
n = int(dur * SAMPLE_RATE)
samples = []
# Formant frequencies for a neutral vowel "uh"
F1, F2 = 500.0, 1200.0
for i in range(n):
    t = i / SAMPLE_RATE
    env = math.sin(math.pi * t / dur)  # smooth bell envelope
    # Buzzy voice source (sawtooth-like via harmonics)
    pitch = 130.0  # low male voice
    voice = sum(sine(t, pitch * k, 1.0 / k) for k in range(1, 6))
    # Shape with formants (bandpass peaks)
    vowel = sine(t, F1, 0.6) + sine(t, F2, 0.3)
    sample = (voice * 0.4 + vowel * 0.6) * env * 0.7
    samples.append(sample)

samples = lowpass(samples, 3000)
samples = [clamp(s) for s in samples]
write_wav("dialogue_blip.wav", samples)

print("\nAll audio assets generated successfully in:", os.path.abspath(OUT_DIR))
