# ResQMesh — Offline Bluetooth Mesh Demo

A deep walkthrough of the flagship **Phase 3** feature: how an emergency
report still reaches the server when the network is dead, by traveling
**device-to-device over Bluetooth**.

No special action is required to "turn on" Bluetooth — the mesh relay is a
**background fallback** that only kicks in when the report **cannot reach the
server**. This document explains the *when*, *how*, and *how-to-verify* in
full, from booting the machines to proving the delivery in the web app.

---

## 1. When does Bluetooth come into play?

**Short answer:** only when the server is unreachable.

The app always tries the server first. There is no manual "Bluetooth on/off"
switch — the relay is automatic and opportunistic:

1. You submit a report and the app can reach the server → it's stored
   directly on the backend. **Bluetooth never engages.**
2. You submit a report and the server is **down / no network** → the request
   fails, so the report is stored in a **local ON-DEVICE outbox** instead.
3. From that moment the device starts **broadcasting the report over BLE** to
   any ResQMesh peer in range.
4. A peer that receives it stores it in its **inbox** ("carries" it) and may
   forward it onward (multi-hop).
5. The moment **any** carrier has a working connection, a periodic (~20 s)
   recovery push — or a manual **Sync now** tap — delivers it to the server.

> So, to answer directly: **yes — you "trigger" it by breaking the device's
> connection to the server** (stopping the backend). The whole point is that a
> report authored offline still ends up on the web dashboard unchanged.

> **The mesh is BONDLESS.** The app uses a vendored, patched `ble_peripheral`
> that accepts relay connections *without* forcing Android bonding. This means
> **no OS "Pair with …?" dialog ever appears** — crucial for the
> "unconscious sender" scenario (details in §2.6 and the vendor note below).

### Data model at a glance

- **Outbox** — reports *I* created but couldn't send. Live on the source device.
- **Inbox** — envelopes *I* received from peers (or my own outbox popped back).
  Live on any carrier device.
- **Envelope** — a self-contained packet: `id` (message_id), `origin` (reporter),
  `report` payload, `hop_count`, `ttl`.
  - Max **8 hops** (multi-hop forwarding), **24 h TTL**, then dropped.
  - Framed into ≤470-byte chunks (`R1|<id>|<offset>|<total>|<b64>`), reassembled
    on the peer, deduplicated by `message_id` (double-delivery is harmless: the
    server returns `201` first time, `200` on duplicates).
- **Peers** — the app runs BOTH a BLE GATT **server** (advertises the shared
  service UUID `6e400001-b5a3-…`) and a BLE **client** (scans, connects,
  writes). Every device is simultaneously a transmitter and a receiver.

---

## 2. Prerequisites (do this before the demo)

You need:

- **Host** with the ResQMesh repo, Android SDK, Flutter, and the backend deps.
- **Two emulators** (they are the two phones talking over BLE):
  - `resqmesh_avd`   → `emulator-5554` → **citizen** (`smokecit`)
  - `resqmesh_avd_b` → `emulator-5556` → **coordinator / peer** (`coorddemo`)
- The **backend** code + a DB, initially **running** (we take it down later).

### 2.1 Paths & variables used throughout

```bash
REPO=~/Desktop/codes/mi_hackathon
EMU=$HOME/Android/Sdk/emulator/emulator
ADB=$HOME/Android/Sdk/platform-tools/adb
# APK path relative to the repo root. If you cd into frontend/mobile instead,
# use: APK=build/app/outputs/flutter-apk/app-debug.apk
APK=$REPO/frontend/mobile/build/app/outputs/flutter-apk/app-debug.apk
BASE=http://localhost:8000/api/v1
```

> `$ANDROID_HOME` is normally `~/Android/Sdk`. Adjust paths to your machine.

### 2.2 Start the backend (initial state: online)

```bash
cd $REPO/backend
uv run python manage.py migrate
nohup uv run python manage.py runserver 0.0.0.0:8000 --noreload \
  > /tmp/resq_backend.log 2>&1 &
# verify it is up:
curl -s -o /dev/null -w "backend: %{http_code}\n" $BASE/relay/messages/
```

> `--noreload` avoids extra re-loader processes (important — see §3.4 for how
> to kill it precisely).

### 2.3 Boot both emulators

