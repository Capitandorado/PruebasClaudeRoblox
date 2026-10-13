#!/usr/bin/env python3
"""Synthesises the original VOID FACTORY sound effects into assets/sounds/*.wav.

Pure standard library (no samples, no third-party assets), deterministic output.
Upload the files to Roblox (Creator Dashboard / Asset Manager) and paste the resulting
asset ids into src/shared/Config/Sounds.luau (see docs/SOUNDS.md).
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def tone(freq, seconds, shape="sine", attack=0.005, decay=None, vibrato=0.0, volume=1.0, freq_end=None):
    n = int(RATE * seconds)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq if freq_end is None else freq + (freq_end - freq) * (i / n)
        if vibrato:
            f *= 1 + vibrato * math.sin(2 * math.pi * 6 * t)
        phase += 2 * math.pi * f / RATE
        if shape == "sine":
            v = math.sin(phase)
        elif shape == "square":
            v = 1.0 if math.sin(phase) >= 0 else -1.0
        elif shape == "saw":
            v = 2 * ((phase / (2 * math.pi)) % 1) - 1
        else:  # triangle
            v = 2 * abs(2 * ((phase / (2 * math.pi)) % 1) - 1) - 1
        env = min(1.0, t / attack) if attack > 0 else 1.0
        if decay:
            env *= math.exp(-t / decay)
        else:
            env *= max(0.0, 1 - i / n)
        out.append(v * env * volume)
    return out


def noise(seconds, volume=1.0, decay=None, lowpass=0.0, seed=1, rise=False):
    rng = random.Random(seed)
    n = int(RATE * seconds)
    out = []
    prev = 0.0
    for i in range(n):
        t = i / RATE
        v = rng.uniform(-1, 1)
        prev = prev * lowpass + v * (1 - lowpass)
        env = (i / n) if rise else (math.exp(-t / decay) if decay else 1 - i / n)
        out.append(prev * env * volume)
    return out


def mix(*tracks, offsets=None):
    offsets = offsets or [0.0] * len(tracks)
    length = max(int(o * RATE) + len(t) for t, o in zip(tracks, offsets))
    out = [0.0] * length
    for track, offset in zip(tracks, offsets):
        start = int(offset * RATE)
        for i, v in enumerate(track):
            out[start + i] += v
    return out


def chord(freqs, seconds, shape="sine", **kwargs):
    return mix(*[tone(f, seconds, shape, **kwargs) for f in freqs])


def note(name):
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    octave = int(name[-1])
    semis = names[name[0]] + (1 if "#" in name else 0) + (octave - 4) * 12
    return 440.0 * 2 ** (semis / 12)


def write(name, samples, gain=0.8):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = gain / peak
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        frames = b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples)
        f.writeframes(frames)
    return path


def main():
    sounds = {}
    sounds["UIClick"] = mix(tone(2400, 0.03, decay=0.008), noise(0.02, 0.3, decay=0.004, seed=2))
    sounds["Error"] = mix(tone(220, 0.12, "square", decay=0.08, volume=0.5), tone(165, 0.16, "square", decay=0.1, volume=0.5), offsets=[0, 0.1])
    sounds["Place"] = mix(tone(160, 0.18, decay=0.05), noise(0.05, 0.4, decay=0.01, lowpass=0.8, seed=3), tone(1200, 0.05, decay=0.015, volume=0.4))
    sounds["BoxOpen"] = mix(noise(0.35, 0.8, lowpass=0.9, seed=4, rise=True), tone(140, 0.25, decay=0.06), offsets=[0, 0.3])
    sounds["RevealCommon"] = mix(tone(note("A5"), 0.5, decay=0.15), tone(note("A6"), 0.4, decay=0.08, volume=0.3))
    sounds["RevealRare"] = mix(*[tone(note(n), 0.5, "triangle", decay=0.18) for n in ("C6", "E6", "G6")], offsets=[0, 0.08, 0.16])
    sounds["RevealLegendary"] = mix(
        chord([note("C5"), note("E5"), note("G5"), note("C6")], 1.3, decay=0.6, vibrato=0.004),
        *[tone(note(n), 0.3, decay=0.1, volume=0.5) for n in ("G6", "C7", "E7", "G7")],
        offsets=[0, 0.05, 0.12, 0.19, 0.26],
    )
    sounds["RevealDivine"] = mix(
        chord([note("D4"), note("A4"), note("D5"), note("F#5")], 1.8, "saw", attack=0.25, decay=0.9, vibrato=0.006, volume=0.35),
        tone(note("D6"), 1.2, decay=0.5, volume=0.6),
        tone(note("A6"), 1.0, decay=0.4, volume=0.4),
        offsets=[0, 0.2, 0.35],
    )
    sounds["RevealVoid"] = mix(
        tone(110, 1.6, decay=0.8, freq_end=40),
        noise(0.9, 0.5, lowpass=0.95, seed=5, rise=True),
        chord([note("C3"), note("F#3"), note("C4")], 1.4, "saw", attack=0.3, decay=0.7, volume=0.25),
        tone(note("F#6"), 0.6, "square", decay=0.2, volume=0.15),
        offsets=[0, 0, 0.6, 1.0],
    )
    sounds["Purchase"] = mix(tone(note("B5"), 0.12, decay=0.05), tone(note("E6"), 0.35, decay=0.12), offsets=[0, 0.08])
    sounds["Upgrade"] = mix(tone(400, 0.4, "triangle", freq_end=1200, decay=0.2), tone(note("C6"), 0.25, decay=0.1, volume=0.5), offsets=[0, 0.3])
    sounds["Fusion"] = mix(noise(0.5, 0.5, lowpass=0.9, seed=6, rise=True), *[tone(note(n), 0.4, decay=0.12, volume=0.6) for n in ("E6", "G#6", "B6", "E7")], offsets=[0, 0.45, 0.52, 0.59, 0.66])
    sounds["Unlock"] = mix(*[tone(note(n), 0.6, "triangle", decay=0.25) for n in ("G5", "C6", "E6", "G6")], offsets=[0, 0.12, 0.24, 0.36])
    sounds["Rebirth"] = mix(
        tone(70, 1.5, decay=0.6, freq_end=45),
        noise(0.4, 0.6, lowpass=0.85, decay=0.15, seed=7),
        chord([note("C5"), note("G5"), note("C6"), note("E6")], 1.6, attack=0.6, decay=1.2, vibrato=0.005, volume=0.6),
        offsets=[0, 0, 0.4],
    )
    sounds["QuestComplete"] = mix(*[tone(note(n), 0.3, "triangle", decay=0.12) for n in ("E6", "G6", "C7")], offsets=[0, 0.1, 0.2])
    for name, samples in sounds.items():
        path = write(name, samples)
        print(f"{name:16s} {len(samples) / RATE:5.2f}s  {os.path.relpath(path)}")


if __name__ == "__main__":
    main()
