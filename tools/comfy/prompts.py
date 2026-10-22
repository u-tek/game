"""Compose prompts from the prompt bible (data/art_prompts.json) and enforce the content rules.

    full_body(bible, hero_id, family)            -> {"positive", "negative", "stats"}  (candidates)
    face(bible, hero_id, family, variant=None)   -> same, for face polish / expression inpaint
    custom(bible, hero_id, family, tags, extra_negative) -> fixes (hands, props) with hero identity
    check(bible, hero_id, positive, negative)    -> list of rule violations ([] = ok)
    check_text(bible, positive, negative, gender)-> same without a hero (used for saved graphs)
    check_graph(bible, graph)                    -> violations in an API graph's text encoders
    enforce(...)                                 -> raises ContentRuleError on any violation

Every composed prompt passes through enforce(), and comfy.Comfy.queue() runs check_graph() on every
graph before it is written or sent, so a prompt that breaks the rules never reaches a server:
- the positive carries `adult` at an effective ComfyUI weight of at least
  content_rules.min_adult_cue_weight (the gendered `mature female` cue was dropped on 2026-10-20:
  it aged the cast; content_rules.adult_cue_by_gender can still require one);
- the positive carries none of the forbidden terms (whole-word match, weights ignored);
- the negative carries every required explicit-nudity and childlike-appearance term at full weight.

The adult mode (--adult, the EroLabs nude set) swaps in the bible's content_rules_adult block:
nudity terms are allowed in the positive and no longer required in the negative, the subject line
becomes 1girl, solo, adult (no gendered mature cue), the family rating becomes `nsfw`, and the
sex-act and childlike terms stay forbidden and required-negative. See docs/dev/skins.md.

Prompts are tag lists for tag-trained SDXL anime models: no prose by default (a family may opt in
with "use_natural": true), at most 2 CLIP chunks of 75 tokens (stats["positive"]["chunks"]).
The MOSS family ("prompt_mode": "sentences", the main generator since 2026-10-20) gets sentences
instead, with no weight syntax: see the "sentence prompts" section.
Weights follow ComfyUI's own parser (comfy/sd1_clip.py): "(tag:0.8)" sets 0.8, a bare "(tag)" is
emphasis 1.1, literal parentheses must be escaped as "\\(" "\\)". lint() rejects bare groups.
"""
import json
import os
import re
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
BIBLE_PATH = os.path.join(ROOT, "data", "art_prompts.json")

CLIP_CHUNK = 75          # tokens per CLIP chunk (77 minus start/end)
MAX_WORD_TOKENS = 8      # ComfyUI splits a single word across chunks only from this length


class ContentRuleError(ValueError):
    pass


class PromptError(ValueError):
    """A prompt that is malformed (bad weight syntax) or contradicts itself (variant vs base state)."""


def load_bible(path=None):
    with open(path or BIBLE_PATH) as f:
        return json.load(f)


# ------------------------------------------------------------------ ComfyUI prompt syntax
def _escape(text):
    return text.replace("\\)", "\0\2").replace("\\(", "\0\1")


def _unescape(text):
    return text.replace("\0\1", "(").replace("\0\2", ")")


def _parse_parentheses(string):
    """Top-level split into plain text and (...) groups (port of comfy.sd1_clip.parse_parentheses)."""
    result, current, depth = [], "", 0
    for ch in string:
        if ch == "(":
            if depth == 0:
                if current:
                    result.append(current)
                current = "("
            else:
                current += ch
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                result.append(current + ")")
                current = ""
            else:
                current += ch
        else:
            current += ch
    if current:
        result.append(current)
    return result


def _token_weights(string, weight):
    out = []
    for x in _parse_parentheses(string):
        w = weight
        if len(x) >= 2 and x[0] == "(" and x[-1] == ")":
            x = x[1:-1]
            i = x.rfind(":")
            w *= 1.1
            if i > 0:
                try:
                    w = float(x[i + 1:])
                    x = x[:i]
                except ValueError:
                    pass
            out += _token_weights(x, w)
        else:
            out.append((x, weight))
    return out


def weighted_segments(text):
    """[(text, weight)] exactly as ComfyUI's CLIPTextEncode splits `text` by weight."""
    return [(_unescape(t), w) for t, w in _token_weights(_escape(text or ""), 1.0)]


def _clean(t):
    return re.sub(r"\s+", " ", t.strip().lower())


def weighted_tags(text):
    """[(tag, weight)]: comma-separated tags (lower case) with their effective ComfyUI weight."""
    out = []
    for seg, w in weighted_segments(text):
        for t in seg.split(","):
            c = _clean(t)
            if c:
                out.append((c, w))
    return out


def tag_weights(text):
    """{tag: highest weight it appears with}."""
    d = {}
    for t, w in weighted_tags(text):
        d[t] = max(d.get(t, w), w)
    return d


