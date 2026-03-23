# VibeMic macOS QA Guide

## Prerequisites

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 5.9+ (`swift --version`)
- Docker Desktop (for backend) OR local Postgres
- OpenAI API key (for transcription live test)

---

## Part 1: Build the macOS App

```bash
cd vibemic-native-macos
swift build
```

If build succeeds, create .app bundle:

```bash
# Build release
swift build -c release

# Create .app bundle
mkdir -p VibeMic.app/Contents/MacOS
mkdir -p VibeMic.app/Contents/Resources
cp .build/release/VibeMic VibeMic.app/Contents/MacOS/
cp VibeMic/Resources/Info.plist VibeMic.app/Contents/
cp VibeMic/Resources/VibeMic.entitlements VibeMic.app/Contents/Resources/

# Run it
open VibeMic.app
```

### Build QA Checklist

- [ ] `swift build` succeeds with no errors
- [ ] `swift build -c release` succeeds
- [ ] .app bundle launches without crash
- [ ] Menu bar icon appears (waveform icon)
- [ ] Status bar menu shows: Record, History, Settings, Paraphrase, Quit

---

## Part 2: Start the Backend

### Option A: Docker (recommended)

```bash
cd vibemic-api

# Create .env
cp .env.example .env
# Edit .env: set a real OPENAI_API_KEY + JWT_SECRET

docker-compose up -d
alembic upgrade head
```

### Option B: Local Postgres

```bash
cd vibemic-api

# Create DB
createdb vibemic
psql vibemic -c "CREATE USER vibemic WITH PASSWORD 'vibemic'; GRANT ALL ON DATABASE vibemic TO vibemic; GRANT ALL ON SCHEMA public TO vibemic;"

# Create .env
cat > .env << 'EOF'
DATABASE_URL=postgresql+asyncpg://vibemic:vibemic@localhost:5432/vibemic
OPENAI_API_KEY=sk-your-real-key-here
JWT_SECRET=your-random-secret-here
CORS_ORIGINS=*
EOF

# Install deps
pip3 install -r requirements.txt

# Run migration
alembic upgrade head

# Start server
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### Backend QA Checklist

- [ ] `curl http://localhost:8000/health` returns `{"status":"ok"}`
- [ ] Register: `curl -X POST http://localhost:8000/auth/register -H 'Content-Type: application/json' -d '{"email":"test@test.com","password":"testpass123"}'` returns token
- [ ] Login: `curl -X POST http://localhost:8000/auth/login -H 'Content-Type: application/json' -d '{"email":"test@test.com","password":"testpass123"}'` returns token
- [ ] Usage: `curl http://localhost:8000/api/usage -H 'Authorization: Bearer <token>'` returns plan + usage

---

## Part 3: Test Developer Mode (Direct OpenAI)

This tests the existing BYOK (bring your own key) flow.

1. Launch VibeMic.app
2. Open Settings (menu bar → Settings, or Dock → Settings)
3. **In User Settings**, scroll to "About" section, Option-click "Developer Mode" text
4. Developer Settings opens
5. Enter your OpenAI API key
6. Make sure "Use VibeMic Cloud" is **unchecked**
7. Save

### Developer Mode QA Checklist

- [ ] Settings window opens
- [ ] Option-click Developer Mode text opens developer settings
- [ ] Can enter API key
- [ ] Save works (settings persist after reopen)
- [ ] Press Ctrl+Option+V → recording starts (red "STOP" in menu bar)
- [ ] Press Ctrl+Option+V again → transcription happens
- [ ] Text appears in clipboard / auto-pastes
- [ ] Notification shows preview of transcribed text
- [ ] History window shows the entry
- [ ] Recording overlay appears and disappears correctly

---

## Part 4: Test User Mode (Proxy / Cloud)

This tests the subscription flow.

1. Make sure backend is running on `localhost:8000`
2. Launch VibeMic.app
3. Open Settings (menu bar → Settings)
4. **User Settings should open by default**

### Step 4a: Change proxy URL to localhost

In Developer Settings (Option-click → Developer Mode):
- Check "Use VibeMic Cloud"
- Set Server URL to `http://localhost:8000`
- Save

OR: temporarily change `defaultProxyBaseURL` in ConfigManager.swift to `http://localhost:8000` before building.

### Step 4b: Create Account + Login

1. In User Settings → Account section
2. Enter email + password
3. Click "Create Account"
4. Should show "Signed in as ..."
5. Plan badge shows "Free"
6. Usage bar shows "0 min / 10 min used"

### Step 4c: Test Transcription via Proxy

1. Press Ctrl+Option+V → record something
2. Press Ctrl+Option+V → stop
3. App should send audio to `localhost:8000/api/transcribe`
4. Text should appear in clipboard / auto-paste

### Step 4d: Test Paraphrase (Free tier should block)

1. In Developer Settings, enable Paraphrase
2. Record + transcribe
3. Should get error or skip paraphrase (free plan doesn't include it)

### Step 4e: Test Usage Tracking

1. After a transcription, reopen Settings
2. Usage bar should show > 0 min used
3. `curl http://localhost:8000/api/usage -H 'Authorization: Bearer <token>'` should confirm

### Proxy Mode QA Checklist

- [ ] User Settings opens by default (not developer settings)
- [ ] Create Account works → token saved
- [ ] Login works → "Signed in as ..." shows
- [ ] Plan badge shows "Free"
- [ ] Usage bar loads and shows 0/10 min
- [ ] Transcription via proxy works (text returned)
- [ ] Usage bar updates after transcription
- [ ] Paraphrase blocked on free tier (402 error)
- [ ] Upgrade button present (will fail without Stripe setup, that's OK)
- [ ] Logout → reopen → token persisted (still signed in)

---

## Part 5: Edge Cases

- [ ] Record with no mic permission → shows notification asking for permission
- [ ] Record with no API key and no proxy login → shows error
- [ ] Record very short audio (< 1 second) → "No audio recorded" or "No speech detected"
- [ ] Backend down + proxy mode → shows network error
- [ ] Bad JWT token → 401, app shows "Session expired" or similar
- [ ] Global hotkey works in any app (not just VibeMic)
- [ ] History → copy button works
- [ ] History → delete button works
- [ ] History → clear all works (with confirmation dialog)
- [ ] Hotkey recorder in settings → capture new hotkey → works after save
- [ ] Quit from menu bar → app exits cleanly

---

## Part 6: Check Logs

If anything fails, check debug log:

```bash
cat /tmp/vibemic/debug.log
```

Backend logs:

```bash
# If using uvicorn directly:
# logs are in terminal

# If using docker:
docker-compose logs api
```

---

## Quick Smoke Test (5 min)

If you just want a fast sanity check:

1. `swift build` → succeeds?
2. Run .app → menu bar icon appears?
3. Ctrl+Option+V → overlay appears, "STOP" in menu bar?
4. Ctrl+Option+V → notification with text?
5. Settings → fields load?

If all 5 pass, the app is functional.
