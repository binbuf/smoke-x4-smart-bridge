# 0010 — Android-only, one bridge, phone as clock source

## Status

Accepted

## Context

The MVP targets a single phone and a single bridge. The board has no
battery-backed RTC, and supporting iOS, web, desktop or multiple bridges would
multiply client, sync and identity work with no MVP user.

## Decision

Ship an Android-only app that manages one bridge per install. There is no bridge
picker or switcher; "Forget device" is the reset path. The phone sets the bridge
clock on connect. Probe identity is `P1`–`P4` and colour, with no user-editable
names, roles or tags.

## Consequences

The app stores one saved bridge connection and can use Android OS bonding and
storage APIs directly. Records made before the first clock sync are marked
estimated. Multi-bridge, iOS, web and desktop are explicitly out of scope and
require new decisions.