```bash
"$EMU" -avd resqmesh_avd   -no-snapshot-save -no-boot-anim > /tmp/emu_a.log 2>&1 &
"$EMU" -avd resqmesh_avd_b -no-snapshot-save -no-boot-anim > /tmp/emu_b.log 2>&1 &
```

**Wait for both to fully boot** (~40-60 s each):

```bash
for d in emulator-5554 emulator-5556; do
  "$ADB" -s $d wait-for-device
  until [ "$("$ADB" -s $d shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do
    sleep 2
  done
  echo "$d booted"
done
"$ADB" devices     # expect both emulator-5554 and emulator-5556 as "device"
```

> If `emulator-5556` doesn't appear, relaunch with `-no-snapshot-save` and wait
> again; first boot of a fresh AVD can be slow.

### 2.4 Install the app + pre-grant BLE permissions

```bash
for d in emulator-5554 emulator-5556; do
  "$ADB" -s $d install -r "$APK"
  "$ADB" -s $d shell pm grant com.resqmesh.resqmesh android.permission.BLUETOOTH_SCAN
  "$ADB" -s $d shell pm grant com.resqmesh.resqmesh android.permission.BLUETOOTH_ADVERTISE
  "$ADB" -s $d shell pm grant com.resqmesh.resqmesh android.permission.BLUETOOTH_CONNECT
  "$ADB" -s $d shell monkey -p com.resqmesh.resqmesh -c android.intent.category.LAUNCHER 1
done
```

**Why no permission dialogs appear:** these `pm grant` lines pre-approve the
three `BLUETOOTH_*` runtime permissions. Grants only last until you reinstall —
**re-run them after any APK reinstall.**

> If you changed app code and need a fresh build first:
> ```bash
> cd $REPO/frontend/mobile && flutter build apk --debug
> ```

### 2.5 Login on both devices

App starts on the **login screen**. (Sessions now persist across reloads, but a
fresh install starts logged out.)

- **5554 → `smokecit` / `strongpass123`** (citizen — submits the report)
- **5556 → `coorddemo` / `strongpass123`** (coordinator — carries + delivers)

Each home screen shows the **Offline mesh** card:
`mesh active · 0 queued · 0 carried` with a **Sync now** button.

> The relay starts **after login**, so both users MUST be logged in for the mesh
> to work.

### 2.6 The OS pairing dialog — REMOVED (bondless mesh)

> **This build no longer shows a pairing dialog at all.** Older builds of the
> relay required Android *bonding* (a system "Pair with `AA:BB:…`?" prompt) on
> first contact, which defeated the "unconscious sender" use case. That's been
> fixed by vendoring and patching `ble_peripheral` so the peripheral accepts a
> relay connection without calling `device.createBond()`.

**What that means for you:**
- **No "Pair with …?" dialog on either device.** A report submitted offline is
  handed off over BLE fully automatically, in the background, even if the
  sender is unconscious and can't tap anything.
