"""Torch-free part of the prompt encoder: ComfyUI-compatible word packing into 75-token CLIP chunks
(comfy/sd1_clip.py tokenize_with_weights), used by sdxl.TextEncoders and tested offline."""
import prompts


def pack_chunks(word_tokens, chunk=75, max_word=8):
    """[(token_ids, weight)] per word -> list of chunks [(token, weight)], at most `chunk` long.
    A word is never split across chunks unless it has >= max_word tokens (comfy/sd1_clip.py)."""
    chunks = [[]]
    for ids, w in word_tokens:
        ids = list(ids)
        while ids:
            room = chunk - len(chunks[-1])
            if len(ids) <= room:
                chunks[-1].extend((t, w) for t in ids)
                ids = []
            elif len(ids) >= max_word and room > 0:
                chunks[-1].extend((t, w) for t in ids[:room])
                ids = ids[room:]
                chunks.append([])
            else:
                chunks.append([])
    if len(chunks) > 1 and not chunks[-1]:
        chunks.pop()
    return chunks


def word_tokens(tokenizer, text):
    """Comfy-style split: weighted segments (prompts.weighted_segments), then words on spaces."""
    out = []
    for seg, w in prompts.weighted_segments(text):
        for word in seg.replace("\n", " ").split(" "):
            if word:
                ids = tokenizer(word, add_special_tokens=False)["input_ids"]
                if ids:
                    out.append((ids, float(w)))
    return out
