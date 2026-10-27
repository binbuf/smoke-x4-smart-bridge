/*
 * log_core.h - firmware-facing sample-record codec and semantic validation.
 *
 * The byte layout, CRC-16/CCITT-FALSE and 24-bit sequence codec are owned by
 * the generated protocol contract (protocol/gen/records.h, from
 * protocol/records.yaml; design 04 section 4.2). This module is the single
 * firmware boundary over that generated codec: it adds the sentinel/attach-bit
 * consistency rules from design 04 and exposes the wire size explicitly, so
 * ring code (T18) never uses sizeof(sx4_sample_rec_t) as the record size.
 *
 * Pure C11: no ESP-IDF, no heap, no host-endian assumptions. A failed decode
 * leaves the caller's record untouched.
 */
#ifndef SX4_LOG_CORE_H
#define SX4_LOG_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "log_io.h"
#include "records.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Wire size of one record. Readers must use this (or sample_log_record_size())
 * rather than sizeof(). The value is 18 today; a future sector-header version
 * may grow it and readers skip the trailing bytes.
 */
#define SAMPLE_LOG_RECORD_SIZE SX4_RECORD_SIZE

_Static_assert(SAMPLE_LOG_RECORD_SIZE == 18u,
               "sample record wire size is 18 bytes");
_Static_assert(SAMPLE_LOG_RECORD_SIZE == SX4_SAMPLE_REC_SIZE,
               "wire size and packed struct size must agree");

_Static_assert(SX4_TEMP_DETACHED == -32768,
               "TEMP_DETACHED must be INT16_MIN");
_Static_assert(SX4_TEMP_INVALID == -32767,
               "TEMP_INVALID must be INT16_MIN + 1");

typedef enum {
    SAMPLE_LOG_OK = 0,
    SAMPLE_LOG_ERR_ARGUMENT = -1, /* null pointer */
    SAMPLE_LOG_ERR_SIZE = -2,     /* buffer shorter than one record */
    SAMPLE_LOG_ERR_CRC = -3,      /* CRC-16 mismatch */
    SAMPLE_LOG_ERR_LAYOUT = -4,   /* attach bit and sentinel disagree */
    SAMPLE_LOG_ERR_IO = -5,       /* log_io transport or read-back failure */
    SAMPLE_LOG_ERR_STATE = -6,    /* ring not mounted/formatted for writing */
    SAMPLE_LOG_ERR_RANGE = -7,    /* seq/sector/offset outside the ring */
} sample_log_status_t;

/* Wire size readers should use (18). */
size_t sample_log_record_size(void);

/*
 * Validate the in-memory record's sentinel/attachment consistency.
 *
 * For each of the four probes, the corresponding attached flag (bits 0..3)
 * must agree with the temperature sentinel:
 *   flag 0 -> temp == TEMP_DETACHED
 *   flag 1 -> temp != TEMP_DETACHED (TEMP_INVALID is allowed)
 *
 * A record that disagrees is corrupt and must not be encoded or accepted on
 * read. Returns true when the record is internally consistent.
 */
bool sample_log_record_validate(const sx4_sample_rec_t *rec);

/* Probe index 0..3; out-of-range or null returns false. */
bool sample_log_record_probe_attached(const sx4_sample_rec_t *rec,
                                      unsigned probe);

/*
 * Encode a record. seq is written as 24-bit little-endian, unix_s and the four
 * i16 temperatures little-endian, then the flags byte and the CRC over bytes
 * 0..15. Returns SAMPLE_LOG_OK and sets *out to SAMPLE_LOG_RECORD_SIZE bytes.
 *
 * SAMPLE_LOG_ERR_LAYOUT is returned (nothing written) when validation fails.
 */
sample_log_status_t sample_log_record_encode(const sx4_sample_rec_t *rec,
                                             uint8_t *out, size_t cap);

/*
 * Decode and verify one record.
 *
 * *in may contain more than one record; only the first SAMPLE_LOG_RECORD_SIZE
 * bytes are consumed, so callers can advance by sample_log_record_size().
 * Returns SAMPLE_LOG_ERR_CRC for a bad CRC and SAMPLE_LOG_ERR_LAYOUT for an
 * attach-bit/sentinel mismatch. On any error *out is untouched.
 */
sample_log_status_t sample_log_record_decode(const uint8_t *in, size_t len,
                                             sx4_sample_rec_t *out);

/* ── Raw ring geometry (design 04 section 4.3) ─────────────────────────── */

#define SAMPLE_LOG_SECTOR_SIZE 4096u
#define SAMPLE_LOG_HEADER_COPY_SIZE 16u
#define SAMPLE_LOG_HEADER_SIZE (2u * SAMPLE_LOG_HEADER_COPY_SIZE)
#define SAMPLE_LOG_RECORDS_PER_SECTOR \
    ((SAMPLE_LOG_SECTOR_SIZE - SAMPLE_LOG_HEADER_SIZE) / SAMPLE_LOG_RECORD_SIZE)
