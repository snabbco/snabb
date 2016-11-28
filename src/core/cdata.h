/* Use of this source code is governed by the Apache 2.0 license; see COPYING. */

enum ctype {
  I8, U8, I16, U16, I32, U32, I64, U64,
  FLOAT, DOUBLE,
  BOOL
};

struct cdata {
  enum ctype type;
  union value {
    int8_t i8; uint8_t u8;
    int16_t i16; uint16_t u16;
    int32_t i32; uint32_t u32;
    int64_t i64; uint64_t u64;
    float f; double d;
    bool b;
  };
};
