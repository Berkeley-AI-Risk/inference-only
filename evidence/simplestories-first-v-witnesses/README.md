# Four SimpleStories first-value witnesses

The four ACL2 witnesses check all 128 signed V mantissas and the shared exponent of the layer-0, position-0 record. Each follows one ordinary STEP from reset on the repaired eight-bank behavioral probe. The held-input evaluation runs for 68,605 cycles and reaches record completion at cycle 68,596.

| First token | First V mantissa | Shared exponent |
| ---: | ---: | ---: |
| 1 | −6,191 | −16 |
| 27 | 4,699 | −15 |
| 32 | 11,821 | −17 |
| 3258 | −813 | −14 |

The held-input model drives the core and application clocks together, holds each input through both phases and samples low. The corrected-cycle parent fixes CLEAR low during the high phase. The proof carries reset, zero internal overrides, two-valuedness, ordered modeled memory and fixed public model values. It explicitly binds the ROMs because the translator drops RTL `initial` blocks. These statements concern the decoded-input behavioral probe. [Held clock construction](book-sources/held-clear-record/kv-step-to-record-held.lisp) · [Public 18-write record theorem](../simplestories-kv-record/README.md)

The [all-token numerical range proof](../simplestories-first-v-profile/README.md) discharges arithmetic prerequisites for the fixed-point reference for all 4,019 legal first tokens. The RTL-to-reference equation for arbitrary first tokens remains open. The finite packet includes the conditional theorem with that equation as a hypothesis. UART refinement, physical memory persistence and board timing have separate evidence. [Conditional equation](book-sources/first-value-numeric/kvn-open-equation.lisp)

## Rebuild the inputs from a clean checkout

Use Python 3.12, Git and patch. The repository must have public commit `b12eadcffd05a6052d648ec23869bc369c4cd16a` and the historical Git objects pinned by the public source reproducer. Run from the repository root. Give preparation a fresh output path whose parent already exists.

```sh
python3.12 -I -S -B evidence/simplestories-first-v-witnesses/prepare_checkout.py \
  --public-git . --out /tmp/first-v-recipient
python3.12 -I -S -B evidence/simplestories-first-v-witnesses/prepare_checkout.py \
  --verify --out /tmp/first-v-recipient
```

The recipe checks 77 RTL source names and reconstructs the 76-file behavioral elaboration. It stages 57 ACL2 source books, including two regenerated constant books, and checks all 187 members of the source manifest. The four fixed witness inputs come from the pinned reviewed source packet. [Source and asset pins](PINS.json) · [Packet checksums](SHA256SUMS)

## Certify the three stages

Use an ACL2 8.7 build and the corrected, certified Community Books from the [translator recipe](../simplestories-kv-record/translator/README.md). The source preparation also copies that recipe into `/tmp/first-v-recipient/translator-recipe`. Use the inspected LRAT adapters and the matching corrected translator source. The checked run used SBCL 2.6.10. The archived SAT stages use CaDiCaL 3.0.0 with proofs checked by ACL2. `cert.pl` requires whitespace-free output, executable and system-book paths. One active numerical book has used about 75 GB of memory. The recorded serial run took roughly ten hours.

```sh
for stage in corrected held finite; do
  python3.12 -I -S -B evidence/simplestories-first-v-witnesses/certify_stage.py \
    --checkout /tmp/first-v-recipient --stage "$stage" \
    --acl2 /path/to/saved_acl2 --books /path/to/corrected/books || exit
done
```

The corrected-cycle, held-input and finite stages run serially from an empty local certificate tree. Each opens a fresh ACL2 world, checks the actual loaded formulas and rehashes its live parent receipts. The reviewed closure contains 56 local certificates. All three stage exits were zero. The loaded worlds reported zero uncertified includes, skipped proofs or redefinitions and showed the 17 recorded trust tags. [Clean recipient receipt](CHECKED-RECIPIENT.json)

The model-derived inputs carry the [SimpleStories MIT notice](../../LICENSES/SimpleStories-MIT.txt) and [model card](../../LICENSES/SimpleStories-MODEL-CARD.md). The preparation stages the existing [proof-tool notices](../simplestories-kv-record/notices/). [Project license scope](../../LICENSE-SCOPE.md)
