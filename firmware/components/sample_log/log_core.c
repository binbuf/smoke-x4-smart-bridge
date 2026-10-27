/*
 * log_core.c - firmware-facing sample-record codec and raw ring geometry.
 *
 * T17 part: the generated protocol codec owns the bytes; this file owns the
 * record semantics: compile-time size agreement, explicit wire size, and the
 * sentinel/attach-bit consistency rule.
 *
 * T18 part: the ring over log_io.h - sector headers, append/rotation, sequence
 * and generation tracking, and boot recovery. No ESP-IDF, no heap.
 * See log_core.h and design 04 section 4.3.
 */

#include "log_core.h"

#include <string.h>

size_t sample_log_record_size(void) { return SAMPLE_LOG_RECORD_SIZE; }

bool sample_log_record_probe_attached(const sx4_sample_rec_t *rec,
                                      unsigned probe) {
    if (rec == NULL || probe >= 4u) {
        return false;
    }
    return (rec->flags & (uint8_t)(1u << probe)) != 0;
}

bool sample_log_record_validate(const sx4_sample_rec_t *rec) {
    if (rec == NULL) {
        return false;
    }
    for (unsigned probe = 0; probe < 4u; probe++) {
        const bool attached = sample_log_record_probe_attached(rec, probe);
        const bool detached = sx4_temp_is_detached(rec->temp[probe]);
        /* The fast-filter bit must agree with the sentinel in both
         * directions: attached=0 with a numeric temp is corrupt, and
         * attached=1 with TEMP_DETACHED is equally corrupt. */
        if (attached == detached) {
            return false;
        }
    }
    return true;
}

sample_log_status_t sample_log_record_encode(const sx4_sample_rec_t *rec,
                                             uint8_t *out, size_t cap) {
    if (rec == NULL || out == NULL) {
        return SAMPLE_LOG_ERR_ARGUMENT;
    }
    if (cap < SAMPLE_LOG_RECORD_SIZE) {
        return SAMPLE_LOG_ERR_SIZE;
    }
    if (!sample_log_record_validate(rec)) {
        return SAMPLE_LOG_ERR_LAYOUT;
    }
    /* The generated encoder returns 0 on failure; cap was already checked. */
    if (sx4_sample_rec_encode(rec, out, cap) != SAMPLE_LOG_RECORD_SIZE) {
        return SAMPLE_LOG_ERR_SIZE;
    }
    return SAMPLE_LOG_OK;
}

sample_log_status_t sample_log_record_decode(const uint8_t *in, size_t len,
                                             sx4_sample_rec_t *out) {
    if (in == NULL || out == NULL) {
        return SAMPLE_LOG_ERR_ARGUMENT;
    }
    if (len < SAMPLE_LOG_RECORD_SIZE) {
        return SAMPLE_LOG_ERR_SIZE;
    }

    /* Decode into a local so a rejected record never exposes partial data. */
    sx4_sample_rec_t decoded;
    memset(&decoded, 0, sizeof(decoded));
    if (!sx4_sample_rec_decode(in, SAMPLE_LOG_RECORD_SIZE, &decoded)) {
        return SAMPLE_LOG_ERR_CRC;
    }
    if (!sample_log_record_validate(&decoded)) {
        return SAMPLE_LOG_ERR_LAYOUT;
    }

    *out = decoded;
    return SAMPLE_LOG_OK;
}

/* ── Ring geometry over log_io ─────────────────────────────────────────── */

static uint32_t sector_base(const log_ring_t *ring, uint32_t sector) {
    (void)ring;
    return sector * SAMPLE_LOG_SECTOR_SIZE;
}

static uint32_t record_base(const log_ring_t *ring, uint32_t sector,
                            uint16_t index) {
    (void)ring;
    return sector * SAMPLE_LOG_SECTOR_SIZE + SAMPLE_LOG_HEADER_SIZE +
           (uint32_t)index * SAMPLE_LOG_RECORD_SIZE;
}

