# PocketLocket privacy policy page

Static page for the **Privacy Policy URL** that App Store Connect requires.
The text mirrors the in-app policy in
`ios/PocketLocket/Features/Settings/PrivacyPolicyView.swift` — if you edit one,
edit both.

## Published from this repo via GitHub Pages

The site is served straight from the `main` branch of
`https://github.com/VamsiRatnakaram/PocketLocket` — no separate site repo.

1. In the repo: **Settings → Pages → Build and deployment → Source: Deploy
   from a branch** → branch `main`, folder **`/privacy-policy`** → Save.
2. After a minute the pages are live at:
   - Privacy policy: `https://vamsiratnakaram.github.io/PocketLocket/`
   - Support page: `https://vamsiratnakaram.github.io/PocketLocket/support.html`

If Pages is not yet enabled, do the two clicks above; pushes to
`privacy-policy/` then republish automatically.

Use those HTTPS URLs for the **Privacy Policy URL** and **Support URL** fields
in App Store Connect (ASC allows the same URL for both, but the support page
above is nicer).

## Before submitting

- Open the live URL in a plain browser window (no login) and confirm it
  renders — Apple checks reachability.
- If you change the in-app policy later, republish this page so the two never
  drift apart.
