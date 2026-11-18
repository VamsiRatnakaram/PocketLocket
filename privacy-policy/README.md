# PocketLocket privacy policy page

Static page for the **Privacy Policy URL** that App Store Connect requires.
The text mirrors the in-app policy in
`ios/PocketLocket/Features/Settings/PrivacyPolicyView.swift` — if you edit one,
edit both.

## Published from this repo via GitHub Pages (already enabled)

The site is served straight from the `main` branch of
`https://github.com/VamsiRatnakaram/PocketLocket` — no separate site repo.

- Source: **Settings → Pages → Build and deployment → Deploy from a branch** →
  branch `main`, folder **`/ (root)`**. A `.nojekyll` file at the repo root
  makes Pages serve these files as-is (no Jekyll processing).
- Live URLs (note the `/privacy-policy/` path — the folder name is part of the
  URL when deploying from root):
  - Privacy policy: `https://vamsiratnakaram.github.io/PocketLocket/privacy-policy/`
  - Support page: `https://vamsiratnakaram.github.io/PocketLocket/privacy-policy/support.html`

Pushes to this folder republish automatically (~1 minute).

Use those HTTPS URLs for the **Privacy Policy URL** and **Support URL** fields
in App Store Connect (ASC allows the same URL for both, but the support page
above is nicer).

## Before submitting

- Open the live URL in a plain browser window (no login) and confirm it
  renders — Apple checks reachability.
- If you change the in-app policy later, republish this page so the two never
  drift apart.
