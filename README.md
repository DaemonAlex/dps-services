# dps-services

**City Services** is one app on the lb-phone and the lb-tablet. A player stands
next to a vehicle, asks for a tow, and follows it live: place in line, driver
accepted, time to arrival, arrived, hooked, delivered.

It is a view. `dps-towjob` owns the queue, the price, the order and the state.
This resource forwards a request and shows what comes back.

## What it is for

A player with a dead car used to have to find a tow driver by voice or by luck. They had no way
to know if anyone was coming. This app lets them ask from the phone and watch the tow arrive
step by step. It also gives the city one place to take the test for a work licence, so staff do
not have to hand licences out.

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

## Licences

The app has a Licences tab. A player reads the study guide, takes a multiple choice test, and
pays from the bank to get the licence. This part is decided here, not in `dps-towjob`.

| Group | Licences |
|---|---|
| Commercial | Commercial B, Commercial A, Tow, Hazmat, Passenger |
| Passenger | Taxi, Chauffeur |
| Pilot | Private Pilot, Commercial Pilot, Airline Transport Pilot, Helicopter |

- Every licence needs a driver licence first. Some need another licence first. Tow needs
  Commercial B or A. Hazmat needs Commercial A and trucker level 8.
- A failed test can be taken again after 30 minutes.
- The answers stay on the server. The page only gets the questions.
- The licence is saved in the character's Qbox metadata (`licences.<id> = true`), next to the
  driver and weapon licences.
- Other scripts can check a licence with the server exports
  `exports['dps-services']:HasLicence(source, id)` and `HasLicences(source, ids)`. Commercial A
  also counts as Commercial B.

Fees, question counts and pass marks are in `config_licences.lua`. The questions are in
`server/banks/`, one file per licence.

## How it connects

    page --fetch--> client/main.lua --lib.callback--> server/main.lua --export--> dps-towjob
    dps-towjob --event--> server/main.lua --net event--> client/main.lua --SendCustomAppMessage--> page

## On its own, and with other scripts

**On its own.** The app needs `lb-phone` to show at all, so there is no version with free
scripts only. With `ox_lib`, `oxmysql`, `qbx_core` and `lb-phone`, the app opens and the Licences
tab works in full. The tow tab says the service is offline until `dps-towjob` is running.

**With a paid phone and tablet (lb-phone, lb-tablet).** The app sits on the home screen of both.
Each step of a tow also arrives as a phone notification. If the phone cannot take it, the player
gets a normal on-screen notice. The script uses the public custom app exports only, so a phone or
tablet update does not break it. It adds the app again when `lb-phone` restarts.

