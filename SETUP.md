# URReefcam – Setup Guide (Windows + VSCode → iPhone)

## What you have
All Swift source files are ready. Because iOS requires macOS to compile, we use
**Codemagic** (free cloud macOS runner) to build, and **Sideloadly** (free Windows
tool) to install the IPA onto your iPhone.

---

## Step 1 – Push to GitHub

1. Create a new **private** repo at github.com
2. In this folder run:
   ```
   git init
   git add .
   git commit -m "initial URReefcam source"
   git remote add origin https://github.com/YOUR_USERNAME/ureefcam.git
   git push -u origin main
   ```

---

## Step 2 – Connect Codemagic

1. Go to [codemagic.io](https://codemagic.io) → Sign in with GitHub
2. Add your `ureefcam` repo
3. Codemagic auto-detects `codemagic.yaml` — no extra config needed
4. Click **Start new build**

The pipeline will:
- Install XcodeGen
- Generate `URReefcam.xcodeproj` from `project.yml`
- Build the app (unsigned)
- Package it as `URReefcam_unsigned.ipa`
- Email you the artifact download link

**Free tier:** 500 macOS build minutes/month — more than enough.

---

## Step 3 – Sideload onto your iPhone (Windows)

1. Download **Sideloadly** from [sideloadly.io](https://sideloadly.io)
2. Connect your iPhone to your PC via USB
3. On iPhone: trust this computer when prompted
4. Drag `URReefcam_unsigned.ipa` into Sideloadly
5. Enter your Apple ID email + password (used locally to re-sign only)
6. Click **Start** — Sideloadly installs the app

### After installing
- iPhone → Settings → General → VPN & Device Management → your Apple ID → **Trust**
- Open URReefcam — grant Camera, Microphone, and Photos permissions

### Re-signing (free Apple ID expires every 7 days)
Repeat Step 3 with the same IPA — Sideloadly re-signs with a fresh cert.

---

## Step 4 – Enable Developer Mode (required for sideloaded apps)

iPhone → Settings → Privacy & Security → Developer Mode → **On** → Restart

---

## VSCode extensions to install

| Extension | Purpose |
|-----------|---------|
| `sswg.swift-lang` | Swift syntax highlight + autocomplete |
| `ms-vscode.cpptools` | (Optional) better symbol navigation |

---

## Testing checklist

- [ ] White balance sliders update preview color in real-time
- [ ] RGB gain clamping: drag temp to extremes — no crash
- [ ] Lens buttons (0.5× / 1× / 4×) switch without freezing
- [ ] Photo mode: tap shutter → thumbnail appears
- [ ] Video mode: tap record → red timer appears → tap stop → saved to Photos
- [ ] Time-lapse: start → frames count up → stop → video assembled in Photos
- [ ] Scheduled capture: add a schedule 1 min from now → notification fires
