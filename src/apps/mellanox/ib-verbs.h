typedef signed char int8_t;
typedef short int int16_t;
typedef int int32_t;

typedef long int int64_t;

typedef unsigned char uint8_t;
typedef unsigned short int uint16_t;

typedef unsigned int uint32_t;

typedef unsigned long int uint64_t;
typedef signed char int_least8_t;
typedef short int int_least16_t;
typedef int int_least32_t;

typedef long int int_least64_t;

typedef unsigned char uint_least8_t;
typedef unsigned short int uint_least16_t;
typedef unsigned int uint_least32_t;

typedef unsigned long int uint_least64_t;
typedef signed char int_fast8_t;

typedef long int int_fast16_t;
typedef long int int_fast32_t;
typedef long int int_fast64_t;
typedef unsigned char uint_fast8_t;

typedef unsigned long int uint_fast16_t;
typedef unsigned long int uint_fast32_t;
typedef unsigned long int uint_fast64_t;
typedef long int intptr_t;

typedef unsigned long int uintptr_t;
typedef long int intmax_t;
typedef unsigned long int uintmax_t;

typedef unsigned char __u_char;
typedef unsigned short int __u_short;
typedef unsigned int __u_int;
typedef unsigned long int __u_long;

typedef signed char __int8_t;
typedef unsigned char __uint8_t;
typedef signed short int __int16_t;
typedef unsigned short int __uint16_t;
typedef signed int __int32_t;
typedef unsigned int __uint32_t;

typedef signed long int __int64_t;
typedef unsigned long int __uint64_t;

typedef long int __quad_t;
typedef unsigned long int __u_quad_t;

typedef unsigned long int __dev_t;
typedef unsigned int __uid_t;
typedef unsigned int __gid_t;
typedef unsigned long int __ino_t;
typedef unsigned long int __ino64_t;
typedef unsigned int __mode_t;
typedef unsigned long int __nlink_t;
typedef long int __off_t;
typedef long int __off64_t;
typedef int __pid_t;
typedef struct { int __val[2]; } __fsid_t;
typedef long int __clock_t;
typedef unsigned long int __rlim_t;
typedef unsigned long int __rlim64_t;
typedef unsigned int __id_t;
typedef long int __time_t;
typedef unsigned int __useconds_t;
typedef long int __suseconds_t;

typedef int __daddr_t;
typedef int __key_t;

typedef int __clockid_t;

typedef void * __timer_t;

typedef long int __blksize_t;

typedef long int __blkcnt_t;
typedef long int __blkcnt64_t;

typedef unsigned long int __fsblkcnt_t;
typedef unsigned long int __fsblkcnt64_t;

typedef unsigned long int __fsfilcnt_t;
typedef unsigned long int __fsfilcnt64_t;

typedef long int __fsword_t;

typedef long int __ssize_t;

typedef long int __syscall_slong_t;

typedef unsigned long int __syscall_ulong_t;

typedef __off64_t __loff_t;
typedef __quad_t *__qaddr_t;
typedef char *__caddr_t;

typedef long int __intptr_t;

typedef unsigned int __socklen_t;

static __inline unsigned int
__bswap_32 (unsigned int __bsx)
{
  return __builtin_bswap32 (__bsx);
}
static __inline __uint64_t
__bswap_64 (__uint64_t __bsx)
{
  return __builtin_bswap64 (__bsx);
}
typedef long unsigned int size_t;

typedef __time_t time_t;

struct timespec
  {
    __time_t tv_sec;
    __syscall_slong_t tv_nsec;
  };

typedef __pid_t pid_t;

struct sched_param
  {
    int __sched_priority;
  };

struct __sched_param
  {
    int __sched_priority;
  };
typedef unsigned long int __cpu_mask;

typedef struct
{
  __cpu_mask __bits[1024 / (8 * sizeof (__cpu_mask))];
} cpu_set_t;

extern int __sched_cpucount (size_t __setsize, const cpu_set_t *__setp)
  __attribute__ ((__nothrow__ , __leaf__));
extern cpu_set_t *__sched_cpualloc (size_t __count) __attribute__ ((__nothrow__ , __leaf__)) ;
extern void __sched_cpufree (cpu_set_t *__set) __attribute__ ((__nothrow__ , __leaf__));

extern int sched_setparam (__pid_t __pid, const struct sched_param *__param)
     __attribute__ ((__nothrow__ , __leaf__));

extern int sched_getparam (__pid_t __pid, struct sched_param *__param) __attribute__ ((__nothrow__ , __leaf__));

extern int sched_setscheduler (__pid_t __pid, int __policy,
          const struct sched_param *__param) __attribute__ ((__nothrow__ , __leaf__));

extern int sched_getscheduler (__pid_t __pid) __attribute__ ((__nothrow__ , __leaf__));

extern int sched_yield (void) __attribute__ ((__nothrow__ , __leaf__));

extern int sched_get_priority_max (int __algorithm) __attribute__ ((__nothrow__ , __leaf__));

extern int sched_get_priority_min (int __algorithm) __attribute__ ((__nothrow__ , __leaf__));

extern int sched_rr_get_interval (__pid_t __pid, struct timespec *__t) __attribute__ ((__nothrow__ , __leaf__));

typedef __clock_t clock_t;

typedef __clockid_t clockid_t;
typedef __timer_t timer_t;

struct tm
{
  int tm_sec;
  int tm_min;
  int tm_hour;
  int tm_mday;
  int tm_mon;
  int tm_year;
  int tm_wday;
  int tm_yday;
  int tm_isdst;

  long int tm_gmtoff;
  const char *tm_zone;

};

struct itimerspec
  {
    struct timespec it_interval;
    struct timespec it_value;
  };

struct sigevent;

extern clock_t clock (void) __attribute__ ((__nothrow__ , __leaf__));

extern time_t time (time_t *__timer) __attribute__ ((__nothrow__ , __leaf__));

extern double difftime (time_t __time1, time_t __time0)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__const__));

extern time_t mktime (struct tm *__tp) __attribute__ ((__nothrow__ , __leaf__));

extern size_t strftime (char *__restrict __s, size_t __maxsize,
   const char *__restrict __format,
   const struct tm *__restrict __tp) __attribute__ ((__nothrow__ , __leaf__));

typedef struct __locale_struct
{

  struct __locale_data *__locales[13];

  const unsigned short int *__ctype_b;
  const int *__ctype_tolower;
  const int *__ctype_toupper;

  const char *__names[13];
} *__locale_t;

typedef __locale_t locale_t;

extern size_t strftime_l (char *__restrict __s, size_t __maxsize,
     const char *__restrict __format,
     const struct tm *__restrict __tp,
     __locale_t __loc) __attribute__ ((__nothrow__ , __leaf__));

extern struct tm *gmtime (const time_t *__timer) __attribute__ ((__nothrow__ , __leaf__));

extern struct tm *localtime (const time_t *__timer) __attribute__ ((__nothrow__ , __leaf__));

extern struct tm *gmtime_r (const time_t *__restrict __timer,
       struct tm *__restrict __tp) __attribute__ ((__nothrow__ , __leaf__));

extern struct tm *localtime_r (const time_t *__restrict __timer,
          struct tm *__restrict __tp) __attribute__ ((__nothrow__ , __leaf__));

extern char *asctime (const struct tm *__tp) __attribute__ ((__nothrow__ , __leaf__));

extern char *ctime (const time_t *__timer) __attribute__ ((__nothrow__ , __leaf__));

extern char *asctime_r (const struct tm *__restrict __tp,
   char *__restrict __buf) __attribute__ ((__nothrow__ , __leaf__));

extern char *ctime_r (const time_t *__restrict __timer,
        char *__restrict __buf) __attribute__ ((__nothrow__ , __leaf__));

extern char *__tzname[2];
extern int __daylight;
extern long int __timezone;

extern char *tzname[2];

extern void tzset (void) __attribute__ ((__nothrow__ , __leaf__));

extern int daylight;
extern long int timezone;

extern int stime (const time_t *__when) __attribute__ ((__nothrow__ , __leaf__));
extern time_t timegm (struct tm *__tp) __attribute__ ((__nothrow__ , __leaf__));

extern time_t timelocal (struct tm *__tp) __attribute__ ((__nothrow__ , __leaf__));

extern int dysize (int __year) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__const__));
extern int nanosleep (const struct timespec *__requested_time,
        struct timespec *__remaining);

extern int clock_getres (clockid_t __clock_id, struct timespec *__res) __attribute__ ((__nothrow__ , __leaf__));

extern int clock_gettime (clockid_t __clock_id, struct timespec *__tp) __attribute__ ((__nothrow__ , __leaf__));

extern int clock_settime (clockid_t __clock_id, const struct timespec *__tp)
     __attribute__ ((__nothrow__ , __leaf__));

extern int clock_nanosleep (clockid_t __clock_id, int __flags,
       const struct timespec *__req,
       struct timespec *__rem);

extern int clock_getcpuclockid (pid_t __pid, clockid_t *__clock_id) __attribute__ ((__nothrow__ , __leaf__));

extern int timer_create (clockid_t __clock_id,
    struct sigevent *__restrict __evp,
    timer_t *__restrict __timerid) __attribute__ ((__nothrow__ , __leaf__));

extern int timer_delete (timer_t __timerid) __attribute__ ((__nothrow__ , __leaf__));

extern int timer_settime (timer_t __timerid, int __flags,
     const struct itimerspec *__restrict __value,
     struct itimerspec *__restrict __ovalue) __attribute__ ((__nothrow__ , __leaf__));

extern int timer_gettime (timer_t __timerid, struct itimerspec *__value)
     __attribute__ ((__nothrow__ , __leaf__));

extern int timer_getoverrun (timer_t __timerid) __attribute__ ((__nothrow__ , __leaf__));

typedef unsigned long int pthread_t;

union pthread_attr_t
{
  char __size[56];
  long int __align;
};

typedef union pthread_attr_t pthread_attr_t;

typedef struct __pthread_internal_list
{
  struct __pthread_internal_list *__prev;
  struct __pthread_internal_list *__next;
} __pthread_list_t;
typedef union
{
  struct __pthread_mutex_s
  {
    int __lock;
    unsigned int __count;
    int __owner;

    unsigned int __nusers;

    int __kind;

    short __spins;
    short __elision;
    __pthread_list_t __list;
  } __data;
  char __size[40];
  long int __align;
} pthread_mutex_t;

typedef union
{
  char __size[4];
  int __align;
} pthread_mutexattr_t;

typedef union
{
  struct
  {
    int __lock;
    unsigned int __futex;
    __extension__ unsigned long long int __total_seq;
    __extension__ unsigned long long int __wakeup_seq;
    __extension__ unsigned long long int __woken_seq;
    void *__mutex;
    unsigned int __nwaiters;
    unsigned int __broadcast_seq;
  } __data;
  char __size[48];
  __extension__ long long int __align;
} pthread_cond_t;

typedef union
{
  char __size[4];
  int __align;
} pthread_condattr_t;

typedef unsigned int pthread_key_t;

typedef int pthread_once_t;

typedef union
{

  struct
  {
    int __lock;
    unsigned int __nr_readers;
    unsigned int __readers_wakeup;
    unsigned int __writer_wakeup;
    unsigned int __nr_readers_queued;
    unsigned int __nr_writers_queued;
    int __writer;
    int __shared;
    unsigned long int __pad1;
    unsigned long int __pad2;

    unsigned int __flags;

  } __data;
  char __size[56];
  long int __align;
} pthread_rwlock_t;

typedef union
{
  char __size[8];
  long int __align;
} pthread_rwlockattr_t;

typedef volatile int pthread_spinlock_t;

typedef union
{
  char __size[32];
  long int __align;
} pthread_barrier_t;

typedef union
{
  char __size[4];
  int __align;
} pthread_barrierattr_t;

typedef long int __jmp_buf[8];

enum
{
  PTHREAD_CREATE_JOINABLE,

  PTHREAD_CREATE_DETACHED

};

enum
{
  PTHREAD_MUTEX_TIMED_NP,
  PTHREAD_MUTEX_RECURSIVE_NP,
  PTHREAD_MUTEX_ERRORCHECK_NP,
  PTHREAD_MUTEX_ADAPTIVE_NP

  ,
  PTHREAD_MUTEX_NORMAL = PTHREAD_MUTEX_TIMED_NP,
  PTHREAD_MUTEX_RECURSIVE = PTHREAD_MUTEX_RECURSIVE_NP,
  PTHREAD_MUTEX_ERRORCHECK = PTHREAD_MUTEX_ERRORCHECK_NP,
  PTHREAD_MUTEX_DEFAULT = PTHREAD_MUTEX_NORMAL

};

enum
{
  PTHREAD_MUTEX_STALLED,
  PTHREAD_MUTEX_STALLED_NP = PTHREAD_MUTEX_STALLED,
  PTHREAD_MUTEX_ROBUST,
  PTHREAD_MUTEX_ROBUST_NP = PTHREAD_MUTEX_ROBUST
};

enum
{
  PTHREAD_PRIO_NONE,
  PTHREAD_PRIO_INHERIT,
  PTHREAD_PRIO_PROTECT
};
enum
{
  PTHREAD_RWLOCK_PREFER_READER_NP,
  PTHREAD_RWLOCK_PREFER_WRITER_NP,
  PTHREAD_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP,
  PTHREAD_RWLOCK_DEFAULT_NP = PTHREAD_RWLOCK_PREFER_READER_NP
};
enum
{
  PTHREAD_INHERIT_SCHED,

  PTHREAD_EXPLICIT_SCHED

};

enum
{
  PTHREAD_SCOPE_SYSTEM,

  PTHREAD_SCOPE_PROCESS

};

enum
{
  PTHREAD_PROCESS_PRIVATE,

  PTHREAD_PROCESS_SHARED

};
struct _pthread_cleanup_buffer
{
  void (*__routine) (void *);
  void *__arg;
  int __canceltype;
  struct _pthread_cleanup_buffer *__prev;
};

enum
{
  PTHREAD_CANCEL_ENABLE,

  PTHREAD_CANCEL_DISABLE

};
enum
{
  PTHREAD_CANCEL_DEFERRED,

  PTHREAD_CANCEL_ASYNCHRONOUS

};

extern int pthread_create (pthread_t *__restrict __newthread,
      const pthread_attr_t *__restrict __attr,
      void *(*__start_routine) (void *),
      void *__restrict __arg) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 3)));

extern void pthread_exit (void *__retval) __attribute__ ((__noreturn__));

extern int pthread_join (pthread_t __th, void **__thread_return);
extern int pthread_detach (pthread_t __th) __attribute__ ((__nothrow__ , __leaf__));

extern pthread_t pthread_self (void) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__const__));

extern int pthread_equal (pthread_t __thread1, pthread_t __thread2)
  __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__const__));

extern int pthread_attr_init (pthread_attr_t *__attr) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_attr_destroy (pthread_attr_t *__attr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_attr_getdetachstate (const pthread_attr_t *__attr,
     int *__detachstate)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_attr_setdetachstate (pthread_attr_t *__attr,
     int __detachstate)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_attr_getguardsize (const pthread_attr_t *__attr,
          size_t *__guardsize)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_attr_setguardsize (pthread_attr_t *__attr,
          size_t __guardsize)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_attr_getschedparam (const pthread_attr_t *__restrict __attr,
           struct sched_param *__restrict __param)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_attr_setschedparam (pthread_attr_t *__restrict __attr,
           const struct sched_param *__restrict
           __param) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_attr_getschedpolicy (const pthread_attr_t *__restrict
     __attr, int *__restrict __policy)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_attr_setschedpolicy (pthread_attr_t *__attr, int __policy)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_attr_getinheritsched (const pthread_attr_t *__restrict
      __attr, int *__restrict __inherit)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_attr_setinheritsched (pthread_attr_t *__attr,
      int __inherit)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_attr_getscope (const pthread_attr_t *__restrict __attr,
      int *__restrict __scope)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_attr_setscope (pthread_attr_t *__attr, int __scope)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_attr_getstackaddr (const pthread_attr_t *__restrict
          __attr, void **__restrict __stackaddr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2))) __attribute__ ((__deprecated__));

extern int pthread_attr_setstackaddr (pthread_attr_t *__attr,
          void *__stackaddr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1))) __attribute__ ((__deprecated__));

extern int pthread_attr_getstacksize (const pthread_attr_t *__restrict
          __attr, size_t *__restrict __stacksize)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_attr_setstacksize (pthread_attr_t *__attr,
          size_t __stacksize)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_attr_getstack (const pthread_attr_t *__restrict __attr,
      void **__restrict __stackaddr,
      size_t *__restrict __stacksize)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2, 3)));

extern int pthread_attr_setstack (pthread_attr_t *__attr, void *__stackaddr,
      size_t __stacksize) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_setschedparam (pthread_t __target_thread, int __policy,
      const struct sched_param *__param)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (3)));

extern int pthread_getschedparam (pthread_t __target_thread,
      int *__restrict __policy,
      struct sched_param *__restrict __param)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (2, 3)));

