/*
 * test_ble_sync.c - host tests for the T31 sync_ctrl parser, logical stream
 * builder and sync_data framer (design 05 sections 5.7/5.8, 04 section 4.5).
 *
 * A client-style reassembler consumes the frames exactly as the app must:
 * concatenate by `len`, reset on START, verify contiguous `frame_seq`, then
 * parse START / RECORDS / END from the logical stream. Both MTU 23 (20 B START
 * spans two frames) and MTU 247 are covered, plus a dropped-frame hole.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ble_sync.h"
#include "records.h"
#include "test_util.h"

#define TEST_GENERATION 0x1234ABCDu

typedef struct {
    ble_sync_extent_t extent;
    bool missing_set;
    uint32_t missing_seq;
    uint32_t read_calls;
    uint32_t extent_calls;
    bool mutate_after_first_read;
    bool mutated;
    uint32_t mutated_generation;
    uint32_t mutated_max_seq;
} fake_source_t;

static bool fake_get_extent(void *ctx, ble_sync_extent_t *out) {
    fake_source_t *fake = ctx;
    fake->extent_calls++;
    *out = fake->extent;
    return true;
}

static bool fake_read_record(void *ctx, uint32_t seq,
                             uint8_t out[SX4_RECORD_SIZE]) {
    fake_source_t *fake = ctx;
    fake->read_calls++;
    if (fake->missing_set && seq == fake->missing_seq) {
        return false;
    }
    if (seq < fake->extent.min_seq || seq > fake->extent.max_seq) {
        return false;
    }
    sx4_sample_rec_t rec;
    memset(&rec, 0, sizeof(rec));
    for (unsigned i = 0; i < 4u; i++) {
        rec.temp[i] = SX4_TEMP_DETACHED;
    }
    sx4_sample_rec_seq_set(&rec, seq);
    rec.unix_s = 100000u + seq * SX4_SAMPLE_INTERVAL_S;
    bool ok = sx4_sample_rec_encode(&rec, out, SX4_RECORD_SIZE) ==
              SX4_RECORD_SIZE;
    /* Simulate records written while a response is being built. */
    if (ok && fake->mutate_after_first_read && !fake->mutated) {
        fake->mutated = true;
        fake->extent.generation = fake->mutated_generation;
        fake->extent.max_seq = fake->mutated_max_seq;
        fake->extent.count =
            fake->extent.max_seq - fake->extent.min_seq + 1u;
    }
    return ok;
}

static ble_sync_source_t fake_source(fake_source_t *fake) {
    ble_sync_source_t source = {
        .get_extent = fake_get_extent,
        .read_record = fake_read_record,
        .ctx = fake,
    };
    return source;
}

typedef struct {
    uint8_t payload[BLE_SYNC_STREAM_MAX];
    size_t len;
    uint8_t expected_seq;
    bool have_seq;
    bool seq_gap;
    bool started;
    bool ended;
    bool error;
    unsigned frames;
    unsigned max_frame_len;
    size_t first_payload_len;
    size_t second_payload_len;
} client_t;

static void client_reset(client_t *client) {
    memset(client, 0, sizeof(*client));
}

/* Feed one notification exactly as the app receives it. */
static void client_ingest(client_t *client, const uint8_t *frame,
                          size_t frame_len) {
    sx4_sync_frame_t header;
    CHECK(frame_len >= SX4_SYNC_FRAME_SIZE);
    CHECK(sx4_sync_frame_decode(frame, frame_len, &header));
    CHECK_EQ_UINT(frame[0], 1u);
    CHECK_EQ_UINT(frame_len, (size_t)SX4_SYNC_FRAME_SIZE + header.len);
    CHECK(client->len + header.len <= sizeof(client->payload));

    if ((header.flags & SX4_SYNC_FRAME_FLAG_START) != 0u) {
        client->started = true;
        client->ended = false;
        client->len = 0;
        client->have_seq = false;
        client->seq_gap = false;
    }
    if (client->have_seq && header.frame_seq != client->expected_seq) {
        client->seq_gap = true;
    }
    client->expected_seq = (uint8_t)(header.frame_seq + 1u);
    client->have_seq = true;

    memcpy(client->payload + client->len, frame + SX4_SYNC_FRAME_SIZE,
           header.len);
    client->len += header.len;
    client->frames++;
    if (header.len > client->max_frame_len) {
        client->max_frame_len = header.len;
    }
    if (client->frames == 1u) {
        client->first_payload_len = header.len;
    } else if (client->frames == 2u) {
        client->second_payload_len = header.len;
    }
    if ((header.flags & SX4_SYNC_FRAME_FLAG_END) != 0u) {
        client->ended = true;
        client->error = (header.flags & SX4_SYNC_FRAME_FLAG_ERROR) != 0u;
    }
}

