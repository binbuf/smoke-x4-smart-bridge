/* dns_shim — pure DNS responder codec (F8.5). */
#include "dns_shim.h"

#include <string.h>

#define QR_RESPONSE 0x80
#define OPCODE_MASK 0x78
#define AA_FLAG 0x04
#define TYPE_A 1
#define CLASS_IN 1

int dns_shim_respond(const uint8_t *query, size_t query_len,
                     const uint8_t ip[4], uint8_t *out, size_t out_cap) {
    /* Header is 12 bytes: ID(2) FLAGS(2) QD(2) AN(2) NS(2) AR(2). */
    if (!query || query_len < 12 || !out) {
        return -1;
    }
    if (query[2] & QR_RESPONSE) {
        return -1; /* already a response */
    }
    if (query[2] & OPCODE_MASK) {
        return -1; /* only standard queries */
    }
    const unsigned qdcount = ((unsigned)query[4] << 8) | query[5];
    if (qdcount == 0) {
        return -1;
    }

    /* Walk the first QNAME. */
    size_t pos = 12;
    while (pos < query_len && query[pos] != 0) {
        const uint8_t label = query[pos];
        if (label & 0xC0) {
            return -1; /* compression in a question: not from a stub */
        }
        pos += (size_t)label + 1;
    }
    if (pos + 4 >= query_len) {
        return -1; /* truncated: no room for null + QTYPE + QCLASS */
    }
    pos++; /* the terminating zero label */
    const unsigned qtype = ((unsigned)query[pos] << 8) | query[pos + 1];
    const unsigned qclass = ((unsigned)query[pos + 2] << 8) | query[pos + 3];
    const size_t question_end = pos + 4;

    const int answer_a = (qtype == TYPE_A && qclass == CLASS_IN);
    const size_t need = question_end + (answer_a ? 16 : 0);
    if (need > out_cap) {
        return -1;
    }

    /* Echo ID + question; claim authority; count one question. */
    memcpy(out, query, question_end);
    out[2] = QR_RESPONSE | AA_FLAG | (query[2] & 0x01); /* keep RD */
    out[3] = 0;                                         /* RCODE 0 */
    out[4] = 0;
    out[5] = 1; /* QDCOUNT = 1: we answer the first question only */
    out[6] = 0;
    out[7] = (uint8_t)(answer_a ? 1 : 0); /* ANCOUNT */
    out[8] = out[9] = out[10] = out[11] = 0;

    if (!answer_a) {
        return (int)question_end; /* empty NOERROR */
    }

    /* One A record: pointer to the question name, TTL 60, RDLENGTH 4. */
    uint8_t *a = out + question_end;
    a[0] = 0xC0;
    a[1] = 0x0C; /* name = offset 12 */
    a[2] = 0;
    a[3] = TYPE_A;
    a[4] = 0;
    a[5] = CLASS_IN;
    a[6] = 0;
    a[7] = 0;
    a[8] = 0;
    a[9] = 60; /* TTL */
    a[10] = 0;
    a[11] = 4;
    memcpy(a + 12, ip, 4);
    return (int)(question_end + 16);
}
