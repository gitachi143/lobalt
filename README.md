# Lobalt

A timeboxing timer for macOS. You give yourself a length of time, and Lobalt
keeps that number in front of you — quietly — until it runs out.

![Lobalt, caught on the beat](docs/fullscreen-pulse.png)

## The idea

Most timers only speak up twice: when you start them and when they go off. In
between you either stare at the clock or forget it exists.

On every whole minute Lobalt hits. The entire surface floods red in about
forty milliseconds, the controls swell and pick up a red halo, the corner
overlay grows by a tenth, and then it all cools back down over the next couple
of seconds. The shape matters more than
the colour: an instant attack, a hard drop off the peak, then a long afterglow.
A symmetrical swell would read as a slow throb, and a plain fade would be gone
before you had looked up.

The digits don't join in — they heat *past* red into white-hot, so the one
thing you actually need to read stays readable while everything behind it goes
crimson.

It presses harder over the last five minutes, and harder still once you're past
your estimate. Turn it down, or off, in Settings. The rest of the time it just
sits there being a timer.

![Lobalt between beats](docs/fullscreen-calm.png)

Full screen gives the ring the whole display, and the controls fade out after a
few seconds until you move the mouse.

## Where it lives

Whenever the Lobalt window isn't the thing you're looking at, a small pill parks
itself in the corner of the screen. It floats above everything, including other
apps in full screen, and never takes focus away from your work.

![The corner overlay](docs/overlay-calm.png)
![The corner overlay, mid-pulse](docs/overlay-pulse.png)

Hover it for controls — pause, add five minutes, stop, microphone — so you can
adjust the timer without leaving the app you're in. Drag it anywhere you like;
it stays there.

## Saying what you want

Press the microphone (or `⌃⌥⌘V` from any app) and say it in plain words.
Recognition runs on-device wherever the hardware supports it, so it works
offline and nothing is sent anywhere.

| You say | You get |
| --- | --- |
| "twenty five minutes to write the essay" | 25:00, labelled *Write the essay* |
| "half an hour" | 30:00 |
| "an hour and a half on the deck" | 1:30:00, labelled *Deck* |
| "ninety seconds" | 1:30 |
| "until 3pm" | however long that is from now |
| "pomodoro" | 25:00 |
| "add five minutes" | extends whatever is running |
| "pause" / "resume" / "stop" / "start over" | does that |

Everything above also works typed, in the field at the bottom of the window —
`25m write the essay`, `1h30 deep work`, `45`. A live read-back shows what it
understood before you commit.

## The rest of it

- **Counts past zero.** When time is up it keeps going in red, so you find out
  you ran eleven minutes over instead of guessing. The ring refills as the
  overrun accrues — a full second lap means you took twice as long as you gave
  yourself.
- **Learns how you estimate.** Every session is logged, and the history window
  tells you whether you habitually run over or under.
  ![Overtime](docs/main-overtime.png)
- **Menu bar countdown**, with a popover holding the full set of controls.
  ![Menu bar popover](docs/menu-panel.png)
- **Full screen** for when you want nothing else on the display. The controls
  fade out after a few seconds and come back when you move the mouse.
- Optional: keep the display awake while timing, launch at login, hide the Dock
  icon and live in the menu bar alone.
- Honours Reduce Motion — the glow stays, the movement goes.

## Driving it from elsewhere

Lobalt registers a `lobalt://` scheme, so Shortcuts, Raycast, a keyboard-macro
app or a shell script can start timers:

```sh
open "lobalt://start?q=25m%20write%20the%20essay"   # anything the text field takes
open "lobalt://start?m=45"                          # or just minutes
open "lobalt://add?m=5"
open "lobalt://pause"    # also resume, toggle, stop, restart, show
```

Transport only, deliberately: any web page can fire a URL scheme, so there is
no link here that opens the microphone or touches the filesystem.

## Install

Requires macOS 14 or later.

```sh
git clone https://github.com/gitachi143/lobalt.git
cd lobalt
./Scripts/build-app.sh --install
```

That produces a universal (Apple silicon + Intel) `Lobalt.app` and copies it to
`/Applications`. Pass a directory to put it somewhere else
(`--install ~/Desktop`), or leave off `--install` to just build into `./build`.

The build is signed ad-hoc rather than with a Developer ID, so the first launch
needs the usual right-click → **Open**. Microphone and speech-recognition
permission are requested the first time you press the microphone, not at launch.

## Shortcuts

System-wide (no Accessibility permission needed):

| | |
| --- | --- |
| `⌃⌥⌘T` | start / pause |
| `⌃⌥⌘V` | speak a timer |
| `⌃⌥⌘P` | bring up the window |

In the window: `Space` start/pause · `⌘D` speak · `⌘.` stop · `⌘R` run again ·
`⌘⇧+` add five minutes · `⌃⌘F` full screen.

## Development

```sh
swift build          # build
swift test           # unit tests for the parser, timer maths and history
./Scripts/build-app.sh   # assemble Lobalt.app
```

Two developer flags on the built binary, both of which run against throwaway
preferences and a throwaway session log rather than your real ones:

```sh
./.build/debug/Lobalt --selftest         # runtime checks: panel placement, window
                                        # lifecycle, menu bar, ticking, parsing
./.build/debug/Lobalt --snapshot ./docs  # re-render the interface images
```

Layout:

- `Sources/LobaltKit` — the parts with no UI in them: the natural-language
  parser, the timer state machine, the session log. This is what the tests
  cover.
- `Sources/Lobalt` — the app: SwiftUI views, the floating panel, the menu bar
  item, speech, global hot keys.

The timer derives its remaining time from a wall-clock deadline rather than
counting ticks, so it stays correct across sleep, app nap and a shut lid. Ticks
only exist to refresh the display, and the tick rate follows what's actually
visible — 60 Hz for the couple of seconds a pulse takes to hit and fade, and
a lazy 0.2 s the rest of the time.

## Licence

MIT.
