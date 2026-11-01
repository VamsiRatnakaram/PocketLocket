# PocketLocket privacy policy page

Static page for the **Privacy Policy URL** that App Store Connect requires.
The text mirrors the in-app policy in
`ios/PocketLocket/Features/Settings/PrivacyPolicyView.swift` — if you edit one,
edit both.

## Publish with GitHub Pages (free, ~2 minutes)

1. Create a **public** GitHub repo, e.g. `pocketlocket-site`.
2. Copy `index.html` to the repo root (or keep the folder and enable Pages on
   `/privacy-policy`).
3. Push, then in the repo: **Settings → Pages → Source: Deploy from a branch →
   `main` / `(root)` → Save**.
4. After a minute your URL is live at:
   `https://<your-github-username>.github.io/pocketlocket-site/`

Use that HTTPS URL for both the **Privacy Policy URL** and (if you like) the
**Support URL** fields in App Store Connect.

## Support page

`support.html` is already written and ships alongside `index.html`, so the
**Support URL** can be `https://<user>.github.io/<repo>/support.html` — or
simply reuse the policy URL for both fields.

## Before submitting

- Open the live URL in a plain browser window (no login) and confirm it
  renders — Apple checks reachability.
- If you change the in-app policy later, republish this page so the two never
  drift apart.