def syntax_problems(text):
    """Weight-syntax problems: unbalanced parentheses, or a (...) group without an explicit
    ':weight' (ComfyUI reads it as emphasis 1.1 -- e.g. 'star (symbol)' must be 'star \\(symbol\\)')."""
    s = _escape(text or "")
    probs, stack = [], []
    for i, ch in enumerate(s):
        if ch == "(":
            stack.append(i)
        elif ch == ")":
            if not stack:
                probs.append("unbalanced ')' at %d" % i)
                continue
            j = stack.pop()
            inner = s[j + 1:i]
            if not re.search(r":\s*-?[0-9]*\.?[0-9]+\s*$", inner):
                probs.append("bare parentheses %r: ComfyUI reads them as emphasis 1.1; write (tag:1.1) "
                             "for emphasis or escape literal ones as \\( \\)" % _unescape(s[j:i + 1])[:60])
    if stack:
        probs.append("unbalanced '(' at %d" % stack[0])
    return probs


# ------------------------------------------------------------------ token estimate
# CLIP's BPE has whole-word tokens for common English words; rarer words split into 2-3 pieces.
# There is no tokenizer vocabulary offline, so this is a calibrated estimate (errs high on long
# words) used to keep prompts inside 2 chunks; the real count can differ by a few tokens.
_COMMON_LONG = set("""masterpiece background aesthetic shoulders shoulder feathered confident seductive
embroidery asymmetrical melancholy gauntlets lighting standing accessories character official multiple
detailed beautiful expression portrait sleeveless ornament floating jewelry necklace bracelet platinum
cleavage neckline backless barefoot blonde breasts athletic muscular pectorals chocolate thighhigh
lipstick eyelashes eyeliner signature watermark artifacts deformed extra missing fingers anatomy
underage children displeasing questionable explicit""".split())


def _word_tokens(word):
    n = 0
    for piece in re.findall(r"[a-z]+|[0-9]|[^\sa-z0-9]+", word.lower()):
        if piece.isalpha():
            if len(piece) <= 7 or piece in _COMMON_LONG:
                n += 1
            else:
                n += 2 if len(piece) <= 12 else 3
        elif piece.isdigit():
            n += 1
        else:
            n += len(piece)
    return n


def clip_stats(text):
    """{"tokens", "chunks"}: estimated CLIP tokens and how many 75-token chunks ComfyUI would use
    (words are never split across chunks unless longer than 8 tokens, as in comfy/sd1_clip.py)."""
    groups = []
    for seg, _w in weighted_segments(text):
        for word in seg.replace("\n", " ").split(" "):
            if word:
                groups.append(_word_tokens(word))
    total, chunks, used = sum(groups), 1, 0
    for g in groups:
        while g > 0:
            if used + g > CLIP_CHUNK:
                if g >= MAX_WORD_TOKENS:
                    g -= CLIP_CHUNK - used
                chunks += 1
                used = 0
            else:
                used += g
                g = 0
    return {"tokens": total, "chunks": chunks}


CHUNK_PACK = 66          # estimated tokens per encoder chunk: the estimate can run a few tokens low


def _top_level_tags(text):
    """`text` split at commas outside (...) groups, each piece stripped; escaped \\( \\) are literal."""
    out, depth, start, i = [], 0, 0, 0
    while i < len(text):
        ch = text[i]
        if ch == "\\":
            i += 2
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        elif ch == "," and depth == 0:
            out.append(text[start:i].strip())
            start = i + 1
        i += 1
    out.append(text[start:].strip())
    return [t for t in out if t]


def split_chunks(text, limit=CHUNK_PACK):
    """`text` packed into pieces of whole tags that each fit one 75-token CLIP chunk, for one
    CLIPTextEncode per piece joined by ConditioningConcat. ComfyUI's own chunking cuts a long prompt
    at exactly 75 tokens, which splits a tag such as 'covered | nipples' into two unrelated words;
    packing by tag keeps every tag whole. ", ".join(pieces) gives back the prompt."""
    pieces, cur, used = [], [], 0
    for tag in _top_level_tags(text or ""):
        cost = sum(_word_tokens(w) for seg, _w in weighted_segments(tag) for w in seg.split()) + 1
        if cur and used + cost > limit:
            pieces.append(", ".join(cur))
            cur, used = [], 0
        cur.append(tag)
        used += cost
    if cur:
        pieces.append(", ".join(cur))
    return pieces or [text or ""]


# ------------------------------------------------------------------ tag helpers
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


SKIN_FIELDS = ("outfit", "footwear", "accessories", "weapon", "pose", "expression", "head", "palette",
               "background", "natural")


RIG_FIELDS = ("natural", "eyes", "default_eyes", "expression", "pose")
POSES = ("rig",)


