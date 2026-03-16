#!/usr/bin/env python3
"""VibeMic Native (macOS) — Voice-to-text for macOS. Press PgDn to record, PgDn again to transcribe and type."""

import json
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

from openai import OpenAI
from pynput import keyboard

# ─── Paths ───
SCRIPT_DIR = Path(__file__).resolve().parent
CONFIG_FILE = SCRIPT_DIR / "config.json"
ENV_FILE = SCRIPT_DIR / ".env"
TEMP_DIR = Path.home() / ".cache" / "vibemic"
TEMP_DIR.mkdir(parents=True, exist_ok=True)
TEMP_WAV = TEMP_DIR / "recording.wav"
MIN_FILE_SIZE = 1000  # bytes — smaller means no real audio

# ─── Available models & options ───
WHISPER_MODELS = [
    "whisper-1",
    "gpt-4o-transcribe",
    "gpt-4o-mini-transcribe",
]

LANGUAGES = [
    ("Auto-detect", ""),
    ("English", "en"),
    ("廣東話 / Chinese", "zh"),
    ("日本語", "ja"),
    ("한국어", "ko"),
    ("Français", "fr"),
    ("Deutsch", "de"),
    ("Español", "es"),
    ("Português", "pt"),
    ("Italiano", "it"),
    ("Nederlands", "nl"),
    ("Polski", "pl"),
    ("Русский", "ru"),
    ("Türkçe", "tr"),
    ("العربية", "ar"),
    ("हिन्दी", "hi"),
    ("ภาษาไทย", "th"),
    ("Tiếng Việt", "vi"),
]

RESPONSE_FORMATS = ["json", "text", "srt", "verbose_json", "vtt"]

# ─── Config management ───
DEFAULT_CONFIG = {
    "api_key": "",
    "model": "gpt-4o-transcribe",
    "language": "",
    "prompt": "廣東話、English、普通話、日本語",
    "temperature": 0,
    "response_format": "json",
    "hotkey": "page_down",
}


def load_config():
    """Load config from config.json, falling back to .env for API key."""
    config = dict(DEFAULT_CONFIG)

    # Try config.json first
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE) as f:
                saved = json.load(f)
            config.update(saved)
        except (json.JSONDecodeError, OSError):
            pass

    # If no API key in config.json, try .env
    if not config.get("api_key"):
        config["api_key"] = _load_env_api_key()

    # Also check environment variable
    env_key = os.environ.get("OPENAI_API_KEY")
    if env_key:
        config["api_key"] = env_key

    return config


def _load_env_api_key():
    """Read OPENAI_API_KEY from .env file."""
    if not ENV_FILE.exists():
        return ""
    try:
        for line in ENV_FILE.read_text().splitlines():
            line = line.strip()
            if line.startswith("OPENAI_API_KEY=") and not line.startswith("#"):
                return line.split("=", 1)[1].strip().strip("\"'")
    except OSError:
        pass
    return ""


def save_config(config):
    """Save config to config.json."""
    try:
        with open(CONFIG_FILE, "w") as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
    except OSError as e:
        print(f"Failed to save config: {e}")


# ─── State ───
config = load_config()
recording_process = None
is_recording = False
state_lock = threading.Lock()
RECORD_KEY = getattr(keyboard.Key, config.get("hotkey", "page_down"), keyboard.Key.page_down)