static bool header_copy_valid(const uint8_t *raw, sx4_sector_header_t *out) {
    if (!sx4_sector_header_decode(raw, SAMPLE_LOG_HEADER_COPY_SIZE, out)) {
        return false;
    }
    /* The generated decoder checks the CRC; magic/version are the format gate
     * that lets a future layout be rejected rather than misread. */
    if (memcmp(out->magic, "SX4L", 4) != 0 || out->version != 1u) {
        return false;
    }
    return true;
}

static sample_log_status_t read_headers(log_ring_t *ring, uint32_t sector,
                                        bool *a_ok, sx4_sector_header_t *a,
                                        bool *b_ok, sx4_sector_header_t *b) {
    uint8_t raw[SAMPLE_LOG_HEADER_SIZE];
    if (log_io_read(&ring->io, sector_base(ring, sector), raw, sizeof raw) !=
        LOG_IO_OK) {
        return SAMPLE_LOG_ERR_IO;
    }
    *a_ok = header_copy_valid(raw, a);
    *b_ok = header_copy_valid(raw + SAMPLE_LOG_HEADER_COPY_SIZE, b);
    return SAMPLE_LOG_OK;
}

static sample_log_status_t write_sector_header(log_ring_t *ring,
                                               uint32_t sector,
                                               uint32_t first_seq) {
    sx4_sector_header_t header;
    memset(&header, 0, sizeof header);
    sx4_sector_header_first_seq_set(&header, first_seq);
    header.generation = ring->generation;

    uint8_t raw[SAMPLE_LOG_HEADER_SIZE];
    if (sx4_sector_header_encode(&header, raw, SAMPLE_LOG_HEADER_COPY_SIZE) !=
            SAMPLE_LOG_HEADER_COPY_SIZE ||
        sx4_sector_header_encode(&header, raw + SAMPLE_LOG_HEADER_COPY_SIZE,
                                 SAMPLE_LOG_HEADER_COPY_SIZE) !=
            SAMPLE_LOG_HEADER_COPY_SIZE) {
        return SAMPLE_LOG_ERR_STATE;
    }
    if (log_io_write(&ring->io, sector_base(ring, sector), raw, sizeof raw) !=
        LOG_IO_OK) {
        return SAMPLE_LOG_ERR_IO;
    }

    /* Headers are the only metadata; verify both copies actually landed. */
    uint8_t readback[SAMPLE_LOG_HEADER_SIZE];
    if (log_io_read(&ring->io, sector_base(ring, sector), readback,
                    sizeof readback) != LOG_IO_OK) {
        return SAMPLE_LOG_ERR_IO;
    }
    sx4_sector_header_t a;
    sx4_sector_header_t b;
    if (!header_copy_valid(readback, &a) ||
        !header_copy_valid(readback + SAMPLE_LOG_HEADER_COPY_SIZE, &b)) {
        return SAMPLE_LOG_ERR_IO;
    }
    if (a.generation != ring->generation || b.generation != ring->generation ||
        sx4_sector_header_first_seq_get(&a) != first_seq ||
        sx4_sector_header_first_seq_get(&b) != first_seq) {
        return SAMPLE_LOG_ERR_IO;
    }
    return SAMPLE_LOG_OK;
}

static bool sector_is_live(const log_ring_t *ring, uint32_t sector) {
    return (ring->live_bitmap[sector / 8u] &
            (uint8_t)(1u << (sector % 8u))) != 0;
}

static void sector_set_live(log_ring_t *ring, uint32_t sector, bool live) {
    uint8_t mask = (uint8_t)(1u << (sector % 8u));
    if (live) {
        ring->live_bitmap[sector / 8u] |= mask;
    } else {
        ring->live_bitmap[sector / 8u] &= (uint8_t)~mask;
    }
}

/*
 * Scan the record area until the first bad CRC/layout or a sequence gap.
 * A gap is treated like a bad tail: a valid-looking later record must not be
 * accepted past a torn write.
 */