def hero_view(bible, hero_id, adult=False, pose=None):
    """The hero's prompt fields; adult=True applies her "adult" block (the nude base look) and
    requires it to exist. pose="rig" applies her "rig" block: the rig-ready pose for the layered rig
    (front view, limbs and props clear of the body, eyes open for the blink frames)."""
    h = _hero(bible, hero_id)
    if pose:
        if pose not in POSES:
            raise KeyError("unknown pose %r (known: %s)" % (pose, ", ".join(POSES)))
        rv = h.get("rig")
        if not isinstance(rv, dict) or not rv.get("natural"):
            raise KeyError("hero %r has no 'rig' block in the bible (a rig-ready natural, eyes, pose)" % hero_id)
        h = dict(h)
        for k in RIG_FIELDS:
            if k in rv:
                h[k] = rv[k]
    if not adult:
        return h
    av = h.get("adult")
    if not isinstance(av, dict) or not av.get("outfit"):
        raise KeyError("hero %r has no 'adult' prompt block in the bible (add outfit + natural)" % hero_id)
    v = dict(h)
    for k in SKIN_FIELDS:
        if k in av:
            v[k] = av[k]
    return v


def skin_view(bible, hero_id, skin_id, adult=False):
    """The hero's prompt fields with a skin's overrides (bible "skins", keyed by the skin id of
    data/skins.json). Identity (subject, body, hair, eyes, wings) always comes from the hero, so a
    skin keeps her face and figure; its negative_extra is added to the hero's. adult=True also
    applies the skin's "adult" block (the EroLabs nude outfit) and requires it to exist."""
    h = _hero(bible, hero_id)
    s = (bible.get("skins") or {}).get(skin_id)
    if s is None:
        raise KeyError("unknown skin %r (bible 'skins')" % skin_id)
    if s.get("hero") != hero_id:
        raise KeyError("skin %r belongs to %r, not %r" % (skin_id, s.get("hero"), hero_id))
    v = dict(h)
    for k in SKIN_FIELDS:
        if k in s:
            v[k] = s[k]
    if adult:
        av = s.get("adult")
        if not isinstance(av, dict) or not av.get("outfit"):
            raise KeyError("skin %r has no 'adult' prompt block in the bible (add outfit + natural)" % skin_id)
        for k in SKIN_FIELDS:
            if k in av:
                v[k] = av[k]
    if s.get("negative_extra"):
        v["negative_extra"] = join_tags(s["negative_extra"], h.get("negative_extra", ""))
    if s.get("cover") and not adult:
        v["cover"] = s["cover"]     # implied topless: hands / arm / hair cover her (sentence families)
    return v


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


def palette(bible, hero_id):
    h = _hero(bible, hero_id)
    return h.get("palette") or bible["factions"][h["faction"]]["palette"]


def style_tags(bible, bg):
    st = bible["style"]
    return join_tags(st["tags"], bg.get("style_tags", ""), st.get("extra_tags", ""))


def _wrap_quality(fam, body_tags, rating_override=None):
    q = join_tags(fam.get("quality", ""), rating_override if rating_override is not None else fam.get("rating", ""))
    if fam.get("quality_position", "start") == "start":
        return join_tags(q, body_tags)
    return join_tags(body_tags, q)


def _negative(bible, fam, h, framing=True, extra="", positive="", adult=False):
    n = bible["negative"]
    rules = rules_for(bible, adult)
    neg_extra = h.get("negative_extra", "")
    if adult and neg_extra:
        # the hero's nudity-fighting extras (e.g. "(nipples:1.2)" against slips in tame art) would
        # fight a nude render: drop every tag from the tame nudity vocabulary, keep the rest
        tame = bible["content_rules"]
        drop = set(tame["required_negative"].get("explicit", [])) | set(tame["forbidden_positive"])
        neg_extra = ", ".join(t for t in split_tags(neg_extra) if norm_tag(t) not in drop)
    # hero/variant extras first: join_tags keeps the first occurrence, so "(loli:1.3)" beats "loli"
    parts = [fam.get("quality_negative", ""),
             rules.get("family_rating_negative") if adult else fam.get("rating_negative", ""),
             fam.get("nude_negative", "") if adult else "",
             neg_extra, extra,
             n["quality"], n["anatomy"]]
    if framing:
        parts.append(n["framing"])
    parts += [n["effects"], n["explicit_adult" if adult else "explicit"], n["childlike"], n["text"], n["style"],
              bible["gender"][h["gender"]]["negative_adult" if adult else "negative"]]
    if "halo" in tag_weights(positive):
        parts.append(n.get("halo", ""))
    return join_tags(*parts)


def _finish(bible, hero_id, positive, negative, adult=False):
    lint(positive, negative)
    enforce(bible, hero_id, positive, negative, adult=adult)
    return {"positive": positive, "negative": negative,
            "stats": {"positive": clip_stats(positive), "negative": clip_stats(negative)}}


def _subject(bible, h, adult):
    """The subject line for a mode: the adult rules' subject_override (1girl, solo, adult) for the
    EroLabs set, the hero's own subject line otherwise."""
    return rules_for(bible, adult).get("subject_override") or h["subject"]


