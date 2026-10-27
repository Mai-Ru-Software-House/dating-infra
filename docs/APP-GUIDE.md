# Mai Ru app guide

How to install the Mai Ru app on a phone and use it against a Mai Ru server. The server
side is in the main [README](../README.md).

## What you need

- A running Mai Ru server and its address (your team gives you this, for example `http://192.168.1.20`).
- A phone that can reach that address: on the same Wi-Fi, over Tailscale, or through a public address.
- **Android:** Android 7.0 or later, and the release file `mai-ru-1.0.0.apk`.
- **iPhone:** iOS 16.4 or later and the free **Expo Go** app from the App Store. There is no signed iOS build.

## Android: install the APK

1. Download `mai-ru-1.0.0.apk` to the phone from the dating-frontend GitHub Release.
2. Open the file. Android asks to allow installs from this source (your browser or file manager): allow it, then tap **Install**.
3. Open **Mai Ru**.

The app is built for one server address. If the address of the server changes, the app has to be rebuilt.

## iPhone: use Expo Go

1. Install **Expo Go** from the App Store.
2. Ask the team to start the app for your server (from the dating-frontend repository, with `EXPO_PUBLIC_API_BASE_URL=http://<server>/api/v1` and `EXPO_PUBLIC_USE_MOCKS=0`, then `npx expo start`).
3. Scan the QR code it shows with the iPhone camera and open it in Expo Go. The iPhone must reach both that computer and the server.

## First use

1. **Allow permissions** when asked:
   - **Location**: used to find people near you and to show your place name.
   - **Photos**: used to choose your profile picture.
2. Tap **Sign up**, fill in your profile, add a photo and finish. You are logged in.
3. Next time, use **Log in** with the account you made. The app keeps you logged in.

## If something goes wrong

| Problem | What to try |
|---|---|
| "Network error" or nothing loads | Open `http://<server>/api/v1/health` in the phone's browser. If that fails, the phone cannot reach the server: check Wi-Fi or Tailscale. |
| Android blocks the install | Allow "Install unknown apps" for the app you opened the file from, then open the file again. |
| No people in your recommendations | You need other accounts near you that match each other's age, gender and distance settings. |
| Photos or location do not work | Phone Settings > Apps > Mai Ru > Permissions, and allow Location and Photos. |
