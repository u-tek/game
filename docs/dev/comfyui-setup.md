# Connecting your ComfyUI (tonight's checklist)

Claude's cloud machine needs to reach your ComfyUI over HTTPS. Takes about 10 minutes.

## 1. ComfyUI on your PC

- An **anime SDXL checkpoint** in `models/checkpoints/`. Illustrious-XL or NoobAI-XL based
  models give the best gacha splash-art look. Claude detects what you have automatically.
- Optional but helpful: an anime upscaler in `models/upscale_models/` (e.g. 4x-AnimeSharp), and a
  background-removal custom node (BiRefNet or rembg). If you have IPAdapter installed, Claude
  uses it to keep each character consistent across variants.
- Start ComfyUI normally (default port 8188).

## 2. Expose it with a password-protected tunnel

ComfyUI has no login of its own, so **don't expose it without auth**. With ngrok:

```bash
ngrok http 8188 --basic-auth "halo:<a long random password>"
```

Note the https address it prints (e.g. `https://your-name.ngrok-free.app`). A free ngrok
account includes one fixed domain, so the address stays the same between sessions.

## 3. Tell this environment about it

In the cloud environment menu in the session's title bar → **Edit**:

1. **Network access**: add your tunnel host (e.g. `your-name.ngrok-free.app`) under
   **Allowed domains**, keeping **Allow package managers** ticked.
2. **Network secrets / environment variables**:
   - `COMFYUI_URL` = `https://your-name.ngrok-free.app`
   - `COMFYUI_AUTH` = `Basic ` followed by the base64 of `halo:<password>`
     (in a terminal: `printf 'halo:<password>' | base64`)
3. Start a **new session** on this repo (settings apply to new sessions) and say
   "ComfyUI is connected, run the art pipeline". Everything else is in the repo.

Never paste the password or token into the chat.

## What happens next

Claude runs `docs/dev/art-generation.md` → "Tonight's runbook": several candidates per hero,
picks the best (you get contact sheets to veto), fixes hands and faces by inpainting, makes
eyes-closed and mouth-open variants, cuts out the background, builds the warp rig, and puts the
art in the game. Then it triggers the iOS build.