# ------------------------------------------------------------------ sentence prompts (the MOSS family)
# MOSS-Image reads prompts with a language model (Qwen3.5), so its family ("prompt_mode": "sentences")
# gets prose: the subject tags the content rules need ("1girl, solo, adult"), the family's style block,
# the hero's own description with her age set to the family's ("in her mid-twenties", owner 2026-10-20),
# and the background as a sentence. No weight syntax anywhere: "(tag:1.2)" would be read as text.
SENTENCES = "sentences"
_AGE_RE = re.compile(r"\b(?:in her (?:(?:early|mid|late)[ -]?)?(?:20s|30s|40s|twenties|thirties|forties)"
                     r"|around (?:30|35|40|thirty|forty))\b", re.I)


def sentence_mode(fam):
    return fam.get("prompt_mode") == SENTENCES


def plain_tags(text):
    """Tags with every weight and bracket removed: '(aged up:1.2), adult' -> 'aged up, adult',
    an escaped literal 'heart (symbol)' -> 'heart symbol'."""
    return join_tags(*[re.sub(r"\s+", " ", re.sub(r"[()\[\]]", " ", t)).strip() for t, _ in weighted_tags(text)])


def _prose(text):
    """A description as clean prose: literal parentheses become commas (lint and ComfyUI's weight parser
    would read them as emphasis), and it ends with a full stop."""
    t = re.sub(r"\s*\(([^()]*)\)", r", \1,", (text or "").strip())
    t = re.sub(r",\s*([,.;:])", r"\1", t)
    t = re.sub(r"\s+", " ", t).strip(" ,")
    return t if not t or t[-1] in ".!?" else t + "."


def _with_age(text, fam):
    return _AGE_RE.sub(fam.get("age_natural", "in her mid-twenties"), text or "")


def _who(fam, h):
    """'She is <Name>, ...': the hero's own description, or for a skin or the adult look (whose 'natural'
    is only the outfit: "Adult. Seraphiel in a pearl micro bikini ...") her identity tags plus that
    outfit sentence and the skin's outfit tags."""
    age = fam.get("age_natural", "in her mid-twenties")
    nat = _prose(_with_age(h["natural"], fam))
    outfit_only = re.match(r"^\s*adult\.\s*", h["natural"] or "", re.I)
    if not outfit_only:
        who = "She is %s, %s" % (h["name"], nat[:1].lower() + nat[1:])
        if h.get("default_eyes") != "closed" and not re.search(r"\beyes?\b", nat, re.I):
            who += " Her eyes: %s." % plain_tags(h["eyes"])     # 32 of 40 descriptions leave eye colour out
        return who
    eyes = "" if h.get("default_eyes") == "closed" else h["eyes"]
    drop = set(fam.get("body_drop_natural") or [])    # MOSS: "toned" drew abs (owner, 2026-10-21: "no abs")
    body = ", ".join(t for t in split_tags(h["body"]) if t not in drop)
    identity = plain_tags(join_tags(body, h["hair"], eyes, h["head"], h["wings_tail"]))
    look = plain_tags(join_tags(h["outfit"], h.get("footwear", ""), h["accessories"], h["weapon"]))
    pose = plain_tags(join_tags(h.get("pose", ""), h["expression"]))
    return " ".join(x for x in (
        "She is %s, a beautiful adult woman %s: %s." % (h["name"], age, identity),
        _prose(re.sub(r"^\s*adult\.\s*", "", nat, flags=re.I)),
        "Outfit details: %s." % look if look else "", "Pose and expression: %s." % pose if pose else "") if x)


def _sentence_negative(bible, fam, h, extra="", adult=False):
    """Plain (unweighted) negative: every required content-rule term, the explicit and childlike blocks,
    the gender block, the hero's extras and the family's style negatives. The SDXL quality, anatomy and
    framing tag lists are left out (MOSS was tested without them)."""
    n = bible["negative"]
    rules = rules_for(bible, adult)
    req = [t for terms in rules["required_negative"].values() for t in terms]
    for g, blocks in (rules.get("required_negative_by_gender") or {}).items():
        if g == h["gender"]:
            req += [t for terms in blocks.values() for t in terms]
    gneg = bible["gender"][h["gender"]]["negative_adult" if adult else "negative"]
    if h.get("cover"):      # implied topless: "topless" in the negative put a micro top back on
        gneg = ", ".join(t for t in split_tags(gneg) if t != "topless")
    parts = [", ".join(req), n["explicit_adult" if adult else "explicit"], n["childlike"], gneg,
             h.get("negative_extra", ""), extra, fam.get("quality_negative", ""),
             rules.get("family_rating_negative") if adult else fam.get("rating_negative", ""),
             fam.get("nude_negative", "") if adult else ""]
    neg = plain_tags(join_tags(*parts))
    if adult:      # no nudity-fighting terms in a nude render (as _negative does for the hero's extras)
        tame = bible["content_rules"]
        drop = set(tame["required_negative"].get("explicit", [])) | set(tame["forbidden_positive"])
        keep = set(req)
        neg = ", ".join(t for t in split_tags(neg) if t not in drop or t in keep)
    return neg


