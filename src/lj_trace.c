/*
** Trace management.
** Copyright (C) 2005-2023 Mike Pall. See Copyright Notice in luajit.h
*/

#define lj_trace_c
#define LUA_CORE

#include <time.h>

#include "lj_obj.h"


#include "lj_gc.h"
#include "lj_err.h"
#include "lj_debug.h"
#include "lj_str.h"
#include "lj_frame.h"
#include "lj_state.h"
#include "lj_bc.h"
#include "lj_ir.h"
#include "lj_jit.h"
#include "lj_iropt.h"
#include "lj_mcode.h"
#include "lj_trace.h"
#include "lj_snap.h"
#include "lj_gdbjit.h"
#include "lj_record.h"
#include "lj_asm.h"
#include "lj_dispatch.h"
#include "lj_vm.h"
#include "lj_target.h"
#include "lj_prng.h"
#include "lj_auditlog.h"

/* -- Error handling ------------------------------------------------------ */

/* Synchronous abort with error message. */
void lj_trace_err(jit_State *J, TraceError e)
{
  setnilV(&J->errinfo);  /* No error info. */
  setintV(J->L->top++, (int32_t)e);
  lj_err_throw(J->L, LUA_ERRRUN);
}

/* Synchronous abort with error message and error info. */
void lj_trace_err_info(jit_State *J, TraceError e)
{
  setintV(J->L->top++, (int32_t)e);
  lj_err_throw(J->L, LUA_ERRRUN);
}

/* -- Hotcount decay ------------------------------------------------------ */

/* We reset all hotcounts every second. This is a rough way to establish a
** relation with elapsed time so that hotcounts provide a measure of frequency.
**
** The concrete goal is to ensure that the JIT will trace code that becomes hot
** over a short duration, but not code that becomes hot over, say, the course
** of an hour.
**
** The "one second" constant is certainly tunable.
** */

static void trace_clearsnapcounts(jit_State *J); /* Forward decl. */

