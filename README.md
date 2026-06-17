# LitKeeper for iOS

A native SwiftUI companion app for [LitKeeper](https://github.com/redwoodstory/LitKeeper). Browse your library, manage the download queue, and read stories offline.

## Requirements

- iOS 17 or later
- A running LitKeeper server instance

## Setup

### 1. Generate an API token

On your LitKeeper server, set `LITKEEPER_API_TOKEN` to a secret string in your `.env` or `docker-compose.yml`:

```
LITKEEPER_API_TOKEN=your-secret-token-here
```

Restart the server after adding it. This token is required — the iOS app uses it to authenticate all API requests.

### 2. Connect the app

Open **Settings → Server & Token** and enter:

- **Server URL** — the base URL of your LitKeeper instance (e.g. `http://192.168.1.10:5017`)
- **API Token** — the value of `LITKEEPER_API_TOKEN` from your server

Tap **Test Connection** to verify. The token is stored in the device Keychain.

## Accessing from Outside Your LAN

The app supports optional proxy credentials for reverse proxies that gate access to your LitKeeper server. Enter them under **Settings → Server → Proxy Authentication**.

The proxy credentials and the LitKeeper API token serve different purposes: the proxy credentials authenticate at the network edge; the API token authenticates to the LitKeeper server itself. Both are required for external access; leave the proxy fields blank for direct LAN access.

### Pangolin Setup

If you're using [Pangolin](https://docs.pangolin.net) as your tunnel/reverse proxy, use a **Share Link** to authenticate the iOS app:

1. In the Pangolin admin panel, open your resource and go to **Share Links**
2. Create a new share link — copy the **Token ID** and **Token Secret**
3. In the iOS app under **Settings → Server → Proxy Authentication**, enter:
   - **Access Token ID** — the Token ID (e.g. `bu8ji397`)
   - **Access Token Secret** — the Token Secret

The app sends these as `P-Access-Token-Id` and `P-Access-Token` headers on every request. No browser login or session management required.

## Security

**Biometric Lock** — enable under **Settings → Security** to lock the app whenever it moves to the background. Face ID or Touch ID is used to unlock.

The app does not participate in the server's PIN lock system. The server PIN lock applies only to browser sessions; API requests (authenticated via `X-Api-Key`) bypass it automatically.

## Local Storage

Downloaded stories are stored in the app's Documents directory and tracked locally with SwiftData. Clearing downloads from **Settings → Local Storage** removes files from the device only — your library on the server is unaffected.