def _sentence_subject(bible, h, adult):
    """The subject tags the content rules read: '1girl, solo, adult' (+ the adult set's 'nsfw' rating)."""
    return plain_tags(join_tags(_subject(bible, h, adult), rules_for(bible, adult).get("family_rating") if adult else ""))


def _face_sentence(fam, closed):
    """The family's face sentence; its closed-eyes form for closed eyes (MOSS follows sentences, and
    'large glossy eyes with detailed gradient irises' kept an eyes_closed variant open, 2026-10-20)."""
    return fam.get("face_natural_closed" if closed else "face_natural", "")


def _nude_pose(fam, h):
    """The nude set's pose for a look: one of nude_poses_natural, the same for every seed of that look."""
    poses = fam.get("nude_poses_natural") or []
    if not poses or not fam.get("pin_up_natural"):
        return ""
    return poses[zlib.crc32((h.get("natural") or h["name"]).encode("utf-8")) % len(poses)]


def _sentence_full_body(bible, fam, h, hero_id, bg, extra_tags, adult, pose=None):
    subj = _sentence_subject(bible, h, adult)
    composition = fam.get("composition_rig_natural" if pose == "rig" else "composition_natural", "")
    style = fam.get("style_natural", "")
    if h.get("cover") and fam.get("outfit_natural") and fam.get("topless_natural"):
        # implied topless (After Dark pack, owner 2026-10-22: "no bra at all. and the hand/s would be covering the
        # nipples"): no micro top; the skin's hands, arm or hair cover her completely
        cover = (fam.get("cover_natural") or {}).get(h["cover"], "")
        style = style.replace(fam["outfit_natural"], fam["topless_natural"].format(cover=cover))
    if adult and fam.get("outfit_natural") and fam.get("nude_natural"):    # the nude set (owner, 2026-10-22)
        style = style.replace(fam["outfit_natural"], fam["nude_natural"])
        # no weapons or held props in the nude set (owner, 2026-10-22: "remove their weapons in all generations")
        h = dict(h, weapon="", outfit=", ".join(t for t in split_tags(h["outfit"])
                                                 if "holding" not in t and "in hand" not in t))
        composition = fam.get("composition_nude_natural") or composition
        nude_pose = _nude_pose(fam, h)
        if nude_pose:   # owner: "way more sexual, rather than just the regular character with no clothes"
            style = style.replace(fam["pin_up_natural"], nude_pose)
            h = dict(h, pose="")
    parts = ["%s, full body." % subj, style,
             _face_sentence(fam, h.get("default_eyes") == "closed"), composition,
             _who(fam, h), _prose(plain_tags(extra_tags)) if extra_tags else "",
             bg.get("natural") or "Plain flat background, no scenery."]
    return " ".join(p.strip() for p in parts if p and p.strip())


def _sentence_close_up(bible, fam, h, tags, bg, adult, what="close-up of her face and shoulders", expression=""):
    """Tags first (so variant_conflicts reads them as clean tags), then the style and who she is. A
    variant's expression is said again as a sentence: MOSS barely moved an eyes_closed or mouth_open
    region from the tags alone (2026-10-20)."""
    age = fam.get("age_natural", "in her mid-twenties")
    head = "%s." % plain_tags(join_tags(_sentence_subject(bible, h, adult), what, tags))
    closed = "closed eyes" in tag_weights(plain_tags(tags))
    parts = [head, fam.get("style_natural", ""), _face_sentence(fam, closed),
             "She is %s, a beautiful adult woman %s." % (h["name"], age),
             "Her expression: %s." % plain_tags(expression) if expression else "",
             bg.get("natural") or "Plain flat background, no scenery."]
    return " ".join(p.strip() for p in parts if p and p.strip())


