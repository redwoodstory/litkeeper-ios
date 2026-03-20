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

## Accessing from Outside Your LAN via Pangolin

The app has built-in support for [Pangolin](https://github.com/fosrl/pangolin) reverse proxy authentication. When your LitKeeper server is behind Pangolin, configure your access tokens under **Settings → Server → Pangolin Access Control**:

- **Token ID** — the value for the `P-Access-Token-Id` header
- **Token** — the value for the `P-Access-Token` header

Find these under **Share Link** in the Pangolin dashboard. Leave both fields blank for direct LAN access — the headers are omitted when empty.

> These Pangolin credentials and the LitKeeper API token serve different purposes and are both required for external access. See the [server security docs](https://github.com/redwoodstory/LitKeeper?tab=readme-ov-file#security) for an explanation of the full auth model.

## Security

**Biometric Lock** — enable under **Settings → Security** to lock the app whenever it moves to the background. Face ID or Touch ID is used to unlock.

The app does not participate in the server's PIN lock system. The server PIN lock applies only to browser sessions; Bearer-token-authenticated API requests (which the app uses) bypass it automatically.

## Local Storage

Downloaded stories are stored in the app's Documents directory and tracked locally with SwiftData. Clearing downloads from **Settings → Local Storage** removes files from the device only — your library on the server is unaffected.
