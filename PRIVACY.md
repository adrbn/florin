# Privacy Policy — Florin

_Last updated: 3 September 2026_

Florin is a personal finance app. It is built so that the person who wrote it
cannot see your money.

## What we collect

**Nothing.**

Florin has no server of ours behind it, no account to create, no analytics, no
crash reporting, no advertising identifiers, and no third-party SDKs that phone
home. There is no "we" that receives your data, because there is no service to
receive it.

## Where your data lives

Everything Florin knows — your accounts, balances, transactions, categories,
budgets and holdings — is stored in a single database file inside the app's own
container on your device.

That file is included in your device backup, so if you have iCloud Backup turned
on, an encrypted copy travels with the rest of your phone. That copy is between
you and Apple; it is not readable by us.

You can export the file at any time from **Settings → Data**, and import it into
Florin on another device.

## Connections Florin makes

Florin talks to the network only where you tell it to, and always directly:

- **Your bank, through Enable Banking (PSD2).** Optional. It works only after
  you register your own application with Enable Banking and supply your own
  credentials, which are stored on your device. The connection is between your
  device, Enable Banking and your bank. Your statements are written straight to
  the local file. Enable Banking's own handling of that data is governed by
  their terms, which you accept when you register with them.
- **Your own Florin server.** Optional. If you self-host the web version, the
  app can read from and write to that server. It is your machine.

If you use neither, Florin makes no network connections at all beyond what iOS
does on its own.

## Face ID

If you turn on the app lock, Florin asks iOS to verify you. iOS answers yes or
no. Your biometrics never reach the app.

## Children

Florin is not directed at children and collects nothing from anyone.

## Changes

Any change to this policy will be committed to the repository, where its history
is public: <https://github.com/adrbn/florin>

## Contact

Open an issue at <https://github.com/adrbn/florin/issues>.