extern int pthread_setschedprio (pthread_t __target_thread, int __prio)
     __attribute__ ((__nothrow__ , __leaf__));
extern int pthread_once (pthread_once_t *__once_control,
    void (*__init_routine) (void)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_setcancelstate (int __state, int *__oldstate);

extern int pthread_setcanceltype (int __type, int *__oldtype);

extern int pthread_cancel (pthread_t __th);

extern void pthread_testcancel (void);

typedef struct
{
  struct
  {
    __jmp_buf __cancel_jmp_buf;
    int __mask_was_saved;
  } __cancel_jmp_buf[1];
  void *__pad[4];
} __pthread_unwind_buf_t __attribute__ ((__aligned__));
struct __pthread_cleanup_frame
{
  void (*__cancel_routine) (void *);
  void *__cancel_arg;
  int __do_it;
  int __cancel_type;
};
extern void __pthread_register_cancel (__pthread_unwind_buf_t *__buf)
     ;
extern void __pthread_unregister_cancel (__pthread_unwind_buf_t *__buf)
  ;
extern void __pthread_unwind_next (__pthread_unwind_buf_t *__buf)
     __attribute__ ((__noreturn__))

     __attribute__ ((__weak__))

     ;

struct __jmp_buf_tag;
extern int __sigsetjmp (struct __jmp_buf_tag *__env, int __savemask) __attribute__ ((__nothrow__));

extern int pthread_mutex_init (pthread_mutex_t *__mutex,
          const pthread_mutexattr_t *__mutexattr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_mutex_destroy (pthread_mutex_t *__mutex)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_mutex_trylock (pthread_mutex_t *__mutex)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_mutex_lock (pthread_mutex_t *__mutex)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_mutex_timedlock (pthread_mutex_t *__restrict __mutex,
        const struct timespec *__restrict
        __abstime) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_mutex_unlock (pthread_mutex_t *__mutex)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_mutex_getprioceiling (const pthread_mutex_t *
      __restrict __mutex,
      int *__restrict __prioceiling)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_mutex_setprioceiling (pthread_mutex_t *__restrict __mutex,
      int __prioceiling,
      int *__restrict __old_ceiling)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 3)));

