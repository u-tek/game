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
- floor/shadow and flat-look negatives (only active because CFG is always > 1);
- exposure hardening: weighted explicit negatives (config STYLES farm harden_negative, per gender) at the
  FRONT of every negative (join_tags keeps the first copy of a tag, so the weights win), the rating tag
  "sensitive" if missing, and tag swaps on the hero copy ("huge breasts" -> "large breasts", "center
  opening" / "opening to the navel" -> "plunging neckline, gold|silver filigree panels").
"bible": the bible as written.

cover(): the prompt of the cover repair (gen.publish_screened): hero identity + outfit without the
exposure-prone tags (config REPAIR drop_outfit_terms) + the opaque material of the outfit ("white glossy
fabric, gold filigree panels"), with the hardened negative for every style.
"""
import copy
import re

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


COLOURS = ("white", "black", "red", "blue", "purple", "pink", "green", "orange", "grey", "crimson", "violet",
           "azure", "silver", "gold")
METALS = ("gold", "silver")
SWAP_FIELDS = ("body", "outfit", "footwear", "accessories", "weapon", "pose", "head", "wings_tail", "hair", "face")


def _colours(text):
    """Colour words in tag order ('white leotard, gold trim' -> ['white', 'gold'])."""
    out = []
    for t in prompts.split_tags(text):
        for w in re.findall(r"[a-z]+", prompts.norm_tag(t)):
            if w in COLOURS and w not in out:
                out.append(w)
    return out


def metal_for(bible, hero):
    h = bible["heroes"][hero]
    found = _colours(", ".join([h.get("outfit", ""), h.get("accessories", ""), prompts.palette(bible, hero)]))
    return next((c for c in found if c in METALS), "gold")


def panels_for(bible, hero):
    return "%s filigree panels" % metal_for(bible, hero)


def cover_material(bible, hero):
    """The opaque material of the hero's outfit for a cover repair: '<main colour> glossy fabric, <metal>
    filigree panels' (main colour = first non-metal colour of the outfit, else of the palette)."""
    h = bible["heroes"][hero]
    found = _colours(h.get("outfit", "")) + _colours(prompts.palette(bible, hero))
    main = next((c for c in found if c not in METALS), "white")
    return "%s glossy fabric, %s, clothed" % (main, panels_for(bible, hero))


def _swap(tags, table, panels):
    out = []
    for t in prompts.split_tags(tags):
        rep = table.get(prompts.norm_tag(t))
        out.append(rep.replace("{panels}", panels) if rep is not None else t)
    return ", ".join(out)


def harden_text(st, gender):
    return (st.get("harden_negative") or {}).get(gender, "")


def harden_negative(bible, hero, name, negative):
    """`negative` with the style's weighted explicit terms in front (unchanged for 'bible')."""
    hard = harden_text(spec(name), bible["heroes"][hero]["gender"])
    return prompts.join_tags(hard, negative) if hard else negative


def harden_positive(bible, hero, name, positive):
    """A recorded positive (final mode reuses the candidate's) with the style's tag swaps and rating tag."""
    st = spec(name)
    if not st.get("replace_tags") and not st.get("rating_tag"):
        return positive
    out = _swap(positive, st.get("replace_tags") or {}, panels_for(bible, hero))
    return _with_rating(out, st)


def _with_rating(positive, st):
    r = st.get("rating_tag")
    if r and r not in prompts.tag_weights(positive):
        return prompts.join_tags(positive, r)
    return positive


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
    if st.get("replace_tags"):
        panels = panels_for(bible, hero)
        for field in SWAP_FIELDS:
            if h.get(field):
                h[field] = _swap(h[field], st["replace_tags"], panels)
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
    pos = pr["positive"]
    if name != "bible":
        neg = prompts.join_tags(neg, st.get("negative_extra", ""), st.get("floating_negative", "") if float_neg else "")
        neg = harden_negative(bible, hero, name, neg)
        pos = _with_rating(pos, st)
    return {"positive": pos, "negative": neg, "background_key": key,
            "bg_rgb": list(b["backgrounds"][key]["rgb"]), "style": record(name)}


def face(bible, hero, name, variant=None):
    """{positive, negative, ...} for the face polish (variant None) or an expression variant."""
    st = spec(name)
    b, key, _ = styled_bible(bible, hero, name)
    pr = prompts.face(b, hero, C.FAMILY, variant=variant, background_key=key)
    neg = pr["negative"]
    pos = pr["positive"]
    if name != "bible":
        neg = harden_negative(bible, hero, name, prompts.join_tags(neg, st.get("face_negative_extra", "")))
        pos = _with_rating(pos, st)
    if variant:
        probs = prompts.variant_conflicts(b, hero, variant, pos)
        if probs:
            raise prompts.PromptError("%s %s variant contradicts itself: %s" % (hero, variant, "; ".join(probs)))
    return {"positive": pos, "negative": neg, "background_key": key,
            "bg_rgb": list(b["backgrounds"][key]["rgb"]), "style": record(name)}


def cover(bible, hero, name):
    """{positive, negative, material, ...} for the cover repair of a flagged region. Always hardened (with
    the farm terms when `name` has none): its only job is opaque coverage."""
    b, key, _ = styled_bible(bible, hero, name)
    h = b["heroes"][hero]
    drop = [t.lower() for t in C.REPAIR["drop_outfit_terms"]]
    h["outfit"] = ", ".join(t for t in prompts.split_tags(h.get("outfit", ""))
                            if not any(d in prompts.norm_tag(t) for d in drop))
    material = cover_material(b, hero)
    pr = prompts.custom(b, hero, C.FAMILY, material, background_key=key)
    st = spec(name) if spec(name).get("harden_negative") else spec("farm")
    hard = harden_text(st, bible["heroes"][hero]["gender"])
    neg = prompts.join_tags(hard, pr["negative"])
    pos = _with_rating(pr["positive"], spec("farm"))
    return {"positive": pos, "negative": neg, "material": material, "background_key": key,
            "bg_rgb": list(b["backgrounds"][key]["rgb"]), "style": record(name)}
