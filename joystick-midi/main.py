#!/usr/bin/env python3
"""MIDI Joy — maps USB joystick/gamepad axes and buttons to MIDI CC/notes."""

import datetime
import json
import math
import os
import queue
import random
import sys
import threading
import time
import tkinter as tk
from dataclasses import asdict, dataclass, field
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from typing import List, Optional

DT = 0.02          # engine tick interval in seconds
APP_VERSION = "2.0"

# DSKY / AGC color palette
_C = {
    "bg":      "#111111",  # window / frame background
    "bg_disp": "#0a1a0a",  # display readout background
    "fg":      "#39ff14",  # primary phosphor green
    "fg_dim":  "#1a6600",  # dim green (inactive)
    "ind_on":  "#39ff14",  # indicator lit fg
    "ind_off": "#0d2d0d",  # indicator unlit bg
    "btn_bg":  "#1a1a1a",  # button face
    "sel_bg":  "#1a5c0f",  # listbox selection bg
    "border":  "#2a4a2a",  # section border
}

import pygame
import rtmidi

try:
    from pythonosc import udp_client as _osc_udp
    HAS_OSC = True
except ImportError:
    HAS_OSC = False

# ---------------------------------------------------------------------------
# Keyboard joystick (duck-types pygame Joystick for testing without hardware)
# ---------------------------------------------------------------------------

class KeyboardJoystick:
    """Fake joystick driven by tkinter key events. Axes spring back to 0 on release."""
    NAME = "Keyboard (Testing)"
    _STEP = 0.15  # axis travel per 50 ms poll tick (~330 ms to full deflection)

    # (negative-keysym, positive-keysym) per axis — all lowercased
    _AXIS_KEYS = [
        ("left",  "right"),  # Axis 0 — ← →
        ("up",    "down"),   # Axis 1 — ↑ ↓
        ("a",     "d"),      # Axis 2 — A / D
        ("w",     "s"),      # Axis 3 — W / S
    ]
    _BUTTON_KEYS = ["1", "2", "3", "4", "5", "6", "7", "8"]

    # Key legend shown in the live input panel
    LEGEND = (
        "Axes:     ←/→  Axis 0     ↑/↓  Axis 1     A/D  Axis 2     W/S  Axis 3\n"
        "Buttons:  1 2 3 4 5 6 7 8"
    )

    def __init__(self):
        self._axes = [0.0] * len(self._AXIS_KEYS)
        self._pressed: set = set()

    def get_name(self) -> str:        return self.NAME
    def get_numaxes(self) -> int:     return len(self._AXIS_KEYS)
    def get_numbuttons(self) -> int:  return len(self._BUTTON_KEYS)
    def get_axis(self, i: int) -> float: return self._axes[i]
    def get_button(self, i: int) -> int: return int(self._BUTTON_KEYS[i] in self._pressed)
    def init(self): pass

    def press(self, keysym: str):    self._pressed.add(keysym.lower())
    def release(self, keysym: str):  self._pressed.discard(keysym.lower())

    def update(self):
        """Advance axis values toward targets; call once per poll tick."""
        for i, (neg, pos) in enumerate(self._AXIS_KEYS):
            target = (-1.0 if neg in self._pressed else 0.0) + (1.0 if pos in self._pressed else 0.0)
            target = max(-1.0, min(1.0, target))
            diff = target - self._axes[i]
            self._axes[i] += math.copysign(min(abs(diff), self._STEP), diff) if diff else 0.0


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class MappingEntry:
    source: str          # e.g. "Axis 0" or "Button 3"
    source_type: str     # "axis" or "button"
    source_index: int
    out_type: str        # "cc" or "note"
    number: int          # CC# or note#
    channel: int         # 1-16
    range_min: int = 0
    range_max: int = 127
    velocity: int = 100
    invert: bool = False
    sensitivity: float = 1.0
    deadzone: float = 0.02    # axis values within ±deadzone of center snap to 0
    snap_floor: int = 0       # snap CC output to range_min if within this many CC steps
    osc_min: float = 0.0     # OSC-type: float sent when axis is at -1.0
    osc_max: float = 1.0     # OSC-type: float sent when axis is at +1.0
    name: str = ""
    osc_address: str = ""     # custom OSC address; blank = auto (/cc/N or /note/N)
    enabled: bool = True      # False = mapping is paused

    def label(self):
        pause = "⏸ " if not self.enabled else "  "
        if self.out_type == "playlist_next":
            target = "PLAYLIST  next scene  →  /playlist/position"
        elif self.out_type == "osc":
            target = f"OSC  {self.osc_address or '(no addr)'}  [{self.osc_min:.1f}–{self.osc_max:.1f}]"
        elif self.out_type == "cc":
            target = f"CC {self.number:<3}  Ch {self.channel}"
        else:
            target = f"Note {self.number:<3} Ch {self.channel}"
        flags = []
        if self.source_type == "axis":
            if self.invert:
                flags.append("INV")
            if abs(self.sensitivity - 1.0) > 0.01:
                flags.append(f"{self.sensitivity:.2f}×")
            if self.deadzone > 0:
                flags.append(f"dz{self.deadzone:.2f}")
            if self.snap_floor > 0:
                flags.append(f"sf{self.snap_floor}")
        flag_str = f"  [{', '.join(flags)}]" if flags else ""
        name_col = f"{self.name:<14}" if self.name else " " * 14
        return f"{pause}{name_col} {self.source:<10} →  {target}{flag_str}"


@dataclass
class OscConfig:
    enabled: bool = False
    host: str = "127.0.0.1"
    port: int = 9000


@dataclass
class AutopilotConfig:
    enabled: bool = False
    inactivity_seconds: float = 30.0
    axes: List[int] = field(default_factory=list)
    drift: float = 0.3   # OU sigma knob  (0.0–1.0)
    speed: float = 0.3   # OU theta knob  (0.0–1.0)


@dataclass
class PlaylistConfig:
    enabled: bool = False
    size: int = 8        # total scenes in Synesthesia playlist
    randomize: bool = False
    position: int = -1   # -1 = before first scene; first advance lands on scene 1
    auto_advance: bool = False
    auto_advance_seconds: float = 30.0
    midi_trigger: bool = False
    midi_note: int = 60
    midi_channel: int = 1
    midi_velocity: int = 100


# ---------------------------------------------------------------------------
# MIDI engine (background thread)
# ---------------------------------------------------------------------------

MAX_LOG_ENTRIES = 200