/* Split a logical stream into frames; optionally stop after `stop_after`. */
static unsigned frame_stream(const uint8_t *stream, size_t stream_len,
                             size_t mtu, bool error, client_t *client,
                             unsigned stop_after) {
    ble_sync_framer_t framer;
    uint8_t frame[SX4_SYNC_FRAME_SIZE + SX4_BLE_SYNC_FRAME_MAX_PAYLOAD];
    size_t offset = 0;
    unsigned frames = 0;

    ble_sync_framer_init(&framer, 0);
    for (;;) {
        size_t n = ble_sync_next_frame(&framer, stream, stream_len, &offset,
                                       mtu, error, frame, sizeof(frame));
        if (n == 0u) {
            break;
        }
        frames++;
        if (stop_after != 0u && frames == stop_after) {
            break;
        }
        if (client != NULL) {
            client_ingest(client, frame, n);
        }
    }
    return frames;
}

typedef struct {
    sx4_sync_start_t start;
    sx4_sync_end_t end;
    uint32_t count;
    uint32_t first_seq;
    uint32_t last_seq;
    bool ascending;
} parsed_t;

static parsed_t parse_stream(const client_t *client) {
    parsed_t parsed;
    memset(&parsed, 0, sizeof(parsed));
    parsed.ascending = true;

    CHECK(client->started);
    CHECK(client->ended);
    CHECK(client->len >= SX4_SYNC_START_SIZE + SX4_SYNC_END_SIZE);
    CHECK(sx4_sync_start_decode(client->payload, client->len, &parsed.start));
    parsed.count = parsed.start.count;

    size_t offset = SX4_SYNC_START_SIZE;
    CHECK(client->len >=
          offset + (size_t)parsed.count * SX4_RECORD_SIZE +
              SX4_SYNC_END_SIZE);
    for (uint32_t i = 0; i < parsed.count; i++) {
        sx4_sample_rec_t rec;
        CHECK(sx4_sample_rec_decode(client->payload + offset,
                                    client->len - offset, &rec));
        uint32_t seq = sx4_sample_rec_seq_get(&rec);
        if (i == 0u) {
            parsed.first_seq = seq;
        } else if (seq != parsed.last_seq + 1u) {
            parsed.ascending = false;
        }
        parsed.last_seq = seq;
        offset += SX4_RECORD_SIZE;
    }
    CHECK(sx4_sync_end_decode(client->payload + offset,
                              client->len - offset, &parsed.end));
    CHECK_EQ_UINT(offset + SX4_SYNC_END_SIZE, client->len);
    return parsed;
}

static fake_source_t extent_source(uint32_t min_seq, uint32_t max_seq) {
    fake_source_t fake;
    memset(&fake, 0, sizeof(fake));
    fake.extent.generation = TEST_GENERATION;
    fake.extent.min_seq = min_seq;
    fake.extent.max_seq = max_seq;
    fake.extent.count = max_seq - min_seq + 1u;
    return fake;
}

static void check_parse_ctrl(void) {
    /* ver, cmd=read, direction=backward, cursor 0x12345678, reserved, 32. */
    static const uint8_t vector[SX4_SYNC_CTRL_SIZE] = {
        0x01, 0x01, 0x01, 0x78, 0x56, 0x34, 0x12, 0xAA, 0x20, 0x00,
    };
    ble_sync_request_t request;

    memset(&request, 0, sizeof(request));
    CHECK_EQ_INT(ble_sync_parse_ctrl(vector, sizeof(vector), &request),
                 BLE_SYNC_REQUEST_OK);
    CHECK_EQ_UINT(request.cmd, SX4_SYNC_CMD_READ);
    CHECK_EQ_UINT(request.direction, SX4_SYNC_DIRECTION_BACKWARD);
    CHECK_EQ_UINT(request.cursor_seq, 0x12345678u);
    CHECK_EQ_UINT(request.max_records, 32u);

    /* A wire max_records of 0 reads as the 32-record default. */
    uint8_t zero[SX4_SYNC_CTRL_SIZE];
    memcpy(zero, vector, sizeof(zero));
    zero[8] = 0;
    zero[9] = 0;
    CHECK_EQ_INT(ble_sync_parse_ctrl(zero, sizeof(zero), &request),
                 BLE_SYNC_REQUEST_OK);
    CHECK_EQ_UINT(request.max_records, SX4_BLE_SYNC_DEFAULT_RECORDS);

    /* More than 64 is clamped, never rejected. */
    zero[8] = 200;
    CHECK_EQ_INT(ble_sync_parse_ctrl(zero, sizeof(zero), &request),
                 BLE_SYNC_REQUEST_OK);
    CHECK_EQ_UINT(request.max_records, SX4_BLE_SYNC_MAX_RECORDS);

    /* Wrong length / ver / cmd / direction are invalid. */
    CHECK_EQ_INT(
        ble_sync_parse_ctrl(vector, SX4_SYNC_CTRL_SIZE - 1u, &request),
        BLE_SYNC_REQUEST_INVALID);
    CHECK_EQ_INT(
        ble_sync_parse_ctrl(vector, SX4_SYNC_CTRL_SIZE + 1u, &request),
        BLE_SYNC_REQUEST_INVALID);
    uint8_t bad[SX4_SYNC_CTRL_SIZE];
    memcpy(bad, vector, sizeof(bad));
    bad[0] = 2;
    CHECK_EQ_INT(ble_sync_parse_ctrl(bad, sizeof(bad), &request),
                 BLE_SYNC_REQUEST_INVALID);
    memcpy(bad, vector, sizeof(bad));
    bad[1] = 3;
    CHECK_EQ_INT(ble_sync_parse_ctrl(bad, sizeof(bad), &request),
                 BLE_SYNC_REQUEST_INVALID);
    memcpy(bad, vector, sizeof(bad));
    bad[2] = 2;
    CHECK_EQ_INT(ble_sync_parse_ctrl(bad, sizeof(bad), &request),
                 BLE_SYNC_REQUEST_INVALID);
    CHECK_EQ_INT(ble_sync_parse_ctrl(NULL, sizeof(vector), &request),
                 BLE_SYNC_REQUEST_INVALID);
}

