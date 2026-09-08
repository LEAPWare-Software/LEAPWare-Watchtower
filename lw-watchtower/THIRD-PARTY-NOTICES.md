# Third-party notices

**This file is part of the shipped payload, and that is the whole reason it is here rather than
at the repository root.** `.claude-plugin/marketplace.json` declares `"source": "./lw-watchtower"`,
so the CLI copies only that subtree into a consumer's plugin cache. A notices file above the
boundary would satisfy a reviewer reading the repository and would reach nobody who installs the
plugin — and the people the licences below are written to protect are exactly the people who
receive a copy. The same argument put a copy of `LICENSE` beside this file.

Six third-party bodies are vendored into this payload, taken from **five upstream repositories**,
held by **five different copyright holders**, under **three licence types** — MIT (three separate
holders), CC BY 4.0, and Apache-2.0. **Every one of the three conditions redistribution on a notice
travelling with the copy**, which is what this file is. Each block below carries, in the same order
every time:

* the **paths in this payload** that the block covers, spelled in full;
* the **upstream repository URL**;
* the **commit** the copy was taken at, as a full SHA;
* the **date it was retrieved**;
* the **SPDX licence identifier**;
* a **`Changes:`** line;
* the **licence text**, verbatim.

**Every `Changes:` line below reads `none`, and that is a measured claim rather than a courtesy.**
Each vendored file's blob hash in this repository's git index was compared with the blob hash the
upstream tree reports at the pinned commit, and all thirteen matched. That is a stronger check than
a diff: it would have caught a line ending silently rewritten by `.gitattributes` on the way into
the index, which a visual diff would not show. No file was reformatted, re-indented, re-encoded or
re-wrapped, and none carries this project's house `Shipped by the LW-WATCHTOWER plugin` header —
inserting one would modify a byte-identical copy and put this project's name at the top of somebody
else's text. **Header-absence is how `tests/payload_guard.ps1` case S17 tells a vendored file from a
house one**, so this file and that case are derived from the same fact and cannot drift apart
silently.

**Taking a subset of an upstream repository is not a modification.** Where a block says only some of
an upstream project's files were vendored, the files that were taken are byte-identical; the ones
that were not are simply absent, and each block says which and why.

## What is NOT in this file, said plainly

`lw-watchtower/skills/lw-handoff/SKILL.md` **is original work.** © 2026 LEAPWare-HQ, Apache-2.0,
the same licence as the rest of this plugin. It is not vendored, not adapted and not derived from
anyone else's handoff procedure, and it appears in no block below — naming an upstream in a
third-party notices file is a statement that something came from it.

---

## `lw-watchtower/context/stack/ponytail.md`

| | |
| --- | --- |
| Upstream | https://github.com/DietrichGebert/ponytail |
| Upstream path | `skills/ponytail/SKILL.md` |
| Commit | `356918eba965ee1eac64bd3a7f0dd02108350de5` |
| Retrieved | 2026-09-07 |
| SPDX | `MIT` |
| Copyright | © 2026 DietrichGebert |

`Changes: none` — byte-identical to the upstream blob at that commit. The file is renamed on the way
in, from `skills/ponytail/SKILL.md` to `context/stack/ponytail.md`, because the CLI this plugin runs
in auto-registers every `skills/*/SKILL.md` as model-invocable and this body is loaded as context by a
module instead. **A path is not content**; nothing inside the file was touched. Nothing was left
behind either: the upstream skill directory holds `SKILL.md` and nothing else, and the body names no
script, template or reference file.

The MIT licence requires this notice to be included in all copies of the software, and this is that
inclusion. Full text, verbatim:

