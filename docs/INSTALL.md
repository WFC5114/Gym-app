# Installing GYM on your iPhone (from Windows)

There is no Mac in this project, so the app is built by GitHub Actions and
installed with **Sideloadly**, which signs it with your own Apple ID.

## You need

- The Windows PC, the iPhone and its USB cable.
- **iTunes and iCloud for Windows, the versions downloaded from apple.com**
  (not the Microsoft Store ones). Sideloadly needs their drivers.
- [Sideloadly](https://sideloadly.io) installed.
- `GymApp.ipa`: from the project files (`builds/`), or from the latest green
  **CI** run on GitHub (Actions > CI > the run > Artifacts > `GymApp-ipa`,
  unzip it).

## Steps

1. Plug the iPhone in, unlock it and tap **Trust** on the phone.
2. Open Sideloadly. Your iPhone appears in the device list.
3. Drag `GymApp.ipa` onto Sideloadly.
4. Type your Apple ID email and press **Start**. Enter the password and the
   two-factor code when asked. (Sideloadly signs the app with it; the
   password goes to Apple only.)
5. On the iPhone: **Settings > Privacy & Security > Developer Mode**, turn it
   on and restart when asked (only the first time).
6. **Settings > General > VPN & Device Management**, tap your Apple ID and
   **Trust**.
7. Open GYM. Allow Apple Health when it asks: that is where your weight and
   InBody scans come from.

## Good to know

- **Free Apple ID: the app stops opening after 7 days.** Plug in and press
  Start again in Sideloadly; your logged food and rests stay (installing over
  the top keeps the app's data). A paid Apple Developer account
  (US$99 a year) makes it last a year.
- **Not yet tried on a real phone** (as of 15 Oct 2026): Health reading, data
  kept between launches, the Dynamic Island rest timer, sound, haptics and
  the sand and jar physics have only run in the CI simulator. If Health or
  the widgets don't show up, a free Apple ID may be signing without those
  permissions; tell Claude what you see.
- BODY shows labelled **SAMPLE DATA** until Health has a weight in it.
- Data stays on the phone. The only network calls are food lookups (Open Food
  Facts).