static void check_busy_policy(void) {
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 10,
        .max_records = 32,
    };
    CHECK_EQ_INT(ble_sync_plan(false, &request), BLE_SYNC_ACTION_READ);
    CHECK_EQ_INT(ble_sync_plan(true, &request), BLE_SYNC_ACTION_NONE);

    request.cmd = SX4_SYNC_CMD_STATUS;
    CHECK_EQ_INT(ble_sync_plan(true, &request), BLE_SYNC_ACTION_STATUS);
    request.cmd = SX4_SYNC_CMD_CANCEL;
    CHECK_EQ_INT(ble_sync_plan(true, &request), BLE_SYNC_ACTION_CANCEL);

    request.cmd = SX4_SYNC_CMD_CANCEL;
    uint8_t stream[SX4_SYNC_END_SIZE];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;
    fake_source_t fake = extent_source(0, 0);
    ble_sync_source_t source = fake_source(&fake);
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_NO_STREAM);
}

static void check_status_empty(void) {
    fake_source_t fake;
    memset(&fake, 0, sizeof(fake));
    fake.extent.generation = 0xCAFEBABEu;
    fake.extent.min_seq = SX4_SEQ_NONE;
    fake.extent.max_seq = SX4_SEQ_NONE;
    fake.extent.count = 0;
    ble_sync_source_t source = fake_source(&fake);

    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_STATUS,
        .direction = SX4_SYNC_DIRECTION_FORWARD,
        .cursor_seq = 0,
        .max_records = 32,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_EMPTY);
    CHECK_EQ_UINT(len, SX4_SYNC_START_SIZE + SX4_SYNC_END_SIZE);

    client_t client;
    client_reset(&client);
    CHECK_EQ_UINT(frame_stream(stream, len, 23, false, &client, 0), 3u);
    CHECK(!client.seq_gap);
    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.generation, 0xCAFEBABEu);
    CHECK_EQ_UINT(parsed.start.count, 0u);
    CHECK_EQ_UINT(parsed.start.record_size, SX4_RECORD_SIZE);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_EMPTY);
    CHECK_EQ_UINT(parsed.start.min_seq, SX4_SEQ_NONE);
    CHECK_EQ_UINT(parsed.start.max_seq, SX4_SEQ_NONE);
    CHECK_EQ_UINT(parsed.end.status, SX4_SYNC_STATUS_EMPTY);
    CHECK_EQ_UINT(parsed.end.min_seq, SX4_SEQ_NONE);
    CHECK_EQ_UINT(parsed.end.max_seq, SX4_SEQ_NONE);
}

static void check_status_extent(void) {
    fake_source_t fake = extent_source(100, 250);
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_STATUS,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 251,
        .max_records = 32,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_OK);
    CHECK_EQ_UINT(len, SX4_SYNC_START_SIZE + SX4_SYNC_END_SIZE);
    CHECK_EQ_UINT(fake.read_calls, 0u);

    client_t client;
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.generation, TEST_GENERATION);
    CHECK_EQ_UINT(parsed.start.min_seq, 100u);
    CHECK_EQ_UINT(parsed.start.max_seq, 250u);
    CHECK_EQ_UINT(parsed.start.start_seq, 251u);
    CHECK_EQ_UINT(parsed.start.count, 0u);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_OK);
    CHECK_EQ_UINT(parsed.end.next_seq, 251u);
    CHECK_EQ_UINT(parsed.end.status, SX4_SYNC_STATUS_OK);
}

