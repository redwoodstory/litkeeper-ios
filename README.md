# LitKeeper for iOS

A native SwiftUI companion app for [LitKeeper](../LitKeeper/README.md). Browse your library, manage the download queue, and read stories offline.

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

When accessing LitKeeper through a reverse proxy (e.g. Pangolin) from outside your LAN, the proxy may require additional authentication headers on each request.

Configure these under **Settings → Server & Token → External Proxy**:

- **Header 1 Name / Value** — first proxy auth header
- **Header 2 Name / Value** — optional second header

For **Pangolin**, use:

| Field | Value |
|-------|-------|
| Header 1 Name | `P-Access-Token-Id` |
| Header 1 Value | your Pangolin token ID |
| Header 2 Name | `P-Access-Token` |
| Header 2 Value | your Pangolin token secret |

These headers are sent on every request when configured. Leave them blank for direct LAN access — they are not sent when empty.

> The proxy headers and the API token serve different purposes and are both required for external access. See the [server security docs](../LitKeeper/README.md#security) for an explanation of the full auth model.

## Security

**Biometric Lock** — enable under **Settings → Security** to lock the app whenever it moves to the background. Face ID or Touch ID (with passcode fallback) is used to unlock.

The app does not participate in the server's PIN lock system. The server PIN lock applies only to browser sessions; Bearer-token-authenticated API requests (which the app uses) bypass it automatically.

## Local Storage

Downloaded stories are stored in the app's Documents directory and tracked locally with SwiftData. Clearing downloads from **Settings → Local Storage** removes files from the device only — your library on the server is unaffected.
