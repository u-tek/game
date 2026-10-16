"""Prompt style overlay for the art farm (torch-free).

The prompt bible (data/art_prompts.json) is never edited here. A style (config.STYLES) is applied to
a deep copy of it in memory, and the farm composes its prompts from that copy with the same
composers as ComfyUI (tools/comfy/prompts.py full_body / face). Every text this module returns must
still pass gen.checked() (prompts.lint + prompts.enforce against the REAL bible) before it is encoded.

"farm" (default):
- a dark slate background ("dark grey background", rgb 70,72,80) for heroes whose bible background is
  grey and whose palette has white (light figures melt into a light grey otherwise);
- "game cg, shiny hair" in the style slot (full body and face prompts), plus
  "(dramatic lighting:0.8), (from side:0.5), (detailed face:1.1)" on the full body ("from side" at
  0.5 with "looking at viewer" is the 3/4-view cue);
- weapon/accessory tags that start with "floating " weighted 1.2, and "holding staff, holding weapon"
  in the negative for a floating weapon that nothing holds;
- floor/shadow and flat-look negatives (only active because CFG is always > 1).
"bible": the bible as written.
"""
import copy

import config as C
import prompts


def spec(name):
    if name not in C.STYLES:
        raise KeyError("unknown style %r (known: %s)" % (name, ", ".join(sorted(C.STYLES))))
    return C.STYLES[name]


def record(name):
    """What goes into the metadata."""
    return {"name": name, "spec": spec(name)}


def _drop(tags, drop):
    gone = {prompts.norm_tag(t) for t in drop}
    return ", ".join(t for t in prompts.split_tags(tags) if prompts.norm_tag(t) not in gone)


def _weight_floating(tags, w):
    out = []
    for t in prompts.split_tags(tags):
        n = prompts.norm_tag(t)
        if n.startswith("floating ") and "(" not in t:
            out.append("(%s:%s)" % (n, ("%.2f" % w).rstrip("0").rstrip(".")))
        else:
            out.append(t)
    return ", ".join(out)


def background_for(bible, hero, name):
    """(key, bg dict) the style uses for this hero (the bible's own unless the overlay swaps it)."""
    st = spec(name)
    key, bg = prompts.background(bible, hero)
    ov = st.get("background")
    if ov and key == ov["when_background"] and ov["when_palette_has"] in prompts.split_tags(
            prompts.palette(bible, hero).replace(" and ", ", ").replace(" theme", "")):
        return ov["key"], {"tags": ov["tags"], "rgb": list(ov["rgb"]), "style_tags": ov.get("style_tags", "")}
    return key, bg


def styled_bible(bible, hero, name):
    """(deep copy of the bible with the style applied for `hero`, background key, floating-weapon flag)."""
    st = spec(name)
    b = copy.deepcopy(bible)
    key, bg = background_for(bible, hero, name)
    if name == "bible" or not st.get("drop_tags") and not st.get("style_extra"):
        return b, key, False
    b["backgrounds"][key] = copy.deepcopy(bg)
    sty = b["style"]
    sty["tags"] = _drop(sty.get("tags", ""), st.get("drop_tags", []))
    sty["extra_tags"] = prompts.join_tags(_drop(sty.get("extra_tags", ""), st.get("drop_tags", [])),
                                          st.get("style_extra", ""))
    h = b["heroes"][hero]
    floating = False
    if st.get("floating_weight"):
        for field in ("weapon", "accessories"):
            if h.get(field):
                new = _weight_floating(h[field], st["floating_weight"])
                floating |= new != h[field]
                h[field] = new
    held = any("holding" in prompts.norm_tag(t) for f in ("weapon", "accessories", "pose")
               for t in prompts.split_tags(h.get(f, "")))
    return b, key, floating and not held


def full_body(bible, hero, name):
    """{positive, negative, background_key, bg_rgb, style} for a full-body render."""
    st = spec(name)
    b, key, float_neg = styled_bible(bible, hero, name)
    pr = prompts.full_body(b, hero, C.FAMILY, background_key=key, extra_tags=st.get("full_body_extra", ""))
    neg = pr["negative"]
    if name != "bible":
        neg = prompts.join_tags(neg, st.get("negative_extra", ""), st.get("floating_negative", "") if float_neg else "")
    return {"positive": pr["positive"], "negative": neg, "background_key": key,
            "bg_rgb": list(b["backgrounds"][key]["rgb"]), "style": record(name)}


def face(bible, hero, name, variant=None):
    """{positive, negative, ...} for the face polish (variant None) or an expression variant."""
    st = spec(name)
    b, key, _ = styled_bible(bible, hero, name)
    pr = prompts.face(b, hero, C.FAMILY, variant=variant, background_key=key)
    neg = pr["negative"]
    if name != "bible":
        neg = prompts.join_tags(neg, st.get("face_negative_extra", ""))
    if variant:
        probs = prompts.variant_conflicts(b, hero, variant, pr["positive"])
        if probs:
            raise prompts.PromptError("%s %s variant contradicts itself: %s" % (hero, variant, "; ".join(probs)))
    return {"positive": pr["positive"], "negative": neg, "background_key": key,
            "bg_rgb": list(b["backgrounds"][key]["rgb"]), "style": record(name)}