static inline uint64_t gettime_ns (void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

/* Timestamp (ns) of last hotcount reset. */
static uint64_t hotcount_decay_ts;

/* Decay hotcounts every second. */
int hotcount_decay (jit_State *J)
{
  uint64_t ts = gettime_ns();
  int decay = (ts - hotcount_decay_ts) > 1000000000LL; /* 1s elapsed? */
  if (decay) {
    /* Reset hotcounts. */
    lj_dispatch_init_hotcount(J2G(J));
    trace_clearsnapcounts(J);
    hotcount_decay_ts = ts;
  }
  return decay;
}


/* -- Trace management ---------------------------------------------------- */

/* The current trace is first assembled in J->cur. The variable length
** arrays point to shared, growable buffers (J->irbuf etc.). When trace
** recording ends successfully, the current trace and its data structures
** are copied to a new (compact) GCtrace object.
*/

/* Find a free trace number. */
static TraceNo trace_findfree(jit_State *J)
{
  if (J->freetrace == 0)
    J->freetrace = 1;
  /* Search for a free slot. */
  for (; J->freetrace < TRACE_MAX; J->freetrace++)
    if (traceref(J, J->freetrace) == NULL)
      return J->freetrace++;
  /* No free slot in trace array. */
  return 0;
}

#define TRACE_APPENDVEC(field, szfield, tp) \
  T->field = (tp *)p; \
  memcpy(p, J->cur.field, J->cur.szfield*sizeof(tp)); \
  p += J->cur.szfield*sizeof(tp);

/* Allocate space for copy of T. */
GCtrace * lj_trace_alloc(lua_State *L, GCtrace *T)
{
  size_t sztr = ((sizeof(GCtrace)+7)&~7);
  size_t szins = (T->nins-T->nk)*sizeof(IRIns);
  size_t sz = sztr + szins +
	      T->nsnap*sizeof(SnapShot) +
	      T->nsnapmap*sizeof(SnapEntry);
  GCtrace *T2 = lj_mem_newt(L, (MSize)sz, GCtrace);
  char *p = (char *)T2 + sztr;
  T2->gct = ~LJ_TTRACE;
  T2->marked = 0;
  T2->traceno = 0;
  T2->ir = (IRIns *)p - T->nk;
  T2->nins = T->nins;
  T2->nk = T->nk;
  T2->nsnap = T->nsnap;
  T2->nsnapmap = T->nsnapmap;
  /* Set szirmcode into T2 allocated memory. May be unallocated in T.
  ** +2 extra spaces for the last instruction and the trace header at [0].
  */
  T2->nszirmcode = T->nins+2-REF_BIAS;
  T2->szirmcode = lj_mem_newt(L, T2->nszirmcode*sizeof(uint16_t), uint16_t);
  memset(T2->szirmcode, 0, T2->nszirmcode*sizeof(uint16_t));
  memcpy(p, T->ir + T->nk, szins);
  return T2;
}

/* Save current trace by copying and compacting it. */
static void trace_save(jit_State *J, GCtrace *T)
{
  size_t sztr = ((sizeof(GCtrace)+7)&~7);
  size_t szins = (J->cur.nins-J->cur.nk)*sizeof(IRIns);
  size_t nszirmcode = T->nszirmcode;
  uint16_t *szirmcode = T->szirmcode;
  char *p = (char *)T + sztr;
  memcpy(T, &J->cur, sizeof(GCtrace));
  T->parent = J->parent;
  T->exitno = J->exitno;
  setgcrefr(T->nextgc, J2G(J)->gc.root);
  setgcrefp(J2G(J)->gc.root, T);
  newwhite(J2G(J), T);
  T->gct = ~LJ_TTRACE;
  T->ir = (IRIns *)p - J->cur.nk;  /* The IR has already been copied above. */
  p += szins;
  TRACE_APPENDVEC(snap, nsnap, SnapShot)
  TRACE_APPENDVEC(snapmap, nsnapmap, SnapEntry)
  /* Set szirmcode into T2 allocated memory. May be unallocated in T. */
  T->nszirmcode = nszirmcode;
  T->szirmcode = szirmcode;
  J->cur.traceno = 0;
  J->curfinal = NULL;
  setgcrefp(J->trace[T->traceno], T);
  lj_gc_barriertrace(J2G(J), T->traceno);
  lj_gdbjit_addtrace(J, T);
  lj_ctype_log(J->L);
  lj_auditlog_trace_stop(J, T);
}

void lj_trace_free(global_State *g, GCtrace *T)
{
  jit_State *J = G2J(g);
  if (T->traceno) {
    lj_gdbjit_deltrace(J, T);
    setgcrefnull(J->trace[T->traceno]);
  }
  lj_mem_free(g, T->szirmcode, T->nszirmcode*sizeof(uint16_t));
  lj_mem_free(g, T,
    ((sizeof(GCtrace)+7)&~7) + (T->nins-T->nk)*sizeof(IRIns) +
    T->nsnap*sizeof(SnapShot) + T->nsnapmap*sizeof(SnapEntry));
}

/* Re-enable compiling a prototype by unpatching any modified bytecode. */
void lj_trace_reenableproto(GCproto *pt)
{
  if ((pt->flags & PROTO_ILOOP)) {
    BCIns *bc = proto_bc(pt);
    BCPos i, sizebc = pt->sizebc;
    pt->flags &= ~PROTO_ILOOP;
    if (bc_op(bc[0]) == BC_IFUNCF)
      setbc_op(&bc[0], BC_FUNCF);
    for (i = 1; i < sizebc; i++) {
      BCOp op = bc_op(bc[i]);
      if (op == BC_IFORL || op == BC_IITERL || op == BC_ILOOP)
	setbc_op(&bc[i], (int)op+(int)BC_LOOP-(int)BC_ILOOP);
    }
  }
}

/* Unpatch the bytecode modified by a root trace. */
static void trace_unpatch(jit_State *J, GCtrace *T)
{
  BCOp op = bc_op(T->startins);
  BCIns *pc = mref(T->startpc, BCIns);
  UNUSED(J);
  if (op == BC_JMP)
    return;  /* No need to unpatch branches in parent traces (yet). */
  switch (bc_op(*pc)) {
  case BC_JFORL:
    lj_assertJ(traceref(J, bc_d(*pc)) == T, "JFORL references other trace");
    *pc = T->startins;
    pc += bc_j(T->startins);
    lj_assertJ(bc_op(*pc) == BC_JFORI, "FORL does not point to JFORI");
    setbc_op(pc, BC_FORI);
    break;
  case BC_JITERL:
  case BC_JLOOP:
    lj_assertJ(op == BC_ITERL || op == BC_ITERN || op == BC_LOOP ||
	       bc_isret(op), "bad original bytecode %d", op);
    *pc = T->startins;
    break;
  case BC_JMP:
    lj_assertJ(op == BC_ITERL, "bad original bytecode %d", op);
    pc += bc_j(*pc)+2;
    if (bc_op(*pc) == BC_JITERL) {
      lj_assertJ(traceref(J, bc_d(*pc)) == T, "JITERL references other trace");
      *pc = T->startins;
    }
    break;
  case BC_JFUNCF:
    lj_assertJ(op == BC_FUNCF, "bad original bytecode %d", op);
    *pc = T->startins;
    break;
  default:  /* Already unpatched. */
    break;
  }
}

/* Flush a root trace. */
static void trace_flushroot(jit_State *J, GCtrace *T)
{
  GCproto *pt = &gcref(T->startpt)->pt;
  lj_assertJ(T->root == 0, "not a root trace");
  lj_assertJ(pt != NULL, "trace has no prototype");
  /* First unpatch any modified bytecode. */
  trace_unpatch(J, T);
  /* Unlink root trace from chain anchored in prototype. */
  if (pt->trace == T->traceno) {  /* Trace is first in chain. Easy. */
    pt->trace = T->nextroot;
  } else if (pt->trace) {  /* Otherwise search in chain of root traces. */
    GCtrace *T2 = traceref(J, pt->trace);
    if (T2) {
      for (; T2->nextroot; T2 = traceref(J, T2->nextroot))
	if (T2->nextroot == T->traceno) {
	  T2->nextroot = T->nextroot;  /* Unlink from chain. */
	  break;
	}
    }
  }
}

/* Flush a trace. Only root traces are considered. */
void lj_trace_flush(jit_State *J, TraceNo traceno)
{
  if (traceno > 0 && traceno < TRACE_MAX) {
    GCtrace *T = traceref(J, traceno);
    if (T && T->root == 0)
      trace_flushroot(J, T);
  }
}

/* Flush all traces associated with a prototype. */
void lj_trace_flushproto(global_State *g, GCproto *pt)
{
  while (pt->trace != 0)
    trace_flushroot(G2J(g), traceref(G2J(g), pt->trace));
}

/* Flush all traces. */
int lj_trace_flushall(lua_State *L)
{
  jit_State *J = L2J(L);
  global_State *g = G(L);
  ptrdiff_t i;
  if ((J2G(J)->hookmask & HOOK_GC))
    return 1;
  lj_auditlog_trace_flushall(J);
  if (J->trace) {
    for (i = (ptrdiff_t)TRACE_MAX-1; i > 0; i--) {
      GCtrace *T = traceref(J, i);
      if (T) {
        if (T->root == 0)
          trace_flushroot(J, T);
        lj_gdbjit_deltrace(J, T);
        T->traceno = T->link = 0;  /* Blacklist the link for cont_stitch. */
        setgcrefnull(J->trace[i]);
      }
    }
  }
  J->cur.traceno = 0;
  J->ntraces = 0;
  J->freetrace = 0;
  g->lasttrace = 0;
  /* Unpatch blacklisted byte codes. */
  GCRef *p = &(G(L)->gc.root);
  GCobj *o;
  while ((o = gcref(*p)) != NULL) {
    if (o->gch.gct == ~LJ_TPROTO) {
      lj_trace_reenableproto(gco2pt(o));
    }
    p = &o->gch.nextgc;
  }
  /* Clear penalty cache. */
  memset(J->penalty, 0, sizeof(J->penalty));
  /* Reset hotcounts. */
  lj_dispatch_init_hotcount(J2G(J));
  /* Initialize hotcount decay timestamp. */
  hotcount_decay_ts = gettime_ns();
  /* Free the whole machine code and invalidate all exit stub groups. */
  lj_mcode_free(J);
  memset(J->exitstubgroup, 0, sizeof(J->exitstubgroup));
  return 0;
}

/* Initialize JIT compiler state. */
void lj_trace_initstate(global_State *g)
{
  jit_State *J = G2J(g);
  TValue *tv;

  /* Initialize aligned SIMD constants. */
  tv = LJ_KSIMD(J, LJ_KSIMD_ABS);
  tv[0].u64 = U64x(7fffffff,ffffffff);
  tv[1].u64 = U64x(7fffffff,ffffffff);
  tv = LJ_KSIMD(J, LJ_KSIMD_NEG);
  tv[0].u64 = U64x(80000000,00000000);
  tv[1].u64 = U64x(80000000,00000000);

  /* Initialize 32/64 bit constants. */
  J->k64[LJ_K64_TOBIT].u64 = U64x(43380000,00000000);
  J->k64[LJ_K64_2P64].u64 = U64x(43f00000,00000000);
  J->k32[LJ_K32_M2P64_31] = 0xdf800000;
  J->k64[LJ_K64_M2P64].u64 = U64x(c3f00000,00000000);
}

/* Free everything associated with the JIT compiler state. */
void lj_trace_freestate(global_State *g)
{
  jit_State *J = G2J(g);
#ifdef LUA_USE_ASSERT
  {  /* This assumes all traces have already been freed. */
    ptrdiff_t i;
    for (i = 1; i < (ptrdiff_t)TRACE_MAX-1; i++)
      lj_assertG(i == (ptrdiff_t)J->cur.traceno || traceref(J, i) == NULL,
		 "trace still allocated");
  }
#endif
  lj_mcode_free(J);
}

/* Clear all trace snap counts (side-exit hot counters). */
static void trace_clearsnapcounts(jit_State *J)
{
  int i, s;
  GCtrace *t;
  /* Clear hotcounts for all snapshots of all traces. */
  for (i = 1; i < TRACE_MAX; i++) {
    t = traceref(J, i);
    if (t != NULL)
      for (s = 0; s < t->nsnap; s++)
        if (t->snap[s].count != SNAPCOUNT_DONE)
          t->snap[s].count = 0;
  }
}

/* -- Penalties and blacklisting ------------------------------------------ */

/* Blacklist a bytecode instruction. */
static void blacklist_pc(GCproto *pt, BCIns *pc)
{
  if (bc_op(*pc) == BC_ITERN) {
    setbc_op(pc, BC_ITERC);
    setbc_op(pc+1+bc_j(pc[1]), BC_JMP);
  } else {
    setbc_op(pc, (int)bc_op(*pc)+(int)BC_ILOOP-(int)BC_LOOP);
    pt->flags |= PROTO_ILOOP;
  }
}

/* Penalize a bytecode instruction. Return true when blacklisted. */
static int penalty_pc(jit_State *J, GCproto *pt, BCIns *pc, TraceError e)
{
  uint32_t i, val = PENALTY_MIN;
  for (i = 0; i < PENALTY_SLOTS; i++)
    if (mref(J->penalty[i].pc, const BCIns) == pc) {  /* Cache slot found? */
      /* First try to bump its hotcount several times. */
      val = ((uint32_t)J->penalty[i].val << 1) +
	    (lj_prng_u64(&J2G(J)->prng) & ((1u<<PENALTY_RNDBITS)-1));
      if (val > PENALTY_MAX) {
	blacklist_pc(pt, pc);  /* Blacklist it, if that didn't help. */
	return 1;
      }
      goto setpenalty;
    }
  /* Assign a new penalty cache slot. */
  i = J->penaltyslot;
  J->penaltyslot = (J->penaltyslot + 1) & (PENALTY_SLOTS-1);
  setmref(J->penalty[i].pc, pc);
setpenalty:
  J->penalty[i].val = val;
  J->penalty[i].reason = e;
  hotcount_set(J2GG(J), pc+1, val);
  return 0;
}

/* Check if this is the last attempt to compile a side trace.
** (If so the next attempt will just record a fallback to the interpreter.)
**/
static int last_try(jit_State *J)
{
  GCtrace *parent = traceref(J, J->parent);
  int count = parent->snap[J->exitno].count;
  return count+1 >= J->param[JIT_P_hotexit] + J->param[JIT_P_tryside];
}


/* -- Trace compiler state machine ---------------------------------------- */

/* Start tracing. */
static void trace_start(jit_State *J)
{
  TraceNo traceno;

  if ((J->pt->flags & PROTO_NOJIT)) {  /* JIT disabled for this proto? */
    if (J->parent == 0 && J->exitno == 0 && bc_op(*J->pc) != BC_ITERN) {
      /* Lazy bytecode patching to disable hotcount events. */
      lj_assertJ(bc_op(*J->pc) == BC_FORL || bc_op(*J->pc) == BC_ITERL ||
		 bc_op(*J->pc) == BC_LOOP || bc_op(*J->pc) == BC_FUNCF,
		 "bad hot bytecode %d", bc_op(*J->pc));
      setbc_op(J->pc, (int)bc_op(*J->pc)+(int)BC_ILOOP-(int)BC_LOOP);
      J->pt->flags |= PROTO_ILOOP;
    }
    J->state = LJ_TRACE_IDLE;  /* Silently ignored. */
    return;
  }

  /* Ensuring forward progress for BC_ITERN can trigger hotcount again. */
  if (!J->parent && bc_op(*J->pc) == BC_JLOOP) {  /* Already compiled. */
    J->state = LJ_TRACE_IDLE;  /* Silently ignored. */
    return;
  }

  /* Get a new trace number. */
  traceno = trace_findfree(J);
  if (traceno == 0 || J->ntraces >= J->param[JIT_P_maxtrace]) {  /* No free trace? */
    lj_assertJ((J2G(J)->hookmask & HOOK_GC) == 0,
	       "recorder called from GC hook");
    lj_trace_flushall(J->L);
    J->state = LJ_TRACE_IDLE;  /* Silently ignored. */
    return;
  }
  setgcrefp(J->trace[traceno], &J->cur);

  /* Setup enough of the current trace to be able to send the vmevent. 
     XXX Still needed with vmevent removed? -lukego */
  memset(&J->cur, 0, sizeof(GCtrace));
  J->cur.traceno = traceno;
  J->cur.nins = J->cur.nk = REF_BASE;
  J->cur.ir = J->irbuf;
  J->cur.snap = J->snapbuf;
  J->cur.snapmap = J->snapmapbuf;
  J->cur.nszirmcode = 0;	/* Only present in assembled trace. */
  J->cur.szirmcode = NULL;
  J->mergesnap = 0;
  J->needsnap = 0;
  J->bcskip = 0;
  J->guardemit.irt = 0;
  J->postproc = LJ_POST_NONE;
  lj_resetsplit(J);
  J->retryrec = 0;
  J->ktrace = 0;
  setgcref(J->cur.startpt, obj2gco(J->pt));

  lj_record_setup(J);
}

/* Stop tracing. */
static void trace_stop(jit_State *J)
{
  BCIns *pc = mref(J->cur.startpc, BCIns);
  BCOp op = bc_op(J->cur.startins);
  GCproto *pt = &gcref(J->cur.startpt)->pt;
  TraceNo traceno = J->cur.traceno;
  GCtrace *T = J->curfinal;
  int i;

  switch (op) {
  case BC_FORL:
    setbc_op(pc+bc_j(J->cur.startins), BC_JFORI);  /* Patch FORI, too. */
    /* fallthrough */
  case BC_LOOP:
  case BC_ITERL:
  case BC_FUNCF:
    /* Patch bytecode of starting instruction in root trace. */
    setbc_op(pc, (int)op+(int)BC_JLOOP-(int)BC_LOOP);
    setbc_d(pc, traceno);
  addroot:
    /* Add to root trace chain in prototype. */
    J->cur.nextroot = pt->trace;
    pt->trace = (TraceNo1)traceno;
    break;
  case BC_ITERN:
  case BC_RET:
  case BC_RET0:
  case BC_RET1:
    *pc = BCINS_AD(BC_JLOOP, J->cur.snap[0].nslots, traceno);
    goto addroot;
  case BC_JMP:
    /* Patch exit branch in parent to side trace entry. */
    lj_assertJ(J->parent != 0 && J->cur.root != 0, "not a side trace");
    lj_asm_patchexit(J, traceref(J, J->parent), J->exitno, J->cur.mcode);
    /* Avoid compiling a side trace twice (stack resizing uses parent exit). */
    {
      SnapShot *snap = &traceref(J, J->parent)->snap[J->exitno];
      snap->count = SNAPCOUNT_DONE;
      if (J->cur.topslot > snap->topslot) snap->topslot = J->cur.topslot;
    }
    /* Add to side trace chain in root trace. */
    {
      GCtrace *root = traceref(J, J->cur.root);
      root->nchild++;
      J->cur.nextside = root->nextside;
      root->nextside = (TraceNo1)traceno;
    }
    break;
  case BC_CALLM:
  case BC_CALL:
  case BC_ITERC:
    /* Trace stitching: patch link of previous trace. */
    traceref(J, J->exitno)->link = traceno;
    break;
  default:
    lj_assertJ(0, "bad stop bytecode %d", op);
    break;
  }

  /* Commit new mcode only after all patching is done. */
  lj_mcode_commit(J, J->cur.mcode);
  J->postproc = LJ_POST_NONE;
  trace_save(J, T);
  J->ntraces++;

  /* Clear any penalty after successful recording. */
  for (i = 0; i < PENALTY_SLOTS; i++)
    if (mref(J->penalty[i].pc, const BCIns) == pc)
      J->penalty[i].val = PENALTY_MIN;
}

/* Start a new root trace for down-recursion. */
static int trace_downrec(jit_State *J)
{
  /* Restart recording at the return instruction. */
  lj_assertJ(J->pt != NULL, "no active prototype");
  lj_assertJ(bc_isret(bc_op(*J->pc)), "not at a return bytecode");
  if (bc_op(*J->pc) == BC_RETM)
    return 0;  /* NYI: down-recursion with RETM. */
  J->parent = 0;
  J->exitno = 0;
  J->state = LJ_TRACE_RECORD;
  trace_start(J);
  return 1;
}

/* Abort tracing. */
static int trace_abort(jit_State *J)
{
  lua_State *L = J->L;
  TraceError e = LJ_TRERR_RECERR;
  TraceNo traceno;

  J->postproc = LJ_POST_NONE;
  lj_mcode_abort(J);
  if (J->curfinal) {
    lj_trace_free(J2G(J), J->curfinal);
    J->curfinal = NULL;
  }
  if (tvisnumber(L->top-1))
    e = (TraceError)numberVint(L->top-1);
  if (e == LJ_TRERR_MCODELM) {
    L->top--;  /* Remove error object */
    J->state = LJ_TRACE_ASM;
    return 1;  /* Retry ASM with new MCode area. */
  }

  /* Penalize or blacklist starting bytecode instruction. */
  if (J->parent == 0 && !bc_isret(bc_op(J->cur.startins))) {
    if (J->exitno == 0) {
      BCIns *startpc = mref(J->cur.startpc, BCIns);
      if (e == LJ_TRERR_RETRY)
	hotcount_set(J2GG(J), startpc+1, 1);  /* Immediate retry. */
      else
	J->final = penalty_pc(J, &gcref(J->cur.startpt)->pt, startpc, e);
    } else {
      traceref(J, J->exitno)->link = J->exitno;  /* Self-link is blacklisted. */
    }
  }

  /* Is this the last attempt at a side trace? */
  if (J->parent && last_try(J)) J->final = 1;

  lj_ctype_log(J->L);
  lj_auditlog_trace_abort(J, e);

  /* Is there anything to abort? */
  traceno = J->cur.traceno;
  if (traceno) {
    J->cur.link = 0;
    J->cur.linktype = LJ_TRLINK_NONE;
    /* Drop aborted trace after the vmevent (which may still access it).
       XXX Rethink now that vmevent is removed? -lukego */
    setgcrefnull(J->trace[traceno]);
    if (traceno < J->freetrace)
      J->freetrace = traceno;
    J->cur.traceno = 0;
  }
  L->top--;  /* Remove error object */
  if (e == LJ_TRERR_DOWNREC)
    return trace_downrec(J);
  else if (e == LJ_TRERR_MCODEAL)
    lj_trace_flushall(L);
  return 0;
}

/* Perform pending re-patch of a bytecode instruction. */
static LJ_AINLINE void trace_pendpatch(jit_State *J, int force)
{
  if (LJ_UNLIKELY(J->patchpc)) {
    if (force || J->bcskip == 0) {
      *J->patchpc = J->patchins;
      J->patchpc = NULL;
    } else {
      J->bcskip = 0;
    }
  }
}

/* State machine for the trace compiler. Protected callback. */
static TValue *trace_state(lua_State *L, lua_CFunction dummy, void *ud)
{
  jit_State *J = (jit_State *)ud;
  UNUSED(dummy);
  do {
  retry:
    switch (J->state) {
    case LJ_TRACE_START:
      J->state = LJ_TRACE_RECORD;  /* trace_start() may change state. */
      trace_start(J);
      lj_dispatch_update(J2G(J));
      if (J->state != LJ_TRACE_RECORD_1ST)
	break;
      /* fallthrough */

    case LJ_TRACE_RECORD_1ST:
      J->state = LJ_TRACE_RECORD;
      /* fallthrough */
    case LJ_TRACE_RECORD:
      trace_pendpatch(J, 0);
      setvmstate(J2G(J), RECORD);
      lj_record_ins(J);
      break;

    case LJ_TRACE_END:
      trace_pendpatch(J, 1);
      J->loopref = 0;
      if ((J->flags & JIT_F_OPT_LOOP) &&
	  J->cur.link == J->cur.traceno && J->framedepth + J->retdepth == 0) {
	setvmstate(J2G(J), OPT);
	lj_opt_dce(J);
	if (lj_opt_loop(J)) {  /* Loop optimization failed? */
	  J->cur.link = 0;
	  J->cur.linktype = LJ_TRLINK_NONE;
	  J->loopref = J->cur.nins;
	  J->state = LJ_TRACE_RECORD;  /* Try to continue recording. */
	  break;
	}
	J->loopref = J->chain[IR_LOOP];  /* Needed by assembler. */
      }
      lj_opt_split(J);
      lj_opt_sink(J);
      if (!J->loopref) J->cur.snap[J->cur.nsnap-1].count = SNAPCOUNT_DONE;
      J->state = LJ_TRACE_ASM;
      break;

    case LJ_TRACE_ASM:
      setvmstate(J2G(J), ASM);
      lj_asm_trace(J, &J->cur);
      trace_stop(J);
      setvmstate(J2G(J), INTERP);
      J->state = LJ_TRACE_IDLE;
      lj_dispatch_update(J2G(J));
      return NULL;

    default:  /* Trace aborted asynchronously. */
      setintV(L->top++, (int32_t)LJ_TRERR_RECERR);
      /* fallthrough */
    case LJ_TRACE_ERR:
      trace_pendpatch(J, 1);
      if (trace_abort(J))
	goto retry;
      setvmstate(J2G(J), INTERP);
      J->state = LJ_TRACE_IDLE;
      lj_dispatch_update(J2G(J));
      return NULL;
    }
  } while (J->state > LJ_TRACE_RECORD);
  return NULL;
}

/* -- Event handling ------------------------------------------------------ */

/* A bytecode instruction is about to be executed. Record it. */
void lj_trace_ins(jit_State *J, const BCIns *pc)
{
  /* Note: J->L must already be set. pc is the true bytecode PC here. */
  J->pc = pc;
  J->fn = curr_func(J->L);
  J->pt = isluafunc(J->fn) ? funcproto(J->fn) : NULL;
  while (lj_vm_cpcall(J->L, NULL, (void *)J, trace_state) != 0)
    J->state = LJ_TRACE_ERR;
}

/* A hotcount triggered. Start recording a root trace. */
void lj_trace_hot(jit_State *J, const BCIns *pc)
{
  /* Note: pc is the interpreter bytecode PC here. It's offset by 1. */
  if (hotcount_decay(J))
    /* Check for hotcount decay, do nothing if hotcounts have decayed. */
    return;
  ERRNO_SAVE
  /* Reset hotcount. */
  hotcount_set(J2GG(J), pc, J->param[JIT_P_hotloop]*HOTCOUNT_LOOP);
  /* Only start a new trace if not recording or inside __gc call. */
  if (J->state == LJ_TRACE_IDLE && !(J2G(J)->hookmask & HOOK_GC)) {
    J->parent = 0;  /* Root trace. */
    J->exitno = 0;
    J->state = LJ_TRACE_START;
    lj_trace_ins(J, pc-1);
  }
  ERRNO_RESTORE
}

/* Check for a hot side exit. If yes, start recording a side trace. */
static void trace_hotside(jit_State *J, const BCIns *pc)
{
  if (hotcount_decay(J))
    /* Check for hotcount decay, do nothing if hotcounts have decayed. */
    return;
  SnapShot *snap = &traceref(J, J->parent)->snap[J->exitno];
  if (!(J2G(J)->hookmask & HOOK_GC) &&
      isluafunc(curr_func(J->L)) &&
      snap->count != SNAPCOUNT_DONE &&
      ++snap->count >= J->param[JIT_P_hotexit]) {
    lj_assertJ(J->state == LJ_TRACE_IDLE, "hot side exit while recording");
    /* J->parent is non-zero for a side trace. */
    J->state = LJ_TRACE_START;
    lj_trace_ins(J, pc);
  }
}

/* Stitch a new trace to the previous trace. */
void lj_trace_stitch(jit_State *J, const BCIns *pc)
{
  /* Only start a new trace if not recording or inside __gc call. */
  if (J->state == LJ_TRACE_IDLE && !(J2G(J)->hookmask & HOOK_GC)) {
    J->parent = 0;  /* Have to treat it like a root trace. */
    /* J->exitno is set to the invoking trace. */
    J->state = LJ_TRACE_START;
    lj_trace_ins(J, pc);
  }
}


/* Tiny struct to pass data to protected call. */
typedef struct ExitDataCP {
  jit_State *J;
  void *exptr;		/* Pointer to exit state. */
  const BCIns *pc;	/* Restart interpreter at this PC. */
} ExitDataCP;

/* Need to protect lj_snap_restore because it may throw. */
static TValue *trace_exit_cp(lua_State *L, lua_CFunction dummy, void *ud)
{
  ExitDataCP *exd = (ExitDataCP *)ud;
  /* Always catch error here and don't call error function. */
  cframe_errfunc(L->cframe) = 0;
  cframe_nres(L->cframe) = -2*LUAI_MAXSTACK*(int)sizeof(TValue);
  exd->pc = lj_snap_restore(exd->J, exd->exptr);
  UNUSED(dummy);
  return NULL;
}

/* A trace exited. Restore interpreter state. */
int lj_trace_exit(jit_State *J, void *exptr)
{
  ERRNO_SAVE
  lua_State *L = J->L;
  ExitDataCP exd;
  int errcode, exitcode = J->exitcode;
  TValue exiterr;
  const BCIns *pc, *retpc;
  void *cf;
  GCtrace *T;

  setnilV(&exiterr);
  if (exitcode) {  /* Trace unwound with error code. */
    J->exitcode = 0;
    copyTV(L, &exiterr, L->top-1);
  }

  T = traceref(J, J->parent); UNUSED(T);
#ifdef EXITSTATE_CHECKEXIT
  if (J->exitno == T->nsnap) {  /* Treat stack check like a parent exit. */
    lj_assertJ(T->root != 0, "stack check in root trace");
    J->exitno = T->ir[REF_BASE].op2;
    J->parent = T->ir[REF_BASE].op1;
    T = traceref(J, J->parent);
  }
#endif
  lj_assertJ(T != NULL && J->exitno < T->nsnap, "bad trace or exit number");
  exd.J = J;
  exd.exptr = exptr;
  errcode = lj_vm_cpcall(L, NULL, &exd, trace_exit_cp);
  if (errcode)
    return -errcode;  /* Return negated error code. */

  if (exitcode) copyTV(L, L->top++, &exiterr);  /* Anchor the error object. */

  pc = exd.pc;
  cf = cframe_raw(L->cframe);
  setcframe_pc(cf, pc);
  if (exitcode) {
    return -exitcode;
  } else if (G(L)->gc.state == GCSatomic || G(L)->gc.state == GCSfinalize) {
    if (!(G(L)->hookmask & HOOK_GC))
      lj_gc_step(L);  /* Exited because of GC: drive GC forward. */
  } else if ((J->flags & JIT_F_ON)) {
    trace_hotside(J, pc);
  }
  /* Return MULTRES or 0 or -17. */
  ERRNO_RESTORE
  switch (bc_op(*pc)) {
  case BC_CALLM: case BC_CALLMT:
    return (int)((BCReg)(L->top - L->base) - bc_a(*pc) - bc_c(*pc) - LJ_FR2);
  case BC_RETM:
    return (int)((BCReg)(L->top - L->base) + 1 - bc_a(*pc) - bc_d(*pc));
  case BC_TSETM:
    return (int)((BCReg)(L->top - L->base) + 1 - bc_a(*pc));
  case BC_JLOOP:
    retpc = &traceref(J, bc_d(*pc))->startins;
    if (bc_isret(bc_op(*retpc)) || bc_op(*retpc) == BC_ITERN) {
      /* Dispatch to original ins to ensure forward progress. */
      if (J->state != LJ_TRACE_RECORD) return -17;
      /* Unpatch bytecode when recording. */
      J->patchins = *pc;
      J->patchpc = (BCIns *)pc;
      *J->patchpc = *retpc;
      J->bcskip = 1;
    }
    return 0;
  default:
    if (bc_op(*pc) >= BC_FUNCF)
      return (int)((BCReg)(L->top - L->base) + 1);
    return 0;
  }
}