static sample_log_status_t scan_sector_records(log_ring_t *ring,
                                               uint32_t sector,
                                               uint16_t *count,
                                               uint32_t *first_seq,
                                               uint32_t *last_seq) {
    uint8_t raw[SAMPLE_LOG_RECORD_SIZE];
    *count = 0;
    *first_seq = 0;
    *last_seq = 0;

    for (uint16_t i = 0; i < SAMPLE_LOG_RECORDS_PER_SECTOR; i++) {
        if (log_io_read(&ring->io, record_base(ring, sector, i), raw,
                        sizeof raw) != LOG_IO_OK) {
            return SAMPLE_LOG_ERR_IO;
        }
        sx4_sample_rec_t rec;
        if (sample_log_record_decode(raw, sizeof raw, &rec) != SAMPLE_LOG_OK) {
            break;
        }
        const uint32_t seq = sx4_sample_rec_seq_get(&rec);
        if (*count != 0) {
            const uint32_t expected = (*last_seq + 1u) & SAMPLE_LOG_SEQ_MAX;
            if (seq != expected) {
                break;
            }
        } else {
            *first_seq = seq;
        }
        *last_seq = seq;
        (*count)++;
    }
    return SAMPLE_LOG_OK;
}

/* Rebuild min_seq/tail_sector from the surviving headers after an eviction. */
static sample_log_status_t recompute_min(log_ring_t *ring) {
    bool any = false;
    ring->min_seq = 0;
    ring->tail_sector = 0;
    for (uint32_t sector = 0; sector < ring->sector_count; sector++) {
        if (!sector_is_live(ring, sector)) {
            continue;
        }
        bool a_ok;
        bool b_ok;
        sx4_sector_header_t a;
        sx4_sector_header_t b;
        if (read_headers(ring, sector, &a_ok, &a, &b_ok, &b) !=
            SAMPLE_LOG_OK) {
            return SAMPLE_LOG_ERR_IO;
        }
        uint32_t first = 0;
        bool have = false;
        if (a_ok && a.generation == ring->generation) {
            first = sx4_sector_header_first_seq_get(&a);
            have = true;
        }
        if (b_ok && b.generation == ring->generation) {
            const uint32_t bf = sx4_sector_header_first_seq_get(&b);
            if (!have || bf < first) {
                first = bf;
                have = true;
            }
        }
        if (!have) {
            return SAMPLE_LOG_ERR_IO;
        }
        if (!any || first < ring->min_seq) {
            ring->min_seq = first;
            ring->tail_sector = sector;
            any = true;
        }
    }
    return SAMPLE_LOG_OK;
}

static sample_log_status_t erase_and_start_sector(log_ring_t *ring,
                                                  uint32_t sector) {
    if (log_io_erase(&ring->io, sector_base(ring, sector),
                     SAMPLE_LOG_SECTOR_SIZE) != LOG_IO_OK) {
        return SAMPLE_LOG_ERR_IO;
    }
    sample_log_status_t status =
        write_sector_header(ring, sector, ring->next_seq);
    if (status != SAMPLE_LOG_OK) {
        return status;
    }
    sector_set_live(ring, sector, true);
    ring->live_sectors++;
    ring->head_sector = sector;
    ring->head_record = 0;
    ring->head_ready = true;
    return SAMPLE_LOG_OK;
}