static void check_backward_last_15_minutes(void) {
    /* 30 records at the 30 s cadence = 14.5 minutes of history. */
    fake_source_t fake = extent_source(70, 99);
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 100,
        .max_records = 32,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_OK);
    CHECK_EQ_UINT(len, SX4_SYNC_START_SIZE + 30u * SX4_RECORD_SIZE +
                            SX4_SYNC_END_SIZE);

    client_t client;
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 30u);
    CHECK_EQ_UINT(parsed.start.start_seq, 70u);
    CHECK_EQ_UINT(parsed.first_seq, 70u);
    CHECK_EQ_UINT(parsed.last_seq, 99u);
    CHECK(parsed.ascending);
    CHECK_EQ_UINT(parsed.end.next_seq, 70u);
    CHECK_EQ_UINT(parsed.end.status, SX4_SYNC_STATUS_OK);

    /* Verify the stored timestamps cover ~15 min, ascending. */
    sx4_sample_rec_t first;
    sx4_sample_rec_t last;
    CHECK(sx4_sample_rec_decode(client.payload + SX4_SYNC_START_SIZE,
                                client.len, &first));
    CHECK(sx4_sample_rec_decode(client.payload + SX4_SYNC_START_SIZE +
                                    29u * SX4_RECORD_SIZE,
                                client.len, &last));
    CHECK_EQ_UINT(last.unix_s - first.unix_s, 29u * 30u);
}

static void check_backward_limits(void) {
    fake_source_t fake = extent_source(0, 999);
    ble_sync_source_t source = fake_source(&fake);
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;

    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 1000,
        .max_records = 64,
    };
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    client_t client;
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 64u);
    CHECK_EQ_UINT(parsed.first_seq, 936u);
    CHECK_EQ_UINT(parsed.last_seq, 999u);
    CHECK(parsed.ascending);
    CHECK_EQ_UINT(parsed.end.next_seq, 936u);

    /* A cursor inside the log takes the highest records below it. */
    request.cursor_seq = 500;
    request.max_records = 10;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.first_seq, 490u);
    CHECK_EQ_UINT(parsed.last_seq, 499u);
    CHECK_EQ_UINT(parsed.end.next_seq, 490u);
    CHECK(parsed.ascending);

    /* Cursor beyond max+1 is a gap and starts from max_seq. */
    request.cursor_seq = 5000;
    request.max_records = 5;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_GAP);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_GAP);
    CHECK_EQ_UINT(parsed.end.status, SX4_SYNC_STATUS_GAP);
    CHECK_EQ_UINT(parsed.start.start_seq, 995u);
    CHECK_EQ_UINT(parsed.first_seq, 995u);
    CHECK_EQ_UINT(parsed.last_seq, 999u);
    CHECK_EQ_UINT(parsed.end.next_seq, 995u);

    /* Cursor 0 has nothing before it; seq 0 is a real record, not "none". */
    request.cursor_seq = 0;
    request.max_records = 8;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 0u);
    CHECK_EQ_UINT(parsed.start.start_seq, 0u);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_OK);
    CHECK_EQ_UINT(parsed.end.next_seq, 0u);
    /* 64 + 10 + 5 records were read; a cursor of 0 reads none. */
    CHECK_EQ_UINT(fake.read_calls, 79u);
}

static void check_forward(void) {
    fake_source_t fake = extent_source(100, 200);
    ble_sync_source_t source = fake_source(&fake);
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;

    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_FORWARD,
        .cursor_seq = 150,
        .max_records = 64,
    };
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    client_t client;
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 50u);
    CHECK_EQ_UINT(parsed.first_seq, 151u);
    CHECK_EQ_UINT(parsed.last_seq, 200u);
    CHECK(parsed.ascending);
    CHECK_EQ_UINT(parsed.end.next_seq, 201u);

    /* At max_seq the direction is drained. */
    request.cursor_seq = 200;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 0u);
    CHECK_EQ_UINT(parsed.start.start_seq, 200u);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_OK);
    CHECK_EQ_UINT(parsed.end.next_seq, 200u);

    /* A cursor older than min_seq - 1 is a gap and starts at min_seq. */
    request.cursor_seq = 0;
    request.max_records = 4;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_GAP);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_GAP);
    CHECK_EQ_UINT(parsed.end.status, SX4_SYNC_STATUS_GAP);
    CHECK_EQ_UINT(parsed.start.count, 4u);
    CHECK_EQ_UINT(parsed.start.start_seq, 100u);
    CHECK_EQ_UINT(parsed.first_seq, 100u);
    CHECK_EQ_UINT(parsed.last_seq, 103u);
    CHECK_EQ_UINT(parsed.end.next_seq, 104u);
}

