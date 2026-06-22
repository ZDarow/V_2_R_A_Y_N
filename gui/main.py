#!/usr/bin/env python3
# v2rayN Manager — графический интерфейс управления прокси
# © 2026, MIT License

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib, GdkPixbuf, Pango
import subprocess
import threading
import os
import sys
import json
import signal
from pathlib import Path
from datetime import datetime

# =============================================================================
# Конфигурация
# =============================================================================
HOME = os.path.expanduser("~")
SCRIPTS_DIR = f"{HOME}/.local/share/v2rayN/scripts"
CONFIG_DIR = f"{HOME}/.config/v2rayN"
DATA_DIR = f"{HOME}/.local/share/v2rayN"
BIN_DIR = f"{DATA_DIR}/bin"
LOGS_DIR = f"{DATA_DIR}/logs"
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SCRIPT_NAMES = {
    "proxy-toggle": f"{SCRIPTS_DIR}/proxy-toggle.sh",
    "status": f"{SCRIPTS_DIR}/status.sh",
    "diagnose": f"{SCRIPTS_DIR}/diagnose.sh",
    "diagnose-network": f"{PROJECT_DIR}/scripts/diagnose-network.sh",
    "netcheck": f"{PROJECT_DIR}/scripts/netcheck.sh",
    "kill-switch": f"{PROJECT_DIR}/scripts/kill-switch.sh",
    "update-rules": f"{SCRIPTS_DIR}/update-rules.sh",
    "migrate-allowinsecure": f"{SCRIPTS_DIR}/migrate-allowinsecure.sh",
    "sync-time": "/usr/local/bin/sync-time.sh",
    "install": f"{PROJECT_DIR}/install.sh",
    "uninstall": f"{PROJECT_DIR}/uninstall.sh",
    "traffic-capture": f"{PROJECT_DIR}/scripts/traffic-capture.sh",
    "proxy-manager": f"{PROJECT_DIR}/scripts/proxy-manager-gui.sh",
    "deploy-mobile": f"{PROJECT_DIR}/mobile/scripts/deploy-mobile.sh",
}

# =============================================================================
# Утилиты
# =============================================================================

def run_cmd(cmd, timeout=30):
    """Запуск команды, возврат (stdout, stderr, returncode)"""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout, r.stderr, r.returncode
    except subprocess.TimeoutExpired:
        return "", "TIMEOUT", -1
    except FileNotFoundError:
        return "", "COMMAND NOT FOUND", -1


def run_cmd_async(cmd, callback, timeout=60):
    """Запуск в отдельном потоке"""
    def worker():
        out, err, rc = run_cmd(cmd, timeout)
        GLib.idle_add(callback, out, err, rc)
    threading.Thread(target=worker, daemon=True).start()


def get_script_path(name):
    return SCRIPT_NAMES.get(name, "")


def script_exists(name):
    return os.path.isfile(SCRIPT_NAMES.get(name, ""))


# =============================================================================
# Виджеты
# =============================================================================