static sample_log_status_t advance_head(log_ring_t *ring) {
    uint32_t sector = (ring->head_sector + 1u) % ring->sector_count;

    if (ring->live_sectors >= ring->sector_count) {
        /* Every sector is live, so the next physical one is the oldest. */
        if (!sector_is_live(ring, sector)) {
            return SAMPLE_LOG_ERR_STATE;
        }
        if (ring->count < SAMPLE_LOG_RECORDS_PER_SECTOR) {
            return SAMPLE_LOG_ERR_STATE;
        }
        ring->count -= SAMPLE_LOG_RECORDS_PER_SECTOR;
        sector_set_live(ring, sector, false);
        ring->live_sectors--;
        if (recompute_min(ring) != SAMPLE_LOG_OK) {
            return SAMPLE_LOG_ERR_IO;
        }
    } else {
        /* A failed sector can leave a hole; skip live sectors to keep their
         * records instead of overwriting them. */
        uint32_t steps = 0;
        while (sector_is_live(ring, sector)) {
            sector = (sector + 1u) % ring->sector_count;
            if (++steps >= ring->sector_count) {
                return SAMPLE_LOG_ERR_STATE;
            }
        }
    }
    return erase_and_start_sector(ring, sector);
}

sample_log_status_t log_ring_mount(log_ring_t *ring, const log_io_t *io,
                                   bool have_generation, uint32_t generation) {
    if (ring == NULL || io == NULL || io->ops == NULL ||
        io->ops->read == NULL || io->ops->write == NULL ||
        io->ops->erase == NULL) {
        return SAMPLE_LOG_ERR_ARGUMENT;
    }
    if (io->sector_size != SAMPLE_LOG_SECTOR_SIZE || io->capacity == 0 ||
        io->capacity % SAMPLE_LOG_SECTOR_SIZE != 0) {
        return SAMPLE_LOG_ERR_RANGE;
    }
    const uint32_t sectors = io->capacity / SAMPLE_LOG_SECTOR_SIZE;
    if (sectors == 0 || sectors > SAMPLE_LOG_MAX_SECTORS) {
        return SAMPLE_LOG_ERR_RANGE;
    }

    memset(ring, 0, sizeof *ring);
    ring->io = *io;
    ring->sector_count = sectors;
    ring->failed = false;

    /* Pass 1: pick the generation. A supplied (NVS) value always wins. */
    bool have_best = false;
    uint32_t best_seq = 0;
    uint32_t best_generation = 0;
    for (uint32_t sector = 0; sector < sectors; sector++) {
        bool a_ok;
        bool b_ok;
        sx4_sector_header_t a;
        sx4_sector_header_t b;
        sample_log_status_t status =
            read_headers(ring, sector, &a_ok, &a, &b_ok, &b);
        if (status != SAMPLE_LOG_OK) {
            return status;
        }
        if (a_ok) {
            const uint32_t seq = sx4_sector_header_first_seq_get(&a);
            if (!have_best || seq > best_seq) {
                best_seq = seq;
                best_generation = a.generation;
                have_best = true;
            }
        }
        if (b_ok) {
            const uint32_t seq = sx4_sector_header_first_seq_get(&b);
            if (!have_best || seq > best_seq) {
                best_seq = seq;
                best_generation = b.generation;
                have_best = true;
            }
        }
    }

    if (have_generation) {
        ring->generation = generation;
        ring->generation_known = true;
    } else if (have_best) {
        ring->generation = best_generation;
        ring->generation_known = true;
    } else {
        ring->generation_known = false;
        ring->needs_format = true;
        return SAMPLE_LOG_OK;
    }
    /* Pass 2: adopt matching sectors, stop each scan at its first bad tail. */
    bool any_records = false;
    uint32_t head_last = 0;
    uint32_t min_seq = 0;
    uint32_t head_sector = 0;
    uint32_t tail_sector = 0;
    uint16_t head_record = 0;
    uint32_t count = 0;

    for (uint32_t sector = 0; sector < sectors; sector++) {
        bool a_ok;
        bool b_ok;
        sx4_sector_header_t a;
        sx4_sector_header_t b;
        sample_log_status_t status =
            read_headers(ring, sector, &a_ok, &a, &b_ok, &b);
        if (status != SAMPLE_LOG_OK) {
            return status;
        }
        const bool a_match = a_ok && a.generation == ring->generation;
        const bool b_match = b_ok && b.generation == ring->generation;

        if (!a_match && !b_match) {
            if (a_ok || b_ok) {
                /* Header is valid but from another generation: reclaim later. */
                continue;
            }
            /* Without a known current generation there is no proof that a
             * headerless sector belongs to this log, so never adopt it. */
            if (!have_generation) {
                continue;
            }
        }

        uint16_t records = 0;
        uint32_t first = 0;
        uint32_t last = 0;
        status = scan_sector_records(ring, sector, &records, &first, &last);
        if (status != SAMPLE_LOG_OK) {
            return status;
        }
        if (records == 0) {
            continue; /* header-only or blank sector: empty/reclaimable */
        }

        bool header_agrees =
            (a_match && sx4_sector_header_first_seq_get(&a) == first) ||
            (b_match && sx4_sector_header_first_seq_get(&b) == first);
        if (!header_agrees) {
            /* The generation is known and the records are valid: repair a
             * missing or torn header from the first committed record. */
            status = write_sector_header(ring, sector, first);
            if (status != SAMPLE_LOG_OK) {
                return status;
            }
        }

        sector_set_live(ring, sector, true);
        ring->live_sectors++;
        count += records;
        if (!any_records || first < min_seq) {
            min_seq = first;
            tail_sector = sector;
        }
        if (!any_records || last > head_last) {
            head_last = last;
            head_sector = sector;
            head_record = records;
        }
        any_records = true;
    }

    ring->count = count;
    if (!any_records) {
        ring->min_seq = 0;
        ring->max_seq = 0;
        ring->next_seq = 0;
        ring->head_sector = 0;
        ring->tail_sector = 0;
        ring->head_record = 0;
        ring->head_ready = false;
        ring->needs_format = false;
        return SAMPLE_LOG_OK;
    }

    ring->min_seq = min_seq;
    ring->max_seq = head_last;
    ring->next_seq = head_last + 1u;
    ring->head_sector = head_sector;
    ring->tail_sector = tail_sector;
    ring->head_record = head_record;
    ring->head_ready = true;
    ring->needs_format = false;
    return SAMPLE_LOG_OK;
}