static void check_mtu23_reassembly(void) {
    CHECK_EQ_UINT(ble_sync_frame_payload_max(23), 16u);
    CHECK_EQ_UINT(ble_sync_frame_payload_max(20), 16u); /* never below 23 */
    CHECK_EQ_UINT(ble_sync_frame_payload_max(247), 240u);
    CHECK_EQ_UINT(ble_sync_frame_payload_max(500), 240u);

    fake_source_t fake = extent_source(0, 199);
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 200,
        .max_records = 32,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);

    /* 20 + 32*18 + 13 = 609 bytes -> ceil(609/16) = 39 frames. */
    client_t client;
    client_reset(&client);
    unsigned frames = frame_stream(stream, len, 23, false, &client, 0);
    CHECK_EQ_UINT(frames, 39u);
    CHECK_EQ_UINT(client.frames, 39u);
    CHECK_EQ_UINT(client.max_frame_len, 16u);
    CHECK_EQ_UINT(client.first_payload_len, 16u);
    CHECK_EQ_UINT(client.second_payload_len, 16u);
    CHECK(client.started);
    CHECK(client.ended);
    CHECK(!client.error);
    CHECK(!client.seq_gap);
    CHECK_EQ_UINT(client.len, len);
    CHECK(memcmp(client.payload, stream, len) == 0);

    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 32u);
    CHECK_EQ_UINT(parsed.first_seq, 168u);
    CHECK_EQ_UINT(parsed.last_seq, 199u);
    CHECK(parsed.ascending);
    CHECK_EQ_UINT(parsed.end.next_seq, 168u);

    /* A record really straddles a frame boundary at MTU 23. */
    bool record_split = false;
    size_t offset = 0;
    for (unsigned i = 0; i + 1u < frames; i++) {
        offset += 16u;
        if (offset > SX4_SYNC_START_SIZE &&
            (offset - SX4_SYNC_START_SIZE) % SX4_RECORD_SIZE != 0u) {
            record_split = true;
        }
    }
    CHECK(record_split);
}

static void check_mtu247_reassembly(void) {
    fake_source_t fake = extent_source(0, 199);
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 200,
        .max_records = 32,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);

    /* 609 bytes -> 240 + 240 + 129 = 3 notification frames. */
    client_t client;
    client_reset(&client);
    unsigned frames = frame_stream(stream, len, 247, false, &client, 0);
    CHECK_EQ_UINT(frames, 3u);
    CHECK_EQ_UINT(client.max_frame_len, 240u);
    CHECK(!client.seq_gap);
    CHECK_EQ_UINT(client.len, len);
    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 32u);
    CHECK_EQ_UINT(parsed.first_seq, 168u);
    CHECK_EQ_UINT(parsed.last_seq, 199u);
    CHECK(parsed.ascending);
}

static void check_full_batch_frame_counts(void) {
    fake_source_t fake = extent_source(0, 199);
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 200,
        .max_records = 64,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(len, 20u + 64u * 18u + 13u);

    client_t slow;
    client_reset(&slow);
    CHECK_EQ_UINT(frame_stream(stream, len, 23, false, &slow, 0), 75u);
    parsed_t parsed = parse_stream(&slow);
    CHECK_EQ_UINT(parsed.start.count, 64u);

    client_t fast;
    client_reset(&fast);
    CHECK_EQ_UINT(frame_stream(stream, len, 247, false, &fast, 0), 5u);
    parsed = parse_stream(&fast);
    CHECK_EQ_UINT(parsed.start.count, 64u);
}

static void check_frame_seq_gap_detected(void) {
    fake_source_t fake = extent_source(0, 49);
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 50,
        .max_records = 16,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);

    /* Collect the first five frames, skip the third, feed the rest. */
    ble_sync_framer_t framer;
    uint8_t frame[4 + SX4_BLE_SYNC_FRAME_MAX_PAYLOAD];
    size_t offset = 0;
    client_t client;
    client_reset(&client);
    unsigned index = 0;
    ble_sync_framer_init(&framer, 0);
    for (;;) {
        size_t n = ble_sync_next_frame(&framer, stream, len, &offset, 23,
                                       false, frame, sizeof(frame));
        if (n == 0u) {
            break;
        }
        index++;
        if (index == 3u) {
            continue; /* the app lost this notification */
        }
        client_ingest(&client, frame, n);
        if (index >= 8u) {
            break;
        }
    }
    CHECK(client.seq_gap);
    CHECK(client.started);
}

static void check_error_and_buffer(void) {
    fake_source_t fake = extent_source(0, 19);
    fake.missing_set = true;
    fake.missing_seq = 7;
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 20,
        .max_records = 20,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_ERROR);
    CHECK_EQ_UINT(len, SX4_SYNC_START_SIZE + 7u * SX4_RECORD_SIZE +
                            SX4_SYNC_END_SIZE);

    client_t client;
    client_reset(&client);
    (void)frame_stream(stream, len, 23, true, &client, 0);
    CHECK(client.error);
    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 7u);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_ERROR);
    CHECK_EQ_UINT(parsed.end.status, SX4_SYNC_STATUS_ERROR);
    CHECK(parsed.ascending);

    /* A too-small buffer is refused before any partial stream is framed. */
    uint8_t tiny[SX4_SYNC_START_SIZE + 4u * SX4_RECORD_SIZE];
    CHECK_EQ_INT(ble_sync_build(&request, &source, tiny, sizeof(tiny), &len,
                                &status),
                 BLE_SYNC_BUILD_BUFFER);

    /* A source without an extent reports ERROR, not a silent empty log. */
    ble_sync_source_t broken = source;
    broken.get_extent = NULL;
    CHECK_EQ_INT(ble_sync_build(&request, &broken, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_INVALID);
}