```
MIT License

Copyright (c) 2026 DietrichGebert

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## `lw-watchtower/context/stack/unlazy.md`

| | |
| --- | --- |
| Upstream | https://github.com/Leonxlnx/unlazy |
| Upstream path | `SKILL.md` |
| Commit | `16671491f6679ad9378f52604d3bc2415b4120c7` |
| Retrieved | 2026-09-07 |
| SPDX | `MIT` |
| Copyright | © 2026 Leonxlnx |

`Changes: none` — byte-identical to the upstream blob at that commit. Renamed on the way in, from
`SKILL.md` to `context/stack/unlazy.md`, for the same reason as `ponytail.md` above; the content is
untouched.

**Only `SKILL.md` was taken.** Upstream also ships `references/`, `templates/`, `scripts/` and
`agents/` directories, and **none of them is vendored here.** The scripts are `.mjs` — this plugin
is pure Windows PowerShell and has no Node dependency anywhere, and adding one to carry a vendored
skill's tooling is a cost the whole payload would pay. A subset is not a modification, so the
`Changes:` line above stands; what it means for a reader of the vendored body is stated plainly
rather than left to be discovered: **the body instructs `node <skill-dir>/scripts/gate-check.mjs`,
`gate-lint.mjs` and `install-hooks.mjs`, and reads `templates/gates-leaf.md` and several
`references/*.md`. Those files are not in this payload and Node is not assumed to be installed.**
Treat the body as the method it describes, not as a set of commands that will run here.

Full MIT text, verbatim:

```
MIT License

Copyright (c) 2026 Leonxlnx

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## `lw-watchtower/skills/grill-me/SKILL.md` and `lw-watchtower/skills/grilling/SKILL.md`

| | |
| --- | --- |
| Upstream | https://github.com/mattpocock/skills |
| Upstream paths | `skills/productivity/grill-me/SKILL.md`, `skills/productivity/grilling/SKILL.md` |
| Commit | `3cca18b368ae95cdbdebbff572ccafa662551015` |
| Retrieved | 2026-09-07 |
| SPDX | `MIT` |
| Copyright | © 2026 Matt Pocock |

`Changes: none` — both files are byte-identical to the upstream blobs at that commit, and both keep
their upstream directory names.

**Two files, one block, because there is one copyright holder.** `grill-me/SKILL.md` is a 157-byte
stub whose entire body is `Call the Skill tool with "grilling".`; `grilling/SKILL.md` is the
procedure it points at. Vendoring the pointer without its target would ship a skill that does
nothing, so both were taken. They come from the same repository at the same commit under the same
licence, so one licence copy discharges the notice for both. Where two upstreams share a licence
*type* but not a *holder*, this file carries separate copies — the MIT text names its holder, and
deduplicating it would drop a name the licence requires be included in all copies.

Each upstream skill directory also holds an `agents/openai.yaml` — a 113-byte port target for a
different harness. **Neither was vendored**, and neither body reads one.

Full MIT text, verbatim:

```
MIT License

Copyright (c) 2026 Matt Pocock

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## `lw-watchtower/skills/task-observer/` — SKILL.md and seven reference files

Covered paths, spelled in full because each one is a separate copy of somebody's work:

* `lw-watchtower/skills/task-observer/SKILL.md`
* `lw-watchtower/skills/task-observer/references/environments.md`
* `lw-watchtower/skills/task-observer/references/migration.md`
* `lw-watchtower/skills/task-observer/references/observation-log.md`
* `lw-watchtower/skills/task-observer/references/signals.md`
* `lw-watchtower/skills/task-observer/references/skill-authoring.md`
* `lw-watchtower/skills/task-observer/references/starter-principles.md`
* `lw-watchtower/skills/task-observer/references/weekly-review.md`

| | |
| --- | --- |
| Upstream | https://github.com/rebelytics/one-skill-to-rule-them-all |
| Upstream paths | `SKILL.md`, `references/*.md` (all seven) |
| Commit | `2967fa5f2f16336677d216fe83d9832a52aadc00` |
| Retrieved | 2026-09-07 |
| SPDX | `CC-BY-4.0` |

`Changes: none` — all eight files are byte-identical to the upstream blobs at that commit.

**All eight, because the body points at `references/*.md` more than thirty times.** Shipping a skill
to a stranger whose own instructions name files that are not there is the defect class this plugin
exists to catch. Reference files are not always-on context — only a skill's frontmatter description
is — so the runtime token cost of carrying them is zero; the cost is disk. Upstream's `scripts/`,
`README.md`, `USER-GUIDE.md`, `CONTRIBUTING.md` and images were **not** vendored.

Vendored under the directory name `task-observer`, which is the upstream skill's own `name:` field.

### CC BY 4.0 § 3(a)(1), item by item

The licence conditions attribution on a list. Each item is discharged here explicitly rather than
left to be inferred from a link.

1. **§ 3(a)(1)(A)(i) — identification of the creator.** Created by **Eoghan Henn**
   ([rebelytics.com](https://rebelytics.com)), the attribution the Licensor asks for by name:
   upstream's own terms request a link to the original repository and the author's name, and both
   are given here. The work's title is **"One Skill to Rule Them All"**.
2. **§ 3(a)(1)(A)(ii) — a copyright notice.** Upstream supplies no separate copyright line, in
   `LICENSE.txt` or elsewhere; the creator identification above is what was supplied and it is
   retained. Stated rather than silently omitted, and no copyright line is invented on the
   Licensor's behalf.
3. **§ 3(a)(1)(A)(iii) — a notice referring to this Public License.** This material is licensed
   under the Creative Commons Attribution 4.0 International Public License. Its full legal code is
   reproduced verbatim below, and is also at
   https://creativecommons.org/licenses/by/4.0/legalcode.
4. **§ 3(a)(1)(A)(iv) — a notice referring to the disclaimer of warranties.** Reproduced in
   § 5 of the legal code below, and it applies: the material is offered **as-is and as-available**,
   with no representations or warranties of any kind.
5. **§ 3(a)(1)(A)(v) — a URI to the Licensed Material.**
   https://github.com/rebelytics/one-skill-to-rule-them-all — pinned for this copy at commit
   `2967fa5f2f16336677d216fe83d9832a52aadc00`.
6. **§ 3(a)(1)(B) — indicate if you modified the material. `Modified: no`.** Not a claim of
   intent: each of the eight files' blob hash in this repository's index equals the upstream blob
   hash at the pinned commit. Upstream indicates no previous modifications, so there is none to
   retain. **This is why the frontmatter of the vendored `SKILL.md` was not reflowed.** It opens
   with a folded YAML block scalar (`description: >`) that this repository's own frontmatter linter
   rejected; the linter was rewritten to parse block scalars rather than the vendored file
   reformatted, because one line of reformatting would have turned this item into `Modified: yes`
   permanently and ended byte-identical resync with upstream.
7. **§ 3(a)(1)(C) — indicate the licence and include its text.** Done by this block and by the
   legal code below. The attribution paragraph the Licensor supplied *inside* `SKILL.md` is also
   retained in place, because the file is unmodified.

Full Creative Commons Attribution 4.0 International legal code, verbatim:

```
Attribution 4.0 International

=======================================================================

Creative Commons Corporation ("Creative Commons") is not a law firm and
does not provide legal services or legal advice. Distribution of
Creative Commons public licenses does not create a lawyer-client or
other relationship. Creative Commons makes its licenses and related
information available on an "as-is" basis. Creative Commons gives no
warranties regarding its licenses, any material licensed under their
terms and conditions, or any related information. Creative Commons
disclaims all liability for damages resulting from their use to the
fullest extent possible.

Using Creative Commons Public Licenses

Creative Commons public licenses provide a standard set of terms and
conditions that creators and other rights holders may use to share
original works of authorship and other material subject to copyright
and certain other rights specified in the public license below. The
following considerations are for informational purposes only, are not
exhaustive, and do not form part of our licenses.

     Considerations for licensors: Our public licenses are
     intended for use by those authorized to give the public
     permission to use material in ways otherwise restricted by
     copyright and certain other rights. Our licenses are
     irrevocable. Licensors should read and understand the terms
     and conditions of the license they choose before applying it.
     Licensors should also secure all rights necessary before
     applying our licenses so that the public can reuse the
     material as expected. Licensors should clearly mark any
     material not subject to the license. This includes other CC-
     licensed material, or material used under an exception or
     limitation to copyright. More considerations for licensors:
    wiki.creativecommons.org/Considerations_for_licensors

     Considerations for the public: By using one of our public
     licenses, a licensor grants the public permission to use the
     licensed material under specified terms and conditions. If
     the licensor's permission is not necessary for any reason--for
     example, because of any applicable exception or limitation to
     copyright--then that use is not regulated by the license. Our
     licenses grant only permissions under copyright and certain
     other rights that a licensor has authority to grant. Use of
     the licensed material may still be restricted for other
     reasons, including because others have copyright or other
     rights in the material. A licensor may make special requests,
     such as asking that all changes be marked or described.
     Although not required by our licenses, you are encouraged to
     respect those requests where reasonable. More considerations
     for the public:
    wiki.creativecommons.org/Considerations_for_licensees

=======================================================================

Creative Commons Attribution 4.0 International Public License

By exercising the Licensed Rights (defined below), You accept and agree
to be bound by the terms and conditions of this Creative Commons
Attribution 4.0 International Public License ("Public License"). To the
extent this Public License may be interpreted as a contract, You are
granted the Licensed Rights in consideration of Your acceptance of
these terms and conditions, and the Licensor grants You such rights in
consideration of benefits the Licensor receives from making the
Licensed Material available under these terms and conditions.


Section 1 -- Definitions.

  a. Adapted Material means material subject to Copyright and Similar
     Rights that is derived from or based upon the Licensed Material
     and in which the Licensed Material is translated, altered,
     arranged, transformed, or otherwise modified in a manner requiring
     permission under the Copyright and Similar Rights held by the
     Licensor. For purposes of this Public License, where the Licensed
     Material is a musical work, performance, or sound recording,
     Adapted Material is always produced where the Licensed Material is
     synched in timed relation with a moving image.

  b. Adapter's License means the license You apply to Your Copyright
     and Similar Rights in Your contributions to Adapted Material in
     accordance with the terms and conditions of this Public License.

  c. Copyright and Similar Rights means copyright and/or similar rights
     closely related to copyright including, without limitation,
     performance, broadcast, sound recording, and Sui Generis Database
     Rights, without regard to how the rights are labeled or
     categorized. For purposes of this Public License, the rights
     specified in Section 2(b)(1)-(2) are not Copyright and Similar
     Rights.

  d. Effective Technological Measures means those measures that, in the
     absence of proper authority, may not be circumvented under laws
     fulfilling obligations under Article 11 of the WIPO Copyright
     Treaty adopted on December 20, 1996, and/or similar international
     agreements.

  e. Exceptions and Limitations means fair use, fair dealing, and/or
     any other exception or limitation to Copyright and Similar Rights
     that applies to Your use of the Licensed Material.

  f. Licensed Material means the artistic or literary work, database,
     or other material to which the Licensor applied this Public
     License.

  g. Licensed Rights means the rights granted to You subject to the
     terms and conditions of this Public License, which are limited to
     all Copyright and Similar Rights that apply to Your use of the
     Licensed Material and that the Licensor has authority to license.

  h. Licensor means the individual(s) or entity(ies) granting rights
     under this Public License.

  i. Share means to provide material to the public by any means or
     process that requires permission under the Licensed Rights, such
     as reproduction, public display, public performance, distribution,
     dissemination, communication, or importation, and to make material
     available to the public including in ways that members of the
     public may access the material from a place and at a time
     individually chosen by them.

  j. Sui Generis Database Rights means rights other than copyright
     resulting from Directive 96/9/EC of the European Parliament and of
     the Council of 11 March 1996 on the legal protection of databases,
     as amended and/or succeeded, as well as other essentially
     equivalent rights anywhere in the world.

  k. You means the individual or entity exercising the Licensed Rights
     under this Public License. Your has a corresponding meaning.


Section 2 -- Scope.

  a. License grant.

       1. Subject to the terms and conditions of this Public License,
          the Licensor hereby grants You a worldwide, royalty-free,
          non-sublicensable, non-exclusive, irrevocable license to
          exercise the Licensed Rights in the Licensed Material to:

            a. reproduce and Share the Licensed Material, in whole or
               in part; and

            b. produce, reproduce, and Share Adapted Material.

       2. Exceptions and Limitations. For the avoidance of doubt, where
          Exceptions and Limitations apply to Your use, this Public
          License does not apply, and You do not need to comply with
          its terms and conditions.

       3. Term. The term of this Public License is specified in Section
          6(a).

       4. Media and formats; technical modifications allowed. The
          Licensor authorizes You to exercise the Licensed Rights in
          all media and formats whether now known or hereafter created,
          and to make technical modifications necessary to do so. The
          Licensor waives and/or agrees not to assert any right or
          authority to forbid You from making technical modifications
          necessary to exercise the Licensed Rights, including
          technical modifications necessary to circumvent Effective
          Technological Measures. For purposes of this Public License,
          simply making modifications authorized by this Section 2(a)
          (4) never produces Adapted Material.

       5. Downstream recipients.

            a. Offer from the Licensor -- Licensed Material. Every
               recipient of the Licensed Material automatically
               receives an offer from the Licensor to exercise the
               Licensed Rights under the terms and conditions of this
               Public License.

            b. No downstream restrictions. You may not offer or impose
               any additional or different terms or conditions on, or
               apply any Effective Technological Measures to, the
               Licensed Material if doing so restricts exercise of the
               Licensed Rights by any recipient of the Licensed
               Material.

       6. No endorsement. Nothing in this Public License constitutes or
          may be construed as permission to assert or imply that You
          are, or that Your use of the Licensed Material is, connected
          with, or sponsored, endorsed, or granted official status by,
          the Licensor or others designated to receive attribution as
          provided in Section 3(a)(1)(A)(i).

  b. Other rights.

       1. Moral rights, such as the right of integrity, are not
          licensed under this Public License, nor are publicity,
          privacy, and/or other similar personality rights; however, to
          the extent possible, the Licensor waives and/or agrees not to
          assert any such rights held by the Licensor to the limited
          extent necessary to allow You to exercise the Licensed
          Rights, but not otherwise.

       2. Patent and trademark rights are not licensed under this
          Public License.

       3. To the extent possible, the Licensor waives any right to
          collect royalties from You for the exercise of the Licensed
          Rights, whether directly or through a collecting society
          under any voluntary or waivable statutory or compulsory
          licensing scheme. In all other cases the Licensor expressly
          reserves any right to collect such royalties.


Section 3 -- License Conditions.

Your exercise of the Licensed Rights is expressly made subject to the
following conditions.

  a. Attribution.

       1. If You Share the Licensed Material (including in modified
          form), You must:

            a. retain the following if it is supplied by the Licensor
               with the Licensed Material:

                 i. identification of the creator(s) of the Licensed
                    Material and any others designated to receive
                    attribution, in any reasonable manner requested by
                    the Licensor (including by pseudonym if
                    designated);

                ii. a copyright notice;

               iii. a notice that refers to this Public License;

                iv. a notice that refers to the disclaimer of
                    warranties;

                 v. a URI or hyperlink to the Licensed Material to the
                    extent reasonably practicable;

            b. indicate if You modified the Licensed Material and
               retain an indication of any previous modifications; and

            c. indicate the Licensed Material is licensed under this
               Public License, and include the text of, or the URI or
               hyperlink to, this Public License.

       2. You may satisfy the conditions in Section 3(a)(1) in any
          reasonable manner based on the medium, means, and context in
          which You Share the Licensed Material. For example, it may be
          reasonable to satisfy the conditions by providing a URI or
          hyperlink to a resource that includes the required
          information.

       3. If requested by the Licensor, You must remove any of the
          information required by Section 3(a)(1)(A) to the extent
          reasonably practicable.

       4. If You Share Adapted Material You produce, the Adapter's
          License You apply must not prevent recipients of the Adapted
          Material from complying with this Public License.


Section 4 -- Sui Generis Database Rights.

Where the Licensed Rights include Sui Generis Database Rights that
apply to Your use of the Licensed Material:

  a. for the avoidance of doubt, Section 2(a)(1) grants You the right
     to extract, reuse, reproduce, and Share all or a substantial
     portion of the contents of the database;

  b. if You include all or a substantial portion of the database
     contents in a database in which You have Sui Generis Database
     Rights, then the database in which You have Sui Generis Database
     Rights (but not its individual contents) is Adapted Material; and

  c. You must comply with the conditions in Section 3(a) if You Share
     all or a substantial portion of the contents of the database.

For the avoidance of doubt, this Section 4 supplements and does not
replace Your obligations under this Public License where the Licensed
Rights include other Copyright and Similar Rights.


Section 5 -- Disclaimer of Warranties and Limitation of Liability.

  a. UNLESS OTHERWISE SEPARATELY UNDERTAKEN BY THE LICENSOR, TO THE
     EXTENT POSSIBLE, THE LICENSOR OFFERS THE LICENSED MATERIAL AS-IS
     AND AS-AVAILABLE, AND MAKES NO REPRESENTATIONS OR WARRANTIES OF
     ANY KIND CONCERNING THE LICENSED MATERIAL, WHETHER EXPRESS,
     IMPLIED, STATUTORY, OR OTHER. THIS INCLUDES, WITHOUT LIMITATION,
     WARRANTIES OF TITLE, MERCHANTABILITY, FITNESS FOR A PARTICULAR
     PURPOSE, NON-INFRINGEMENT, ABSENCE OF LATENT OR OTHER DEFECTS,
     ACCURACY, OR THE PRESENCE OR ABSENCE OF ERRORS, WHETHER OR NOT
     KNOWN OR DISCOVERABLE. WHERE DISCLAIMERS OF WARRANTIES ARE NOT
     ALLOWED IN FULL OR IN PART, THIS DISCLAIMER MAY NOT APPLY TO YOU.

  b. TO THE EXTENT POSSIBLE, IN NO EVENT WILL THE LICENSOR BE LIABLE
     TO YOU ON ANY LEGAL THEORY (INCLUDING, WITHOUT LIMITATION,
     NEGLIGENCE) OR OTHERWISE FOR ANY DIRECT, SPECIAL, INDIRECT,
     INCIDENTAL, CONSEQUENTIAL, PUNITIVE, EXEMPLARY, OR OTHER LOSSES,
     COSTS, EXPENSES, OR DAMAGES ARISING OUT OF THIS PUBLIC LICENSE OR
     USE OF THE LICENSED MATERIAL, EVEN IF THE LICENSOR HAS BEEN
     ADVISED OF THE POSSIBILITY OF SUCH LOSSES, COSTS, EXPENSES, OR
     DAMAGES. WHERE A LIMITATION OF LIABILITY IS NOT ALLOWED IN FULL OR
     IN PART, THIS LIMITATION MAY NOT APPLY TO YOU.

  c. The disclaimer of warranties and limitation of liability provided
     above shall be interpreted in a manner that, to the extent
     possible, most closely approximates an absolute disclaimer and
     waiver of all liability.


Section 6 -- Term and Termination.

  a. This Public License applies for the term of the Copyright and
     Similar Rights licensed here. However, if You fail to comply with
     this Public License, then Your rights under this Public License
     terminate automatically.

  b. Where Your right to use the Licensed Material has terminated under
     Section 6(a), it reinstates:

       1. automatically as of the date the violation is cured, provided
          it is cured within 30 days of Your discovery of the
          violation; or

       2. upon express reinstatement by the Licensor.

     For the avoidance of doubt, this Section 6(b) does not affect any
     right the Licensor may have to seek remedies for Your violations
     of this Public License.

  c. For the avoidance of doubt, the Licensor may also offer the
     Licensed Material under separate terms or conditions or stop
     distributing the Licensed Material at any time; however, doing so
     will not terminate this Public License.

  d. Sections 1, 5, 6, 7, and 8 survive termination of this Public
     License.


Section 7 -- Other Terms and Conditions.

  a. The Licensor shall not be bound by any additional or different
     terms or conditions communicated by You unless expressly agreed.

  b. Any arrangements, understandings, or agreements regarding the
     Licensed Material not stated herein are separate from and
     independent of the terms and conditions of this Public License.


Section 8 -- Interpretation.

  a. For the avoidance of doubt, this Public License does not, and
     shall not be interpreted to, reduce, limit, restrict, or impose
     conditions on any use of the Licensed Material that could lawfully
     be made without permission under this Public License.

  b. To the extent possible, if any provision of this Public License is
     deemed unenforceable, it shall be automatically reformed to the
     minimum extent necessary to make it enforceable. If the provision
     cannot be reformed, it shall be severed from this Public License
     without affecting the enforceability of the remaining terms and
     conditions.

  c. No term or condition of this Public License will be waived and no
     failure to comply consented to unless expressly agreed to by the
     Licensor.

  d. Nothing in this Public License constitutes or may be interpreted
     as a limitation upon, or waiver of, any privileges and immunities
     that apply to the Licensor or You, including from the legal
     processes of any jurisdiction or authority.


=======================================================================

Creative Commons is not a party to its public
licenses. Notwithstanding, Creative Commons may elect to apply one of
its public licenses to material it publishes and in those instances
will be considered the "Licensor." The text of the Creative Commons
public licenses is dedicated to the public domain under the CC0 Public
Domain Dedication. Except for the limited purpose of indicating that
material is shared under a Creative Commons public license or as
otherwise permitted by the Creative Commons policies published at
creativecommons.org/policies, Creative Commons does not authorize the
use of the trademark "Creative Commons" or any other trademark or logo
of Creative Commons without its prior written consent including,
without limitation, in connection with any unauthorized modifications
to any of its public licenses or any other arrangements,
understandings, or agreements concerning use of licensed material. For
the avoidance of doubt, this paragraph does not form part of the
public licenses.

Creative Commons may be contacted at creativecommons.org.
```

---

## `lw-watchtower/skills/vibesec/SKILL.md`

| | |
| --- | --- |
| Upstream | https://github.com/BehiSecc/VibeSec-Skill |
| Upstream path | `SKILL.md` |
| Commit | `0590993b35ad51961f65a4d01cf1196dfead05bb` |
| Retrieved | 2026-09-07 |
| SPDX | `Apache-2.0` |

`Changes: none` — byte-identical to the upstream blob at that commit. The upstream repository holds
exactly three files — `SKILL.md`, `README.md` and `LICENSE`. Only `SKILL.md` was vendored; the
licence is discharged by the sibling `lw-watchtower/LICENSE`, as § 4(a) below explains.

### Apache-2.0 § 4, condition by condition

* **§ 4(a) — give every recipient a copy of the License.** The copy is the sibling file
  **`lw-watchtower/LICENSE`**, inside this payload and beside this one, so it reaches everyone who
  receives `SKILL.md`. A second verbatim copy is not reproduced here, and that is a measured
  decision rather than a shortcut: this project is itself Apache-2.0, and the two licence texts were
  compared — **every line from the title through § 9 is identical**, byte for byte. They differ only
  in the optional boilerplate APPENDIX, where this repository has filled in
  `Copyright 2026 LEAPWare` and upstream left the `[yyyy] [name of copyright owner]` placeholder
  standing. **That appendix line is this project's copyright statement over its own work and does
  not extend to the vendored file**, whose copyright is upstream's.
* **§ 4(b) — state changes prominently.** There are none. The file is unmodified, which is stated
  above and provable from the blob hash.
* **§ 4(c) — retain the notices in the Source form.** Nothing was removed. Upstream's `SKILL.md`
  carries no copyright, patent, trademark or attribution notice of its own to retain, and its
  `LICENSE` leaves the copyright appendix unfilled, so **upstream declares no named copyright owner
  anywhere in the repository.** None is invented here; the work is attributed to its publisher,
  **BehiSecc**, at the URL above.
* **§ 4(d) — the NOTICE file. Not triggered.** Checked rather than assumed: upstream ships **no
  `NOTICE` file** at the pinned commit. § 4(d) applies only "if the Work includes a `NOTICE` text
  file", so there is nothing to reproduce. This is written down instead of left silent because a
  reader cannot tell an absent obligation from an unchecked one.

---

## How this file is kept honest

`tests/payload_guard.ps1` case **S17** enumerates every tracked `.md` under `lw-watchtower/skills/`
and `lw-watchtower/context/stack/` from the git index, treats absence of the house
`Shipped by the LW-WATCHTOWER plugin` header as the mark of a vendored file, and **fails when a
vendored path is not spelled in this file.** It reads the tree rather than a list, so a seventh
vendored body cannot land without this file growing a block for it, and a vendored file deleted
without its notice being removed is visible in the same run.

Case **S14** lints every shipped frontmatter block, including the four vendored ones. It was
rewritten in the same commit that added these files, to parse the folded block scalar that
`task-observer/SKILL.md` opens with — the guard changed so the vendored file would not have to.
