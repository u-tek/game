"""Step semantics and time estimates for the art farm (torch-free, tested offline).

ComfyUI's `steps` for a partial denoise is the number of steps actually run. diffusers' SDXL
img2img/inpaint pipelines instead run int(num_inference_steps * strength) of the
num_inference_steps schedule, so the bible's "hires: 20 steps at denoise 0.4" would run only 8.
The engine therefore takes EFFECTIVE steps and asks diffusers for total_steps_for(effective, strength).
"""


def total_steps_for(effective, strength):
    """Smallest n with min(int(n * strength), n) >= effective (diffusers' own formula, float rounding
    included), so exactly `effective` steps run at this strength."""
    effective = int(effective)
    strength = float(strength)
    if effective < 1:
        raise ValueError("effective steps must be >= 1, got %r" % (effective,))
    if not 0.0 < strength <= 1.0:
        raise ValueError("strength must be in (0, 1], got %r" % (strength,))
    n = max(effective, int(effective / strength) - 1)
    while min(int(n * strength), n) < effective:
        n += 1
    return n


def steps_run(total, strength):
    """Steps diffusers runs for a schedule of `total` at `strength` (get_timesteps)."""
    return min(int(int(total) * float(strength)), int(total))


def megapixels(w, h):
    return (int(w) * int(h)) / 1e6


def estimate_s(ref_s_per_step_mp, w, h, steps, overhead_s=120.0, exponent=1.2):
    """Seconds for a sampled stage: ref s/step at 1 MP x MP^exponent x steps + overhead."""
    return float(ref_s_per_step_mp) * megapixels(w, h) ** float(exponent) * int(steps) + float(overhead_s)


def ref_from_measure(s_per_step, w, h, exponent=1.2):
    """Back out the 1-MP reference s/step from a measured stage."""
    mp = max(1e-3, megapixels(w, h))
    return float(s_per_step) / mp ** float(exponent)
