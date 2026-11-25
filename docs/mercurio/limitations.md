# What this Mercurio build cannot do yet

Mercurio for iOS, version 0.1.15 (28). This is the list to read before you rely on a build. The gaps below are known.

## Notifications

Push notifications do not work yet.

Apple delivers a push only for the team and bundle id that own the APNs key, and Mercurio ships no relay. A build you sign yourself therefore gets no push until you also run a copy of `relay/` with your own APNs key (see `relay/README.md`).

Settings includes a Custom Push Relay field. Leave it blank unless you run your own relay. Mercurio refuses the upstream Heeler relay on purpose, so the per-host notification switches stay off until you enter a relay of your own.

The needs-you bubble on the Agents list does not use push. It works while the app is open and connected.

## Pairing

The setup command is `herdr plugin action invoke heeler.pair`. That name is the plugin id. It is the right command. The install line uses this repository, `Ormus-Solutions/mercurio-ios/plugin`.

A herdr session name can use letters, digits, dots, underscores, and hyphens, up to 64 characters. Leave it blank for the default session.

## Windows hosts

Mercurio can connect to a native Windows host. Chat, Skills, Changes, file and image uploads, and notification registration are not available on Windows yet. The screen says so when you open one of those.

## Agent questions

Answer these in the terminal. Mercurio will say it cannot do them:

- Claude questions that include previews
- Codex questions that use Other
- Oh My Pi questions

Codex can stay on "Waiting for Conversation" with Codex CLI 0.161.0, herdr 0.9.3, and integration v8. Start that pane with `codex --no-daemon`. Mercurio does not add that flag for you.

## Links

Choosing a link asks whether to open it in Mercurio or in the browser. On a phone, a loopback address (`localhost`, `127.0.0.1`) tunnels to the computer. On the simulator it opens directly. Any other address loads as written.

## Networks

A second ZeroTier network saved with a different identity will not connect until you quit Mercurio and open it again. The error tells you to do that.

If the app is suspended while you are signing in to Tailscale in the browser, you come back to Needs sign-in. Tap Sign In again.

## iPad

In a narrow window, opening a Host or a Settings page and then widening the window returns you to that list. The page you had pushed is not kept.
