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
- the positive carries `adult` and the gendered `mature female` / `mature male` tag, each at an
  effective ComfyUI weight of at least content_rules.min_adult_cue_weight;
- the positive carries none of the forbidden terms (whole-word match, weights ignored);
- the negative carries every required explicit-nudity and childlike-appearance term at full weight.

Prompts are tag lists for tag-trained SDXL anime models: no prose by default (a family may opt in
with "use_natural": true), at most 2 CLIP chunks of 75 tokens (stats["positive"]["chunks"]).
Weights follow ComfyUI's own parser (comfy/sd1_clip.py): "(tag:0.8)" sets 0.8, a bare "(tag)" is
emphasis 1.1, literal parentheses must be escaped as "\\(" "\\)". lint() rejects bare groups.
"""
import json
import os
import re

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


def _wrap_quality(fam, body_tags):
    q = join_tags(fam.get("quality", ""), fam.get("rating", ""))
    if fam.get("quality_position", "start") == "start":
        return join_tags(q, body_tags)
    return join_tags(body_tags, q)


def _negative(bible, fam, h, framing=True, extra="", positive=""):
    n = bible["negative"]
    # hero/variant extras first: join_tags keeps the first occurrence, so "(loli:1.3)" beats "loli"
    parts = [fam.get("quality_negative", ""), fam.get("rating_negative", ""), h.get("negative_extra", ""), extra,
             n["quality"], n["anatomy"]]
    if framing:
        parts.append(n["framing"])
    parts += [n["effects"], n["explicit"], n["childlike"], n["text"], n["style"],
              bible["gender"][h["gender"]]["negative"]]
    if "halo" in tag_weights(positive):
        parts.append(n.get("halo", ""))
    return join_tags(*parts)


def _finish(bible, hero_id, positive, negative):
    lint(positive, negative)
    enforce(bible, hero_id, positive, negative)
    return {"positive": positive, "negative": negative,
            "stats": {"positive": clip_stats(positive), "negative": clip_stats(negative)}}


# ------------------------------------------------------------------ composers
def full_body(bible, hero_id, family, background_key=None, extra_tags=""):
    """Positive/negative for a full-body candidate. Order: quality/rating (family position),
    subject, adult face styling, composition (full body early: the rig needs head to feet), body, hair, eyes,
    expression, head, wings/tail, outfit, footwear, accessories, weapon, pose, palette,
    background, style. The brief sentence is appended only for families with use_natural."""
    h = _hero(bible, hero_id)
    fam = family_block(bible, family)
    _, bg = background(bible, hero_id, background_key)
    eyes = "" if h.get("default_eyes") == "closed" else h["eyes"]
    body = join_tags(h["subject"], h.get("adult_face", ""), bible["composition"]["tags"], h["body"], h["hair"],
                     eyes, h["expression"],
                     h["head"], h["wings_tail"], h["outfit"], h.get("footwear", ""), h["accessories"], h["weapon"],
                     h.get("pose", ""), palette(bible, hero_id), bg["tags"], style_tags(bible, bg), extra_tags)
    positive = _wrap_quality(fam, body)
    if fam.get("use_natural"):
        positive += ". " + h["natural"]
    negative = _negative(bible, fam, h, framing=True, positive=positive)
    return _finish(bible, hero_id, positive, negative)


def face(bible, hero_id, family, variant=None, background_key=None):
    """Prompt for a face crop: polish (variant None) or an expression variant (eyes_closed, ...).
    Only face identity tags + the expression: no prose, costume or pose (the crop shows a face,
    and the base expression must not leak into a variant)."""
    h = _hero(bible, hero_id)
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
    body = join_tags(h["subject"], h.get("adult_face", ""), bible["crop_tags"], h["face"], expr,
                     style_tags(bible, bg), bg["tags"])
    positive = _wrap_quality(fam, body)
    negative = _negative(bible, fam, h, framing=False, extra=vneg, positive=positive)
    if variant:
        problems = variant_conflicts(bible, hero_id, variant, positive)
        if problems:
            raise PromptError("%s %s variant contradicts itself: %s" % (hero_id, variant, "; ".join(problems)))
    return _finish(bible, hero_id, positive, negative)


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


def custom(bible, hero_id, family, tags, extra_negative="", background_key=None):
    """Prompt for fixing a region (hands, a prop): hero identity tags + the given tags (no prose)."""
    h = _hero(bible, hero_id)
    fam = family_block(bible, family)
    _, bg = background(bible, hero_id, background_key)
    body = join_tags(h["subject"], tags, h["hair"], h["outfit"], h.get("footwear", ""), h["accessories"],
                     h["weapon"], style_tags(bible, bg), bg["tags"])
    positive = _wrap_quality(fam, body)
    negative = _negative(bible, fam, h, framing=False, extra=extra_negative, positive=positive)
    return _finish(bible, hero_id, positive, negative)


def lint(positive, negative):
    """Raise PromptError on malformed weight syntax."""
    probs = ["positive: " + p for p in syntax_problems(positive)] + ["negative: " + p for p in syntax_problems(negative)]
    if probs:
        raise PromptError("prompt syntax:\n  " + "\n  ".join(probs))


# ------------------------------------------------------------------ content rules
def _has_term(text, term):
    """Whole-word, case-insensitive match of a term in prompt text (weights/brackets/escapes ignored)."""
    t = re.sub(r"\\[()]|[\(\)\[\]]|:\s*[0-9.]+", " ", (text or "").lower())
    t = re.sub(r"\s+", " ", t)
    return re.search(r"(?<![a-z0-9_])" + re.escape(term.lower()) + r"(?![a-z0-9_])", t) is not None


def check_text(bible, positive, negative, gender=None):
    """Content-rule violations for a prompt pair ([] = ok). gender 'female'/'male' adds the gendered
    rules; None (unknown, e.g. a saved graph) requires a mature cue of either gender and applies the
    stricter female term list unless the prompt is clearly male."""
    rules = bible["content_rules"]
    problems = []
    tw = tag_weights(positive)
    minw = float(rules.get("min_adult_cue_weight", 0.6))
    if gender is None:
        gender = "male" if ({"1boy", "male focus"} & set(tw)) and "1girl" not in tw else "female?"
    need = [rules["adult_cue_required"]]
    by_g = rules["adult_cue_by_gender"]
    if gender in by_g:
        need.append(by_g[gender])
    elif not any(c in tw for c in by_g.values()):
        need.append(" or ".join(sorted(by_g.values())))
    for cue in need:
        if cue not in tw:
            problems.append("positive prompt lacks the adult cue tag %r" % cue)
    for cue in rules["adult_cues"]:
        if cue in tw and tw[cue] < minw:
            problems.append("adult cue %r is weighted %.2f (minimum %.2f)" % (cue, tw[cue], minw))
    forbidden = list(rules["forbidden_positive"])
    if gender != "male":
        forbidden += rules.get("forbidden_positive_female", [])
    for term in forbidden:
        if _has_term(positive, term):
            problems.append("forbidden term in positive prompt: %r" % term)
    nw = tag_weights(negative)
    min_neg = float(rules.get("min_negative_weight", 0.9))
    required = [(g, t) for g, terms in rules["required_negative"].items() for t in terms]
    by_gender = rules.get("required_negative_by_gender", {})
    for g in ([gender] if gender in by_gender else ["female"] if gender != "male" else []):
        required += [(grp, t) for grp, terms in by_gender[g].items() for t in terms]
    for group, term in required:
        if term not in nw:
            problems.append("negative prompt is missing required %s term %r" % (group, term))
        elif nw[term] < min_neg:
            problems.append("required %s term %r is weighted %.2f in the negative (minimum %.2f)"
                            % (group, term, nw[term], min_neg))
    return problems


def check(bible, hero_id, positive, negative):
    """Content-rule violations for a hero's prompt pair ([] = ok)."""
    h = _hero(bible, hero_id)
    return check_text(bible, positive, negative, gender=h.get("gender"))


def enforce(bible, hero_id, positive, negative):
    problems = check(bible, hero_id, positive, negative)
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


def check_graph(bible, graph):
    """Content-rule violations in an API graph ([] = ok; graphs without text encoders pass)."""
    pos, neg = graph_prompts(graph)
    if not pos and not neg:
        return []
    problems = []
    if pos and not neg:
        problems.append("graph has a positive prompt but no negative prompt")
    negative = " , ".join(neg)
    for i, p in enumerate(pos):
        for pr in check_text(bible, p, negative if neg else ""):
            if pr not in problems:
                problems.append(pr)
    if not pos:
        for pr in check_text(bible, "1girl, adult, mature female", negative):
            if pr not in problems and "negative" in pr:
                problems.append(pr)
    return problems
