# Tools and optional source-build dependencies

## Running the prebuilt demo

You need the matching **Tang Mega 138K non-Pro, GW5AST-138C/PG484A** board,
its USB connection/power, Python 3.12 with the host requirements, and GOWIN's
standalone Programmer. Complete factory-backup restoration additionally uses
the separately downloaded **openFPGALoader 1.1.1**. You do **not** need the
hardware compiler, its
development license, or the four source-IP files below to run the included
bitstreams. The documented workflow was tested on Apple Silicon macOS;
Linux/Windows ports have not been validated by this project.

Obtain the Programmer from
[GOWIN's official download page](https://www.gowinsemi.com/en/support/download_eda/)
under its terms. The tested standalone release is **1.9.12.03, build 2712,
macOS ARM64**. Its official archive is
[programmer1.9.12.03(2712).MacOS.m1.tar.gz](https://cdn.gowinsemi.com.cn/programmer1.9.12.03(2712).MacOS.m1.tar.gz),
SHA-256 `d7a400d4cb0d81b7a62e56555f39405e6a3858dc9ca32424a037c00584bac490`.
The extracted `Programmer/bin/programmer_cli` must hash to
`41a967c1d18ec73b420801d52bf83ad40b92ca032683231d55a5ef158d523cfb`.
Keep the installation's accompanying libraries and data files intact.

For the tested 16-MiB flash, `Programmer/bin/data/spi/spi.ini` must use
`size = 128` (Mbit) in **both `[DEFAULT]` and `[Generic Flash]`**, matching the
configuration used for this rehearsal. Preserve a copy before editing those
capacity values; leave the command bytes and other settings unchanged.
This setting does not identify your physical flash: verify the ID/capacity
as described in [PROGRAMMING.md](PROGRAMMING.md).
Do not reuse numeric programming operations with an unreviewed tool version.

### Factory-backup restoration tool

Install openFPGALoader through its
[official installation instructions](https://trabucayre.github.io/openFPGALoader/guide/install.html).
On the tested Mac, Homebrew supplied version **1.1.1**:

```sh
brew install openfpgaloader
openFPGALoader -V
```

Require that version for the documented recovery procedure; a later package
is not automatically qualified by this project's test. The tested ARM64
Homebrew executable had SHA-256
`f880eb583695f8056566da308248ba539a1a1c4cabb6305c3d801acfd58f9e1b`.
Other builds can have different bytes; the recorded hash identifies the
tested executable, not every build of that version. The tool and its libraries
are not redistributed in this repository. No paid FPGA development license
is required for it. Follow [PROGRAMMING.md](PROGRAMMING.md) for exact board
selection and the whole-array recovery procedure; do not substitute this
procedure for the separate model-at-`0x801000` installation commands.

## Optional: rebuild the hardware from source

The exact demonstrated compiler is **GOWIN Education V1.9.11.03 for macOS**.
The selected part is `GW5AST-LV138PG484AC1/I0`, not the 60K, device B revision
or 138K Pro/FPG676A. Consult
[Sipeed's board guide](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k.html)
and [IDE installation guide](https://wiki.sipeed.com/hardware/en/tang/common-doc/get_started/install-the-ide.html).

Obtain the IDE through GOWIN's official download page and your own account.
The reference `Gowin_V1.9.11.03Education_macOS.dmg` has SHA-256
`95efaf06e4df1d902ec3307ce5e52fceb76cf5937b0eae5001555df94330c500`.
The build wrapper's `--gowin-ide` names the directory containing `bin/gw_sh`
and `lib/`, normally below `Contents/Resources/Gowin_EDA/IDE`.
The pinned `bin/gw_sh` hash is
`1a2497e6752a4561b64f620e0aa68ae5da599b118f8d723ca70c491f6688678e`.
A file hash is an identity check, not publisher authentication of an entire
installation. Do not disable system-wide security to run unknown software.

### Four exact source inputs from Sipeed

All four are publicly available at revision
`06e7d8b118d345915ab6f257b7c22226f81575cd` of
[Sipeed's official example](https://github.com/sipeed/TangMega-138K-example/tree/06e7d8b118d345915ab6f257b7c22226f81575cd/ddr_memory).
The release preparation verified unauthenticated downloads against the exact
selected inputs. No private supplier response or regenerated substitute is
needed. `VENDOR-DEPENDENCIES.json` lists the URLs, sizes and hashes.

From the repository root:

```sh
python3.12 -I -S -B tools/fetch_vendor.py ../fpga-vendor-inputs --confirm-permitted-vendor-use
python3.12 -I -S -B tools/fetch_vendor.py ../fpga-vendor-inputs --check
```

The first command downloads only those four files and never executes them.
The second is offline. Both reject different existing bytes without overwriting
them. Obtain and retain their original notices under the applicable terms;
the project's Apache grant does not relicense independently supplied IP.

The DDR header records IP 6.0 generated with V1.9.12.02_SP1; that generator
version differs from the compiler used for the demonstrated build. The fixed
interface has a 32-bit DDR bus and 256-bit application words, with a 100-MHz
application clock and 400-MHz memory PLL. Use the exact files and actual RTL
connections; these summary settings are not an equivalent regeneration recipe.

### Check, then build

```sh
python3.12 -B host-app/build_hardware.py \
  --vendor-dir /absolute/path/to/fpga-vendor-inputs \
  --gowin-ide /absolute/path/to/Gowin_EDA/IDE \
  --output /absolute/space-free/path/to/fresh-build \
  --confirm-permitted-vendor-use --preflight-only
```

Preflight checks the 90 pinned inputs and compiler without starting a build
or accessing hardware. Remove `--preflight-only` to compile and route into a
fresh output directory. Keep that output and downloaded vendor files private.
The `BUILD.json` receipt records source/output correspondence, **not** timing
signoff, whole-chip correctness or what is currently loaded on a board.
For the normal prebuilt workflow, use the included build receipt instead.

The command defaults to the **baseline**. To build the K/V-protected
variant, add `--variant kv-protected` and use a different fresh output
directory. Its inventory contains 93 inputs, including the same four vendor
files. The wrapper checks the selected inventory and records the variant in
`BUILD.json`; do not substitute one variant's receipt for the other's image.
The tested protected prebuilt image is already included, so a new route is
not necessary to try it. Neither successful build is complete DDR timing
signoff. See [the two-version guide](KV-PROTECTION.md).