static void check_forward_gap_boundaries(void) {
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_FORWARD,
        .cursor_seq = 98,
        .max_records = 4,
    };

    fake_source_t fake = extent_source(100, 200);
    ble_sync_source_t source = fake_source(&fake);
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_GAP);
    client_t client;
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_GAP);
    CHECK_EQ_UINT(parsed.end.status, SX4_SYNC_STATUS_GAP);
    CHECK_EQ_UINT(parsed.start.start_seq, 100u);
    CHECK_EQ_UINT(parsed.first_seq, 100u);
    CHECK_EQ_UINT(parsed.last_seq, 103u);
    CHECK_EQ_UINT(parsed.end.next_seq, 104u);
    CHECK_EQ_UINT(parsed.start.min_seq, 100u);
    CHECK_EQ_UINT(parsed.end.max_seq, 200u);

    /* min_seq - 1 == 99: a cursor at 99 is contiguous, not a gap. */
    request.cursor_seq = 99;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_OK);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_OK);
    CHECK_EQ_UINT(parsed.first_seq, 100u);

    /* min_seq == 0 is never a gap: seq 0 is a real record. */
    fake_source_t zero = extent_source(0, 10);
    source = fake_source(&zero);
    request.cursor_seq = 0;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_OK);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_OK);
    CHECK_EQ_UINT(parsed.first_seq, 1u);
    CHECK_EQ_UINT(parsed.last_seq, 4u);

    /* min_seq == 1 has no lower record to miss either. */
    fake_source_t one = extent_source(1, 10);
    source = fake_source(&one);
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_OK);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_OK);
    CHECK_EQ_UINT(parsed.first_seq, 1u);
}

static void check_backward_gap_boundaries(void) {
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;

    fake_source_t fake = extent_source(100, 200);
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 202,
        .max_records = 4,
    };

    /* max_seq + 1 == 201, so 202 is a gap and restarts at max_seq. */
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_GAP);
    client_t client;
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_GAP);
    CHECK_EQ_UINT(parsed.end.status, SX4_SYNC_STATUS_GAP);
    CHECK_EQ_UINT(parsed.first_seq, 197u);
    CHECK_EQ_UINT(parsed.last_seq, 200u);
    CHECK_EQ_UINT(parsed.end.next_seq, 197u);

    /* Exactly max_seq + 1 is the contiguous backward edge. */
    request.cursor_seq = 201;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_OK);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_OK);
    CHECK_EQ_UINT(parsed.first_seq, 197u);
    CHECK_EQ_UINT(parsed.last_seq, 200u);

    /* A cursor at min_seq has nothing before it: count 0, start = cursor. */
    request.cursor_seq = 100;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_OK);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 0u);
    CHECK_EQ_UINT(parsed.start.start_seq, 100u);
    CHECK_EQ_UINT(parsed.end.next_seq, 100u);
    CHECK_EQ_UINT(parsed.end.status, SX4_SYNC_STATUS_OK);

    /* The last valid 24-bit seq: cursor = max + 1 is contiguous, not a gap. */
    fake_source_t top;
    memset(&top, 0, sizeof(top));
    top.extent.generation = TEST_GENERATION;
    top.extent.min_seq = 0x00FFFFFFu;
    top.extent.max_seq = 0x00FFFFFFu;
    top.extent.count = 1u;
    source = fake_source(&top);
    request.cursor_seq = 0x01000000u;
    request.max_records = 8;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_OK);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 1u);
    CHECK_EQ_UINT(parsed.first_seq, 0x00FFFFFFu);
    CHECK_EQ_UINT(parsed.end.next_seq, 0x00FFFFFFu);
}

