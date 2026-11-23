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
captioned, and the astronaut looks at what it is talking about. The player can pick a male or a female voice (the gender is read from a voice's name, and only the
genders the PC has a voice for are offered). **The training** (`scenes/training.tscn`, `scripts/training.gd`) hosts the
real game with a coach panel and plays it through in six lessons (sow, grow, dry, harvest, select, ask), using the same helpers
(`scripts/training_driver.gd`) as the test that drives the real scene through those steps (`tests/crew_ui_test.gd`).

## The colony: food, hunger, three endings, a score

The bay feeds a colony (`core/colony.hpp`, started with `start_colony(difficulty)`; without one the bay is a sandbox). Food is counted in kcal: each crop has
its energy per kilo in `species.hpp` (lettuce 150, radish 160, tomato 180, potato 770), a harvest adds `kg x kcal_per_kg` to the colony's store, and the
crew eats its day's need a little every hour. With the store empty the crew goes hungry, and a hungry spell ends the moment it eats in full again; hungry
for the whole grace period and the colony fails; kept fed for the goal period and it succeeds.

| | Easy | Intermediate | Difficult |
|---|---|---|---|
| Crew | 4 | 8 | 12 |
| Food asked of the bay | 24 kcal a day | 50 | 66 |
| Food in store at the start | 100 days | 60 | 95 |
| Hungry days before it fails | 14 | 10 | 7 |
| Days to keep them fed | 120 | 200 | 300 |
| If it fails | all evacuated home: failed | half taken home, half lost: failed | nowhere to go: extinct |
| Score multiplier | x1 | x1.5 | x2 |

**Every number here is a design value.** One bay of 32 plants grows only 30 to 80 kcal a day (a person eats 2,500), so the colony asks the bay for a
fresh-food share scaled to what it can grow, and the rest of the diet is imagined to come from elsewhere. `tests/test_colony.cpp` plays simple strategies
against each mode and pins down who wins. On the station: doing nothing fails every mode (on days 114, 70 and 102); on Easy any farming wins; on
Intermediate all lettuce fails and two beds of lettuce with two of potato win; on Difficult potatoes are essential (the first harvest is on day 105) and
so is lettuce to carry the colony until then (one bed of lettuce and three of potato win). However large a reserve a game asks for, it is cut so that the
food runs out `kMinFailureMarginDays` before the goal: a colony that grows nothing always fails. A game whose bay grows less scales the colony with `demand_scale` and `reserve_scale` (the Mars dome does: see [mars-farming](https://github.com/Overby-Industries/mars-farming)).

**The score** (`Colony::score()`, shown live and ranked on the leaderboard): 3 points for each day the colony has lasted, 0.5 for each kcal grown, 150 for each
different crop harvested, 10 for each day of food in store (up to 60), 1,000 for making it, less 40 for each plant lost and 25 for each hungry day, times the
mode's multiplier, never below zero. The strategies above score about 3,500 for a win on Easy, 7,000 on Intermediate and 17,000 to 19,000 on Difficult.

**The leaderboard** (`scripts/leaderboard.gd`): the ten best runs for each mode, in `user://leaderboard.json` on this PC only; nothing is sent anywhere. An
online board would need a server to send scores to, and `submit()` and `entries()` are all the game calls.

## What does not exist yet

Equipment faults and events, an online leaderboard, a save file, sound effects and music (the crew speaks, but nothing else makes a noise), and any tuning beyond a first guess. The Blender-modelled props do exist (planter, light, tank, crate and wall
panel; see [GRAPHICS_GUIDE.md](GRAPHICS_GUIDE.md)). The Mars version lives in its own repository, started as a
copy of this core, and adds a sun, dust storms and a shade to the LEDs; the two share no library yet.

## Numbers are placeholders

All crop and equipment numbers are design values, chosen to sit inside the ranges used in controlled-environment
growing. They have not been validated and are meant to be changed while playing. The model, not the numbers, is
what the tests guarantee.