extern int pthread_mutex_consistent (pthread_mutex_t *__mutex)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutexattr_init (pthread_mutexattr_t *__attr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_mutexattr_destroy (pthread_mutexattr_t *__attr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_mutexattr_getpshared (const pthread_mutexattr_t *
      __restrict __attr,
      int *__restrict __pshared)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_mutexattr_setpshared (pthread_mutexattr_t *__attr,
      int __pshared)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_mutexattr_gettype (const pthread_mutexattr_t *__restrict
          __attr, int *__restrict __kind)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_mutexattr_settype (pthread_mutexattr_t *__attr, int __kind)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_mutexattr_getprotocol (const pthread_mutexattr_t *
       __restrict __attr,
       int *__restrict __protocol)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_mutexattr_setprotocol (pthread_mutexattr_t *__attr,
       int __protocol)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_mutexattr_getprioceiling (const pthread_mutexattr_t *
          __restrict __attr,
          int *__restrict __prioceiling)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_mutexattr_setprioceiling (pthread_mutexattr_t *__attr,
          int __prioceiling)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_mutexattr_getrobust (const pthread_mutexattr_t *__attr,
     int *__robustness)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_mutexattr_setrobust (pthread_mutexattr_t *__attr,
     int __robustness)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_rwlock_init (pthread_rwlock_t *__restrict __rwlock,
    const pthread_rwlockattr_t *__restrict
    __attr) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_rwlock_destroy (pthread_rwlock_t *__rwlock)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_rwlock_rdlock (pthread_rwlock_t *__rwlock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_rwlock_tryrdlock (pthread_rwlock_t *__rwlock)
  __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_rwlock_timedrdlock (pthread_rwlock_t *__restrict __rwlock,
           const struct timespec *__restrict
           __abstime) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_rwlock_wrlock (pthread_rwlock_t *__rwlock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_rwlock_trywrlock (pthread_rwlock_t *__rwlock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_rwlock_timedwrlock (pthread_rwlock_t *__restrict __rwlock,
           const struct timespec *__restrict
           __abstime) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_rwlock_unlock (pthread_rwlock_t *__rwlock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_rwlockattr_init (pthread_rwlockattr_t *__attr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_rwlockattr_destroy (pthread_rwlockattr_t *__attr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_rwlockattr_getpshared (const pthread_rwlockattr_t *
       __restrict __attr,
       int *__restrict __pshared)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_rwlockattr_setpshared (pthread_rwlockattr_t *__attr,
       int __pshared)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_rwlockattr_getkind_np (const pthread_rwlockattr_t *
       __restrict __attr,
       int *__restrict __pref)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_rwlockattr_setkind_np (pthread_rwlockattr_t *__attr,
       int __pref) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_cond_init (pthread_cond_t *__restrict __cond,
         const pthread_condattr_t *__restrict __cond_attr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_cond_destroy (pthread_cond_t *__cond)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_cond_signal (pthread_cond_t *__cond)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_cond_broadcast (pthread_cond_t *__cond)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_cond_wait (pthread_cond_t *__restrict __cond,
         pthread_mutex_t *__restrict __mutex)
     __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_cond_timedwait (pthread_cond_t *__restrict __cond,
       pthread_mutex_t *__restrict __mutex,
       const struct timespec *__restrict __abstime)
     __attribute__ ((__nonnull__ (1, 2, 3)));

extern int pthread_condattr_init (pthread_condattr_t *__attr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_condattr_destroy (pthread_condattr_t *__attr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_condattr_getpshared (const pthread_condattr_t *
     __restrict __attr,
     int *__restrict __pshared)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_condattr_setpshared (pthread_condattr_t *__attr,
     int __pshared) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_condattr_getclock (const pthread_condattr_t *
          __restrict __attr,
          __clockid_t *__restrict __clock_id)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_condattr_setclock (pthread_condattr_t *__attr,
          __clockid_t __clock_id)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_spin_init (pthread_spinlock_t *__lock, int __pshared)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_spin_destroy (pthread_spinlock_t *__lock)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_spin_lock (pthread_spinlock_t *__lock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_spin_trylock (pthread_spinlock_t *__lock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_spin_unlock (pthread_spinlock_t *__lock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_barrier_init (pthread_barrier_t *__restrict __barrier,
     const pthread_barrierattr_t *__restrict
     __attr, unsigned int __count)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_barrier_destroy (pthread_barrier_t *__barrier)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_barrier_wait (pthread_barrier_t *__barrier)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_barrierattr_init (pthread_barrierattr_t *__attr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_barrierattr_destroy (pthread_barrierattr_t *__attr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_barrierattr_getpshared (const pthread_barrierattr_t *
        __restrict __attr,
        int *__restrict __pshared)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern int pthread_barrierattr_setpshared (pthread_barrierattr_t *__attr,
        int __pshared)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_key_create (pthread_key_t *__key,
          void (*__destr_function) (void *))
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));

extern int pthread_key_delete (pthread_key_t __key) __attribute__ ((__nothrow__ , __leaf__));

extern void *pthread_getspecific (pthread_key_t __key) __attribute__ ((__nothrow__ , __leaf__));

extern int pthread_setspecific (pthread_key_t __key,
    const void *__pointer) __attribute__ ((__nothrow__ , __leaf__)) ;

extern int pthread_getcpuclockid (pthread_t __thread_id,
      __clockid_t *__clock_id)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (2)));
extern int pthread_atfork (void (*__prepare) (void),
      void (*__parent) (void),
      void (*__child) (void)) __attribute__ ((__nothrow__ , __leaf__));

typedef long int ptrdiff_t;
typedef int wchar_t;

extern int *__errno_location (void) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__const__));

struct ibv_srq_init_attr;
struct ibv_cq;
struct ibv_pd;
struct ibv_qp_init_attr;
struct ibv_qp_attr;
struct ibv_xrc_domain {
 struct ibv_context *context;
 uint32_t handle;
};

struct ibv_srq_legacy {
 struct ibv_context *context;
 void *srq_context;
 struct ibv_pd *pd;
 uint32_t handle;

 uint32_t events_completed;

 uint32_t xrc_srq_num_bin_compat;
 struct ibv_xrc_domain *xrc_domain_bin_compat;
 struct ibv_cq *xrc_cq_bin_compat;

 pthread_mutex_t mutex;
 pthread_cond_t cond;

 void *ibv_srq;

 uint32_t xrc_srq_num;
 struct ibv_xrc_domain *xrc_domain;
 struct ibv_cq *xrc_cq;
};
struct ibv_xrc_domain *ibv_open_xrc_domain(struct ibv_context *context,
        int fd, int oflag) __attribute__((deprecated));
struct ibv_srq *ibv_create_xrc_srq(struct ibv_pd *pd,
       struct ibv_xrc_domain *xrc_domain,
       struct ibv_cq *xrc_cq,
       struct ibv_srq_init_attr *srq_init_attr) __attribute__((deprecated));
int ibv_close_xrc_domain(struct ibv_xrc_domain *d) __attribute__((deprecated));
int ibv_create_xrc_rcv_qp(struct ibv_qp_init_attr *init_attr,
     uint32_t *xrc_rcv_qpn) __attribute__((deprecated));
int ibv_modify_xrc_rcv_qp(struct ibv_xrc_domain *xrc_domain,
     uint32_t xrc_qp_num,
     struct ibv_qp_attr *attr, int attr_mask) __attribute__((deprecated));
int ibv_query_xrc_rcv_qp(struct ibv_xrc_domain *xrc_domain, uint32_t xrc_qp_num,
    struct ibv_qp_attr *attr, int attr_mask,
    struct ibv_qp_init_attr *init_attr) __attribute__((deprecated));
int ibv_reg_xrc_rcv_qp(struct ibv_xrc_domain *xrc_domain,
    uint32_t xrc_qp_num) __attribute__((deprecated));
int ibv_unreg_xrc_rcv_qp(struct ibv_xrc_domain *xrc_domain,
    uint32_t xrc_qp_num) __attribute__((deprecated));

union ibv_gid {
 uint8_t raw[16];
 struct {
  uint64_t subnet_prefix;
  uint64_t interface_id;
 } global;
};
static void *__VERBS_ABI_IS_EXTENDED = ((uint8_t *)((void *)0)) - 1;

enum ibv_node_type {
 IBV_NODE_UNKNOWN = -1,
 IBV_NODE_CA = 1,
 IBV_NODE_SWITCH,
 IBV_NODE_ROUTER,
 IBV_NODE_RNIC,

 IBV_EXP_NODE_TYPE_START = 32,
 IBV_EXP_NODE_MIC = IBV_EXP_NODE_TYPE_START
};

enum ibv_transport_type {
 IBV_TRANSPORT_UNKNOWN = -1,
 IBV_TRANSPORT_IB = 0,
 IBV_TRANSPORT_IWARP,

 IBV_EXP_TRANSPORT_TYPE_START = 32,
 IBV_EXP_TRANSPORT_SCIF = IBV_EXP_TRANSPORT_TYPE_START
};

enum ibv_device_cap_flags {
 IBV_DEVICE_RESIZE_MAX_WR = 1,
 IBV_DEVICE_BAD_PKEY_CNTR = 1 << 1,
 IBV_DEVICE_BAD_QKEY_CNTR = 1 << 2,
 IBV_DEVICE_RAW_MULTI = 1 << 3,
 IBV_DEVICE_AUTO_PATH_MIG = 1 << 4,
 IBV_DEVICE_CHANGE_PHY_PORT = 1 << 5,
 IBV_DEVICE_UD_AV_PORT_ENFORCE = 1 << 6,
 IBV_DEVICE_CURR_QP_STATE_MOD = 1 << 7,
 IBV_DEVICE_SHUTDOWN_PORT = 1 << 8,
 IBV_DEVICE_INIT_TYPE = 1 << 9,
 IBV_DEVICE_PORT_ACTIVE_EVENT = 1 << 10,
 IBV_DEVICE_SYS_IMAGE_GUID = 1 << 11,
 IBV_DEVICE_RC_RNR_NAK_GEN = 1 << 12,
 IBV_DEVICE_SRQ_RESIZE = 1 << 13,
 IBV_DEVICE_N_NOTIFY_CQ = 1 << 14,
 IBV_DEVICE_XRC = 1 << 20,
};

enum ibv_atomic_cap {
 IBV_ATOMIC_NONE,
 IBV_ATOMIC_HCA,
 IBV_ATOMIC_GLOB
};

struct ibv_device_attr {
 char fw_ver[64];
 uint64_t node_guid;
 uint64_t sys_image_guid;
 uint64_t max_mr_size;
 uint64_t page_size_cap;
 uint32_t vendor_id;
 uint32_t vendor_part_id;
 uint32_t hw_ver;
 int max_qp;
 int max_qp_wr;
 int device_cap_flags;
 int max_sge;
 int max_sge_rd;
 int max_cq;
 int max_cqe;
 int max_mr;
 int max_pd;
 int max_qp_rd_atom;
 int max_ee_rd_atom;
 int max_res_rd_atom;
 int max_qp_init_rd_atom;
 int max_ee_init_rd_atom;
 enum ibv_atomic_cap atomic_cap;
 int max_ee;
 int max_rdd;
 int max_mw;
 int max_raw_ipv6_qp;
 int max_raw_ethy_qp;
 int max_mcast_grp;
 int max_mcast_qp_attach;
 int max_total_mcast_qp_attach;
 int max_ah;
 int max_fmr;
 int max_map_per_fmr;
 int max_srq;
 int max_srq_wr;
 int max_srq_sge;
 uint16_t max_pkeys;
 uint8_t local_ca_ack_delay;
 uint8_t phys_port_cnt;
};

enum ibv_mtu {
 IBV_MTU_256 = 1,
 IBV_MTU_512 = 2,
 IBV_MTU_1024 = 3,
 IBV_MTU_2048 = 4,
 IBV_MTU_4096 = 5
};

enum ibv_port_state {
 IBV_PORT_NOP = 0,
 IBV_PORT_DOWN = 1,
 IBV_PORT_INIT = 2,
 IBV_PORT_ARMED = 3,
 IBV_PORT_ACTIVE = 4,
 IBV_PORT_ACTIVE_DEFER = 5
};

enum {
 IBV_LINK_LAYER_UNSPECIFIED,
 IBV_LINK_LAYER_INFINIBAND,
 IBV_LINK_LAYER_ETHERNET,

 IBV_EXP_LINK_LAYER_START = 32,
 IBV_EXP_LINK_LAYER_SCIF = IBV_EXP_LINK_LAYER_START
};

enum ibv_port_cap_flags {
 IBV_PORT_SM = 1 << 1,
 IBV_PORT_NOTICE_SUP = 1 << 2,
 IBV_PORT_TRAP_SUP = 1 << 3,
 IBV_PORT_OPT_IPD_SUP = 1 << 4,
 IBV_PORT_AUTO_MIGR_SUP = 1 << 5,
 IBV_PORT_SL_MAP_SUP = 1 << 6,
 IBV_PORT_MKEY_NVRAM = 1 << 7,
 IBV_PORT_PKEY_NVRAM = 1 << 8,
 IBV_PORT_LED_INFO_SUP = 1 << 9,
 IBV_PORT_SYS_IMAGE_GUID_SUP = 1 << 11,
 IBV_PORT_PKEY_SW_EXT_PORT_TRAP_SUP = 1 << 12,
 IBV_PORT_EXTENDED_SPEEDS_SUP = 1 << 14,
 IBV_PORT_CM_SUP = 1 << 16,
 IBV_PORT_SNMP_TUNNEL_SUP = 1 << 17,
 IBV_PORT_REINIT_SUP = 1 << 18,
 IBV_PORT_DEVICE_MGMT_SUP = 1 << 19,
 IBV_PORT_VENDOR_CLASS = 1 << 24,
 IBV_PORT_CLIENT_REG_SUP = 1 << 25,
 IBV_PORT_IP_BASED_GIDS = 1 << 26,
};

struct ibv_port_attr {
 enum ibv_port_state state;
 enum ibv_mtu max_mtu;
 enum ibv_mtu active_mtu;
 int gid_tbl_len;
 uint32_t port_cap_flags;
 uint32_t max_msg_sz;
 uint32_t bad_pkey_cntr;
 uint32_t qkey_viol_cntr;
 uint16_t pkey_tbl_len;
 uint16_t lid;
 uint16_t sm_lid;
 uint8_t lmc;
 uint8_t max_vl_num;
 uint8_t sm_sl;
 uint8_t subnet_timeout;
 uint8_t init_type_reply;
 uint8_t active_width;
 uint8_t active_speed;
 uint8_t phys_state;
 uint8_t link_layer;
 uint8_t reserved;
};

enum ibv_event_type {
 IBV_EVENT_CQ_ERR,
 IBV_EVENT_QP_FATAL,
 IBV_EVENT_QP_REQ_ERR,
 IBV_EVENT_QP_ACCESS_ERR,
 IBV_EVENT_COMM_EST,
 IBV_EVENT_SQ_DRAINED,
 IBV_EVENT_PATH_MIG,
 IBV_EVENT_PATH_MIG_ERR,
 IBV_EVENT_DEVICE_FATAL,
 IBV_EVENT_PORT_ACTIVE,
 IBV_EVENT_PORT_ERR,
 IBV_EVENT_LID_CHANGE,
 IBV_EVENT_PKEY_CHANGE,
 IBV_EVENT_SM_CHANGE,
 IBV_EVENT_SRQ_ERR,
 IBV_EVENT_SRQ_LIMIT_REACHED,
 IBV_EVENT_QP_LAST_WQE_REACHED,
 IBV_EVENT_CLIENT_REREGISTER,
 IBV_EVENT_GID_CHANGE,

 IBV_EXP_EVENT_DCT_KEY_VIOLATION = 32,
};

struct ibv_async_event {
 union {
  struct ibv_cq *cq;
  struct ibv_qp *qp;
  struct ibv_srq *srq;
  int port_num;

  uint32_t xrc_qp_num;
 } element;
 enum ibv_event_type event_type;
};

enum ibv_wc_status {
 IBV_WC_SUCCESS,
 IBV_WC_LOC_LEN_ERR,
 IBV_WC_LOC_QP_OP_ERR,
 IBV_WC_LOC_EEC_OP_ERR,
 IBV_WC_LOC_PROT_ERR,
 IBV_WC_WR_FLUSH_ERR,
 IBV_WC_MW_BIND_ERR,
 IBV_WC_BAD_RESP_ERR,
 IBV_WC_LOC_ACCESS_ERR,
 IBV_WC_REM_INV_REQ_ERR,
 IBV_WC_REM_ACCESS_ERR,
 IBV_WC_REM_OP_ERR,
 IBV_WC_RETRY_EXC_ERR,
 IBV_WC_RNR_RETRY_EXC_ERR,
 IBV_WC_LOC_RDD_VIOL_ERR,
 IBV_WC_REM_INV_RD_REQ_ERR,
 IBV_WC_REM_ABORT_ERR,
 IBV_WC_INV_EECN_ERR,
 IBV_WC_INV_EEC_STATE_ERR,
 IBV_WC_FATAL_ERR,
 IBV_WC_RESP_TIMEOUT_ERR,
 IBV_WC_GENERAL_ERR
};
const char *ibv_wc_status_str(enum ibv_wc_status status);

enum ibv_wc_opcode {
 IBV_WC_SEND,
 IBV_WC_RDMA_WRITE,
 IBV_WC_RDMA_READ,
 IBV_WC_COMP_SWAP,
 IBV_WC_FETCH_ADD,
 IBV_WC_BIND_MW,

 IBV_WC_RECV = 1 << 7,
 IBV_WC_RECV_RDMA_WITH_IMM
};

enum ibv_wc_flags {
 IBV_WC_GRH = 1 << 0,
 IBV_WC_WITH_IMM = 1 << 1
};

struct ibv_wc {
 uint64_t wr_id;
 enum ibv_wc_status status;
 enum ibv_wc_opcode opcode;
 uint32_t vendor_err;
 uint32_t byte_len;
 uint32_t imm_data;
 uint32_t qp_num;
 uint32_t src_qp;
 int wc_flags;
 uint16_t pkey_index;
 uint16_t slid;
 uint8_t sl;
 uint8_t dlid_path_bits;
};

enum ibv_access_flags {
 IBV_ACCESS_LOCAL_WRITE = 1,
 IBV_ACCESS_REMOTE_WRITE = (1<<1),
 IBV_ACCESS_REMOTE_READ = (1<<2),
 IBV_ACCESS_REMOTE_ATOMIC = (1<<3),
 IBV_ACCESS_MW_BIND = (1<<4)
};

struct ibv_pd {
 struct ibv_context *context;
 uint32_t handle;
};

enum ibv_xrcd_init_attr_mask {
 IBV_XRCD_INIT_ATTR_FD = 1 << 0,
 IBV_XRCD_INIT_ATTR_OFLAGS = 1 << 1,
 IBV_XRCD_INIT_ATTR_RESERVED = 1 << 2
};

struct ibv_xrcd_init_attr {
 uint32_t comp_mask;
 int fd;
 int oflags;
};

struct ibv_xrcd {
 struct ibv_context *context;
};

enum ibv_rereg_mr_flags {
 IBV_REREG_MR_CHANGE_TRANSLATION = (1 << 0),
 IBV_REREG_MR_CHANGE_PD = (1 << 1),
 IBV_REREG_MR_CHANGE_ACCESS = (1 << 2),
 IBV_REREG_MR_KEEP_VALID = (1 << 3)
};

struct ibv_mr {
 struct ibv_context *context;
 struct ibv_pd *pd;
 void *addr;
 size_t length;
 uint32_t handle;
 uint32_t lkey;
 uint32_t rkey;
};

enum ibv_mw_type {
 IBV_MW_TYPE_1 = 1,
 IBV_MW_TYPE_2 = 2
};

struct ibv_mw {
 struct ibv_context *context;
 struct ibv_pd *pd;
 uint32_t rkey;
};

struct ibv_global_route {
 union ibv_gid dgid;
 uint32_t flow_label;
 uint8_t sgid_index;
 uint8_t hop_limit;
 uint8_t traffic_class;
};

struct ibv_grh {
 uint32_t version_tclass_flow;
 uint16_t paylen;
 uint8_t next_hdr;
 uint8_t hop_limit;
 union ibv_gid sgid;
 union ibv_gid dgid;
};

enum ibv_rate {
 IBV_RATE_MAX = 0,
 IBV_RATE_2_5_GBPS = 2,
 IBV_RATE_5_GBPS = 5,
 IBV_RATE_10_GBPS = 3,
 IBV_RATE_20_GBPS = 6,
 IBV_RATE_30_GBPS = 4,
 IBV_RATE_40_GBPS = 7,
 IBV_RATE_60_GBPS = 8,
 IBV_RATE_80_GBPS = 9,
 IBV_RATE_120_GBPS = 10,
 IBV_RATE_14_GBPS = 11,
 IBV_RATE_56_GBPS = 12,
 IBV_RATE_112_GBPS = 13,
 IBV_RATE_168_GBPS = 14,
 IBV_RATE_25_GBPS = 15,
 IBV_RATE_100_GBPS = 16,
 IBV_RATE_200_GBPS = 17,
 IBV_RATE_300_GBPS = 18
};

int ibv_rate_to_mult(enum ibv_rate rate) __attribute__((const));

enum ibv_rate mult_to_ibv_rate(int mult) __attribute__((const));

int ibv_rate_to_mbps(enum ibv_rate rate) __attribute__((const));

enum ibv_rate mbps_to_ibv_rate(int mbps) __attribute__((const));

struct ibv_ah_attr {
 struct ibv_global_route grh;
 uint16_t dlid;
 uint8_t sl;
 uint8_t src_path_bits;
 uint8_t static_rate;
 uint8_t is_global;
 uint8_t port_num;
};

enum ibv_srq_attr_mask {
 IBV_SRQ_MAX_WR = 1 << 0,
 IBV_SRQ_LIMIT = 1 << 1
};

struct ibv_srq_attr {
 uint32_t max_wr;
 uint32_t max_sge;
 uint32_t srq_limit;
};

struct ibv_srq_init_attr {
 void *srq_context;
 struct ibv_srq_attr attr;
};

enum ibv_srq_type {
 IBV_SRQT_BASIC,
 IBV_SRQT_XRC
};

enum ibv_srq_init_attr_mask {
 IBV_SRQ_INIT_ATTR_TYPE = 1 << 0,
 IBV_SRQ_INIT_ATTR_PD = 1 << 1,
 IBV_SRQ_INIT_ATTR_XRCD = 1 << 2,
 IBV_SRQ_INIT_ATTR_CQ = 1 << 3,
 IBV_SRQ_INIT_ATTR_RESERVED = 1 << 4
};

struct ibv_srq_init_attr_ex {
 void *srq_context;
 struct ibv_srq_attr attr;

 uint32_t comp_mask;
 enum ibv_srq_type srq_type;
 struct ibv_pd *pd;
 struct ibv_xrcd *xrcd;
 struct ibv_cq *cq;
};

enum ibv_qp_type {
 IBV_QPT_RC = 2,
 IBV_QPT_UC,
 IBV_QPT_UD,

 IBV_QPT_XRC,
 IBV_QPT_RAW_PACKET = 8,
 IBV_QPT_RAW_ETH = 8,
 IBV_QPT_XRC_SEND = 9,
 IBV_QPT_XRC_RECV,

 IBV_EXP_QP_TYPE_START = 32,
 IBV_EXP_QPT_DC_INI = IBV_EXP_QP_TYPE_START
};

struct ibv_qp_cap {
 uint32_t max_send_wr;
 uint32_t max_recv_wr;
 uint32_t max_send_sge;
 uint32_t max_recv_sge;
 uint32_t max_inline_data;
};

struct ibv_qp_init_attr {
 void *qp_context;
 struct ibv_cq *send_cq;
 struct ibv_cq *recv_cq;
 struct ibv_srq *srq;
 struct ibv_qp_cap cap;
 enum ibv_qp_type qp_type;
 int sq_sig_all;

 struct ibv_xrc_domain *xrc_domain;
};

enum ibv_qp_init_attr_mask {
 IBV_QP_INIT_ATTR_PD = 1 << 0,
 IBV_QP_INIT_ATTR_XRCD = 1 << 1,
 IBV_QP_INIT_ATTR_RESERVED = 1 << 2
};

struct ibv_qp_init_attr_ex {
 void *qp_context;
 struct ibv_cq *send_cq;
 struct ibv_cq *recv_cq;
 struct ibv_srq *srq;
 struct ibv_qp_cap cap;
 enum ibv_qp_type qp_type;
 int sq_sig_all;

 uint32_t comp_mask;
 struct ibv_pd *pd;
 struct ibv_xrcd *xrcd;
};

enum ibv_qp_open_attr_mask {
 IBV_QP_OPEN_ATTR_NUM = 1 << 0,
 IBV_QP_OPEN_ATTR_XRCD = 1 << 1,
 IBV_QP_OPEN_ATTR_CONTEXT = 1 << 2,
 IBV_QP_OPEN_ATTR_TYPE = 1 << 3,
 IBV_QP_OPEN_ATTR_RESERVED = 1 << 4
};

struct ibv_qp_open_attr {
 uint32_t comp_mask;
 uint32_t qp_num;
 struct ibv_xrcd *xrcd;
 void *qp_context;
 enum ibv_qp_type qp_type;
};

enum ibv_qp_attr_mask {
 IBV_QP_STATE = 1 << 0,
 IBV_QP_CUR_STATE = 1 << 1,
 IBV_QP_EN_SQD_ASYNC_NOTIFY = 1 << 2,
 IBV_QP_ACCESS_FLAGS = 1 << 3,
 IBV_QP_PKEY_INDEX = 1 << 4,
 IBV_QP_PORT = 1 << 5,
 IBV_QP_QKEY = 1 << 6,
 IBV_QP_AV = 1 << 7,
 IBV_QP_PATH_MTU = 1 << 8,
 IBV_QP_TIMEOUT = 1 << 9,
 IBV_QP_RETRY_CNT = 1 << 10,
 IBV_QP_RNR_RETRY = 1 << 11,
 IBV_QP_RQ_PSN = 1 << 12,
 IBV_QP_MAX_QP_RD_ATOMIC = 1 << 13,
 IBV_QP_ALT_PATH = 1 << 14,
 IBV_QP_MIN_RNR_TIMER = 1 << 15,
 IBV_QP_SQ_PSN = 1 << 16,
 IBV_QP_MAX_DEST_RD_ATOMIC = 1 << 17,
 IBV_QP_PATH_MIG_STATE = 1 << 18,
 IBV_QP_CAP = 1 << 19,
 IBV_QP_DEST_QPN = 1 << 20
};

enum ibv_qp_state {
 IBV_QPS_RESET,
 IBV_QPS_INIT,
 IBV_QPS_RTR,
 IBV_QPS_RTS,
 IBV_QPS_SQD,
 IBV_QPS_SQE,
 IBV_QPS_ERR,
 IBV_QPS_UNKNOWN
};

enum ibv_mig_state {
 IBV_MIG_MIGRATED,
 IBV_MIG_REARM,
 IBV_MIG_ARMED
};

struct ibv_qp_attr {
 enum ibv_qp_state qp_state;
 enum ibv_qp_state cur_qp_state;
 enum ibv_mtu path_mtu;
 enum ibv_mig_state path_mig_state;
 uint32_t qkey;
 uint32_t rq_psn;
 uint32_t sq_psn;
 uint32_t dest_qp_num;
 int qp_access_flags;
 struct ibv_qp_cap cap;
 struct ibv_ah_attr ah_attr;
 struct ibv_ah_attr alt_ah_attr;
 uint16_t pkey_index;
 uint16_t alt_pkey_index;
 uint8_t en_sqd_async_notify;
 uint8_t sq_draining;
 uint8_t max_rd_atomic;
 uint8_t max_dest_rd_atomic;
 uint8_t min_rnr_timer;
 uint8_t port_num;
 uint8_t timeout;
 uint8_t retry_cnt;
 uint8_t rnr_retry;
 uint8_t alt_port_num;
 uint8_t alt_timeout;
};

enum ibv_wr_opcode {
 IBV_WR_RDMA_WRITE,
 IBV_WR_RDMA_WRITE_WITH_IMM,
 IBV_WR_SEND,
 IBV_WR_SEND_WITH_IMM,
 IBV_WR_RDMA_READ,
 IBV_WR_ATOMIC_CMP_AND_SWP,
 IBV_WR_ATOMIC_FETCH_AND_ADD
};

enum ibv_send_flags {
 IBV_SEND_FENCE = 1 << 0,
 IBV_SEND_SIGNALED = 1 << 1,
 IBV_SEND_SOLICITED = 1 << 2,
 IBV_SEND_INLINE = 1 << 3
};

struct ibv_sge {
 uint64_t addr;
 uint32_t length;
 uint32_t lkey;
};

struct ibv_send_wr {
 uint64_t wr_id;
 struct ibv_send_wr *next;
 struct ibv_sge *sg_list;
 int num_sge;
 enum ibv_wr_opcode opcode;
 int send_flags;
 uint32_t imm_data;
 union {
  struct {
   uint64_t remote_addr;
   uint32_t rkey;
  } rdma;
  struct {
   uint64_t remote_addr;
   uint64_t compare_add;
   uint64_t swap;
   uint32_t rkey;
  } atomic;
  struct {
   struct ibv_ah *ah;
   uint32_t remote_qpn;
   uint32_t remote_qkey;
  } ud;
 } wr;
 union {
  union {
   struct {
    uint32_t remote_srqn;
   } xrc;
  } qp_type;

  uint32_t xrc_remote_srq_num;
 };
};

struct ibv_recv_wr {
 uint64_t wr_id;
 struct ibv_recv_wr *next;
 struct ibv_sge *sg_list;
 int num_sge;
};

struct ibv_mw_bind {
 uint64_t wr_id;
 struct ibv_mr *mr;
 void *addr;
 size_t length;
 int send_flags;
 int mw_access_flags;
};

struct ibv_srq {
 struct ibv_context *context;
 void *srq_context;
 struct ibv_pd *pd;
 uint32_t handle;

 pthread_mutex_t mutex;
 pthread_cond_t cond;
 uint32_t events_completed;

 uint32_t xrc_srq_num_bin_compat_padding;
 struct ibv_xrc_domain *xrc_domain_bin_compat_padding;
 struct ibv_cq *xrc_cq_bin_compat_padding;
 void *ibv_srq_padding;

 uint32_t xrc_srq_num;
 struct ibv_xrc_domain *xrc_domain;
 struct ibv_cq *xrc_cq;
};

enum ibv_event_flags {
 IBV_XRC_QP_EVENT_FLAG = 0x80000000,
};

struct ibv_qp {
 struct ibv_context *context;
 void *qp_context;
 struct ibv_pd *pd;
 struct ibv_cq *send_cq;
 struct ibv_cq *recv_cq;
 struct ibv_srq *srq;
 uint32_t handle;
 uint32_t qp_num;
 enum ibv_qp_state state;
 enum ibv_qp_type qp_type;

 pthread_mutex_t mutex;
 pthread_cond_t cond;
 uint32_t events_completed;
};

struct ibv_comp_channel {
 struct ibv_context *context;
 int fd;
 int refcnt;
};

struct ibv_cq {
 struct ibv_context *context;
 struct ibv_comp_channel *channel;
 void *cq_context;
 uint32_t handle;
 int cqe;

 pthread_mutex_t mutex;
 pthread_cond_t cond;
 uint32_t comp_events_completed;
 uint32_t async_events_completed;
};

struct ibv_ah {
 struct ibv_context *context;
 struct ibv_pd *pd;
 uint32_t handle;
};

struct ibv_device;
struct ibv_context;

struct ibv_device_ops {
 struct ibv_context * (*alloc_context)(struct ibv_device *device, int cmd_fd);
 void (*free_context)(struct ibv_context *context);
};

enum {
 IBV_SYSFS_NAME_MAX = 64,
 IBV_SYSFS_PATH_MAX = 256
};

struct ibv_device {
 struct ibv_device_ops ops;
 enum ibv_node_type node_type;
 enum ibv_transport_type transport_type;

 char name[IBV_SYSFS_NAME_MAX];

 char dev_name[IBV_SYSFS_NAME_MAX];

 char dev_path[IBV_SYSFS_PATH_MAX];

 char ibdev_path[IBV_SYSFS_PATH_MAX];
};

struct verbs_device {
 struct ibv_device device;
 size_t sz;
 size_t size_of_context;
 int (*init_context)(struct verbs_device *device,
    struct ibv_context *ctx, int cmd_fd);
 void (*uninit_context)(struct verbs_device *device,
    struct ibv_context *ctx);

};

struct ibv_context_ops {
 int (*query_device)(struct ibv_context *context,
           struct ibv_device_attr *device_attr);
 int (*query_port)(struct ibv_context *context, uint8_t port_num,
           struct ibv_port_attr *port_attr);
 struct ibv_pd * (*alloc_pd)(struct ibv_context *context);
 int (*dealloc_pd)(struct ibv_pd *pd);
 struct ibv_mr * (*reg_mr)(struct ibv_pd *pd, void *addr, size_t length,
       int access);
 struct ibv_mr * (*rereg_mr)(struct ibv_mr *mr,
         int flags,
         struct ibv_pd *pd, void *addr,
         size_t length,
         int access);
 int (*dereg_mr)(struct ibv_mr *mr);
 struct ibv_mw * (*alloc_mw)(struct ibv_pd *pd, enum ibv_mw_type type);
 int (*bind_mw)(struct ibv_qp *qp, struct ibv_mw *mw,
        struct ibv_mw_bind *mw_bind);
 int (*dealloc_mw)(struct ibv_mw *mw);
 struct ibv_cq * (*create_cq)(struct ibv_context *context, int cqe,
          struct ibv_comp_channel *channel,
          int comp_vector);
 int (*poll_cq)(struct ibv_cq *cq, int num_entries, struct ibv_wc *wc);
 int (*req_notify_cq)(struct ibv_cq *cq, int solicited_only);
 void (*cq_event)(struct ibv_cq *cq);
 int (*resize_cq)(struct ibv_cq *cq, int cqe);
 int (*destroy_cq)(struct ibv_cq *cq);
 struct ibv_srq * (*create_srq)(struct ibv_pd *pd,
           struct ibv_srq_init_attr *srq_init_attr);
 int (*modify_srq)(struct ibv_srq *srq,
           struct ibv_srq_attr *srq_attr,
           int srq_attr_mask);
 int (*query_srq)(struct ibv_srq *srq,
          struct ibv_srq_attr *srq_attr);
 int (*destroy_srq)(struct ibv_srq *srq);
 int (*post_srq_recv)(struct ibv_srq *srq,
       struct ibv_recv_wr *recv_wr,
       struct ibv_recv_wr **bad_recv_wr);
 struct ibv_qp * (*create_qp)(struct ibv_pd *pd, struct ibv_qp_init_attr *attr);
 int (*query_qp)(struct ibv_qp *qp, struct ibv_qp_attr *attr,
         int attr_mask,
         struct ibv_qp_init_attr *init_attr);
 int (*modify_qp)(struct ibv_qp *qp, struct ibv_qp_attr *attr,
          int attr_mask);
 int (*destroy_qp)(struct ibv_qp *qp);
 int (*post_send)(struct ibv_qp *qp, struct ibv_send_wr *wr,
          struct ibv_send_wr **bad_wr);
 int (*post_recv)(struct ibv_qp *qp, struct ibv_recv_wr *wr,
          struct ibv_recv_wr **bad_wr);
 struct ibv_ah * (*create_ah)(struct ibv_pd *pd, struct ibv_ah_attr *attr);
 int (*destroy_ah)(struct ibv_ah *ah);
 int (*attach_mcast)(struct ibv_qp *qp, const union ibv_gid *gid,
      uint16_t lid);
 int (*detach_mcast)(struct ibv_qp *qp, const union ibv_gid *gid,
      uint16_t lid);
 void (*async_event)(struct ibv_async_event *event);
};

struct ibv_context {
 struct ibv_device *device;
 struct ibv_context_ops ops;
 int cmd_fd;
 int async_fd;
 int num_comp_vectors;
 pthread_mutex_t mutex;
 void *abi_compat;
};

enum verbs_context_mask {
 VERBS_CONTEXT_XRCD = (uint64_t)1 << 0,
 VERBS_CONTEXT_SRQ = (uint64_t)1 << 1,
 VERBS_CONTEXT_QP = (uint64_t)1 << 2,
 VERBS_CONTEXT_RESERVED = (uint64_t)1 << 3,
 VERBS_CONTEXT_EXP = (uint64_t)1 << 62
};

struct verbs_context {

 struct ibv_qp * (*open_qp)(struct ibv_context *context,
   struct ibv_qp_open_attr *attr);
 struct ibv_qp * (*create_qp_ex)(struct ibv_context *context,
   struct ibv_qp_init_attr_ex *qp_init_attr_ex);
 int (*get_srq_num)(struct ibv_srq *srq, uint32_t *srq_num);
 struct ibv_srq * (*create_srq_ex)(struct ibv_context *context,
   struct ibv_srq_init_attr_ex *srq_init_attr_ex);
 struct ibv_xrcd * (*open_xrcd)(struct ibv_context *context,
   struct ibv_xrcd_init_attr *xrcd_init_attr);
 int (*close_xrcd)(struct ibv_xrcd *xrcd);
 uint64_t has_comp_mask;
 size_t sz;
 struct ibv_context context;
};

static inline struct verbs_context *verbs_get_ctx(struct ibv_context *ctx)
{
 return (!ctx || (ctx->abi_compat != __VERBS_ABI_IS_EXTENDED)) ?
  ((void *)0) : ((struct verbs_context *) ((uint8_t *)(ctx) - __builtin_offsetof (struct verbs_context, context)));
}
static inline struct verbs_device *verbs_get_device(
     const struct ibv_device *dev)
{
 return (dev->ops.alloc_context) ?
  ((void *)0) : ((struct verbs_device *) ((uint8_t *)(dev) - __builtin_offsetof (struct verbs_device, device)));
}
struct ibv_device **ibv_get_device_list(int *num_devices);
void ibv_free_device_list(struct ibv_device **list);

const char *ibv_get_device_name(struct ibv_device *device);

uint64_t ibv_get_device_guid(struct ibv_device *device);

struct ibv_context *ibv_open_device(struct ibv_device *device);

int ibv_close_device(struct ibv_context *context);
int ibv_get_async_event(struct ibv_context *context,
   struct ibv_async_event *event);
void ibv_ack_async_event(struct ibv_async_event *event);

int ibv_query_device(struct ibv_context *context,
       struct ibv_device_attr *device_attr);

int ibv_query_port(struct ibv_context *context, uint8_t port_num,
     struct ibv_port_attr *port_attr);

static inline int ___ibv_query_port(struct ibv_context *context,
        uint8_t port_num,
        struct ibv_port_attr *port_attr)
{

 port_attr->link_layer = IBV_LINK_LAYER_UNSPECIFIED;
 port_attr->reserved = 0;

 return ibv_query_port(context, port_num, port_attr);
}

int ibv_query_gid(struct ibv_context *context, uint8_t port_num,
    int index, union ibv_gid *gid);

int ibv_query_pkey(struct ibv_context *context, uint8_t port_num,
     int index, uint16_t *pkey);

struct ibv_pd *ibv_alloc_pd(struct ibv_context *context);

int ibv_dealloc_pd(struct ibv_pd *pd);

static inline struct ibv_xrcd *
ibv_open_xrcd(struct ibv_context *context, struct ibv_xrcd_init_attr *xrcd_init_attr)
{
 struct verbs_context *vctx = ({ struct verbs_context *vctx = verbs_get_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context, open_xrcd)) || !vctx->open_xrcd) ? ((void *)0) : vctx; });
 if (!vctx) {
  (*__errno_location ()) = 38;
  return ((void *)0);
 }
 return vctx->open_xrcd(context, xrcd_init_attr);
}

static inline int ibv_close_xrcd(struct ibv_xrcd *xrcd)
{
 struct verbs_context *vctx = verbs_get_ctx(xrcd->context);
 return vctx->close_xrcd(xrcd);
}

struct ibv_mr *ibv_reg_mr(struct ibv_pd *pd, void *addr,
     size_t length, int access);

int ibv_dereg_mr(struct ibv_mr *mr);

static inline struct ibv_mw *ibv_alloc_mw(struct ibv_pd *pd,
  enum ibv_mw_type type)
{
 if (!pd->context->ops.alloc_mw) {
  (*__errno_location ()) = 38;
  return ((void *)0);
 }

 struct ibv_mw *mw = pd->context->ops.alloc_mw(pd, type);
 if (mw) {
  mw->context = pd->context;
  mw->pd = pd;
 }
 return mw;
}

static inline int ibv_dealloc_mw(struct ibv_mw *mw)
{
 return mw->context->ops.dealloc_mw(mw);
}

static inline uint32_t ibv_inc_rkey(uint32_t rkey)
{
 const uint32_t mask = 0x000000ff;
 uint8_t newtag = (uint8_t) ((rkey + 1) & mask);
 return (rkey & ~mask) | newtag;
}

struct ibv_comp_channel *ibv_create_comp_channel(struct ibv_context *context);

int ibv_destroy_comp_channel(struct ibv_comp_channel *channel);
struct ibv_cq *ibv_create_cq(struct ibv_context *context, int cqe,
        void *cq_context,
        struct ibv_comp_channel *channel,
        int comp_vector);
int ibv_resize_cq(struct ibv_cq *cq, int cqe);

int ibv_destroy_cq(struct ibv_cq *cq);
int ibv_get_cq_event(struct ibv_comp_channel *channel,
       struct ibv_cq **cq, void **cq_context);
void ibv_ack_cq_events(struct ibv_cq *cq, unsigned int nevents);
static inline int ibv_poll_cq(struct ibv_cq *cq, int num_entries, struct ibv_wc *wc)
{
 return cq->context->ops.poll_cq(cq, num_entries, wc);
}
static inline int ibv_req_notify_cq(struct ibv_cq *cq, int solicited_only)
{
 return cq->context->ops.req_notify_cq(cq, solicited_only);
}
struct ibv_srq *ibv_create_srq(struct ibv_pd *pd,
          struct ibv_srq_init_attr *srq_init_attr);

static inline struct ibv_srq *
ibv_create_srq_ex(struct ibv_context *context,
    struct ibv_srq_init_attr_ex *srq_init_attr_ex)
{
 struct verbs_context *vctx;
 uint32_t mask = srq_init_attr_ex->comp_mask;

 if (!(mask & ~(IBV_SRQ_INIT_ATTR_PD | IBV_SRQ_INIT_ATTR_TYPE)) &&
     (mask & IBV_SRQ_INIT_ATTR_PD) &&
     (!(mask & IBV_SRQ_INIT_ATTR_TYPE) ||
      (srq_init_attr_ex->srq_type == IBV_SRQT_BASIC)))
  return ibv_create_srq(srq_init_attr_ex->pd,
          (struct ibv_srq_init_attr *) srq_init_attr_ex);

 vctx = ({ struct verbs_context *vctx = verbs_get_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context, create_srq_ex)) || !vctx->create_srq_ex) ? ((void *)0) : vctx; });
 if (!vctx) {
  (*__errno_location ()) = 38;
  return ((void *)0);
 }
 return vctx->create_srq_ex(context, srq_init_attr_ex);
}
int ibv_modify_srq(struct ibv_srq *srq,
     struct ibv_srq_attr *srq_attr,
     int srq_attr_mask);

int ibv_query_srq(struct ibv_srq *srq, struct ibv_srq_attr *srq_attr);

static inline int ibv_get_srq_num(struct ibv_srq *srq, uint32_t *srq_num)
{
 struct verbs_context *vctx = ({ struct verbs_context *vctx = verbs_get_ctx(srq->context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context, get_srq_num)) || !vctx->get_srq_num) ? ((void *)0) : vctx; });

 if (!vctx)
  return 38;

 return vctx->get_srq_num(srq, srq_num);
}

int ibv_destroy_srq(struct ibv_srq *srq);
static inline int ibv_post_srq_recv(struct ibv_srq *srq,
        struct ibv_recv_wr *recv_wr,
        struct ibv_recv_wr **bad_recv_wr)
{
 return srq->context->ops.post_srq_recv(srq, recv_wr, bad_recv_wr);
}

struct ibv_qp *ibv_create_qp(struct ibv_pd *pd,
        struct ibv_qp_init_attr *qp_init_attr);

static inline struct ibv_qp *
ibv_create_qp_ex(struct ibv_context *context, struct ibv_qp_init_attr_ex *qp_init_attr_ex)
{
 struct verbs_context *vctx;
 uint32_t mask = qp_init_attr_ex->comp_mask;

 if (mask == IBV_QP_INIT_ATTR_PD)
  return ibv_create_qp(qp_init_attr_ex->pd,
         (struct ibv_qp_init_attr *) qp_init_attr_ex);

 vctx = ({ struct verbs_context *vctx = verbs_get_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context, create_qp_ex)) || !vctx->create_qp_ex) ? ((void *)0) : vctx; });
 if (!vctx) {
  (*__errno_location ()) = 38;
  return ((void *)0);
 }
 return vctx->create_qp_ex(context, qp_init_attr_ex);
}

