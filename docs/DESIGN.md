# Design

## The idea

A hydroponics bay on an Aevoric hab ring has to feed the crew inside hard limits: a power budget for the
lights, a water tank that is recycled but never quite closed, a nutrient stock, and a clock that does not stop.
The player plants, tends and harvests; the loop is zero-waste (a harvest returns some nutrient concentrate to
the stock, and the dehumidifier returns most of the water the plants transpire).

This is the real-time cousin of the Greenhouse Bay in Aevoria Simulator, where banked water turns into food at
the press of a button. Here the food takes weeks of game time, and how well you run the bay decides how much
there is and how good it is.

## What exists

**The simulation** (`core/`, plain C++17, tested without Godot):

- **Crops** (`species.hpp`): butterhead lettuce, Cherry Belle radish, dwarf tomato, dwarf potato. Each has
  days to mature, preferred light (PPFD, umol/m2/s), a light ceiling, a temperature trapezoid, water use,
  nutrient use, yield and, for the bushes, when flowering and fruiting begin.
- **A plant** (`plant.hpp`) gets four growth factors between 0 and 1 each hour: light, temperature, water,
  nutrients. They multiply, and progress only advances in lit hours. Under ideal conditions on a 16-hour
  photoperiod a plant reaches Ready in exactly `days_to_mature` days; a test pins that down for every crop.
  Shortage of water or nutrients, or the wrong temperature, costs health (a plant with no water dies in about
  three days); good conditions let it recover. Stages: Seed, Sprout, Growing, Flowering, Fruiting, Ready,
  Overripe, Dead. A Ready crop keeps full value for a few days, loses value as it goes Overripe, and spoils
  after three times that window.
- **A bay** (`bay.hpp`) holds beds, a light schedule, LEDs with a power budget (over-demand dims every bed),
  an optional sun with a dust optical depth and a shade, a day/night temperature swing, a water tank
  (recycled at 90%), a nutrient stock, optional automatic irrigation, and an event list the game turns into
  signals. It advances in steps of at most an hour, deterministically for a given seed.
- Yield is `yield_kg x health x (0.5 + 0.5 x quality) x freshness`, where quality is the plant's average growth
  factor over its life.

**The game slice** (`godot/scenes/greenhouse.tscn`): four beds of eight slots on two benches, a grow light over
each (hung 1.55 m above the bench, clear of every crop, and faded to a ghost when it would hide a slot), a water tank, a
window onto Earth, and a crew astronaut on the walkway looking over the beds. The room is brushed steel, graphite and
aluminium with amber trim and warm-white light; blue is a small accent. Over every slot floats a **button** that says what its
plant needs next (`+` to sow, the growth percentage, Water, Feed, Harvest or Clear) and does it when pressed
(`scripts/slot_buttons.gd`; what a button says is one function of the plant and its bed, `SlotButtons.state_of`, which the tests and the
voice read too). Select a slot, sow it or the bed, water, feed, harvest, clear. HUD: day and clock, temperature, power, water,
nutrient stock, harvest totals, LED brightness, automatic irrigation, time controls from pause to 64x, Ask crew and How to play.

**The crew voice** (`scripts/crew_voice.gd`) turns the same states into words: what to do next (in this order: a harvest waiting, a dead
plant, a dry bed, a hungry bed, the water and nutrient stores, the power budget, news, empty slots, a round of the plants), a
description of whatever is selected, and an answer to Ask crew. It is spoken by the operating system's text-to-speech and
captioned, and the astronaut looks at what it is talking about. **The training** (`scenes/training.tscn`, `scripts/training.gd`) hosts the
real game with a coach panel and plays it through in six lessons (sow, grow, dry, harvest, select, ask), using the same helpers
(`scripts/training_driver.gd`) as the test that drives the real scene through those steps (`tests/crew_ui_test.gd`).

## What does not exist yet

Crew food demand and a reason to grow one crop over another (the astronaut is the first crew member to be given
one), equipment faults and events, a save file, sound effects and music (the crew speaks, but nothing else makes a noise), and any tuning beyond a first guess. The Blender-modelled props do exist (planter, light, tank, crate and wall
panel; see [GRAPHICS_GUIDE.md](GRAPHICS_GUIDE.md)). The Mars version lives in its own repository, started as a
copy of this core, and adds a sun, dust storms and a shade to the LEDs; the two share no library yet.

## Numbers are placeholders

All crop and equipment numbers are design values, chosen to sit inside the ranges used in controlled-environment
growing. They have not been validated and are meant to be changed while playing. The model, not the numbers, is
what the tests guarantee.
