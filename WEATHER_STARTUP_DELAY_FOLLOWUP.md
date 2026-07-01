# Weather Startup Delay Follow-Up

## Smoke-test finding

During the simulator smoke test on April 26, 2026, the Home weather tile rendered `—` for roughly 19 seconds on a normal launch. It eventually resolved to the current weather after CoreLocation timed out and WeatherKit returned data, so this was not a crash or a hard failure.

Observed behavior:

- Build passed for the `WorkingOut` scheme.
- UI smoke tests passed.
- Normal app launch showed the Home screen within about 5 seconds.
- The weather tile stayed in its placeholder state until the location/weather chain completed.

## Current behavior

`WeatherSummaryView` displays `—` when `WeatherViewModel.summary` and `WeatherViewModel.errorText` are both nil. On appear, it waits briefly, then calls `vm.fetch()`.

`WeatherViewModel.fetch()` only proceeds when location permission is already granted. If `CLLocationManager.location` has no cached coordinate, it calls `requestLocation()`. WeatherKit is only requested after CoreLocation returns a coordinate.

## User impact

The tile looks empty or broken during startup even though the app is working. On slower simulator/device location paths, users can stare at `—` long enough to think weather is unavailable.

## Proposed fix

1. Add an explicit loading state to `WeatherViewModel`.
2. Render useful copy in `WeatherSummaryView` while location/weather is loading, such as `Updating weather...`.
3. Cache the last successful `WeatherSummary` with a timestamp in app storage or a small weather cache service.
4. On launch, immediately render the cached summary if it is fresh enough, then refresh in the background.
5. If location is unavailable or permission is missing, show a clear non-alarming state instead of a bare dash.

Suggested cache policy:

- Treat cached weather as fresh for 30 to 60 minutes.
- Keep showing stale cached weather while a refresh is in flight, but visually avoid implying it is live.
- Clear the cache only when the stored payload becomes invalid, not when a single refresh fails.

## Validation checklist

- Launch normally on simulator and confirm the tile never shows only `—`.
- Launch with location authorized and no cached coordinate; verify loading text appears quickly.
- Launch with cached weather; verify cached weather appears immediately and refreshes silently.
- Launch with location denied; verify the tile shows a clear unavailable/permission state.
- Run `WorkingOutUITests` to confirm screenshot fixture behavior remains deterministic.

