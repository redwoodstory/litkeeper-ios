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

The app supports an optional proxy token for reverse proxies that gate access to your LitKeeper server. Enter the token value under **Settings → Server → Proxy Authentication**.

The app sends this value as the `X-Auth-Token` header on every request alongside your LitKeeper API token (sent as `X-Api-Key`). Leave the field blank for direct LAN access — the header is omitted when empty.

> Both tokens are required for external access: the proxy token authenticates at the network edge; the API token authenticates to the LitKeeper server itself.

### Pangolin Setup

If you're using [Pangolin](https://docs.pangolin.net) as your tunnel/reverse proxy, configure **Header Authentication** on your resource as follows:

| Field | Value |
|-------|-------|
| Header Name | `X-Auth-Token` |
| Expected Value | any secret string you choose (e.g. a UUID) |
| Force 401 Unauthorized | **Enabled** |

Enabling "Force 401" is required for API clients. Without it, Pangolin responds to unauthenticated requests with a browser redirect instead of a 401, which breaks non-browser clients.

Enter the same secret string in the app under **Settings → Server → Proxy Authentication Token**.

## Security

**Biometric Lock** — enable under **Settings → Security** to lock the app whenever it moves to the background. Face ID or Touch ID is used to unlock.

The app does not participate in the server's PIN lock system. The server PIN lock applies only to browser sessions; API requests (which the app uses) bypass it automatically.

## Local Storage

Downloaded stories are stored in the app's Documents directory and tracked locally with SwiftData. Clearing downloads from **Settings → Local Storage** removes files from the device only — your library on the server is unaffected.