# ------------------------------------------------------------------ composers
def full_body(bible, hero_id, family, background_key=None, extra_tags="", skin=None, adult=False, pose=None):
    """Positive/negative for a full-body candidate. Order: quality/rating (family position),
    subject, adult face styling, composition (full body early: the rig needs head to feet), body, hair, eyes,
    expression, head, wings/tail, outfit, footwear, accessories, weapon, pose, palette,
    background, style. The brief sentence is appended only for families with use_natural.
    skin: a skin id from the bible's "skins" (skin_view) for that skin's outfit, pose and props.
    adult=True: the EroLabs nude set -- the skin's "adult" outfit block, content_rules_adult, the
    relaxed subject line and the nsfw rating (see docs/dev/skins.md).
    pose="rig": the hero's rig-ready pose (hero_view) for the layered rig; base look only."""
    if skin and pose:
        raise PromptError("pose %r is for the base look, not a skin" % pose)
    h = skin_view(bible, hero_id, skin, adult=adult) if skin else hero_view(bible, hero_id, adult=adult, pose=pose)
    fam = family_block(bible, family)
    if skin and h.get("background") and not background_key:
        background_key = h["background"]
    _, bg = background(bible, hero_id, background_key)
    if sentence_mode(fam):
        positive = _sentence_full_body(bible, fam, h, hero_id, bg, extra_tags, adult, pose=pose)
        return _finish(bible, hero_id, positive, _sentence_negative(bible, fam, h, adult=adult), adult=adult)
    eyes = "" if h.get("default_eyes") == "closed" else h["eyes"]
    body = join_tags(_subject(bible, h, adult), h.get("adult_face", ""), bible["composition"]["tags"], h["body"], h["hair"],
                     eyes, h["expression"],
                     h["head"], h["wings_tail"], h["outfit"], h.get("footwear", ""), h["accessories"], h["weapon"],
                     h.get("pose", ""), h.get("palette") or palette(bible, hero_id), bg["tags"],
                     style_tags(bible, bg), extra_tags)
    positive = _wrap_quality(fam, body, rating_override=rules_for(bible, adult).get("family_rating") if adult else None)
    if fam.get("use_natural"):
        positive += ". " + h["natural"]
    negative = _negative(bible, fam, h, framing=True, positive=positive, adult=adult)
    return _finish(bible, hero_id, positive, negative, adult=adult)


def face(bible, hero_id, family, variant=None, background_key=None, skin=None, adult=False, pose=None):
    """Prompt for a face crop: polish (variant None) or an expression variant (eyes_closed, ...).
    Only face identity tags + the expression: no prose, costume or pose (the crop shows a face,
    and the base expression must not leak into a variant). skin: a skin's expression for the polish
    (identity stays the hero's, skin_view). adult=True: the skin's "adult" block and
    content_rules_adult (the face itself only changes by the subject line). pose="rig": the rig
    block's eyes and expression (hero_view)."""
    h = skin_view(bible, hero_id, skin, adult=adult) if skin else hero_view(bible, hero_id, adult=adult, pose=pose)
    fam = family_block(bible, family)
    _, bg = background(bible, hero_id, background_key)
    if variant:
        spec = variant_spec(bible, hero_id, variant)
        expr, vneg = spec["prompt"], spec["negative"]
    else:
        fr = bible["face_refine"]
        closed = h.get("default_eyes") == "closed"
        expr = join_tags("" if closed else h["eyes"], h["expression"], fr["tags"],
                         "" if closed else fr.get("eyes_open_tags", ""))
        vneg = ""
    if sentence_mode(fam):
        tags = join_tags(h["face"], expr)
        if variant:
            problems = variant_conflicts(bible, hero_id, variant, plain_tags(join_tags(_subject(bible, h, adult), tags)))
            if problems:
                raise PromptError("%s %s variant contradicts itself: %s" % (hero_id, variant, "; ".join(problems)))
        positive = _sentence_close_up(bible, fam, h, tags, bg, adult, expression=expr if variant else "")
        return _finish(bible, hero_id, positive, _sentence_negative(bible, fam, h, extra=vneg, adult=adult),
                       adult=adult)
    body = join_tags(_subject(bible, h, adult), h.get("adult_face", ""), bible["crop_tags"], h["face"], expr,
                     style_tags(bible, bg), bg["tags"])
    positive = _wrap_quality(fam, body, rating_override=rules_for(bible, adult).get("family_rating") if adult else None)
    negative = _negative(bible, fam, h, framing=False, extra=vneg, positive=positive, adult=adult)
    if variant:
        problems = variant_conflicts(bible, hero_id, variant, positive)
        if problems:
            raise PromptError("%s %s variant contradicts itself: %s" % (hero_id, variant, "; ".join(problems)))
    return _finish(bible, hero_id, positive, negative, adult=adult)


def variant_spec(bible, hero_id, variant):
    """{prompt, region, region_frac, denoise, negative, conflicts} for an expression variant."""
    h = _hero(bible, hero_id)
    g = bible["variants"].get(variant)
    if g is None:
        raise KeyError("unknown variant %r (known: %s)" % (variant, ", ".join(k for k in bible["variants"]
                                                                              if not k.startswith("_"))))
    hv = h.get("variants", {}).get(variant)
    if isinstance(hv, dict):
        prompt, region = hv.get("prompt", ""), hv.get("region", g["region"])
    elif hv:
        prompt, region = hv, g["region"]
    elif g.get("tags"):
        prompt, region = g["tags"].replace("{eyes}", h["eyes"]), g["region"]
    else:
        raise KeyError("hero %s has no %s variant prompt" % (hero_id, variant))
    return {"prompt": prompt, "region": region, "region_frac": bible["regions"][region],
            "denoise": float(g.get("denoise", 0.6)), "negative": g.get("negative", ""),
            "conflicts": list(g.get("conflicts", []))}


def _eye_colour_tags(h):
    return [t for t in (norm_tag(x) for x in split_tags(h.get("eyes", "")))
            if re.match(r"^[a-z]+ eyes$", t) and t not in ("closed eyes", "open eyes")]


