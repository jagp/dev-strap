# The Pines Digitization & Archive LLM — Project Plan

A roadmap for digitizing the on-premises document collection at The Pines
(Skaneateles Lake, NY) and building an AI-queryable family archive from it.

**The one constraint that shapes everything:** physical access to the documents
ends Friday. Image capture is the only step that cannot be redone from home, so
the week on-site is spent entirely on capture and provenance. Every other phase
(transcription, structuring, the LLM layer) works from the images and can happen
anywhere, anytime.

## Phase overview

| Phase | What | When | Where |
|-------|------|------|-------|
| 0 | Capture: photograph every page + record provenance | Mon–Fri (this week) | On-site |
| 1 | Transcription: OCR typed pages, vision-LLM the handwritten ones | Weeks 2–4 | Anywhere |
| 2 | Structured archive: metadata, entities, timeline, searchable index | Weeks 4–8 | Anywhere |
| 3 | LLM layer: RAG chat over the corpus ("Ask The Pines") | Weeks 8+ | Anywhere |

---

## Phase 0 — Capture (this week, on-site)

Full field procedure lives in [CAPTURE-GUIDE.md](CAPTURE-GUIDE.md). The short
version:

- **Phone camera beats scanners here.** Legal-size (8.5×14) pages exceed most
  consumer flatbeds, and bound diaries can't go through a sheet feeder. A phone
  on an improvised copy stand with good indirect light captures a page in
  seconds at plenty of resolution for OCR and handwriting transcription.
- **Capture, don't process.** No OCR, no cropping, no organizing beyond the
  naming convention on-site. Raw images plus the capture log are the deliverable.
- **Provenance is also expiring Friday.** The cousins who know what these
  documents are and where they came from are on the property right now. Voice
  memos of "walk me through this box" conversations are as valuable as the
  scans, and only capturable this week.
- **Nightly 3-2-1 backup.** Phone → laptop → cloud, every evening. One
  unverified copy of an irreplaceable archive is a single point of failure.

**Throughput sanity check:** several hundred documents at an average of ~3 pages
each is roughly 1,000–1,500 pages. A settled phone-rig rhythm runs 10–15
seconds per page, so pure capture time is 4–6 hours — comfortably three
90-minute sessions per day Tuesday through Thursday, with Monday for setup and
a pilot batch, and Friday for the gap sweep.

**Priority order if time runs short** (most irreplaceable first):

1. Handwritten diaries, journals, letters — unique, fragile, hardest to re-create
2. Pines Inc. / Skaneateles China company records — likely exists nowhere else
3. Legal paperwork (deeds, wills, incorporation) — copies *may* exist in county records
4. Building schematics — oversized: capture in overlapping sections plus one overview shot
5. Anything typed/printed that plausibly exists in other archives

---

## Phase 1 — Transcription (from home)

Input: the image tree from Phase 0. Output: a faithful text transcript per
document, stored next to its images.

- **Typed/printed pages** → conventional OCR (Tesseract locally, or a cloud
  document API). Cheap, fast, accurate on clean type.
- **Handwritten pages** (the diaries — probably the bulk of the interesting
  material) → vision-LLM transcription. Modern multimodal models read
  19th/20th-century cursive far better than classical HTR tools. Send each page
  image with a prompt that asks for a verbatim transcript, `[illegible]`
  markers, and a page-level confidence note. Low-confidence pages go into a
  human review queue — a good winter-evening family activity, and a way to pull
  cousins into the project.
- **Storage layout** — one directory per document, images and derived text
  together:

  ```
  archive/
    B01/                      # box
      F03/                    # folder
        D012/                 # document
          pages/PINES_B01_F03_D012_P01.jpg ...
          transcript.md       # full text, page-delimited
          meta.json           # see metadata-schema.json
  ```

Originals are immutable: transcription and everything after only ever *adds*
files next to the images, never modifies them.

## Phase 2 — Structured archive

A note on "tokenizing": there's no manual tokenization step — models tokenize
internally. What this phase actually builds is the **structured metadata and
chunked text** that retrieval (Phase 3) sits on.

- **Per-document metadata** (`meta.json`, schema in
  [metadata-schema.json](metadata-schema.json)): type, date or date range,
  author, people/places/organizations mentioned, topics, physical location in
  the archive, transcription confidence.
- **Entity registry**: one canonical list of people (starting with the three
  brothers and three sisters and descending from there), places, and
  organizations (Pines Inc., the Skaneateles china company), so "Grandpa E.",
  "Edward", and "E.J.P." resolve to one person. An LLM extraction pass over the
  transcripts proposes entities and mentions; a human approves merges.
- **Timeline**: every dated event extracted into one chronology — construction
  milestones, deeds changing hands, company events, diary entries.
- **Index**: SQLite with full-text search over transcripts + the metadata
  tables. Optionally a small static website so relatives can browse and search
  without any AI in the loop. This artifact is valuable even if Phase 3 never
  happens.

## Phase 3 — The LLM layer

**Reality check on "train a small LLM on this corpus":** a few hundred
documents is roughly 0.5–2 million tokens. Training a language model from
scratch needs billions; even heavy fine-tuning on 1M tokens produces a model
that has memorized fragments but can't answer questions reliably. The corpus is
precious, but it is small. Ranked by return on effort:

1. **RAG — recommended.** Chunk the transcripts, embed them, retrieve relevant
   passages per question, and have a frontier model answer *with citations to
   document IDs and page images*. This gives "Ask The Pines: who paid for the
   1912 roof?" → an answer quoting the actual ledger page. Best answer quality,
   no training, and the corpus can keep growing.
2. **Zero-code interim:** drop the transcripts into a Claude Project today and
   get a usable "Ask The Pines" while the real pipeline is being built. Good
   demo for the family by Thanksgiving.
3. **LoRA fine-tune of a small open model (1–8B) — optional art project.**
   Fine-tuning on the diaries can capture *voice* — a model that writes like
   the great-grandparents sounds. Delightful, but it's a stylistic toy, not the
   archive's brain. Do it after RAG works, if at all.

**Privacy note:** this corpus contains legal documents and personal diaries of
living people's ancestors. Keep the repo and any hosted index private, and make
a deliberate choice about which cloud services touch the text before uploading.

---

## Deliverables in this directory

| File | Purpose |
|------|---------|
| `PLAN.md` | This roadmap |
| `CAPTURE-GUIDE.md` | Field procedure for the on-site week: rig, app, naming, daily schedule, QA |
| `capture-log.template.csv` | Inventory spreadsheet to fill as documents are captured |
| `metadata-schema.json` | Draft JSON Schema for per-document `meta.json` (Phase 2) |