class TextViewBuffer:
    """ScrolledTextView + TextBuffer для вывода результатов"""
    def __init__(self):
        self.buffer = Gtk.TextBuffer()
        self.textview = Gtk.TextView(buffer=self.buffer)
        self.textview.set_editable(False)
        self.textview.set_cursor_visible(False)
        self.textview.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        css = Gtk.CssProvider()
        css.load_from_data(b"textview { font: 9pt monospace; }")
        self.textview.get_style_context().add_provider(css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.scrolled = Gtk.ScrolledWindow()
        self.scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        self.scrolled.set_vexpand(True)
        self.scrolled.set_hexpand(True)
        self.scrolled.add(self.textview)

    def append(self, text, tag=None):
        end = self.buffer.get_end_iter()
        if tag:
            self.buffer.insert_with_tags_by_name(end, text, tag)
        else:
            self.buffer.insert(end, text)
        self.textview.scroll_to_iter(self.buffer.get_end_iter(), 0.0, False, 0.0)

    def clear(self):
        self.buffer.set_text("")

    def get_widget(self):
        return self.scrolled


class StatusBar:
    """Нижняя панель статуса"""
    def __init__(self, window):
        self.window = window
        self.box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self.box.set_margin_start(8)
        self.box.set_margin_end(8)
        self.box.set_margin_top(4)
        self.box.set_margin_bottom(4)

        # Иконка статуса
        self.icon = Gtk.Image.new_from_icon_name("network-wired", Gtk.IconSize.MENU)
        self.box.pack_start(self.icon, False, False, 0)

        # Прокси
        self.proxy_label = Gtk.Label(label="Прокси: ⏳")
        self.proxy_label.set_xalign(0)
        self.box.pack_start(self.proxy_label, False, False, 4)

        # Xray
        self.xray_label = Gtk.Label(label="Xray: ⏳")
        self.xray_label.set_xalign(0)
        self.box.pack_start(self.xray_label, False, False, 4)

        # Kill-switch
        self.ks_label = Gtk.Label(label="KS: ⏳")
        self.ks_label.set_xalign(0)
        self.box.pack_start(self.ks_label, False, False, 4)

        # Время
        self.time_label = Gtk.Label(label="")
        self.time_label.set_xalign(1)
        self.box.pack_end(self.time_label, True, True, 0)

        self.update()

    def update(self):
        def cb(out, err, rc):
            # Статус прокси
            proxy_mode = "⏳"
            try:
                r = subprocess.run(
                    ["gsettings", "get", "org.gnome.system.proxy", "mode"],
                    capture_output=True, text=True, timeout=3
                )
                mode = r.stdout.strip().strip("'")
                proxy_mode = "🟢 ВКЛ" if mode == "manual" else "🔴 ВЫКЛ"
            except: pass
            self.proxy_label.set_text(f"Прокси: {proxy_mode}")

            # Xray
            xray_status = "⏳"
            if os.path.isfile(f"{BIN_DIR}/xray/xray"):
                if os.system("pgrep -x xray >/dev/null 2>&1") == 0:
                    xray_status = "🟢 РАБОТАЕТ"
                else:
                    xray_status = "🔴 ОСТАНОВЛЕН"
            else:
                xray_status = "⚪ НЕ УСТАНОВЛЕН"
            self.xray_label.set_text(f"Xray: {xray_status}")

            # Kill-switch
            ks_status = "⏳"
            r = os.system("sudo iptables -L V2RAYN >/dev/null 2>&1")
            if r == 0:
                ks_status = "🟢 АКТИВЕН"
            else:
                r2 = os.system("iptables -L V2RAYN >/dev/null 2>&1")
                ks_status = "🟢 АКТИВЕН" if r2 == 0 else "⚪ ВЫКЛ"
            self.ks_label.set_text(f"Kill-switch: {ks_status}")

            # Время
            now = datetime.now().strftime("%H:%M:%S")
            self.time_label.set_text(f"🕐 {now}")

        run_cmd_async(["true"], cb)

    def start_auto_update(self):
        GLib.timeout_add_seconds(10, self.update)
        self.update()
        return True


# =============================================================================
# Вкладки
# =============================================================================

class TabStatus:
    """Вкладка «Статус»"""
    def __init__(self):
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.box.set_margin_top(12)
        self.box.set_margin_bottom(12)
        self.box.set_margin_start(12)
        self.box.set_margin_end(12)

        # Сетка статусов
        grid = Gtk.Grid()
        grid.set_column_spacing(12)
        grid.set_row_spacing(6)

        labels = [
            ("🖥 Платформа", "⏳", "platform"),
            ("🌐 Прокси SOCKS5", "⏳", "proxy_socks"),
            ("🌐 Прокси HTTP", "⏳", "proxy_http"),
            ("🔀 BBR", "⏳", "bbr"),
            ("🛡 Kill-switch", "⏳", "killswitch"),
            ("⏱ Время (NTP)", "⏳", "ntp"),
            ("📦 geoip.dat", "⏳", "geoip"),
            ("📦 geosite.dat", "⏳", "geosite"),
            ("🔌 Xray-core", "⏳", "xray"),
            ("🔄 Обновление правил", "⏳", "update_timer"),
        ]

        self.labels = {}
        for i, (title, default, key) in enumerate(labels):
            row, col = divmod(i, 2)
            lbl = Gtk.Label(label=title, xalign=0)
            val = Gtk.Label(label=default, xalign=0)
            val.set_markup(f"<b>{default}</b>")
            self.labels[key] = val
            grid.attach(lbl, col * 2, row, 1, 1)
            grid.attach(val, col * 2 + 1, row, 1, 1)

        self.box.pack_start(grid, False, False, 0)

        # Разделитель
        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        sep.set_margin_top(12)
        sep.set_margin_bottom(12)
        self.box.pack_start(sep, False, False, 0)

        # Кнопка обновить
        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        refresh_btn = Gtk.Button(label="🔄 Обновить статус")
        refresh_btn.connect("clicked", self.refresh)
        btn_row.pack_start(refresh_btn, False, False, 0)
        self.box.pack_start(btn_row, False, False, 0)

        # Текстовый лог
        self.log = TextViewBuffer()
        self.box.pack_start(self.log.get_widget(), True, True, 0)

        self.refresh()

    def refresh(self, widget=None):
        def probe(key, cmd, transform=None):
            def cb(out, err, rc):
                val = transform(out) if transform else (out.strip() if out else "N/A")
                self.labels[key].set_markup(f"<b>{val}</b>")
            run_cmd_async(cmd, cb, timeout=5)

        probe("platform", ["uname", "-mo"])
        probe("proxy_socks", ["bash", "-c",
            "ss -tlnp 2>/dev/null | grep -q ':10808 ' && echo '🟢 :10808' || echo '🔴 не слушает'"])
        probe("proxy_http", ["bash", "-c",
            "ss -tlnp 2>/dev/null | grep -q ':10809 ' && echo '🟢 :10809' || echo '🔴 не слушает'"])
        probe("bbr", ["bash", "-c",
            "sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'N/A'"])
        probe("killswitch", ["bash", "-c",
            "sudo iptables -L V2RAYN >/dev/null 2>&1 && echo '🟢 АКТИВЕН' || echo '⚪ ВЫКЛ'"])
        probe("ntp", ["bash", "-c",
            "timedatectl show --property=NTPSynchronized --value 2>/dev/null || echo 'no'"])

        # geoip/geosite даты
        for f, k in [("geoip.dat", "geoip"), ("geosite.dat", "geosite")]:
            path = f"{BIN_DIR}/{f}"
            if os.path.isfile(path):
                size = os.path.getsize(path)
                mtime = datetime.fromtimestamp(os.path.getmtime(path)).strftime("%d.%m.%Y")
                self.labels[k].set_markup(
                    f"<b>{mtime} ({size // 1024 // 1024}MB)</b>")
            else:
                self.labels[k].set_markup("<b>🔴 не найден</b>")

        # Xray версия
        xray_bin = f"{BIN_DIR}/xray/xray"
        if os.path.isfile(xray_bin):
            probe("xray", ["bash", "-c", f"\"{xray_bin}\" version 2>/dev/null | head -1 || echo 'OK'"])
        else:
            self.labels["xray"].set_markup("<b>🔴 не установлен</b>")

        # Timer
        probe("update_timer", ["bash", "-c",
            "systemctl --user is-active v2rayn-rules-update.timer 2>/dev/null || echo 'inactive'"])

    def get_widget(self):
        return self.box


class TabControl:
    """Вкладка «Управление»"""
    def __init__(self):
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.box.set_margin_top(12)
        self.box.set_margin_bottom(12)
        self.box.set_margin_start(12)
        self.box.set_margin_end(12)

        # Прокси
        frame_proxy = self._make_action_group("🌐 Системный прокси", [
            ("🟢 Включить", "proxy-toggle", ["bash", get_script_path("proxy-toggle"), "on"]),
            ("🔴 Выключить", "proxy-toggle-off", ["bash", get_script_path("proxy-toggle"), "off"]),
            ("📋 Статус", "proxy-status", ["bash", get_script_path("status")]),
        ])
        self.box.pack_start(frame_proxy, False, False, 0)

        # Kill-switch
        frame_ks = self._make_action_group("🛡 Kill-switch (iptables)", [
            ("🟢 Включить", "ks-on", ["sudo", get_script_path("kill-switch"), "on"]),
            ("🔴 Выключить", "ks-off", ["sudo", get_script_path("kill-switch"), "off"]),
            ("📋 Статус", "ks-status", ["sudo", get_script_path("kill-switch"), "status"]),
        ])
        self.box.pack_start(frame_ks, False, False, 0)

        # Обновления
        frame_update = self._make_action_group("🔄 Обновление правил", [
            ("📥 Обновить geoip/geosite", "update-rules", ["bash", get_script_path("update-rules")]),
            ("🕐 Статус таймера", "timer-status", ["bash", "-c",
                "systemctl --user status v2rayn-rules-update.timer 2>/dev/null | head -5"]),
        ])
        self.box.pack_start(frame_update, False, False, 0)

        # Xray
        frame_xray = self._make_action_group("🔌 Xray-core", [
            ("🔄 Перезапустить", "restart-xray", ["bash", "-c",
                "systemctl --user restart v2rayn.service 2>/dev/null || pkill -x xray 2>/dev/null; "
                "nohup ~/.local/share/v2rayN/bin/xray/xray run -c ~/.config/xray/config.json >/dev/null 2>&1 &"]),
            ("📋 Статус", "xray-status", ["bash", "-c",
                "systemctl --user status v2rayn.service 2>/dev/null || pgrep -a xray 2>/dev/null || echo 'xray не запущен'"]),
        ])
        self.box.pack_start(frame_xray, False, False, 0)

        # Время
        frame_time = self._make_action_group("⏱ Синхронизация времени", [
            ("🔄 Синхронизировать", "sync-time", ["sudo", get_script_path("sync-time")]),
            ("📋 Статус", "time-status", ["bash", "-c", "timedatectl status | head -8"]),
        ])
        self.box.pack_start(frame_time, False, False, 0)

        self.output = TextViewBuffer()
        self.box.pack_start(self.output.get_widget(), True, True, 0)

    def _make_action_group(self, title, actions):
        frame = Gtk.Frame(label=title)
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        vbox.set_margin_top(6)
        vbox.set_margin_bottom(6)
        vbox.set_margin_start(6)
        vbox.set_margin_end(6)

        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        for label, name, cmd in actions:
            btn = Gtk.Button(label=label)
            btn.connect("clicked", self._on_action, name, cmd)
            hbox.pack_start(btn, False, False, 0)
        vbox.pack_start(hbox, False, False, 0)
        frame.add(vbox)
        return frame

    def _on_action(self, btn, name, cmd):
        self.output.clear()
        self.output.append(f"$ {' '.join(cmd)}\n\n", "cmd")
        def cb(out, err, rc):
            self.output.append(out if out else "")
            if err:
                self.output.append(f"\n⚠ {err}\n", "warn")
            self.output.append(f"\n[код: {rc}]\n")
        run_cmd_async(cmd, cb, timeout=120)

    def get_widget(self):
        return self.box


class TabDiagnostics:
    """Вкладка «Диагностика»"""
    def __init__(self):
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.box.set_margin_top(12)
        self.box.set_margin_bottom(12)
        self.box.set_margin_start(12)
        self.box.set_margin_end(12)

        # Кнопки в FlowBox с переносом строк
        btn_box = Gtk.FlowBox()
        btn_box.set_max_children_per_line(3)
        btn_box.set_selection_mode(Gtk.SelectionMode.NONE)
        btn_box.set_column_spacing(6)
        btn_box.set_row_spacing(6)

        diag_buttons = [
            ("🚀 Быстрая диагностика", "diagnose-quick",
             ["bash", get_script_path("diagnose-network"), "--quick", "--no-install"]),
            ("🔬 Полная диагностика", "diagnose-full",
             ["bash", get_script_path("diagnose-network"), "--no-install"]),
            ("🛡 Безопасность", "diagnose-security",
             ["bash", get_script_path("diagnose-network"), "--security"]),
            ("🌐 Связность", "diagnose-connectivity",
             ["bash", get_script_path("diagnose-network"), "--connectivity"]),
            ("📋 Netcheck", "netcheck", ["bash", get_script_path("netcheck")]),
            ("📡 Захват трафика", "traffic",
             ["bash", get_script_path("traffic-capture")]),
        ]

        for label, name, cmd in diag_buttons:
            btn = Gtk.Button(label=label)
            btn.connect("clicked", self._run_diag, name, cmd)
            btn_box.insert(btn, -1)

        self.box.pack_start(btn_box, False, False, 0)

        self.output = TextViewBuffer()
        self.box.pack_start(self.output.get_widget(), True, True, 0)

    def _run_diag(self, btn, name, cmd):
        self.output.clear()
        self.output.append(f"$ {' '.join(cmd)}\n\n", "cmd")
        def cb(out, err, rc):
            self.output.append(out if out else "")
            if err:
                self.output.append(f"\n⚠ {err}\n", "warn")
            self.output.append(f"\n[код: {rc}]\n")
        run_cmd_async(cmd, cb, timeout=300)

    def get_widget(self):
        return self.box


class TabInstall:
    """Вкладка «Установка/Обновление»"""
    def __init__(self):
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.box.set_margin_top(12)
        self.box.set_margin_bottom(12)
        self.box.set_margin_start(12)
        self.box.set_margin_end(12)

        btn_box = Gtk.FlowBox()
        btn_box.set_max_children_per_line(3)
        btn_box.set_selection_mode(Gtk.SelectionMode.NONE)
        btn_box.set_column_spacing(6)
        btn_box.set_row_spacing(6)

        buttons = [
            ("📥 Установить v2rayN", "install", ["bash", get_script_path("install")]),
            ("📥 Конфиги + подписки", "install-configs",
             ["bash", get_script_path("install"), "--skip-v2rayn"]),
            ("🗑 Удалить v2rayN", "uninstall", ["bash", get_script_path("uninstall")]),
            ("📦 Обновить geoip/geosite", "update-rules",
             ["bash", get_script_path("update-rules")]),
            ("🔄 Миграция allowInsecure", "migrate",
             ["bash", get_script_path("migrate-allowinsecure")]),
        ]

        for label, name, cmd in buttons:
            btn = Gtk.Button(label=label)
            btn.connect("clicked", self._run_install, name, cmd)
            btn_box.insert(btn, -1)

        self.box.pack_start(btn_box, False, False, 0)

        self.output = TextViewBuffer()
        self.box.pack_start(self.output.get_widget(), True, True, 0)

    def _run_install(self, btn, name, cmd):
        self.output.clear()
        self.output.append(f"$ {' '.join(cmd)}\n\n", "cmd")
        def cb(out, err, rc):
            self.output.append(out if out else "")
            if err:
                self.output.append(f"\n⚠ {err}\n", "warn")
            self.output.append(f"\n[код: {rc}]\n")
        run_cmd_async(cmd, cb, timeout=300)

    def get_widget(self):
        return self.box


class TabMobile:
    """Вкладка «Мобильное»"""
    def __init__(self):
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.box.set_margin_top(12)
        self.box.set_margin_bottom(12)
        self.box.set_margin_start(12)
        self.box.set_margin_end(12)

        btn_box = Gtk.FlowBox()
        btn_box.set_max_children_per_line(3)
        btn_box.set_selection_mode(Gtk.SelectionMode.NONE)
        btn_box.set_column_spacing(6)
        btn_box.set_row_spacing(6)

        buttons = [
            ("📱 Деплой (ADB)", "deploy-adb",
             ["bash", get_script_path("deploy-mobile"), "--mode", "adb"]),
            ("📱 Деплой (ZIP)", "deploy-zip",
             ["bash", get_script_path("deploy-mobile"), "--mode", "zip"]),
            ("📱 Деплой (HTTP)", "deploy-http",
             ["bash", get_script_path("deploy-mobile"), "--mode", "http"]),
            ("🔗 Сгенерировать URL", "gen-url",
             ["bash", f"{PROJECT_DIR}/mobile/scripts/generate-mobile-url.sh"]),
            ("📖 Документация", "mobile-docs",
             ["bash", "-c", f"xdg-open {PROJECT_DIR}/mobile/docs/mobile.md 2>/dev/null || echo 'Откройте вручную: mobile/docs/mobile.md'"]),
        ]

        for label, name, cmd in buttons:
            btn = Gtk.Button(label=label)
            btn.connect("clicked", self._run_mobile, name, cmd)
            btn_box.insert(btn, -1)

        self.box.pack_start(btn_box, False, False, 0)

        self.output = TextViewBuffer()
        self.box.pack_start(self.output.get_widget(), True, True, 0)

    def _run_mobile(self, btn, name, cmd):
        self.output.clear()
        self.output.append(f"$ {' '.join(cmd)}\n\n", "cmd")
        def cb(out, err, rc):
            self.output.append(out if out else "")
            if err:
                self.output.append(f"\n⚠ {err}\n", "warn")
            self.output.append(f"\n[код: {rc}]\n")
        run_cmd_async(cmd, cb, timeout=120)

    def get_widget(self):
        return self.box


class TabLogs:
    """Вкладка «Логи»"""
    def __init__(self):
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.box.set_margin_top(12)
        self.box.set_margin_bottom(12)
        self.box.set_margin_start(12)
        self.box.set_margin_end(12)

        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)

        refresh_btn = Gtk.Button(label="🔄 Обновить список")
        refresh_btn.connect("clicked", self.refresh)
        btn_row.pack_start(refresh_btn, False, False, 0)

        self.file_combo = Gtk.ComboBoxText()
        self.file_combo.set_size_request(300, -1)
        btn_row.pack_start(self.file_combo, False, False, 4)

        view_btn = Gtk.Button(label="📄 Показать")
        view_btn.connect("clicked", self.show_log)
        btn_row.pack_start(view_btn, False, False, 0)

        clear_btn = Gtk.Button(label="🧹 Очистить")
        clear_btn.connect("clicked", self.clear_output)
        btn_row.pack_start(clear_btn, False, False, 0)

        self.box.pack_start(btn_row, False, False, 0)

        self.output = TextViewBuffer()
        self.box.pack_start(self.output.get_widget(), True, True, 0)

        self.log_files = []
        self.refresh()

    def refresh(self, widget=None):
        self.file_combo.remove_all()
        self.log_files = []

        # Собираем логи
        dirs = [LOGS_DIR, f"{HOME}/logs", "/var/log"]
        for d in dirs:
            if os.path.isdir(d):
                for f in sorted(os.listdir(d), reverse=True):
                    path = os.path.join(d, f)
                    if os.path.isfile(path) and (f.endswith(".log") or "diagnostic" in f):
                        size = os.path.getsize(path)
                        self.file_combo.append_text(f"{d}/{f}  ({size//1024}KB)")
                        self.log_files.append(path)

        if self.log_files:
            self.file_combo.set_active(0)

    def show_log(self, widget=None):
        idx = self.file_combo.get_active()
        if idx < 0 or idx >= len(self.log_files):
            return
        path = self.log_files[idx]
        self.output.clear()
        try:
            with open(path, 'r', errors='replace') as f:
                data = f.read()
            # Показываем последние 200 строк
            lines = data.split('\n')
            if len(lines) > 200:
                lines = lines[-200:]
                self.output.append(f"... (показаны последние 200 из {len(lines)} строк)\n\n")
            self.output.append('\n'.join(lines))
        except Exception as e:
            self.output.append(f"Ошибка чтения: {e}")

    def clear_output(self, widget=None):
        self.output.clear()

    def get_widget(self):
        return self.box


