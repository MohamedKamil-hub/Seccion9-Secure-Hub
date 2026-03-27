from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # API
    api_host: str = "127.0.0.1"
    api_port: int = 8000

    # Auth
    admin_user: str = "admin"
    admin_password: str = "CAMBIAME"
    secret_key: str = "CAMBIAME"
    access_token_expire_minutes: int = 480  # 8 horas

    # WireGuard
    server_public_ip: str = ""
    server_public_key: str = ""
    server_port: int = 51820
    wg_interface: str = "wg0"
    wg_conf_path: str = "/etc/wireguard/wg0.conf"
    vpn_subnet: str = "10.0.0"
    configs_dir: str = "/etc/wireguard/clientes"

    class Config:
        env_file = ".env"


settings = Settings()