static void check_generation_snapshot(void) {
    fake_source_t fake = extent_source(10, 19);
    fake.mutate_after_first_read = true;
    fake.mutated_generation = 0xFEEDFACEu;
    fake.mutated_max_seq = 29;
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 20,
        .max_records = 32,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;

    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(fake.extent_calls, 1u);
    client_t client;
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed_t parsed = parse_stream(&client);
    /* Records written during the transfer are not in this response. */
    CHECK_EQ_UINT(parsed.start.count, 10u);
    CHECK_EQ_UINT(parsed.first_seq, 10u);
    CHECK_EQ_UINT(parsed.last_seq, 19u);
    CHECK_EQ_UINT(parsed.start.generation, TEST_GENERATION);
    CHECK_EQ_UINT(parsed.start.min_seq, 10u);
    CHECK_EQ_UINT(parsed.start.max_seq, 19u);
    CHECK_EQ_UINT(parsed.end.min_seq, 10u);
    CHECK_EQ_UINT(parsed.end.max_seq, 19u);
    CHECK_EQ_UINT(parsed.end.next_seq, 10u);

    /* The next request sees the new generation and the new high-water mark. */
    request.cmd = SX4_SYNC_CMD_STATUS;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.generation, 0xFEEDFACEu);
    CHECK_EQ_UINT(parsed.start.min_seq, 10u);
    CHECK_EQ_UINT(parsed.start.max_seq, 29u);
    CHECK_EQ_UINT(parsed.end.max_seq, 29u);

    /* A stale cursor from the old epoch cannot silently fetch new records. */
    request.cmd = SX4_SYNC_CMD_READ;
    request.direction = SX4_SYNC_DIRECTION_FORWARD;
    request.cursor_seq = 0;
    request.max_records = 5;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(status, SX4_SYNC_STATUS_GAP);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.generation, 0xFEEDFACEu);
    CHECK_EQ_UINT(parsed.start.status, SX4_SYNC_STATUS_GAP);
    CHECK_EQ_UINT(parsed.start.start_seq, 10u);

    /* Forward catch-up from the old max picks the records written after it. */
    request.cursor_seq = 19;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.generation, 0xFEEDFACEu);
    CHECK_EQ_UINT(parsed.first_seq, 20u);
    CHECK_EQ_UINT(parsed.last_seq, 24u);
    CHECK_EQ_UINT(parsed.end.next_seq, 25u);
}

static void check_frame_seq_wrap(void) {
    fake_source_t fake = extent_source(0, 199);
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 200,
        .max_records = 64,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);

    /* MTU 23 gives 75 frames; start at 250 so frame_seq wraps mid-response. */
    ble_sync_framer_t framer;
    uint8_t frame[SX4_SYNC_FRAME_SIZE + SX4_BLE_SYNC_FRAME_MAX_PAYLOAD];
    size_t offset = 0;
    unsigned frames = 0;
    uint8_t previous = 0;
    bool saw_255 = false;
    bool saw_wrap = false;
    client_t client;
    client_reset(&client);
    ble_sync_framer_init(&framer, 250u);
    for (;;) {
        size_t n = ble_sync_next_frame(&framer, stream, len, &offset, 23,
                                       false, frame, sizeof(frame));
        if (n == 0u) {
            break;
        }
        sx4_sync_frame_t header;
        CHECK(sx4_sync_frame_decode(frame, n, &header));
        if (header.frame_seq == 255u) {
            saw_255 = true;
        }
        if (previous == 255u && header.frame_seq == 0u) {
            saw_wrap = true;
        }
        previous = header.frame_seq;
        client_ingest(&client, frame, n);
        frames++;
    }
    CHECK_EQ_UINT(frames, 75u);
    CHECK(saw_255);
    CHECK(saw_wrap);
    CHECK(!client.seq_gap);
    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 64u);
    CHECK_EQ_UINT(parsed.first_seq, 136u);
    CHECK_EQ_UINT(parsed.last_seq, 199u);
}

static void check_disconnect_mid_batch(void) {
    fake_source_t fake = extent_source(0, 99);
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 100,
        .max_records = 20,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);

    /* Deliver only the first two frames, then the link drops. */
    ble_sync_framer_t framer;
    uint8_t frame[SX4_SYNC_FRAME_SIZE + SX4_BLE_SYNC_FRAME_MAX_PAYLOAD];
    size_t offset = 0;
    client_t client;
    client_reset(&client);
    ble_sync_framer_init(&framer, 0);
    for (unsigned i = 0; i < 2u; i++) {
        size_t n = ble_sync_next_frame(&framer, stream, len, &offset, 23,
                                       false, frame, sizeof(frame));
        CHECK(n != 0u);
        client_ingest(&client, frame, n);
    }
    CHECK(client.started);
    CHECK(!client.ended);
    CHECK(client.len < len);
    CHECK(!client.seq_gap);

    /*
     * The device keeps no partial transfer: the app re-sends the same cursor
     * and gets a fresh START/RECORDS/END stream from the beginning.
     */
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed_t parsed = parse_stream(&client);
    CHECK(client.started);
    CHECK(client.ended);
    CHECK_EQ_UINT(parsed.start.count, 20u);
    CHECK_EQ_UINT(parsed.first_seq, 80u);
    CHECK_EQ_UINT(parsed.last_seq, 99u);
    CHECK_EQ_UINT(parsed.end.next_seq, 80u);
}