def variant_conflicts(bible, hero_id, variant, positive):
    """Terms in a variant's positive prompt that contradict the variant (e.g. 'closed eyes' in
    eyes_open, an eye colour with closed eyes, the variant's own negative terms)."""
    h = _hero(bible, hero_id)
    spec = variant_spec(bible, hero_id, variant)
    tags = tag_weights(positive)      # whole tags: 'half-closed eyes' is not 'closed eyes'
    bad = []
    for term in spec["conflicts"] + [norm_tag(t) for t in split_tags(spec["negative"])]:
        if term in tags and term not in bad:
            bad.append(term)
    if "closed eyes" in tags:
        bad += [t for t in _eye_colour_tags(h) if t in tags]
    return ["%r" % t for t in bad]


def custom(bible, hero_id, family, tags, extra_negative="", background_key=None, skin=None, adult=False):
    """Prompt for fixing a region (hands, a prop): hero identity tags + the given tags (no prose).
    skin: that skin's outfit and props (skin_view). adult=True: the skin's "adult" outfit and
    content_rules_adult (fixes on a nude candidate keep the nude look)."""
    h = skin_view(bible, hero_id, skin, adult=adult) if skin else hero_view(bible, hero_id, adult=adult)
    fam = family_block(bible, family)
    _, bg = background(bible, hero_id, background_key)
    if sentence_mode(fam):
        detail = join_tags(tags, h["hair"], h["outfit"], h.get("footwear", ""), h["accessories"], h["weapon"])
        positive = _sentence_close_up(bible, fam, h, detail, bg, adult, what="detail view")
        return _finish(bible, hero_id, positive, _sentence_negative(bible, fam, h, extra=extra_negative, adult=adult),
                       adult=adult)
    body = join_tags(_subject(bible, h, adult), tags, h["hair"], h["outfit"], h.get("footwear", ""), h["accessories"],
                     h["weapon"], style_tags(bible, bg), bg["tags"])
    positive = _wrap_quality(fam, body, rating_override=rules_for(bible, adult).get("family_rating") if adult else None)
    negative = _negative(bible, fam, h, framing=False, extra=extra_negative, positive=positive, adult=adult)
    return _finish(bible, hero_id, positive, negative, adult=adult)


def lint(positive, negative):
    """Raise PromptError on malformed weight syntax."""
    probs = ["positive: " + p for p in syntax_problems(positive)] + ["negative: " + p for p in syntax_problems(negative)]
    if probs:
        raise PromptError("prompt syntax:\n  " + "\n  ".join(probs))


# ------------------------------------------------------------------ content rules
def rules_for(bible, adult=False):
    """The content-rules block of a mode: bible['content_rules'], or bible['content_rules_adult']
    for the EroLabs nude set (--adult). Raises ContentRuleError if the adult block is missing."""
    if not adult:
        return bible["content_rules"]
    rules = bible.get("content_rules_adult")
    if not isinstance(rules, dict):
        raise ContentRuleError("bible has no 'content_rules_adult' block: the adult mode needs it")
    return rules


def _has_term(text, term):
    """Whole-word, case-insensitive match of a term in prompt text (weights/brackets/escapes ignored)."""
    t = re.sub(r"\\[()]|[\(\)\[\]]|:\s*[0-9.]+", " ", (text or "").lower())
    t = re.sub(r"\s+", " ", t)
    return re.search(r"(?<![a-z0-9_])" + re.escape(term.lower()) + r"(?![a-z0-9_])", t) is not None


