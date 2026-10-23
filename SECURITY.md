# Security policy

SideSeat lets someone outside the device see and operate an app, so security reports are taken seriously.

## Reporting a vulnerability

Please don't open a public issue. Report it privately through GitHub's **Security › Report a vulnerability** on this repository.

Include what you found, the steps to reproduce it, and the impact you expect. You'll get an acknowledgement within 3 working days and an update at least every 7 days until it's resolved. Once a fix is released, you'll be credited in the release notes unless you'd rather not be.

## Supported versions

Only the latest release gets security fixes while SideSeat is below 1.0.

## In scope

- Anything that lets an agent see or control the app without the user's consent, or after they've ended the session or switched to view-only
- Masked or secure content leaving the device unmasked
- Agent input reaching views or actions it shouldn't (for example, bypassing an `inputInterceptor`)
- Session codes that can be guessed or reused within the library's own handling

## Out of scope

- The reference relay and console in `Examples/Relay`. They're for local development and intentionally have no agent authentication, rate limiting or TLS. See "Before you ship it" in the README.
- Content an app chooses not to mask
- Issues that need a jailbroken device or a debugger attached to the app