static inline struct ibv_qp *
ibv_open_qp(struct ibv_context *context, struct ibv_qp_open_attr *qp_open_attr)
{
 struct verbs_context *vctx = ({ struct verbs_context *vctx = verbs_get_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context, open_qp)) || !vctx->open_qp) ? ((void *)0) : vctx; });
 if (!vctx) {
  (*__errno_location ()) = 38;
  return ((void *)0);
 }
 return vctx->open_qp(context, qp_open_attr);
}

int ibv_modify_qp(struct ibv_qp *qp, struct ibv_qp_attr *attr,
    int attr_mask);
int ibv_query_qp(struct ibv_qp *qp, struct ibv_qp_attr *attr,
   int attr_mask,
   struct ibv_qp_init_attr *init_attr);

int ibv_destroy_qp(struct ibv_qp *qp);

static inline int ibv_post_send(struct ibv_qp *qp, struct ibv_send_wr *wr,
    struct ibv_send_wr **bad_wr)
{
 return qp->context->ops.post_send(qp, wr, bad_wr);
}

static inline int ibv_post_recv(struct ibv_qp *qp, struct ibv_recv_wr *wr,
    struct ibv_recv_wr **bad_wr)
{
 return qp->context->ops.post_recv(qp, wr, bad_wr);
}

struct ibv_ah *ibv_create_ah(struct ibv_pd *pd, struct ibv_ah_attr *attr);
int ibv_init_ah_from_wc(struct ibv_context *context, uint8_t port_num,
   struct ibv_wc *wc, struct ibv_grh *grh,
   struct ibv_ah_attr *ah_attr);
struct ibv_ah *ibv_create_ah_from_wc(struct ibv_pd *pd, struct ibv_wc *wc,
         struct ibv_grh *grh, uint8_t port_num);

int ibv_destroy_ah(struct ibv_ah *ah);
int ibv_attach_mcast(struct ibv_qp *qp, const union ibv_gid *gid, uint16_t lid);

int ibv_detach_mcast(struct ibv_qp *qp, const union ibv_gid *gid, uint16_t lid);

int ibv_fork_init(void);

const char *ibv_node_type_str(enum ibv_node_type node_type);

const char *ibv_port_state_str(enum ibv_port_state port_state);

const char *ibv_event_type_str(enum ibv_event_type event);

struct _IO_FILE;

typedef struct _IO_FILE FILE;

typedef struct _IO_FILE __FILE;

typedef struct
{
  int __count;
  union
  {

    unsigned int __wch;

    char __wchb[4];
  } __value;
} __mbstate_t;
typedef struct
{
  __off_t __pos;
  __mbstate_t __state;
} _G_fpos_t;
typedef struct
{
  __off64_t __pos;
  __mbstate_t __state;
} _G_fpos64_t;
typedef __builtin_va_list __gnuc_va_list;
struct _IO_jump_t; struct _IO_FILE;
typedef void _IO_lock_t;

struct _IO_marker {
  struct _IO_marker *_next;
  struct _IO_FILE *_sbuf;

  int _pos;
};

enum __codecvt_result
{
  __codecvt_ok,
  __codecvt_partial,
  __codecvt_error,
  __codecvt_noconv
};
struct _IO_FILE {
  int _flags;