def notify(title, message):
    """Send macOS desktop notification via osascript."""
    safe_title = title.replace('"', '\\"')
    safe_msg = message.replace('"', '\\"')
    try:
        subprocess.Popen(
            [
                "osascript", "-e",
                f'display notification "{safe_msg}" with title "{safe_title}"'
            ],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except FileNotFoundError:
        print(f"[{title}] {message}")


def type_text(text):
    """Type text into the focused window by copying to clipboard and pasting via Cmd+V."""
    proc = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
    proc.communicate(text.encode("utf-8"))
    time.sleep(0.1)
    subprocess.run(
        [
            "osascript", "-e",
            'tell application "System Events" to keystroke "v" using command down'
        ],
        timeout=5
    )


# ─── Settings GUI (macOS native via osascript + tkinter) ───
class SettingsWindow:
    """Tkinter settings panel for VibeMic configuration."""

    def __init__(self, current_config, on_save):
        self.on_save = on_save
        self.win = None
        self.current_config = current_config

    def open(self):
        """Open the settings window (or focus it if already open)."""
        import tkinter as tk
        from tkinter import ttk, messagebox

        if self.win is not None:
            try:
                self.win.lift()
                self.win.focus_force()
                return
            except tk.TclError:
                self.win = None

        self.win = tk.Tk()
        self.win.title("VibeMic Settings")
        self.win.geometry("520x540")
        self.win.resizable(False, False)

        style = ttk.Style(self.win)
        style.theme_use("aqua" if "aqua" in style.theme_names() else "clam")

        main = ttk.Frame(self.win, padding=20)
        main.pack(fill="both", expand=True)

        row = 0

        # ── API Key ──
        ttk.Label(main, text="OpenAI API Key:", font=("", 10, "bold")).grid(
            row=row, column=0, sticky="w", pady=(0, 2)
        )
        row += 1
        self.api_key_var = tk.StringVar(value=self.current_config.get("api_key", ""))
        api_entry = ttk.Entry(main, textvariable=self.api_key_var, show="•", width=60)
        api_entry.grid(row=row, column=0, columnspan=2, sticky="ew", pady=(0, 5))

        row += 1
        self.show_key = tk.BooleanVar(value=False)
        def toggle_key():
            api_entry.config(show="" if self.show_key.get() else "•")
        ttk.Checkbutton(main, text="Show key", variable=self.show_key, command=toggle_key).grid(
            row=row, column=0, sticky="w", pady=(0, 10)
        )

        # ── Model ──
        row += 1
        ttk.Label(main, text="Model:", font=("", 10, "bold")).grid(
            row=row, column=0, sticky="w", pady=(0, 2)
        )
        row += 1
        self.model_var = tk.StringVar(value=self.current_config.get("model", "gpt-4o-transcribe"))
        model_combo = ttk.Combobox(main, textvariable=self.model_var, values=WHISPER_MODELS, state="readonly", width=30)
        model_combo.grid(row=row, column=0, sticky="w", pady=(0, 10))

        # ── Language ──
        row += 1
        ttk.Label(main, text="Language:", font=("", 10, "bold")).grid(
            row=row, column=0, sticky="w", pady=(0, 2)
        )
        row += 1
        lang_labels = [f"{name} ({code})" if code else name for name, code in LANGUAGES]
        self.lang_var = tk.StringVar()
        current_lang = self.current_config.get("language", "")
        for name, code in LANGUAGES:
            if code == current_lang:
                self.lang_var.set(f"{name} ({code})" if code else name)
                break
        else:
            self.lang_var.set(lang_labels[0])
        lang_combo = ttk.Combobox(main, textvariable=self.lang_var, values=lang_labels, state="readonly", width=30)
        lang_combo.grid(row=row, column=0, sticky="w", pady=(0, 10))

        # ── Prompt ──
        row += 1
        ttk.Label(main, text="Prompt (hint for Whisper):", font=("", 10, "bold")).grid(
            row=row, column=0, sticky="w", pady=(0, 2)
        )
        row += 1
        self.prompt_text = tk.Text(main, height=3, width=58, wrap="word")
        self.prompt_text.insert("1.0", self.current_config.get("prompt", ""))
        self.prompt_text.grid(row=row, column=0, columnspan=2, sticky="ew", pady=(0, 10))

        # ── Temperature ──
        row += 1
        ttk.Label(main, text="Temperature:", font=("", 10, "bold")).grid(
            row=row, column=0, sticky="w", pady=(0, 2)
        )
        row += 1
        temp_frame = ttk.Frame(main)
        temp_frame.grid(row=row, column=0, sticky="w", pady=(0, 10))
        self.temp_var = tk.DoubleVar(value=self.current_config.get("temperature", 0))
        self.temp_label = ttk.Label(temp_frame, text=f"{self.temp_var.get():.1f}")
        temp_scale = ttk.Scale(
            temp_frame, from_=0, to=1, variable=self.temp_var, orient="horizontal", length=250,
            command=lambda v: self.temp_label.config(text=f"{float(v):.1f}")
        )
        temp_scale.pack(side="left")
        self.temp_label.pack(side="left", padx=(10, 0))

        # ── Response Format ──
        row += 1
        ttk.Label(main, text="Response Format:", font=("", 10, "bold")).grid(
            row=row, column=0, sticky="w", pady=(0, 2)
        )
        row += 1
        self.format_var = tk.StringVar(value=self.current_config.get("response_format", "json"))
        format_combo = ttk.Combobox(main, textvariable=self.format_var, values=RESPONSE_FORMATS, state="readonly", width=20)
        format_combo.grid(row=row, column=0, sticky="w", pady=(0, 15))

        # ── Buttons ──
        row += 1
        btn_frame = ttk.Frame(main)
        btn_frame.grid(row=row, column=0, columnspan=2, sticky="e")
        ttk.Button(btn_frame, text="Cancel", command=self._close).pack(side="right", padx=(5, 0))
        ttk.Button(btn_frame, text="Save", command=lambda: self._save(messagebox)).pack(side="right")

        self.win.protocol("WM_DELETE_WINDOW", self._close)
        self.win.mainloop()

    def _get_selected_language_code(self):
        selected = self.lang_var.get()
        for name, code in LANGUAGES:
            label = f"{name} ({code})" if code else name
            if label == selected:
                return code
        return ""

    def _save(self, messagebox):
        api_key = self.api_key_var.get().strip()
        if not api_key:
            messagebox.showwarning("VibeMic", "API Key is required.", parent=self.win)
            return

        new_config = {
            "api_key": api_key,
            "model": self.model_var.get(),
            "language": self._get_selected_language_code(),
            "prompt": self.prompt_text.get("1.0", "end-1c").strip(),
            "temperature": round(self.temp_var.get(), 1),
            "response_format": self.format_var.get(),
            "hotkey": self.current_config.get("hotkey", "page_down"),
        }

        save_config(new_config)
        self.on_save(new_config)
        notify("VibeMic", "Settings saved!")
        self._close()

    def _close(self):
        if self.win:
            self.win.destroy()
            self.win = None


# ─── Recording & transcription ───

def start_recording(app, update_tray):
    """Start sox recording."""
    global recording_process, is_recording

    if TEMP_WAV.exists():
        TEMP_WAV.unlink()

    try:
        recording_process = subprocess.Popen(
            ["sox", "-d", "-r", "16000", "-c", "1", "-b", "16", str(TEMP_WAV)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except FileNotFoundError:
        notify("VibeMic", "sox not found. Install: brew install sox")
        return

    is_recording = True
    update_tray("recording")
    notify("VibeMic", "Recording... Press PgDn to stop")


def stop_and_transcribe(app, update_tray):
    """Stop recording, send to Whisper, type the result."""
    global recording_process, is_recording, config

    if not recording_process:
        is_recording = False
        update_tray("idle")
        return

    recording_process.send_signal(signal.SIGINT)
    try:
        recording_process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        recording_process.kill()
        recording_process.wait()

    recording_process = None
    is_recording = False
    update_tray("transcribing")
    notify("VibeMic", "Transcribing...")

    if not TEMP_WAV.exists():
        notify("VibeMic", "No audio recorded. Check mic.")
        update_tray("idle")
        return

    if TEMP_WAV.stat().st_size < MIN_FILE_SIZE:
        notify("VibeMic", "Too short, try again.")
        update_tray("idle")
        return

    # Reload config in case settings changed
    config = load_config()
    api_key = config.get("api_key", "")

    if not api_key:
        notify("VibeMic", "No API key. Open Settings to set one.")
        update_tray("idle")
        return

    try:
        client = OpenAI(api_key=api_key)
        with open(TEMP_WAV, "rb") as f:
            params = {
                "file": f,
                "model": config.get("model", "whisper-1"),
            }
            lang = config.get("language", "")
            if lang:
                params["language"] = lang

            prompt = config.get("prompt", "")
            if prompt:
                params["prompt"] = prompt

            temp = config.get("temperature", 0)
            if temp > 0:
                params["temperature"] = temp

            resp_fmt = config.get("response_format", "json")
            if resp_fmt and resp_fmt != "json":
                params["response_format"] = resp_fmt

            transcription = client.audio.transcriptions.create(**params)

        text = (transcription.text or "").strip()
        if not text:
            notify("VibeMic", "No speech detected.")
            update_tray("idle")
            return

        type_text(text)
        notify("VibeMic", f"Typed: {text[:60]}{'…' if len(text) > 60 else ''}")
        update_tray("idle")

    except Exception as e:
        msg = str(e)
        if "401" in msg or "Incorrect API key" in msg:
            notify("VibeMic", "Invalid API key. Check Settings.")
        elif "ENOTFOUND" in msg or "ECONNREFUSED" in msg:
            notify("VibeMic", "Can't reach OpenAI.")
        else:
            notify("VibeMic", f"Error: {msg[:80]}")
        update_tray("idle")

    try:
        if TEMP_WAV.exists():
            TEMP_WAV.unlink()
    except OSError:
        pass


def on_hotkey(app, update_tray):
    """Toggle recording on hotkey press."""
    with state_lock:
        if is_recording:
            threading.Thread(target=stop_and_transcribe, args=(app, update_tray), daemon=True).start()
        else:
            start_recording(app, update_tray)


def main():
    global config

    import rumps

    config = load_config()

    if not config.get("api_key"):
        print("WARNING: No OpenAI API key found. Open Settings from the menu bar icon to set one.")

    # Check sox is installed
    try:
        subprocess.run(["which", "sox"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("ERROR: sox not found. Install: brew install sox")
        sys.exit(1)

    # ─── Menu bar app via rumps ───
    class VibeMicApp(rumps.App):
        def __init__(self):
            super().__init__("VibeMic", title="🎙")
            self.menu = [
                rumps.MenuItem("VibeMic — Press PgDn to record"),
                None,
                rumps.MenuItem("Settings...", callback=self._open_settings),
                None,
            ]
            self._state = "idle"

        def update_state(self, state):
            self._state = state
            titles = {
                "idle": "🎙",
                "recording": "🔴",
                "transcribing": "⏳",
            }
            self.title = titles.get(state, "🎙")

        def _open_settings(self, _):
            threading.Thread(target=settings_win.open, daemon=True).start()

    app = VibeMicApp()

    def on_settings_save(new_config):
        global config
        config = new_config

    settings_win = SettingsWindow(config, on_settings_save)

    def update_tray(state):
        app.update_state(state)

    # Global hotkey listener
    def on_press(key):
        if key == RECORD_KEY:
            on_hotkey(app, update_tray)

    listener = keyboard.Listener(on_press=on_press)
    listener.daemon = True
    listener.start()

    print("VibeMic Native (macOS) running. Press PgDn to record. Menu bar icon active.")
    print(f"Config: model={config.get('model')}, language={config.get('language') or 'auto'}")
    print(f"API key: {'set' if config.get('api_key') else 'missing — open Settings'}")
    print("NOTE: Grant Accessibility permission to your terminal in System Settings → Privacy & Security → Accessibility")
    app.run()


if __name__ == "__main__":
    main()
