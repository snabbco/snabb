/* AES-GCM interface from Intel's implementation. */

typedef struct gcm_data
{
  uint8_t expanded_keys[16*11];
  uint8_t shifted_hkey_1[16];
  uint8_t shifted_hkey_2[16];
  uint8_t shifted_hkey_3[16];
  uint8_t shifted_hkey_4[16];
  uint8_t shifted_hkey_5[16];
  uint8_t shifted_hkey_6[16];
  uint8_t shifted_hkey_7[16];
  uint8_t shifted_hkey_8[16];
  uint8_t shifted_hkey_1_k[16];
  uint8_t shifted_hkey_2_k[16];
  uint8_t shifted_hkey_3_k[16];
  uint8_t shifted_hkey_4_k[16];
  uint8_t shifted_hkey_5_k[16];
  uint8_t shifted_hkey_6_k[16];
  uint8_t shifted_hkey_7_k[16];
  uint8_t shifted_hkey_8_k[16];
} gcm_data;

void    aesni_gcm_enc_avx_gen4(
        gcm_data        *my_ctx_data,
        uint8_t      *out, /* Ciphertext output. Encrypt in-place is allowed.  */
        const   uint8_t *in, /* Plaintext input */
        uint64_t     plaintext_len, /* Length of data in Bytes for encryption. */
        uint8_t      *iv, /* Pre-counter block j0: 4 byte salt (from Security Association) concatenated with 8 byte Initialisation Vector (from IPSec ESP Payload) concatenated with 0x00000001. 16-byte aligned pointer. */
        const   uint8_t *aad, /* Additional Authentication Data (AAD)*/
        uint64_t     aad_len, /* Length of AAD in bytes. With RFC4106 this is going to be 8 or 12 Bytes */
        uint8_t      *auth_tag, /* Authenticated Tag output. */
        uint64_t     auth_tag_len); /* Authenticated Tag Length in bytes. Valid values are 16 (most likely), 12 or 8. */

void    aesni_gcm_dec_avx_gen4(
        gcm_data        *my_ctx_data,     /* aligned to 16 Bytes */
        uint8_t      *out, /* Plaintext output. Decrypt in-place is allowed.  */
        const   uint8_t *in, /* Ciphertext input */
        uint64_t     plaintext_len, /* Length of data in Bytes for encryption. */
        uint8_t      *iv, /* Pre-counter block j0: 4 byte salt (from Security Association) concatenated with 8 byte Initialisation Vector (from IPSec ESP Payload) concatenated with 0x00000001. 16-byte aligned pointer. */
        const   uint8_t *aad, /* Additional Authentication Data (AAD)*/
        uint64_t     aad_len, /* Length of AAD in bytes. With RFC4106 this is going to be 8 or 12 Bytes */
        uint8_t      *auth_tag, /* Authenticated Tag output. */
        uint64_t     auth_tag_len); /* Authenticated Tag Length in bytes. Valid values are 16 (most likely), 12 or 8. */

void aes_keyexp_128_enc_avx(void *key, void *enc_exp_keys);

void	aesni_gcm_precomp_avx_gen4
        (gcm_data     *my_ctx_data, 
         uint8_t *hash_subkey); /* H, the Hash sub key input. Data starts on a 16-byte boundary. */
