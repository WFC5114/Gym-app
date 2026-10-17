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

## If Sideloadly can't sign in

"GSA returned a non-plist response (HTTP 503)" means Apple's desktop sign-in
server (gsa.apple.com) refused the login; the app file is fine. If you can
sign in at appleid.apple.com but not in iTunes or Sideloadly, the block is on
the PC or network. Try, in order:

1. Test the line: in PowerShell run
   `curl.exe -k -sS -o NUL -w "%{http_code}" https://gsa.apple.com/grandslam/GsService2/lookup`.
   **401** (repeatably) means Apple's sign-in server is reachable. "Could not
   connect" or a mix of failures means your connection filters it: install
   Proton VPN (free plan; Stealth protocol if it won't connect), connect, check
   for 401, then run Sideloadly or AltServer with the VPN on. (On Wei's PC,
   16 Oct 2026, the line failed on home and hotspot and gave 401 via Proton.)
2. Run the PC off the phone's hotspot and press Start again.
3. Windows Settings > Time & language: turn on "Set time automatically".
4. Turn off any proxy or antivirus HTTPS/web scanning (or pause it).
5. Update Sideloadly, and reinstall iTunes and iCloud from apple.com (not the
   Microsoft Store).
6. Still failing: Apple may have paused desktop sign-ins after several failed
   tries. Wait a few hours and try once.

The alternative is AltStore (also free, also 7 days), or a paid Apple
Developer account and TestFlight, which needs no PC sign-in at all.
