/*
 * test_sx_radio_rx.c - the radio-to-parser seam and parameter block (T13).
 *
 * No radio and no ESP-IDF: the test calls sx4_radio_rx_publish() directly and
 * takes the same frame the parser pipeline would see. The fixture payload is a
 * real X4 state packet captured in T10.
 */
#include <stdint.h>
#include <string.h>

#include "lora_corpus.h"
#include "sx_radio_params.h"
#include "sx_radio_rx.h"
#include "test_util.h"

static void check_parameter_block(void) {
    CHECK_EQ_UINT(sx4_radio_params.spreading_factor, 9u);
    CHECK_EQ_UINT(sx4_radio_params.bandwidth_index, 4u);
    CHECK_EQ_UINT(sx4_radio_params.coding_rate, 0x01u);
    CHECK_EQ_UINT(sx4_radio_params.preamble_symbols, 10u);
    CHECK_EQ_UINT(sx4_radio_params.sync_word, 0x12u);
    CHECK(sx4_radio_params.crc_on);
    CHECK(sx4_radio_params.tcxo_voltage > 3.29f &&
          sx4_radio_params.tcxo_voltage < 3.31f);
    CHECK(sx4_radio_params.use_regulator_ldo);
    CHECK_EQ_UINT(sx4_radio_params.frequency_min_hz, 902000000u);
    CHECK_EQ_UINT(sx4_radio_params.frequency_max_hz, 928000000u);
    CHECK_EQ_UINT(SX4_RADIO_MAX_PAYLOAD, 128u);
    CHECK_EQ_UINT(SX4_RADIO_TASK_STACK_BYTES, 4096u);
    CHECK_EQ_UINT(SX4_RADIO_TASK_PRIORITY, 6u);
    CHECK_EQ_UINT(SX4_RADIO_TASK_CORE, 1u);

    CHECK(sx4_radio_frequency_valid(902000000u));
    CHECK(sx4_radio_frequency_valid(918500000u));
    CHECK(sx4_radio_frequency_valid(928000000u));
    CHECK(!sx4_radio_frequency_valid(901999999u));
    CHECK(!sx4_radio_frequency_valid(928000001u));
    CHECK(!sx4_radio_frequency_valid(0u));
}

static void check_inject_and_take(void) {
    static const uint8_t payload[] =
        "LMXC[\\,30,1,1,0,826,0,99,47,0,823,0,160,32,0,827,0,160,32,0,"
        "825,1,160,32,0,0,";
    const uint8_t length = (uint8_t)(sizeof payload - 1u);

    sx4_radio_rx_reset();
    sx4_radio_packet_t packet;
    CHECK(!sx4_radio_rx_take(&packet));

    CHECK(sx4_radio_rx_publish(payload, length, -92, 7));
    CHECK_EQ_UINT(sx4_radio_rx_published_count(), 1u);
    CHECK_EQ_UINT(sx4_radio_rx_dropped_count(), 0u);

    CHECK(sx4_radio_rx_take(&packet));
    CHECK_EQ_UINT(packet.length, length);
    CHECK_EQ_INT(packet.rssi, -92);
    CHECK_EQ_INT(packet.snr, 7);
    CHECK(memcmp(packet.payload, payload, length) == 0);
    CHECK(!sx4_radio_rx_take(&packet));
}

static void check_bounds(void) {
    uint8_t payload[SX4_RADIO_MAX_PAYLOAD + 1];
    memset(payload, 'A', sizeof payload);

    sx4_radio_rx_reset();
    CHECK(!sx4_radio_rx_publish(NULL, 1, 0, 0));
    CHECK(!sx4_radio_rx_publish(payload, 0, 0, 0));
    CHECK(!sx4_radio_rx_publish(payload, SX4_RADIO_MAX_PAYLOAD + 1u, 0, 0));
    CHECK_EQ_UINT(sx4_radio_rx_published_count(), 0u);

    CHECK(sx4_radio_rx_publish(payload, SX4_RADIO_MAX_PAYLOAD, -10, 1));
    sx4_radio_packet_t packet;
    CHECK(sx4_radio_rx_take(&packet));
    CHECK_EQ_UINT(packet.length, SX4_RADIO_MAX_PAYLOAD);
    CHECK(memcmp(packet.payload, payload, SX4_RADIO_MAX_PAYLOAD) == 0);
}

static void check_bounded_handoff(void) {
    uint8_t payload[SX4_RADIO_MAX_PAYLOAD];
    memset(payload, 'Q', sizeof payload);

    sx4_radio_rx_reset();
    for (unsigned i = 0; i < SX4_RADIO_RX_CAPACITY; i++) {
        CHECK(sx4_radio_rx_publish(payload, 10, -1, 1));
    }
    CHECK(!sx4_radio_rx_publish(payload, 10, -1, 1));
    CHECK(!sx4_radio_rx_publish(payload, 10, -1, 1));
    CHECK_EQ_UINT(sx4_radio_rx_published_count(), SX4_RADIO_RX_CAPACITY);
    CHECK_EQ_UINT(sx4_radio_rx_dropped_count(), 2u);

    sx4_radio_packet_t packet;
    for (unsigned i = 0; i < SX4_RADIO_RX_CAPACITY; i++) {
        CHECK(sx4_radio_rx_take(&packet));
        CHECK_EQ_UINT(packet.length, 10u);
    }
    CHECK(!sx4_radio_rx_take(&packet));
}

/* A real captured X4 state packet reaches the seam unchanged. */
static void check_real_x4_fixture(void) {
    sx4_loralog_line_t lines[128];
    size_t count = 0;
    int rc = sx4_loralog_read(SX4_FIXTURE_DIR "/x4-t10-25min.loralog", lines,
                              sizeof lines / sizeof lines[0], &count);
    CHECK_EQ_INT(rc, 0);
    CHECK(count > 0);

    const sx4_loralog_line_t *state = NULL;
    for (size_t i = 0; i < count; i++) {
        if (!lines[i].is_tx && strcmp(lines[i].cls, "state26") == 0) {
            state = &lines[i];
            break;
        }
    }
    CHECK(state != NULL);
    if (state == NULL) {
        return;
    }

    size_t length = strlen(state->payload);
    CHECK(length > 0 && length <= SX4_RADIO_MAX_PAYLOAD);
    CHECK(state->rssi >= -128 && state->rssi <= 127);

    sx4_radio_rx_reset();
    CHECK(sx4_radio_rx_publish((const uint8_t *)state->payload,
                               (uint8_t)length, (int8_t)state->rssi,
                               (int8_t)state->snr));

    sx4_radio_packet_t packet;
    CHECK(sx4_radio_rx_take(&packet));
    CHECK_EQ_UINT(packet.length, length);
    CHECK_EQ_INT(packet.rssi, state->rssi);
    CHECK_EQ_INT(packet.snr, state->snr);
    CHECK(memcmp(packet.payload, state->payload, length) == 0);
    printf("radio seam: injected real X4 packet (%u bytes, rssi=%d snr=%d)\n",
           packet.length, packet.rssi, packet.snr);
}

int main(void) {
    check_parameter_block();
    check_inject_and_take();
    check_bounds();
    check_bounded_handoff();
    check_real_x4_fixture();
    return sx4_test_summary("sx-radio-rx");
}
