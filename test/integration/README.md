# Integration Tests

These require a working Docker environment. Run manually before pushing major changes.

## Automated Smoke Test

Run the lightweight Docker smoke harness to verify the manager can start and stop a real container through `start_instance()` and `stop_instance()` without booting the full ASA runtime:

```bash
bash test/run_integration_checks.sh
```

This test uses a temporary `busybox` compose file and overrides only the ASA-specific checks, so it validates manager orchestration and compose control rather than game-server startup.

If Docker is installed but the smoke test reports socket permission errors, either add your user to the `docker` group or rerun the smoke test with `sudo`.

## Full Local Validation

Run the full local validation wrapper against a dedicated existing test instance to exercise the real manager startup path, wait for the container, and wait for the ASA process inside the container:

```bash
bash test/run_full_local_validation.sh test_beta --branch beta
```

Use `--branch stable` to validate the stable/latest mode, or leave the branch as `current` to keep the manager in its existing mode. Useful flags:

```bash
bash test/run_full_local_validation.sh test_beta --branch beta --leave-running
bash test/run_full_local_validation.sh test_beta --branch stable --skip-fast
bash test/run_full_local_validation.sh test_beta --branch beta --sudo
```

This script is intentionally local-only. Use a dedicated test instance, not a live production server, because it performs a clean stop/start cycle.
Use `--sudo` on WSL or other setups where the manager needs elevated privileges to manipulate ownership or run the target validation path. Leave it off when validating a proper non-root `pokuser` / matching-PUID installation.

## Pre-flight Checklist

- [ ] `./POK-manager.sh -setup` completes without errors
- [ ] `./POK-manager.sh -create test_instance` creates `Instance_test_instance/` with a compose file
- [ ] `./POK-manager.sh -list` shows `test_instance`
- [ ] `./POK-manager.sh -status test_instance` reports correct state
- [ ] `./POK-manager.sh -start test_instance` starts the container
- [ ] `./POK-manager.sh -stop test_instance` stops the container gracefully
- [ ] `./POK-manager.sh -restart 1 test_instance` performs a countdown restart
- [ ] `./POK-manager.sh -backup test_instance` creates a backup archive
- [ ] `./POK-manager.sh -restore test_instance` lists and restores backups
- [ ] `./POK-manager.sh -API TRUE test_instance` enables API mode
- [ ] `./POK-manager.sh -API FALSE test_instance` disables API mode
- [ ] `./POK-manager.sh -fix` runs without errors
- [ ] `./POK-manager.sh -status -all` works with multiple instances
- [ ] Manual rename test: rename `Instance_test_instance` to `Instance_renamed`, then run `-start renamed` and confirm the mismatch is detected and offered for repair

## Cleanup

```bash
./POK-manager.sh -stop test_instance
rm -rf Instance_test_instance
```
