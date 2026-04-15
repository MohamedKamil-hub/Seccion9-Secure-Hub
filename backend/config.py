"""
SECCION9 LITE — Configuration
All values from .env. Panel settings persisted in JSON.
"""

import json
import os
from pydantic_settings import BaseSettings

PANEL_SETTINGS_FILE = "/etc/wireguard/panel_settings.json"


def get_panel_setting(key: str, default=None):
    try:
        with open(PANEL_SETTINGS_FILE) as f:
            return json.load(f).get(key, default)
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def save_panel_setting(key: str, value):
    data = {}
    try:
        if os.path.exists(PANEL_SETTINGS_FILE):
            with open(PANEL_SETTINGS_FILE) as f:
                data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    data[key] = value
    os.makedirs(os.path.dirname(PANEL_SETTINGS_FILE), exist_ok=True)
    with open(PANEL_SETTINGS_FILE, "w") as f:
        json.dump(data, f, indent=2)


class Settings(BaseSettings):
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    admin_user: str = "admin"
    admin_password: str = "admin1234"
    secret_key: str = "change-me-in-production"
    server_public_ip: str = ""
    server_public_key: str = ""
    server_port: int = 51820
    wg_interface: str = "wg0"
    wg_conf_path: str = "/etc/wireguard/wg0.conf"
    configs_dir: str = "/etc/wireguard/clientes"
    access_token_expire_minutes: int = 480
    vpn_subnet: str = "10.0.0"
    dns_servers: str = "8.8.8.8,8.8.4.4"
    panel_public_url: str = ""
    backup_server_ip: str = ""
    backup_server_port: int = 22
    private_web_port: int = 80

    class Config:
        env_file = ".env"
        extra = "ignore"

    def get_dns(self) -> str:
        override = get_panel_setting("dns_servers")
        return override if override else self.dns_servers

    def get_invite_base_url(self) -> str:
        if self.panel_public_url:
            return self.panel_public_url.rstrip("/")
        return f"https://{self.server_public_ip}"


settings = Settings()
