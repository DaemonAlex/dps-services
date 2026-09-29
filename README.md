# dps-services

**City Services** is one app on the lb-phone and the lb-tablet. A player stands
next to a vehicle, asks for a tow, and follows it live: place in line, driver
accepted, time to arrival, arrived, hooked, delivered.

It is a view. `dps-towjob` owns the queue, the price, the order and the state.
This resource forwards a request and shows what comes back.

## Who can do what

| Player | Can request |
|---|---|
| Anyone | Repair tow, $200, charged when the vehicle is hooked |
| Police, EMS, fire, on duty | Impound tow, no fee, goes to the front of the line |
| Tow driver | Sees a Driver tab: current offer (accept or decline) and current job |

If no tow driver is on duty, or nobody accepts within three minutes, City Tow
takes the request.

A request can be called off while it is in line or while the driver is on the
way. Once the driver has reached the vehicle it is too late. The fee is only
taken when the vehicle is hooked, and it is given back if the tow then does not
happen; the app says which. A finished request stays on screen until Done is
pressed, so the place the vehicle went can be read.

## How it connects

    page --fetch--> client/main.lua --lib.callback--> server/main.lua --export--> dps-towjob
    dps-towjob --event--> server/main.lua --net event--> client/main.lua --SendCustomAppMessage--> page

## Requires

| | |
|---|---|
| `ox_lib` | callbacks, closest-vehicle lookup |
| `qbx_core` | the player, their job, and the vehicle registry the model name comes from |
| `lb-phone` | hosts the app on the phone |
| `lb-tablet` | hosts the app on the tablet, through one entry in its `Config.CustomApps` |
| `dps-towjob` 2.9.0 or newer | the queue; a soft dependency, checked at every call |
| `jg-vehiclestudio` | optional: the vehicle photo on the scan and status cards. Without it the cards show no picture. |

## Tablet entry

Add to `Config.CustomApps` in `lb-tablet/config/config.lua`:

    {
        identifier = 'dps_services',
        name = 'City Services',
        description = 'Call a tow and follow it to your door',
        developer = 'City of Del Perro Sands',
        size = 96,
        defaultApp = true,
        ui = 'https://cfx-nui-dps-services/ui/index.html',
    },

## Sharp edges

- The page runs inside the phone's or tablet's frame. `GetParentResourceName()`
  returns `lb-phone` or `lb-tablet` there, so the fetch address is written out
  as `https://dps-services/`. Do not change it.
- Relative paths do not resolve from that frame. The page is one file with its
  styles and scripts inside it.
- Updates reach the page through `SendCustomAppMessage`, never `SendNUIMessage`.
  The tablet only keeps the page alive while the app is open, so the page asks
  for its state every time it loads.
- Never use `backdrop-filter`. The game's browser paints it as a black square.

## Server console

| Command | Description |
|---|---|
| `servicesdebug` | One line proving the app can reach the tow script: the tow resource name, its state, the repair and impound fees and the scan range. Refuses any caller but the console. |

## Tests

    lua5.4 tests/run.lua