class MidiEngine:
    def __init__(self):
        self._lock = threading.Lock()
        self._mappings: List[MappingEntry] = []
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._midi_out = rtmidi.MidiOut()
        self._joystick: Optional[pygame.joystick.JoystickType] = None
        self._last_axis: dict = {}
        self._button_state: dict = {}
        self.activity_queue: queue.Queue = queue.Queue()
        self._ap_config = AutopilotConfig()
        self._ap_values: dict = {}
        self._last_real_input: float = time.time()
        self._ap_active: bool = False
        self._axis_cal: dict = {}  # {axis_index: {"offset": float, "enabled": bool}}
        self._osc_config = OscConfig()
        self._osc_client = None
        self._pl_client = None  # dedicated client for playlist; works even when OSC output is off
        self._last_osc: dict[str, float] = {}
        self._osc_order: list[str] = []
        self._playlist = PlaylistConfig()
        self._pl_order: list[int] = list(range(1, self._playlist.size + 1))
        self._pl_last_advance: float = time.time()
        self._osc_in_ref = None  # set by MapperApp to enable direct WORLD updates

    def get_midi_ports(self) -> List[str]:
        return self._midi_out.get_ports()

    def open_port(self, index: int):
        if self._midi_out.is_port_open():
            self._midi_out.close_port()
        self._midi_out.open_port(index)

    def set_joystick(self, joystick: Optional[pygame.joystick.JoystickType]):
        with self._lock:
            self._joystick = joystick
            self._last_axis.clear()
            self._button_state.clear()

    def set_mappings(self, mappings: List[MappingEntry]):
        with self._lock:
            self._mappings = list(mappings)

    def set_autopilot(self, config: AutopilotConfig):
        with self._lock:
            self._ap_config = config

    def set_axis_cal(self, cal: dict):
        with self._lock:
            self._axis_cal = dict(cal)

    def set_osc(self, config: OscConfig):
        with self._lock:
            self._osc_config = config
            if HAS_OSC and config.enabled:
                try:
                    self._osc_client = _osc_udp.SimpleUDPClient(config.host, config.port)
                except Exception:
                    self._osc_client = None
            else:
                self._osc_client = None
            if HAS_OSC and config.host:
                try:
                    self._pl_client = _osc_udp.SimpleUDPClient(config.host, config.port)
                except Exception:
                    self._pl_client = None

    @property
    def autopilot_active(self) -> bool:
        with self._lock:
            return self._ap_active

    def start(self):
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=1.0)
            self._thread = None

    def _run(self):
        while self._running:
            # pygame.event.pump() must run on the main thread — SDL event processing
            # is not thread-safe. The main thread's _poll_joystick() handles it.
            with self._lock:
                js = self._joystick
                mappings = list(self._mappings)
                ap = self._ap_config
            pl = self._playlist
            if (pl.enabled and pl.auto_advance and pl.size > 0 and
                    time.time() - self._pl_last_advance >= pl.auto_advance_seconds):
                self.playlist_advance()

            if js is None:
                time.sleep(DT)
                continue

            ap_on = ap.enabled and (time.time() - self._last_real_input) > ap.inactivity_seconds
            with self._lock:
                self._ap_active = ap_on

            for m in mappings:
                if not m.enabled:
                    continue
                if m.source_type == "axis":
                    real_raw = js.get_axis(m.source_index)
                    prev_real = self._last_axis.get(m.source_index)

                    # Detect real joystick movement to reset inactivity clock
                    if prev_real is None or abs(real_raw - prev_real) > 0.005:
                        self._last_real_input = time.time()
                        self._pl_last_advance = time.time()
                        self._ap_values.pop(m.source_index, None)

                    if ap_on and m.source_index in ap.axes:
                        # Ornstein-Uhlenbeck update: smooth mean-reverting random walk
                        x = self._ap_values.get(m.source_index, 0.0)
                        theta = 0.2 + ap.speed * 3.8
                        sigma = ap.drift * 0.6
                        x += -theta * x * DT + sigma * math.sqrt(DT) * random.gauss(0, 1)
                        x = max(-1.0, min(1.0, x))
                        self._ap_values[m.source_index] = x
                        raw = x
                    else:
                        raw = real_raw
                        self._last_axis[m.source_index] = real_raw

                    # Apply center calibration offset
                    cal = self._axis_cal.get(m.source_index, {})
                    if cal.get("enabled"):
                        raw = max(-1.0, min(1.0, raw - cal.get("offset", 0.0)))

                    # Apply dead zone: snap near-center values to exactly 0
                    if abs(raw) <= m.deadzone:
                        raw = 0.0

                    if m.out_type == "playlist_next":
                        continue
                    processed = (-raw if m.invert else raw) * m.sensitivity
                    processed = max(-1.0, min(1.0, processed))
                    if m.out_type == "osc":
                        osc_val = (processed + 1.0) / 2.0 * (m.osc_max - m.osc_min) + m.osc_min
                        self._send_osc(m.osc_address or f"/axis/{m.source_index}", osc_val)
                    else:
                        val = round((processed + 1.0) / 2.0 * (m.range_max - m.range_min) + m.range_min)
                        val = max(m.range_min, min(m.range_max, val))
                        if m.snap_floor > 0 and val - m.range_min <= m.snap_floor:
                            val = m.range_min
                        if m.out_type == "cc":
                            self._send([0xB0 | (m.channel - 1), m.number, val])
                            self._send_osc(m.osc_address or f"/cc/{m.number}", val / 127.0)
                        else:
                            self._send([0x90 | (m.channel - 1), m.number, val])
                            self._send_osc(m.osc_address or f"/note/{m.number}", val / 127.0)

                elif m.source_type == "button":
                    pressed = js.get_button(m.source_index)
                    prev = self._button_state.get(m.source_index, False)
                    if pressed != prev:
                        self._button_state[m.source_index] = pressed
                        self._pl_last_advance = time.time()
                        if m.out_type == "playlist_next":
                            if pressed:
                                self.playlist_advance()
                        elif m.out_type == "osc":
                            osc_val = m.osc_max if pressed else m.osc_min
                            self._send_osc(m.osc_address or f"/button/{m.source_index}", osc_val)
                        elif m.out_type == "note":
                            status = 0x90 if pressed else 0x80
                            vel = m.velocity if pressed else 0
                            self._send([status | (m.channel - 1), m.number, vel])
                            self._send_osc(m.osc_address or f"/note/{m.number}", vel / 127.0)
                        else:
                            v = 127 if pressed else 0
                            self._send([0xB0 | (m.channel - 1), m.number, v])
                            self._send_osc(m.osc_address or f"/cc/{m.number}", 1.0 if pressed else 0.0)
            time.sleep(DT)

    def set_playlist(self, config: PlaylistConfig):
        with self._lock:
            self._playlist = config
            order = list(range(1, config.size + 1))
            if config.randomize:
                import random
                random.shuffle(order)
            self._pl_order = order
            if config.position < 0:
                self._playlist.position = -1
            else:
                self._playlist.position = max(0, min(config.position, config.size - 1))

    def playlist_advance(self):
        pl = self._playlist
        if not pl.enabled or pl.size == 0:
            return
        self._pl_last_advance = time.time()
        pl.position = (pl.position + 1) % pl.size
        scene_idx = self._pl_order[pl.position]
        client = self._pl_client or self._osc_client
        if client is not None:
            try:
                client.send_message("/playlist/position", float(scene_idx))
            except Exception:
                pass
        ts = time.strftime("%H:%M:%S")
        self.activity_queue.put(
            f"{ts}  PLAYLIST scene {scene_idx:02d}  →  /playlist/position {float(scene_idx):.0f}")
        if pl.midi_trigger:
            self._send([0x90 | (pl.midi_channel - 1), pl.midi_note, pl.midi_velocity])
            self._send([0x80 | (pl.midi_channel - 1), pl.midi_note, 0])
        if self._osc_in_ref is not None:
            self._osc_in_ref.set_world(scene_idx)

    def playlist_goto(self, position: int):
        pl = self._playlist
        if pl.size == 0:
            return
        self._pl_last_advance = time.time()
        pl.position = max(0, min(position, pl.size - 1))
        scene_idx = self._pl_order[pl.position]
        client = self._pl_client or self._osc_client
        if client is not None:
            try:
                client.send_message("/playlist/position", float(scene_idx))
            except Exception:
                pass
        ts = time.strftime("%H:%M:%S")
        self.activity_queue.put(
            f"{ts}  PLAYLIST scene {scene_idx:02d}  →  /playlist/position {float(scene_idx):.0f}")
        if self._osc_in_ref is not None:
            self._osc_in_ref.set_world(scene_idx)

    @property
    def playlist_position(self) -> int:
        return self._playlist.position

    def _send(self, msg: list):
        if self._midi_out.is_port_open():
            self._midi_out.send_message(msg)
            self.activity_queue.put(self._fmt(msg))

    def _send_osc(self, address: str, value: float):
        if address not in self._last_osc:
            self._osc_order.append(address)
        self._last_osc[address] = value
        if self._osc_client is not None:
            try:
                self._osc_client.send_message(address, value)
                ts = time.strftime("%H:%M:%S")
                self.activity_queue.put(f"{ts}  OSC {address}  {value:.3f}")
            except Exception:
                pass

    def get_osc_snapshot(self, n: int = 3) -> list:
        """Return the n most-recently-seen OSC (address, value) pairs."""
        result = [(a, self._last_osc[a]) for a in self._osc_order[:n]]
        while len(result) < n:
            result.append(("--", None))
        return result

    def _fmt(self, msg: list) -> str:
        ts = time.strftime("%H:%M:%S")
        status = msg[0] & 0xF0
        ch = (msg[0] & 0x0F) + 1
        if status == 0xB0:
            return f"{ts}  CC {msg[1]:3d}  val {msg[2]:3d}  Ch {ch}"
        elif status == 0x90:
            return f"{ts}  Note On  {msg[1]:3d}  vel {msg[2]:3d}  Ch {ch}"
        elif status == 0x80:
            return f"{ts}  Note Off {msg[1]:3d}              Ch {ch}"
        else:
            return f"{ts}  {' '.join(f'{b:02X}' for b in msg)}"

    def close(self):
        self.stop()
        if self._midi_out.is_port_open():
            self._midi_out.close_port()


# ---------------------------------------------------------------------------
# OSC input server (receives /world messages to drive the AGC display)
# ---------------------------------------------------------------------------

class OscInputServer:
    """Background OSC UDP receiver. Listens for /world <int 0-99> messages."""

    def __init__(self, port: int = 9001):
        self._port = port
        self._lock = threading.Lock()
        self._world: Optional[int] = None
        self._server = None
        self._thread: Optional[threading.Thread] = None

    def start(self):
        if not HAS_OSC:
            return
        try:
            from pythonosc.osc_server import ThreadingOSCUDPServer
            from pythonosc.dispatcher import Dispatcher
            dp = Dispatcher()
            dp.map("/world", self._handle_world)
            dp.set_default_handler(lambda *_: None)
            self._server = ThreadingOSCUDPServer(("0.0.0.0", self._port), dp)
            self._thread = threading.Thread(
                target=self._server.serve_forever, daemon=True, name="osc-in")
            self._thread.start()
        except Exception:
            self._server = None

    def stop(self):
        if self._server:
            self._server.shutdown()
            self._server = None

    def _handle_world(self, address, *args):
        if args:
            try:
                val = max(0, min(99, int(args[0])))
                with self._lock:
                    self._world = val
            except (ValueError, TypeError):
                pass

    def world_value(self) -> Optional[int]:
        with self._lock:
            return self._world

    def set_world(self, n: int):
        with self._lock:
            self._world = max(0, min(99, int(n)))


# ---------------------------------------------------------------------------
# Add / Edit mapping dialog
# ---------------------------------------------------------------------------