sample_log_status_t log_ring_format(log_ring_t *ring, uint32_t generation) {
    if (ring == NULL || ring->sector_count == 0 || ring->io.ops == NULL) {
        return SAMPLE_LOG_ERR_ARGUMENT;
    }
    memset(ring->live_bitmap, 0, sizeof ring->live_bitmap);
    ring->generation = generation;
    ring->generation_known = true;
    ring->needs_format = false;
    ring->min_seq = 0;
    ring->max_seq = 0;
    ring->next_seq = 0;
    ring->count = 0;
    ring->head_sector = 0;
    ring->tail_sector = 0;
    ring->head_record = 0;
    ring->live_sectors = 0;
    ring->head_ready = false;
    ring->failed = false;
    return SAMPLE_LOG_OK;
}

sample_log_status_t log_ring_append(log_ring_t *ring, sx4_sample_rec_t *rec) {
    if (ring == NULL || rec == NULL) {
        return SAMPLE_LOG_ERR_ARGUMENT;
    }
    if (!ring->generation_known || ring->sector_count == 0) {
        return SAMPLE_LOG_ERR_STATE;
    }
    if (ring->failed) {
        return SAMPLE_LOG_ERR_STATE;
    }
    if (ring->next_seq > SAMPLE_LOG_SEQ_MAX) {
        return SAMPLE_LOG_ERR_RANGE;
    }

    if (ring->head_ready &&
        ring->head_record >= SAMPLE_LOG_RECORDS_PER_SECTOR) {
        if (advance_head(ring) != SAMPLE_LOG_OK) {
            ring->failed = true;
            return SAMPLE_LOG_ERR_IO;
        }
    }
    if (!ring->head_ready) {
        if (erase_and_start_sector(ring, ring->head_sector) != SAMPLE_LOG_OK) {
            ring->failed = true;
            return SAMPLE_LOG_ERR_IO;
        }
    }

    sx4_sample_rec_t assigned = *rec;
    const uint32_t seq = ring->next_seq;
    sx4_sample_rec_seq_set(&assigned, seq);

    uint8_t raw[SAMPLE_LOG_RECORD_SIZE];
    if (sample_log_record_encode(&assigned, raw, sizeof raw) !=
        SAMPLE_LOG_OK) {
        return SAMPLE_LOG_ERR_LAYOUT;
    }
    if (log_io_write(&ring->io,
                     record_base(ring, ring->head_sector, ring->head_record),
                     raw, sizeof raw) != LOG_IO_OK) {
        /* A torn tail is left for recovery; never advance past it. */
        ring->failed = true;
        return SAMPLE_LOG_ERR_IO;
    }

    if (ring->count == 0) {
        ring->min_seq = seq;
        ring->tail_sector = ring->head_sector;
    }
    ring->max_seq = seq;
    ring->next_seq = seq + 1u;
    ring->count++;
    ring->head_record++;
    *rec = assigned;
    return SAMPLE_LOG_OK;
}

