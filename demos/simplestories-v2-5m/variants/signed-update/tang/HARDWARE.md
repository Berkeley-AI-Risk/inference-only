# Tang S-AWIC hardware

## Admission and ownership

The core and all admission storage operate at 25 MHz. The read-only SPI source operates in the native 12.5 MHz trusted domain. Its tagged bytes cross the native four-entry registered asynchronous FIFO. The existing thin transport joins the core to the 100 MHz vendor DDR application interface. Admission does not send large RAM arrays across clock domains.

Signature storage and the verifier's intermediate LMS hash rows use synchronous private block RAM. A ready/valid handshake prevents the verifier from consuming a signature byte before its addressed read completes. The intermediate hash port similarly qualifies the selected row before SHA consumption. These ports are internal; package data cannot select arbitrary memory addresses.

1. Reset revokes admission, model lock and runtime validity.
2. The SPI source reads the fixed signed-admission slot with opcode `0x03`. The ingress parser sends exactly the canonical frame to the LMS verifier and checks that the rest of the slot is erased `0xff` padding.
3. The admission block hashes its private payload RAM and verifies all supplied signatures from two or three distinct fixed authorities. The actual native SHA compressor performs all LMS/LMOTS hashing. Only completed admission and valid slot padding permit the separate fixed model read.
4. The boot owner writes all 227,062 model words to DDR. It then reads them back in ascending order through the actual native adapter and transport. The same latched readback stream supplies the whole-image check and all 1,774 signed page-digest comparisons, with the runtime bank's zero tail for the final page.
5. The same readback supplies normalization storage, checks projection metadata against sealed signed RAM, and authenticates the fixed arithmetic-table suffix against a hardware constant.
6. Only all completed checks permit the one-way handoff to the runtime adapter. The four-bank service reads page digests and projection metadata from the private admitted tables. Each weight/LUT page is verified before use.
7. The UART token machine accepts APPEND, STEP and CLEAR under the fixed architecture. Runtime cannot rewrite admission storage or reopen boot ownership. A reset requires fresh complete admission.

```mermaid
flowchart LR
    F[Fixed read-only flash source] --> C[Tagged-byte CDC FIFO]
    C --> A[Frame and LMS admission]
    A --> S[Private sealed tables]
    A --> W[Model DDR load]
    W --> R[Ordered DDR readback]
    R --> H[Image, fixed-LUT and signed-page checks]
    R --> N[Private norm parameters]
    H --> L[One-way model lock]
    S --> P[Four verified page banks]
    L --> T[APPEND / STEP / CLEAR]
    N --> T
    N --> L
    P --> T
```

## Fixed flash layout

| Region | Start | Bytes | End, exclusive |
| --- | ---: | ---: | ---: |
| Full physical model image | `0x801000` | 7,265,984 | `0xeeeec0` |
| Signed admission slot | `0xf00000` | 262,144 | `0xf40000` |

The slot contains the 115,396-byte two-signer or 116,692-byte three-signer frame, followed by `0xff` padding. There are exactly two fixed SPI transactions: admission first, then model after permission. Neither package fields nor UART traffic control SPI addresses, opcodes or lengths. Signature rejection cannot initiate model writes.

The FPGA configuration is loaded into volatile SRAM separately. The offline [prepare_flash.py](tools/prepare_flash.py) validates a package and writes the two data files and a hashed plan. It does not program a device. [check_flash.py](tools/check_flash.py) checks an independently read complete 16 MiB array against a deliberately blank layout outside those regions. It does not establish preservation of an unrecorded configuration region.

For a baseline-preserving install, [prepare_preserving_flash.py](tools/prepare_preserving_flash.py) overlays only those two fixed regions onto a complete pre-install backup. It revalidates the signed package and produces a complete raw 16 MiB candidate and hashes. `check_flash.py --baseline` checks the independent post-install readback against the same overlay, including every unchanged byte outside the update regions. The original independently captured backups remain separate recovery inputs.

## Model-dependent storage

| Data | Authenticated source | Runtime consumer |
| --- | --- | --- |
| Whole-image commitment | Signed payload, private admission registers | Ordered DDR readback checker |
| 1,774 expected page hashes | Signed payload, private sealed RAM | Native four-bank verified-page service |
| 2,328 projection metadata words | Signed payload, private sealed RAM; also compared against image readback | Existing synchronous metadata DMA |
| 3,328 RMSNorm coefficient/scale rows | Exact image readback, before model lock | Body and final-norm synchronous private ports |

The 13 RMSNorm vectors each contain 256 W10 coefficients. Transformer coefficients occupy words 211800–211919; transformer norm metadata occupies 214248–214249. Final-norm coefficients occupy 214250–214259, with metadata at 214260. The store rejects the forbidden `-512` coefficient, zero or out-of-format multipliers and nonzero padding. Its outputs are masked before lock. The active RMSNorm services use these ports, not model-compiled coefficient ROMs.

The fixed RoPE, softmax-exponential and SiLU suffix begins at word 214261 and has 409,632 bytes. Its SHA-256 is `fea751d73eb4fd28f160a4dcc4b8d1fa39c125cb05d10393ac45ad4e3e1bb76b`. The boot checker compares this suffix with the hardwired digest before model lock. This check uses the signed image and does not add a new package payload. Runtime authentication uses the page table checked against that same readback.

## Boot-to-runtime page binding

<a id="boot-to-runtime-page-binding-limit"></a>

Whole-image, page, fixed-function-table and normalization checks consume the same ordered DDR response stream. Before lock, the page checker compares all signed digests with the measured pages, including the final page's zero padding. Image and page verification, fixed-table success, loaded norm parameters, signed admission and absence of faults are all required for lock.

Runtime weight/LUT pages authenticate against this sealed table. The fixed suffix therefore remains bound to the arithmetic tables used by the model, under the SHA/private-state and fixed-configuration assumptions. Model-update authorities can approve compatible weights; the hardwired architecture and fixed-function tables remain fixed.

## Build and security boundaries

The project retains the native board pins, clocks, physical DDR wrapper and DSP arithmetic branches. Proprietary vendor DDR/PLL source is acquired separately and checked against the enclosing demo's dependency manifest. It is not included in this source snapshot.

The [selected input identity](SOURCE-IDENTITY.json) binds every published non-vendor native input and the prebuilt image. The full native receipt retains the four separately acquired vendor hashes. The production file list selects the active hierarchy; copied unused modules do not define its behavior.

The current complete-model regressions use fast flash and modeled DDR storage, retaining actual admission, LMS/SHA, normalization, numerical-core and UART RTL. DSP primitives use their integer-equivalent behavioral branches. Physical SPI/DDR behavior, native mapping and timing have separate build/board evidence and qualification limits.

The inherited SDC is diagnostic: no new false paths, clock groups or relaxed periods are used. Routed resource fit and specific timing reports must be distinguished from complete vendor-DDR timing signoff. An FPGA owner can replace the configuration; the intended fixed-circuit claim also requires a frozen FPGA configuration or an eventual ASIC and an assessed physical threat model.

SPI transfer and verification time are implementation latency. They are not a security-enforced update delay or a residual-training bound.
