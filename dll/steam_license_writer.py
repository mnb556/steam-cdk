#!/usr/bin/env python3
"""Steam许可文件写入器 — 独立运行，不注入任何进程"""
import os, json, sys, winreg, urllib.request, shutil

FLASK = "http://127.0.0.1:5000"
APPID = 1623730

def find_steam():
    keys = [
        (winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam", "SteamPath"),
        (winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam", "SteamExe"),
        (winreg.HKEY_LOCAL_MACHINE, r"Software\WOW6432Node\Valve\Steam", "InstallPath"),
    ]
    for root, subkey, name in keys:
        try:
            with winreg.OpenKey(root, subkey) as k:
                v, _ = winreg.QueryValueEx(k, name)
                v = v.replace("/", "\\")
                if v.lower().endswith("steam.exe"):
                    return os.path.dirname(v)
                return v
        except:
            pass
    return None

def http_get(url):
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            return json.loads(r.read())
    except Exception as e:
        print(f"  [!] API error: {e}")
        return None

def backup(path):
    bak = path + ".ctfbak"
    if os.path.exists(path) and not os.path.exists(bak):
        shutil.copy2(path, bak)
        print(f"  [*] Backed up: {os.path.basename(path)}")

def main():
    print("[*] Steam License Writer v1.0")

    steam = find_steam()
    if not steam:
        print("[!] Steam not found")
        return 1
    print(f"[*] Steam: {steam}")

    # 1. Get authorized apps from Flask
    print("[*] Getting app list from server...")
    data = http_get(f"{FLASK}/api/cdk/install-apps")
    if not data or not data.get("apps"):
        print("[!] No authorized apps — generate CDK codes first")
        return 1

    apps = data["apps"]
    print(f"[*] Found {len(apps)} app(s):")
    for a in apps:
        print(f"    AppID={a['appid']} Name={a['game_name']}")

    # 2. Write appmanifest for each app
    steamapps = os.path.join(steam, "steamapps")
    os.makedirs(steamapps, exist_ok=True)

    for app in apps:
        appid = app["appid"]
        name = app["game_name"]

        # appmanifest_<appid>.acf
        acf_path = os.path.join(steamapps, f"appmanifest_{appid}.acf")
        if os.path.exists(acf_path):
            print(f"  [*] appmanifest_{appid}.acf exists, skip")
        else:
            backup(acf_path)
            acf = f'''"AppState"
{{
\t"appid"\t\t"{appid}"
\t"Universe"\t\t"1"
\t"name"\t\t"{name}"
\t"StateFlags"\t\t"4"
\t"installdir"\t\t"{name}"
\t"LastUpdated"\t\t"0"
\t"UpdateResult"\t\t"0"
\t"SizeOnDisk"\t\t"1"
\t"buildid"\t\t"13371337"
\t"LastOwner"\t\t"76561198000000000"
\t"BytesToDownload"\t\t"0"
\t"BytesDownloaded"\t\t"0"
\t"AutoUpdateBehavior"\t\t"0"
}}
'''
            with open(acf_path, 'w') as f:
                f.write(acf)
            print(f"  [+] Wrote: appmanifest_{appid}.acf")

    # 2.5 Write package license
    package_dir = os.path.join(steam, "package")
    os.makedirs(package_dir, exist_ok=True)
    for app in apps:
        appid = app["appid"]
        pkg_path = os.path.join(package_dir, f"ctf_license_{appid}.vdf")
        if not os.path.exists(pkg_path):
            pkg = f'''"CTFLicenseCache"
{{
\t"AppID"\t\t"{appid}"
\t"SteamID"\t\t"76561198000000000"
\t"LicenseFlags"\t\t"15"
\t"PurchaseTime"\t\t"0"
\t"Source"\t\t"CTFLocalActivation"
}}
'''
            with open(pkg_path, 'w') as f:
                f.write(pkg)
            print(f"  [+] Wrote: ctf_license_{appid}.vdf")
        else:
            print(f"  [*] ctf_license_{appid}.vdf exists")

    # 3. Update localconfig.vdf
    # Find userdata folder
    userdata = os.path.join(steam, "userdata")
    config_targets = []
    if os.path.exists(userdata):
        for uid in os.listdir(userdata):
            cfg = os.path.join(userdata, uid, "config", "localconfig.vdf")
            if os.path.exists(cfg):
                config_targets.append(cfg)

    if not config_targets:
        # Create if not exist
        uid = "76561198000000000"
        cfg_dir = os.path.join(userdata, str(uid), "config")
        os.makedirs(cfg_dir, exist_ok=True)
        cfg = os.path.join(cfg_dir, "localconfig.vdf")
        config_targets.append(cfg)

    for cfg_path in config_targets:
        backup(cfg_path)

        if os.path.exists(cfg_path):
            with open(cfg_path, 'r') as f:
                text = f.read()
        else:
            text = ''

        if not text.strip():
            text = '''"UserLocalConfigStore"
{
\t"Software"
\t{
\t\t"Valve"
\t\t{
\t\t\t"Steam"
\t\t\t{
\t\t\t}
\t\t}
\t}
}
'''

        for app in apps:
            appid = str(app["appid"])
            marker = f'"CTF_{appid}"'
            if marker in text:
                print(f"  [*] localconfig already has AppID={appid}")
                continue

            # Find Steam section
            steam_pos = text.find('"Steam"')
            if steam_pos < 0:
                print(f"  [!] Cannot find Steam section in localconfig")
                continue

            brace_pos = text.find('{', steam_pos)
            if brace_pos < 0:
                continue

            insert = f'''
\t\t\t\t"apps"
\t\t\t\t{{
\t\t\t\t\t"{appid}"
\t\t\t\t\t{{
\t\t\t\t\t\t"Installed"\t\t"1"
\t\t\t\t\t\t"CTF_{appid}"\t\t"1"
\t\t\t\t\t}}
\t\t\t\t}}
\t\t\t\t"Licenses"
\t\t\t\t{{
\t\t\t\t\t"{appid}"\t\t"0"
\t\t\t\t}}'''
            text = text[:brace_pos+1] + insert + text[brace_pos+1:]

        with open(cfg_path, 'w') as f:
            f.write(text)
        print(f"  [+] Updated: {os.path.basename(cfg_path)}")

    print("[+] Done! Steam library should now show these games.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
