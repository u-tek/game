#!/usr/bin/env python3
"""Renders the ambient menu loop "Twilight Hymn" for Halo & Horn.

    python3 assets/art/ui/src/make_music.py   (needs numpy; ffmpeg for the .ogg)

8 bars x 4 s in A minor: string pad, soft bass, celesta arpeggio, a sparse flute melody
in the second half, and a long hall reverb. The reverb is a circular FFT convolution and
every note tail wraps to the start, so the loop is seamless. Output:
assets/art/ui/music_twilight.ogg (UI.gd plays it looped).
"""
import os
import subprocess
import wave

import numpy as np

SR = 32000
BAR = 4.0
BARS = 8
L = int(SR * BAR * BARS)
rng = np.random.default_rng(1207)


def hz(note):
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "Eb": -6, "E": -5, "F": -4, "F#": -3, "G": -2,
             "G#": -1, "A": 0, "A#": 1, "Bb": 1, "B": 2}
    n, octave = note[:-1], int(note[-1])
    return 440.0 * 2 ** ((names[n] + (octave - 4) * 12) / 12.0)


out = np.zeros(L)


def add(start_s, sig):
    """Mix `sig` at time start_s, wrapping past the loop end to the start."""
    i0 = int(start_s * SR) % L
    n = len(sig)
    end = i0 + n
    if end <= L:
        out[i0:end] += sig
    else:
        first = L - i0
        out[i0:] += sig[:first]
        rest = sig[first:]
        while len(rest) > 0:
            k = min(len(rest), L)
            out[:k] += rest[:k]
            rest = rest[k:]


def env(n, attack, release, total):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    r = np.clip((total - t) / max(release, 1e-4), 0, 1)
    return a * r


def pad_note(f, dur, amp):
    rel = 1.6
    n = int((dur + rel) * SR)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    vib = 1 + 0.0015 * np.sin(2 * np.pi * 4.3 * t + rng.uniform(0, 6))
    for det in (-0.004, 0.0, 0.0037):
        ph = 2 * np.pi * f * (1 + det) * np.cumsum(vib) / SR
        for h in range(1, 7):
            sig += np.sin(h * ph + rng.uniform(0, 6)) / (h ** 1.7)
    breath = 0.85 + 0.15 * np.sin(2 * np.pi * 0.23 * t + rng.uniform(0, 6))
    return sig * env(n, 1.3, rel + 0.4, dur + rel) * breath * amp / 3.0


def bass_note(f, dur, amp):
    n = int((dur + 0.6) * SR)
    t = np.arange(n) / SR
    sig = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(4 * np.pi * f * t) + 0.08 * np.sin(6 * np.pi * f * t)
    shape = np.exp(-t * 0.35)
    return sig * shape * env(n, 0.15, 0.8, dur + 0.6) * amp


def bell(f, amp, length=2.2):
    n = int(length * SR)
    t = np.arange(n) / SR
    sig = (np.sin(2 * np.pi * f * t) * np.exp(-t * 2.4)
           + 0.35 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t * 4.0)
           + 0.12 * np.sin(2 * np.pi * f * 3.0 * t) * np.exp(-t * 6.0)
           + 0.05 * np.sin(2 * np.pi * f * 4.2 * t) * np.exp(-t * 9.0))
    att = np.clip(t / 0.004, 0, 1)
    return sig * att * amp


def flute(f, dur, amp):
    rel = 0.35
    n = int((dur + rel) * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t / 0.5, 0, 1)
    ph = 2 * np.pi * f * np.cumsum(vib) / SR
    sig = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    noise = rng.normal(0, 1, n)
    noise = np.convolve(noise, np.ones(12) / 12, mode="same") * 0.05
    return (sig + noise) * env(n, 0.12, rel + 0.15, dur + rel) * amp


CHORDS = [
    ("A2", ["A3", "C4", "E4", "B4"]),
    ("F2", ["F3", "A3", "C4", "E4"]),
    ("C3", ["G3", "C4", "E4", "G4"]),
    ("G2", ["G3", "B3", "D4", "G4"]),
    ("A2", ["A3", "C4", "E4", "A4"]),
    ("F2", ["F3", "A3", "C4", "E4"]),
    ("D3", ["F3", "A3", "D4", "F4"]),
    ("E2", ["E3", "G#3", "B3", "E4"]),
]

for b, (root, voices) in enumerate(CHORDS):
    t0 = b * BAR
    for v in voices:
        add(t0, pad_note(hz(v), BAR, 0.11))
    add(t0, bass_note(hz(root), BAR, 0.32))
    # Celesta arpeggio: 8th notes over chord tones, up an octave or two.
    tones = [hz(v) * 2 for v in voices]
    pattern = [0, 1, 2, 3, 2, 1, 3, 2]
    for k, p in enumerate(pattern):
        if rng.random() < 0.22 and k not in (0, 4):
            continue
        f = tones[p] * (2 if (k == 6 and rng.random() < 0.5) else 1)
        add(t0 + k * 0.5 + rng.uniform(0, 0.012), bell(f, 0.075 if k % 2 == 0 else 0.055))

# Sparse flute melody in bars 5-8 (beats are 1 s).
MELODY = [
    (16.0, "E5", 1.5), (17.5, "D5", 0.5), (18.0, "C5", 1.0), (19.0, "E5", 1.0),
    (20.0, "C5", 2.5), (22.5, "A4", 1.5),
    (24.0, "D5", 1.0), (25.0, "F5", 1.0), (26.0, "E5", 1.0), (27.0, "D5", 1.0),
    (28.0, "B4", 2.0), (30.0, "G#4", 1.0), (31.0, "B4", 0.9),
]
for start, note, dur in MELODY:
    add(start, flute(hz(note), dur, 0.16))

# Hall reverb: decaying stereo-ish noise impulse, circular convolution (seamless loop).
ir_len = int(3.2 * SR)
t = np.arange(ir_len) / SR
ir = rng.normal(0, 1, ir_len) * np.exp(-t * 2.2)
ir = np.convolve(ir, np.ones(6) / 6, mode="same")  # darken
ir[0] = 0.0
ir /= np.sqrt(np.sum(ir ** 2))
irp = np.zeros(L)
irp[:ir_len] = ir
wet = np.real(np.fft.ifft(np.fft.fft(out) * np.fft.fft(irp)))
mix = out * 0.72 + wet * 0.55

mix /= np.max(np.abs(mix)) + 1e-9
mix *= 0.8

here = os.path.dirname(os.path.abspath(__file__))
dst_dir = os.path.dirname(here)
wav_path = os.path.join(here, "music_twilight.wav")
with wave.open(wav_path, "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((mix * 32767).astype("<i2").tobytes())
ogg_path = os.path.join(dst_dir, "music_twilight.ogg")
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "4", ogg_path], check=True)
os.remove(wav_path)
print("wrote", ogg_path, os.path.getsize(ogg_path), "bytes,", L / SR, "s")