  char* _IO_read_ptr;
  char* _IO_read_end;
  char* _IO_read_base;
  char* _IO_write_base;
  char* _IO_write_ptr;
  char* _IO_write_end;
  char* _IO_buf_base;
  char* _IO_buf_end;

  char *_IO_save_base;
  char *_IO_backup_base;
  char *_IO_save_end;

  struct _IO_marker *_markers;

  struct _IO_FILE *_chain;

  int _fileno;

  int _flags2;

  __off_t _old_offset;

  unsigned short _cur_column;
  signed char _vtable_offset;
  char _shortbuf[1];

  _IO_lock_t *_lock;
  __off64_t _offset;
  void *__pad1;
  void *__pad2;
  void *__pad3;
  void *__pad4;
  size_t __pad5;

  int _mode;

  char _unused2[15 * sizeof (int) - 4 * sizeof (void *) - sizeof (size_t)];

};

typedef struct _IO_FILE _IO_FILE;

struct _IO_FILE_plus;

extern struct _IO_FILE_plus _IO_2_1_stdin_;
extern struct _IO_FILE_plus _IO_2_1_stdout_;
extern struct _IO_FILE_plus _IO_2_1_stderr_;
typedef __ssize_t __io_read_fn (void *__cookie, char *__buf, size_t __nbytes);

typedef __ssize_t __io_write_fn (void *__cookie, const char *__buf,
     size_t __n);

typedef int __io_seek_fn (void *__cookie, __off64_t *__pos, int __w);

typedef int __io_close_fn (void *__cookie);
extern int __underflow (_IO_FILE *);
extern int __uflow (_IO_FILE *);
extern int __overflow (_IO_FILE *, int);
extern int _IO_getc (_IO_FILE *__fp);
extern int _IO_putc (int __c, _IO_FILE *__fp);
extern int _IO_feof (_IO_FILE *__fp) __attribute__ ((__nothrow__ , __leaf__));
extern int _IO_ferror (_IO_FILE *__fp) __attribute__ ((__nothrow__ , __leaf__));

extern int _IO_peekc_locked (_IO_FILE *__fp);

extern void _IO_flockfile (_IO_FILE *) __attribute__ ((__nothrow__ , __leaf__));
extern void _IO_funlockfile (_IO_FILE *) __attribute__ ((__nothrow__ , __leaf__));
extern int _IO_ftrylockfile (_IO_FILE *) __attribute__ ((__nothrow__ , __leaf__));
extern int _IO_vfscanf (_IO_FILE * __restrict, const char * __restrict,
   __gnuc_va_list, int *__restrict);
extern int _IO_vfprintf (_IO_FILE *__restrict, const char *__restrict,
    __gnuc_va_list);
extern __ssize_t _IO_padn (_IO_FILE *, int, __ssize_t);
extern size_t _IO_sgetn (_IO_FILE *, void *, size_t);

extern __off64_t _IO_seekoff (_IO_FILE *, __off64_t, int, int);
extern __off64_t _IO_seekpos (_IO_FILE *, __off64_t, int);

extern void _IO_free_backup_area (_IO_FILE *) __attribute__ ((__nothrow__ , __leaf__));

typedef __gnuc_va_list va_list;
typedef __off_t off_t;
typedef __ssize_t ssize_t;

typedef _G_fpos_t fpos_t;

extern struct _IO_FILE *stdin;
extern struct _IO_FILE *stdout;
extern struct _IO_FILE *stderr;

extern int remove (const char *__filename) __attribute__ ((__nothrow__ , __leaf__));

extern int rename (const char *__old, const char *__new) __attribute__ ((__nothrow__ , __leaf__));

extern int renameat (int __oldfd, const char *__old, int __newfd,
       const char *__new) __attribute__ ((__nothrow__ , __leaf__));

extern FILE *tmpfile (void) ;
extern char *tmpnam (char *__s) __attribute__ ((__nothrow__ , __leaf__)) ;

extern char *tmpnam_r (char *__s) __attribute__ ((__nothrow__ , __leaf__)) ;
extern char *tempnam (const char *__dir, const char *__pfx)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__malloc__)) ;

extern int fclose (FILE *__stream);

extern int fflush (FILE *__stream);

extern int fflush_unlocked (FILE *__stream);

extern FILE *fopen (const char *__restrict __filename,
      const char *__restrict __modes) ;

extern FILE *freopen (const char *__restrict __filename,
        const char *__restrict __modes,
        FILE *__restrict __stream) ;

extern FILE *fdopen (int __fd, const char *__modes) __attribute__ ((__nothrow__ , __leaf__)) ;
extern FILE *fmemopen (void *__s, size_t __len, const char *__modes)
  __attribute__ ((__nothrow__ , __leaf__)) ;

extern FILE *open_memstream (char **__bufloc, size_t *__sizeloc) __attribute__ ((__nothrow__ , __leaf__)) ;

extern void setbuf (FILE *__restrict __stream, char *__restrict __buf) __attribute__ ((__nothrow__ , __leaf__));

extern int setvbuf (FILE *__restrict __stream, char *__restrict __buf,
      int __modes, size_t __n) __attribute__ ((__nothrow__ , __leaf__));

extern void setbuffer (FILE *__restrict __stream, char *__restrict __buf,
         size_t __size) __attribute__ ((__nothrow__ , __leaf__));

extern void setlinebuf (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__));

extern int fprintf (FILE *__restrict __stream,
      const char *__restrict __format, ...);

extern int printf (const char *__restrict __format, ...);

extern int sprintf (char *__restrict __s,
      const char *__restrict __format, ...) __attribute__ ((__nothrow__));

extern int vfprintf (FILE *__restrict __s, const char *__restrict __format,
       __gnuc_va_list __arg);

extern int vprintf (const char *__restrict __format, __gnuc_va_list __arg);

extern int vsprintf (char *__restrict __s, const char *__restrict __format,
       __gnuc_va_list __arg) __attribute__ ((__nothrow__));

extern int snprintf (char *__restrict __s, size_t __maxlen,
       const char *__restrict __format, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 3, 4)));

extern int vsnprintf (char *__restrict __s, size_t __maxlen,
        const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 3, 0)));

extern int vdprintf (int __fd, const char *__restrict __fmt,
       __gnuc_va_list __arg)
     __attribute__ ((__format__ (__printf__, 2, 0)));
extern int dprintf (int __fd, const char *__restrict __fmt, ...)
     __attribute__ ((__format__ (__printf__, 2, 3)));

extern int fscanf (FILE *__restrict __stream,
     const char *__restrict __format, ...) ;

extern int scanf (const char *__restrict __format, ...) ;

extern int sscanf (const char *__restrict __s,
     const char *__restrict __format, ...) __attribute__ ((__nothrow__ , __leaf__));
extern int fscanf (FILE *__restrict __stream, const char *__restrict __format, ...) __asm__ ("" "__isoc99_fscanf")

                               ;
extern int scanf (const char *__restrict __format, ...) __asm__ ("" "__isoc99_scanf")
                              ;
extern int sscanf (const char *__restrict __s, const char *__restrict __format, ...) __asm__ ("" "__isoc99_sscanf") __attribute__ ((__nothrow__ , __leaf__))

                      ;

extern int vfscanf (FILE *__restrict __s, const char *__restrict __format,
      __gnuc_va_list __arg)
     __attribute__ ((__format__ (__scanf__, 2, 0))) ;

extern int vscanf (const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__format__ (__scanf__, 1, 0))) ;

extern int vsscanf (const char *__restrict __s,
      const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__format__ (__scanf__, 2, 0)));
extern int vfscanf (FILE *__restrict __s, const char *__restrict __format, __gnuc_va_list __arg) __asm__ ("" "__isoc99_vfscanf")

     __attribute__ ((__format__ (__scanf__, 2, 0))) ;
extern int vscanf (const char *__restrict __format, __gnuc_va_list __arg) __asm__ ("" "__isoc99_vscanf")

     __attribute__ ((__format__ (__scanf__, 1, 0))) ;
extern int vsscanf (const char *__restrict __s, const char *__restrict __format, __gnuc_va_list __arg) __asm__ ("" "__isoc99_vsscanf") __attribute__ ((__nothrow__ , __leaf__))

     __attribute__ ((__format__ (__scanf__, 2, 0)));

extern int fgetc (FILE *__stream);
extern int getc (FILE *__stream);

extern int getchar (void);

extern int getc_unlocked (FILE *__stream);
extern int getchar_unlocked (void);
extern int fgetc_unlocked (FILE *__stream);

extern int fputc (int __c, FILE *__stream);
extern int putc (int __c, FILE *__stream);

extern int putchar (int __c);

extern int fputc_unlocked (int __c, FILE *__stream);

extern int putc_unlocked (int __c, FILE *__stream);
extern int putchar_unlocked (int __c);

extern int getw (FILE *__stream);

extern int putw (int __w, FILE *__stream);

extern char *fgets (char *__restrict __s, int __n, FILE *__restrict __stream)
     ;
extern char *gets (char *__s) __attribute__ ((__deprecated__));

extern __ssize_t __getdelim (char **__restrict __lineptr,
          size_t *__restrict __n, int __delimiter,
          FILE *__restrict __stream) ;
extern __ssize_t getdelim (char **__restrict __lineptr,
        size_t *__restrict __n, int __delimiter,
        FILE *__restrict __stream) ;

extern __ssize_t getline (char **__restrict __lineptr,
       size_t *__restrict __n,
       FILE *__restrict __stream) ;

extern int fputs (const char *__restrict __s, FILE *__restrict __stream);

extern int puts (const char *__s);

extern int ungetc (int __c, FILE *__stream);

extern size_t fread (void *__restrict __ptr, size_t __size,
       size_t __n, FILE *__restrict __stream) ;

extern size_t fwrite (const void *__restrict __ptr, size_t __size,
        size_t __n, FILE *__restrict __s);

extern size_t fread_unlocked (void *__restrict __ptr, size_t __size,
         size_t __n, FILE *__restrict __stream) ;
extern size_t fwrite_unlocked (const void *__restrict __ptr, size_t __size,
          size_t __n, FILE *__restrict __stream);

extern int fseek (FILE *__stream, long int __off, int __whence);

extern long int ftell (FILE *__stream) ;

extern void rewind (FILE *__stream);

extern int fseeko (FILE *__stream, __off_t __off, int __whence);

extern __off_t ftello (FILE *__stream) ;

extern int fgetpos (FILE *__restrict __stream, fpos_t *__restrict __pos);

extern int fsetpos (FILE *__stream, const fpos_t *__pos);

extern void clearerr (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__));