class MappingDialog(tk.Toplevel):
    def __init__(self, parent, joystick: Optional[pygame.joystick.JoystickType],
                 entry: Optional[MappingEntry] = None):
        super().__init__(parent)
        self.configure(bg=_C["bg"])
        self.title("Edit Mapping" if entry else "Add Mapping")
        self.resizable(False, False)
        self.grab_set()
        self.result: Optional[MappingEntry] = None

        self._sources = []
        if joystick:
            for i in range(joystick.get_numaxes()):
                self._sources.append(("axis", i, f"Axis {i}"))
            for i in range(joystick.get_numbuttons()):
                self._sources.append(("button", i, f"Button {i}"))
        if not self._sources:
            self._sources = [("axis", 0, "Axis 0")]

        pad = {"padx": 8, "pady": 4}

        # Shorthand style dicts
        lkw = dict(bg=_C["bg"], fg=_C["fg"])
        ekw = dict(bg=_C["bg_disp"], fg=_C["fg"], insertbackground=_C["fg"],
                   relief="flat", font=("Courier", 11))
        skw = dict(bg=_C["bg_disp"], fg=_C["fg"], buttonbackground=_C["btn_bg"],
                   relief="flat", font=("Courier", 11))
        bkw = dict(bg=_C["btn_bg"], fg=_C["fg"],
                   activebackground="#2a2a2a", activeforeground=_C["fg"],
                   relief="raised", bd=1)
        ckw = dict(bg=_C["bg"], fg=_C["fg"], selectcolor=_C["bg_disp"],
                   activebackground=_C["bg"], activeforeground=_C["fg"])

        # Name
        tk.Label(self, text="Name:", **lkw).grid(row=0, column=0, sticky="e", **pad)
        self._name_var = tk.StringVar()
        tk.Entry(self, textvariable=self._name_var, width=22, **ekw).grid(
            row=0, column=1, columnspan=2, sticky="ew", **pad)

        # Source
        tk.Label(self, text="Source:", **lkw).grid(row=1, column=0, sticky="e", **pad)
        self._src_var = tk.StringVar()
        self._src_cb = ttk.Combobox(self, textvariable=self._src_var,
                                    values=[s[2] for s in self._sources],
                                    state="readonly", width=14,
                                    style="DSKY.TCombobox")
        self._src_cb.grid(row=1, column=1, columnspan=2, sticky="w", **pad)
        self._src_cb.bind("<<ComboboxSelected>>", self._on_src_change)

        # Output type
        tk.Label(self, text="Output type:", **lkw).grid(row=2, column=0, sticky="e", **pad)
        self._out_var = tk.StringVar(value="cc")
        tk.Radiobutton(self, text="CC", variable=self._out_var,
                       value="cc", command=self._on_type_change, **ckw).grid(
            row=2, column=1, sticky="w")
        tk.Radiobutton(self, text="Note", variable=self._out_var,
                       value="note", command=self._on_type_change, **ckw).grid(
            row=2, column=2, sticky="w")
        tk.Radiobutton(self, text="OSC", variable=self._out_var,
                       value="osc", command=self._on_type_change, **ckw).grid(
            row=2, column=3, sticky="w")
        tk.Radiobutton(self, text="Playlist", variable=self._out_var,
                       value="playlist_next", command=self._on_type_change, **ckw).grid(
            row=2, column=4, sticky="w")

        # Number
        self._num_lbl = tk.Label(self, text="Number (0–127):", **lkw)
        self._num_lbl.grid(row=3, column=0, sticky="e", **pad)
        self._num_var = tk.IntVar(value=1)
        self._num_sb = tk.Spinbox(self, from_=0, to=127, textvariable=self._num_var, width=6, **skw)
        self._num_sb.grid(row=3, column=1, sticky="w", **pad)

        # Channel
        self._ch_lbl = tk.Label(self, text="Channel (1–16):", **lkw)
        self._ch_lbl.grid(row=4, column=0, sticky="e", **pad)
        self._ch_var = tk.IntVar(value=1)
        self._ch_sb = tk.Spinbox(self, from_=1, to=16, textvariable=self._ch_var, width=6, **skw)
        self._ch_sb.grid(row=4, column=1, sticky="w", **pad)

        # Axis options
        self._axis_frame = tk.LabelFrame(self, text="Axis options",
                                          bg=_C["bg"], fg=_C["fg_dim"])
        self._axis_frame.grid(row=5, column=0, columnspan=3, sticky="ew", padx=8, pady=4)

        tk.Label(self._axis_frame, text="Output min:", **lkw).grid(row=0, column=0, sticky="e", **pad)
        self._rmin_var = tk.IntVar(value=0)
        tk.Spinbox(self._axis_frame, from_=0, to=127, textvariable=self._rmin_var,
                   width=6, **skw).grid(row=0, column=1, sticky="w", **pad)
        tk.Label(self._axis_frame, text="max:", **lkw).grid(row=0, column=2, sticky="e", **pad)
        self._rmax_var = tk.IntVar(value=127)
        tk.Spinbox(self._axis_frame, from_=0, to=127, textvariable=self._rmax_var,
                   width=6, **skw).grid(row=0, column=3, sticky="w", **pad)

        self._invert_var = tk.BooleanVar(value=False)
        tk.Checkbutton(self._axis_frame, text="Reverse axis direction",
                       variable=self._invert_var, **ckw).grid(
            row=1, column=0, columnspan=4, sticky="w", padx=8, pady=(0, 4))

        tk.Label(self._axis_frame, text="Sensitivity:", **lkw).grid(row=2, column=0, sticky="e", **pad)
        self._sens_var = tk.DoubleVar(value=1.0)
        self._sens_lbl = tk.Label(self._axis_frame, text="1.00×", width=6, anchor="w", **lkw)
        self._sens_lbl.grid(row=2, column=2, sticky="w")
        tk.Scale(self._axis_frame, from_=0.25, to=4.0, resolution=0.05,
                 orient="horizontal", variable=self._sens_var,
                 showvalue=False, length=160,
                 bg=_C["bg"], fg=_C["fg"], troughcolor=_C["bg_disp"],
                 highlightbackground=_C["bg"], activebackground=_C["fg"],
                 command=lambda _: self._update_sens_label()).grid(
            row=2, column=1, sticky="w", padx=(8, 4), pady=4)
        tk.Button(self._axis_frame, text="Reset",
                  command=lambda: [self._sens_var.set(1.0), self._update_sens_label()],
                  **bkw).grid(row=2, column=3, padx=4)

        tk.Label(self._axis_frame, text="Dead zone:", **lkw).grid(row=3, column=0, sticky="e", **pad)
        self._dz_var = tk.DoubleVar(value=0.02)
        self._dz_lbl = tk.Label(self._axis_frame, text="±0.02", width=6, anchor="w", **lkw)
        self._dz_lbl.grid(row=3, column=2, sticky="w")
        tk.Scale(self._axis_frame, from_=0.0, to=0.25, resolution=0.005,
                 orient="horizontal", variable=self._dz_var,
                 showvalue=False, length=160,
                 bg=_C["bg"], fg=_C["fg"], troughcolor=_C["bg_disp"],
                 highlightbackground=_C["bg"], activebackground=_C["fg"],
                 command=lambda _: self._dz_lbl.config(
                     text=f"±{self._dz_var.get():.3f}")).grid(
            row=3, column=1, sticky="w", padx=(8, 4), pady=4)
        tk.Button(self._axis_frame, text="None",
                  command=lambda: [self._dz_var.set(0.0),
                                   self._dz_lbl.config(text="±0.000")],
                  **bkw).grid(row=3, column=3, padx=4)

        self._snap_floor_lbl = tk.Label(self._axis_frame, text="Floor snap (CC):", **lkw)
        self._snap_floor_lbl.grid(row=4, column=0, sticky="e", **pad)
        self._snap_floor_var = tk.IntVar(value=0)
        self._snap_floor_sb = tk.Spinbox(self._axis_frame, from_=0, to=30,
                                          textvariable=self._snap_floor_var, width=4, **skw)
        self._snap_floor_sb.grid(row=4, column=1, sticky="w", padx=(8, 4), pady=4)
        self._snap_floor_hint = tk.Label(self._axis_frame, text="(0 = off)", fg=_C["fg_dim"],
                                          bg=_C["bg"], font=("Helvetica", 9))
        self._snap_floor_hint.grid(row=4, column=2, sticky="w")

        self._osc_range_lbl = tk.Label(self._axis_frame, text="OSC range:", **lkw)
        self._osc_range_lbl.grid(row=5, column=0, sticky="e", **pad)
        self._osc_min_var = tk.DoubleVar(value=0.0)
        self._osc_max_var = tk.DoubleVar(value=1.0)
        self._osc_min_sb = tk.Spinbox(self._axis_frame, from_=-10.0, to=10.0, increment=0.1,
                                       textvariable=self._osc_min_var, width=5, **skw)
        self._osc_min_sb.grid(row=5, column=1, sticky="w", padx=(8, 2), pady=4)
        self._osc_dash_lbl = tk.Label(self._axis_frame, text="–", **lkw)
        self._osc_dash_lbl.grid(row=5, column=2, sticky="w")
        self._osc_max_sb = tk.Spinbox(self._axis_frame, from_=-10.0, to=10.0, increment=0.1,
                                       textvariable=self._osc_max_var, width=5, **skw)
        self._osc_max_sb.grid(row=5, column=3, sticky="w", padx=(2, 4), pady=4)
        self._osc_range_widgets = [self._osc_range_lbl, self._osc_min_sb,
                                    self._osc_dash_lbl, self._osc_max_sb]
        self._snap_floor_widgets = [self._snap_floor_lbl, self._snap_floor_sb, self._snap_floor_hint]

        # Velocity frame
        self._vel_frame = tk.LabelFrame(self, text="Note velocity",
                                         bg=_C["bg"], fg=_C["fg_dim"])
        self._vel_frame.grid(row=6, column=0, columnspan=3, sticky="ew", **pad)
        tk.Label(self._vel_frame, text="Velocity:", **lkw).grid(row=0, column=0, **pad)
        self._vel_var = tk.IntVar(value=100)
        tk.Spinbox(self._vel_frame, from_=1, to=127, textvariable=self._vel_var,
                   width=6, **skw).grid(row=0, column=1, **pad)

        # OSC address override
        tk.Label(self, text="OSC address:", **lkw).grid(row=7, column=0, sticky="e", **pad)
        osc_row = tk.Frame(self, bg=_C["bg"])
        osc_row.grid(row=7, column=1, columnspan=2, sticky="ew", **pad)
        self._osc_addr_var = tk.StringVar()
        tk.Entry(osc_row, textvariable=self._osc_addr_var, width=18, **ekw).pack(side="left")
        tk.Label(osc_row, text="(blank = auto)", fg=_C["fg_dim"],
                 bg=_C["bg"], font=("Helvetica", 9)).pack(side="left", padx=(6, 0))

        # OK / Cancel
        btn_frame = tk.Frame(self, bg=_C["bg"])
        btn_frame.grid(row=8, column=0, columnspan=3, pady=8)
        tk.Button(btn_frame, text="OK", width=8, command=self._ok, **bkw).pack(side="left", padx=4)
        tk.Button(btn_frame, text="Cancel", width=8, command=self.destroy, **bkw).pack(side="left", padx=4)

        # Pre-fill from existing entry
        if entry:
            self._name_var.set(entry.name)
            self._src_var.set(entry.source)
            self._out_var.set(entry.out_type)
            self._num_var.set(entry.number)
            self._ch_var.set(entry.channel)
            self._rmin_var.set(entry.range_min)
            self._rmax_var.set(entry.range_max)
            self._vel_var.set(entry.velocity)
            self._invert_var.set(entry.invert)
            self._sens_var.set(entry.sensitivity)
            self._dz_var.set(entry.deadzone)
            self._dz_lbl.config(text=f"±{entry.deadzone:.3f}")
            self._snap_floor_var.set(entry.snap_floor)
            self._osc_min_var.set(entry.osc_min)
            self._osc_max_var.set(entry.osc_max)
            self._osc_addr_var.set(entry.osc_address)
        elif self._sources:
            self._src_var.set(self._sources[0][2])

        self._update_sens_label()
        self._on_src_change()
        self._on_type_change()

    def _update_sens_label(self):
        self._sens_lbl.config(text=f"{self._sens_var.get():.2f}×")

    def _on_src_change(self, *_):
        self._on_type_change()

    def _on_type_change(self, *_):
        src_label = self._src_var.get()
        src = next((s for s in self._sources if s[2] == src_label), None)
        is_axis = src and src[0] == "axis"
        out_type = self._out_var.get()
        is_osc = out_type == "osc"
        is_playlist = out_type == "playlist_next"

        if is_osc or is_playlist:
            self._num_lbl.grid_remove(); self._num_sb.grid_remove()
            self._ch_lbl.grid_remove();  self._ch_sb.grid_remove()
            self._vel_frame.grid_remove()
        else:
            self._num_lbl.grid(); self._num_sb.grid()
            self._ch_lbl.grid();  self._ch_sb.grid()

        if is_playlist:
            self._axis_frame.grid_remove()
            self._vel_frame.grid_remove()
        elif is_axis:
            self._axis_frame.grid()
            if not is_osc:
                self._vel_frame.grid_remove()
            for w in self._osc_range_widgets:
                (w.grid() if is_osc else w.grid_remove())
            for w in self._snap_floor_widgets:
                (w.grid_remove() if is_osc else w.grid())
        else:
            self._axis_frame.grid_remove()
            if out_type == "note" and not is_osc:
                self._vel_frame.grid()
            else:
                self._vel_frame.grid_remove()

    def _ok(self):
        src_label = self._src_var.get()
        src = next((s for s in self._sources if s[2] == src_label), None)
        if not src:
            messagebox.showerror("Error", "Select a source.", parent=self)
            return
        src_type, src_idx, _ = src
        self.result = MappingEntry(
            source=src_label,
            source_type=src_type,
            source_index=src_idx,
            out_type=self._out_var.get(),
            number=self._num_var.get(),
            channel=self._ch_var.get(),
            range_min=self._rmin_var.get(),
            range_max=self._rmax_var.get(),
            velocity=self._vel_var.get(),
            invert=self._invert_var.get(),
            sensitivity=round(self._sens_var.get(), 4),
            deadzone=round(self._dz_var.get(), 4),
            snap_floor=self._snap_floor_var.get(),
            osc_min=round(self._osc_min_var.get(), 3),
            osc_max=round(self._osc_max_var.get(), 3),
            name=self._name_var.get().strip(),
            osc_address=self._osc_addr_var.get().strip(),
        )
        self.destroy()


# ---------------------------------------------------------------------------
# Main application window
# ---------------------------------------------------------------------------

if getattr(sys, 'frozen', False):
    _BASE_DIR = os.path.dirname(sys.executable)
else:
    _BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CONFIG = os.path.join(_BASE_DIR, "mappings.json")
POLL_INTERVAL_MS = 50
MAX_BARS = 20
BTN_COLS = 8  # buttons per row in the button state grid