static void check_full_ring_backfill(void) {
    /*
     * 30 days at the 30 s cadence is 86,400 records; this ring also holds
     * 3,600 older records, so the same backward walk is "30 days, then the
     * rest of the ring". Batches are 64 records (the wire maximum).
     */
    enum { RING_RECORDS = 90000, DAY_30_RECORDS = 86400 };
    fake_source_t fake = extent_source(0, RING_RECORDS - 1);
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = RING_RECORDS,
        .max_records = 64,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;

    uint32_t total = 0;
    uint32_t cursor = RING_RECORDS;
    unsigned batches = 0;
    for (;;) {
        CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                    &len, &status),
                     BLE_SYNC_BUILD_OK);
        client_t client;
        client_reset(&client);
        (void)frame_stream(stream, len, 247, false, &client, 0);
        parsed_t parsed = parse_stream(&client);
        CHECK(parsed.ascending);
        CHECK_EQ_UINT(parsed.start.min_seq, 0u);
        CHECK_EQ_UINT(parsed.start.max_seq, RING_RECORDS - 1);
        if (parsed.count == 0u) {
            CHECK_EQ_UINT(parsed.start.start_seq, cursor);
            CHECK_EQ_UINT(parsed.end.next_seq, cursor);
            CHECK_EQ_UINT(parsed.end.status, SX4_SYNC_STATUS_OK);
            break;
        }
        CHECK_EQ_UINT(parsed.last_seq, cursor - 1u);
        CHECK_EQ_UINT(parsed.end.next_seq, parsed.first_seq);
        total += parsed.count;
        cursor = parsed.end.next_seq;
        request.cursor_seq = cursor;
        batches++;
        CHECK(batches < 2000u);
    }
    CHECK_EQ_UINT(total, RING_RECORDS);
    CHECK(total > DAY_30_RECORDS);
    CHECK_EQ_UINT(cursor, 0u);
    CHECK_EQ_UINT(batches, (RING_RECORDS + 63u) / 64u);

    /* Forward catch-up from the top is already drained. */
    request.direction = SX4_SYNC_DIRECTION_FORWARD;
    request.cursor_seq = RING_RECORDS - 1;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    client_t client;
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 0u);
    CHECK_EQ_UINT(parsed.start.start_seq, RING_RECORDS - 1);
    CHECK_EQ_UINT(parsed.end.next_seq, RING_RECORDS - 1);
    CHECK_EQ_UINT(parsed.end.status, SX4_SYNC_STATUS_OK);
}

static void check_build_max_records(void) {
    fake_source_t fake = extent_source(0, 199);
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_FORWARD,
        .cursor_seq = 0,
        .max_records = 0,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;

    /* Direct callers get the same wire rule: 0 -> 32, above 64 -> 64. */
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    client_t client;
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 32u);

    request.max_records = 200;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    client_reset(&client);
    (void)frame_stream(stream, len, 247, false, &client, 0);
    parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 64u);
}

static void check_used_record_count(void) {
    /* The START count is the emitted count, never the requested cap. */
    fake_source_t fake = extent_source(5, 5);
    ble_sync_source_t source = fake_source(&fake);
    ble_sync_request_t request = {
        .cmd = SX4_SYNC_CMD_READ,
        .direction = SX4_SYNC_DIRECTION_BACKWARD,
        .cursor_seq = 6,
        .max_records = 64,
    };
    uint8_t stream[BLE_SYNC_STREAM_MAX];
    size_t len = 0;
    uint8_t status = SX4_SYNC_STATUS_OK;
    CHECK_EQ_INT(ble_sync_build(&request, &source, stream, sizeof(stream),
                                &len, &status),
                 BLE_SYNC_BUILD_OK);
    CHECK_EQ_UINT(len, SX4_SYNC_START_SIZE + SX4_RECORD_SIZE +
                            SX4_SYNC_END_SIZE);
    client_t client;
    client_reset(&client);
    (void)frame_stream(stream, len, 23, false, &client, 0);
    parsed_t parsed = parse_stream(&client);
    CHECK_EQ_UINT(parsed.start.count, 1u);
    CHECK_EQ_UINT(parsed.first_seq, 5u);
    CHECK_EQ_UINT(parsed.end.next_seq, 5u);
}

int main(void) {
    check_parse_ctrl();
    check_busy_policy();
    check_status_empty();
    check_status_extent();
    check_backward_last_15_minutes();
    check_backward_limits();
    check_forward();
    check_mtu23_reassembly();
    check_mtu247_reassembly();
    check_full_batch_frame_counts();
    check_frame_seq_gap_detected();
    check_error_and_buffer();
    check_used_record_count();
    check_forward_gap_boundaries();
    check_backward_gap_boundaries();
    check_generation_snapshot();
    check_frame_seq_wrap();
    check_disconnect_mid_batch();
    check_full_ring_backfill();
    check_build_max_records();
    return sx4_test_summary("ble-sync");
}