extern int feof (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;

extern int ferror (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;

extern void clearerr_unlocked (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__));
extern int feof_unlocked (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;
extern int ferror_unlocked (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;

extern void perror (const char *__s);

extern int sys_nerr;
extern const char *const sys_errlist[];

extern int fileno (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;

extern int fileno_unlocked (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;
extern FILE *popen (const char *__command, const char *__modes) ;

extern int pclose (FILE *__stream);

extern char *ctermid (char *__s) __attribute__ ((__nothrow__ , __leaf__));
extern void flockfile (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__));

extern int ftrylockfile (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;

extern void funlockfile (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__));

enum ibv_exp_func_name {
 IBV_EXP_POST_SEND_FUNC,
 IBV_EXP_POLL_CQ_FUNC,
 IBV_POST_SEND_FUNC,
 IBV_POLL_CQ_FUNC,
 IBV_POST_RECV_FUNC
};

enum ibv_exp_start_values {
 IBV_EXP_START_ENUM = 0x40,
 IBV_EXP_START_FLAG_LOC = 0x20,
 IBV_EXP_START_FLAG = (1ULL << IBV_EXP_START_FLAG_LOC),
};

enum ibv_exp_atomic_cap {
 IBV_EXP_ATOMIC_NONE = IBV_ATOMIC_NONE,
 IBV_EXP_ATOMIC_HCA = IBV_ATOMIC_HCA,
 IBV_EXP_ATOMIC_GLOB = IBV_ATOMIC_GLOB,

 IBV_EXP_ATOMIC_HCA_REPLY_BE = IBV_EXP_START_ENUM
};

enum ibv_exp_device_cap_flags {
 IBV_EXP_DEVICE_RESIZE_MAX_WR = IBV_DEVICE_RESIZE_MAX_WR,
 IBV_EXP_DEVICE_BAD_PKEY_CNTR = IBV_DEVICE_BAD_PKEY_CNTR,
 IBV_EXP_DEVICE_BAD_QKEY_CNTR = IBV_DEVICE_BAD_QKEY_CNTR,
 IBV_EXP_DEVICE_RAW_MULTI = IBV_DEVICE_RAW_MULTI,
 IBV_EXP_DEVICE_AUTO_PATH_MIG = IBV_DEVICE_AUTO_PATH_MIG,
 IBV_EXP_DEVICE_CHANGE_PHY_PORT = IBV_DEVICE_CHANGE_PHY_PORT,
 IBV_EXP_DEVICE_UD_AV_PORT_ENFORCE = IBV_DEVICE_UD_AV_PORT_ENFORCE,
 IBV_EXP_DEVICE_CURR_QP_STATE_MOD = IBV_DEVICE_CURR_QP_STATE_MOD,
 IBV_EXP_DEVICE_SHUTDOWN_PORT = IBV_DEVICE_SHUTDOWN_PORT,
 IBV_EXP_DEVICE_INIT_TYPE = IBV_DEVICE_INIT_TYPE,
 IBV_EXP_DEVICE_PORT_ACTIVE_EVENT = IBV_DEVICE_PORT_ACTIVE_EVENT,
 IBV_EXP_DEVICE_SYS_IMAGE_GUID = IBV_DEVICE_SYS_IMAGE_GUID,
 IBV_EXP_DEVICE_RC_RNR_NAK_GEN = IBV_DEVICE_RC_RNR_NAK_GEN,
 IBV_EXP_DEVICE_SRQ_RESIZE = IBV_DEVICE_SRQ_RESIZE,
 IBV_EXP_DEVICE_N_NOTIFY_CQ = IBV_DEVICE_N_NOTIFY_CQ,
 IBV_EXP_DEVICE_XRC = IBV_DEVICE_XRC,

 IBV_EXP_DEVICE_DC_TRANSPORT = (IBV_EXP_START_FLAG << 0),
 IBV_EXP_DEVICE_QPG = (IBV_EXP_START_FLAG << 1),
 IBV_EXP_DEVICE_UD_RSS = (IBV_EXP_START_FLAG << 2),
 IBV_EXP_DEVICE_UD_TSS = (IBV_EXP_START_FLAG << 3),
 IBV_EXP_DEVICE_MEM_WINDOW = (IBV_EXP_START_FLAG << 17),
 IBV_EXP_DEVICE_MEM_MGT_EXTENSIONS = (IBV_EXP_START_FLAG << 21),

 IBV_EXP_DEVICE_MW_TYPE_2A = (IBV_EXP_START_FLAG << 23),
 IBV_EXP_DEVICE_MW_TYPE_2B = (IBV_EXP_START_FLAG << 24),
 IBV_EXP_DEVICE_CROSS_CHANNEL = (IBV_EXP_START_FLAG << 28),
 IBV_EXP_DEVICE_MANAGED_FLOW_STEERING = (IBV_EXP_START_FLAG << 29),
 IBV_EXP_DEVICE_MR_ALLOCATE = (IBV_EXP_START_FLAG << 30),
 IBV_EXP_DEVICE_SHARED_MR = (IBV_EXP_START_FLAG << 31),
};

enum ibv_exp_device_attr_comp_mask {
 IBV_EXP_DEVICE_ATTR_CALC_CAP = (1 << 0),
 IBV_EXP_DEVICE_ATTR_WITH_TIMESTAMP_MASK = (1 << 1),
 IBV_EXP_DEVICE_ATTR_WITH_HCA_CORE_CLOCK = (1 << 2),
 IBV_EXP_DEVICE_ATTR_EXP_CAP_FLAGS = (1 << 3),
 IBV_EXP_DEVICE_DC_RD_REQ = (1 << 4),
 IBV_EXP_DEVICE_DC_RD_RES = (1 << 5),
 IBV_EXP_DEVICE_ATTR_INLINE_RECV_SZ = (1 << 6),
 IBV_EXP_DEVICE_ATTR_RSS_TBL_SZ = (1 << 7),

 IBV_EXP_DEVICE_ATTR_RESERVED = (1 << 8)
};

struct ibv_exp_device_calc_cap {
 uint64_t data_types;
 uint64_t data_sizes;
 uint64_t int_ops;
 uint64_t uint_ops;
 uint64_t fp_ops;
};

struct ibv_exp_device_attr {
 char fw_ver[64];
 uint64_t node_guid;
 uint64_t sys_image_guid;
 uint64_t max_mr_size;
 uint64_t page_size_cap;
 uint32_t vendor_id;
 uint32_t vendor_part_id;
 uint32_t hw_ver;
 int max_qp;
 int max_qp_wr;
 int reserved;
 int max_sge;
 int max_sge_rd;
 int max_cq;
 int max_cqe;
 int max_mr;
 int max_pd;
 int max_qp_rd_atom;
 int max_ee_rd_atom;
 int max_res_rd_atom;
 int max_qp_init_rd_atom;
 int max_ee_init_rd_atom;
 enum ibv_exp_atomic_cap exp_atomic_cap;
 int max_ee;
 int max_rdd;
 int max_mw;
 int max_raw_ipv6_qp;
 int max_raw_ethy_qp;
 int max_mcast_grp;
 int max_mcast_qp_attach;
 int max_total_mcast_qp_attach;
 int max_ah;
 int max_fmr;
 int max_map_per_fmr;
 int max_srq;
 int max_srq_wr;
 int max_srq_sge;
 uint16_t max_pkeys;
 uint8_t local_ca_ack_delay;
 uint8_t phys_port_cnt;
 uint32_t comp_mask;
 struct ibv_exp_device_calc_cap calc_cap;
 uint64_t timestamp_mask;
 uint64_t hca_core_clock;
 uint64_t exp_device_cap_flags;
 int max_dc_req_rd_atom;
 int max_dc_res_rd_atom;
 int inline_recv_sz;
 uint32_t max_rss_tbl_sz;
};

enum ibv_exp_access_flags {
 IBV_EXP_ACCESS_LOCAL_WRITE = IBV_ACCESS_LOCAL_WRITE,
 IBV_EXP_ACCESS_REMOTE_WRITE = IBV_ACCESS_REMOTE_WRITE,
 IBV_EXP_ACCESS_REMOTE_READ = IBV_ACCESS_REMOTE_READ,
 IBV_EXP_ACCESS_REMOTE_ATOMIC = IBV_ACCESS_REMOTE_ATOMIC,
 IBV_EXP_ACCESS_MW_BIND = IBV_ACCESS_MW_BIND,

 IBV_EXP_ACCESS_ALLOCATE_MR = (IBV_EXP_START_FLAG << 5),
 IBV_EXP_ACCESS_SHARED_MR_USER_READ = (IBV_EXP_START_FLAG << 6),
 IBV_EXP_ACCESS_SHARED_MR_USER_WRITE = (IBV_EXP_START_FLAG << 7),
 IBV_EXP_ACCESS_SHARED_MR_GROUP_READ = (IBV_EXP_START_FLAG << 8),
 IBV_EXP_ACCESS_SHARED_MR_GROUP_WRITE = (IBV_EXP_START_FLAG << 9),
 IBV_EXP_ACCESS_SHARED_MR_OTHER_READ = (IBV_EXP_START_FLAG << 10),
 IBV_EXP_ACCESS_SHARED_MR_OTHER_WRITE = (IBV_EXP_START_FLAG << 11),
 IBV_EXP_ACCESS_NO_RDMA = (IBV_EXP_START_FLAG << 12),
 IBV_EXP_ACCESS_MW_ZERO_BASED = (IBV_EXP_START_FLAG << 13),

 IBV_EXP_ACCESS_RESERVED = (IBV_EXP_START_FLAG << 14)
};

struct ibv_exp_mw_bind_info {
 struct ibv_mr *mr;
 uint64_t addr;
 uint64_t length;
 uint64_t exp_mw_access_flags;
};

enum ibv_exp_bind_mw_comp_mask {
 IBV_EXP_BIND_MW_RESERVED = (1 << 0)
};

struct ibv_exp_mw_bind {
 struct ibv_qp *qp;
 struct ibv_mw *mw;
 uint64_t wr_id;
 uint64_t exp_send_flags;
 struct ibv_exp_mw_bind_info bind_info;
 uint32_t comp_mask;
};

enum ibv_exp_calc_op {
 IBV_EXP_CALC_OP_ADD = 0,
 IBV_EXP_CALC_OP_MAXLOC,
 IBV_EXP_CALC_OP_BAND,
 IBV_EXP_CALC_OP_BXOR,
 IBV_EXP_CALC_OP_BOR,
 IBV_EXP_CALC_OP_NUMBER
};

enum ibv_exp_calc_data_type {
 IBV_EXP_CALC_DATA_TYPE_INT = 0,
 IBV_EXP_CALC_DATA_TYPE_UINT,
 IBV_EXP_CALC_DATA_TYPE_FLOAT,
 IBV_EXP_CALC_DATA_TYPE_NUMBER
};

enum ibv_exp_calc_data_size {
 IBV_EXP_CALC_DATA_SIZE_64_BIT = 0,
 IBV_EXP_CALC_DATA_SIZE_NUMBER
};

enum ibv_exp_wr_opcode {
 IBV_EXP_WR_RDMA_WRITE = IBV_WR_RDMA_WRITE,
 IBV_EXP_WR_RDMA_WRITE_WITH_IMM = IBV_WR_RDMA_WRITE_WITH_IMM,
 IBV_EXP_WR_SEND = IBV_WR_SEND,
 IBV_EXP_WR_SEND_WITH_IMM = IBV_WR_SEND_WITH_IMM,
 IBV_EXP_WR_RDMA_READ = IBV_WR_RDMA_READ,
 IBV_EXP_WR_ATOMIC_CMP_AND_SWP = IBV_WR_ATOMIC_CMP_AND_SWP,
 IBV_EXP_WR_ATOMIC_FETCH_AND_ADD = IBV_WR_ATOMIC_FETCH_AND_ADD,

 IBV_EXP_WR_SEND_WITH_INV = 8 + IBV_EXP_START_ENUM,
 IBV_EXP_WR_LOCAL_INV = 10 + IBV_EXP_START_ENUM,
 IBV_EXP_WR_BIND_MW = 14 + IBV_EXP_START_ENUM,
 IBV_EXP_WR_SEND_ENABLE = 0x20 + IBV_EXP_START_ENUM,
 IBV_EXP_WR_RECV_ENABLE,
 IBV_EXP_WR_CQE_WAIT
};

enum ibv_exp_send_flags {
 IBV_EXP_SEND_FENCE = IBV_SEND_FENCE,
 IBV_EXP_SEND_SIGNALED = IBV_SEND_SIGNALED,
 IBV_EXP_SEND_SOLICITED = IBV_SEND_SOLICITED,
 IBV_EXP_SEND_INLINE = IBV_SEND_INLINE,

 IBV_EXP_SEND_IP_CSUM = (IBV_EXP_START_FLAG << 0),
 IBV_EXP_SEND_WITH_CALC = (IBV_EXP_START_FLAG << 1),
 IBV_EXP_SEND_WAIT_EN_LAST = (IBV_EXP_START_FLAG << 2)
};

enum ibv_exp_send_wr_comp_mask {
 IBV_EXP_SEND_WR_ATTR_RESERVED = 1 << 0
};

struct ibv_exp_send_wr {
 uint64_t wr_id;
 struct ibv_exp_send_wr *next;
 struct ibv_sge *sg_list;
 int num_sge;
 enum ibv_exp_wr_opcode exp_opcode;
 int reserved;
 union {
  uint32_t imm_data;
  uint32_t invalidate_rkey;
 } ex;
 union {
  struct {
   uint64_t remote_addr;
   uint32_t rkey;
  } rdma;
  struct {
   uint64_t remote_addr;
   uint64_t compare_add;
   uint64_t swap;
   uint32_t rkey;
  } atomic;
  struct {
   struct ibv_ah *ah;
   uint32_t remote_qpn;
   uint32_t remote_qkey;
  } ud;
 } wr;
 union {
  union {
   struct {
    uint32_t remote_srqn;
   } xrc;
  } qp_type;

  uint32_t xrc_remote_srq_num;
 };
 union {
  struct {
   uint64_t remote_addr;
   uint32_t rkey;
  } rdma;
  struct {
   uint64_t remote_addr;
   uint64_t compare_add;
   uint64_t swap;
   uint32_t rkey;
  } atomic;
  struct {
   struct ibv_cq *cq;
   int32_t cq_count;
  } cqe_wait;
  struct {
   struct ibv_qp *qp;
   int32_t wqe_count;
  } wqe_enable;
 } task;
 union {
  struct {
   enum ibv_exp_calc_op calc_op;
   enum ibv_exp_calc_data_type data_type;
   enum ibv_exp_calc_data_size data_size;
  } calc;
 } op;
 struct {
  struct ibv_ah *ah;
  uint64_t dct_access_key;
  uint32_t dct_number;
 } dc;
 struct {
  struct ibv_mw *mw;
  uint32_t rkey;
  struct ibv_exp_mw_bind_info bind_info;
 } bind_mw;
 uint64_t exp_send_flags;
 uint32_t comp_mask;
};

enum ibv_exp_values_comp_mask {
  IBV_EXP_VALUES_HW_CLOCK_NS = 1 << 0,
  IBV_EXP_VALUES_HW_CLOCK = 1 << 1,
  IBV_EXP_VALUES_RESERVED = 1 << 2
};

struct ibv_exp_values {
 uint32_t comp_mask;
 uint64_t hwclock_ns;
 uint64_t hwclock;
};

enum ibv_exp_cq_create_flags {
 IBV_EXP_CQ_CREATE_CROSS_CHANNEL = 1 << 0,
 IBV_EXP_CQ_TIMESTAMP = 1 << 1,
 IBV_EXP_CQ_TIMESTAMP_TO_SYS_TIME = 1 << 2,

};

enum {
 IBV_EXP_CQ_CREATE_FLAGS_MASK = IBV_EXP_CQ_CREATE_CROSS_CHANNEL |
       IBV_EXP_CQ_TIMESTAMP |
       IBV_EXP_CQ_TIMESTAMP_TO_SYS_TIME,
};

enum ibv_exp_cq_init_attr_mask {
 IBV_EXP_CQ_INIT_ATTR_FLAGS = 1 << 0,
 IBV_EXP_CQ_INIT_ATTR_RESERVED = 1 << 1,
};

struct ibv_exp_cq_init_attr {
 uint32_t comp_mask;
 uint32_t flags;

};

enum ibv_exp_ah_attr_attr_comp_mask {
 IBV_EXP_AH_ATTR_LL = 1 << 0,
 IBV_EXP_AH_ATTR_VID = 1 << 1,
 IBV_EXP_AH_ATTR_RESERVED = 1 << 2
};

enum ll_address_type {
 LL_ADDRESS_UNKNOWN,
 LL_ADDRESS_IB,
 LL_ADDRESS_ETH,
 LL_ADDRESS_SIZE
};

struct ibv_exp_ah_attr {
 struct ibv_global_route grh;
 uint16_t dlid;
 uint8_t sl;
 uint8_t src_path_bits;
 uint8_t static_rate;
 uint8_t is_global;
 uint8_t port_num;
 uint32_t comp_mask;
 struct {
  enum ll_address_type type;
  uint32_t len;
  char *address;
 } ll_address;
 uint16_t vid;
};

enum ibv_exp_qp_attr_mask {
 IBV_EXP_QP_STATE = IBV_QP_STATE,
 IBV_EXP_QP_CUR_STATE = IBV_QP_CUR_STATE,
 IBV_EXP_QP_EN_SQD_ASYNC_NOTIFY = IBV_QP_EN_SQD_ASYNC_NOTIFY,
 IBV_EXP_QP_ACCESS_FLAGS = IBV_QP_ACCESS_FLAGS,
 IBV_EXP_QP_PKEY_INDEX = IBV_QP_PKEY_INDEX,
 IBV_EXP_QP_PORT = IBV_QP_PORT,
 IBV_EXP_QP_QKEY = IBV_QP_QKEY,
 IBV_EXP_QP_AV = IBV_QP_AV,
 IBV_EXP_QP_PATH_MTU = IBV_QP_PATH_MTU,
 IBV_EXP_QP_TIMEOUT = IBV_QP_TIMEOUT,
 IBV_EXP_QP_RETRY_CNT = IBV_QP_RETRY_CNT,
 IBV_EXP_QP_RNR_RETRY = IBV_QP_RNR_RETRY,
 IBV_EXP_QP_RQ_PSN = IBV_QP_RQ_PSN,
 IBV_EXP_QP_MAX_QP_RD_ATOMIC = IBV_QP_MAX_QP_RD_ATOMIC,
 IBV_EXP_QP_ALT_PATH = IBV_QP_ALT_PATH,
 IBV_EXP_QP_MIN_RNR_TIMER = IBV_QP_MIN_RNR_TIMER,
 IBV_EXP_QP_SQ_PSN = IBV_QP_SQ_PSN,
 IBV_EXP_QP_MAX_DEST_RD_ATOMIC = IBV_QP_MAX_DEST_RD_ATOMIC,
 IBV_EXP_QP_PATH_MIG_STATE = IBV_QP_PATH_MIG_STATE,
 IBV_EXP_QP_CAP = IBV_QP_CAP,
 IBV_EXP_QP_DEST_QPN = IBV_QP_DEST_QPN,

 IBV_EXP_QP_GROUP_RSS = IBV_EXP_START_FLAG << 21,
 IBV_EXP_QP_DC_KEY = IBV_EXP_START_FLAG << 22,
};

enum ibv_exp_qp_attr_comp_mask {
 IBV_EXP_QP_ATTR_RESERVED = 1 << 0
};

struct ibv_exp_qp_attr {
 enum ibv_qp_state qp_state;
 enum ibv_qp_state cur_qp_state;
 enum ibv_mtu path_mtu;
 enum ibv_mig_state path_mig_state;
 uint32_t qkey;
 uint32_t rq_psn;
 uint32_t sq_psn;
 uint32_t dest_qp_num;
 int qp_access_flags;
 struct ibv_qp_cap cap;
 struct ibv_ah_attr ah_attr;
 struct ibv_ah_attr alt_ah_attr;
 uint16_t pkey_index;
 uint16_t alt_pkey_index;
 uint8_t en_sqd_async_notify;
 uint8_t sq_draining;
 uint8_t max_rd_atomic;
 uint8_t max_dest_rd_atomic;
 uint8_t min_rnr_timer;
 uint8_t port_num;
 uint8_t timeout;
 uint8_t retry_cnt;
 uint8_t rnr_retry;
 uint8_t alt_port_num;
 uint8_t alt_timeout;
 uint64_t dct_key;
 uint32_t comp_mask;
};

enum ibv_exp_qp_init_attr_comp_mask {
 IBV_EXP_QP_INIT_ATTR_PD = 1 << 0,
 IBV_EXP_QP_INIT_ATTR_XRCD = 1 << 1,
 IBV_EXP_QP_INIT_ATTR_CREATE_FLAGS = 1 << 2,
 IBV_EXP_QP_INIT_ATTR_INL_RECV = 1 << 3,
 IBV_EXP_QP_INIT_ATTR_QPG = 1 << 4,
 IBV_EXP_QP_INIT_ATTR_RESERVED = 1 << 5
};

enum ibv_exp_qpg_type {
 IBV_EXP_QPG_NONE = 0,
 IBV_EXP_QPG_PARENT = (1<<0),
 IBV_EXP_QPG_CHILD_RX = (1<<1),
 IBV_EXP_QPG_CHILD_TX = (1<<2)
};

struct ibv_exp_qpg_init_attrib {
 uint32_t tss_child_count;
 uint32_t rss_child_count;
};

struct ibv_exp_qpg {
 uint32_t qpg_type;
 union {
  struct ibv_qp *qpg_parent;
  struct ibv_exp_qpg_init_attrib parent_attrib;
 };
};

enum ibv_exp_qp_create_flags {
 IBV_EXP_QP_CREATE_CROSS_CHANNEL = (1 << 2),
 IBV_EXP_QP_CREATE_MANAGED_SEND = (1 << 3),
 IBV_EXP_QP_CREATE_MANAGED_RECV = (1 << 4),
 IBV_EXP_QP_CREATE_IGNORE_SQ_OVERFLOW = (1 << 6),
 IBV_EXP_QP_CREATE_IGNORE_RQ_OVERFLOW = (1 << 7),
 IBV_EXP_QP_CREATE_ATOMIC_BE_REPLY = (1 << 8),

 IBV_EXP_QP_CREATE_MASK = (0x000001DC)
};

struct ibv_exp_qp_init_attr {
 void *qp_context;
 struct ibv_cq *send_cq;
 struct ibv_cq *recv_cq;
 struct ibv_srq *srq;
 struct ibv_qp_cap cap;
 enum ibv_qp_type qp_type;
 int sq_sig_all;

 uint32_t comp_mask;
 struct ibv_pd *pd;
 struct ibv_xrcd *xrcd;
 uint32_t exp_create_flags;

 uint32_t max_inl_recv;
 struct ibv_exp_qpg qpg;
};

enum ibv_exp_dct_init_attr_comp_mask {
 IBV_EXP_DCT_INIT_ATTR_RESERVED = 1 << 0
};

enum {
 IBV_EXP_DCT_CREATE_FLAGS_MASK = (1 << 0) - 1,
};

struct ibv_exp_dct_init_attr {
 struct ibv_pd *pd;
 struct ibv_cq *cq;
 struct ibv_srq *srq;
 uint64_t dc_key;
 uint8_t port;
 uint32_t access_flags;
 uint8_t min_rnr_timer;
 uint8_t tclass;
 uint32_t flow_label;
 enum ibv_mtu mtu;
 uint8_t pkey_index;
 uint8_t gid_index;
 uint8_t hop_limit;
 uint32_t inline_size;
 uint32_t create_flags;
 uint32_t comp_mask;
};

enum {
 IBV_EXP_DCT_STATE_ACTIVE = 0,
 IBV_EXP_DCT_STATE_DRAINING = 1,
 IBV_EXP_DCT_STATE_DRAINED = 2
};

enum ibv_exp_dct_attr_comp_mask {
 IBV_EXP_DCT_ATTR_RESERVED = 1 << 0
};

struct ibv_exp_dct_attr {
 uint64_t dc_key;
 uint8_t port;
 uint32_t access_flags;
 uint8_t min_rnr_timer;
 uint8_t tclass;
 uint32_t flow_label;
 enum ibv_mtu mtu;
 uint8_t pkey_index;
 uint8_t gid_index;
 uint8_t hop_limit;
 uint32_t key_violations;
 uint8_t state;
 struct ibv_srq *srq;
 struct ibv_cq *cq;
 struct ibv_pd *pd;
 uint32_t comp_mask;
};

enum {
 IBV_EXP_QUERY_PORT_STATE = 1 << 0,
 IBV_EXP_QUERY_PORT_MAX_MTU = 1 << 1,
 IBV_EXP_QUERY_PORT_ACTIVE_MTU = 1 << 2,
 IBV_EXP_QUERY_PORT_GID_TBL_LEN = 1 << 3,
 IBV_EXP_QUERY_PORT_CAP_FLAGS = 1 << 4,
 IBV_EXP_QUERY_PORT_MAX_MSG_SZ = 1 << 5,
 IBV_EXP_QUERY_PORT_BAD_PKEY_CNTR = 1 << 6,
 IBV_EXP_QUERY_PORT_QKEY_VIOL_CNTR = 1 << 7,
 IBV_EXP_QUERY_PORT_PKEY_TBL_LEN = 1 << 8,
 IBV_EXP_QUERY_PORT_LID = 1 << 9,
 IBV_EXP_QUERY_PORT_SM_LID = 1 << 10,
 IBV_EXP_QUERY_PORT_LMC = 1 << 11,
 IBV_EXP_QUERY_PORT_MAX_VL_NUM = 1 << 12,
 IBV_EXP_QUERY_PORT_SM_SL = 1 << 13,
 IBV_EXP_QUERY_PORT_SUBNET_TIMEOUT = 1 << 14,
 IBV_EXP_QUERY_PORT_INIT_TYPE_REPLY = 1 << 15,
 IBV_EXP_QUERY_PORT_ACTIVE_WIDTH = 1 << 16,
 IBV_EXP_QUERY_PORT_ACTIVE_SPEED = 1 << 17,
 IBV_EXP_QUERY_PORT_PHYS_STATE = 1 << 18,
 IBV_EXP_QUERY_PORT_LINK_LAYER = 1 << 19,

 IBV_EXP_QUERY_PORT_STD_MASK = (1 << 20) - 1,

 IBV_EXP_QUERY_PORT_MASK = IBV_EXP_QUERY_PORT_STD_MASK,
};

enum ibv_exp_query_port_attr_comp_mask {
 IBV_EXP_QUERY_PORT_ATTR_MASK1 = 1 << 0,
 IBV_EXP_QUERY_PORT_ATTR_RESERVED = 1 << 1,

 IBV_EXP_QUERY_PORT_ATTR_MASKS = IBV_EXP_QUERY_PORT_ATTR_RESERVED - 1
};

struct ibv_exp_port_attr {
 union {
  struct {
   enum ibv_port_state state;
   enum ibv_mtu max_mtu;
   enum ibv_mtu active_mtu;
   int gid_tbl_len;
   uint32_t port_cap_flags;
   uint32_t max_msg_sz;
   uint32_t bad_pkey_cntr;
   uint32_t qkey_viol_cntr;
   uint16_t pkey_tbl_len;
   uint16_t lid;
   uint16_t sm_lid;
   uint8_t lmc;
   uint8_t max_vl_num;
   uint8_t sm_sl;
   uint8_t subnet_timeout;
   uint8_t init_type_reply;
   uint8_t active_width;
   uint8_t active_speed;
   uint8_t phys_state;
   uint8_t link_layer;
   uint8_t reserved;
  };
  struct ibv_port_attr port_attr;
 };
 uint32_t comp_mask;
 uint32_t mask1;
};

enum ibv_exp_cq_attr_mask {
 IBV_EXP_CQ_MODERATION = 1 << 0,
 IBV_EXP_CQ_CAP_FLAGS = 1 << 1
};

enum ibv_exp_cq_cap_flags {
 IBV_EXP_CQ_IGNORE_OVERRUN = (1 << 0),

 IBV_EXP_CQ_CAP_MASK = (0x00000001)
};

enum ibv_exp_cq_attr_comp_mask {
 IBV_EXP_CQ_ATTR_MODERATION = (1 << 0),
 IBV_EXP_CQ_ATTR_CQ_CAP_FLAGS = (1 << 1),

 IBV_EXP_CQ_ATTR_RESERVED = (1 << 2)
};

struct ibv_exp_cq_attr {
 uint32_t comp_mask;
 struct {
  uint16_t cq_count;
  uint16_t cq_period;
 } moderation;
 uint32_t cq_cap_flags;
};

enum ibv_exp_reg_shared_mr_comp_mask {
 IBV_EXP_REG_SHARED_MR_RESERVED = (1 << 0)
};

struct ibv_exp_reg_shared_mr_in {
 uint32_t mr_handle;
 struct ibv_pd *pd;
 void *addr;
 uint64_t exp_access;
 uint32_t comp_mask;
};

enum ibv_exp_flow_flags {
 IBV_EXP_FLOW_ATTR_FLAGS_ALLOW_LOOP_BACK = 1,
};

enum ibv_exp_flow_attr_type {

 IBV_EXP_FLOW_ATTR_NORMAL = 0x0,

 IBV_EXP_FLOW_ATTR_ALL_DEFAULT = 0x1,

 IBV_EXP_FLOW_ATTR_MC_DEFAULT = 0x2,

 IBV_EXP_FLOW_ATTR_SNIFFER = 0x3,
};

enum ibv_exp_flow_spec_type {
 IBV_EXP_FLOW_SPEC_ETH = 0x20,
 IBV_EXP_FLOW_SPEC_IB = 0x21,
 IBV_EXP_FLOW_SPEC_IPV4 = 0x30,
 IBV_EXP_FLOW_SPEC_TCP = 0x40,
 IBV_EXP_FLOW_SPEC_UDP = 0x41,
};

struct ibv_exp_flow_eth_filter {
 uint8_t dst_mac[6];
 uint8_t src_mac[6];
 uint16_t ether_type;

 uint16_t vlan_tag;
};

struct ibv_exp_flow_spec_eth {
 enum ibv_exp_flow_spec_type type;
 uint16_t size;
 struct ibv_exp_flow_eth_filter val;
 struct ibv_exp_flow_eth_filter mask;
};

struct ibv_exp_flow_ib_filter {
 uint32_t qpn;
 uint8_t dst_gid[16];
};

struct ibv_exp_flow_spec_ib {
 enum ibv_exp_flow_spec_type type;
 uint16_t size;
 struct ibv_exp_flow_ib_filter val;
 struct ibv_exp_flow_ib_filter mask;
};

struct ibv_exp_flow_ipv4_filter {
 uint32_t src_ip;
 uint32_t dst_ip;
};

struct ibv_exp_flow_spec_ipv4 {
 enum ibv_exp_flow_spec_type type;
 uint16_t size;
 struct ibv_exp_flow_ipv4_filter val;
 struct ibv_exp_flow_ipv4_filter mask;
};

struct ibv_exp_flow_tcp_udp_filter {
 uint16_t dst_port;
 uint16_t src_port;
};

struct ibv_exp_flow_spec_tcp_udp {
 enum ibv_exp_flow_spec_type type;
 uint16_t size;
 struct ibv_exp_flow_tcp_udp_filter val;
 struct ibv_exp_flow_tcp_udp_filter mask;
};

struct ibv_exp_flow_spec {
 union {
  struct {
   enum ibv_exp_flow_spec_type type;
   uint16_t size;
  } hdr;
  struct ibv_exp_flow_spec_ib ib;
  struct ibv_exp_flow_spec_eth eth;
  struct ibv_exp_flow_spec_ipv4 ipv4;
  struct ibv_exp_flow_spec_tcp_udp tcp_udp;
 };
};

struct ibv_exp_flow_attr {
 enum ibv_exp_flow_attr_type type;
 uint16_t size;
 uint16_t priority;
 uint8_t num_of_specs;
 uint8_t port;
 uint32_t flags;

 uint64_t reserved;
};

struct ibv_exp_flow {
 struct ibv_context *context;
 uint32_t handle;
};

struct ibv_exp_dct {
 struct ibv_context *context;
 uint32_t handle;
 uint32_t dct_num;
 struct ibv_pd *pd;
 struct ibv_srq *srq;
 struct ibv_cq *cq;
};

enum ibv_exp_wc_opcode {
 IBV_EXP_WC_SEND,
 IBV_EXP_WC_RDMA_WRITE,
 IBV_EXP_WC_RDMA_READ,
 IBV_EXP_WC_COMP_SWAP,
 IBV_EXP_WC_FETCH_ADD,
 IBV_EXP_WC_BIND_MW,
 IBV_EXP_WC_LOCAL_INV = 7,

 IBV_EXP_WC_RECV = 1 << 7,
 IBV_EXP_WC_RECV_RDMA_WITH_IMM
};

enum ibv_exp_wc_flags {
 IBV_EXP_WC_GRH = IBV_WC_GRH,
 IBV_EXP_WC_WITH_IMM = IBV_WC_WITH_IMM,

 IBV_EXP_WC_WITH_INV = IBV_EXP_START_FLAG << 2,
 IBV_EXP_WC_WITH_SL = IBV_EXP_START_FLAG << 4,
 IBV_EXP_WC_WITH_SLID = IBV_EXP_START_FLAG << 5,
 IBV_EXP_WC_WITH_TIMESTAMP = IBV_EXP_START_FLAG << 6,
 IBV_EXP_WC_QP = IBV_EXP_START_FLAG << 7,
 IBV_EXP_WC_SRQ = IBV_EXP_START_FLAG << 8,
 IBV_EXP_WC_DCT = IBV_EXP_START_FLAG << 9,
};

struct ibv_exp_wc {
 uint64_t wr_id;
 enum ibv_wc_status status;
 enum ibv_exp_wc_opcode exp_opcode;
 uint32_t vendor_err;
 uint32_t byte_len;
 uint32_t imm_data;
 uint32_t qp_num;
 uint32_t src_qp;
 int reserved;
 uint16_t pkey_index;
 uint16_t slid;
 uint8_t sl;
 uint8_t dlid_path_bits;
 uint64_t timestamp;
 struct ibv_qp *qp;
 struct ibv_srq *srq;
 struct ibv_exp_dct *dct;
 uint64_t exp_wc_flags;
};

enum ibv_exp_reg_mr_in_comp_mask {

 IBV_EXP_REG_MR_RESERVED = (1 << 0)
};
struct ibv_exp_reg_mr_in {
 struct ibv_pd *pd;
 void *addr;
 size_t length;
 uint64_t exp_access;
 uint32_t comp_mask;
};

enum ibv_exp_task_type {
 IBV_EXP_TASK_SEND = 0,
 IBV_EXP_TASK_RECV = 1
};

enum ibv_exp_task_comp_mask {
 IBV_EXP_TASK_RESERVED = (1 << 0)
};

struct ibv_exp_task {
 enum ibv_exp_task_type task_type;
 struct {
  struct ibv_qp *qp;
  union {
   struct ibv_exp_send_wr *send_wr;
   struct ibv_recv_wr *recv_wr;
  };
 } item;
 struct ibv_exp_task *next;
 uint32_t comp_mask;
};

enum ibv_exp_arm_attr_comp_mask {
 IBV_EXP_ARM_ATTR_RESERVED = (1 << 0)
};
struct ibv_exp_arm_attr {
 uint32_t comp_mask;
};

struct verbs_context_exp {

 int (*drv_exp_arm_dct)(struct ibv_exp_dct *dct, struct ibv_exp_arm_attr *attr);
 int (*lib_exp_arm_dct)(struct ibv_exp_dct *dct, struct ibv_exp_arm_attr *attr);
 int (*drv_exp_bind_mw)(struct ibv_exp_mw_bind *mw_bind);
 int (*lib_exp_bind_mw)(struct ibv_exp_mw_bind *mw_bind);
 int (*drv_exp_post_send)(struct ibv_qp *qp,
     struct ibv_exp_send_wr *wr,
     struct ibv_exp_send_wr **bad_wr);
 struct ibv_mr * (*drv_exp_reg_mr)(struct ibv_exp_reg_mr_in *in);
 struct ibv_mr * (*lib_exp_reg_mr)(struct ibv_exp_reg_mr_in *in);
 struct ibv_ah * (*drv_exp_ibv_create_ah)(struct ibv_pd *pd,
       struct ibv_exp_ah_attr *attr_exp);
 int (*drv_exp_query_values)(struct ibv_context *context, int q_values,
        struct ibv_exp_values *values);
 struct ibv_cq * (*exp_create_cq)(struct ibv_context *context, int cqe,
      struct ibv_comp_channel *channel,
      int comp_vector, struct ibv_exp_cq_init_attr *attr);
 int (*drv_exp_ibv_poll_cq)(struct ibv_cq *ibcq, int num_entries,
       struct ibv_exp_wc *wc, uint32_t wc_size);
 void * (*drv_exp_get_legacy_xrc) (struct ibv_srq *ibv_srq);
 void (*drv_exp_set_legacy_xrc) (struct ibv_srq *ibv_srq, void *legacy_xrc);
 struct ibv_mr * (*drv_exp_ibv_reg_shared_mr)(struct ibv_exp_reg_shared_mr_in *in);
 struct ibv_mr * (*lib_exp_ibv_reg_shared_mr)(struct ibv_exp_reg_shared_mr_in *in);
 int (*drv_exp_modify_qp)(struct ibv_qp *qp, struct ibv_exp_qp_attr *attr,
     uint64_t exp_attr_mask);
 int (*lib_exp_modify_qp)(struct ibv_qp *qp, struct ibv_exp_qp_attr *attr,
     uint64_t exp_attr_mask);
 int (*drv_exp_post_task)(struct ibv_context *context,
     struct ibv_exp_task *task,
     struct ibv_exp_task **bad_task);
 int (*lib_exp_post_task)(struct ibv_context *context,
     struct ibv_exp_task *task,
     struct ibv_exp_task **bad_task);
 int (*drv_exp_modify_cq)(struct ibv_cq *cq,
     struct ibv_exp_cq_attr *attr, int attr_mask);
 int (*lib_exp_modify_cq)(struct ibv_cq *cq,
     struct ibv_exp_cq_attr *attr, int attr_mask);
 int (*drv_exp_ibv_destroy_flow) (struct ibv_exp_flow *flow);
 int (*lib_exp_ibv_destroy_flow) (struct ibv_exp_flow *flow);
 struct ibv_exp_flow * (*drv_exp_ibv_create_flow) (struct ibv_qp *qp,
            struct ibv_exp_flow_attr
            *flow_attr);
 struct ibv_exp_flow * (*lib_exp_ibv_create_flow) (struct ibv_qp *qp,
         struct ibv_exp_flow_attr
         *flow_attr);

 int (*drv_exp_query_port)(struct ibv_context *context, uint8_t port_num,
      struct ibv_exp_port_attr *port_attr);
 int (*lib_exp_query_port)(struct ibv_context *context, uint8_t port_num,
      struct ibv_exp_port_attr *port_attr);
 struct ibv_exp_dct *(*create_dct)(struct ibv_context *context,
       struct ibv_exp_dct_init_attr *attr);
 int (*destroy_dct)(struct ibv_exp_dct *dct);
 int (*query_dct)(struct ibv_exp_dct *dct, struct ibv_exp_dct_attr *attr);
 int (*drv_exp_query_device)(struct ibv_context *context,
        struct ibv_exp_device_attr *attr);
 int (*lib_exp_query_device)(struct ibv_context *context,
        struct ibv_exp_device_attr *attr);
 struct ibv_qp *(*drv_exp_create_qp)(struct ibv_context *context,
         struct ibv_exp_qp_init_attr *init_attr);
 struct ibv_qp *(*lib_exp_create_qp)(struct ibv_context *context,
         struct ibv_exp_qp_init_attr *init_attr);
 size_t sz;

};

static inline struct verbs_context_exp *verbs_get_exp_ctx(struct ibv_context *ctx)
{
 size_t sz;
 struct verbs_context *vctx = verbs_get_ctx(ctx);

 if (!vctx || !(vctx->has_comp_mask & VERBS_CONTEXT_EXP))
  return ((void *)0);
 sz = *(size_t *)(((char *)vctx) - sizeof(size_t));
 return (struct verbs_context_exp *)(((char *)vctx) - sz);
}
static inline struct ibv_qp *
ibv_exp_create_qp(struct ibv_context *context, struct ibv_exp_qp_init_attr *qp_init_attr)
{
 struct verbs_context_exp *vctx;
 uint32_t mask = qp_init_attr->comp_mask;

 if (mask == IBV_EXP_QP_INIT_ATTR_PD)
  return ibv_create_qp(qp_init_attr->pd,
         (struct ibv_qp_init_attr *) qp_init_attr);

 vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, lib_exp_create_qp)) || !vctx->lib_exp_create_qp) ? ((void *)0) : vctx; });
 if (!vctx) {
  (*__errno_location ()) = 38;
  return ((void *)0);
 }
 if (qp_init_attr->comp_mask > (IBV_EXP_QP_INIT_ATTR_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, qp_init_attr->comp_mask, IBV_EXP_QP_INIT_ATTR_RESERVED - 1); qp_init_attr->comp_mask = 0; };

 return vctx->lib_exp_create_qp(context, qp_init_attr);
}

