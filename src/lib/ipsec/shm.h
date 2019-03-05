/* Use of this source code is governed by the Apache 2.0 license; see COPYING. */

/**
 * https://www.iana.org/assignments/ikev2-parameters/ikev2-parameters.xhtml
 */
enum encryption_algorithm_t {
    ENCR_AES_GCM_16 = 20,
};

struct ipsec_sa {
    uint32_t spi;
    uint64_t tstamp;
    uint32_t replay_window;
    uint16_t enc_alg;
    union {
        struct {
            uint8_t  key[16];
            uint8_t  salt[4];
        } aes_gcm_16;
    } enc_key;
} __attribute__ ((__packed__)) ;