# Indicator light definitions: (display label, internal key)
_INDICATORS = [
    ("MIDI OUT", "midi"),
    ("OSC  OUT", "osc"),
    ("AUTO PIL", "auto"),
    ("CTRL CON", "ctrl"),
    ("CAL  ACT", "cal"),
    ("KEY  MODE", "key"),
]


# ---------------------------------------------------------------------------
# Playlist window
# ---------------------------------------------------------------------------

class PlaylistWindow(tk.Toplevel):
    """Floating panel for Synesthesia playlist control."""

    POLL_MS = 200

    def __init__(self, parent, engine, on_change):
        super().__init__(parent)
        self.title("MIDI Joy — Playlist")
        self.resizable(False, False)
        self.configure(bg=_C["bg"])
        try:
            self.attributes("-topmost", True)
        except Exception:
            pass
        self._engine = engine
        self._on_change = on_change  # callback(PlaylistConfig) → saves config

        lkw = dict(bg=_C["bg"], fg=_C["fg"])
        skw = dict(bg=_C["bg_disp"], fg=_C["fg"], buttonbackground=_C["btn_bg"],
                   relief="flat", font=("Courier", 11))
        ckw = dict(bg=_C["bg"], fg=_C["fg"], selectcolor=_C["bg_disp"],
                   activebackground=_C["bg"], activeforeground=_C["fg"])
        bkw = dict(bg=_C["btn_bg"], fg=_C["fg"],
                   activebackground="#2a2a2a", activeforeground=_C["fg"],
                   relief="raised", bd=1)

        cfg = engine._playlist
        pad = {"padx": 10, "pady": 5}

        # Config panel
        cfg_frame = tk.Frame(self, bg=_C["bg_disp"], padx=12, pady=10)
        cfg_frame.pack(fill="x", padx=12, pady=(12, 6))

        self._enabled_var = tk.BooleanVar(value=cfg.enabled)
        tk.Checkbutton(cfg_frame, text="ENABLED", variable=self._enabled_var,
                       command=self._push, **ckw).grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 6))

        tk.Label(cfg_frame, text="Scenes in playlist:", **lkw).grid(
            row=1, column=0, sticky="w", **pad)
        self._size_var = tk.IntVar(value=cfg.size)
        tk.Spinbox(cfg_frame, from_=1, to=99, textvariable=self._size_var,
                   width=5, command=self._push, **skw).grid(
            row=1, column=1, sticky="w", **pad)

        self._rand_var = tk.BooleanVar(value=cfg.randomize)
        tk.Checkbutton(cfg_frame, text="Randomize order", variable=self._rand_var,
                       command=self._push, **ckw).grid(
            row=2, column=0, columnspan=2, sticky="w", pady=(4, 0))

        tk.Frame(cfg_frame, bg=_C["fg_dim"], height=1).grid(
            row=3, column=0, columnspan=2, sticky="ew", pady=(8, 4))

        self._auto_var = tk.BooleanVar(value=cfg.auto_advance)
        tk.Checkbutton(cfg_frame, text="Auto advance after (seconds):",
                       variable=self._auto_var, command=self._push, **ckw).grid(
            row=4, column=0, sticky="w")
        self._auto_sec_var = tk.DoubleVar(value=cfg.auto_advance_seconds)
        tk.Spinbox(cfg_frame, from_=1, to=3600, increment=5,
                   textvariable=self._auto_sec_var, width=6,
                   command=self._push, **skw).grid(
            row=4, column=1, sticky="w", **pad)

        tk.Frame(cfg_frame, bg=_C["fg_dim"], height=1).grid(
            row=5, column=0, columnspan=2, sticky="ew", pady=(8, 4))

        self._midi_trig_var = tk.BooleanVar(value=cfg.midi_trigger)
        tk.Checkbutton(cfg_frame, text="MIDI trigger:", variable=self._midi_trig_var,
                       command=self._push, **ckw).grid(
            row=6, column=0, sticky="w")
        midi_row = tk.Frame(cfg_frame, bg=_C["bg_disp"])
        midi_row.grid(row=6, column=1, sticky="w", **pad)
        self._midi_note_var = tk.IntVar(value=cfg.midi_note)
        self._midi_ch_var   = tk.IntVar(value=cfg.midi_channel)
        self._midi_vel_var  = tk.IntVar(value=cfg.midi_velocity)
        tk.Label(midi_row, text="Note", bg=_C["bg_disp"], fg=_C["fg_dim"],
                 font=("Helvetica", 8)).pack(side="left")
        tk.Spinbox(midi_row, from_=0, to=127, textvariable=self._midi_note_var,
                   width=4, command=self._push, **skw).pack(side="left", padx=(2, 6))
        tk.Label(midi_row, text="Ch", bg=_C["bg_disp"], fg=_C["fg_dim"],
                 font=("Helvetica", 8)).pack(side="left")
        tk.Spinbox(midi_row, from_=1, to=16, textvariable=self._midi_ch_var,
                   width=3, command=self._push, **skw).pack(side="left", padx=(2, 6))
        tk.Label(midi_row, text="Vel", bg=_C["bg_disp"], fg=_C["fg_dim"],
                 font=("Helvetica", 8)).pack(side="left")
        tk.Spinbox(midi_row, from_=1, to=127, textvariable=self._midi_vel_var,
                   width=4, command=self._push, **skw).pack(side="left", padx=(2, 0))

        # Status row
        status_frame = tk.Frame(self, bg=_C["bg"], padx=12, pady=4)
        status_frame.pack(fill="x", padx=12, pady=(0, 4))
        self._pos_lbl = tk.Label(status_frame, text="Scene:  -- / --",
                                 bg=_C["bg"], fg=_C["fg"],
                                 font=("Courier", 13, "bold"))
        self._pos_lbl.pack(side="left")
        tk.Button(status_frame, text="RESET TO START",
                  command=self._reset, **bkw).pack(side="right")

        self._poll()

    def _push(self, *_):
        try:
            size = max(1, int(self._size_var.get()))
        except (ValueError, tk.TclError):
            size = 1
        try:
            auto_sec = max(1.0, float(self._auto_sec_var.get()))
        except (ValueError, tk.TclError):
            auto_sec = 30.0
        cfg = PlaylistConfig(
            enabled=self._enabled_var.get(),
            size=size,
            randomize=self._rand_var.get(),
            position=self._engine._playlist.position,
            auto_advance=self._auto_var.get(),
            auto_advance_seconds=auto_sec,
            midi_trigger=self._midi_trig_var.get(),
            midi_note=self._midi_note_var.get(),
            midi_channel=self._midi_ch_var.get(),
            midi_velocity=self._midi_vel_var.get(),
        )
        self._engine.set_playlist(cfg)
        self._on_change(cfg)

    def _reset(self):
        self._engine.playlist_goto(0)
        self._on_change(self._engine._playlist)

    def _poll(self):
        if not self.winfo_exists():
            return
        pl = self._engine._playlist
        pos_str = f"{pl.position + 1:02d}" if pl.position >= 0 else "--"
        self._pos_lbl.config(text=f"Scene:  {pos_str} / {pl.size:02d}")
        self.after(self.POLL_MS, self._poll)


# ---------------------------------------------------------------------------
# AGC / DSKY output window
# ---------------------------------------------------------------------------