static inline int ibv_exp_query_device(struct ibv_context *context,
           struct ibv_exp_device_attr *attr)
{
 struct verbs_context_exp *vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, lib_exp_query_device)) || !vctx->lib_exp_query_device) ? ((void *)0) : vctx; })
                                  ;
 if (!vctx)
  return 38;

 if (attr->comp_mask > (IBV_EXP_DEVICE_ATTR_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, attr->comp_mask, IBV_EXP_DEVICE_ATTR_RESERVED - 1); attr->comp_mask = 0; };
 return vctx->lib_exp_query_device(context, attr);
}

static inline struct ibv_exp_dct *
ibv_exp_create_dct(struct ibv_context *context,
     struct ibv_exp_dct_init_attr *attr)
{
 struct verbs_context_exp *vctx;
 struct ibv_exp_dct *dct;

 vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, create_dct)) || !vctx->create_dct) ? ((void *)0) : vctx; });
 if (!vctx) {
  (*__errno_location ()) = 38;
  return ((void *)0);
 }

 pthread_mutex_lock(&context->mutex);
 if (attr->comp_mask > (IBV_EXP_DCT_INIT_ATTR_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, attr->comp_mask, IBV_EXP_DCT_INIT_ATTR_RESERVED - 1); attr->comp_mask = 0; };
 dct = vctx->create_dct(context, attr);
 if (dct)
  dct->context = context;

 pthread_mutex_unlock(&context->mutex);

 return dct;
}