class TabConfig:
    """Вкладка «Конфигурация»"""
    def __init__(self):
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.box.set_margin_top(12)
        self.box.set_margin_bottom(12)
        self.box.set_margin_start(12)
        self.box.set_margin_end(12)

        # Выбор режима роутинга
        routing_frame = Gtk.Frame(label="⚙️ Режим роутинга")
        routing_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        routing_vbox.set_margin_top(6)
        routing_vbox.set_margin_bottom(6)
        routing_vbox.set_margin_start(6)
        routing_vbox.set_margin_end(6)

        label = Gtk.Label(
            label="Текущий режим определяет, какой трафик идёт через прокси.\n"
                  "Изменение требует перезапуска Xray.",
            xalign=0, wrap=True
        )
        routing_vbox.pack_start(label, False, False, 0)

        mode_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.routing_all = Gtk.RadioButton.new_with_label_from_widget(None, "🌍 Всё через прокси (routing-russia.json)")
        self.routing_blocked = Gtk.RadioButton.new_with_label_from_widget(self.routing_all, "🔒 Только заблокированное (only_blocked.json)")
        mode_row.pack_start(self.routing_all, False, False, 0)
        mode_row.pack_start(self.routing_blocked, False, False, 0)
        routing_vbox.pack_start(mode_row, False, False, 0)

        apply_btn = Gtk.Button(label="✅ Применить")
        apply_btn.connect("clicked", self.apply_routing)
        routing_vbox.pack_start(apply_btn, False, False, 0)

        routing_frame.add(routing_vbox)
        self.box.pack_start(routing_frame, False, False, 0)

        # Файлы конфигов
        config_frame = Gtk.Frame(label="📝 Файлы конфигурации")
        config_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        config_vbox.set_margin_top(6)
        config_vbox.set_margin_bottom(6)
        config_vbox.set_margin_start(6)
        config_vbox.set_margin_end(6)

        config_files = [
            ("routing-russia.json", f"{CONFIG_DIR}/routing-russia.json"),
            ("only_blocked.json", f"{CONFIG_DIR}/only_blocked.json"),
            ("config.json (Xray)", f"{HOME}/.config/xray/config.json"),
            ("guiNConfig.json", f"{CONFIG_DIR}/guiNConfig.json"),
        ]

        for name, path in config_files:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
            fname = Gtk.Label(label=name, xalign=0)
            fname.set_size_request(200, -1)
            row.pack_start(fname, False, False, 0)
            status = "✅" if os.path.isfile(path) else "❌"
            slbl = Gtk.Label(label=f"{status}  {path}")
            slbl.set_xalign(0)
            slbl.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
            row.pack_start(slbl, True, True, 0)
            config_vbox.pack_start(row, False, False, 0)

        config_frame.add(config_vbox)
        self.box.pack_start(config_frame, False, False, 0)

        # Определяем текущий режим
        self._detect_current_mode()

    def _detect_current_mode(self):
        def cb(out, err, rc):
            if "only_blocked" in out:
                self.routing_blocked.set_active(True)
            else:
                self.routing_all.set_active(True)
        run_cmd_async(
            ["bash", "-c", f"grep -l 'only_blocked\\|routing-russia' {HOME}/.config/xray/config.json 2>/dev/null || echo 'routing-russia'"],
            cb
        )

    def apply_routing(self, widget):
        mode = "only_blocked" if self.routing_blocked.get_active() else "routing-russia"
        src = f"{PROJECT_DIR}/config/{mode}.json"
        dst = f"{CONFIG_DIR}/{mode}.json"

        def cb(out, err, rc):
            if rc == 0:
                self._restart_xray()
            else:
                dialog = Gtk.MessageDialog(
                    parent=None, flags=0,
                    message_type=Gtk.MessageType.ERROR,
                    buttons=Gtk.ButtonsType.OK,
                    text=f"Ошибка копирования {mode}.json"
                )
                dialog.run()
                dialog.destroy()

        run_cmd_async(["cp", src, dst], cb)

    def _restart_xray(self):
        def cb(out, err, rc):
            dialog = Gtk.MessageDialog(
                parent=None, flags=0,
                message_type=Gtk.MessageType.INFO,
                buttons=Gtk.ButtonsType.OK,
                text="Режим роутинга изменён. Перезапустите Xray на вкладке «Управление»."
            )
            dialog.run()
            dialog.destroy()

        run_cmd_async(["bash", "-c",
            "pkill -x xray 2>/dev/null; sleep 1; "
            "nohup ~/.local/share/v2rayN/bin/xray/xray run -c ~/.config/xray/config.json >/dev/null 2>&1 &"],
            cb)

    def get_widget(self):
        return self.box