#define SAMPLE_LOG_DEFAULT_PARTITION_BYTES 6160384u
#define SAMPLE_LOG_DEFAULT_SECTOR_COUNT \
    (SAMPLE_LOG_DEFAULT_PARTITION_BYTES / SAMPLE_LOG_SECTOR_SIZE)
#define SAMPLE_LOG_MAX_SECTORS SAMPLE_LOG_DEFAULT_SECTOR_COUNT
#define SAMPLE_LOG_CAPACITY_RECORDS \
    (SAMPLE_LOG_DEFAULT_SECTOR_COUNT * SAMPLE_LOG_RECORDS_PER_SECTOR)
#define SAMPLE_LOG_SEQ_MAX 0x00FFFFFFu

_Static_assert(SAMPLE_LOG_RECORD_SIZE == 18u, "record stride is 18 bytes");
_Static_assert(SAMPLE_LOG_HEADER_SIZE == 32u, "two 16-byte header copies");
_Static_assert(SAMPLE_LOG_RECORDS_PER_SECTOR == 225u,
               "(4096 - 32) / 18 = 225 records per sector");
_Static_assert(SAMPLE_LOG_DEFAULT_SECTOR_COUNT == 1504u,
               "6,160,384 bytes / 4096 = 1504 sectors");
_Static_assert(SAMPLE_LOG_CAPACITY_RECORDS == 338400u,
               "1,504 sectors x 225 records = 338,400 records");

/*
 * Mounted ring state. The struct is plain data: no heap, no globals, and no
 * ESP-IDF. A caller may keep it anywhere; log_ring_mount() resets it.
 *
 * Sectors are physical and fixed-size. The header of each live sector records
 * the first sequence it contains and the generation of the log. Recovery uses
 * those headers; records themselves carry the per-record CRC.
 */
typedef struct {
    log_io_t io;
    uint32_t sector_count;
    uint32_t generation;
    uint32_t min_seq;
    uint32_t max_seq;
    uint32_t next_seq;
    uint32_t count;      /* live records, not the sequence span */
    uint32_t head_sector; /* newest sector */
    uint32_t tail_sector; /* sector holding min_seq */
    uint32_t live_sectors;
    uint16_t head_record; /* next record slot in head_sector, 0..225 */
    bool generation_known;
    bool needs_format;
    bool head_ready;      /* head sector header is written and verified */
    bool failed;          /* a write failed; remount before further appends */
    uint8_t live_bitmap[(SAMPLE_LOG_MAX_SECTORS + 7u) / 8u];
} log_ring_t;

typedef struct {
    uint32_t generation;
    uint32_t min_seq;
    uint32_t max_seq;
    uint32_t next_seq;
    uint32_t count;
    uint32_t live_sectors;
    uint32_t sector_count;
    bool generation_known;
    bool needs_format;
} log_ring_info_t;

/*
 * Mount and recover a ring over io.
 *
 * have_generation=true means the caller already knows the generation (NVS).
 * Sectors whose headers carry a different generation are ignored and become
 * reclaimable. Missing/broken headers are reconstructed from valid records only
 * in this mode: the known generation is the proof that the records are current.
 *
 * have_generation=false restores the generation from the newest valid sector
 * header. If no header is readable the ring reports needs_format=true and the
 * caller must choose a fresh random generation and call log_ring_format().
 *
 * io->sector_size must be 4096 and capacity must be 1..1504 whole sectors.
 */
sample_log_status_t log_ring_mount(log_ring_t *ring, const log_io_t *io,
                                   bool have_generation, uint32_t generation);

/*
 * Start a fresh, empty log with generation. Existing sectors are not erased
 * here: they carry a different generation and are reclaimed lazily, one sector
 * at a time, as the writer rotates. That keeps clear/format cheap on NOR.
 */
sample_log_status_t log_ring_format(log_ring_t *ring, uint32_t generation);

/*
 * Append one sample. The ring assigns the next sequence (0 for an empty log)
 * and writes the record into the newest sector, rotating and erasing the
 * oldest sector when required. On success rec->seq is updated.
 *
 * A failed write leaves the ring failed; no earlier record is rewritten.
 * Remount to recover the valid tail before appending again.
 */
sample_log_status_t log_ring_append(log_ring_t *ring, sx4_sample_rec_t *rec);

/* Read one committed record by sequence. CRC and layout are re-checked. */
sample_log_status_t log_ring_read_seq(log_ring_t *ring, uint32_t seq,
                                      sx4_sample_rec_t *out);

/* Snapshot of the recovered bookkeeping; no I/O. */
void log_ring_info(const log_ring_t *ring, log_ring_info_t *out);

#ifdef __cplusplus
}
#endif

#endif /* SX4_LOG_CORE_H */
