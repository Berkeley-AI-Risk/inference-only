# Run the periodic-reauthorization demonstration

Use the Tang Mega 138K Basic / GW5AST-138C, the enclosing demo's [programming guide](../../PROGRAMMING.md), and the [signed-update installation workflow](../signed-update/tang/REPRODUCE.md#offline-flash-data-and-board-qualification). The board needs the signed base-model flash data at the existing signed-update addresses. Preserve independently checked recovery backups before any model installation. This variant changes the SRAM configuration, not the flash layout.

Use Python 3.10+ on the tested macOS host. Set `HOME_DEMO` to this directory's absolute path, `SIGNED_MODEL` to the verified base `.swic` package, and `RUN` to a fresh directory outside the repository. The model weights are the enclosing demo's existing base assets; the package CLI and flash planner are in the signed-update integration. No production key is required or included.

First create a policy for the exact signed model and start the loopback authorization service:

```sh
python3 -I -B "$HOME_DEMO/tools/setup_policy.py" --package "$SIGNED_MODEL" --policy "$RUN/policy.json"
python3 -I -B "$HOME_DEMO/reference/home_server.py" --policy "$RUN/policy.json" \
  --signer-state "$RUN/home-signer-state.json" --port 8765
```

Keep the service running. Its policy is read on every request. The deliberately public H5 home key has 32 signing leaves; preserve its signer-state file and never reset it as a way to extend a deployment. This finite public fixture is intended for short tests. A production service would require a suitable private-key scheme, capacity and durable state management.

In a second terminal, open the UART relay **before** loading the image. `MODEL_ROOT` is the commitment printed by setup; `UART` is the serial device identified by the programming guide:

```sh
python3 -I -B "$HOME_DEMO/tools/relay.py" --device "$UART" --model-root "$MODEL_ROOT" \
  --smoke --output "$RUN/smoke"
```

In a third terminal, select the board/cable/location as described by the programming guide, check the [bitstream hash](prebuilt/README.md), and load only volatile SRAM:

```sh
"$PROGRAMMER" --device GW5AST-138C --cable-index "$CABLE_INDEX" \
  --location "$LOCATION" --frequency 0.9MHz --operation_index 2 \
  --fsFile "$HOME_DEMO/prebuilt/home_product.fs"
```

The relay waits up to three minutes for autonomous model admission and the first challenge. Its base-model smoke check verifies `[108,32]`, then CLEAR. It handles home grants in 16-byte chunks with 3 ms gaps, waits 0.5 seconds after a grant and avoids the final 0.5 seconds before a renewal handover. Do not share the UART with the browser app or another reader. Each new session needs a fresh challenge; start the relay before loading again.

For a renewal/revocation inspection, omit `--smoke` and keep the relay running. To revoke the model, atomically replace `policy.json` with a policy removing its commitment. The relay reports a denial, and the hardware stops by its permission deadline. An unavailable service also stops operation. This demo's 10-second permission period is configurable in hardware; it is not a wall-time guarantee under clock tampering.

To install a replacement, sign compatible weights under the separate model-update policy, prepare/check the flash data using the signed-update guide, and add the replacement commitment to home policy. The old commitment can remain withdrawn. Install through the deployment host, start the relay with the replacement commitment and reload SRAM for a fresh session. The base `[108,32]` smoke expectation applies only to the base fixture. There is no automatic network-push agent or preservation of the old model's context.

After testing, close the relay, restore `../signed-update/tang/prebuilt/swic_product.fs` into SRAM and verify its baseline using the signed-update UART checker. The restored image does not require home authorization. None of the commands above writes FPGA configuration flash; model-data changes use the separately documented flash procedure.