# =============================================================================
# Главное окно
# =============================================================================

class MainWindow:
    def __init__(self):
        self.window = Gtk.Window(title="v2rayN Manager")
        self.window.set_default_size(960, 680)
        self.window.set_position(Gtk.WindowPosition.CENTER)
        self.window.connect("map-event", self._on_first_map)

        # Устанавливаем иконку
        icon_path = os.path.join(os.path.dirname(__file__), "icons", "v2rayn.png")
        if os.path.isfile(icon_path):
            self.window.set_icon_from_file(icon_path)

        # Обработка Ctrl+C
        signal.signal(signal.SIGINT, self._on_sigint)

        # Основной контейнер
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # Notebook (вкладки) — обёрнут в ScrolledWindow, чтобы не растягивать окно
        self.tabs = {}
        tab_configs = [
            ("📊 Статус", TabStatus()),
            ("🎮 Управление", TabControl()),
            ("🔬 Диагностика", TabDiagnostics()),
            ("📥 Установка", TabInstall()),
            ("📱 Мобильное", TabMobile()),
            ("📋 Логи", TabLogs()),
            ("⚙️ Конфиг", TabConfig()),
        ]

        notebook = Gtk.Notebook()
        notebook.set_tab_pos(Gtk.PositionType.TOP)
        notebook.set_scrollable(True)

        for name, tab in tab_configs:
            lbl = Gtk.Label(label=name)
            notebook.append_page(tab.get_widget(), lbl)
            self.tabs[name] = tab

        # ScrolledWindow отключает влияние notebook на размер окна
        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.add(notebook)
        sw.set_vexpand(True)
        sw.set_hexpand(True)

        vbox.pack_start(sw, True, True, 0)

        # Статус-бар
        self.statusbar = StatusBar(self.window)
        self.statusbar.start_auto_update()
        vbox.pack_start(self.statusbar.box, False, False, 0)

        self.window.add(vbox)

        # Меню
        self._create_menu()

        self.window.connect("destroy", self._on_destroy)

    def _create_menu(self):
        accel = Gtk.AccelGroup()
        self.window.add_accel_group(accel)

        # Всегда поверх других окон
        self.window.set_keep_above(False)

    def _on_sigint(self, signum, frame):
        Gtk.main_quit()

    def _on_destroy(self, widget):
        Gtk.main_quit()

    def _on_first_map(self, widget, event):
        """После первого отображения — подгоняем размер под экран"""
        display = self.window.get_display()
        n_mon = display.get_n_monitors()
        if n_mon > 0:
            geo = display.get_monitor(0).get_geometry()
            max_w = min(geo.width - 40, 1200)
            max_h = min(geo.height - 80, 800)
        else:
            max_w, max_h = 960, 680
        # Тройной ресайз с задержками — GTK может отменять resize()
        GLib.idle_add(lambda: self._try_resize(max_w, max_h))
        GLib.timeout_add(100, lambda: self._try_resize(max_w, max_h))
        GLib.timeout_add(300, lambda: self._try_resize(max_w, max_h))
        return False

    def _try_resize(self, max_w, max_h):
        cur_w, cur_h = self.window.get_size()
        new_w = min(cur_w, max_w)
        new_h = min(cur_h, max_h)
        if new_w < cur_w or new_h < cur_h:
            self.window.unmaximize()
            self.window.resize(new_w, new_h)
        return False

    def run(self):
        self.window.show_all()
        Gtk.main()