class DskyWindow(tk.Toplevel):
    """Standalone AGC-style display: status indicators, WORLD OSC value, clock + 3 axes."""

    POLL_MS = 100
    _DISP_FONT = "DS-Digital"

    @staticmethod
    def _fmt_osc(v: float) -> str:
        a = abs(v)
        if a < 10:
            return f"{v:+.3f}"
        elif a < 100:
            return f"{v:+.2f}"
        elif a < 1000:
            return f"{v:+.1f}"
        else:
            return f"{v:+.0f}"

    def __init__(self, parent, get_osc_vals, get_indicators, osc_in):
        super().__init__(parent)
        self.title("MIDI Joy — AGC")
        self.resizable(True, True)
        self.configure(bg=_C["bg"])
        self.geometry("500x460")
        try:
            self.attributes("-topmost", True)
        except Exception:
            pass
        self._get_osc_vals = get_osc_vals
        self._get_indicators = get_indicators
        self._osc_in = osc_in
        self._ind_labels: dict = {}
        self._clock_lbl: Optional[tk.Label] = None
        self._axis_lbls: List[tk.Label] = []
        self._world_lbl: Optional[tk.Label] = None
        self._data_frame: Optional[tk.Frame] = None
        self._world_panel: Optional[tk.Frame] = None
        self._build_ui()
        self.bind("<Configure>", self._on_resize)
        self._update()

    def _build_ui(self):
        outer = tk.Frame(self, bg=_C["bg"], padx=14, pady=12)
        outer.pack(fill="both", expand=True)

        # ── Top row: indicators (left) + WORLD (right) ───────────────────────
        top = tk.Frame(outer, bg=_C["bg"])
        top.pack(fill="x", pady=(0, 10))

        # Status indicators panel — 2-column × 3-row grid
        ind_panel = tk.Frame(top, bg=_C["bg_disp"], padx=10, pady=10)
        ind_panel.pack(side="left", fill="y", padx=(0, 10))

        for row_idx, (i0, i1) in enumerate([(0, 1), (2, 3), (4, 5)]):
            for col_idx, ind_idx in enumerate([i0, i1]):
                name, key = _INDICATORS[ind_idx]
                cell = tk.Frame(ind_panel, bg=_C["bg_disp"])
                cell.grid(row=row_idx, column=col_idx, sticky="w",
                          padx=8, pady=3)
                sq = tk.Label(cell, text="", bg=_C["ind_off"],
                              width=2, height=1, relief="flat")
                sq.pack(side="left")
                self._ind_labels[key] = sq
                tk.Label(cell, text=name, bg=_C["bg_disp"], fg=_C["fg_dim"],
                         font=("Courier", 9), width=9, anchor="w").pack(
                    side="left", padx=(4, 0))

        # WORLD panel
        self._world_panel = tk.Frame(top, bg=_C["bg_disp"], padx=14, pady=10)
        self._world_panel.pack(side="left", fill="both", expand=True)
        tk.Label(self._world_panel, text="WORLD", bg=_C["bg_disp"], fg=_C["fg_dim"],
                 font=("Helvetica", 9, "bold")).pack(anchor="n")
        self._world_lbl = tk.Label(self._world_panel, text="--",
                                   bg=_C["bg_disp"], fg=_C["fg"],
                                   font=(self._DISP_FONT, 40, "bold"), width=3)
        self._world_lbl.pack(expand=True)

        # ── Bottom: data panel (clock + axes) ────────────────────────────────
        self._data_frame = tk.Frame(outer, bg=_C["bg_disp"], padx=14, pady=10)
        self._data_frame.pack(fill="both", expand=True)
        self._data_frame.columnconfigure(2, weight=1)
        for r in (0, 2, 4, 6):
            self._data_frame.rowconfigure(r, weight=1)

        _row_names = ("CLOCK", "ROLL", "PITCH", "YAW")
        all_lbls = []
        for i, name in enumerate(_row_names):
            data_row = i * 2
            tk.Label(self._data_frame, text=name, bg=_C["bg_disp"], fg=_C["fg_dim"],
                     font=("Helvetica", 9, "bold"), anchor="w").grid(
                row=data_row, column=0, padx=(0, 6), sticky="nsw")
            tk.Label(self._data_frame, text="○", bg=_C["bg_disp"], fg=_C["fg_dim"],
                     font=("Courier", 14)).grid(
                row=data_row, column=1, padx=(0, 10), sticky="ns")
            lbl = tk.Label(self._data_frame,
                           text="--:--:--" if i == 0 else "+00000",
                           bg=_C["bg_disp"], fg=_C["fg"],
                           font=(self._DISP_FONT, 28, "bold"), anchor="w")
            lbl.grid(row=data_row, column=2, sticky="nsew")
            all_lbls.append(lbl)
            if i < 3:
                tk.Frame(self._data_frame, bg=_C["fg_dim"], height=1).grid(
                    row=data_row + 1, column=0, columnspan=3, sticky="ew", pady=2)

        self._clock_lbl = all_lbls[0]
        self._axis_lbls = all_lbls[1:]

    def _on_resize(self, event):
        if event.widget is not self:
            return
        self.update_idletasks()
        dh = self._data_frame.winfo_height()
        wh = self._world_panel.winfo_height()
        # 4 data rows share height minus label row (≈15px) and 3 separators (≈9px each)
        row_h = max(1, (dh - 40) // 4)
        data_size = max(10, int(row_h * 0.62))
        world_size = max(10, int((wh - 30) * 0.55))
        df = (self._DISP_FONT, data_size, "bold")
        self._clock_lbl.config(font=df)
        for lbl in self._axis_lbls:
            lbl.config(font=df)
        self._world_lbl.config(font=(self._DISP_FONT, world_size, "bold"))

    def _update(self):
        if not self.winfo_exists():
            return
        # Clock
        self._clock_lbl.config(text=datetime.datetime.now().strftime("%H:%M:%S"))
        # OSC output values
        osc_vals = self._get_osc_vals(3)
        for lbl, (_, v) in zip(self._axis_lbls, osc_vals):
            lbl.config(text=self._fmt_osc(v) if v is not None else "  --")
        # Indicator lights
        states = self._get_indicators()
        for key, sq in self._ind_labels.items():
            sq.config(bg=_C["ind_on"] if states.get(key, False) else _C["ind_off"])
        # World value
        wv = self._osc_in.world_value()
        self._world_lbl.config(text=f"{wv:02d}" if wv is not None else "--")
        self.after(self.POLL_MS, self._update)


class MapperApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("MIDI Joy")
        self.configure(bg=_C["bg"])
        _icon_path = Path(__file__).parent / "icon.png"
        if _icon_path.exists():
            try:
                _img = tk.PhotoImage(file=str(_icon_path))
                self.iconphoto(True, _img)
                self._icon_img = _img
            except Exception:
                pass
        self.resizable(True, True)
        self.minsize(560, 500)
        self.geometry("700x760")

        pygame.init()
        pygame.joystick.init()

        self._engine = MidiEngine()
        self._mappings: List[MappingEntry] = []
        self._autopilot_config = AutopilotConfig()
        self._joystick: Optional[pygame.joystick.JoystickType] = None
        self._kb_joystick = KeyboardJoystick()
        self._running = False
        self._log_open = False
        self._ap_open = False
        self._ap_axis_vars: List[tk.BooleanVar] = []
        self._axis_cal: dict = {}
        self._axis_cal_vars: dict = {}

        self._osc_in = OscInputServer(port=9001)
        self._osc_in.start()
        self._engine._osc_in_ref = self._osc_in
        self._dsky_win: Optional[DskyWindow] = None
        self._pl_win = None

        # DSKY display state
        self._ind: dict = {}           # key → tk.Label (indicator lights)
        self._r_bars: List[tk.Label] = []
        self._r_vals: List[tk.Label] = []
        self._r_names: List[tk.Label] = []
        self._r_ap: list = []
        self._r_cal: list = []
        self._r_set0: list = []
        self._btn_labels: List[tk.Label] = []

        self._build_ui()
        self._refresh_controllers()
        self._refresh_midi_ports()
        self._load_default_config()
        self._poll_joystick()
        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self.bind_all("<KeyPress>",   self._on_key_press)
        self.bind_all("<KeyRelease>", self._on_key_release)

    # -----------------------------------------------------------------------
    # UI construction
    # -----------------------------------------------------------------------

    def _setup_styles(self):
        st = ttk.Style()
        try:
            st.theme_use("alt")
        except Exception:
            pass
        st.configure("DSKY.TCombobox",
                     fieldbackground=_C["bg_disp"], background=_C["btn_bg"],
                     foreground=_C["fg"], selectbackground=_C["sel_bg"],
                     selectforeground=_C["fg"])
        st.map("DSKY.TCombobox",
               fieldbackground=[("readonly", _C["bg_disp"])],
               selectbackground=[("readonly", _C["sel_bg"])],
               selectforeground=[("readonly", _C["fg"])])
        # TScrollbar custom style omitted — use tk.Scrollbar directly instead

    def _build_ui(self):
        self._setup_styles()

        # ── Top section: displays (full width) ───────────────────────────────
        right_frame = tk.Frame(self, bg=_C["bg"])
        right_frame.pack(fill="x", padx=8, pady=(8, 4))

        # Prog row: indicator lights (left) + PROG version (right)
        prog_row = tk.Frame(right_frame, bg=_C["bg"])
        prog_row.pack(fill="x", pady=(0, 6))

        # Indicator lights — compact 2-column grid on the left of prog row
        ind_frame = tk.Frame(prog_row, bg=_C["bg"])
        ind_frame.pack(side="left", padx=(0, 12))
        for row_idx, (i0, i1) in enumerate([(0, 1), (2, 3), (4, 5)]):
            for col_idx, ind_idx in enumerate([i0, i1]):
                name, key = _INDICATORS[ind_idx]
                cell = tk.Frame(ind_frame, bg=_C["bg"], padx=2, pady=1)
                cell.grid(row=row_idx, column=col_idx, padx=4, pady=1, sticky="w")
                state_lbl = tk.Label(cell, text="", bg=_C["ind_off"],
                                     width=2, height=1, relief="flat")
                state_lbl.pack(side="left")
                self._ind[key] = state_lbl
                tk.Label(cell, text=name, bg=_C["bg"], fg=_C["fg_dim"],
                         font=("Courier", 9), width=9, anchor="w").pack(side="left", padx=(3, 0))

        # PROG version display — right side of prog row
        tk.Label(prog_row, text="PROG", bg=_C["bg"], fg=_C["fg_dim"],
                 font=("Helvetica", 8)).pack(side="right", padx=(0, 4), anchor="s")
        tk.Label(prog_row, text=f"  {APP_VERSION}  ", bg=_C["bg_disp"], fg=_C["fg"],
                 font=("Courier", 18, "bold"), padx=6, pady=2).pack(side="right")

        # VERB / NOUN display boxes
        vn_row = tk.Frame(right_frame, bg=_C["bg"])
        vn_row.pack(fill="x", pady=(0, 4))

        verb_box = tk.Frame(vn_row, bg=_C["bg_disp"], padx=6, pady=4)
        verb_box.pack(side="left", fill="both", expand=True, padx=(0, 4))
        tk.Label(verb_box, text="CONTROLLER", bg=_C["bg_disp"], fg=_C["fg_dim"],
                 font=("Helvetica", 8)).pack(anchor="w")
        ctrl_inner = tk.Frame(verb_box, bg=_C["bg_disp"])
        ctrl_inner.pack(fill="x")
        self._ctrl_var = tk.StringVar()
        self._ctrl_cb = ttk.Combobox(ctrl_inner, textvariable=self._ctrl_var,
                                     state="readonly", style="DSKY.TCombobox")
        self._ctrl_cb.pack(side="left", fill="x", expand=True)
        self._ctrl_cb.bind("<<ComboboxSelected>>", self._on_ctrl_select)
        tk.Button(ctrl_inner, text="↺", command=self._refresh_controllers,
                  bg=_C["bg_disp"], fg=_C["fg"], activebackground=_C["bg_disp"],
                  activeforeground=_C["fg"], relief="flat",
                  font=("Helvetica", 11), pady=0).pack(side="left", padx=(4, 0))

        noun_box = tk.Frame(vn_row, bg=_C["bg_disp"], padx=6, pady=4)
        noun_box.pack(side="left", fill="both", expand=True)
        tk.Label(noun_box, text="MIDI OUT", bg=_C["bg_disp"], fg=_C["fg_dim"],
                 font=("Helvetica", 8)).pack(anchor="w")
        midi_inner = tk.Frame(noun_box, bg=_C["bg_disp"])
        midi_inner.pack(fill="x")
        self._midi_var = tk.StringVar()
        self._midi_cb = ttk.Combobox(midi_inner, textvariable=self._midi_var,
                                     state="readonly", style="DSKY.TCombobox")
        self._midi_cb.pack(side="left", fill="x", expand=True)
        self._midi_cb.bind("<<ComboboxSelected>>", self._on_midi_select)
        tk.Button(midi_inner, text="↺", command=self._refresh_midi_ports,
                  bg=_C["bg_disp"], fg=_C["fg"], activebackground=_C["bg_disp"],
                  activeforeground=_C["fg"], relief="flat",
                  font=("Helvetica", 11), pady=0).pack(side="left", padx=(4, 0))

        # OSC row (compact)
        osc_row = tk.Frame(right_frame, bg=_C["bg"])
        osc_row.pack(fill="x", pady=(0, 4))
        tk.Label(osc_row, text="OSC", bg=_C["bg"], fg=_C["fg_dim"],
                 font=("Courier", 9), width=4, anchor="e").pack(side="left")
        self._osc_host_var = tk.StringVar(value="127.0.0.1")
        tk.Entry(osc_row, textvariable=self._osc_host_var, width=14,
                 bg=_C["bg_disp"], fg=_C["fg"], insertbackground=_C["fg"],
                 relief="flat", font=("Courier", 10)).pack(side="left", padx=(4, 0))
        tk.Label(osc_row, text=":", bg=_C["bg"], fg=_C["fg"],
                 font=("Courier", 11)).pack(side="left", padx=2)
        self._osc_port_var = tk.StringVar(value="9000")
        tk.Spinbox(osc_row, from_=1, to=65535, textvariable=self._osc_port_var,
                   width=6, bg=_C["bg_disp"], fg=_C["fg"],
                   buttonbackground=_C["btn_bg"], relief="flat",
                   font=("Courier", 10)).pack(side="left")
        self._osc_enabled_var = tk.BooleanVar(value=False)
        tk.Checkbutton(osc_row, text="ON", variable=self._osc_enabled_var,
                       command=self._on_osc_change,
                       bg=_C["bg"], fg=_C["fg_dim"], selectcolor=_C["bg_disp"],
                       activebackground=_C["bg"], activeforeground=_C["fg"],
                       font=("Helvetica", 9, "bold")).pack(side="left", padx=6)
        self._osc_host_var.trace_add("write", lambda *_: self._on_osc_change())
        self._osc_port_var.trace_add("write", lambda *_: self._on_osc_change())

        # R-registers (axis readouts)
        self._r_frame = tk.Frame(right_frame, bg=_C["bg_disp"], padx=2, pady=2)
        self._r_frame.pack(fill="x", pady=(0, 2))

        # Button state dots (below R-registers)
        self._btn_dots_frame = tk.Frame(right_frame, bg=_C["bg"])
        self._btn_dots_frame.pack(fill="x")

        # ── Autopilot (collapsible) ───────────────────────────────────────────
        self._build_autopilot_panel()

        # ── Mappings list ─────────────────────────────────────────────────────
        map_outer = tk.Frame(self, bg=_C["bg"])
        map_outer.pack(fill="both", expand=True, padx=8, pady=4)

        map_header = tk.Frame(map_outer, bg=_C["bg"])
        map_header.pack(fill="x")
        tk.Label(map_header, text="MAPPINGS", bg=_C["bg"], fg=_C["fg_dim"],
                 font=("Helvetica", 9, "bold")).pack(side="left", padx=4, pady=(2, 1))

        list_frame = tk.Frame(map_outer, bg=_C["bg"])
        list_frame.pack(fill="both", expand=True)

        scrollbar = tk.Scrollbar(list_frame, orient="vertical",
                                bg=_C["btn_bg"], troughcolor=_C["bg"],
                                activebackground=_C["fg"])
        self._listbox = tk.Listbox(list_frame, yscrollcommand=scrollbar.set,
                                   font=("Courier", 12), activestyle="none",
                                   bg=_C["bg_disp"], fg=_C["fg"],
                                   selectbackground=_C["sel_bg"],
                                   selectforeground=_C["fg"],
                                   bd=0, highlightthickness=0)
        scrollbar.config(command=self._listbox.yview)
        self._listbox.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        self._listbox.bind("<Double-Button-1>", lambda _: self._edit_mapping())

        # ── MIDI Activity log (collapsible) ───────────────────────────────────
        self._build_activity_log()

        # ── DSKY keyboard ─────────────────────────────────────────────────────
        self._build_dsky_keyboard()

    def _build_autopilot_panel(self):
        outer = tk.Frame(self, bg=_C["bg"])
        outer.pack(fill="x", padx=8, pady=(0, 2))

        header = tk.Frame(outer, bg=_C["bg"])
        header.pack(fill="x")
        self._ap_toggle_btn = tk.Button(
            header, text="▸ AUTOPILOT", anchor="w",
            relief="flat", font=("Helvetica", 10, "bold"),
            bg=_C["bg"], fg=_C["fg_dim"],
            activebackground=_C["bg"], activeforeground=_C["fg"],
            command=self._toggle_ap)
        self._ap_toggle_btn.pack(side="left", fill="x", expand=True)
        self._ap_enabled_var = tk.BooleanVar(value=False)
        tk.Checkbutton(header, text="ENABLED", variable=self._ap_enabled_var,
                       command=self._push_autopilot,
                       bg=_C["bg"], fg=_C["fg_dim"], selectcolor=_C["bg_disp"],
                       activebackground=_C["bg"], activeforeground=_C["fg"],
                       font=("Helvetica", 9)).pack(side="right", padx=6)

        self._ap_content = tk.Frame(outer, bg=_C["bg"])

        row0 = tk.Frame(self._ap_content, bg=_C["bg"])
        row0.pack(fill="x", padx=4, pady=(4, 2))
        tk.Label(row0, text="Inactivity timeout:", bg=_C["bg"], fg=_C["fg"],
                 font=("Helvetica", 10)).pack(side="left")
        self._ap_timeout_var = tk.DoubleVar(value=30.0)
        tk.Spinbox(row0, from_=5, to=300, increment=5,
                   textvariable=self._ap_timeout_var, width=6,
                   bg=_C["bg_disp"], fg=_C["fg"], buttonbackground=_C["btn_bg"],
                   relief="flat", font=("Courier", 11),
                   command=self._push_autopilot).pack(side="left", padx=4)
        tk.Label(row0, text="sec", bg=_C["bg"], fg=_C["fg_dim"]).pack(side="left")

        row2 = tk.Frame(self._ap_content, bg=_C["bg"])
        row2.pack(fill="x", padx=4, pady=(2, 4))

        tk.Label(row2, text="Drift:", bg=_C["bg"], fg=_C["fg"]).grid(
            row=0, column=0, sticky="e", padx=(0, 4))
        self._ap_drift_var = tk.DoubleVar(value=0.3)
        self._ap_drift_lbl = tk.Label(row2, text="0.30", width=5, anchor="w",
                                      bg=_C["bg"], fg=_C["fg"])
        tk.Scale(row2, from_=0.0, to=1.0, resolution=0.05, orient="horizontal",
                 variable=self._ap_drift_var, showvalue=False, length=120,
                 bg=_C["bg"], fg=_C["fg"], troughcolor=_C["bg_disp"],
                 highlightbackground=_C["bg"], activebackground=_C["fg"],
                 command=lambda _: [self._ap_drift_lbl.config(
                     text=f"{self._ap_drift_var.get():.2f}"), self._push_autopilot()]
                 ).grid(row=0, column=1, padx=2)
        self._ap_drift_lbl.grid(row=0, column=2, sticky="w")

        tk.Label(row2, text="Speed:", bg=_C["bg"], fg=_C["fg"]).grid(
            row=0, column=3, sticky="e", padx=(12, 4))
        self._ap_speed_var = tk.DoubleVar(value=0.3)
        self._ap_speed_lbl = tk.Label(row2, text="0.30", width=5, anchor="w",
                                      bg=_C["bg"], fg=_C["fg"])
        tk.Scale(row2, from_=0.0, to=1.0, resolution=0.05, orient="horizontal",
                 variable=self._ap_speed_var, showvalue=False, length=120,
                 bg=_C["bg"], fg=_C["fg"], troughcolor=_C["bg_disp"],
                 highlightbackground=_C["bg"], activebackground=_C["fg"],
                 command=lambda _: [self._ap_speed_lbl.config(
                     text=f"{self._ap_speed_var.get():.2f}"), self._push_autopilot()]
                 ).grid(row=0, column=4, padx=2)
        self._ap_speed_lbl.grid(row=0, column=5, sticky="w")

    def _build_activity_log(self):
        outer = tk.Frame(self, bg=_C["bg"])
        outer.pack(fill="x", padx=8, pady=(0, 2))

        header = tk.Frame(outer, bg=_C["bg"])
        header.pack(fill="x")
        self._log_toggle_btn = tk.Button(
            header, text="▸ MIDI ACTIVITY", anchor="w",
            relief="flat", font=("Helvetica", 10, "bold"),
            bg=_C["bg"], fg=_C["fg_dim"],
            activebackground=_C["bg"], activeforeground=_C["fg"],
            command=self._toggle_log)
        self._log_toggle_btn.pack(side="left", fill="x", expand=True)
        tk.Button(header, text="CLEAR", command=self._clear_log,
                  bg=_C["btn_bg"], fg=_C["fg"],
                  activebackground="#2a2a2a", activeforeground=_C["fg"],
                  relief="flat", font=("Helvetica", 9)).pack(side="right", padx=4)

        self._log_content = tk.Frame(outer, bg=_C["bg"])
        log_scroll = tk.Scrollbar(self._log_content, orient="vertical",
                                  bg=_C["btn_bg"], troughcolor=_C["bg"],
                                  activebackground=_C["fg"])
        self._log_listbox = tk.Listbox(
            self._log_content, height=6,
            yscrollcommand=log_scroll.set,
            font=("Courier", 10), activestyle="none",
            bg=_C["bg_disp"], fg=_C["fg"],
            selectbackground=_C["sel_bg"], selectforeground=_C["fg"],
            bd=0, highlightthickness=0)
        log_scroll.config(command=self._log_listbox.yview)
        self._log_listbox.pack(side="left", fill="both", expand=True)
        log_scroll.pack(side="right", fill="y")

    def _build_dsky_keyboard(self):
        kf = tk.Frame(self, bg=_C["bg"], pady=4)
        kf.pack(fill="x", padx=8, pady=(4, 8))
        for col in range(7):
            kf.columnconfigure(col, weight=1)

        def mk(text, row, col, rowspan=1, colspan=1, cmd=None, ipy=8,
               bg="#000000", fg="white"):
            # tk.Label inside a border Frame — Labels always respect bg on macOS
            border = tk.Frame(kf, bg="#777777")
            border.grid(row=row, column=col, rowspan=rowspan, columnspan=colspan,
                        sticky="nsew", padx=3, pady=3)
            lbl = tk.Label(border, text=text, bg=bg, fg=fg,
                           font=("Helvetica", 10, "bold"),
                           cursor="hand2", pady=ipy)
            lbl.pack(fill="both", expand=True, padx=2, pady=2)
            if cmd:
                def on_press(_, w=lbl):
                    w._saved_bg = w.cget("bg")
                    w.config(bg="#333333")
                def on_release(_, w=lbl, c=cmd):
                    w.config(bg=w._saved_bg)
                    c()
                lbl.bind("<Button-1>", on_press)
                lbl.bind("<ButtonRelease-1>", on_release)
            return lbl

        # Tall side buttons (left)
        mk("CTRL", 0, 0, rowspan=2, ipy=22,
           cmd=lambda: self._ctrl_cb.focus_set())
        mk("PORT", 2, 0, rowspan=2, ipy=22,
           cmd=lambda: self._midi_cb.focus_set())

        # Center row 0
        mk("ADD",  0, 1, cmd=self._add_mapping)
        mk("SAVE", 0, 2, cmd=self._save_config)
        mk("LOAD", 0, 3, cmd=self._load_config)
        mk("CLR",  0, 4, cmd=self._clear_log)
        mk("NEW",  0, 5, cmd=self._new_config)

        # Center row 1 — AGC + PLAYLIST
        mk("AGC", 1, 1, colspan=3, ipy=4,
           cmd=self._open_agc_window, bg="#001a00", fg=_C["fg"])
        mk("PLAYLIST", 1, 4, colspan=2, ipy=4,
           cmd=self._open_playlist_window, bg="#001a00", fg=_C["fg"])

        # Center row 2
        mk("EDIT", 2, 1, cmd=self._edit_mapping)
        mk("DEL",  2, 2, cmd=self._delete_mapping)
        mk("PAUS", 2, 3, cmd=self._toggle_mapping_enabled)
        mk("AUTO", 2, 4, cmd=self._toggle_autopilot)
        mk("OSC",  2, 5, cmd=self._open_osc_dialog)

        # Tall side buttons (right)
        self._start_btn = mk("START", 0, 6, rowspan=2, ipy=22,
                              cmd=self._toggle_running,
                              bg="#003300", fg="white")
        mk("RSET", 2, 6, rowspan=2, ipy=22, cmd=self._new_config)

    def _toggle_ap(self):
        if self._ap_open:
            self._ap_content.pack_forget()
            self._ap_toggle_btn.config(text="▸ AUTOPILOT")
        else:
            self._ap_content.pack(fill="x")
            self._ap_toggle_btn.config(text="▾ AUTOPILOT")
        self._ap_open = not self._ap_open

    def _push_autopilot(self):
        axes = [i for i, v in enumerate(self._ap_axis_vars) if v.get()]
        self._autopilot_config = AutopilotConfig(
            enabled=self._ap_enabled_var.get(),
            inactivity_seconds=self._ap_timeout_var.get(),
            axes=axes,
            drift=round(self._ap_drift_var.get(), 4),
            speed=round(self._ap_speed_var.get(), 4),
        )
        self._engine.set_autopilot(self._autopilot_config)

    def _toggle_autopilot(self):
        new_val = not self._ap_enabled_var.get()
        self._ap_enabled_var.set(new_val)
        self._push_autopilot()

    def _toggle_log(self):
        if self._log_open:
            self._log_content.pack_forget()
            self._log_toggle_btn.config(text="▸ MIDI ACTIVITY")
        else:
            self._log_content.pack(fill="x")
            self._log_toggle_btn.config(text="▾ MIDI ACTIVITY")
        self._log_open = not self._log_open

    def _clear_log(self):
        self._log_listbox.delete(0, tk.END)

    def _on_osc_change(self):
        if not HAS_OSC and self._osc_enabled_var.get():
            messagebox.showwarning("OSC unavailable",
                                   "python-osc is not installed.\n"
                                   "Run: pip install python-osc", parent=self)
            self._osc_enabled_var.set(False)
            return
        try:
            port = int(self._osc_port_var.get())
        except (ValueError, tk.TclError):
            return
        self._engine.set_osc(OscConfig(
            enabled=self._osc_enabled_var.get(),
            host=self._osc_host_var.get().strip(),
            port=port,
        ))

    def _open_osc_dialog(self):
        dlg = tk.Toplevel(self)
        dlg.title("OSC Settings")
        dlg.configure(bg=_C["bg"])
        dlg.resizable(False, False)
        dlg.grab_set()

        lkw = dict(bg=_C["bg"], fg=_C["fg"])
        ekw = dict(bg=_C["bg_disp"], fg=_C["fg"], insertbackground=_C["fg"],
                   relief="flat", font=("Courier", 11))
        skw = dict(bg=_C["bg_disp"], fg=_C["fg"], buttonbackground=_C["btn_bg"],
                   relief="flat", font=("Courier", 11))
        bkw = dict(bg=_C["btn_bg"], fg=_C["fg"],
                   activebackground="#2a2a2a", activeforeground=_C["fg"],
                   relief="raised", bd=2)
        pad = {"padx": 14, "pady": 6}

        tk.Label(dlg, text="OSC OUTPUT", font=("Helvetica", 13, "bold"), **lkw).grid(
            row=0, column=0, columnspan=2, pady=(12, 8))
        tk.Label(dlg, text="Host:", **lkw).grid(row=1, column=0, sticky="e", **pad)
        tk.Entry(dlg, textvariable=self._osc_host_var, width=18, **ekw).grid(
            row=1, column=1, sticky="w", **pad)
        tk.Label(dlg, text="Port:", **lkw).grid(row=2, column=0, sticky="e", **pad)
        tk.Spinbox(dlg, from_=1, to=65535, textvariable=self._osc_port_var,
                   width=8, **skw).grid(row=2, column=1, sticky="w", **pad)
        tk.Label(dlg, text="Enabled:", **lkw).grid(row=3, column=0, sticky="e", **pad)
        tk.Checkbutton(dlg, variable=self._osc_enabled_var, command=self._on_osc_change,
                       bg=_C["bg"], fg=_C["fg"], selectcolor=_C["bg_disp"],
                       activebackground=_C["bg"], activeforeground=_C["fg"]).grid(
            row=3, column=1, sticky="w", **pad)
        tk.Button(dlg, text="Close", command=dlg.destroy, width=8, **bkw).grid(
            row=4, column=0, columnspan=2, pady=12)

    # -----------------------------------------------------------------------
    # Device management
    # -----------------------------------------------------------------------

    def _refresh_controllers(self):
        pygame.joystick.quit()
        pygame.joystick.init()
        count = pygame.joystick.get_count()
        names = [pygame.joystick.Joystick(i).get_name() for i in range(count)]
        names.append(KeyboardJoystick.NAME)
        self._ctrl_cb["values"] = names
        if names:
            self._ctrl_cb.current(0)
            self._on_ctrl_select()
        else:
            self._ctrl_var.set("")
            self._joystick = None
            self._rebuild_live_panel()

    def _on_ctrl_select(self, *_):
        idx = self._ctrl_cb.current()
        if idx < 0:
            return
        hw_count = pygame.joystick.get_count()
        if idx >= hw_count:
            self._joystick = self._kb_joystick
        else:
            self._joystick = pygame.joystick.Joystick(idx)
            self._joystick.init()
        self._engine.set_joystick(self._joystick)
        self._rebuild_live_panel()

    def _refresh_midi_ports(self):
        ports = self._engine.get_midi_ports()
        self._midi_cb["values"] = ports
        if ports:
            self._midi_cb.current(0)
            self._on_midi_select()
        else:
            self._midi_var.set("")

    def _on_midi_select(self, *_):
        idx = self._midi_cb.current()
        if idx >= 0:
            self._engine.open_port(idx)

    # -----------------------------------------------------------------------
    # Live input / R-register panel
    # -----------------------------------------------------------------------

    def _rebuild_live_panel(self):
        for w in self._r_frame.winfo_children():
            w.destroy()
        for w in self._btn_dots_frame.winfo_children():
            w.destroy()
        self._r_bars = []
        self._r_vals = []
        self._r_names = []
        self._r_ap = []
        self._r_cal = []
        self._r_set0 = []
        self._btn_labels = []

        checked = {i for i, v in enumerate(self._ap_axis_vars) if v.get()}
        self._ap_axis_vars = []

        if self._joystick is None:
            tk.Label(self._r_frame, text="No controller",
                     bg=_C["bg_disp"], fg=_C["fg_dim"],
                     font=("Courier", 11)).pack(pady=8)
            return

        js = self._joystick
        n_axes = js.get_numaxes()
        n_buttons = js.get_numbuttons()

        btn_s = dict(bg=_C["btn_bg"], fg=_C["fg"],
                     activebackground="#2a2a2a", activeforeground=_C["fg"],
                     relief="flat", font=("Helvetica", 8), pady=0, padx=2)
        chk_s = dict(bg=_C["bg_disp"], fg=_C["fg"],
                     selectcolor=_C["bg"], activebackground=_C["bg_disp"],
                     activeforeground=_C["fg"], font=("Helvetica", 8))

        for i in range(n_axes):
            row = tk.Frame(self._r_frame, bg=_C["bg_disp"])
            row.pack(fill="x", pady=1)

            tk.Label(row, text=f"R{i+1}", bg=_C["bg_disp"], fg=_C["fg_dim"],
                     font=("Courier", 10, "bold"), width=3).pack(side="left", padx=(4, 0))

            bar_lbl = tk.Label(row, text=self._axis_bar(0.0),
                               bg=_C["bg_disp"], fg=_C["fg"],
                               font=("Courier", 10), anchor="w")
            bar_lbl.pack(side="left", fill="x", expand=True)
            self._r_bars.append(bar_lbl)

            val_lbl = tk.Label(row, text="+00064", bg=_C["bg_disp"], fg=_C["fg"],
                               font=("Courier", 13, "bold"), width=7)
            val_lbl.pack(side="left", padx=4)
            self._r_vals.append(val_lbl)

            name_lbl = tk.Label(row, text="", bg=_C["bg_disp"], fg=_C["fg_dim"],
                                font=("Courier", 10), width=8, anchor="w")
            name_lbl.pack(side="left", padx=(0, 4))
            self._r_names.append(name_lbl)

            # SET0 button
            set0 = tk.Button(row, text="SET0",
                             command=lambda idx=i: self._set_axis_zero(idx), **btn_s)
            set0.pack(side="right", padx=(2, 4))
            self._r_set0.append(set0)

            # CAL toggle
            cal_enabled = self._axis_cal.get(i, {}).get("enabled", False)
            cal_var = tk.BooleanVar(value=cal_enabled)
            self._axis_cal_vars[i] = cal_var
            cal_chk = tk.Checkbutton(row, text="CAL", variable=cal_var,
                                     command=lambda idx=i: self._on_cal_toggle(idx),
                                     **chk_s)
            cal_chk.pack(side="right", padx=(0, 2))
            self._r_cal.append(cal_chk)

            # AP toggle
            ap_var = tk.BooleanVar(value=(i in checked))
            self._ap_axis_vars.append(ap_var)
            ap_chk = tk.Checkbutton(row, text="AP", variable=ap_var,
                                    command=self._push_autopilot, **chk_s)
            ap_chk.pack(side="right", padx=(0, 2))
            self._r_ap.append(ap_chk)

        # Button dots grid
        if n_buttons > 0:
            btn_outer = tk.Frame(self._btn_dots_frame, bg=_C["bg"])
            btn_outer.pack(fill="x", padx=4, pady=(4, 2))
            for i in range(n_buttons):
                cell = tk.Frame(btn_outer, bg=_C["btn_bg"], bd=1, relief="groove",
                                width=44, height=36)
                cell.grid(row=i // BTN_COLS, column=i % BTN_COLS,
                          padx=2, pady=2, sticky="nsew")
                cell.pack_propagate(False)
                tk.Label(cell, text=f"B{i}", font=("Helvetica", 8),
                         fg=_C["fg_dim"], bg=_C["btn_bg"]).pack()
                lbl = tk.Label(cell, text="○", font=("Helvetica", 14),
                               fg=_C["fg_dim"], bg=_C["btn_bg"])
                lbl.pack()
                self._btn_labels.append(lbl)

        # Keyboard legend when keyboard joystick is active
        if isinstance(js, KeyboardJoystick):
            tk.Label(self._btn_dots_frame, text=js.LEGEND,
                     bg=_C["bg"], fg=_C["fg_dim"],
                     font=("Courier", 9), justify="left", anchor="w").pack(
                fill="x", padx=8, pady=(4, 2))

    def _axis_bar(self, value: float) -> str:
        filled = max(0, min(MAX_BARS, int((value + 1.0) / 2.0 * MAX_BARS)))
        return f"[{'█' * filled}{'░' * (MAX_BARS - filled)}] {value:+.2f}"

    def _update_r_regs(self):
        js = self._joystick
        if js is None:
            return
        n = js.get_numaxes()
        if len(self._r_bars) != n:
            self._rebuild_live_panel()
            return

        # Map axis index → first matching mapping's display name
        axis_names: dict = {}
        for m in self._mappings:
            if m.source_type == "axis" and m.source_index not in axis_names:
                axis_names[m.source_index] = (m.name or m.source).strip()

        for i in range(n):
            val = js.get_axis(i)
            self._r_bars[i].config(text=self._axis_bar(val))
            cc = round((val + 1.0) / 2.0 * 127)
            self._r_vals[i].config(text=f"+{cc:05d}")
            raw_name = axis_names.get(i, "")
            self._r_names[i].config(text=raw_name[:8])

        for i, lbl in enumerate(self._btn_labels):
            if i < js.get_numbuttons():
                pressed = js.get_button(i)
                lbl.config(text="●" if pressed else "○",
                           fg=_C["fg"] if pressed else _C["fg_dim"])

    def _update_indicators(self):
        def lit(key: str, on: bool):
            lbl = self._ind.get(key)
            if lbl:
                lbl.configure(bg=_C["ind_on"] if on else _C["ind_off"])

        lit("midi", self._running)
        lit("osc", self._osc_enabled_var.get())
        lit("auto", self._running and self._engine.autopilot_active)
        lit("ctrl", self._joystick is not None)
        lit("cal", any(v.get("enabled") for v in self._axis_cal.values()))
        lit("key", isinstance(self._joystick, KeyboardJoystick))

    def _poll_joystick(self):
        pygame.event.pump()

        if isinstance(self._joystick, KeyboardJoystick):
            self._joystick.update()

        if self._joystick:
            self._update_r_regs()

        # Update START button color based on running / autopilot state
        if self._running:
            if self._engine.autopilot_active:
                self._start_btn.config(bg="#440055", fg="white")
            else:
                self._start_btn.config(bg="#3a0a0a")

        self._update_indicators()

        # Drain MIDI activity queue and append to log
        try:
            while True:
                entry = self._engine.activity_queue.get_nowait()
                self._log_listbox.insert(tk.END, "  " + entry)
                if self._log_listbox.size() > MAX_LOG_ENTRIES:
                    self._log_listbox.delete(0)
                self._log_listbox.see(tk.END)
        except queue.Empty:
            pass

        self.after(POLL_INTERVAL_MS, self._poll_joystick)

    # -----------------------------------------------------------------------
    # Axis center calibration
    # -----------------------------------------------------------------------

    def _set_axis_zero(self, axis_idx: int):
        if self._joystick is None:
            return
        offset = self._joystick.get_axis(axis_idx)
        self._axis_cal.setdefault(axis_idx, {"offset": 0.0, "enabled": False})
        self._axis_cal[axis_idx]["offset"] = offset
        self._axis_cal[axis_idx]["enabled"] = True
        if axis_idx in self._axis_cal_vars:
            self._axis_cal_vars[axis_idx].set(True)
        self._push_axis_cal()

    def _on_cal_toggle(self, axis_idx: int):
        enabled = self._axis_cal_vars[axis_idx].get()
        self._axis_cal.setdefault(axis_idx, {"offset": 0.0, "enabled": False})
        self._axis_cal[axis_idx]["enabled"] = enabled
        self._push_axis_cal()

    def _push_axis_cal(self):
        self._engine.set_axis_cal(self._axis_cal)

    # -----------------------------------------------------------------------
    # Keyboard controller event forwarding
    # -----------------------------------------------------------------------

    def _on_key_press(self, event):
        if isinstance(self._joystick, KeyboardJoystick):
            if not isinstance(event.widget, (tk.Entry, tk.Spinbox)):
                self._kb_joystick.press(event.keysym)

    def _on_key_release(self, event):
        if isinstance(self._joystick, KeyboardJoystick):
            self._kb_joystick.release(event.keysym)

    # -----------------------------------------------------------------------
    # Mapping CRUD
    # -----------------------------------------------------------------------

    def _refresh_listbox(self):
        self._listbox.delete(0, tk.END)
        for i, m in enumerate(self._mappings):
            self._listbox.insert(tk.END, "  " + m.label())
            if not m.enabled:
                self._listbox.itemconfig(i, fg=_C["fg_dim"])

    def _add_mapping(self):
        dlg = MappingDialog(self, self._joystick)
        self.wait_window(dlg)
        if dlg.result:
            self._mappings.append(dlg.result)
            self._push_mappings()
            self._refresh_listbox()
            self._autosave()

    def _edit_mapping(self):
        sel = self._listbox.curselection()
        if not sel:
            messagebox.showinfo("Edit", "Select a mapping to edit.", parent=self)
            return
        idx = sel[0]
        dlg = MappingDialog(self, self._joystick, self._mappings[idx])
        self.wait_window(dlg)
        if dlg.result:
            self._mappings[idx] = dlg.result
            self._push_mappings()
            self._refresh_listbox()
            self._autosave()

    def _delete_mapping(self):
        sel = self._listbox.curselection()
        if not sel:
            messagebox.showinfo("Delete", "Select a mapping to delete.", parent=self)
            return
        idx = sel[0]
        self._mappings.pop(idx)
        self._push_mappings()
        self._refresh_listbox()
        self._autosave()

    def _toggle_mapping_enabled(self):
        sel = self._listbox.curselection()
        if not sel:
            messagebox.showinfo("Pause", "Select a mapping to pause/resume.", parent=self)
            return
        idx = sel[0]
        m = self._mappings[idx]
        self._mappings[idx] = MappingEntry(**{**asdict(m), "enabled": not m.enabled})
        self._push_mappings()
        self._refresh_listbox()
        self._listbox.selection_set(idx)
        self._autosave()

    def _push_mappings(self):
        self._engine.set_mappings(self._mappings)

    # -----------------------------------------------------------------------
    # Start / Stop
    # -----------------------------------------------------------------------

    def _toggle_running(self):
        if self._running:
            self._engine.stop()
            self._running = False
            self._start_btn.config(text="START", bg="#003300", fg="white")
        else:
            if not self._joystick:
                messagebox.showwarning("No controller", "Connect a controller first.", parent=self)
                return
            if not self._midi_cb.get():
                messagebox.showwarning("No MIDI port", "Select a MIDI output port first.", parent=self)
                return
            self._push_mappings()
            self._push_autopilot()
            self._engine.start()
            self._running = True
            self._start_btn.config(text="STOP", bg="#550000", fg="white")

    # -----------------------------------------------------------------------
    # Config
    # -----------------------------------------------------------------------

    def _new_config(self):
        if not messagebox.askyesno("New Config",
                                   "Clear all mappings and start fresh?",
                                   parent=self):
            return
        self._mappings = []
        self._push_mappings()
        self._refresh_listbox()
        self._autosave()

    def _autosave(self):
        try:
            self._write_config(DEFAULT_CONFIG)
        except Exception:
            pass

    def _save_config(self):
        path = filedialog.asksaveasfilename(
            defaultextension=".json",
            filetypes=[("JSON files", "*.json"), ("All files", "*.*")],
            initialfile="mappings.json", parent=self)
        if path:
            self._write_config(path)

    def _load_config(self):
        path = filedialog.askopenfilename(
            filetypes=[("JSON files", "*.json"), ("All files", "*.*")], parent=self)
        if path:
            self._read_config(path)

    def _load_default_config(self):
        if os.path.exists(DEFAULT_CONFIG):
            self._read_config(DEFAULT_CONFIG)

    def _write_config(self, path: str):
        axis_cal_json = {str(k): v for k, v in self._axis_cal.items()}
        try:
            osc_port = int(self._osc_port_var.get())
        except (ValueError, tk.TclError):
            osc_port = 9000
        with open(path, "w") as f:
            json.dump({
                "mappings": [asdict(m) for m in self._mappings],
                "autopilot": asdict(self._autopilot_config),
                "axis_cal": axis_cal_json,
                "osc": asdict(OscConfig(
                    enabled=self._osc_enabled_var.get(),
                    host=self._osc_host_var.get().strip(),
                    port=osc_port,
                )),
                "playlist": asdict(self._engine._playlist),
            }, f, indent=2)

    def _read_config(self, path: str):
        try:
            with open(path) as f:
                data = json.load(f)
            if isinstance(data, list):
                mappings_data, autopilot_data = data, {}
            else:
                mappings_data = data.get("mappings", [])
                autopilot_data = data.get("autopilot", {})
            self._mappings = [MappingEntry(**d) for d in mappings_data]
            valid_ap_keys = AutopilotConfig.__dataclass_fields__
            self._autopilot_config = AutopilotConfig(
                **{k: v for k, v in autopilot_data.items() if k in valid_ap_keys})
            raw_cal = data.get("axis_cal", {}) if isinstance(data, dict) else {}
            self._axis_cal = {int(k): v for k, v in raw_cal.items()}
            osc_data = data.get("osc", {}) if isinstance(data, dict) else {}
            valid_osc = OscConfig.__dataclass_fields__
            osc = OscConfig(**{k: v for k, v in osc_data.items() if k in valid_osc})
            self._osc_host_var.set(osc.host)
            self._osc_port_var.set(str(osc.port))
            self._osc_enabled_var.set(osc.enabled)
            pl_data = data.get("playlist", {}) if isinstance(data, dict) else {}
            valid_pl = PlaylistConfig.__dataclass_fields__
            pl_cfg = PlaylistConfig(**{k: v for k, v in pl_data.items() if k in valid_pl})
            self._engine.set_playlist(pl_cfg)
            if pl_cfg.position >= 0:
                self._osc_in.set_world(self._engine._pl_order[pl_cfg.position])
            self._ap_enabled_var.set(self._autopilot_config.enabled)
            self._ap_timeout_var.set(self._autopilot_config.inactivity_seconds)
            self._ap_drift_var.set(self._autopilot_config.drift)
            self._ap_drift_lbl.config(text=f"{self._autopilot_config.drift:.2f}")
            self._ap_speed_var.set(self._autopilot_config.speed)
            self._ap_speed_lbl.config(text=f"{self._autopilot_config.speed:.2f}")
            for i, var in enumerate(self._ap_axis_vars):
                var.set(i in self._autopilot_config.axes)
            self._push_mappings()
            self._push_autopilot()
            self._push_axis_cal()
            self._on_osc_change()
            self._refresh_listbox()
        except Exception as e:
            messagebox.showerror("Load error", str(e), parent=self)

    # -----------------------------------------------------------------------
    # AGC window
    # -----------------------------------------------------------------------

    def _get_indicator_states(self) -> dict:
        return {
            "midi": self._running,
            "osc":  self._osc_enabled_var.get(),
            "auto": self._running and self._engine.autopilot_active,
            "ctrl": self._joystick is not None,
            "cal":  any(v.get("enabled") for v in self._axis_cal.values()),
            "key":  isinstance(self._joystick, KeyboardJoystick),
        }

    def _open_agc_window(self):
        if self._dsky_win and self._dsky_win.winfo_exists():
            self._dsky_win.lift()
            return
        self._dsky_win = DskyWindow(
            self,
            get_osc_vals=self._engine.get_osc_snapshot,
            get_indicators=self._get_indicator_states,
            osc_in=self._osc_in,
        )

    # -----------------------------------------------------------------------
    # Playlist window
    # -----------------------------------------------------------------------

    def _open_playlist_window(self):
        if self._pl_win and self._pl_win.winfo_exists():
            self._pl_win.lift()
            return
        self._pl_win = PlaylistWindow(
            self, self._engine, self._save_playlist_config)

    def _save_playlist_config(self, cfg: PlaylistConfig = None):
        if cfg is None:
            cfg = self._engine._playlist
        self._autosave()

    # -----------------------------------------------------------------------
    # Cleanup
    # -----------------------------------------------------------------------

    def _on_close(self):
        self._autosave()
        self._engine.close()
        self._osc_in.stop()
        pygame.quit()
        self.destroy()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    app = MapperApp()
    app.mainloop()
