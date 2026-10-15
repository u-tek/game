"""Compose prompts from the prompt bible (data/art_prompts.json) and enforce the content rules.

    full_body(bible, hero_id, family)            -> {"positive", "negative"}  (candidates)
    face(bible, hero_id, family, variant=None)   -> {"positive", "negative"}  (face polish / expression inpaint)
    custom(bible, hero_id, family, tags, extra_negative) -> fixes (hands, props) with hero context
    check(bible, hero_id, positive, negative)    -> list of rule violations ([] = ok)
    enforce(...)                                 -> raises ContentRuleError on any violation

Every composed prompt passes through enforce(), so a prompt that breaks the rules never reaches a
server: the negative must carry every required explicit-nudity and childlike-appearance term, the
positive must carry an adult cue and none of the forbidden terms.
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
BIBLE_PATH = os.path.join(ROOT, "data", "art_prompts.json")


class ContentRuleError(ValueError):
    pass


def load_bible(path=None):
    with open(path or BIBLE_PATH) as f:
        return json.load(f)


def norm_tag(t):
    """'(mature female:0.8)' -> 'mature female'; strips weights, brackets, escapes, extra spaces."""
    t = t.strip().lower().replace("\\(", "(").replace("\\)", ")")
    m = re.match(r"^[\(\[]+(.*?)(?::\s*[0-9.]+)?[\)\]]+$", t)
    if m:
        t = m.group(1)
    return re.sub(r"\s+", " ", t).strip()


def split_tags(s):
    return [p.strip() for p in (s or "").split(",") if p.strip()]


def join_tags(*parts):
    """Join tag strings, dropping empties and duplicate tags (first occurrence wins)."""
    seen, out = set(), []
    for part in parts:
        for t in split_tags(part):
            k = norm_tag(t)
            if k in seen:
                continue
            seen.add(k)
            out.append(t)
    return ", ".join(out)


def _hero(bible, hero_id):
    h = bible["heroes"].get(hero_id)
    if h is None:
        raise KeyError("unknown hero %r (known: %s)" % (hero_id, ", ".join(bible["heroes"])))
    return h


def family_block(bible, family):
    f = bible["families"].get(family)
    if f is None:
        raise KeyError("unknown model family %r (known: %s)" % (family, ", ".join(bible["families"])))
    return f


def background(bible, hero_id, override=None):
    h = _hero(bible, hero_id)
    key = override or h.get("background") or bible["factions"][h["faction"]]["background"]
    bg = bible["backgrounds"][key]
    return key, bg


def _wrap_quality(fam, body_tags):
    q = join_tags(fam.get("quality", ""), fam.get("rating", ""))
    if fam.get("quality_position") == "start":
        return join_tags(q, body_tags)
    return join_tags(body_tags, q)


def _negative(bible, fam, h, framing=True, extra=""):
    n = bible["negative"]
    parts = [fam.get("quality_negative", ""), fam.get("rating_negative", ""), n["quality"], n["anatomy"]]
    if framing:
        parts.append(n["framing"])
    parts += [n["explicit"], n["childlike"], n["text"], n["style"],
              bible["gender"][h["gender"]]["negative"], h.get("negative_extra", ""), extra]
    return join_tags(*parts)


def full_body(bible, hero_id, family, background_key=None, extra_tags=""):
    """Positive/negative for a full-body candidate."""
    h = _hero(bible, hero_id)
    fam = family_block(bible, family)
    fac = bible["factions"][h["faction"]]
    _, bg = background(bible, hero_id, background_key)
    body = join_tags(h["subject"], h["body"], h["hair"], h["eyes"], h["expression"], h["head"], h["wings_tail"],
                     h["outfit"], h["accessories"], h["weapon"], bible["composition"]["tags"], h.get("pose", ""),
                     fac["palette"], bg["tags"], bible["style"]["tags"], extra_tags)
    natural = " ".join([h["natural"], "Colours: %s." % fac["palette_natural"], bible["composition"]["natural"],
                        bible["style"]["natural"]])
    positive = _wrap_quality(fam, body) + ". " + natural
    negative = _negative(bible, fam, h, framing=True)
    enforce(bible, hero_id, positive, negative)
    return {"positive": positive, "negative": negative}


def face(bible, hero_id, family, variant=None, background_key=None):
    """Prompt for a face crop: polish (variant None) or an expression variant (eyes_closed, ...)."""
    h = _hero(bible, hero_id)
    fam = family_block(bible, family)
    _, bg = background(bible, hero_id, background_key)
    if variant:
        if variant not in h["variants"]:
            raise KeyError("hero %s has no %s variant prompt" % (hero_id, variant))
        expr = h["variants"][variant]
        vneg = bible["variants"][variant].get("negative", "")
    else:
        expr = join_tags(h["eyes"], h["expression"], bible["face_refine"]["tags"])
        vneg = ""
    body = join_tags(h["subject"], bible["crop_tags"], h["face"], expr, bible["style"]["tags"], bg["tags"])
    positive = _wrap_quality(fam, body) + ". " + h["natural"]
    negative = _negative(bible, fam, h, framing=False, extra=vneg)
    enforce(bible, hero_id, positive, negative)
    return {"positive": positive, "negative": negative}


def custom(bible, hero_id, family, tags, extra_negative="", background_key=None):
    """Prompt for fixing a region (hands, a prop): hero identity + the given tags."""
    h = _hero(bible, hero_id)
    fam = family_block(bible, family)
    _, bg = background(bible, hero_id, background_key)
    body = join_tags(h["subject"], tags, h["hair"], h["outfit"], h["accessories"], h["weapon"],
                     bible["style"]["tags"], bg["tags"])
    positive = _wrap_quality(fam, body) + ". " + h["natural"]
    negative = _negative(bible, fam, h, framing=False, extra=extra_negative)
    enforce(bible, hero_id, positive, negative)
    return {"positive": positive, "negative": negative}


def _has_term(text, term):
    """Whole-word, case-insensitive match of a term in prompt text (weights/brackets ignored)."""
    t = re.sub(r"[\(\)\[\]]|:\s*[0-9.]+", " ", text.lower())
    return re.search(r"(?<![a-z0-9_])" + re.escape(term.lower()) + r"(?![a-z0-9_])", t) is not None


def check(bible, hero_id, positive, negative):
    """Content-rule violations for a prompt pair ([] = ok)."""
    rules = bible["content_rules"]
    h = _hero(bible, hero_id)
    problems = []
    pos_tags = {norm_tag(t) for t in split_tags(positive.split(". ")[0])}
    if not any(c in pos_tags for c in rules["adult_cues"]):
        problems.append("positive prompt has no adult cue tag (%s)" % ", ".join(rules["adult_cues"]))
    if not _has_term(positive, "adult"):
        problems.append("positive prompt never says 'adult'")
    forbidden = list(rules["forbidden_positive"])
    if h.get("gender") == "female":
        forbidden += rules.get("forbidden_positive_female", [])
    for term in forbidden:
        if _has_term(positive, term):
            problems.append("forbidden term in positive prompt: %r" % term)
    neg_tags = {norm_tag(t) for t in split_tags(negative)}
    for group, terms in rules["required_negative"].items():
        for term in terms:
            if term not in neg_tags:
                problems.append("negative prompt is missing required %s term %r" % (group, term))
    return problems


def enforce(bible, hero_id, positive, negative):
    problems = check(bible, hero_id, positive, negative)
    if problems:
        raise ContentRuleError("prompt for %s breaks the content rules:\n  %s" % (hero_id, "\n  ".join(problems)))