def check_text(bible, positive, negative, gender=None, adult=False):
    """Content-rule violations for a prompt pair ([] = ok). gender 'female'/'male' adds the gendered
    rules; None (unknown, e.g. a saved graph) requires a mature cue of either gender and applies the
    stricter female term list unless the prompt is clearly male. adult=True checks against
    content_rules_adult (nudity allowed, relaxed adult cues, sex acts and childlike terms still
    refused)."""
    rules = rules_for(bible, adult)
    problems = []
    tw = tag_weights(positive)
    minw = float(rules.get("min_adult_cue_weight", 0.6))
    # Scenery (splash-card background plates): "no humans" and no character tag at all. Only the adult cue is
    # waived; forbidden terms and the required safety negatives still apply.
    people = ("1girl", "2girls", "3girls", "1boy", "multiple girls", "multiple boys", "solo", "girl", "woman",
              "female", "male", "person", "people", "character")
    if "no humans" in tw and not any(p in tw for p in people):
        gender = "scenery"
    if gender is None:
        gender = "male" if ({"1boy", "male focus"} & set(tw)) and "1girl" not in tw else "female?"
    need = [c for c in ([rules.get("adult_cue_required")] if gender != "scenery" else []) if c]
    by_g = rules.get("adult_cue_by_gender") or {}
    if gender == "scenery":
        pass
    elif gender in by_g:
        need.append(by_g[gender])
    elif by_g and not any(c in tw for c in by_g.values()):
        need.append(" or ".join(sorted(by_g.values())))
    for cue in need:
        if cue not in tw:
            problems.append("positive prompt lacks the adult cue tag %r" % cue)
    for cue in rules["adult_cues"]:
        if cue in tw and tw[cue] < minw:
            problems.append("adult cue %r is weighted %.2f (minimum %.2f)" % (cue, tw[cue], minw))
    forbidden = list(rules.get("forbidden_positive", []))
    if gender != "male":
        forbidden += rules.get("forbidden_positive_female", [])
    for term in forbidden:
        if _has_term(positive, term):
            problems.append("forbidden term in positive prompt: %r" % term)
    nw = tag_weights(negative)
    min_neg = float(rules.get("min_negative_weight", 0.9))
    required = [(g, t) for g, terms in rules["required_negative"].items() for t in terms]
    by_gender = rules.get("required_negative_by_gender") or {}
    gs = [gender] if gender in by_gender else (
        ["female"] if gender not in ("male", "scenery") and "female" in by_gender else [])
    for g in gs:
        required += [(grp, t) for grp, terms in by_gender[g].items() for t in terms]
    for group, term in required:
        if term not in nw:
            problems.append("negative prompt is missing required %s term %r" % (group, term))
        elif nw[term] < min_neg:
            problems.append("required %s term %r is weighted %.2f in the negative (minimum %.2f)"
                            % (group, term, nw[term], min_neg))
    return problems


def check(bible, hero_id, positive, negative, adult=False):
    """Content-rule violations for a hero's prompt pair ([] = ok)."""
    h = _hero(bible, hero_id)
    return check_text(bible, positive, negative, gender=h.get("gender"), adult=adult)


def enforce(bible, hero_id, positive, negative, adult=False):
    problems = check(bible, hero_id, positive, negative, adult=adult)
    if problems:
        raise ContentRuleError("prompt for %s breaks the content rules:\n  %s" % (hero_id, "\n  ".join(problems)))


# ------------------------------------------------------------------ API graphs
def _is_encoder(node):
    return "TextEncode" in str(node.get("class_type", ""))


def _encoder_text(node):
    return ", ".join(v for v in node.get("inputs", {}).values() if isinstance(v, str))


def graph_prompts(graph):
    """(positive texts, negative texts) of an API graph: text-encoder nodes traced back from every
    'positive' / 'negative' input (through ControlNet and other conditioning nodes). The encoders
    behind one input (chunks joined by ConditioningConcat) are read as one prompt, in trace order.
    Encoders that feed neither are counted as positive (the strict side)."""
    role_of = {}
    groups = {}          # (input node, output index, role) -> encoder ids in trace order

    def trace(nid, idx, role, seen, key):
        if nid in seen or nid not in graph:
            return
        seen.add(nid)
        node = graph[nid]
        if _is_encoder(node):
            role_of.setdefault(nid, set()).add(role)
            groups.setdefault(key, [])
            if nid not in groups[key]:
                groups[key].append(nid)
            return
        ins = node.get("inputs", {})
        if "positive" in ins and "negative" in ins:      # e.g. ControlNetApplyAdvanced: out 0 pos, 1 neg
            follow = [ins["positive"] if idx == 0 else ins["negative"]]
        else:
            follow = list(ins.values())
        for v in follow:
            if isinstance(v, list) and len(v) == 2 and isinstance(v[1], int):
                trace(str(v[0]), v[1], role, seen, key)

    for node in graph.values():
        for role in ("positive", "negative"):
            v = node.get("inputs", {}).get(role)
            if isinstance(v, list) and len(v) == 2 and isinstance(v[1], int) and not _is_encoder(node):
                trace(str(v[0]), v[1], role, set(), (str(v[0]), v[1], role))
    pos, neg = [], []
    for (_nid, _idx, role), nids in groups.items():
        text = ", ".join(_encoder_text(graph[n]) for n in nids)
        out = pos if role == "positive" else neg
        if text not in out:
            out.append(text)
    for nid, node in graph.items():
        if _is_encoder(node) and nid not in role_of:
            pos.append(_encoder_text(node))
    return pos, neg


def check_graph(bible, graph, adult=False):
    """Content-rule violations in an API graph ([] = ok; graphs without text encoders pass).
    adult=True checks against content_rules_adult (the EroLabs nude set)."""
    pos, neg = graph_prompts(graph)
    if not pos and not neg:
        return []
    problems = []
    if pos and not neg:
        problems.append("graph has a positive prompt but no negative prompt")
    negative = " , ".join(neg)
    for i, p in enumerate(pos):
        for pr in check_text(bible, p, negative if neg else "", adult=adult):
            if pr not in problems:
                problems.append(pr)
    if not pos:
        for pr in check_text(bible, "1girl, adult", negative, adult=adult):
            if pr not in problems and "negative" in pr:
                problems.append(pr)
    return problems