**With [dps-towjob](https://github.com/DaemonAlex/dps-towjob).** This is what makes the tow tab
work. The player stands by a vehicle, picks it, and sends the request. `dps-towjob` runs the
queue, the price and the driver offers. The app shows the place in line, the driver, the time to
arrival, hooked and delivered. Tow drivers get a Driver tab to accept or decline. `dps-towjob` is
checked at every call, so it can restart without the app dropping off the phone.

**With a paid vehicle image script (jg-vehiclestudio).** The scan and status cards show a photo
of the vehicle. The script only reads the photo list. Without it the cards have no picture and
everything else works.

**With a paid trucker script (m-TruckerSimulator).** The Hazmat licence needs trucker level 8,
read from the trucker script's `trucker_players` table. A driver who takes a hazardous load
(Explosives, Compressed Gas, Fuel) with no Hazmat licence gets a warning. When they deliver it,
the pay is taken back. This needs two DPS lines in the trucker script's open
`server/sv_webhooks.lua` that fire `dps-services:trucker:jobAccepted` and
`dps-services:trucker:jobCompleted`. Put those two lines back after you update the trucker
script.

**With a paid police MDT (wasabi_mdt).** An unlicensed hazmat delivery also sends police a
dispatch call, "Illegal hazmat haul", at the delivery spot. Without the MDT the pay is still
taken back and no call is sent.

## Requires

| | |
|---|---|
| `ox_lib` | callbacks, closest-vehicle lookup |
| `qbx_core` | the player, their job, and the vehicle registry the model name comes from |
| `oxmysql` | the licence test records (`dps_licence_tests`, made on first start) |
| `lb-phone` | hosts the app on the phone |
| `lb-tablet` | hosts the app on the tablet, through one entry in its `Config.CustomApps` |
| `dps-towjob` 2.9.0 or newer | the queue; a soft dependency, checked at every call |
| `jg-vehiclestudio` | optional: the vehicle photo on the scan and status cards. Without it the cards show no picture. |
| `m-TruckerSimulator` | optional: the trucker level for the Hazmat licence, and the hazmat load check |
| `wasabi_mdt` | optional: the police dispatch call for an unlicensed hazmat delivery |

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
| `licencedebug` | One line per licence: fee, pass mark, how many questions are in its bank, and whether it is ready. Then the number of test records. Console only. |

## Tests

    lua5.4 tests/run.lua

## Recent changes

- **12 November 2026.** README: what it is for, how it works alone and with paid scripts, other
  DPS scripts. The Licences tab and the trucker hazmat check are now written up.
- **25 October 2026.** Synced with the live server. This brought in the Licences tab (11 work
  licences, tests and fees), the `HasLicence` exports, and the hazmat check for the trucker
  script, all agreed on 11 October 2026.
- **30 September 2026.** First version. Request a tow, follow it live, Driver tab, vehicle
  photos, cancel and refund wording, `servicesdebug`.

## Author

Made by [DaemonAlex](https://github.com/DaemonAlex) for DelPerroSands.

## Other DPS scripts

All of these are made for DelPerroSands and run together on one Qbox server. Each one works on
its own. The ones marked "pairs with" do more when both are running.

| Script | What it does |
|---|---|
| [dps-inventory](https://github.com/DaemonAlex/dps-inventory) | The inventory: ox_inventory with equipment slots, backpacks, armour plates and a self status panel, in the DelPerroSands colours. |
| [dps-medical](https://github.com/DaemonAlex/dps-medical) | Patient records, illness and diagnostic tests. A companion to wasabi_ambulance. Pairs with dps-inventory: symptoms and diagnoses show on the status panel. |
| [dps-insurance](https://github.com/DaemonAlex/dps-insurance) | Ties m-Insurance into the MDT, impound, hospital and medical chart. Pairs with dps-medical. |
| [dps-studio](https://github.com/DaemonAlex/dps-studio) | Build rooms, doors and portals in game from one panel (`/studio`), with owners and managers so staff do not have to support them. |
| [dps-shops](https://github.com/DaemonAlex/dps-shops) | Shop clerks who greet and react to a robbery, then player-owned shops. |
| [dps-fleet](https://github.com/DaemonAlex/dps-fleet) | Vehicle browser and workshop on one panel: extras, liveries and mods for emergency vehicles. |
| [dps-parking](https://github.com/DaemonAlex/dps-parking) | Parking with valet, impound, violations and reserved spots. |
| [dps-vehiclepersistence](https://github.com/DaemonAlex/dps-vehiclepersistence) | Vehicles stay where they were parked. Pairs with dps-parking. |
| [dps-towjob](https://github.com/DaemonAlex/dps-towjob) | Queue-based tow job with jg-mechanic integration. |
| [dps-autoshops](https://github.com/DaemonAlex/dps-autoshops) | Self-service repair shops when no mechanic is on duty. |
| [dps-cityworker](https://github.com/DaemonAlex/dps-cityworker) | City infrastructure job and career. |
| [dps-ainpcs](https://github.com/DaemonAlex/dps-ainpcs) | NPCs you can talk to, with trust, quests and intel. |
| [dps-badpeds](https://github.com/DaemonAlex/dps-badpeds) | Police interaction with NPCs: stops, arrests, intel and jail records. |
| [dps-gangwars](https://github.com/DaemonAlex/dps-gangwars) | Ambient gang NPCs, territory population and war reinforcements. |
| [dps-rotations](https://github.com/DaemonAlex/dps-rotations) | Moves dealers, harvests and other spots on a fixed schedule. |
| [dps-trains](https://github.com/DaemonAlex/dps-trains) | The train system. Pairs with dps-trains-stock, dps-traintools and dps-transitapp. |
| [dps-transitapp](https://github.com/DaemonAlex/dps-transitapp) | Live train arrival boards on the lb-phone. |
| [dps-faceplant](https://github.com/DaemonAlex/dps-faceplant) | City help, reports and staff tools on the lb-phone and lb-tablet. |
| [dps-chat](https://github.com/DaemonAlex/dps-chat) | A command box for voice-only servers. No chat feed. |
| [dps-filmmode](https://github.com/DaemonAlex/dps-filmmode) | One key hides every HUD layer and gives a smooth free camera for recording. |