- **The extra hands-free adb watcher is no longer required.** (It's harmless if
  you still run it, but there's nothing for it to tap.)
- **Trade-off:** the relay link is not link-layer encrypted (the GATT write
  characteristic is non-secure). This is acceptable here: it's a local,
  short-range, store-and-forward channel, and the app-level data model already
  dedups and self-validates envelopes.

**Implementation note (for rebuilds):** the `flutter_blue_plus` **central**
side and the `ble_peripheral` **peripheral** side are separate. The patch lives
in the vendored copy at `frontend/mobile/plugins/ble_peripheral/.../BlePeripheralPlugin.kt`
(see the `createBond()` removal in `onConnectionStateChange`), referenced as a
**path dependency** in `frontend/mobile/pubspec.yaml`. If you ever re-upstream
the plugin, re-apply this patch and keep the path dependency.

### 2.7 Automatic GPS location + faking it on the emulator

Reports no longer have manual lat/long fields. The form reads the device's
**current GPS position** on open (`geolocator`) and attaches it to the report —
both when submitted online and when buffered into the offline outbox (the
coordinates ride inside the relay envelope and are materialized by the backend).

Android needs these permissions (already declared in the manifest and pre-granted
below alongside BLE):

```bash
for d in emulator-5554 emulator-5556; do
  "$ADB" -s $d shell pm grant com.resqmesh.resqmesh android.permission.ACCESS_FINE_LOCATION
  "$ADB" -s $d shell pm grant com.resqmesh.resqmesh android.permission.ACCESS_COARSE_LOCATION
done
```

**To fake a deterministic position on an emulator** (so the demo shows a stable,
realistic coordinate like Kathmandu `27.7172`/`85.3240`):

```bash
"$ADB" -s emulator-5554 shell appops set com.resqmesh.resqmesh android:mock_location allow
"$ADB" -s emulator-5554 shell settings put secure mock_location 1
"$ADB" -s emulator-5554 emu geo fix 85.3240 27.7172    # <lon> <lat>
```

> Real devices need no setup; the app just asks for location permission once and
> uses the GPS/network fix. If GPS is off or denied, the form shows a
> "Location unavailable / Retry" card and the report is still sendable — but
> with **no coordinates**.

---

## 3. The demo — step by step

Layout the surfaces so the audience can see everything:
- **Terminal shell A** — backend control (start/stop) + `curl` checks.
- **5554 (citizen)** and **5556 (coordinator)** emulator windows side by side.
- **Chrome** → `http://localhost:8000/admin/` (or `flutter run -d chrome` as the
  coordinator dashboard) for the web-visible proof.

### Phase 0 — checkpoints

Confirm both cards read **`0 queued · 0 carried`**, the backend responds, and
both users are logged in:

```bash
curl -s -o /dev/null -w "backend: %{http_code}\n" $BASE/relay/messages/
```

### Phase 1 — take the server DOWN (this is the "stop the connection" step)

```bash
pgrep -af runserver                 # find the EXACT PIDs (get the uv/python PID)
kill <backend-pids>                 # kill by PID — NEVER `pkill -f runserver`
# confirm the app now sees no server:
curl -s -o /dev/null -m 2 $BASE/relay/messages/ && echo "still up" || echo "backend down"
```

> Killing by PID (not `pkill`) keeps the rest of the machine clean and lets you
> restart precisely later.

### Phase 2 — citizen submits a report while OFFLINE (on 5554)

1. On 5554 tap **GET HELP**.
2. Type a description, e.g. *"Trapped under debris near KU, two people injured."*
3. Pick an incident type, optionally add people affected.
4. **SEND EMERGENCY REPORT.**

> **Location is automatic.** The form captures your **current GPS position**
> when it opens — there are no Latitude/Longitude fields to type. A live card
> shows the coordinates it will attach (e.g. `27.717198, 85.323998 · GPS location
> (±5 m) — sent automatically `). Refresh/Retry recollects on demand. Catching
> the location on form-open is what makes this usable mid-emergency: nobody can
> calmly type a 9-decimal lat/long while under a collapsed building. See
> §2.7 for how to fake GPS in the demo.

**What you should observe:**
- A snackbar: **"No connection — report saved offline…"**
- 5554's card flips to **`1 queued · 0 carried`**.
- 5554 logcat: `[relay] outbox + <message_id>`

```bash
"$ADB" -s emulator-5554 logcat -d | grep -E '\[relay'
```

### Phase 3 — the BLE hop (5554 → 5556)

The devices auto-scan/advertise and trade the envelope. **No UI needed.** Wait
~10-60 s.

**What you should observe:**
- 5554 logcat: `[relay-ble] … peer <mac> …: sent 1 envelope(s)`
- 5556 logcat: `[relay] inbox + <message_id> origin=smokecit`
- 5556's card flips to **`0 queued · 1 carried`** ("I am now carrying a report
  that isn't mine")

```bash
"$ADB" -s emulator-5556 logcat -d | grep -E '\[relay'
```

> No OS pairing dialog appears (bondless mesh, §2.6) — the hand-off happens
> fully automatically in the background.

### Phase 4 — bring the server BACK

```bash
cd $REPO/backend
nohup uv run python manage.py runserver 0.0.0.0:8000 --noreload \
  > /tmp/resq_backend.log 2>&1 &
curl -s -o /dev/null -w "backend: %{http_code}\n" $BASE/relay/messages/
```

### Phase 5 — the carrier delivers to the server

Within **~20 s**, 5556's periodic recovery push delivers the carried report.
Or tap **Sync now** on 5556 to force it immediately.

**What you should observe:**
- 5556 logcat: `[relay] delivered 1 to server`
- Both cards settle back at **`0 queued · 0 carried`**

### Phase 6 — prove it reached the server (web / API)

```bash
curl -s $BASE/relay/messages/ | python3 -m json.tool
```

Look for the record with:
- `delivery_status: "DELIVERED"`
- `synced_to_server: true`
- a populated `report_id`
- `source_node: "smokecit"` and the original description text

**Web proof (Chrome):**
- Open **`http://localhost:8000/admin/`** → Emergencies → find the report as
  **DELIVERED** (or `synced_to_server: true`).
- Or run the coordinator dashboard (`flutter run -d chrome`, login
  `coorddemo`) → the report is in the list, fully populated, timestamp and
  reporter preserved from when it was authored **offline**.

> **Closing beat:** tap **Sync now** on any card — it runs the exact same
> delivery path on demand. That's the recovery mechanism made visible.

---

## 4. How to check it — quick reference

| What | How to look |
|------|-------------|
| Server alive? | `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/api/v1/relay/messages/` |
| 5554 queued/report stored offline | `logcat -d -s 5554 … \| grep '\[relay'` → `outbox + <id>` |
| BLE sent (5554) | `… -s emulator-5554 logcat -d \| grep '\[relay'` → `peer <mac>: sent 1 envelope(s)` |
| BLE received (5556) | `… -s emulator-5556 logcat -d \| grep '\[relay'` → `inbox + <id> origin=smokecit` |
| Delivered to server | `… -s emulator-5556 logcat -d \| grep '\[relay'` → `delivered 1 to server` |
| On-screen mesh state | Both apps' **Offline mesh** card: `X queued · Y carried` |
| On the web | Django admin Emergencies = `DELIVERED` / `synced_to_server:true`; or `curl …/relay/messages/` |
| Manual push | Tap **Sync now** on the card (runs the same recovery path) |

---

## 5. Troubleshooting the BLE demo

| Symptom | Likely cause / fix |
|---------|--------------------|
| Card still "0 queued" after an offline report | The backend was probably still up, so the report went straight to the server and never entered the outbox. Confirm with `curl` that the server is truly down (Phase 1), then submit again. |
| `[relay]` shows nothing at all | User not logged in (relay starts only after login). Log in. |
| BLE scan finds nothing / mesh idle | Both AVDs must run on the **same host**, Bluetooth ON, and BLE perms re-granted after a reinstall (§2.4). |
| "Pair with …" repeats | Should not appear in this build (bondless, §2.6). If you see one on an older APK, it's normal (fresh random address) — tap Pair; it never blocks the relay. |
| No `delivered 1 to server` after restart | Expected delivery is within ~20 s, but you can force it with **Sync now**. If still nothing, re-check the backend URL the app uses (`10.0.2.2:8000` on Android) and that the server binds `0.0.0.0`. |
| Emulator-5556 not in `adb devices` | Relaunch the AVD with `-no-snapshot-save -no-boot-anim` and wait for `sys.boot_completed=1`. |
| Duplicate deliveries | Harmless by design — server returns `201` once, `200` after (dedup by `message_id`). |

---

## 6. Recap

- **Bluetooth engages only when the server is unreachable** — breaking the
  connection to the server is exactly what triggers it.
- A report authored offline lives in a **local outbox**, then hops
  **device-to-device over BLE** into a peer's **inbox** (multi-hop, max 8,
  TTL 24 h).
- The carrier delivers it to the server (periodic ~20 s flush or **Sync now**)
  once it's online — visible end-to-end across **5554 logcat → 5556 logcat →
  the web dashboard**.
- You can observe it **entirely from the web + emulators**: Django admin / the
  coordinator dashboard show the `DELIVERED` report, and the mesh card + logcat
  on each emulator show every hop.
- **No user action is ever required to relay a report** (bondless mesh):
  because the app no longer forces Android bonding, a report handed off over
  BLE works even if the sender is unconscious and cannot tap anything.
- **Location is captured automatically from GPS** on form open — never typed by
  hand — and the coordinates travel with the report through the mesh, preserved
  end-to-end as it's carried device-to-device to the server.