# =============================================================================
# Точка входа
# =============================================================================

def setup_tags(buffer):
    """Регистрация тегов для подсветки вывода"""
    tag_table = buffer.get_tag_table()

    cmd_tag = Gtk.TextTag.new("cmd")
    cmd_tag.set_property("foreground", "#555")
    cmd_tag.set_property("style", Pango.Style.ITALIC)
    tag_table.add(cmd_tag)

    warn_tag = Gtk.TextTag.new("warn")
    warn_tag.set_property("foreground", "#cc6600")
    warn_tag.set_property("weight", Pango.Weight.BOLD)
    tag_table.add(warn_tag)

    ok_tag = Gtk.TextTag.new("ok")
    ok_tag.set_property("foreground", "#008800")
    tag_table.add(ok_tag)

    err_tag = Gtk.TextTag.new("err")
    err_tag.set_property("foreground", "#cc0000")
    err_tag.set_property("weight", Pango.Weight.BOLD)
    tag_table.add(err_tag)


def main():
    # Проверка зависимостей
    try:
        import gi
        gi.require_version('Gtk', '3.0')
    except (ImportError, ValueError) as e:
        print(f"Ошибка: требуется PyGObject (python3-gi). Установите: sudo apt install python3-gi", file=sys.stderr)
        sys.exit(1)

    app = MainWindow()

    # Настройка тегов во всех текстовых буферах
    for tab in app.tabs.values():
        if hasattr(tab, 'output') and hasattr(tab.output, 'buffer'):
            setup_tags(tab.output.buffer)

    app.run()


if __name__ == "__main__":
    main()