static inline int ibv_exp_destroy_dct(struct ibv_exp_dct *dct)
{
 struct verbs_context_exp *vctx;
 struct ibv_context *context = dct->context;
 int err;

 vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, destroy_dct)) || !vctx->destroy_dct) ? ((void *)0) : vctx; });
 if (!vctx) {
  (*__errno_location ()) = 38;
  return (*__errno_location ());
 }

 pthread_mutex_lock(&context->mutex);
 err = vctx->destroy_dct(dct);
 pthread_mutex_unlock(&context->mutex);

 return err;
}

static inline int ibv_exp_query_dct(struct ibv_exp_dct *dct,
        struct ibv_exp_dct_attr *attr)
{
 struct verbs_context_exp *vctx;
 struct ibv_context *context = dct->context;
 int err;

 vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, query_dct)) || !vctx->query_dct) ? ((void *)0) : vctx; });
 if (!vctx) {
  (*__errno_location ()) = 38;
  return (*__errno_location ());
 }

 pthread_mutex_lock(&context->mutex);
 if (attr->comp_mask > (IBV_EXP_DCT_ATTR_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, attr->comp_mask, IBV_EXP_DCT_ATTR_RESERVED - 1); attr->comp_mask = 0; };
 err = vctx->query_dct(dct, attr);
 pthread_mutex_unlock(&context->mutex);

 return err;
}

static inline int ibv_exp_arm_dct(struct ibv_exp_dct *dct,
      struct ibv_exp_arm_attr *attr)
{
 struct verbs_context_exp *vctx;
 struct ibv_context *context = dct->context;
 int err;

 vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, lib_exp_arm_dct)) || !vctx->lib_exp_arm_dct) ? ((void *)0) : vctx; });
 if (!vctx) {
  (*__errno_location ()) = 38;
  return (*__errno_location ());
 }

 pthread_mutex_lock(&context->mutex);
 if (attr->comp_mask > (IBV_EXP_ARM_ATTR_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, attr->comp_mask, IBV_EXP_ARM_ATTR_RESERVED - 1); attr->comp_mask = 0; };
 err = vctx->lib_exp_arm_dct(dct, attr);
 pthread_mutex_unlock(&context->mutex);

 return err;
}

static inline int ibv_exp_query_port(struct ibv_context *context,
         uint8_t port_num,
         struct ibv_exp_port_attr *port_attr)
{
 struct verbs_context_exp *vctx;

 if (0 == port_attr->comp_mask)
  return ___ibv_query_port(context, port_num, &port_attr->port_attr)
                                ;

 if ((!port_attr->comp_mask & IBV_EXP_QUERY_PORT_ATTR_MASK1) ||
     (port_attr->comp_mask & ~IBV_EXP_QUERY_PORT_ATTR_MASKS) ||
     (port_attr->mask1 & ~IBV_EXP_QUERY_PORT_MASK)) {
  (*__errno_location ()) = 22;
  return -(*__errno_location ());
 }

 vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, lib_exp_query_port)) || !vctx->lib_exp_query_port) ? ((void *)0) : vctx; });

 if (!vctx) {

  if (port_attr->comp_mask == IBV_EXP_QUERY_PORT_ATTR_MASK1 &&
      !(port_attr->mask1 & ~IBV_EXP_QUERY_PORT_STD_MASK))
   return ___ibv_query_port(context, port_num, &port_attr->port_attr)
                                 ;

  (*__errno_location ()) = 38;
  return -(*__errno_location ());
 }
 if (port_attr->comp_mask > (IBV_EXP_QUERY_PORT_ATTR_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, port_attr->comp_mask, IBV_EXP_QUERY_PORT_ATTR_RESERVED - 1); port_attr->comp_mask = 0; };

 return vctx->lib_exp_query_port(context, port_num, port_attr);
}

static inline int ibv_exp_post_task(struct ibv_context *context,
        struct ibv_exp_task *task,
        struct ibv_exp_task **bad_task)
{
 struct verbs_context_exp *vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, lib_exp_post_task)) || !vctx->lib_exp_post_task) ? ((void *)0) : vctx; })
                               ;
 if (!vctx)
  return 38;

 if (task->comp_mask > (IBV_EXP_TASK_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, task->comp_mask, IBV_EXP_TASK_RESERVED - 1); task->comp_mask = 0; };

 return vctx->lib_exp_post_task(context, task, bad_task);
}

static inline int ibv_exp_query_values(struct ibv_context *context, int q_values,
           struct ibv_exp_values *values)
{
 struct verbs_context_exp *vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, drv_exp_query_values)) || !vctx->drv_exp_query_values) ? ((void *)0) : vctx; })
                                  ;
 if (!vctx) {
  (*__errno_location ()) = 38;
  return -(*__errno_location ());
 }
 if (values->comp_mask > (IBV_EXP_VALUES_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, values->comp_mask, IBV_EXP_VALUES_RESERVED - 1); values->comp_mask = 0; };

 return vctx->drv_exp_query_values(context, q_values, values);
}

static inline struct ibv_exp_flow *ibv_exp_create_flow(struct ibv_qp *qp,
             struct ibv_exp_flow_attr *flow)
{
 struct verbs_context_exp *vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(qp->context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, lib_exp_ibv_create_flow)) || !vctx->lib_exp_ibv_create_flow) ? ((void *)0) : vctx; })
                                     ;
 if (!vctx || !vctx->lib_exp_ibv_create_flow)
  return ((void *)0);

 if (flow->reserved != 0L) {
  fprintf(stderr, "%s:%d: flow->reserved must be 0\n", __FUNCTION__, 1272);
  flow->reserved = 0L;
 }

 return vctx->lib_exp_ibv_create_flow(qp, flow);
}

static inline int ibv_exp_destroy_flow(struct ibv_exp_flow *flow_id)
{
 struct verbs_context_exp *vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(flow_id->context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, lib_exp_ibv_destroy_flow)) || !vctx->lib_exp_ibv_destroy_flow) ? ((void *)0) : vctx; })
                                      ;
 if (!vctx || !vctx->lib_exp_ibv_destroy_flow)
  return -38;

 return vctx->lib_exp_ibv_destroy_flow(flow_id);
}

static inline int ibv_exp_poll_cq(struct ibv_cq *ibcq, int num_entries,
      struct ibv_exp_wc *wc, uint32_t wc_size)
{
 struct verbs_context_exp *vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(ibcq->context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, drv_exp_ibv_poll_cq)) || !vctx->drv_exp_ibv_poll_cq) ? ((void *)0) : vctx; })
                                 ;
 if (!vctx)
  return -38;

 return vctx->drv_exp_ibv_poll_cq(ibcq, num_entries, wc, wc_size);
}

static inline int ibv_exp_post_send(struct ibv_qp *qp,
        struct ibv_exp_send_wr *wr,
        struct ibv_exp_send_wr **bad_wr)
{
 struct verbs_context_exp *vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(qp->context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, drv_exp_post_send)) || !vctx->drv_exp_post_send) ? ((void *)0) : vctx; })
                               ;
 if (!vctx)
  return -38;

 return vctx->drv_exp_post_send(qp, wr, bad_wr);
}

static inline struct ibv_mr *ibv_exp_reg_shared_mr(struct ibv_exp_reg_shared_mr_in *mr_in)
{
 struct verbs_context_exp *vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(mr_in->pd->context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, lib_exp_ibv_reg_shared_mr)) || !vctx->lib_exp_ibv_reg_shared_mr) ? ((void *)0) : vctx; })
                                       ;
 if (!vctx) {
  (*__errno_location ()) = 38;
  return ((void *)0);
 }
 if (mr_in->comp_mask > (IBV_EXP_REG_SHARED_MR_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, mr_in->comp_mask, IBV_EXP_REG_SHARED_MR_RESERVED - 1); mr_in->comp_mask = 0; };

 return vctx->lib_exp_ibv_reg_shared_mr(mr_in);
}
static inline int ibv_exp_modify_cq(struct ibv_cq *cq,
        struct ibv_exp_cq_attr *cq_attr,
        int cq_attr_mask)
{
 struct verbs_context_exp *vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(cq->context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, lib_exp_modify_cq)) || !vctx->lib_exp_modify_cq) ? ((void *)0) : vctx; })
                               ;
 if (!vctx)
  return 38;

 if (cq_attr->comp_mask > (IBV_EXP_CQ_ATTR_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, cq_attr->comp_mask, IBV_EXP_CQ_ATTR_RESERVED - 1); cq_attr->comp_mask = 0; };

 return vctx->lib_exp_modify_cq(cq, cq_attr, cq_attr_mask);
}

static inline struct ibv_cq *ibv_exp_create_cq(struct ibv_context *context,
            int cqe,
            void *cq_context,
            struct ibv_comp_channel *channel,
            int comp_vector,
            struct ibv_exp_cq_init_attr *attr)
{
 struct verbs_context_exp *vctx;
 struct ibv_cq *cq;

 vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, exp_create_cq)) || !vctx->exp_create_cq) ? ((void *)0) : vctx; });
 if (!vctx) {
  (*__errno_location ()) = 38;
  return ((void *)0);
 }

 pthread_mutex_lock(&context->mutex);
 if (attr->comp_mask > (IBV_EXP_CQ_INIT_ATTR_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, attr->comp_mask, IBV_EXP_CQ_INIT_ATTR_RESERVED - 1); attr->comp_mask = 0; };
 cq = vctx->exp_create_cq(context, cqe, channel, comp_vector, attr);
 if (cq) {
  cq->context = context;
  cq->channel = channel;
  if (channel)
   ++channel->refcnt;
  cq->cq_context = cq_context;
  cq->comp_events_completed = 0;
  cq->async_events_completed = 0;
  pthread_mutex_init(&cq->mutex, ((void *)0));
  pthread_cond_init(&cq->cond, ((void *)0));
 }

 pthread_mutex_unlock(&context->mutex);

 return cq;
}

static inline int
ibv_exp_modify_qp(struct ibv_qp *qp, struct ibv_exp_qp_attr *attr, uint64_t exp_attr_mask)
{
 struct verbs_context_exp *vctx;

 vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(qp->context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, lib_exp_modify_qp)) || !vctx->lib_exp_modify_qp) ? ((void *)0) : vctx; });
 if (!vctx) {
  (*__errno_location ()) = 38;
  return (*__errno_location ());
 }
 if (attr->comp_mask > (IBV_EXP_QP_ATTR_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, attr->comp_mask, IBV_EXP_QP_ATTR_RESERVED - 1); attr->comp_mask = 0; };

 return vctx->lib_exp_modify_qp(qp, attr, exp_attr_mask);
}

static inline struct ibv_mr *ibv_exp_reg_mr(struct ibv_exp_reg_mr_in *in)
{
 struct verbs_context_exp *vctx;

 vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(in->pd->context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, lib_exp_reg_mr)) || !vctx->lib_exp_reg_mr) ? ((void *)0) : vctx; });
 if (!vctx) {
  (*__errno_location ()) = 38;
  return ((void *)0);
 }
 if (in->comp_mask > (IBV_EXP_REG_MR_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, in->comp_mask, IBV_EXP_REG_MR_RESERVED - 1); in->comp_mask = 0; };

 return vctx->lib_exp_reg_mr(in);
}

static inline int ibv_exp_bind_mw(struct ibv_exp_mw_bind *mw_bind)
{
 struct verbs_context_exp *vctx;

 vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(mw_bind->mw->context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, lib_exp_bind_mw)) || !vctx->lib_exp_bind_mw) ? ((void *)0) : vctx; });
 if (!vctx) {
  (*__errno_location ()) = 38;
  return (*__errno_location ());
 }
 if (mw_bind->comp_mask > (IBV_EXP_BIND_MW_RESERVED - 1)) { fprintf(stderr, "%s: resetting invalid comp_mask !!! (comp_mask = 0x%x valid_mask = 0x%x)\n", __FUNCTION__, mw_bind->comp_mask, IBV_EXP_BIND_MW_RESERVED - 1); mw_bind->comp_mask = 0; };

 return vctx->lib_exp_bind_mw(mw_bind);
}

typedef int (*drv_exp_post_send_func)(struct ibv_qp *qp,
     struct ibv_exp_send_wr *wr,
     struct ibv_exp_send_wr **bad_wr);
typedef int (*drv_post_send_func)(struct ibv_qp *qp, struct ibv_send_wr *wr,
    struct ibv_send_wr **bad_wr);
typedef int (*drv_exp_poll_cq_func)(struct ibv_cq *ibcq, int num_entries,
       struct ibv_exp_wc *wc, uint32_t wc_size);
typedef int (*drv_poll_cq_func)(struct ibv_cq *cq, int num_entries, struct ibv_wc *wc);
typedef int (*drv_post_recv_func)(struct ibv_qp *qp, struct ibv_recv_wr *wr,
    struct ibv_recv_wr **bad_wr);

static inline void *ibv_exp_get_provider_func(struct ibv_context *context,
      enum ibv_exp_func_name name)
{
 struct verbs_context_exp *vctx;

 switch (name) {
 case IBV_EXP_POST_SEND_FUNC:
  vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, drv_exp_post_send)) || !vctx->drv_exp_post_send) ? ((void *)0) : vctx; });
  if (!vctx)
   goto error;

  return (void *)vctx->drv_exp_post_send;

 case IBV_EXP_POLL_CQ_FUNC:
  vctx = ({ struct verbs_context_exp *vctx = verbs_get_exp_ctx(context); (!vctx || (vctx->sz < sizeof(*vctx) - __builtin_offsetof (struct verbs_context_exp, drv_exp_ibv_poll_cq)) || !vctx->drv_exp_ibv_poll_cq) ? ((void *)0) : vctx; });
  if (!vctx)
   goto error;

  return (void *)vctx->drv_exp_ibv_poll_cq;

 case IBV_POST_SEND_FUNC:
  if (!context->ops.post_send)
   goto error;

  return (void *)context->ops.post_send;

 case IBV_POLL_CQ_FUNC:
  if (!context->ops.poll_cq)
   goto error;

  return (void *)context->ops.poll_cq;

 case IBV_POST_RECV_FUNC:
  if (!context->ops.post_recv)
   goto error;

  return (void *)context->ops.post_recv;

 default:
  break;
 }

error:
 (*__errno_location ()) = 38;
 return ((void *)0);
}