sample_log_status_t log_ring_read_seq(log_ring_t *ring, uint32_t seq,
                                      sx4_sample_rec_t *out) {
    if (ring == NULL || out == NULL) {
        return SAMPLE_LOG_ERR_ARGUMENT;
    }
    if (!ring->generation_known || seq > SAMPLE_LOG_SEQ_MAX) {
        return SAMPLE_LOG_ERR_RANGE;
    }
    if (ring->count == 0 || seq < ring->min_seq || seq > ring->max_seq) {
        return SAMPLE_LOG_ERR_RANGE;
    }

    for (uint32_t sector = 0; sector < ring->sector_count; sector++) {
        if (!sector_is_live(ring, sector)) {
            continue;
        }
        bool a_ok;
        bool b_ok;
        sx4_sector_header_t a;
        sx4_sector_header_t b;
        if (read_headers(ring, sector, &a_ok, &a, &b_ok, &b) !=
            SAMPLE_LOG_OK) {
            return SAMPLE_LOG_ERR_IO;
        }
        for (unsigned copy = 0; copy < 2u; copy++) {
            const bool ok = copy == 0 ? a_ok : b_ok;
            const sx4_sector_header_t *header = copy == 0 ? &a : &b;
            if (!ok || header->generation != ring->generation) {
                continue;
            }
            const uint32_t first = sx4_sector_header_first_seq_get(header);
            if (seq < first) {
                continue;
            }
            const uint32_t index = seq - first;
            if (index >= SAMPLE_LOG_RECORDS_PER_SECTOR) {
                continue;
            }
            uint8_t raw[SAMPLE_LOG_RECORD_SIZE];
            if (log_io_read(&ring->io,
                            record_base(ring, sector, (uint16_t)index), raw,
                            sizeof raw) != LOG_IO_OK) {
                return SAMPLE_LOG_ERR_IO;
            }
            sx4_sample_rec_t decoded;
            const sample_log_status_t status =
                sample_log_record_decode(raw, sizeof raw, &decoded);
            if (status != SAMPLE_LOG_OK) {
                return status;
            }
            if (sx4_sample_rec_seq_get(&decoded) != seq) {
                return SAMPLE_LOG_ERR_CRC;
            }
            *out = decoded;
            return SAMPLE_LOG_OK;
        }
    }
    return SAMPLE_LOG_ERR_RANGE;
}

void log_ring_info(const log_ring_t *ring, log_ring_info_t *out) {
    if (ring == NULL || out == NULL) {
        return;
    }
    out->generation = ring->generation;
    out->min_seq = ring->min_seq;
    out->max_seq = ring->max_seq;
    out->next_seq = ring->next_seq;
    out->count = ring->count;
    out->live_sectors = ring->live_sectors;
    out->sector_count = ring->sector_count;
    out->generation_known = ring->generation_known;
    out->needs_format = ring->needs_format;
}
